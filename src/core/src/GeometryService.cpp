#include "tbe/core/GeometryService.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <optional>
#include <stdexcept>
#include <utility>

namespace tbe::core {

namespace {

constexpr auto epsilon = 1.0e-9;

double wall_length(const Line2& axis) {
    const auto dx = axis.end.x - axis.start.x;
    const auto dy = axis.end.y - axis.start.y;
    return std::sqrt((dx * dx) + (dy * dy));
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

// The distance from an endpoint to a true mitre intersection.  Extending a
// wall by half of its thickness only happens to be correct for a 90 degree
// corner; every other angle needs the half-angle relation below.  Keeping a
// finite limit prevents an almost reversed pair of lines from generating a
// kilometre-long spike while the user is still sketching a wall.
std::optional<double> miter_extension(double half_thickness, Point2 first, Point2 second) {
    const auto sine = cross(first, second);
    const auto cosine = dot(first, second);
    const auto denominator = 1.0 + cosine;
    if (std::abs(sine) <= epsilon || denominator <= epsilon) {
        return std::nullopt;
    }

    const auto extension = half_thickness * std::abs(sine) / denominator;
    constexpr auto miter_limit = 4.0;
    if (!std::isfinite(extension) || extension > half_thickness * miter_limit) {
        return std::nullopt;
    }
    return extension;
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
        if (!std::isfinite(opening.x_min) || !std::isfinite(opening.x_max) ||
            !std::isfinite(opening.y_min) || !std::isfinite(opening.y_max) ||
            !std::isfinite(opening.z_min) || !std::isfinite(opening.z_max) ||
            opening.x_min < -epsilon || opening.x_max > wall_length + epsilon || opening.x_min >= opening.x_max) {
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

void append_triangle(MeshBuffer& mesh, std::uint32_t a, std::uint32_t b, std::uint32_t c, ElementId material_id = 0) {
    mesh.indices.push_back(a);
    mesh.indices.push_back(b);
    mesh.indices.push_back(c);
    if (!mesh.triangle_material_ids.empty() || material_id != 0) {
        mesh.triangle_material_ids.push_back(material_id);
    }
}

void append_quad(MeshBuffer& mesh, std::uint32_t a, std::uint32_t b, std::uint32_t c, std::uint32_t d, ElementId material_id = 0) {
    append_triangle(mesh, a, b, c, material_id);
    append_triangle(mesh, a, c, d, material_id);
}

void ensure_material_tracking(MeshBuffer& mesh) {
    if (mesh.triangle_material_ids.empty() && !mesh.indices.empty()) {
        mesh.triangle_material_ids.assign(mesh.indices.size() / 3, 0);
    }
}

void append_opening_reveal(MeshBuffer& mesh, const OpeningRectangle& opening, ElementId material_id = 0) {
    ensure_material_tracking(mesh);
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_min, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_min, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_min, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_min, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_max, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_max, .z = opening.z_min});
    mesh.vertices.push_back(Point3{.x = opening.x_max, .y = opening.y_max, .z = opening.z_max});
    mesh.vertices.push_back(Point3{.x = opening.x_min, .y = opening.y_max, .z = opening.z_max});

    append_quad(mesh, base + 0, base + 4, base + 7, base + 3, material_id);
    append_quad(mesh, base + 1, base + 2, base + 6, base + 5, material_id);
    append_quad(mesh, base + 3, base + 7, base + 6, base + 2, material_id);
    append_quad(mesh, base + 0, base + 1, base + 5, base + 4, material_id);
}

void append_layer_face_with_openings(
    MeshBuffer& mesh,
    double y,
    double x_min,
    double x_max,
    double height,
    const std::vector<OpeningRectangle>& openings,
    ElementId material_id
) {
    // WALL OPENING CONTRACT: `openings` is already sorted along the local
    // wall axis by build_wall_profile(). Its x coordinates are measured from
    // the wall axis start and its z coordinates are measured from the wall's
    // base. This routine is the authoritative filled-face cut; a later
    // renderer overlay may decorate the face, but it must never reconstruct a
    // solid quad across one of these intervals. If a new wall layer or
    // material pass bypasses this helper, doors/windows can look correct in
    // metadata while an opaque face remains behind them in Solid.
    auto cursor = x_min;
    for (const auto& opening : openings) {
        if (opening.x_min > cursor + epsilon) {
            const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back(Point3{.x = cursor, .y = y, .z = 0.0});
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = 0.0});
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = height});
            mesh.vertices.push_back(Point3{.x = cursor, .y = y, .z = height});
            append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
        }
        if (opening.z_min > epsilon) {
            const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = 0.0});
            mesh.vertices.push_back(Point3{.x = opening.x_max, .y = y, .z = 0.0});
            mesh.vertices.push_back(Point3{.x = opening.x_max, .y = y, .z = opening.z_min});
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = opening.z_min});
            append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
        }
        if (opening.z_max < height - epsilon) {
            const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = opening.z_max});
            mesh.vertices.push_back(Point3{.x = opening.x_max, .y = y, .z = opening.z_max});
            mesh.vertices.push_back(Point3{.x = opening.x_max, .y = y, .z = height});
            mesh.vertices.push_back(Point3{.x = opening.x_min, .y = y, .z = height});
            append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
        }
        cursor = std::max(cursor, opening.x_max);
    }
    if (cursor < x_max - epsilon) {
        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back(Point3{.x = cursor, .y = y, .z = 0.0});
        mesh.vertices.push_back(Point3{.x = x_max, .y = y, .z = 0.0});
        mesh.vertices.push_back(Point3{.x = x_max, .y = y, .z = height});
        mesh.vertices.push_back(Point3{.x = cursor, .y = y, .z = height});
        append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
    }
}

