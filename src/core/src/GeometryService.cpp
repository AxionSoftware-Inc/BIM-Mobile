#include "tbe/core/GeometryService.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

#if TBE_HAS_OCCT
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepGProp.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRep_Tool.hxx>
#include <GProp_GProps.hxx>
#include <Poly_Triangulation.hxx>
#include <TopExp_Explorer.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>
#include <TopLoc_Location.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>
#endif

namespace tbe::core {

namespace {

constexpr auto epsilon = 1.0e-9;

double wall_length(const Line2& axis) {
    const auto dx = axis.end.x - axis.start.x;
    const auto dy = axis.end.y - axis.start.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

double polygon_signed_area(const std::vector<Point2>& polygon) {
    auto value = 0.0;
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto& current = polygon[index];
        const auto& next = polygon[(index + 1) % polygon.size()];
        value += (current.x * next.y) - (next.x * current.y);
    }
    return value / 2.0;
}

Point2 add(Point2 left, Point2 right) {
    return Point2{.x = left.x + right.x, .y = left.y + right.y};
}

Point2 scale(Point2 value, double factor) {
    return Point2{.x = value.x * factor, .y = value.y * factor};
}

Point2 perpendicular_left(Point2 direction) {
    return Point2{.x = -direction.y, .y = direction.x};
}

MeshBuffer extrude_polygon_mesh(const std::vector<Point2>& polygon, double thickness, double elevation_offset) {
    MeshBuffer mesh;
    const auto vertex_count = polygon.size();
    if (vertex_count < 3 || thickness <= 0.0) {
        return mesh;
    }

    mesh.vertices.reserve(vertex_count * 2);
    mesh.indices.reserve((vertex_count - 2) * 6 + vertex_count * 6);
    for (const auto& point : polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = elevation_offset});
    }
    for (const auto& point : polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = elevation_offset + thickness});
    }
    for (std::uint32_t index = 1; index + 1 < vertex_count; ++index) {
        mesh.indices.push_back(0);
        mesh.indices.push_back(index);
        mesh.indices.push_back(index + 1);
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + index + 1));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + index));
    }
    for (std::uint32_t index = 0; index < vertex_count; ++index) {
        const auto next = (index + 1) % static_cast<std::uint32_t>(vertex_count);
        mesh.indices.push_back(index);
        mesh.indices.push_back(next);
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + next));
        mesh.indices.push_back(index);
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + next));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + index));
    }
    return mesh;
}

std::vector<Point2> rectangle_polygon(Point2 center, double width, double depth) {
    const auto half_width = width / 2.0;
    const auto half_depth = depth / 2.0;
    return {
        Point2{.x = center.x - half_width, .y = center.y - half_depth},
        Point2{.x = center.x + half_width, .y = center.y - half_depth},
        Point2{.x = center.x + half_width, .y = center.y + half_depth},
        Point2{.x = center.x - half_width, .y = center.y + half_depth},
    };
}

MeshBuffer column_mesh(Point2 center, double width, double depth, double height) {
    return extrude_polygon_mesh(rectangle_polygon(center, width, depth), height, 0.0);
}

MeshBuffer beam_mesh(Point2 start, Point2 end, double width, double height) {
    const auto beam_length = wall_length(Line2{.start = start, .end = end});
    if (beam_length <= epsilon || width <= 0.0 || height <= 0.0) {
        return {};
    }
    const auto direction = Point2{
        .x = (end.x - start.x) / beam_length,
        .y = (end.y - start.y) / beam_length,
    };
    const auto normal = scale(perpendicular_left(direction), width / 2.0);
    return extrude_polygon_mesh({
        add(start, normal),
        add(end, normal),
        add(end, scale(normal, -1.0)),
        add(start, scale(normal, -1.0)),
    }, height, 0.0);
}

