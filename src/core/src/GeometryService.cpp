#include "tbe/core/GeometryService.hpp"

#include <algorithm>
#include <cmath>
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

std::string GeometryService::backend_name() const {
#if TBE_HAS_OCCT
    return "Open CASCADE";
#else
    return "Fallback mesh estimator";
#endif
}

WallProfile2D GeometryService::build_wall_profile(const WallData& wall) const {
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

GeneratedGeometry GeometryService::build_wall_geometry(const WallData& wall, Revision source_revision) const {
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

} // namespace tbe::core