void append_layer_prism(
    MeshBuffer& mesh,
    double x_min_at_y_min,
    double x_max_at_y_min,
    double x_min_at_y_max,
    double x_max_at_y_max,
    double y_min,
    double y_max,
    double height,
    const std::vector<OpeningRectangle>& openings,
    ElementId material_id,
    bool wraps_openings,
    bool wraps_ends
) {
    // Layered walls deliberately share the same analytical opening rectangles
    // as the envelope wall. `wraps_openings` controls only the reveal/jamb
    // faces for this physical layer; it must not disable the long-face cut
    // above. Keep this distinction when adding insulation, finish or core
    // layers, otherwise a decorative layer can silently cap a real opening.
    append_layer_face_with_openings(mesh, y_min, x_min_at_y_min, x_max_at_y_min, height, openings, material_id);
    append_layer_face_with_openings(mesh, y_max, x_min_at_y_max, x_max_at_y_max, height, openings, material_id);

    const auto append_rect = [&](Point3 a, Point3 b, Point3 c, Point3 d) {
        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back(a);
        mesh.vertices.push_back(b);
        mesh.vertices.push_back(c);
        mesh.vertices.push_back(d);
        append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
    };
    if (wraps_ends) {
        // End caps are only present on layers that wrap the wall endpoints.
        // The long y_min/y_max faces above already own the two wall faces;
        // duplicating either of them here creates coplanar polygons and
        // produces z-fighting bands while the camera orbits on mobile GPUs.
        append_rect(
            {x_min_at_y_min, y_min, 0.0}, {x_min_at_y_max, y_max, 0.0},
            {x_min_at_y_max, y_max, height}, {x_min_at_y_min, y_min, height}
        );
        append_rect(
            {x_max_at_y_min, y_min, 0.0}, {x_max_at_y_min, y_min, height},
            {x_max_at_y_max, y_max, height}, {x_max_at_y_max, y_max, 0.0}
        );
    }
    // Close the actual bottom and top of the layered prism. These used to be
    // emitted as a second copy of the y_min/y_max faces, which both sealed
    // hosted openings and left two coincident wall surfaces in every layer.
    append_rect(
        {x_min_at_y_min, y_min, 0.0}, {x_max_at_y_min, y_min, 0.0},
        {x_max_at_y_max, y_max, 0.0}, {x_min_at_y_max, y_max, 0.0}
    );
    append_rect(
        {x_min_at_y_min, y_min, height}, {x_min_at_y_max, y_max, height},
        {x_max_at_y_max, y_max, height}, {x_max_at_y_min, y_min, height}
    );

    // Only layers configured to wrap openings receive jamb/head/sill return
    // faces.  The analytical opening cut remains shared by every layer.
    if (wraps_openings) {
        for (const auto& opening : openings) {
            append_rect({opening.x_min, y_min, opening.z_min}, {opening.x_min, y_max, opening.z_min}, {opening.x_min, y_max, opening.z_max}, {opening.x_min, y_min, opening.z_max});
            append_rect({opening.x_max, y_min, opening.z_min}, {opening.x_max, y_min, opening.z_max}, {opening.x_max, y_max, opening.z_max}, {opening.x_max, y_max, opening.z_min});
            append_rect({opening.x_min, y_min, opening.z_min}, {opening.x_max, y_min, opening.z_min}, {opening.x_max, y_max, opening.z_min}, {opening.x_min, y_max, opening.z_min});
            append_rect({opening.x_min, y_min, opening.z_max}, {opening.x_min, y_max, opening.z_max}, {opening.x_max, y_max, opening.z_max}, {opening.x_max, y_min, opening.z_max});
        }
    }
}