MeshBuffer stair_mesh(const StairData& stair) {
    if (stair.width_meters <= 0.0 || stair.total_run_meters <= 0.0 || stair.total_rise_meters <= 0.0) {
        return {};
    }
    const auto direction_length = std::sqrt((stair.direction.x * stair.direction.x) + (stair.direction.y * stair.direction.y));
    if (direction_length <= epsilon) {
        return {};
    }
    const auto unit = Point2{.x = stair.direction.x / direction_length, .y = stair.direction.y / direction_length};
    const auto normal = scale(perpendicular_left(unit), stair.width_meters / 2.0);
    const auto run = scale(unit, stair.total_run_meters);
    return extrude_polygon_mesh({
        add(stair.start, normal),
        add(add(stair.start, run), normal),
        add(add(stair.start, run), scale(normal, -1.0)),
        add(stair.start, scale(normal, -1.0)),
    }, stair.total_rise_meters, 0.0);
}

Point2 subtract(Point2 left, Point2 right) {
    return Point2{.x = left.x - right.x, .y = left.y - right.y};
}

double dot(Point2 left, Point2 right) {
    return (left.x * right.x) + (left.y * right.y);
}

double cross(Point2 left, Point2 right) {
    return (left.x * right.y) - (left.y * right.x);
}

Point2 unit_direction(const Line2& axis) {
    const auto length = wall_length(axis);
    if (length <= epsilon) {
        throw std::invalid_argument("wall axis length must be positive");
    }

    return Point2{
        .x = (axis.end.x - axis.start.x) / length,
        .y = (axis.end.y - axis.start.y) / length,
    };
}

Point2 direction_away_from(Point2 point, Line2 axis) {
    const auto start_distance = wall_length(Line2{.start = point, .end = axis.start});
    const auto end_distance = wall_length(Line2{.start = point, .end = axis.end});
    const auto away = start_distance < end_distance
        ? subtract(axis.end, axis.start)
        : subtract(axis.start, axis.end);
    const auto length = std::sqrt((away.x * away.x) + (away.y * away.y));
    if (length <= epsilon) {
        return Point2{};
    }

    return Point2{.x = away.x / length, .y = away.y / length};
}

double local_x(Point2 point, const Line2& axis) {
    const auto direction = unit_direction(axis);
    return dot(subtract(point, axis.start), direction);
}

bool intervals_overlap(double first_start, double first_end, double second_start, double second_end) {
    return first_start < second_end && second_start < first_end;
}

void validate_opening_rectangles(const std::vector<OpeningRectangle>& openings, double wall_length, double wall_height) {
    for (std::size_t index = 0; index < openings.size(); ++index) {
        const auto& opening = openings[index];
        if (opening.x_min < -epsilon || opening.x_max > wall_length + epsilon || opening.x_min >= opening.x_max) {
            throw std::invalid_argument("opening must stay inside host wall length");
        }
        if (opening.z_min < -epsilon || opening.z_max > wall_height + epsilon || opening.z_min >= opening.z_max) {
            throw std::invalid_argument("opening must stay inside host wall height");
        }

        for (std::size_t other = index + 1; other < openings.size(); ++other) {
            const auto& candidate = openings[other];
            if (intervals_overlap(opening.x_min, opening.x_max, candidate.x_min, candidate.x_max)) {
                throw std::invalid_argument("opening overlaps an existing hosted opening");
            }
        }
    }
}

void append_quad(MeshBuffer& mesh, std::uint32_t a, std::uint32_t b, std::uint32_t c, std::uint32_t d) {
    mesh.indices.push_back(a);
    mesh.indices.push_back(b);
    mesh.indices.push_back(c);
    mesh.indices.push_back(a);
    mesh.indices.push_back(c);
    mesh.indices.push_back(d);
}

void append_opening_reveal(MeshBuffer& mesh, const OpeningRectangle& opening) {
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_min, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_min, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_min, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_min, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_max, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_max, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_max, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_max, .z = opening.z_max});

    append_quad(mesh, base + 0, base + 4, base + 7, base + 3);
    append_quad(mesh, base + 1, base + 2, base + 6, base + 5);
    append_quad(mesh, base + 3, base + 7, base + 6, base + 2);
    append_quad(mesh, base + 0, base + 1, base + 5, base + 4);
}