MeshBuffer build_layered_wall_mesh(
    const std::vector<WallProfile2D>& layer_profiles,
    double height_meters,
    const std::vector<WallAssemblyLayer>& layers
) {
    MeshBuffer mesh;
    if (layers.empty() || layer_profiles.size() != layers.size()) {
        return mesh;
    }
    auto y = -std::accumulate(layers.begin(), layers.end(), 0.0, [](double total, const auto& layer) {
        return total + layer.thickness_meters;
    }) / 2.0;
    for (std::size_t index = 0; index < layers.size(); ++index) {
        const auto& layer = layers[index];
        const auto& profile = layer_profiles[index];
        if (profile.polygon.size() < 4) {
            return {};
        }
        const auto next_y = y + layer.thickness_meters;
        // Each layer receives its own solved plan profile.  This is what
        // makes a thin finish, an insulation layer and a structural core
        // clean up independently at a joined endpoint instead of inheriting
        // the envelope wall's mitre distance.
        append_layer_prism(
            mesh,
            profile.polygon[0].x, profile.polygon[1].x,
            profile.polygon[3].x, profile.polygon[2].x,
            y, next_y, height_meters, profile.openings, layer.material_id,
            layer.wraps_openings, layer.wraps_ends
        );
        y = next_y;
    }
    return mesh;
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

    // Hosted openings are real voids, not decorative reveal geometry. The two
    // long wall faces must be tessellated around them; otherwise an opaque
    // wall face remains behind every door/window and can depth-fight with the
    // hosted element in the viewport.
    append_layer_face_with_openings(
        mesh,
        profile.polygon[0].y,
        std::min(profile.polygon[0].x, profile.polygon[1].x),
        std::max(profile.polygon[0].x, profile.polygon[1].x),
        height_meters,
        profile.openings,
        0
    );
    append_layer_face_with_openings(
        mesh,
        profile.polygon[2].y,
        std::min(profile.polygon[2].x, profile.polygon[3].x),
        std::max(profile.polygon[2].x, profile.polygon[3].x),
        height_meters,
        profile.openings,
        0
    );
    // End caps and the top/bottom caps remain intact because hosted openings
    // are vertical cuts through the two long faces.
    for (const auto index : {std::uint32_t{1}, std::uint32_t{3}}) {
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

struct ArcStation {
    double distance_meters{};
    Point2 centerline{};
    Point2 radial{};
};

std::vector<ArcStation> arc_stations(const WallData& wall, const WallProfile2D& profile) {
    if (!wall.arc.has_value()) return {};
    const auto& arc = *wall.arc;
    const auto path_length = std::abs(arc.radius_meters * arc.sweep_radians);
    if (path_length <= epsilon || arc.radius_meters <= epsilon) return {};

    std::vector<double> distances{0.0, path_length};
    for (const auto& opening : profile.openings) {
        distances.push_back(std::clamp(opening.x_min, 0.0, path_length));
        distances.push_back(std::clamp(opening.x_max, 0.0, path_length));
    }
    const auto segment_count = std::clamp(static_cast<int>(std::ceil(path_length / 0.18)), 12, 96);
    for (int index = 1; index < segment_count; ++index) {
        distances.push_back(path_length * static_cast<double>(index) / static_cast<double>(segment_count));
    }
    std::sort(distances.begin(), distances.end());
    distances.erase(std::unique(distances.begin(), distances.end(), [](double left, double right) {
        return std::abs(left - right) <= 1.0e-8;
    }), distances.end());

    std::vector<ArcStation> stations;
    stations.reserve(distances.size());
    for (const auto distance : distances) {
        const auto fraction = distance / path_length;
        const auto angle = arc.start_angle_radians + (arc.sweep_radians * fraction);
        const auto radial = Point2{.x = std::cos(angle), .y = std::sin(angle)};
        stations.push_back(ArcStation{
            .distance_meters = distance,
            .centerline = Point2{
                .x = arc.center.x + (radial.x * arc.radius_meters),
                .y = arc.center.y + (radial.y * arc.radius_meters),
            },
            .radial = radial,
        });
    }
    return stations;
}

bool opening_contains_distance(const OpeningRectangle& opening, double distance) {
    return distance > opening.x_min + epsilon && distance < opening.x_max - epsilon;
}

void append_curved_wall_band(
    MeshBuffer& mesh,
    Point2 outer,
    Point2 inner,
    double z_min,
    double z_max,
    double base_elevation,
    ElementId material_id
) {
    if (z_max <= z_min + epsilon) return;
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation + z_min});
    mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation + z_min});
    mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation + z_max});
    mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation + z_max});
    append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
}