MeshBuffer extrude_profile(const WallProfile2D& profile, double height_meters) {
    MeshBuffer mesh;
    const auto vertex_count = profile.polygon.size();
    if (vertex_count < 3) {
        return mesh;
    }

    mesh.vertices.reserve((vertex_count * 2) + (profile.openings.size() * 8));
    mesh.indices.reserve(((vertex_count - 2) * 6) + (vertex_count * 6) + (profile.openings.size() * 24));

    for (const auto& point : profile.polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = 0.0});
    }
    for (const auto& point : profile.polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = height_meters});
    }

    for (std::uint32_t index = 1; index + 1 < vertex_count; ++index) {
        mesh.indices.push_back(0);
        mesh.indices.push_back(index + 1);
        mesh.indices.push_back(index);

        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + index));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + index + 1));
    }

    for (std::uint32_t index = 0; index < vertex_count; ++index) {
        const auto next = (index + 1) % static_cast<std::uint32_t>(vertex_count);
        append_quad(
            mesh,
            index,
            next,
            static_cast<std::uint32_t>(vertex_count + next),
            static_cast<std::uint32_t>(vertex_count + index)
        );
    }

    for (const auto& opening : profile.openings) {
        append_opening_reveal(mesh, opening);
    }

    return mesh;
}

Point3 to_world_point(const Point3& local_point, const Line2& axis) {
    const auto direction = unit_direction(axis);
    const Point2 perpendicular{
        .x = -direction.y,
        .y = direction.x,
    };

    return Point3{
        .x = axis.start.x + (local_point.x * direction.x) + (local_point.y * perpendicular.x),
        .y = axis.start.y + (local_point.x * direction.y) + (local_point.y * perpendicular.y),
        .z = local_point.z,
    };
}

} // namespace

std::string FallbackGeometryBackend::name() const {
    return "Fallback mesh estimator";
}

bool FallbackGeometryBackend::supports_exact_solids() const noexcept {
    return false;
}

WallProfile2D FallbackGeometryBackend::build_wall_profile(const WallData& wall) const {
    const auto length = wall_length(wall.axis);
    if (length <= epsilon || wall.thickness_meters <= 0.0 || wall.height_meters <= 0.0) {
        throw std::invalid_argument("wall dimensions must be positive");
    }

    const auto half_thickness = wall.thickness_meters / 2.0;
    auto profile = WallProfile2D{
        .polygon = {
            Point2{.x = 0.0, .y = -half_thickness},
            Point2{.x = length, .y = -half_thickness},
            Point2{.x = length, .y = half_thickness},
            Point2{.x = 0.0, .y = half_thickness},
        },
    };

    const auto direction = unit_direction(wall.axis);
    const auto miter_extension = half_thickness;

    for (const auto& join : wall.joins) {
        if (join.kind == WallJoinKind::Tee || join.kind == WallJoinKind::Cross) {
            ++profile.t_junction_placeholders;
            continue;
        }

        const auto join_x = local_x(join.point, wall.axis);
        const auto at_start = std::abs(join_x) <= 1.0e-6;
        const auto at_end = std::abs(join_x - length) <= 1.0e-6;
        if (!at_start && !at_end) {
            ++profile.t_junction_placeholders;
            continue;
        }

        const auto other_direction = direction_away_from(join.point, join.other_axis);
        const auto turn = cross(direction, other_direction);
        if (std::abs(turn) <= epsilon) {
            continue;
        }

        profile.has_miter_join = true;
        if (at_end) {
            if (turn > 0.0) {
                profile.polygon[2].x += miter_extension;
            } else {
                profile.polygon[1].x += miter_extension;
            }
        } else {
            if (turn > 0.0) {
                profile.polygon[0].x -= miter_extension;
            } else {
                profile.polygon[3].x -= miter_extension;
            }
        }
    }

    for (const auto& opening : wall.openings) {
        const auto x_min = opening.offset_meters - (opening.width_meters / 2.0);
        const auto x_max = opening.offset_meters + (opening.width_meters / 2.0);
        const auto z_min = opening.sill_height_meters;
        const auto z_max = opening.sill_height_meters + opening.height_meters;
        profile.openings.push_back(OpeningRectangle{
            .element_id = opening.element_id,
            .kind = opening.kind,
            .x_min = x_min,
            .x_max = x_max,
            .y_min = -half_thickness,
            .y_max = half_thickness,
            .z_min = z_min,
            .z_max = z_max,
        });
    }

    validate_opening_rectangles(profile.openings, length, wall.height_meters);
    return profile;
}

GeneratedGeometry FallbackGeometryBackend::build_wall_geometry(const WallData& wall, Revision source_revision) const {
    auto profile = build_wall_profile(wall);
    auto mesh = extrude_profile(profile, wall.height_meters);

    for (auto& vertex : mesh.vertices) {
        vertex = to_world_point(vertex, wall.axis);
    }

    const auto gross_volume = wall_length(wall.axis) * wall.height_meters * wall.thickness_meters;

    auto opening_volume = 0.0;
    for (const auto& opening : profile.openings) {
        opening_volume += (opening.x_max - opening.x_min) * (opening.z_max - opening.z_min) * wall.thickness_meters;
    }

    return GeneratedGeometry{
        .dirty = false,
        .source_revision = source_revision,
        .vertices = static_cast<int>(mesh.vertices.size()),
        .triangles = static_cast<int>(mesh.indices.size() / 3),
        .openings_cut = static_cast<int>(profile.openings.size()),
        .solid_volume_cubic_meters = std::max(0.0, gross_volume - opening_volume),
        .profile = std::move(profile),
        .mesh = std::move(mesh),
    };
}

#if TBE_HAS_OCCT

namespace {

GeneratedGeometry build_occt_wall_geometry(const WallData& wall, Revision source_revision) {
    FallbackGeometryBackend fallback;
    const auto profile = fallback.build_wall_profile(wall);
    const auto length = wall_length(wall.axis);
    const auto half_thickness = wall.thickness_meters / 2.0;

    TopoDS_Shape solid = BRepPrimAPI_MakeBox(
        length,
        wall.thickness_meters,
        wall.height_meters
    ).Shape();

    for (const auto& opening : profile.openings) {
        const auto opening_solid = BRepPrimAPI_MakeBox(
            opening.x_max - opening.x_min,
            wall.thickness_meters + 2.0e-6,
            opening.z_max - opening.z_min
        ).Shape();

        gp_Trsf opening_transform;
        opening_transform.SetTranslation(gp_Vec(opening.x_min, -1.0e-6, opening.z_min));
        auto transformed_opening = opening_solid;
        transformed_opening.Move(TopLoc_Location(opening_transform));
        solid = BRepAlgoAPI_Cut(solid, transformed_opening);
    }

    BRepMesh_IncrementalMesh mesher(solid, 1.0e-4, false, 0.5, true);
    (void)mesher;
    MeshBuffer mesh;
    for (TopExp_Explorer explorer(solid, TopAbs_FACE); explorer.More(); explorer.Next()) {
        const auto face = TopoDS::Face(explorer.Current());
        TopLoc_Location location;
        const auto triangulation = BRep_Tool::Triangulation(face, location);
        if (triangulation.IsNull()) {
            continue;
        }

        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        for (int index = 1; index <= triangulation->NbNodes(); ++index) {
            const auto point = triangulation->Node(index).Transformed(location.Transformation());
            const auto direction = unit_direction(wall.axis);
            const Point2 perpendicular{.x = -direction.y, .y = direction.x};
            mesh.vertices.push_back(Point3{
                .x = wall.axis.start.x + (point.X() * direction.x) + ((point.Y() - half_thickness) * perpendicular.x),
                .y = wall.axis.start.y + (point.X() * direction.y) + ((point.Y() - half_thickness) * perpendicular.y),
                .z = point.Z(),
            });
        }

        for (int index = 1; index <= triangulation->NbTriangles(); ++index) {
            Standard_Integer first{};
            Standard_Integer second{};
            Standard_Integer third{};
            triangulation->Triangle(index).Get(first, second, third);
            if (face.Orientation() == TopAbs_REVERSED) {
                std::swap(second, third);
            }
            mesh.indices.push_back(base + static_cast<std::uint32_t>(first - 1));
            mesh.indices.push_back(base + static_cast<std::uint32_t>(second - 1));
            mesh.indices.push_back(base + static_cast<std::uint32_t>(third - 1));
        }
    }

    GProp_GProps properties;
    BRepGProp::VolumeProperties(solid, properties);
    return GeneratedGeometry{
        .dirty = false,
        .source_revision = source_revision,
        .vertices = static_cast<int>(mesh.vertices.size()),
        .triangles = static_cast<int>(mesh.indices.size() / 3),
        .openings_cut = static_cast<int>(profile.openings.size()),
        .solid_volume_cubic_meters = properties.Mass(),
        .profile = profile,
        .mesh = std::move(mesh),
    };
}

} // namespace