MeshBuffer build_curved_wall_mesh(
    const WallData& wall,
    const WallProfile2D& profile,
    double height_meters,
    double base_elevation,
    ElementId material_id
) {
    MeshBuffer mesh;
    const auto stations = arc_stations(wall, profile);
    if (stations.size() < 2) return mesh;
    const auto half_thickness = wall.thickness_meters / 2.0;

    struct StationVertices {
        std::uint32_t outer_bottom{};
        std::uint32_t inner_bottom{};
        std::uint32_t outer_top{};
        std::uint32_t inner_top{};
    };
    std::vector<StationVertices> vertices;
    vertices.reserve(stations.size());
    for (const auto& station : stations) {
        const auto outer = Point2{
            .x = station.centerline.x + (station.radial.x * half_thickness),
            .y = station.centerline.y + (station.radial.y * half_thickness),
        };
        const auto inner = Point2{
            .x = station.centerline.x - (station.radial.x * half_thickness),
            .y = station.centerline.y - (station.radial.y * half_thickness),
        };
        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation});
        mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation});
        mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation + height_meters});
        mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation + height_meters});
        vertices.push_back(StationVertices{
            .outer_bottom = base,
            .inner_bottom = base + 1,
            .outer_top = base + 2,
            .inner_top = base + 3,
        });
    }

    for (std::size_t index = 0; index + 1 < stations.size(); ++index) {
        const auto& first = stations[index];
        const auto& second = stations[index + 1];
        const auto midpoint = (first.distance_meters + second.distance_meters) * 0.5;
        const auto opening = std::find_if(profile.openings.begin(), profile.openings.end(), [&](const auto& candidate) {
            return opening_contains_distance(candidate, midpoint);
        });
        const auto& a = vertices[index];
        const auto& b = vertices[index + 1];
        // Top and bottom remain continuous; a hosted opening removes only the
        // vertical wall faces between its sill and head.
        append_quad(mesh, a.outer_bottom, b.outer_bottom, b.inner_bottom, a.inner_bottom, material_id);
        append_quad(mesh, a.outer_top, a.inner_top, b.inner_top, b.outer_top, material_id);
        const auto append_side_bands = [&](std::uint32_t first_bottom, std::uint32_t second_bottom,
                                           std::uint32_t second_top, std::uint32_t first_top) {
            if (opening == profile.openings.end()) {
                append_quad(mesh, first_bottom, second_bottom, second_top, first_top, material_id);
                return;
            }
            append_curved_wall_band(mesh,
                Point2{.x = mesh.vertices[first_bottom].x, .y = mesh.vertices[first_bottom].y},
                Point2{.x = mesh.vertices[second_bottom].x, .y = mesh.vertices[second_bottom].y},
                0.0, opening->z_min, base_elevation, material_id);
            append_curved_wall_band(mesh,
                Point2{.x = mesh.vertices[first_top].x, .y = mesh.vertices[first_top].y},
                Point2{.x = mesh.vertices[second_top].x, .y = mesh.vertices[second_top].y},
                opening->z_max, height_meters, base_elevation, material_id);
        };
        append_side_bands(a.outer_bottom, b.outer_bottom, b.outer_top, a.outer_top);
        append_side_bands(a.inner_bottom, b.inner_bottom, b.inner_top, a.inner_top);
    }

    const auto append_end_cap = [&](const StationVertices& station) {
        append_quad(mesh, station.outer_bottom, station.inner_bottom, station.inner_top, station.outer_top, material_id);
    };
    append_end_cap(vertices.front());
    append_end_cap(vertices.back());

    // Add the four reveal faces at every opening boundary.  The main wall
    // faces above are split at these exact stations, so the opening remains a
    // real void instead of a panel painted over a solid curved wall.
    for (const auto& opening : profile.openings) {
        for (const auto distance : {opening.x_min, opening.x_max}) {
            const auto station = std::find_if(stations.begin(), stations.end(), [&](const auto& candidate) {
                return std::abs(candidate.distance_meters - distance) <= 1.0e-8;
            });
            if (station == stations.end()) continue;
            const auto radial = station->radial;
            const auto outer = Point2{
                .x = station->centerline.x + (radial.x * half_thickness),
                .y = station->centerline.y + (radial.y * half_thickness),
            };
            const auto inner = Point2{
                .x = station->centerline.x - (radial.x * half_thickness),
                .y = station->centerline.y - (radial.y * half_thickness),
            };
            const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation + opening.z_min});
            mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation + opening.z_min});
            mesh.vertices.push_back(Point3{.x = inner.x, .y = inner.y, .z = base_elevation + opening.z_max});
            mesh.vertices.push_back(Point3{.x = outer.x, .y = outer.y, .z = base_elevation + opening.z_max});
            append_quad(mesh, base + 0, base + 1, base + 2, base + 3, material_id);
        }
    }
    return mesh;
}

} // namespace

std::string GeometryService::backend_name() const {
#if TBE_HAS_OCCT
    return "Open CASCADE";
#else
    return "Fallback mesh estimator";
#endif
}

WallProfile2D GeometryService::build_wall_profile(const WallData& wall) const {
    const auto length = wall.arc.has_value()
        ? std::abs(wall.arc->radius_meters * wall.arc->sweep_radians)
        : wall_length(wall.axis);
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

    // Curved walls use arc-length coordinates for hosted openings.  Their
    // endpoint joins are intentionally handled without straight-wall mitres;
    // the real circular strip is generated by build_curved_wall_mesh().
    if (wall.arc.has_value()) {
        for (const auto& opening : wall.openings) {
            const auto x_min = opening.offset_meters - (opening.width_meters / 2.0);
            const auto x_max = opening.offset_meters + (opening.width_meters / 2.0);
            const auto z_min = opening.vertical_offset_meters + opening.sill_height_meters;
            const auto z_max = opening.vertical_offset_meters + opening.sill_height_meters + opening.height_meters;
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
        std::sort(profile.openings.begin(), profile.openings.end(), [](const auto& left, const auto& right) {
            return left.x_min < right.x_min;
        });
        validate_opening_rectangles(profile.openings, length, wall.height_meters);
        return profile;
    }

    const auto direction = unit_direction(wall.axis);
    struct EndpointMiter {
        double extension{};
        double turn{};
    };
    std::optional<EndpointMiter> start_miter;
    std::optional<EndpointMiter> end_miter;
    bool tee_at_start = false;
    bool tee_at_end = false;

    for (const auto& join : wall.joins) {
        if (join.kind == WallJoinKind::Tee || join.kind == WallJoinKind::Cross) {
            ++profile.t_junction_placeholders;
            if (join.kind == WallJoinKind::Tee) {
                const auto join_x = local_x(join.point, wall.axis);
                if (std::abs(join_x) <= 1.0e-6) {
                    tee_at_start = true;
                } else if (std::abs(join_x - length) <= 1.0e-6) {
                    tee_at_end = true;
                }
            }
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
        const auto extension = miter_extension(half_thickness, direction, other_direction);
        if (!extension.has_value()) {
            continue;
        }

        auto& target = at_end ? end_miter : start_miter;
        // A fan of walls can share one endpoint.  A wall can only have one
        // cap there, so retain the widest valid mitre instead of summing all
        // joins into a visibly exploded corner.
        if (!target.has_value() || extension.value() > target->extension) {
            target = EndpointMiter{.extension = extension.value(), .turn = turn};
        }
    }

    const auto apply_miter = [&](const EndpointMiter& miter, bool at_end) {
        profile.has_miter_join = true;
        const auto signed_extension = miter.turn > 0.0 ? miter.extension : -miter.extension;
        if (at_end) {
            // A mitre is a shared cap, not a one-sided overhang.  Moving both
            // faces in opposite directions gives the neighbouring wall the
            // exact same cap line and removes the overlap seam in plan.
            profile.polygon[1].x += signed_extension;
            profile.polygon[2].x -= signed_extension;
        } else {
            profile.polygon[0].x -= signed_extension;
            profile.polygon[3].x += signed_extension;
        }
    };
    if (start_miter.has_value()) apply_miter(*start_miter, false);
    if (end_miter.has_value()) apply_miter(*end_miter, true);

    // A Tee is different from an end-to-end corner: the branch wall must stop
    // at the face of the continuous wall, not run through its centreline.
    // Otherwise both wall meshes occupy the same half-thickness and their
    // coincident edges show as doubled lines in plan/3D. Keep the host wall
    // untouched and retract only the endpoint wall by half its thickness.
    if (tee_at_start) {
        const auto trimmed_start = half_thickness;
        profile.polygon[0].x = std::max(profile.polygon[0].x, trimmed_start);
        profile.polygon[3].x = std::max(profile.polygon[3].x, trimmed_start);
    }
    if (tee_at_end) {
        const auto trimmed_end = length - half_thickness;
        profile.polygon[1].x = std::min(profile.polygon[1].x, trimmed_end);
        profile.polygon[2].x = std::min(profile.polygon[2].x, trimmed_end);
    }

    for (const auto& opening : wall.openings) {
        const auto x_min = opening.offset_meters - (opening.width_meters / 2.0);
        const auto x_max = opening.offset_meters + (opening.width_meters / 2.0);
        const auto z_min = opening.vertical_offset_meters + opening.sill_height_meters;
        const auto z_max = opening.vertical_offset_meters + opening.sill_height_meters + opening.height_meters;
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

    std::sort(profile.openings.begin(), profile.openings.end(), [](const auto& left, const auto& right) {
        return left.x_min < right.x_min;
    });

    validate_opening_rectangles(profile.openings, length, wall.height_meters);
    return profile;
}

GeneratedGeometry GeometryService::build_wall_geometry(
    const WallData& wall,
    Revision source_revision,
    const std::vector<WallAssemblyLayer>& layers
) const {
    auto profile = build_wall_profile(wall);
    const auto arc_thickness = layers.empty()
        ? wall.thickness_meters
        : std::accumulate(layers.begin(), layers.end(), 0.0, [](double total, const auto& layer) {
            return total + layer.thickness_meters;
        });
    if (wall.arc.has_value()) {
        const auto material_id = layers.empty() ? ElementId{0} : layers.front().material_id;
        auto mesh = build_curved_wall_mesh(
            wall,
            profile,
            wall.height_meters,
            0.0,
            material_id
        );
        auto opening_volume = 0.0;
        for (const auto& opening : profile.openings) {
            opening_volume += (opening.x_max - opening.x_min) *
                (opening.z_max - opening.z_min) * arc_thickness;
        }
        const auto gross_volume = std::abs(wall.arc->radius_meters * wall.arc->sweep_radians) *
            wall.height_meters * arc_thickness;
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
    const auto layer_thickness = std::accumulate(layers.begin(), layers.end(), 0.0, [](double total, const auto& layer) {
        return total + layer.thickness_meters;
    });
    std::vector<WallProfile2D> layer_profiles;
    if (!layers.empty() && layer_thickness > epsilon) {
        layer_profiles.reserve(layers.size());
        for (const auto& layer : layers) {
            auto layer_wall = wall;
            // A layer is extruded between its two assembly faces below, so
            // the profile solver must use the full face-to-face offset when
            // resolving an endpoint mitre.  Passing the layer thickness as
            // the wall thickness would halve the mitre extension again.
            layer_wall.thickness_meters = layer.thickness_meters * 2.0;
            layer_profiles.push_back(build_wall_profile(layer_wall));
        }
    }
    auto mesh = layer_profiles.empty()
        ? extrude_profile(profile, wall.height_meters)
        : build_layered_wall_mesh(layer_profiles, wall.height_meters, layers);

    for (auto& vertex : mesh.vertices) {
        vertex = to_world_point(vertex, wall.axis);
    }

    const auto resolved_thickness = layer_thickness > epsilon ? layer_thickness : wall.thickness_meters;
    const auto gross_volume = wall_length(wall.axis) * wall.height_meters * resolved_thickness;

    auto opening_volume = 0.0;
    for (const auto& opening : profile.openings) {
        opening_volume += (opening.x_max - opening.x_min) * (opening.z_max - opening.z_min) * resolved_thickness;
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

} // namespace tbe::core