std::string OpenCascadeGeometryBackend::name() const {
    return "Open CASCADE solid backend";
}

bool OpenCascadeGeometryBackend::supports_exact_solids() const noexcept {
    return true;
}

WallProfile2D OpenCascadeGeometryBackend::build_wall_profile(const WallData& wall) const {
    FallbackGeometryBackend fallback;
    return fallback.build_wall_profile(wall);
}

GeneratedGeometry OpenCascadeGeometryBackend::build_wall_geometry(const WallData& wall, Revision source_revision) const {
    return build_occt_wall_geometry(wall, source_revision);
}

#endif

GeometryService::GeometryService(Backend backend) {
    switch (backend) {
    case Backend::Fallback:
        backend_ = std::make_unique<FallbackGeometryBackend>();
        break;
    case Backend::OpenCascade:
#if TBE_HAS_OCCT
        backend_ = std::make_unique<OpenCascadeGeometryBackend>();
        break;
#else
        throw std::invalid_argument("Open CASCADE geometry backend is not available in this build");
#endif
    }
}

GeometryService::~GeometryService() = default;
GeometryService::GeometryService(GeometryService&&) noexcept = default;
GeometryService& GeometryService::operator=(GeometryService&&) noexcept = default;

std::string GeometryService::backend_name() const {
    return backend_->name();
}

bool GeometryService::supports_exact_solids() const noexcept {
    return backend_->supports_exact_solids();
}

double GeometryService::polygon_area(const std::vector<Point2>& polygon) const {
    return std::abs(polygon_signed_area(polygon));
}

double GeometryService::roof_surface_area(const RoofData& roof) const {
    const auto plan_area = polygon_area(roof.boundary_polygon);
    if (roof.roof_type == RoofType::SimpleGable && roof.slope_degrees.has_value()) {
        const auto radians = (*roof.slope_degrees) * 3.14159265358979323846 / 180.0;
        const auto cosine = std::cos(radians);
        if (std::abs(cosine) > epsilon) {
            return plan_area / cosine;
        }
    }
    return plan_area;
}

double GeometryService::layered_assembly_thickness(const LayeredAssemblyData& assembly) const {
    auto total = 0.0;
    for (const auto& layer : assembly.layers) {
        total += layer.thickness_meters;
    }
    return total;
}

MeshBuffer GeometryService::build_extruded_polygon_mesh(
    const std::vector<Point2>& polygon,
    double thickness,
    double elevation_offset
) const {
    return extrude_polygon_mesh(polygon, thickness, elevation_offset);
}

MeshBuffer GeometryService::build_column_mesh(Point2 center, double width, double depth, double height) const {
    return column_mesh(center, width, depth, height);
}

MeshBuffer GeometryService::build_beam_mesh(Point2 start, Point2 end, double width, double height) const {
    return beam_mesh(start, end, width, height);
}

MeshBuffer GeometryService::build_stair_mesh(const StairData& stair) const {
    return stair_mesh(stair);
}

WallProfile2D GeometryService::build_wall_profile(const WallData& wall) const {
    return backend_->build_wall_profile(wall);
}

GeneratedGeometry GeometryService::build_wall_geometry(const WallData& wall, Revision source_revision) const {
    return backend_->build_wall_geometry(wall, source_revision);
}

} // namespace tbe::core
