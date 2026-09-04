#include "tbe/core/Document.hpp"

#include "tbe/core/GeometryService.hpp"
#include "tbe/core/PolygonTriangulation.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
#include <numbers>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <utility>

namespace tbe::core {

namespace {

constexpr auto epsilon = 1.0e-9;

double length(const Line2& line) {
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

double wall_centerline_length(const WallData& wall) {
    if (wall.arc.has_value()) {
        return std::abs(wall.arc->radius_meters * wall.arc->sweep_radians);
    }
    return length(wall.axis);
}

// A curved wall remains one authored element, but every downstream profile
// operation needs a bounded approximation of its centerline. Keep this
// tessellation policy in the core so Pick Walls, room detection and their
// dependent floor/ceiling systems use the same path rather than falling back
// to the arc chord.
std::vector<Point2> wall_path_points(const WallData& wall) {
    if (!wall.arc.has_value()) {
        return {wall.axis.start, wall.axis.end};
    }

    const auto& arc = *wall.arc;
    const auto path_length = std::abs(arc.radius_meters * arc.sweep_radians);
    const auto segment_count = std::clamp(
        static_cast<int>(std::ceil(path_length / 0.18)),
        16,
        96
    );
    std::vector<Point2> points;
    points.reserve(static_cast<std::size_t>(segment_count) + 1);
    for (int index = 0; index <= segment_count; ++index) {
        const auto fraction = static_cast<double>(index) /
            static_cast<double>(segment_count);
        const auto angle = arc.start_angle_radians +
            (arc.sweep_radians * fraction);
        points.push_back(Point2{
            .x = arc.center.x + (std::cos(angle) * arc.radius_meters),
            .y = arc.center.y + (std::sin(angle) * arc.radius_meters),
        });
    }
    if (!points.empty()) {
        points.front() = wall.axis.start;
        points.back() = wall.axis.end;
    }
    return points;
}

// WallJoin stores a reference line consumed by the geometry service. For a
// curved wall its endpoint chord is not a usable direction: a straight wall
// joining the arc must see the arc tangent at the contact, otherwise its
// miter cap is solved against an unrelated diagonal.
Line2 wall_join_reference_axis(const WallData& wall, Point2 contact) {
    if (!wall.arc.has_value()) {
        return wall.axis;
    }

    const auto& arc = *wall.arc;
    const auto start_distance = std::hypot(
        contact.x - wall.axis.start.x,
        contact.y - wall.axis.start.y);
    const auto end_distance = std::hypot(
        contact.x - wall.axis.end.x,
        contact.y - wall.axis.end.y);
    const auto endpoint = start_distance <= end_distance ? wall.axis.start : wall.axis.end;
    const auto radial_length = std::hypot(
        endpoint.x - arc.center.x,
        endpoint.y - arc.center.y);
    if (radial_length <= epsilon) {
        return wall.axis;
    }

    const auto radial = Point2{
        .x = (endpoint.x - arc.center.x) / radial_length,
        .y = (endpoint.y - arc.center.y) / radial_length,
    };
    const auto tangent_forward = arc.sweep_radians >= 0.0
        ? Point2{.x = -radial.y, .y = radial.x}
        : Point2{.x = radial.y, .y = -radial.x};
    // Keep the reference axis in the authored tangent orientation.  The
    // straight-wall join solver already asks direction_away_from() which way
    // to travel from the contact point; reversing the arc tangent here at its
    // end makes that second reversal produce the opposite cap side.  That
    // leaves the arc and straight wall with crossing, rather than shared,
    // miter planes.
    const auto away = tangent_forward;
    return Line2{
        .start = contact,
        .end = Point2{.x = contact.x + away.x, .y = contact.y + away.y},
    };
}

Point2 add(Point2 left, Point2 right) {
    return Point2{.x = left.x + right.x, .y = left.y + right.y};
}

Point2 subtract(Point2 left, Point2 right) {
    return Point2{.x = left.x - right.x, .y = left.y - right.y};
}

Point2 scale(Point2 value, double factor) {
    return Point2{.x = value.x * factor, .y = value.y * factor};
}

Point2 unit_direction(Line2 line) {
    const auto line_length = length(line);
    return Point2{
        .x = (line.end.x - line.start.x) / line_length,
        .y = (line.end.y - line.start.y) / line_length,
    };
}

Point2 perpendicular_left(Point2 direction) {
    return Point2{.x = -direction.y, .y = direction.x};
}

bool between(double value, double first, double second) {
    return value >= (std::min(first, second) - epsilon) && value <= (std::max(first, second) + epsilon);
}

bool same_point(Point2 first, Point2 second) {
    return std::abs(first.x - second.x) < epsilon && std::abs(first.y - second.y) < epsilon;
}

void append_unique(std::vector<ElementId>& values, ElementId value) {
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

std::string escape_json(std::string_view value) {
    std::string escaped;
    for (const auto ch : value) {
        if (ch == '"' || ch == '\\') {
            escaped.push_back('\\');
        }
        escaped.push_back(ch);
    }
    return escaped;
}

std::string escape_xml(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const auto ch : value) {
        switch (ch) {
        case '&': escaped.append("&amp;"); break;
        case '<': escaped.append("&lt;"); break;
        case '>': escaped.append("&gt;"); break;
        case '"': escaped.append("&quot;"); break;
        case '\'': escaped.append("&apos;"); break;
        default: escaped.push_back(ch); break;
        }
    }
    return escaped;
}

std::string svg_element_kind_name(ElementKind kind) {
    switch (kind) {
    case ElementKind::Level: return "level";
    case ElementKind::Wall: return "wall";
    case ElementKind::Door: return "door";
    case ElementKind::Window: return "window";
    case ElementKind::Room: return "room";
    case ElementKind::Roof: return "roof";
    case ElementKind::Column: return "column";
    case ElementKind::Beam: return "beam";
    case ElementKind::Stair: return "stair";
    case ElementKind::Slab: return "slab";
    case ElementKind::Proxy: return "proxy";
    }
    return "unknown";
}

std::string svg_hit_kind_name(ElementKind kind) {
    switch (kind) {
    case ElementKind::Wall: return "wall_body";
    case ElementKind::Door:
    case ElementKind::Window: return "opening";
    case ElementKind::Room: return "room_interior";
    case ElementKind::Roof: return "roof";
    case ElementKind::Column: return "column";
    case ElementKind::Beam: return "beam";
    case ElementKind::Stair: return "stair";
    case ElementKind::Slab: return "slab";
    case ElementKind::Proxy: return "proxy";
    case ElementKind::Level: return "level";
    }
    return "unknown";
}

std::optional<Point2> line_intersection(Line2 first, Line2 second) {
    const auto x1 = first.start.x;
    const auto y1 = first.start.y;
    const auto x2 = first.end.x;
    const auto y2 = first.end.y;
    const auto x3 = second.start.x;
    const auto y3 = second.start.y;
    const auto x4 = second.end.x;
    const auto y4 = second.end.y;

    const auto denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4));
    if (std::abs(denominator) < epsilon) {
        return std::nullopt;
    }

    const auto px = (((x1 * y2) - (y1 * x2)) * (x3 - x4) - (x1 - x2) * ((x3 * y4) - (y3 * x4))) / denominator;
    const auto py = (((x1 * y2) - (y1 * x2)) * (y3 - y4) - (y1 - y2) * ((x3 * y4) - (y3 * x4))) / denominator;

    return Point2{.x = px, .y = py};
}

std::optional<Point2> segment_intersection(Line2 first, Line2 second) {
    const auto intersection = line_intersection(first, second);
    if (!intersection.has_value()) {
        return std::nullopt;
    }
    if (!between(intersection->x, first.start.x, first.end.x) ||
        !between(intersection->y, first.start.y, first.end.y) ||
        !between(intersection->x, second.start.x, second.end.x) ||
        !between(intersection->y, second.start.y, second.end.y)) {
        return std::nullopt;
    }
    return intersection;
}

bool is_endpoint(Point2 point, Line2 line) {
    return same_point(point, line.start) || same_point(point, line.end);
}

WallJoinKind join_kind(Point2 point, Line2 first, Line2 second) {
    const auto first_endpoint = is_endpoint(point, first);
    const auto second_endpoint = is_endpoint(point, second);

    if (first_endpoint && second_endpoint) {
        return WallJoinKind::End;
    }
    if (first_endpoint || second_endpoint) {
        return WallJoinKind::Tee;
    }
    return WallJoinKind::Cross;
}

bool openings_overlap(double first_offset, double first_width, double second_offset, double second_width) {
    const auto first_start = first_offset - (first_width / 2.0);
    const auto first_end = first_offset + (first_width / 2.0);
    const auto second_start = second_offset - (second_width / 2.0);
    const auto second_end = second_offset + (second_width / 2.0);
    return first_start < second_end && second_start < first_end;
}

bool near(double first, double second) {
    return std::abs(first - second) < 1.0e-9;
}

bool is_horizontal(const Line2& line) {
    return near(line.start.y, line.end.y) && !near(line.start.x, line.end.x);
}

bool is_vertical(const Line2& line) {
    return near(line.start.x, line.end.x) && !near(line.start.y, line.end.y);
}

double min_x(const Line2& line) {
    return std::min(line.start.x, line.end.x);
}

double max_x(const Line2& line) {
    return std::max(line.start.x, line.end.x);
}

double min_y(const Line2& line) {
    return std::min(line.start.y, line.end.y);
}

double max_y(const Line2& line) {
    return std::max(line.start.y, line.end.y);
}

struct IntervalWallRef {
    ElementId wall_id{};
    double fixed{};
    double range_min{};
    double range_max{};
};

struct RoomCandidate {
    std::vector<ElementId> boundary_wall_ids{};
    // One wall id for every boundary edge in boundary_polygon. Keeping this
    // parallel array lets the interior offset use the curved wall's actual
    // thickness instead of guessing from its endpoint chord.
    std::vector<ElementId> boundary_edge_wall_ids{};
    std::vector<Point2> boundary_polygon{};
    double area_square_meters{};
    double perimeter_meters{};
    ElementId level_id{};
};

struct GraphWallRef {
    ElementId id{};
    const WallData* wall{};
};

bool interval_covered(double query_min, double query_max, double range_min, double range_max) {
    return query_min >= (range_min - epsilon) && query_max <= (range_max + epsilon);
}

std::vector<Point2> simplify_polygon(std::vector<Point2> polygon) {
    if (polygon.size() <= 2) {
        return polygon;
    }

    std::vector<Point2> simplified;
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto previous = polygon[(index + polygon.size() - 1) % polygon.size()];
        const auto current = polygon[index];
        const auto next = polygon[(index + 1) % polygon.size()];

        const auto collinear_x = near(previous.x, current.x) && near(current.x, next.x);
        const auto collinear_y = near(previous.y, current.y) && near(current.y, next.y);
        if (collinear_x || collinear_y) {
            continue;
        }
        simplified.push_back(current);
    }
    return simplified;
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

double polygon_area(const std::vector<Point2>& polygon) {
    return std::abs(polygon_signed_area(polygon));
}

std::vector<RoomCandidate> graph_room_candidates(
    const std::vector<GraphWallRef>& walls,
    ElementId level_id) {
    constexpr auto endpoint_tolerance = 0.35;
    if (walls.size() < 3) {
        return {};
    }

    struct Endpoint {
        Point2 point{};
        std::size_t wall_index{};
        bool is_start{};
    };
    std::vector<Endpoint> endpoints;
    endpoints.reserve(walls.size() * 2);
    for (std::size_t index = 0; index < walls.size(); ++index) {
        if (walls[index].wall == nullptr || length(walls[index].wall->axis) <= epsilon) {
            continue;
        }
        endpoints.push_back(Endpoint{
            .point = walls[index].wall->axis.start,
            .wall_index = index,
            .is_start = true,
        });
        endpoints.push_back(Endpoint{
            .point = walls[index].wall->axis.end,
            .wall_index = index,
            .is_start = false,
        });
    }
    if (endpoints.size() < 6) {
        return {};
    }

    std::vector<std::size_t> parent(endpoints.size());
    std::iota(parent.begin(), parent.end(), 0);
    const auto find_root = [&](std::size_t value, const auto& self) -> std::size_t {
        if (parent[value] == value) {
            return value;
        }
        parent[value] = self(parent[value], self);
        return parent[value];
    };
    const auto unite = [&](std::size_t first, std::size_t second) {
        auto first_root = find_root(first, find_root);
        auto second_root = find_root(second, find_root);
        if (first_root != second_root) {
            parent[second_root] = first_root;
        }
    };

    // Exact/shared endpoints are always the same graph node. Join metadata is
    // also honoured so a small, explicitly repaired gap remains connected
    // without merging nearby parallel walls that merely look close on touch.
    for (std::size_t first = 0; first < endpoints.size(); ++first) {
        for (std::size_t second = first + 1; second < endpoints.size(); ++second) {
            if (same_point(endpoints[first].point, endpoints[second].point)) {
                unite(first, second);
            }
        }
    }

    std::map<ElementId, std::size_t> wall_index_by_id;
    for (std::size_t index = 0; index < walls.size(); ++index) {
        wall_index_by_id[walls[index].id] = index;
    }
    const auto endpoint_index = [&](std::size_t wall_index, Point2 point) -> std::optional<std::size_t> {
        std::optional<std::size_t> best;
        auto best_distance = endpoint_tolerance;
        for (std::size_t index = 0; index < endpoints.size(); ++index) {
            if (endpoints[index].wall_index != wall_index) {
                continue;
            }
            const auto distance = std::hypot(
                endpoints[index].point.x - point.x,
                endpoints[index].point.y - point.y);
            if (distance <= best_distance) {
                best_distance = distance;
                best = index;
            }
        }
        return best;
    };
    for (std::size_t index = 0; index < walls.size(); ++index) {
        const auto* wall = walls[index].wall;
        if (wall == nullptr) {
            continue;
        }
        for (const auto& join : wall->joins) {
            const auto other = wall_index_by_id.find(join.other_wall_id);
            if (other == wall_index_by_id.end()) {
                continue;
            }
            const auto first_endpoint = endpoint_index(index, join.point);
            const auto second_endpoint = endpoint_index(other->second, join.point);
            if (first_endpoint.has_value() && second_endpoint.has_value()) {
                unite(*first_endpoint, *second_endpoint);
            }
        }
    }

    struct GraphNode {
        Point2 point{};
    };
    std::map<std::size_t, std::size_t> node_by_root;
    std::vector<GraphNode> nodes;
    std::vector<std::size_t> endpoint_nodes(endpoints.size());
    for (std::size_t index = 0; index < endpoints.size(); ++index) {
        const auto root = find_root(index, find_root);
        const auto [it, inserted] = node_by_root.emplace(root, nodes.size());
        if (inserted) {
            nodes.push_back(GraphNode{.point = endpoints[index].point});
        }
        endpoint_nodes[index] = it->second;
    }

    struct HalfEdge {
        std::size_t from{};
        std::size_t to{};
        std::size_t twin{};
        ElementId wall_id{};
        std::vector<Point2> path{};
    };
    std::vector<HalfEdge> half_edges;
    std::vector<std::vector<std::size_t>> outgoing(nodes.size());
    for (std::size_t wall_index = 0; wall_index < walls.size(); ++wall_index) {
        const auto start = std::find_if(
            endpoints.begin(), endpoints.end(), [&](const auto& endpoint) {
                return endpoint.wall_index == wall_index && endpoint.is_start;
            });
        const auto end = std::find_if(
            endpoints.begin(), endpoints.end(), [&](const auto& endpoint) {
                return endpoint.wall_index == wall_index && !endpoint.is_start;
            });
        if (start == endpoints.end() || end == endpoints.end()) {
            continue;
        }
        const auto from = endpoint_nodes[static_cast<std::size_t>(std::distance(endpoints.begin(), start))];
        const auto to = endpoint_nodes[static_cast<std::size_t>(std::distance(endpoints.begin(), end))];
        if (from == to) {
            continue;
        }
        const auto forward = half_edges.size();
        const auto path = wall_path_points(*walls[wall_index].wall);
        half_edges.push_back(HalfEdge{
            .from = from,
            .to = to,
            .twin = forward + 1,
            .wall_id = walls[wall_index].id,
            .path = path,
        });
        half_edges.push_back(HalfEdge{
            .from = to,
            .to = from,
            .twin = forward,
            .wall_id = walls[wall_index].id,
            .path = std::vector<Point2>(path.rbegin(), path.rend()),
        });
        outgoing[from].push_back(forward);
        outgoing[to].push_back(forward + 1);
    }

    for (auto& edges : outgoing) {
        std::sort(edges.begin(), edges.end(), [&](std::size_t first, std::size_t second) {
            const auto& first_edge = half_edges[first];
            const auto& second_edge = half_edges[second];
            const auto first_direction = first_edge.path.size() >= 2
                ? subtract(first_edge.path[1], first_edge.path[0])
                : subtract(nodes[first_edge.to].point, nodes[first_edge.from].point);
            const auto second_direction = second_edge.path.size() >= 2
                ? subtract(second_edge.path[1], second_edge.path[0])
                : subtract(nodes[second_edge.to].point, nodes[second_edge.from].point);
            const auto first_angle = std::atan2(
                first_direction.y,
                first_direction.x);
            const auto second_angle = std::atan2(
                second_direction.y,
                second_direction.x);
            return first_angle < second_angle;
        });
    }

    std::vector<bool> visited(half_edges.size(), false);
    std::vector<RoomCandidate> candidates;
    for (std::size_t start_edge = 0; start_edge < half_edges.size(); ++start_edge) {
        if (visited[start_edge]) {
            continue;
        }
        std::vector<Point2> polygon;
        std::vector<ElementId> boundary_wall_ids;
        std::vector<ElementId> boundary_edge_wall_ids;
        auto current_edge = start_edge;
        auto closed = false;
        for (std::size_t guard = 0; guard <= half_edges.size() + 2; ++guard) {
            if (visited[current_edge]) {
                closed = current_edge == start_edge;
                break;
            }
            visited[current_edge] = true;
            const auto& edge = half_edges[current_edge];
            for (std::size_t path_index = 0; path_index < edge.path.size(); ++path_index) {
                const auto point = edge.path[path_index];
                if (polygon.empty() || !same_point(polygon.back(), point)) {
                    polygon.push_back(point);
                }
                if (path_index + 1 < edge.path.size()) {
                    boundary_edge_wall_ids.push_back(edge.wall_id);
                }
            }
            append_unique(boundary_wall_ids, edge.wall_id);

            const auto& next_edges = outgoing[edge.to];
            const auto reverse = edge.twin;
            const auto reverse_it = std::find(next_edges.begin(), next_edges.end(), reverse);
            if (reverse_it == next_edges.end() || next_edges.empty()) {
                break;
            }
            const auto reverse_index = static_cast<std::size_t>(std::distance(next_edges.begin(), reverse_it));
            current_edge = next_edges[(reverse_index + next_edges.size() - 1) % next_edges.size()];
        }
        if (!closed || polygon.size() < 3 || boundary_wall_ids.size() < 3) {
            continue;
        }
        if (polygon.size() > 1 && same_point(polygon.front(), polygon.back())) {
            polygon.pop_back();
        }
        if (boundary_edge_wall_ids.size() != polygon.size()) {
            continue;
        }
        const auto signed_area = polygon_signed_area(polygon);
        // With the clockwise predecessor walk, bounded faces are CCW and the
        // unbounded exterior face is CW. Keeping only positive faces prevents
        // the outer shell from becoming a Room.
        if (signed_area <= 1.0e-6) {
            continue;
        }
        auto perimeter = 0.0;
        for (std::size_t index = 0; index < polygon.size(); ++index) {
            const auto& first = polygon[index];
            const auto& second = polygon[(index + 1) % polygon.size()];
            perimeter += std::hypot(second.x - first.x, second.y - first.y);
        }
        candidates.push_back(RoomCandidate{
            .boundary_wall_ids = std::move(boundary_wall_ids),
            .boundary_edge_wall_ids = std::move(boundary_edge_wall_ids),
            .boundary_polygon = std::move(polygon),
            .area_square_meters = signed_area,
            .perimeter_meters = perimeter,
            .level_id = level_id,
        });
    }
    return candidates;
}

double layered_assembly_total_thickness(const LayeredAssemblyData& assembly) {
    auto total = 0.0;
    for (const auto& layer : assembly.layers) {
        total += layer.thickness_meters;
    }
    return total;
}

Revision cache_assembly_revision(const LayeredAssemblyData* assembly) {
    return assembly == nullptr ? 0 : assembly->revision;
}

void assign_cache_material(MeshBuffer& mesh, ElementId material_id) {
    if (mesh.indices.empty()) {
        mesh.triangle_material_ids.clear();
        return;
    }
    mesh.triangle_material_ids.assign(mesh.indices.size() / 3, material_id);
}

bool rebind_envelope_material(
    GeneratedMeshCache& cache,
    MeshBuffer& active_mesh,
    bool active_is_layered,
    const LayeredAssemblyData* assembly
) {
    if (assembly == nullptr || cache.dirty || assembly->layers.empty()) {
        return false;
    }
    auto* mesh = !cache.mesh.indices.empty()
        ? &cache.mesh
        : (!active_is_layered && !active_mesh.indices.empty() ? &active_mesh : nullptr);
    if (mesh == nullptr) {
        return false;
    }
    assign_cache_material(*mesh, assembly->layers.front().material_id);
    cache.assembly_revision = assembly->revision;
    return true;
}

void normalize_wall_layer_semantics(
    std::vector<WallAssemblyLayer>& layers,
    int& core_start_layer,
    int& core_end_layer
) {
    for (auto& layer : layers) {
        if (layer.side == WallLayerSide::Unspecified) {
            if (layer.function == WallLayerFunction::ExteriorFinish) {
                layer.side = WallLayerSide::Exterior;
            } else if (layer.function == WallLayerFunction::InteriorFinish) {
                layer.side = WallLayerSide::Interior;
            }
        }
    }

    if (core_start_layer >= 0 || core_end_layer >= 0) {
        // An explicit core boundary is authoritative. Keep the function
        // flags and the indices consistent so downstream geometry,
        // quantities, and UI all read the same semantic contract.
        if (core_start_layer >= 0 && core_end_layer >= core_start_layer &&
            core_end_layer < static_cast<int>(layers.size())) {
            for (std::size_t index = 0; index < layers.size(); ++index) {
                if (static_cast<int>(index) >= core_start_layer &&
                    static_cast<int>(index) <= core_end_layer) {
                    layers[index].function = WallLayerFunction::Core;
                } else if (layers[index].function == WallLayerFunction::Core) {
                    layers[index].function = WallLayerFunction::Generic;
                }
            }
        }
        return;
    }

    int first_core = -1;
    int last_core = -1;
    for (std::size_t index = 0; index < layers.size(); ++index) {
        if (layers[index].function != WallLayerFunction::Core) {
            continue;
        }
        if (first_core < 0) {
            first_core = static_cast<int>(index);
        }
        last_core = static_cast<int>(index);
    }
    core_start_layer = first_core;
    core_end_layer = last_core;
}

void normalize_layered_assembly_semantics(LayeredAssemblyData& assembly) {
    normalize_wall_layer_semantics(
        assembly.layers,
        assembly.core_start_layer,
        assembly.core_end_layer
    );
}

std::string material_category_label(MaterialCategory category) {
    switch (category) {
    case MaterialCategory::Structural: return "Structural";
    case MaterialCategory::Finish: return "Finish";
    case MaterialCategory::Insulation: return "Insulation";
    case MaterialCategory::Glass: return "Glass";
    case MaterialCategory::Generic: return "Generic";
    }
    return "Generic";
}

bool cyclic_polygon_equal(const std::vector<Point2>& first, const std::vector<Point2>& second) {
    if (first.size() != second.size()) {
        return false;
    }
    if (first.empty()) {
        return true;
    }

    for (std::size_t offset = 0; offset < second.size(); ++offset) {
        auto matches_forward = true;
        for (std::size_t index = 0; index < first.size(); ++index) {
            if (!same_point(first[index], second[(index + offset) % second.size()])) {
                matches_forward = false;
                break;
            }
        }
        if (matches_forward) {
            return true;
        }

        auto matches_reverse = true;
        for (std::size_t index = 0; index < first.size(); ++index) {
            const auto reverse_index = (offset + second.size() - index) % second.size();
            if (!same_point(first[index], second[reverse_index])) {
                matches_reverse = false;
                break;
            }
        }
        if (matches_reverse) {
            return true;
        }
    }

    return false;
}

constexpr auto default_ceiling_height_offset_meters = 2.6;

double normalized_ceiling_height_offset(double value) {
    return std::abs(value) < epsilon ? default_ceiling_height_offset_meters : value;
}

bool has_duplicate_points(const std::vector<Point2>& points) {
    for (std::size_t index = 0; index < points.size(); ++index) {
        for (std::size_t other = index + 1; other < points.size(); ++other) {
            if (same_point(points[index], points[other])) {
                return true;
            }
        }
    }
    return false;
}

bool polygon_has_self_intersection(const std::vector<Point2>& polygon) {
    if (polygon.size() < 4) {
        return false;
    }
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const Line2 first{
            .start = polygon[index],
            .end = polygon[(index + 1) % polygon.size()],
        };
        for (std::size_t other = index + 1; other < polygon.size(); ++other) {
            const auto first_next = (index + 1) % polygon.size();
            const auto other_next = (other + 1) % polygon.size();
            if (index == other || first_next == other || other_next == index) {
                continue;
            }
            const Line2 second{
                .start = polygon[other],
                .end = polygon[other_next],
            };
            const auto intersection = segment_intersection(first, second);
            if (intersection.has_value()) {
                return true;
            }
        }
    }
    return false;
}

struct PickWallLoopResult {
    std::vector<Point2> polygon{};
    std::vector<ElementId> ordered_wall_ids{};
};

PickWallLoopResult build_pick_wall_loop(
    const Document& document,
    const std::vector<ElementId>& picked_wall_ids
) {
    if (picked_wall_ids.size() < 3) {
        throw std::invalid_argument("pick-walls profile needs at least 3 walls");
    }

    struct LoopWallRef {
        ElementId wall_id{};
        Point2 start{};
        Point2 end{};
        std::vector<Point2> path{};
        std::size_t start_node{};
        std::size_t end_node{};
    };

    std::vector<Point2> nodes;
    auto find_or_add_node = [&](Point2 point) {
        for (std::size_t index = 0; index < nodes.size(); ++index) {
            if (same_point(nodes[index], point)) {
                return index;
            }
        }
        nodes.push_back(point);
        return nodes.size() - 1;
    };

    std::vector<LoopWallRef> walls;
    walls.reserve(picked_wall_ids.size());
    for (const auto wall_id : picked_wall_ids) {
        if (std::find_if(
                walls.begin(),
                walls.end(),
                [wall_id](const LoopWallRef& wall) { return wall.wall_id == wall_id; }) != walls.end()) {
            throw std::invalid_argument("pick-walls profile contains duplicate walls");
        }
        const auto* wall_element = document.find_ptr(wall_id);
        const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
        if (wall == nullptr) {
            throw std::invalid_argument("pick-walls profile references a non-wall element");
        }
        const auto start_node = find_or_add_node(wall->axis.start);
        const auto end_node = find_or_add_node(wall->axis.end);
        if (start_node == end_node) {
            throw std::invalid_argument("pick-walls profile contains a zero-length wall");
        }
        walls.push_back(LoopWallRef{
            .wall_id = wall_id,
            .start = wall->axis.start,
            .end = wall->axis.end,
            .path = wall_path_points(*wall),
            .start_node = start_node,
            .end_node = end_node,
        });
    }

    std::vector<std::vector<std::size_t>> adjacency(nodes.size());
    for (std::size_t index = 0; index < walls.size(); ++index) {
        adjacency[walls[index].start_node].push_back(index);
        adjacency[walls[index].end_node].push_back(index);
    }
    for (const auto& connected : adjacency) {
        if (connected.size() != 2) {
            throw std::invalid_argument("pick-walls profile must form one connected closed loop");
        }
    }

    std::vector<bool> visited(walls.size(), false);
    std::vector<ElementId> ordered_wall_ids;
    std::vector<Point2> polygon;
    ordered_wall_ids.reserve(walls.size());
    polygon.reserve(walls.size());

    std::size_t current_wall_index = 0;
    std::size_t current_node = walls[current_wall_index].start_node;
    const auto start_node = current_node;
    for (std::size_t step = 0; step < walls.size(); ++step) {
        if (visited[current_wall_index]) {
            throw std::invalid_argument("pick-walls profile contains an ambiguous or repeated loop");
        }
        visited[current_wall_index] = true;
        const auto& wall = walls[current_wall_index];
        const auto append_path_point = [&](Point2 point) {
            if (polygon.empty() || !same_point(polygon.back(), point)) {
                polygon.push_back(point);
            }
        };
        if (wall.start_node == current_node) {
            for (const auto point : wall.path) append_path_point(point);
        } else {
            for (auto point = wall.path.rbegin(); point != wall.path.rend(); ++point) {
                append_path_point(*point);
            }
        }
        ordered_wall_ids.push_back(wall.wall_id);

        const auto next_node = wall.start_node == current_node ? wall.end_node : wall.start_node;
        const auto& connected = adjacency[next_node];
        const auto next_wall_it = std::find_if(
            connected.begin(),
            connected.end(),
            [&](std::size_t candidate) { return candidate != current_wall_index; });
        current_node = next_node;
        if (step + 1 == walls.size()) {
            if (current_node != start_node) {
                throw std::invalid_argument("pick-walls profile does not close back to its start");
            }
            continue;
        }
        if (next_wall_it == connected.end()) {
            throw std::invalid_argument("pick-walls profile became disconnected while ordering walls");
        }
        current_wall_index = *next_wall_it;
    }

    if (polygon.size() > 1 && same_point(polygon.front(), polygon.back())) {
        polygon.pop_back();
    }

    if (std::find(visited.begin(), visited.end(), false) != visited.end()) {
        throw std::invalid_argument("pick-walls profile must be a single simple loop");
    }

    polygon = simplify_polygon(std::move(polygon));
    if (polygon.size() < 3 || has_duplicate_points(polygon) || polygon_has_self_intersection(polygon)) {
        throw std::invalid_argument("pick-walls profile produced an invalid closed boundary");
    }
    if (polygon_signed_area(polygon) < 0.0) {
        std::reverse(polygon.begin(), polygon.end());
        std::reverse(ordered_wall_ids.begin(), ordered_wall_ids.end());
    }
    return PickWallLoopResult{
        .polygon = std::move(polygon),
        .ordered_wall_ids = std::move(ordered_wall_ids),
    };
}

void validate_profile_polygon(
    const std::vector<Point2>& polygon,
    ProfileTargetKind target_kind
) {
    const auto target_label = [target_kind]() -> const char* {
        switch (target_kind) {
        case ProfileTargetKind::WallPath: return "wall";
        case ProfileTargetKind::FloorBoundary: return "floor";
        case ProfileTargetKind::CeilingBoundary: return "ceiling";
        case ProfileTargetKind::RoofBoundary: return "roof";
        }
        return "profile";
    }();

    if (polygon.size() < 3) {
        throw std::invalid_argument(std::string(target_label) + " profile needs at least 3 unique points");
    }
    if (has_duplicate_points(polygon)) {
        throw std::invalid_argument(std::string(target_label) + " profile contains duplicate points");
    }
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const Line2 edge{
            .start = polygon[index],
            .end = polygon[(index + 1) % polygon.size()],
        };
        if (length(edge) <= epsilon) {
            throw std::invalid_argument(std::string(target_label) + " profile contains a too-short edge");
        }
    }
    if (polygon_has_self_intersection(polygon)) {
        throw std::invalid_argument(std::string(target_label) + " profile self-intersects");
    }
    if (polygon_area(polygon) <= epsilon) {
        throw std::invalid_argument(std::string(target_label) + " profile must enclose a positive area");
    }
}

MeshBuffer extrude_polygon_mesh(const std::vector<Point2>& polygon, double thickness, double elevation_offset) {
    MeshBuffer mesh;
    const auto vertex_count = polygon.size();
    if (vertex_count < 3 || thickness <= 0.0) {
        return mesh;
    }

    for (const auto& point : polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = elevation_offset});
    }
    for (const auto& point : polygon) {
        mesh.vertices.push_back(Point3{.x = point.x, .y = point.y, .z = elevation_offset + thickness});
    }

    const auto top_triangles = triangulate_simple_polygon(polygon);
    for (std::size_t index = 0; index + 2 < top_triangles.size(); index += 3) {
        const auto first = top_triangles[index];
        const auto second = top_triangles[index + 1];
        const auto third = top_triangles[index + 2];
        mesh.indices.push_back(first);
        mesh.indices.push_back(second);
        mesh.indices.push_back(third);

        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + third));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + second));
        mesh.indices.push_back(static_cast<std::uint32_t>(vertex_count + first));
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

MeshBuffer build_layered_slab_mesh(
    const std::vector<Point2>& polygon,
    const LayeredAssemblyData& assembly,
    double elevation_offset
) {
    MeshBuffer mesh;
    auto layer_elevation = elevation_offset;
    for (const auto& layer : assembly.layers) {
        const auto layer_mesh = extrude_polygon_mesh(polygon, layer.thickness_meters, layer_elevation);
        const auto vertex_offset = static_cast<std::uint32_t>(mesh.vertices.size());
        mesh.vertices.insert(mesh.vertices.end(), layer_mesh.vertices.begin(), layer_mesh.vertices.end());
        for (const auto index : layer_mesh.indices) {
            mesh.indices.push_back(vertex_offset + index);
        }
        mesh.triangle_material_ids.insert(
            mesh.triangle_material_ids.end(),
            layer_mesh.indices.size() / 3,
            layer.material_id
        );
        layer_elevation += layer.thickness_meters;
    }
    return mesh;
}

MeshBuffer build_gable_roof_mesh(const RoofData& roof, double thickness);
MeshBuffer build_auto_footprint_roof_mesh(const RoofData& roof, double thickness);

void append_mesh_with_material(
    MeshBuffer& target,
    const MeshBuffer& source,
    double z_offset,
    ElementId material_id
) {
    const auto vertex_offset = static_cast<std::uint32_t>(target.vertices.size());
    target.vertices.reserve(target.vertices.size() + source.vertices.size());
    for (const auto& vertex : source.vertices) {
        target.vertices.push_back(Point3{
            .x = vertex.x,
            .y = vertex.y,
            .z = vertex.z + z_offset,
        });
    }
    target.indices.reserve(target.indices.size() + source.indices.size());
    for (const auto index : source.indices) {
        target.indices.push_back(vertex_offset + index);
    }
    target.triangle_material_ids.insert(
        target.triangle_material_ids.end(),
        source.indices.size() / 3,
        material_id
    );
}

MeshBuffer build_layered_roof_mesh(
    const RoofData& roof,
    const LayeredAssemblyData& assembly
) {
    MeshBuffer mesh;
    auto layer_offset = 0.0;
    for (const auto& layer : assembly.layers) {
        RoofData layer_roof = roof;
        layer_roof.thickness_meters = layer.thickness_meters;
        const auto layer_mesh = layer_roof.roof_type == RoofType::Flat
            ? extrude_polygon_mesh(layer_roof.boundary_polygon, layer.thickness_meters, 0.0)
            : layer_roof.roof_type == RoofType::SimpleGable
                ? build_gable_roof_mesh(layer_roof, layer.thickness_meters)
                : build_auto_footprint_roof_mesh(layer_roof, layer.thickness_meters);
        append_mesh_with_material(mesh, layer_mesh, layer_offset, layer.material_id);
        layer_offset += layer.thickness_meters;
    }
    return mesh;
}

bool valid_gable_profile(const std::vector<Point2>& polygon) {
    if (polygon.size() != 4 || polygon_has_self_intersection(polygon)) return false;
    double min_x = polygon.front().x, max_x = min_x, min_y = polygon.front().y, max_y = min_y;
    for (const auto& point : polygon) {
        min_x = std::min(min_x, point.x); max_x = std::max(max_x, point.x);
        min_y = std::min(min_y, point.y); max_y = std::max(max_y, point.y);
    }
    return cyclic_polygon_equal(polygon, {{min_x, min_y}, {max_x, min_y}, {max_x, max_y}, {min_x, max_y}});
}

MeshBuffer build_gable_roof_mesh(const RoofData& roof, double thickness);

std::optional<std::vector<Point2>> offset_roof_boundary(const std::vector<Point2>& polygon, double offset) {
    if (polygon.size() < 3) {
        return std::nullopt;
    }
    if (std::abs(offset) <= epsilon) {
        return polygon;
    }
    const auto ccw = polygon_signed_area(polygon) > 0.0;
    std::vector<Line2> shifted;
    shifted.reserve(polygon.size());
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto start = polygon[index];
        const auto end = polygon[(index + 1) % polygon.size()];
        const auto direction = unit_direction(Line2{.start = start, .end = end});
        const auto outward = ccw
            ? Point2{.x = direction.y, .y = -direction.x}
            : Point2{.x = -direction.y, .y = direction.x};
        const auto shift = scale(outward, offset);
        shifted.push_back(Line2{.start = add(start, shift), .end = add(end, shift)});
    }

    std::vector<Point2> result;
    result.reserve(polygon.size());
    for (std::size_t index = 0; index < shifted.size(); ++index) {
        const auto& previous = shifted[(index + shifted.size() - 1) % shifted.size()];
        const auto& current = shifted[index];
        const auto first_direction = subtract(previous.end, previous.start);
        const auto second_direction = subtract(current.end, current.start);
        const auto denominator = (first_direction.x * second_direction.y) - (first_direction.y * second_direction.x);
        if (std::abs(denominator) <= epsilon) {
            return std::nullopt;
        }
        const auto delta = subtract(current.start, previous.start);
        const auto t = ((delta.x * second_direction.y) - (delta.y * second_direction.x)) / denominator;
        result.push_back(add(previous.start, scale(first_direction, t)));
    }
    if (result.size() < 3 || polygon_has_self_intersection(result) ||
        polygon_signed_area(result) * polygon_signed_area(polygon) <= epsilon) {
        return std::nullopt;
    }
    // A concave footprint can remain formally simple after an inward offset
    // even though one of its wavefront edges has already collapsed and
    // reversed.  That is the first straight-skeleton event, so reject it and
    // let the binary search stop before the topology changes.
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto original = subtract(polygon[(index + 1) % polygon.size()], polygon[index]);
        const auto shifted_edge = subtract(result[(index + 1) % result.size()], result[index]);
        if ((original.x * shifted_edge.x) + (original.y * shifted_edge.y) <= epsilon) {
            return std::nullopt;
        }
    }
    return result;
}

std::vector<std::array<std::size_t, 3>> triangulate_roof_boundary(std::vector<Point2> polygon) {
    if (polygon_signed_area(polygon) < 0.0) {
        std::reverse(polygon.begin(), polygon.end());
    }
    std::vector<std::size_t> remaining(polygon.size());
    std::iota(remaining.begin(), remaining.end(), 0);
    std::vector<std::array<std::size_t, 3>> triangles;
    const auto point_in_triangle = [](Point2 point, Point2 a, Point2 b, Point2 c) {
        const auto ab = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
        const auto bc = (c.x - b.x) * (point.y - b.y) - (c.y - b.y) * (point.x - b.x);
        const auto ca = (a.x - c.x) * (point.y - c.y) - (a.y - c.y) * (point.x - c.x);
        return ab >= -epsilon && bc >= -epsilon && ca >= -epsilon;
    };
    while (remaining.size() > 3) {
        bool clipped = false;
        for (std::size_t index = 0; index < remaining.size(); ++index) {
            const auto previous = remaining[(index + remaining.size() - 1) % remaining.size()];
            const auto current = remaining[index];
            const auto next = remaining[(index + 1) % remaining.size()];
            const auto& a = polygon[previous];
            const auto& b = polygon[current];
            const auto& c = polygon[next];
            const auto cross_value = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
            if (cross_value <= epsilon) {
                continue;
            }
            const auto contains_other = std::any_of(remaining.begin(), remaining.end(), [&](std::size_t candidate) {
                return candidate != previous && candidate != current && candidate != next &&
                    point_in_triangle(polygon[candidate], a, b, c);
            });
            if (contains_other) {
                continue;
            }
            triangles.push_back({previous, current, next});
            remaining.erase(remaining.begin() + static_cast<std::ptrdiff_t>(index));
            clipped = true;
            break;
        }
        if (!clipped) {
            return {};
        }
    }
    if (remaining.size() == 3) {
        triangles.push_back({remaining[0], remaining[1], remaining[2]});
    }
    return triangles;
}

std::optional<std::pair<std::vector<Point2>, double>> build_roof_plateau(
    const std::vector<Point2>& boundary
) {
    auto shortest_edge = std::numeric_limits<double>::max();
    for (std::size_t index = 0; index < boundary.size(); ++index) {
        shortest_edge = std::min(shortest_edge, length(Line2{
            .start = boundary[index], .end = boundary[(index + 1) % boundary.size()]
        }));
    }
    if (!std::isfinite(shortest_edge) || shortest_edge <= epsilon) {
        return std::nullopt;
    }

    // Move every eave inwards together.  The largest simple inset is the
    // first straight-skeleton event; stopping just before it creates a small
    // ridge/valley plateau and works for convex, L, U and irregular simple
    // footprints without ever fanning triangles through a concave notch.
    auto low = 0.0;
    auto high = shortest_edge;
    for (int iteration = 0; iteration < 40; ++iteration) {
        const auto candidate_distance = (low + high) * 0.5;
        const auto candidate = offset_roof_boundary(boundary, -candidate_distance);
        if (candidate.has_value() && std::abs(polygon_signed_area(*candidate)) > epsilon) {
            low = candidate_distance;
        } else {
            high = candidate_distance;
        }
    }
    if (low <= epsilon) {
        return std::nullopt;
    }
    const auto plateau_distance = low * 0.94;
    const auto plateau = offset_roof_boundary(boundary, -plateau_distance);
    if (!plateau.has_value()) {
        return std::nullopt;
    }
    return std::make_pair(*plateau, plateau_distance);
}

MeshBuffer build_auto_footprint_roof_mesh(const RoofData& roof, double thickness) {
    if (roof.boundary_polygon.size() < 3 || !roof.slope_degrees.has_value()) {
        return {};
    }

    const auto boundary = offset_roof_boundary(roof.boundary_polygon, roof.overhang_meters.value_or(0.0));
    if (!boundary.has_value()) {
        return {};
    }
    const auto plateau = build_roof_plateau(*boundary);
    if (!plateau.has_value()) {
        return {};
    }
    const auto& eaves = *boundary;
    const auto& ridge = plateau->first;
    const auto eave_triangles = triangulate_roof_boundary(eaves);
    const auto ridge_triangles = triangulate_roof_boundary(ridge);
    if (eave_triangles.empty() || ridge_triangles.empty() || eaves.size() != ridge.size()) {
        return {};
    }
    const auto rise = plateau->second * std::tan(*roof.slope_degrees * 3.14159265358979323846 / 180.0);
    if (rise <= epsilon) {
        return {};
    }

    MeshBuffer mesh;
    const auto count = static_cast<std::uint32_t>(eaves.size());
    mesh.vertices.reserve((count * 3) + ridge_triangles.size() * 3);
    // Bottom eaves, top eaves and the raised, footprint-derived ridge loop.
    for (const auto& point : eaves) mesh.vertices.push_back({point.x, point.y, 0.0});
    for (const auto& point : eaves) mesh.vertices.push_back({point.x, point.y, thickness});
    for (const auto& point : ridge) mesh.vertices.push_back({point.x, point.y, thickness + rise});
    const auto top_eave = count;
    const auto ridge_base = count * 2;

    for (const auto& triangle : eave_triangles) {
        mesh.indices.insert(mesh.indices.end(), {
            static_cast<std::uint32_t>(triangle[0]),
            static_cast<std::uint32_t>(triangle[2]),
            static_cast<std::uint32_t>(triangle[1]),
        });
    }
    for (std::uint32_t index = 0; index < count; ++index) {
        const auto next = (index + 1) % count;
        // Fascia at the eave.
        mesh.indices.insert(mesh.indices.end(), {
            index, next, top_eave + next,
            index, top_eave + next, top_eave + index,
        });
        // One true slope face per footprint edge.  The inner edge is a
        // parallel offset, so its rise/distance is exactly tan(slope).
        mesh.indices.insert(mesh.indices.end(), {
            top_eave + index, top_eave + next, ridge_base + next,
            top_eave + index, ridge_base + next, ridge_base + index,
        });
    }
    for (const auto& triangle : ridge_triangles) {
        mesh.indices.insert(mesh.indices.end(), {
            ridge_base + static_cast<std::uint32_t>(triangle[0]),
            ridge_base + static_cast<std::uint32_t>(triangle[1]),
            ridge_base + static_cast<std::uint32_t>(triangle[2]),
        });
    }
    return mesh;
}

double triangle_area(Point3 first, Point3 second, Point3 third) {
    const auto ab = Point3{.x = second.x - first.x, .y = second.y - first.y, .z = second.z - first.z};
    const auto ac = Point3{.x = third.x - first.x, .y = third.y - first.y, .z = third.z - first.z};
    const Point3 cross_product{
        .x = (ab.y * ac.z) - (ab.z * ac.y),
        .y = (ab.z * ac.x) - (ab.x * ac.z),
        .z = (ab.x * ac.y) - (ab.y * ac.x),
    };
    return 0.5 * std::sqrt(
        (cross_product.x * cross_product.x) +
        (cross_product.y * cross_product.y) +
        (cross_product.z * cross_product.z)
    );
}

double auto_roof_surface_area(const RoofData& roof, double thickness) {
    const auto mesh = build_auto_footprint_roof_mesh(roof, thickness);
    auto area = 0.0;
    for (std::size_t index = 0; index + 2 < mesh.indices.size(); index += 3) {
        const auto& first = mesh.vertices[mesh.indices[index]];
        const auto& second = mesh.vertices[mesh.indices[index + 1]];
        const auto& third = mesh.vertices[mesh.indices[index + 2]];
        if (first.z >= thickness - epsilon && second.z >= thickness - epsilon && third.z >= thickness - epsilon) {
            area += triangle_area(first, second, third);
        }
    }
    return area;
}

MeshBuffer build_gable_roof_mesh(const RoofData& roof, double thickness) {
    if (!valid_gable_profile(roof.boundary_polygon) || !roof.slope_degrees.has_value()) return {};
    double min_x = roof.boundary_polygon.front().x, max_x = min_x, min_y = roof.boundary_polygon.front().y, max_y = min_y;
    for (const auto& point : roof.boundary_polygon) {
        min_x = std::min(min_x, point.x); max_x = std::max(max_x, point.x);
        min_y = std::min(min_y, point.y); max_y = std::max(max_y, point.y);
    }
    const auto dx = max_x - min_x, dy = max_y - min_y;
    const auto rise = std::min(dx, dy) * 0.5 * std::tan(*roof.slope_degrees * 3.14159265358979323846 / 180.0);
    if (rise <= epsilon) return {};
    MeshBuffer mesh;
    if (dx >= dy) {
        mesh.vertices = {{min_x,min_y,0},{max_x,min_y,0},{max_x,max_y,0},{min_x,max_y,0},{min_x,min_y,thickness},{max_x,min_y,thickness},{max_x,max_y,thickness},{min_x,max_y,thickness},{min_x,(min_y+max_y)*0.5,thickness+rise},{max_x,(min_y+max_y)*0.5,thickness+rise}};
        mesh.indices = {0,2,1,0,3,2,0,1,5,0,5,4,3,7,6,3,6,2,0,4,8,0,8,3,3,8,7,1,2,9,1,9,5,2,6,9,4,5,9,4,9,8,7,8,9,7,9,6};
    } else {
        mesh.vertices = {{min_x,min_y,0},{max_x,min_y,0},{max_x,max_y,0},{min_x,max_y,0},{min_x,min_y,thickness},{max_x,min_y,thickness},{max_x,max_y,thickness},{min_x,max_y,thickness},{(min_x+max_x)*0.5,min_y,thickness+rise},{(min_x+max_x)*0.5,max_y,thickness+rise}};
        mesh.indices = {0,2,1,0,3,2,0,1,5,0,5,4,3,7,6,3,6,2,0,4,8,0,8,1,1,8,5,3,2,9,3,9,7,2,6,9,4,7,9,4,9,8,5,8,9,5,9,6};
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

MeshBuffer extrude_column_mesh(Point2 center, double width, double depth, double height) {
    return extrude_polygon_mesh(rectangle_polygon(center, width, depth), height, 0.0);
}

MeshBuffer extrude_beam_mesh(Point2 start, Point2 end, double width, double height) {
    const auto beam_length = length(Line2{.start = start, .end = end});
    if (beam_length <= epsilon || width <= 0.0 || height <= 0.0) {
        return {};
    }
    const auto direction = unit_direction(Line2{.start = start, .end = end});
    const auto normal = scale(perpendicular_left(direction), width / 2.0);
    std::vector<Point2> polygon{
        add(start, normal),
        add(end, normal),
        add(end, scale(normal, -1.0)),
        add(start, scale(normal, -1.0)),
    };
    return extrude_polygon_mesh(polygon, height, 0.0);
}

MeshBuffer build_straight_stair_mesh(const StairData& stair) {
    if (stair.width_meters <= 0.0 || stair.total_run_meters <= 0.0 || stair.total_rise_meters <= 0.0) {
        return {};
    }
    const auto direction_length = std::sqrt((stair.direction.x * stair.direction.x) + (stair.direction.y * stair.direction.y));
    if (direction_length <= epsilon) {
        return {};
    }
    const auto unit = Point2{.x = stair.direction.x / direction_length, .y = stair.direction.y / direction_length};
    // A staircase is one watertight stepped solid, rather than a stack of
    // overlapping boxes.  The old approach left coplanar internal faces in
    // Solid view (the visual "many boxes" effect) and spent O(n²) welding
    // them.  This emits only exterior tread/riser/side faces in O(n).
    MeshBuffer mesh;
    const auto step_count = std::max(1, stair.tread_count);
    const auto tread = stair.total_run_meters / static_cast<double>(step_count);
    const auto rise = stair.total_rise_meters / static_cast<double>(step_count);
    const auto normal = scale(perpendicular_left(unit), stair.width_meters / 2.0);
    const auto point_at = [&](double run, double side, double height) {
        const auto plan = add(add(stair.start, scale(unit, run)), scale(normal, side));
        return Point3{.x = plan.x, .y = plan.y, .z = height};
    };
    const auto add_quad = [&](Point3 a, Point3 b, Point3 c, Point3 d) {
        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        mesh.vertices.insert(mesh.vertices.end(), {a, b, c, d});
        mesh.indices.insert(mesh.indices.end(), {base, base + 1, base + 2, base, base + 2, base + 3});
    };

    // Build one continuous stair-shaped side profile. The old implementation
    // emitted a full-height side panel for every tread, which looked like a
    // row of boxes. This profile is a single monolithic wedge with a sloped
    // underside and the stepped top contour.
    std::vector<Point3> side_profile;
    side_profile.reserve(static_cast<std::size_t>(step_count) + 3);
    side_profile.push_back(point_at(0.0, -1.0, 0.0));
    side_profile.push_back(point_at(stair.total_run_meters, -1.0, stair.total_rise_meters));
    for (int step = step_count - 1; step >= 0; --step) {
        const auto run = tread * static_cast<double>(step);
        const auto height = rise * static_cast<double>(step + 1);
        side_profile.push_back(point_at(run, -1.0, height));
    }
    const auto side_base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.insert(mesh.vertices.end(), side_profile.begin(), side_profile.end());
    for (std::uint32_t index = 1; index + 1 < side_profile.size(); ++index) {
        mesh.indices.insert(mesh.indices.end(), {side_base, side_base + index, side_base + index + 1});
    }

    std::vector<Point3> opposite_profile;
    opposite_profile.reserve(side_profile.size());
    for (const auto& point : side_profile) {
        const auto run = ((point.x - stair.start.x) * unit.x) + ((point.y - stair.start.y) * unit.y);
        opposite_profile.push_back(point_at(run, 1.0, point.z));
    }
    const auto opposite_base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.insert(mesh.vertices.end(), opposite_profile.begin(), opposite_profile.end());
    for (std::uint32_t index = 1; index + 1 < opposite_profile.size(); ++index) {
        mesh.indices.insert(mesh.indices.end(), {opposite_base, opposite_base + index + 1, opposite_base + index});
    }

    // One sloped underside closes the monolithic wedge.
    add_quad(point_at(0.0, 1.0, 0.0), point_at(stair.total_run_meters, 1.0, stair.total_rise_meters),
             point_at(stair.total_run_meters, -1.0, stair.total_rise_meters), point_at(0.0, -1.0, 0.0));
    add_quad(point_at(0.0, -1.0, 0.0), point_at(0.0, 1.0, 0.0),
             point_at(0.0, 1.0, rise), point_at(0.0, -1.0, rise));

    for (int step = 0; step < step_count; ++step) {
        const auto run_start = tread * static_cast<double>(step);
        const auto run_end = tread * static_cast<double>(step + 1);
        const auto lower = rise * static_cast<double>(step);
        const auto upper = rise * static_cast<double>(step + 1);
        // Tread and riser are the only horizontal/vertical exterior faces.
        add_quad(point_at(run_start, -1.0, upper), point_at(run_start, 1.0, upper),
                 point_at(run_end, 1.0, upper), point_at(run_end, -1.0, upper));
        if (step > 0) {
            add_quad(point_at(run_start, -1.0, lower), point_at(run_start, 1.0, lower),
                     point_at(run_start, 1.0, upper), point_at(run_start, -1.0, upper));
        }
    }
    return mesh;
}

void append_mesh_with_z_offset(MeshBuffer& target, const MeshBuffer& source, double z_offset) {
    const auto vertex_base = static_cast<std::uint32_t>(target.vertices.size());
    target.vertices.reserve(target.vertices.size() + source.vertices.size());
    for (const auto& vertex : source.vertices) {
        target.vertices.push_back(Point3{.x = vertex.x, .y = vertex.y, .z = vertex.z + z_offset});
    }
    target.indices.reserve(target.indices.size() + source.indices.size());
    for (const auto index : source.indices) {
        target.indices.push_back(vertex_base + index);
    }
}

void append_oriented_box(
    MeshBuffer& mesh,
    Point2 center,
    Point2 direction,
    double width,
    double depth,
    double z0,
    double z1
) {
    const auto direction_length = std::hypot(direction.x, direction.y);
    if (direction_length <= epsilon || width <= epsilon || depth <= epsilon || z1 <= z0 + epsilon) {
        return;
    }
    const auto unit = Point2{.x = direction.x / direction_length, .y = direction.y / direction_length};
    const auto normal = perpendicular_left(unit);
    const auto half_width = width / 2.0;
    const auto half_depth = depth / 2.0;
    const auto corner = [&](double along, double across, double z) {
        const auto plan = add(add(center, scale(unit, along)), scale(normal, across));
        return Point3{.x = plan.x, .y = plan.y, .z = z};
    };
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.insert(mesh.vertices.end(), {
        corner(-half_width, -half_depth, z0), corner(half_width, -half_depth, z0),
        corner(half_width, half_depth, z0), corner(-half_width, half_depth, z0),
        corner(-half_width, -half_depth, z1), corner(half_width, -half_depth, z1),
        corner(half_width, half_depth, z1), corner(-half_width, half_depth, z1),
    });
    mesh.indices.insert(mesh.indices.end(), {
        base + 0, base + 2, base + 1, base + 0, base + 3, base + 2,
        base + 4, base + 5, base + 6, base + 4, base + 6, base + 7,
        base + 0, base + 1, base + 5, base + 0, base + 5, base + 4,
        base + 1, base + 2, base + 6, base + 1, base + 6, base + 5,
        base + 2, base + 3, base + 7, base + 2, base + 7, base + 6,
        base + 3, base + 0, base + 4, base + 3, base + 4, base + 7,
    });
}

MeshBuffer build_stair_mesh(const StairData& stair) {
    if (stair.layout_kind == StairLayoutKind::Straight || stair.path_points.size() < 3) {
        return build_straight_stair_mesh(stair);
    }
    MeshBuffer mesh;
    double total_path = 0.0;
    for (std::size_t index = 1; index < stair.path_points.size(); ++index) {
        total_path += std::hypot(
            stair.path_points[index].x - stair.path_points[index - 1].x,
            stair.path_points[index].y - stair.path_points[index - 1].y
        );
    }
    if (total_path <= epsilon || stair.total_rise_meters <= epsilon) {
        return {};
    }
    const auto total_steps = std::max(1, stair.tread_count);
    auto steps_used = 0;
    auto current_rise = 0.0;
    for (std::size_t index = 1; index < stair.path_points.size(); ++index) {
        const auto start = stair.path_points[index - 1];
        const auto end = stair.path_points[index];
        const auto run = std::hypot(end.x - start.x, end.y - start.y);
        if (run <= epsilon) continue;
        const auto remaining_segments = static_cast<int>(stair.path_points.size() - index - 1);
        const auto proportional_steps = static_cast<int>(std::lround(
            static_cast<double>(total_steps) * run / total_path
        ));
        const auto steps_left = total_steps - steps_used;
        const auto step_count = index + 1 == stair.path_points.size()
            ? std::max(1, steps_left)
            : std::max(1, std::min(proportional_steps, steps_left - remaining_segments));
        StairData flight = stair;
        flight.layout_kind = StairLayoutKind::Straight;
        flight.path_points.clear();
        flight.start = start;
        flight.direction = Point2{.x = end.x - start.x, .y = end.y - start.y};
        flight.total_run_meters = run;
        flight.total_rise_meters = stair.total_rise_meters * run / total_path;
        flight.tread_count = step_count;
        flight.riser_count = step_count;
        append_mesh_with_z_offset(mesh, build_straight_stair_mesh(flight), current_rise);
        current_rise += flight.total_rise_meters;
        steps_used += step_count;

        if (index + 1 < stair.path_points.size()) {
            const auto next = stair.path_points[index + 1];
            const auto landing_direction = Point2{.x = next.x - end.x, .y = next.y - end.y};
            append_oriented_box(
                mesh,
                end,
                landing_direction,
                stair.width_meters,
                std::max(stair.landing_depth_meters, stair.width_meters),
                current_rise - 0.08,
                current_rise
            );
        }
    }

    if (stair.railing_enabled) {
        // Lightweight architectural railing: posts and segmented top rails
        // follow every flight, avoiding a second semantic object per post.
        current_rise = 0.0;
        for (std::size_t index = 1; index < stair.path_points.size(); ++index) {
            const auto start = stair.path_points[index - 1];
            const auto end = stair.path_points[index];
            const auto run = std::hypot(end.x - start.x, end.y - start.y);
            if (run <= epsilon) continue;
            const auto direction = Point2{.x = (end.x - start.x) / run, .y = (end.y - start.y) / run};
            const auto normal = perpendicular_left(direction);
            const auto flight_rise = stair.total_rise_meters * run / total_path;
            const auto rail_offset = stair.width_meters / 2.0 + 0.06;
            const auto post_count = std::max(2, static_cast<int>(std::ceil(run / 1.5)) + 1);
            for (int post = 0; post < post_count; ++post) {
                const auto t = static_cast<double>(post) / static_cast<double>(post_count - 1);
                const auto position = Point2{
                    .x = start.x + (end.x - start.x) * t,
                    .y = start.y + (end.y - start.y) * t,
                };
                const auto z = current_rise + flight_rise * t;
                for (const auto side : {-1.0, 1.0}) {
                    append_oriented_box(
                        mesh,
                        add(position, scale(normal, rail_offset * side)),
                        direction,
                        0.06,
                        0.06,
                        z,
                        z + 0.92
                    );
                }
            }
            const auto rail_segments = std::max(1, static_cast<int>(std::ceil(run / 0.8)));
            for (int rail = 0; rail < rail_segments; ++rail) {
                const auto t0 = static_cast<double>(rail) / rail_segments;
                const auto t1 = static_cast<double>(rail + 1) / rail_segments;
                const auto mid = (t0 + t1) / 2.0;
                const auto position = Point2{
                    .x = start.x + (end.x - start.x) * mid,
                    .y = start.y + (end.y - start.y) * mid,
                };
                const auto z = current_rise + flight_rise * mid + 0.92;
                for (const auto side : {-1.0, 1.0}) {
                    append_oriented_box(mesh, add(position, scale(normal, rail_offset * side)), direction, run / rail_segments + 0.04, 0.07, z - 0.035, z + 0.035);
                }
            }
            current_rise += flight_rise;
        }
    }
    return mesh;
}

MeshBuffer build_layered_stair_mesh(
    const StairData& stair,
    const LayeredAssemblyData& assembly
) {
    // Stair layer thickness is a material build-up property; it must not be
    // interpreted as extra rise, which would duplicate the whole staircase
    // vertically. Keep one watertight stair solid and expose the assembly's
    // core material on its triangles. The semantic layer list remains
    // available to quantity/documentation consumers.
    auto mesh = build_stair_mesh(stair);
    if (mesh.indices.empty() || assembly.layers.empty()) {
        return mesh;
    }
    auto material_id = assembly.layers.front().material_id;
    if (assembly.core_start_layer >= 0 &&
        assembly.core_start_layer < static_cast<int>(assembly.layers.size())) {
        material_id = assembly.layers[static_cast<std::size_t>(assembly.core_start_layer)].material_id;
    }
    mesh.triangle_material_ids.assign(mesh.indices.size() / 3, material_id);
    return mesh;
}

double roof_plan_area(const RoofData& roof) {
    return polygon_area(roof.boundary_polygon);
}

double roof_surface_area(const RoofData& roof) {
    const auto plan_area = roof_plan_area(roof);
    if (roof.roof_type == RoofType::AutoFootprint && roof.slope_degrees.has_value()) {
        const auto surface = auto_roof_surface_area(roof, roof.thickness_meters);
        if (surface > epsilon) {
            return surface;
        }
    }
    if (roof.roof_type == RoofType::SimpleGable && roof.slope_degrees.has_value()) {
        const auto radians = (*roof.slope_degrees) * 3.14159265358979323846 / 180.0;
        const auto cosine = std::cos(radians);
        if (std::abs(cosine) > epsilon) {
            return plan_area / cosine;
        }
    }
    return plan_area;
}

} // namespace

Document::Document(std::string name)
    : name_(std::move(name)) {
    if (name_.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }
}

std::string_view Document::name() const noexcept {
    return name_;
}

const UnitSettings& Document::unit_settings() const noexcept {
    return unit_settings_;
}

void Document::set_unit_settings(UnitSettings settings) {
    unit_settings_ = std::move(settings);
}

void Document::rename(std::string name) {
    if (name.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }

    name_ = std::move(name);
}

ElementId Document::create_material(
    std::string name,
    MaterialCategory category,
    std::optional<double> density_kg_per_m3,
    std::optional<double> unit_cost,
    std::map<std::string, std::string> metadata,
    std::string display_color
) {
    if (name.empty()) {
        throw std::invalid_argument("material name must not be empty");
    }

    const auto material_id = allocate_id();
    materials_[material_id] = MaterialDefinition{
        .material_id = material_id,
        .name = std::move(name),
        .category = category,
        .density_kg_per_m3 = density_kg_per_m3,
        .unit_cost = unit_cost,
        .display_color = display_color.empty() ? "#B0B7C3" : std::move(display_color),
        .metadata = std::move(metadata),
    };
    return material_id;
}

const MaterialDefinition* Document::get_material(ElementId material_id) const noexcept {
    const auto found = materials_.find(material_id);
    return found == materials_.end() ? nullptr : &found->second;
}

void Document::update_material(MaterialDefinition material) {
    if (material.material_id == 0 || material.name.empty()) {
        throw std::invalid_argument("material definition is invalid");
    }
    if (material.category == MaterialCategory::Glass) {
        const auto uses_material = [&](const auto& layers) {
            return std::any_of(layers.begin(), layers.end(), [&](const auto& layer) {
                return layer.material_id == material.material_id;
            });
        };
        const auto hosted_opening = std::find_if(elements_.begin(), elements_.end(), [&](const auto& element) {
            const auto* wall = element.wall();
            if (wall == nullptr || wall->openings.empty()) {
                return false;
            }
            if (wall->wall_type_id != 0) {
                const auto* wall_type = get_wall_type(wall->wall_type_id);
                if (wall_type != nullptr && uses_material(wall_type->layers)) {
                    return true;
                }
            }
            if (wall->assembly_id != 0) {
                const auto* assembly = get_layered_assembly(wall->assembly_id);
                if (assembly != nullptr && assembly->kind == LayeredAssemblyKind::Wall && uses_material(assembly->layers)) {
                    return true;
                }
            }
            return false;
        });
        if (hosted_opening != elements_.end()) {
            throw std::invalid_argument("a material used by a wall with hosted openings cannot be changed to glass");
        }
    }
    materials_[material.material_id] = std::move(material);
    invalidate_dependency_graph_cache();
}

ElementId Document::create_wall_type(std::string name, std::vector<WallAssemblyLayer> layers, WallTypeCategory category) {
    if (name.empty()) {
        throw std::invalid_argument("wall type name must not be empty");
    }
    if (layers.empty()) {
        throw std::invalid_argument("wall type must contain layers");
    }

    for (const auto& layer : layers) {
        if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("wall type layer thickness must be positive");
        }
    }

    const auto wall_type_id = allocate_id();
    WallTypeData wall_type{
        .wall_type_id = wall_type_id,
        .name = std::move(name),
        .category = category,
        .layers = std::move(layers),
    };
    normalize_wall_layer_semantics(
        wall_type.layers,
        wall_type.core_start_layer,
        wall_type.core_end_layer
    );
    wall_types_[wall_type_id] = std::move(wall_type);
    return wall_type_id;
}

const WallTypeData* Document::get_wall_type(ElementId wall_type_id) const noexcept {
    const auto found = wall_types_.find(wall_type_id);
    return found == wall_types_.end() ? nullptr : &found->second;
}

void Document::update_wall_type(WallTypeData wall_type) {
    if (wall_type.wall_type_id == 0 || wall_type.name.empty() || wall_type.layers.empty()) {
        throw std::invalid_argument("wall type is invalid");
    }
    for (const auto& layer : wall_type.layers) {
        if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("wall type layer thickness must be positive");
        }
    }
    normalize_wall_layer_semantics(
        wall_type.layers,
        wall_type.core_start_layer,
        wall_type.core_end_layer
    );
    if (wall_type.core_start_layer < -1 || wall_type.core_end_layer < -1 ||
        (wall_type.core_start_layer < 0) != (wall_type.core_end_layer < 0) ||
        (wall_type.core_start_layer >= 0 &&
         (wall_type.core_start_layer > wall_type.core_end_layer ||
          wall_type.core_end_layer >= static_cast<int>(wall_type.layers.size())))) {
        throw std::invalid_argument("wall type core layer range is invalid");
    }
    const auto wall_type_id = wall_type.wall_type_id;
    if (wall_type_uses_glass(wall_type)) {
        const auto hosted_opening = std::find_if(elements_.begin(), elements_.end(), [&](const auto& element) {
            const auto* wall = element.wall();
            return wall != nullptr && wall->wall_type_id == wall_type_id && !wall->openings.empty();
        });
        if (hosted_opening != elements_.end()) {
            throw std::invalid_argument("a glass wall type cannot be assigned while the wall has hosted openings");
        }
    }
    const auto previous = get_wall_type(wall_type_id);
    const auto previous_thickness = previous == nullptr ? -1.0 : total_wall_type_thickness(*previous);
    // The interactive envelope only depends on the total wall thickness.
    // Splitting that thickness into more layers is a detailed-cache change,
    // not a reason to rebuild the lightweight viewport mesh.
    const auto envelope_geometry_changed = previous == nullptr ||
        std::abs(previous_thickness - total_wall_type_thickness(wall_type)) > epsilon;
    const auto layered_geometry_changed = envelope_geometry_changed || previous == nullptr ||
        previous->core_start_layer != wall_type.core_start_layer ||
        previous->core_end_layer != wall_type.core_end_layer ||
        previous->layers.size() != wall_type.layers.size() ||
        std::any_of(previous->layers.begin(), previous->layers.end(), [&](const auto& layer) {
            const auto index = static_cast<std::size_t>(&layer - previous->layers.data());
            if (index >= wall_type.layers.size()) {
                return true;
            }
            const auto& next_layer = wall_type.layers[index];
            return layer.material_id != next_layer.material_id ||
                layer.function != next_layer.function ||
                layer.priority != next_layer.priority ||
                layer.structural != next_layer.structural ||
                layer.side != next_layer.side ||
                layer.wraps_openings != next_layer.wraps_openings ||
                layer.wraps_ends != next_layer.wraps_ends ||
                std::abs(layer.thickness_meters - next_layer.thickness_meters) > epsilon;
        });
    wall_types_[wall_type.wall_type_id] = std::move(wall_type);
    const auto total_thickness = total_wall_type_thickness(wall_types_.at(wall_type_id));
    for (auto& element : elements_) {
        if (auto* wall = element.wall(); wall != nullptr && wall->wall_type_id == wall_type_id) {
            if (layered_geometry_changed) {
                wall->layered_geometry.dirty = true;
            }
            if (envelope_geometry_changed) {
                wall->thickness_meters = total_thickness;
                mark_wall_dirty(element);
            }
        }
    }
    invalidate_dependency_graph_cache();
}

ElementId Document::create_layered_assembly(LayeredAssemblyKind kind, std::string name, std::vector<WallAssemblyLayer> layers) {
    if (name.empty() || layers.empty()) {
        throw std::invalid_argument("layered assembly is invalid");
    }
    for (const auto& layer : layers) {
        if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("assembly layer thickness must be positive");
        }
    }

    const auto assembly_id = allocate_id();
    LayeredAssemblyData assembly{
        .assembly_id = assembly_id,
        .kind = kind,
        .name = std::move(name),
        .layers = std::move(layers),
        .revision = 1,
    };
    normalize_layered_assembly_semantics(assembly);
    layered_assemblies_[assembly_id] = std::move(assembly);
    invalidate_dependency_graph_cache();
    return assembly_id;
}

const LayeredAssemblyData* Document::get_layered_assembly(ElementId assembly_id) const noexcept {
    const auto found = layered_assemblies_.find(assembly_id);
    return found == layered_assemblies_.end() ? nullptr : &found->second;
}

void Document::update_layered_assembly(LayeredAssemblyData assembly) {
    if (assembly.assembly_id == 0 || assembly.name.empty() || assembly.layers.empty()) {
        throw std::invalid_argument("layered assembly is invalid");
    }
    for (const auto& layer : assembly.layers) {
        if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("assembly layer thickness must be positive");
        }
    }
    normalize_layered_assembly_semantics(assembly);
    if (assembly.core_start_layer < -1 || assembly.core_end_layer < -1 ||
        (assembly.core_start_layer < 0) != (assembly.core_end_layer < 0) ||
        (assembly.core_start_layer >= 0 &&
         (assembly.core_start_layer > assembly.core_end_layer ||
          assembly.core_end_layer >= static_cast<int>(assembly.layers.size())))) {
        throw std::invalid_argument("assembly core layer range is invalid");
    }
    const auto assembly_id = assembly.assembly_id;
    if (assembly.kind == LayeredAssemblyKind::Wall && layered_assembly_uses_glass(assembly)) {
        const auto hosted_opening = std::find_if(elements_.begin(), elements_.end(), [&](const auto& element) {
            const auto* wall = element.wall();
            return wall != nullptr && wall->assembly_id == assembly_id && !wall->openings.empty();
        });
        if (hosted_opening != elements_.end()) {
            throw std::invalid_argument("a glass wall assembly cannot be assigned while the wall has hosted openings");
        }
    }
    const auto previous = get_layered_assembly(assembly_id);
    const auto previous_thickness = previous == nullptr ? -1.0 : layered_assembly_total_thickness(*previous);
    const auto next_thickness = layered_assembly_total_thickness(assembly);
    // The interactive envelope only depends on the total wall thickness.
    // Changes to the layer split stay in the detailed cache and are loaded
    // only by a section/documentation request.
    const auto envelope_geometry_changed = previous == nullptr ||
        std::abs(previous_thickness - next_thickness) > epsilon;
    const auto layered_geometry_changed = envelope_geometry_changed || previous == nullptr ||
        previous->core_start_layer != assembly.core_start_layer ||
        previous->core_end_layer != assembly.core_end_layer ||
        previous->layers.size() != assembly.layers.size() ||
        std::any_of(previous->layers.begin(), previous->layers.end(), [&](const auto& layer) {
            const auto index = static_cast<std::size_t>(&layer - previous->layers.data());
            if (index >= assembly.layers.size()) {
                return true;
            }
            const auto& next_layer = assembly.layers[index];
            return layer.material_id != next_layer.material_id ||
                layer.function != next_layer.function ||
                layer.priority != next_layer.priority ||
                layer.structural != next_layer.structural ||
                layer.side != next_layer.side ||
                layer.wraps_openings != next_layer.wraps_openings ||
                layer.wraps_ends != next_layer.wraps_ends ||
                std::abs(layer.thickness_meters - next_layer.thickness_meters) > epsilon;
        });
    assembly.revision = previous == nullptr
        ? 1
        : (layered_geometry_changed ? previous->revision + 1 : previous->revision);
    const auto assembly_was_missing = previous == nullptr;
    layered_assemblies_[assembly_id] = std::move(assembly);
    const auto& stored_assembly = layered_assemblies_.at(assembly_id);
    for (auto& element : elements_) {
        if (auto* wall = element.wall(); wall != nullptr && wall->assembly_id == assembly_id) {
            const auto preserve_loaded_envelope = assembly_was_missing &&
                !wall->geometry.dirty && !wall->geometry.mesh.indices.empty();
            if (layered_geometry_changed) {
                wall->layered_geometry.dirty = true;
            }
            if (envelope_geometry_changed) {
                wall->thickness_meters = layered_assembly_total_thickness(stored_assembly);
                if (preserve_loaded_envelope) {
                    wall->geometry.assembly_revision = stored_assembly.revision;
                } else {
                    mark_wall_dirty(element);
                }
            }
        } else if (auto* slab = element.slab(); slab != nullptr && slab->assembly_id == assembly_id) {
            const auto preserve_loaded_envelope = assembly_was_missing &&
                !slab->generated_geometry_dirty && !slab->envelope_geometry.dirty &&
                (!slab->envelope_geometry.mesh.indices.empty() || !slab->mesh.indices.empty());
            if (layered_geometry_changed) {
                slab->layered_geometry.dirty = true;
                if ((preserve_loaded_envelope || !envelope_geometry_changed) &&
                    rebind_envelope_material(
                        slab->envelope_geometry,
                        slab->mesh,
                        slab->geometry_is_layered,
                        &stored_assembly
                    )) {
                    if (!slab->geometry_is_layered && !slab->envelope_geometry.mesh.indices.empty()) {
                        slab->mesh = slab->envelope_geometry.mesh;
                    }
                }
                if (preserve_loaded_envelope) {
                    slab->envelope_geometry.dirty = false;
                } else {
                    slab->envelope_geometry.dirty = slab->envelope_geometry.dirty || envelope_geometry_changed;
                    slab->generated_geometry_dirty = slab->generated_geometry_dirty || envelope_geometry_changed;
                }
                element.touch();
            }
        } else if (auto* roof = element.roof(); roof != nullptr && roof->assembly_id == assembly_id) {
            const auto preserve_loaded_envelope = assembly_was_missing &&
                !roof->generated_geometry_dirty && !roof->envelope_geometry.dirty &&
                (!roof->envelope_geometry.mesh.indices.empty() || !roof->mesh.indices.empty());
            if (layered_geometry_changed) {
                roof->layered_geometry.dirty = true;
                if ((preserve_loaded_envelope || !envelope_geometry_changed) &&
                    rebind_envelope_material(
                        roof->envelope_geometry,
                        roof->mesh,
                        roof->geometry_is_layered,
                        &stored_assembly
                    )) {
                    if (!roof->geometry_is_layered && !roof->envelope_geometry.mesh.indices.empty()) {
                        roof->mesh = roof->envelope_geometry.mesh;
                    }
                }
                if (preserve_loaded_envelope) {
                    roof->envelope_geometry.dirty = false;
                } else {
                    roof->envelope_geometry.dirty = roof->envelope_geometry.dirty || envelope_geometry_changed;
                    roof->generated_geometry_dirty = roof->generated_geometry_dirty || envelope_geometry_changed;
                }
                element.touch();
            }
        } else if (auto* stair = element.stair(); stair != nullptr && stair->assembly_id == assembly_id) {
            const auto preserve_loaded_envelope = assembly_was_missing &&
                !stair->generated_geometry_dirty && !stair->envelope_geometry.dirty &&
                (!stair->envelope_geometry.mesh.indices.empty() || !stair->mesh.indices.empty());
            if (layered_geometry_changed) {
                stair->layered_geometry.dirty = true;
                if ((preserve_loaded_envelope || !envelope_geometry_changed) &&
                    rebind_envelope_material(
                        stair->envelope_geometry,
                        stair->mesh,
                        stair->geometry_is_layered,
                        &stored_assembly
                    )) {
                    if (!stair->geometry_is_layered && !stair->envelope_geometry.mesh.indices.empty()) {
                        stair->mesh = stair->envelope_geometry.mesh;
                    }
                }
                if (preserve_loaded_envelope) {
                    stair->envelope_geometry.dirty = false;
                } else {
                    stair->envelope_geometry.dirty = stair->envelope_geometry.dirty || envelope_geometry_changed;
                    stair->generated_geometry_dirty = stair->generated_geometry_dirty || envelope_geometry_changed;
                }
                element.touch();
            }
        }
    }
    invalidate_dependency_graph_cache();
}

ElementId Document::create_level(std::string name, double elevation_meters, double default_wall_height_meters) {
    if (name.empty()) {
        throw std::invalid_argument("level name must not be empty");
    }
    if (!std::isfinite(elevation_meters)) {
        throw std::invalid_argument("level elevation must be finite");
    }
    if (!std::isfinite(default_wall_height_meters) || default_wall_height_meters <= 0.0) {
        throw std::invalid_argument("default wall height must be positive");
    }
    for (const auto& element : elements_) {
        const auto* existing = element.level();
        if (existing != nullptr &&
            std::abs(existing->elevation_meters - elevation_meters) <= epsilon) {
            throw std::invalid_argument("level elevations must be unique");
        }
    }

    const auto id = allocate_id();
    const auto level_name = name;
    elements_.emplace_back(id, ElementKind::Level, std::move(name), LevelData{
        .name = level_name,
        .elevation_meters = elevation_meters,
        .default_wall_height_meters = default_wall_height_meters,
    });
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_wall(
    std::string name,
    Line2 axis,
    double thickness_meters,
    double height_meters,
    ElementId level_id,
    ElementId assembly_id,
    ElementId wall_type_id
) {
    if (name.empty()) {
        throw std::invalid_argument("wall name must not be empty");
    }
    validate_wall_axis(axis, thickness_meters, height_meters);
    if (level_id != 0) {
        (void)require_level(level_id);
    }
    if (assembly_id != 0) {
        const auto* assembly = get_layered_assembly(assembly_id);
        if (assembly == nullptr || assembly->kind != LayeredAssemblyKind::Wall) {
            throw std::invalid_argument("wall assembly must exist and have Wall kind");
        }
        if (wall_type_id != 0) {
            throw std::invalid_argument("wall cannot use both a wall type and an assembly");
        }
        // Wall-kind assemblies are a load-time compatibility format. Convert
        // them immediately so a newly authored wall never carries a second
        // composition source beside WallTypeData.
        wall_type_id = wall_type_for_assembly(*assembly);
        assembly_id = 0;
        thickness_meters = total_wall_type_thickness(*get_wall_type(wall_type_id));
        validate_wall_axis(axis, thickness_meters, height_meters);
    }
    if (wall_type_id != 0) {
        const auto* wall_type = get_wall_type(wall_type_id);
        if (wall_type == nullptr) {
            throw std::invalid_argument("wall type does not exist");
        }
        thickness_meters = total_wall_type_thickness(*wall_type);
        validate_wall_axis(axis, thickness_meters, height_meters);
    }

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Wall, std::move(name), WallData{
        .level_id = level_id,
        .base_level_id = level_id,
        .wall_type_id = wall_type_id,
        .assembly_id = assembly_id,
        .axis = axis,
        .thickness_meters = thickness_meters,
        .height_meters = height_meters,
    });
    if (level_id != 0) {
        dirty_room_level_ids_.push_back(level_id);
    }
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_curved_wall(
    std::string name,
    Line2 chord,
    WallArcData arc,
    double thickness_meters,
    double height_meters,
    ElementId level_id,
    ElementId assembly_id,
    ElementId wall_type_id
) {
    if (name.empty()) {
        throw std::invalid_argument("wall name must not be empty");
    }
    validate_wall_axis(chord, thickness_meters, height_meters);
    const auto distance_to_center = [&](Point2 point) {
        return std::hypot(point.x - arc.center.x, point.y - arc.center.y);
    };
    if (!std::isfinite(arc.center.x) || !std::isfinite(arc.center.y) ||
        !std::isfinite(arc.radius_meters) || !std::isfinite(arc.start_angle_radians) ||
        !std::isfinite(arc.sweep_radians) || arc.radius_meters <= epsilon ||
        std::abs(arc.sweep_radians) <= epsilon ||
        std::abs(arc.sweep_radians) > (2.0 * std::numbers::pi) + 1.0e-6) {
        throw std::invalid_argument("curved wall arc geometry is invalid");
    }
    const auto endpoint_tolerance = std::max(1.0e-5, arc.radius_meters * 1.0e-4);
    if (std::abs(distance_to_center(chord.start) - arc.radius_meters) > endpoint_tolerance ||
        std::abs(distance_to_center(chord.end) - arc.radius_meters) > endpoint_tolerance) {
        throw std::invalid_argument("curved wall endpoints must lie on the arc");
    }
    if (level_id != 0) {
        (void)require_level(level_id);
    }
    if (assembly_id != 0) {
        const auto* assembly = get_layered_assembly(assembly_id);
        if (assembly == nullptr || assembly->kind != LayeredAssemblyKind::Wall) {
            throw std::invalid_argument("wall assembly must exist and have Wall kind");
        }
        if (wall_type_id != 0) {
            throw std::invalid_argument("wall cannot use both a wall type and an assembly");
        }
        wall_type_id = wall_type_for_assembly(*assembly);
        assembly_id = 0;
        thickness_meters = total_wall_type_thickness(*get_wall_type(wall_type_id));
        validate_wall_axis(chord, thickness_meters, height_meters);
    }
    if (wall_type_id != 0) {
        const auto* wall_type = get_wall_type(wall_type_id);
        if (wall_type == nullptr) {
            throw std::invalid_argument("wall type does not exist");
        }
        thickness_meters = total_wall_type_thickness(*wall_type);
        validate_wall_axis(chord, thickness_meters, height_meters);
    }

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Wall, std::move(name), WallData{
        .level_id = level_id,
        .base_level_id = level_id,
        .wall_type_id = wall_type_id,
        .assembly_id = assembly_id,
        .axis = chord,
        .thickness_meters = thickness_meters,
        .height_meters = height_meters,
        .arc = std::move(arc),
    });
    if (level_id != 0) {
        dirty_room_level_ids_.push_back(level_id);
    }
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    invalidate_dependency_graph_cache();
    return id;
}

void Document::set_wall_type(ElementId wall_id, ElementId wall_type_id) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (wall_type_id != 0 && get_wall_type(wall_type_id) == nullptr) {
        throw std::invalid_argument("wall type does not exist");
    }
    if (wall != nullptr && !wall->openings.empty() && wall_type_id != 0) {
        const auto* wall_type = get_wall_type(wall_type_id);
        if (wall_type != nullptr && wall_type_uses_glass(*wall_type)) {
            throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
        }
    }
    // A wall uses exactly one layered source at a time. This also clears a
    // legacy assembly when the user explicitly chooses Unassigned.
    wall->assembly_id = 0;
    wall->wall_type_id = wall_type_id;
    if (const auto* wall_type = get_wall_type(wall_type_id)) {
        wall->thickness_meters = total_wall_type_thickness(*wall_type);
    }
    mark_wall_dirty(wall_element);
    refresh_dependencies_for_wall(wall_id);
}

ElementId Document::wall_type_for_assembly(const LayeredAssemblyData& assembly) {
    const auto layers_equal = [](const auto& left, const auto& right) {
        if (left.size() != right.size()) return false;
        return std::equal(left.begin(), left.end(), right.begin(), [](const auto& first, const auto& second) {
            return first.material_id == second.material_id &&
                std::abs(first.thickness_meters - second.thickness_meters) <= epsilon &&
                first.function == second.function &&
                first.priority == second.priority &&
                first.structural == second.structural &&
                first.side == second.side &&
                first.wraps_openings == second.wraps_openings &&
                first.wraps_ends == second.wraps_ends;
        });
    };
    for (const auto& [wall_type_id, wall_type] : wall_types_) {
        if (wall_type.name == assembly.name && layers_equal(wall_type.layers, assembly.layers)) {
            return wall_type_id;
        }
    }
    return create_wall_type(assembly.name, assembly.layers, WallTypeCategory::Generic);
}

void Document::normalize_wall_type_sources() {
    const auto requires_normalization = std::any_of(elements_.begin(), elements_.end(), [&](const auto& element) {
        const auto* wall = element.wall();
        return wall != nullptr && (
            wall->assembly_id != 0 ||
            (wall->wall_type_id != 0 && get_wall_type(wall->wall_type_id) == nullptr) ||
            (wall->wall_type_id != 0 &&
             get_wall_type(wall->wall_type_id) != nullptr &&
             !wall->openings.empty() &&
             wall_type_uses_glass(*get_wall_type(wall->wall_type_id))));
    });
    if (!requires_normalization) return;

    std::set<ElementId> affected_levels;
    for (auto& element : elements_) {
        auto* wall = element.wall();
        if (wall == nullptr) continue;

        const auto* existing_type = wall->wall_type_id == 0
            ? nullptr
            : get_wall_type(wall->wall_type_id);
        const auto* assembly = wall->assembly_id == 0
            ? nullptr
            : get_layered_assembly(wall->assembly_id);
        const auto previous_wall_type_id = wall->wall_type_id;
        const auto previous_assembly_id = wall->assembly_id;
        const auto previous_thickness = wall->thickness_meters;

        if (existing_type != nullptr &&
            (!wall->openings.empty() && wall_type_uses_glass(*existing_type))) {
            // A corrupted/legacy file may have assigned a glass type before
            // opening validation existed. Keep the hosted openings usable and
            // drop only the invalid type reference; the wall envelope stays
            // intact until the user selects a solid type.
            wall->wall_type_id = 0;
            wall->assembly_id = 0;
        } else if (existing_type != nullptr) {
            wall->assembly_id = 0;
            wall->thickness_meters = total_wall_type_thickness(*existing_type);
        } else if (assembly != nullptr && assembly->kind == LayeredAssemblyKind::Wall) {
            if (!wall->openings.empty() && layered_assembly_uses_glass(*assembly)) {
                // Preserve a valid opening host instead of migrating an
                // invalid glass-wall assignment into WallTypeData.
                wall->wall_type_id = 0;
                wall->assembly_id = 0;
            } else {
                const auto wall_type_id = wall_type_for_assembly(*assembly);
                const auto* wall_type = get_wall_type(wall_type_id);
                wall->wall_type_id = wall_type_id;
                wall->assembly_id = 0;
                if (wall_type != nullptr) {
                    wall->thickness_meters = total_wall_type_thickness(*wall_type);
                }
            }
        } else {
            // A missing type/assembly must not remain as a dangling semantic
            // reference. Keep the authored envelope as an explicit generic
            // wall until the user assigns a catalog type.
            wall->wall_type_id = 0;
            wall->assembly_id = 0;
        }
        const auto changed = previous_wall_type_id != wall->wall_type_id ||
            previous_assembly_id != wall->assembly_id ||
            std::abs(previous_thickness - wall->thickness_meters) > epsilon;
        if (!changed) continue;
        wall->geometry.dirty = true;
        wall->layered_geometry.dirty = true;
        if (wall->level_id != 0) affected_levels.insert(wall->level_id);
    }
    for (auto& element : elements_) {
        auto* room = element.room();
        if (room == nullptr || !affected_levels.contains(room->level_id)) continue;
        dirty_room_ids_.push_back(element.id());
        element.touch();
    }
    for (auto& [_, system] : floor_systems_) {
        if (affected_levels.contains(system.level_id)) system.dirty = true;
    }
    for (auto& [_, system] : ceiling_systems_) {
        if (affected_levels.contains(system.level_id)) system.dirty = true;
    }
    invalidate_dependency_graph_cache();
}

ElementId Document::upsert_wall_type_for_wall(
    ElementId wall_id,
    std::string name,
    std::vector<WallAssemblyLayer> layers,
    WallTypeCategory category,
    int core_start_layer,
    int core_end_layer
) {
    auto& wall_element = require_wall(wall_id);
    if (layers.empty()) {
        throw std::invalid_argument("wall type must contain layers");
    }

    // Normalize omitted core bounds and layer sides before comparing or
    // storing the candidate. Otherwise the same layer stack could compare
    // differently merely because one caller supplied -1 and another supplied
    // the inferred core range, causing catalog growth over time.
    auto normalized_layers = layers;
    auto normalized_core_start = core_start_layer;
    auto normalized_core_end = core_end_layer;
    normalize_wall_layer_semantics(normalized_layers, normalized_core_start, normalized_core_end);

    // Reuse an existing semantically identical type before allocating a new
    // record. This makes repeated Inspector edits idempotent even when the
    // user changes away and back to a previous layer stack.
    auto layers_equal = [](const auto& left, const auto& right) {
        if (left.size() != right.size()) return false;
        return std::equal(left.begin(), left.end(), right.begin(), [](const auto& first, const auto& second) {
            return first.material_id == second.material_id &&
                std::abs(first.thickness_meters - second.thickness_meters) <= epsilon &&
                first.function == second.function &&
                first.priority == second.priority &&
                first.structural == second.structural &&
                first.side == second.side &&
                first.wraps_openings == second.wraps_openings &&
                first.wraps_ends == second.wraps_ends;
        });
    };

    const auto* wall = wall_element.wall();
    const auto current_type_id = wall == nullptr ? 0 : wall->wall_type_id;
    for (const auto& [candidate_id, candidate] : wall_types_) {
        if (candidate.category == category &&
            candidate.name == name &&
            candidate.core_start_layer == normalized_core_start &&
            candidate.core_end_layer == normalized_core_end &&
            layers_equal(candidate.layers, normalized_layers)) {
            set_wall_type(wall_id, candidate_id);
            return candidate_id;
        }
    }

    auto sole_user = current_type_id != 0 && get_wall_type(current_type_id) != nullptr;
    if (sole_user) {
        for (const auto& element : elements_) {
            const auto* other_wall = element.wall();
            if (other_wall != nullptr && element.id() != wall_id &&
                other_wall->wall_type_id == current_type_id) {
                sole_user = false;
                break;
            }
        }
    }

    if (sole_user) {
        auto edited = *get_wall_type(current_type_id);
        edited.name = std::move(name);
        edited.category = category;
        edited.layers = std::move(normalized_layers);
        edited.core_start_layer = normalized_core_start;
        edited.core_end_layer = normalized_core_end;
        update_wall_type(std::move(edited));
        return current_type_id;
    }

    auto created = create_wall_type(std::move(name), std::move(normalized_layers), category);
    auto edited = *get_wall_type(created);
    edited.core_start_layer = normalized_core_start;
    edited.core_end_layer = normalized_core_end;
    update_wall_type(std::move(edited));
    set_wall_type(wall_id, created);
    return created;
}

void Document::set_element_assembly(ElementId element_id, ElementId assembly_id) {
    const auto* assembly = get_layered_assembly(assembly_id);
    if (assembly == nullptr) throw std::invalid_argument("compound assembly does not exist");
    auto* element = find_ptr(element_id);
    if (element == nullptr) {
        // Floor systems are document-owned authoring records rather than
        // Element variants, but their stable IDs are exposed by the same
        // render-scene selection contract. Keep one assembly command for both
        // slab elements and generated/manual floor systems.
        const auto system = floor_systems_.find(element_id);
        if (system == floor_systems_.end()) {
            throw std::invalid_argument("element does not exist");
        }
        if (assembly->kind != LayeredAssemblyKind::Floor) {
            throw std::invalid_argument("floor system requires Floor assembly");
        }
        system->second.assembly_id = assembly_id;
        system->second.dirty = true;
        invalidate_dependency_graph_cache();
        return;
    }
    if (auto* wall = element->wall()) {
        if (assembly->kind != LayeredAssemblyKind::Wall) throw std::invalid_argument("wall requires Wall assembly");
        if (!wall->openings.empty() && layered_assembly_uses_glass(*assembly)) {
            throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
        }
        // Wall-kind assemblies are accepted only for old callers. Convert
        // them to the canonical wall-type store immediately; no active wall
        // is allowed to keep an assembly_id source.
        const auto wall_type_id = wall_type_for_assembly(*assembly);
        set_wall_type(element_id, wall_type_id);
    } else if (auto* slab = element->slab()) {
        if (assembly->kind != LayeredAssemblyKind::Floor) throw std::invalid_argument("slab requires Floor assembly");
        slab->assembly_id = assembly_id;
        slab->thickness_meters = layered_assembly_total_thickness(*assembly);
        slab->envelope_geometry.dirty = true;
        slab->layered_geometry.dirty = true;
        slab->generated_geometry_dirty = true;
        element->touch();
    } else if (auto* roof = element->roof()) {
        if (assembly->kind != LayeredAssemblyKind::Roof) throw std::invalid_argument("roof requires Roof assembly");
        roof->assembly_id = assembly_id;
        roof->thickness_meters = layered_assembly_total_thickness(*assembly);
        roof->envelope_geometry.dirty = true;
        roof->layered_geometry.dirty = true;
        roof->generated_geometry_dirty = true;
        element->touch();
    } else if (auto* stair = element->stair()) {
        if (assembly->kind != LayeredAssemblyKind::Stair) throw std::invalid_argument("stair requires Stair assembly");
        stair->assembly_id = assembly_id;
        stair->envelope_geometry.dirty = true;
        stair->layered_geometry.dirty = true;
        stair->generated_geometry_dirty = true;
        element->touch();
    } else {
        throw std::invalid_argument("element does not support compound assemblies");
    }
    invalidate_dependency_graph_cache();
}

void Document::set_element_family_reference(
    ElementId element_id,
    std::string family_asset_id,
    std::string family_name,
    std::string family_type_id,
    std::string family_type_name,
    std::string family_category,
    std::string family_asset_path
) {
    auto* element = find_ptr(element_id);
    if (element == nullptr) {
        throw std::invalid_argument("element does not exist");
    }
    if (family_asset_id.empty() || family_name.empty() || family_type_id.empty() ||
        family_type_name.empty() || family_category.empty()) {
        throw std::invalid_argument("family reference fields are required");
    }

    auto& metadata = element->metadata();
    metadata["family_asset_id"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = std::move(family_asset_id),
    };
    metadata["family_name"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = std::move(family_name),
    };
    metadata["family_type_id"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = std::move(family_type_id),
    };
    metadata["family_type_name"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = std::move(family_type_name),
    };
    metadata["family_category"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = std::move(family_category),
    };
    if (!family_asset_path.empty()) {
        metadata["family_asset_path"] = MetadataValue{
            .kind = MetadataValueKind::Text,
            .value = std::move(family_asset_path),
        };
    } else {
        metadata.erase("family_asset_path");
    }
    element->touch();
}

void Document::update_roof_properties(ElementId roof_id, RoofType roof_type, std::optional<double> slope_degrees, std::optional<double> overhang_meters) {
    auto* element = find_ptr(roof_id);
    auto* roof = element == nullptr ? nullptr : element->roof();
    if (roof == nullptr) throw std::invalid_argument("roof does not exist");
    if (roof_type == RoofType::SimpleGable && (!slope_degrees.has_value() || *slope_degrees <= 0.0 || *slope_degrees >= 75.0 || !valid_gable_profile(roof->boundary_polygon))) {
        throw std::invalid_argument("simple gable requires rectangular profile and 0-75 degree slope");
    }
    if (roof_type == RoofType::AutoFootprint && (!slope_degrees.has_value() || *slope_degrees <= 0.0 || *slope_degrees >= 75.0 || polygon_has_self_intersection(roof->boundary_polygon))) {
        throw std::invalid_argument("automatic footprint roof requires a simple profile and 0-75 degree slope");
    }
    if (overhang_meters.has_value() && *overhang_meters < 0.0) throw std::invalid_argument("roof overhang cannot be negative");
    roof->roof_type = roof_type;
    roof->slope_degrees = slope_degrees;
    roof->overhang_meters = overhang_meters;
    roof->generated_geometry_dirty = true;
    element->touch();
}

void Document::set_beam_column_join(ElementId beam_id, ElementId column_id, bool enabled) {
    const auto* beam = find_ptr(beam_id);
    const auto* column = find_ptr(column_id);
    if (beam == nullptr || beam->beam() == nullptr || column == nullptr || column->column() == nullptr) {
        throw std::invalid_argument("join requires a beam and a column");
    }
    const auto relation = std::make_pair(beam_id, column_id);
    const auto found = std::find(beam_column_joins_.begin(), beam_column_joins_.end(), relation);
    if (enabled && found == beam_column_joins_.end()) beam_column_joins_.push_back(relation);
    if (!enabled && found != beam_column_joins_.end()) beam_column_joins_.erase(found);
    invalidate_dependency_graph_cache();
}

void Document::set_structural_wall_cut(ElementId wall_id, ElementId cutter_id, bool enabled, double clearance_meters) {
    if (clearance_meters < 0.0) throw std::invalid_argument("structural cut clearance cannot be negative");
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    auto* cutter = find_ptr(cutter_id);
    if (cutter == nullptr || (cutter->column() == nullptr && cutter->beam() == nullptr)) {
        throw std::invalid_argument("wall cut requires a column or beam cutter");
    }
    const auto cut_key = std::make_pair(wall_id, cutter_id);
    if (!enabled) {
        disabled_auto_structural_cuts_.insert(cut_key);
    } else if (!resolving_structural_relations_) {
        disabled_auto_structural_cuts_.erase(cut_key);
    }
    auto updated = *wall;
    updated.openings.erase(std::remove_if(updated.openings.begin(), updated.openings.end(), [&](const HostedOpening& opening) {
        return opening.element_id == cutter_id && opening.kind == OpeningKind::StructuralVoid;
    }), updated.openings.end());
    if (enabled) {
        const auto dx = updated.axis.end.x - updated.axis.start.x;
        const auto dy = updated.axis.end.y - updated.axis.start.y;
        const auto length = std::sqrt(dx * dx + dy * dy);
        if (length <= epsilon) throw std::invalid_argument("wall axis is invalid");
        Point2 center{};
        double width{};
        double height{};
        if (const auto* column = cutter->column()) {
            center = column->position;
            width = std::abs(dx / length) * column->width_meters + std::abs(dy / length) * column->depth_meters;
            height = column->height_meters;
        } else if (const auto* beam = cutter->beam()) {
            center = {(beam->start.x + beam->end.x) * 0.5, (beam->start.y + beam->end.y) * 0.5};
            width = beam->width_meters;
            height = beam->height_meters;
        }
        const auto offset = ((center.x - updated.axis.start.x) * dx + (center.y - updated.axis.start.y) * dy) / length;
        updated.openings.push_back(HostedOpening{
            .element_id = cutter_id,
            .kind = OpeningKind::StructuralVoid,
            .offset_meters = offset,
            .width_meters = width + (2.0 * clearance_meters),
            .height_meters = std::min(height + clearance_meters, resolved_wall_height(updated)),
            .sill_height_meters = 0.0,
            .vertical_offset_meters = 0.0,
        });
        validate_wall_openings(updated);
    }
    wall->openings = std::move(updated.openings);
    mark_wall_dirty(wall_element);
    if (resolving_structural_relations_) {
        // auto_join_structural_elements owns this transaction.  Calling the
        // normal wall refresh path here would re-enter auto_join_walls(),
        // which in turn invokes this resolver again.
        mark_rooms_dirty_for_wall(wall_id);
        touch_related_rooms(wall_id);
        invalidate_dependency_graph_cache();
        return;
    }
    refresh_dependencies_for_wall(wall_id);
}

void Document::set_wall_properties(ElementId wall_id, double thickness_meters, double height_meters, ElementId wall_type_id) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (thickness_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("wall thickness and height must be positive");
    }
    if (wall_type_id != 0 && get_wall_type(wall_type_id) == nullptr) {
        throw std::invalid_argument("wall type does not exist");
    }
    wall->thickness_meters = thickness_meters;
    wall->height_meters = height_meters;
    wall->wall_type_id = wall_type_id;
    // Wall editing is a canonical authoring path. A property edit with no
    // selected type must not leave a second, hidden layered source attached
    // to the same wall; legacy assembly-only records are handled explicitly
    // by set_element_assembly and normalized at project load.
    wall->assembly_id = 0;
    if (const auto* wall_type = get_wall_type(wall_type_id)) {
        wall->thickness_meters = total_wall_type_thickness(*wall_type);
    }
    auto updated = *wall;
    validate_wall_axis(updated.axis, wall->thickness_meters, resolved_wall_height(updated));
    validate_wall_openings(updated);
    mark_wall_dirty(wall_element);
    refresh_dependencies_for_wall(wall_id);
    invalidate_dependency_graph_cache();
}

void Document::set_wall_axis(ElementId wall_id, Line2 axis) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (wall->arc.has_value()) {
        throw std::invalid_argument("curved wall requires an arc geometry edit");
    }
    validate_wall_axis(axis, wall->thickness_meters, resolved_wall_height(*wall));

    auto updated = *wall;
    updated.axis = axis;
    validate_wall_openings(updated);

    wall->axis = axis;
    mark_wall_dirty(wall_element);
    for (auto& element : elements_) {
        auto* roof = element.roof();
        if (roof != nullptr && std::find(roof->source_wall_ids.begin(), roof->source_wall_ids.end(), wall_id) != roof->source_wall_ids.end()) {
            roof->generated_geometry_dirty = true;
            element.touch();
        }
    }
    refresh_dependencies_for_wall(wall_id);
    // Axis edits are a normal authoring path, not only a low-level geometry
    // update. Rebuild joins immediately so a moved endpoint cannot keep the
    // previous miter/cap relation and make the next corner look torn.
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    invalidate_dependency_graph_cache();
}

void Document::set_wall_axis_with_joins(ElementId wall_id, Line2 axis) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (wall->arc.has_value()) {
        throw std::invalid_argument("curved wall requires an arc geometry edit");
    }
    validate_wall_axis(axis, wall->thickness_meters, resolved_wall_height(*wall));

    struct AxisUpdate {
        ElementId id{};
        Line2 before{};
        Line2 after{};
    };
    std::vector<AxisUpdate> updates{
        AxisUpdate{.id = wall_id, .before = wall->axis, .after = axis},
    };
    // Endpoint drags are allowed to be a few pixels inaccurate on touch. If
    // the moved endpoint lands close to another wall's endpoint or line,
    // resolve that contact before the join graph is rebuilt. Otherwise the
    // two walls can be recorded as joined at a shallow diagonal intersection
    // even though the user's intention was a perpendicular/T connection.
    if (std::abs(axis.start.x - wall->axis.start.x) > epsilon ||
        std::abs(axis.start.y - wall->axis.start.y) > epsilon ||
        std::abs(axis.end.x - wall->axis.end.x) > epsilon ||
        std::abs(axis.end.y - wall->axis.end.y) > epsilon) {
        constexpr double endpoint_snap_tolerance_meters = 0.35;
        const auto point_on_segment = [](Point2 point, Line2 line) {
            return between(point.x, line.start.x, line.end.x) &&
                between(point.y, line.start.y, line.end.y);
        };
        const auto distance = [](Point2 first, Point2 second) {
            return std::hypot(first.x - second.x, first.y - second.y);
        };
        const auto moved_start = distance(axis.start, wall->axis.start) > epsilon;
        const auto moved_end = distance(axis.end, wall->axis.end) > epsilon;
        auto snap_endpoint = [&](Point2& endpoint, bool moved) {
            if (!moved) return;
            auto best_distance = endpoint_snap_tolerance_meters;
            std::optional<Point2> best;
            for (const auto& other_element : elements_) {
                const auto* other_wall = other_element.wall();
                if (other_wall == nullptr || other_element.id() == wall_id ||
                    other_wall->level_id != wall->level_id) {
                    continue;
                }
                for (const auto candidate : {other_wall->axis.start, other_wall->axis.end}) {
                    const auto candidate_distance = distance(endpoint, candidate);
                    if (candidate_distance < best_distance) {
                        best_distance = candidate_distance;
                        best = candidate;
                    }
                }
                const auto intersection = line_intersection(axis, other_wall->axis);
                if (intersection.has_value() && point_on_segment(*intersection, other_wall->axis)) {
                    const auto intersection_distance = distance(endpoint, *intersection);
                    if (intersection_distance < best_distance) {
                        best_distance = intersection_distance;
                        best = intersection;
                    }
                }
            }
            if (best.has_value()) endpoint = *best;
        };
        snap_endpoint(axis.start, moved_start);
        snap_endpoint(axis.end, moved_end);
        updates.front().after = axis;
    }
    const auto translate = [](Point2 point, Point2 delta) {
        return Point2{.x = point.x + delta.x, .y = point.y + delta.y};
    };
    const auto source = updates.front();
    const auto start_delta = subtract(source.after.start, source.before.start);
    const auto end_delta = subtract(source.after.end, source.before.end);
    const auto is_translation = std::abs(start_delta.x - end_delta.x) <= epsilon &&
        std::abs(start_delta.y - end_delta.y) <= epsilon;
    const auto source_axis = wall->axis;
    const auto source_level_id = wall->level_id;

    // Only a body translation carries joined endpoints with it. Endpoint
    // edits deliberately leave neighboring walls fixed; auto_join_walls()
    // below then rebuilds the relation at the new intersection (including a
    // T-junction when the moved endpoint lands on another wall's middle).
    // Spatial proximity is intentionally not enough, and the graph is not
    // recursively walked: a body move affects immediate joined endpoints
    // only, never the rest of the building.
    if (is_translation) {
        constexpr double joined_endpoint_tolerance_meters = 0.35;
        const auto endpoint_distance = [](Point2 point, Line2 line) {
            return std::min(
                length(Line2{.start = point, .end = line.start}),
                length(Line2{.start = point, .end = line.end})
            );
        };
        const auto point_on_segment = [](Point2 point, Line2 line) {
            return between(point.x, line.start.x, line.end.x) &&
                between(point.y, line.start.y, line.end.y);
        };

        // Resolve immediate attachment from the pre-move axes instead of
        // trusting a possibly stale serialized join list. A body move carries
        // an attached endpoint even when it slightly overruns a T host; it
        // never walks beyond that directly attached wall.
        for (const auto& other_element : elements_) {
            const auto* other_wall = other_element.wall();
            if (other_wall == nullptr || other_element.id() == wall_id ||
                other_wall->level_id != source_level_id) {
                continue;
            }
            const auto intersection = line_intersection(source_axis, other_wall->axis);
            if (!intersection.has_value()) continue;

            const auto source_on_segment = point_on_segment(*intersection, source_axis);
            const auto other_on_segment = point_on_segment(*intersection, other_wall->axis);
            const auto source_near_endpoint =
                endpoint_distance(*intersection, source_axis) <= joined_endpoint_tolerance_meters;
            const auto other_near_endpoint =
                endpoint_distance(*intersection, other_wall->axis) <= joined_endpoint_tolerance_meters;
            if ((!source_on_segment && !source_near_endpoint) ||
                (!other_on_segment && !other_near_endpoint) ||
                !other_near_endpoint) {
                continue;
            }

            auto other_axis = other_wall->axis;
            const auto start_distance = length(Line2{
                .start = other_axis.start, .end = *intersection});
            const auto end_distance = length(Line2{
                .start = other_axis.end, .end = *intersection});
            if (start_distance <= end_distance &&
                start_distance <= joined_endpoint_tolerance_meters) {
                other_axis.start = translate(other_axis.start, start_delta);
            } else if (end_distance <= joined_endpoint_tolerance_meters) {
                other_axis.end = translate(other_axis.end, start_delta);
            } else {
                continue;
            }
            updates.push_back(AxisUpdate{
                .id = other_element.id(),
                .before = other_wall->axis,
                .after = other_axis,
            });
        }
    }

    // Validate the complete connected edit before writing any axis. This
    // prevents a bad opening or too-short wall from leaving a partial chain.
    for (const auto& update : updates) {
        auto& element = require_wall(update.id);
        auto* candidate = element.wall();
        auto checked = *candidate;
        checked.axis = update.after;
        validate_wall_axis(update.after, candidate->thickness_meters, resolved_wall_height(checked));
        validate_wall_openings(checked);
        if (update.id != wall_id) {
            const auto before_direction = subtract(update.before.end, update.before.start);
            const auto after_direction = subtract(update.after.end, update.after.start);
            const auto direction_dot = (before_direction.x * after_direction.x) +
                (before_direction.y * after_direction.y);
            if (direction_dot <= epsilon) {
                throw std::invalid_argument(
                    "wall move would invert or collapse an immediately joined wall");
            }
        }
    }

    for (const auto& update : updates) {
        auto& element = require_wall(update.id);
        element.wall()->axis = update.after;
        mark_wall_dirty(element);
        for (auto& related : elements_) {
            auto* roof = related.roof();
            if (roof != nullptr && std::find(roof->source_wall_ids.begin(), roof->source_wall_ids.end(), update.id) != roof->source_wall_ids.end()) {
                roof->generated_geometry_dirty = true;
                related.touch();
            }
        }
        refresh_dependencies_for_wall(update.id);
    }
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    invalidate_dependency_graph_cache();
}

void Document::trim_extend_walls(
    ElementId first_wall_id,
    bool first_uses_start,
    ElementId second_wall_id,
    bool second_uses_start
) {
    if (first_wall_id == second_wall_id) {
        throw std::invalid_argument("trim/extend requires two distinct walls");
    }

    auto& first_element = require_wall(first_wall_id);
    auto& second_element = require_wall(second_wall_id);
    auto* first_wall = first_element.wall();
    auto* second_wall = second_element.wall();
    if (first_wall == nullptr || second_wall == nullptr) {
        throw std::invalid_argument("trim/extend requires wall elements");
    }
    if (std::abs(resolved_wall_base_elevation(*first_wall) -
                 resolved_wall_base_elevation(*second_wall)) > epsilon) {
        throw std::invalid_argument("trim/extend walls must share a base elevation");
    }

    const auto intersection = line_intersection(first_wall->axis, second_wall->axis);
    if (!intersection.has_value()) {
        throw std::invalid_argument("trim/extend walls must not be parallel");
    }

    auto first_axis = first_wall->axis;
    auto second_axis = second_wall->axis;
    if (first_uses_start) {
        first_axis.start = *intersection;
    } else {
        first_axis.end = *intersection;
    }
    if (second_uses_start) {
        second_axis.start = *intersection;
    } else {
        second_axis.end = *intersection;
    }

    constexpr double minimum_trimmed_length_meters = 0.10;
    if (length(first_axis) < minimum_trimmed_length_meters ||
        length(second_axis) < minimum_trimmed_length_meters) {
        throw std::invalid_argument("trim/extend would leave a wall too short");
    }

    // Validate every changed wall before writing either one. This keeps an
    // opening-validation failure atomic instead of leaving a half-trimmed
    // pair in the project.
    auto first_updated = *first_wall;
    first_updated.axis = first_axis;
    validate_wall_axis(first_axis, first_wall->thickness_meters, resolved_wall_height(first_updated));
    validate_wall_openings(first_updated);
    auto second_updated = *second_wall;
    second_updated.axis = second_axis;
    validate_wall_axis(second_axis, second_wall->thickness_meters, resolved_wall_height(second_updated));
    validate_wall_openings(second_updated);

    first_wall->axis = first_axis;
    second_wall->axis = second_axis;
    mark_wall_dirty(first_element);
    mark_wall_dirty(second_element);
    for (auto& element : elements_) {
        auto* roof = element.roof();
        if (roof == nullptr) {
            continue;
        }
        const auto first_used = std::find(
            roof->source_wall_ids.begin(), roof->source_wall_ids.end(), first_wall_id);
        const auto second_used = std::find(
            roof->source_wall_ids.begin(), roof->source_wall_ids.end(), second_wall_id);
        if (first_used != roof->source_wall_ids.end() ||
            second_used != roof->source_wall_ids.end()) {
            roof->generated_geometry_dirty = true;
            element.touch();
        }
    }
    mark_rooms_dirty_for_wall(first_wall_id);
    mark_rooms_dirty_for_wall(second_wall_id);
    touch_related_rooms(first_wall_id);
    touch_related_rooms(second_wall_id);
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    invalidate_dependency_graph_cache();
}

ElementId Document::split_wall(ElementId wall_id, double offset_meters) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (wall->arc.has_value()) {
        throw std::invalid_argument("curved walls cannot be split into segments");
    }
    const auto wall_length = length(wall->axis);
    if (offset_meters <= epsilon || offset_meters >= (wall_length - epsilon)) {
        throw std::invalid_argument("split offset must stay inside wall");
    }

    const auto direction = unit_direction(wall->axis);
    const auto split_point = add(wall->axis.start, scale(direction, offset_meters));
    const auto original_end = wall->axis.end;
    const auto original_openings = wall->openings;

    wall->axis.end = split_point;
    wall->openings.clear();
    mark_wall_dirty(wall_element);

    const auto new_wall_id = allocate_id();
    const auto split_name = std::string(wall_element.name()) + " Split";
    elements_.emplace_back(new_wall_id, ElementKind::Wall, split_name, WallData{
        .level_id = wall->level_id,
        .base_level_id = wall->base_level_id,
        .top_level_id = wall->top_level_id,
        .axis = Line2{.start = split_point, .end = original_end},
        .thickness_meters = wall->thickness_meters,
        .height_meters = wall->height_meters,
        .base_offset_meters = wall->base_offset_meters,
        .top_offset_meters = wall->top_offset_meters,
        .height_mode = wall->height_mode,
    });

    for (const auto& opening : original_openings) {
        if (opening.offset_meters < offset_meters) {
            add_opening_to_wall(wall_id, opening);
            continue;
        }

        auto shifted = opening;
        shifted.offset_meters -= offset_meters;
        add_opening_to_wall(new_wall_id, shifted);

        if (auto* opening_element = find_ptr(opening.element_id)) {
            if (auto* door = opening_element->door()) {
                door->host_wall_id = new_wall_id;
                door->offset_meters = shifted.offset_meters;
                door->level_id = wall->level_id;
                opening_element->touch();
            } else if (auto* window = opening_element->window()) {
                window->host_wall_id = new_wall_id;
                window->offset_meters = shifted.offset_meters;
                window->level_id = wall->level_id;
                opening_element->touch();
            }
        }
    }

    refresh_dependencies_for_wall(wall_id);
    refresh_dependencies_for_wall(new_wall_id);
    invalidate_dependency_graph_cache();
    return new_wall_id;
}

ElementId Document::create_door(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters) {
    if (name.empty()) {
        throw std::invalid_argument("door name must not be empty");
    }
    auto& wall_element = require_wall(host_wall_id);
    const auto* wall = wall_element.wall();
    if (wall_uses_glass(*wall)) {
        throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
    }
    validate_opening(*wall, offset_meters, width_meters, height_meters);

    const auto id = allocate_id();
    const auto level_id = wall->level_id;
    elements_.emplace_back(id, ElementKind::Door, std::move(name), DoorData{
        .level_id = level_id,
        .host_wall_id = host_wall_id,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .level_offset_meters = 0.0,
        .vertical_offset_meters = 0.0,
        .level_locked = true,
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Door,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = 0.0,
        .vertical_offset_meters = 0.0,
    });

    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_window(
    std::string name,
    ElementId host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    if (name.empty()) {
        throw std::invalid_argument("window name must not be empty");
    }
    if (!std::isfinite(sill_height_meters) || sill_height_meters < 0.0) {
        throw std::invalid_argument("window sill height must not be negative");
    }
    if (!std::isfinite(height_meters) || height_meters <= 0.0) {
        throw std::invalid_argument("window height must be positive");
    }

    auto& wall_element = require_wall(host_wall_id);
    const auto* wall = wall_element.wall();
    if (wall_uses_glass(*wall)) {
        throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
    }
    validate_opening(*wall, offset_meters, width_meters, height_meters + sill_height_meters);

    const auto id = allocate_id();
    const auto level_id = wall->level_id;
    elements_.emplace_back(id, ElementKind::Window, std::move(name), WindowData{
        .level_id = level_id,
        .host_wall_id = host_wall_id,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
        .level_offset_meters = 0.0,
        .vertical_offset_meters = 0.0,
        .level_locked = true,
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Window,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
        .vertical_offset_meters = 0.0,
    });

    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_slab(
    ElementId level_id,
    std::vector<Point2> boundary_polygon,
    double thickness_meters,
    ElementId material_id,
    ElementId assembly_id,
    double elevation_offset_meters
) {
    (void)require_level(level_id);
    if (boundary_polygon.size() < 3 || thickness_meters <= 0.0) {
        throw std::invalid_argument("slab boundary and thickness must be valid");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("slab material does not exist");
    }
    const auto* slab_assembly = assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id);
    if (assembly_id != 0 && slab_assembly == nullptr) {
        throw std::invalid_argument("slab assembly does not exist");
    }
    if (slab_assembly != nullptr && slab_assembly->kind != LayeredAssemblyKind::Floor) {
        throw std::invalid_argument("slab assembly kind must be Floor");
    }
    const auto resolved_thickness = slab_assembly == nullptr
        ? thickness_meters
        : layered_assembly_total_thickness(*slab_assembly);

    const auto id = allocate_id();
    auto area = polygon_area(boundary_polygon);
    // Creation is an interactive operation. Keep the initial mesh at the
    // envelope level and defer the compound build until a detail consumer
    // explicitly asks for it.
    auto mesh = extrude_polygon_mesh(boundary_polygon, resolved_thickness, elevation_offset_meters);
    const auto envelope_material_id = slab_assembly != nullptr && !slab_assembly->layers.empty()
        ? slab_assembly->layers.front().material_id
        : material_id;
    assign_cache_material(mesh, envelope_material_id);
    SlabData slab{
        .level_id = level_id,
        .boundary_polygon = std::move(boundary_polygon),
        .thickness_meters = resolved_thickness,
        .material_id = material_id,
        .assembly_id = assembly_id,
        .elevation_offset_meters = elevation_offset_meters,
        .generated_geometry_dirty = false,
        .mesh = std::move(mesh),
        .area_square_meters = area,
        .volume_cubic_meters = area * resolved_thickness,
    };
    slab.envelope_geometry.dirty = false;
    slab.envelope_geometry.assembly_revision = cache_assembly_revision(slab_assembly);
    slab.envelope_geometry.mesh = slab.mesh;
    elements_.emplace_back(id, ElementKind::Slab, "Slab", std::move(slab));
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_roof(
    ElementId level_id,
    std::vector<Point2> boundary_polygon,
    RoofType roof_type,
    double thickness_meters,
    ElementId material_id,
    ElementId assembly_id,
    std::optional<double> slope_degrees,
    std::optional<double> overhang_meters,
    std::vector<ElementId> source_wall_ids
) {
    (void)require_level(level_id);
    if (boundary_polygon.size() < 3 || thickness_meters <= 0.0) {
        throw std::invalid_argument("roof boundary and thickness must be valid");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("roof material does not exist");
    }
    if (assembly_id != 0 && get_layered_assembly(assembly_id) == nullptr) {
        throw std::invalid_argument("roof assembly does not exist");
    }
    if (assembly_id != 0 && get_layered_assembly(assembly_id)->kind != LayeredAssemblyKind::Roof) {
        throw std::invalid_argument("roof assembly kind must be Roof");
    }
    if (roof_type == RoofType::SimpleGable &&
        (!slope_degrees.has_value() || *slope_degrees <= 0.0 || *slope_degrees >= 75.0 || !valid_gable_profile(boundary_polygon))) {
        throw std::invalid_argument("simple gable requires rectangular profile and 0-75 degree slope");
    }
    if (roof_type == RoofType::AutoFootprint &&
        (!slope_degrees.has_value() || *slope_degrees <= 0.0 || *slope_degrees >= 75.0 || polygon_has_self_intersection(boundary_polygon))) {
        throw std::invalid_argument("automatic footprint roof requires a simple profile and 0-75 degree slope");
    }

    const auto id = allocate_id();
    const auto resolved_thickness = assembly_id != 0 ? layered_assembly_total_thickness(*get_layered_assembly(assembly_id)) : thickness_meters;
    const RoofData area_roof{.boundary_polygon = boundary_polygon, .roof_type = roof_type, .thickness_meters = resolved_thickness, .slope_degrees = slope_degrees, .overhang_meters = overhang_meters};
    const auto area = roof_type == RoofType::Flat ? polygon_area(boundary_polygon) : roof_surface_area(area_roof);
    auto mesh = roof_type == RoofType::Flat
        ? extrude_polygon_mesh(boundary_polygon, resolved_thickness, 0.0)
        : roof_type == RoofType::SimpleGable
            ? build_gable_roof_mesh(area_roof, resolved_thickness)
            : build_auto_footprint_roof_mesh(area_roof, resolved_thickness);
    RoofData roof_data{
        .level_id = level_id,
        .boundary_polygon = std::move(boundary_polygon),
        .source_wall_ids = std::move(source_wall_ids),
        .roof_type = roof_type,
        .thickness_meters = resolved_thickness,
        .slope_degrees = slope_degrees,
        .overhang_meters = overhang_meters,
        .material_id = material_id,
        .assembly_id = assembly_id,
        .generated_geometry_dirty = false,
        .mesh = std::move(mesh),
        .area_square_meters = area,
        .volume_cubic_meters = area * resolved_thickness,
    };
    roof_data.envelope_geometry.dirty = false;
    roof_data.envelope_geometry.assembly_revision = cache_assembly_revision(
        assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id)
    );
    elements_.emplace_back(id, ElementKind::Roof, "Roof", std::move(roof_data));
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_column(
    ElementId level_id,
    Point2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    ElementId material_id
) {
    (void)require_level(level_id);
    if (width_meters <= 0.0 || depth_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("column dimensions must be positive");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("column material does not exist");
    }
    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Column, "Column", ColumnData{
        .level_id = level_id,
        .position = position,
        .width_meters = width_meters,
        .depth_meters = depth_meters,
        .height_meters = height_meters,
        .material_id = material_id,
        .generated_geometry_dirty = false,
        .mesh = extrude_column_mesh(position, width_meters, depth_meters, height_meters),
        .volume_cubic_meters = width_meters * depth_meters * height_meters,
    });
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_beam(
    ElementId level_id,
    Point2 start,
    Point2 end,
    double width_meters,
    double height_meters,
    ElementId material_id
) {
    (void)require_level(level_id);
    const auto beam_length = length(Line2{.start = start, .end = end});
    if (beam_length <= epsilon || width_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("beam dimensions must be positive");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("beam material does not exist");
    }
    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Beam, "Beam", BeamData{
        .level_id = level_id,
        .start = start,
        .end = end,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .material_id = material_id,
        .generated_geometry_dirty = false,
        .mesh = extrude_beam_mesh(start, end, width_meters, height_meters),
        .length_meters = beam_length,
        .volume_cubic_meters = beam_length * width_meters * height_meters,
    });
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_stair(
    ElementId base_level_id,
    ElementId top_level_id,
    Point2 start,
    Point2 direction,
    double width_meters,
    double total_rise_meters,
    double total_run_meters,
    int riser_count,
    int tread_count,
    ElementId material_id,
    ElementId assembly_id
) {
    (void)require_level(base_level_id);
    if (top_level_id != 0) {
        (void)require_level(top_level_id);
    }
    if (top_level_id != 0 && top_level_id != base_level_id &&
        level_elevation(top_level_id) <= level_elevation(base_level_id) + epsilon) {
        throw std::invalid_argument("stair top level must be above base level");
    }
    if (width_meters <= 0.0 || total_rise_meters <= 0.0 || total_run_meters <= 0.0 || riser_count <= 0 || tread_count <= 0) {
        throw std::invalid_argument("stair dimensions and counts must be positive");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("stair material does not exist");
    }
    if (assembly_id != 0) {
        const auto* assembly = get_layered_assembly(assembly_id);
        if (assembly == nullptr || assembly->kind != LayeredAssemblyKind::Stair) {
            throw std::invalid_argument("stair assembly must exist and have Stair kind");
        }
    }
    const auto direction_length = std::hypot(direction.x, direction.y);
    if (direction_length <= epsilon) {
        throw std::invalid_argument("stair direction must be non-zero");
    }
    return create_stair_layout(
        base_level_id,
        top_level_id,
        {start, add(start, scale(direction, total_run_meters / direction_length))},
        width_meters,
        total_rise_meters,
        riser_count,
        tread_count,
        0.0,
        StairLayoutKind::Straight,
        false,
        material_id,
        assembly_id
    );
}

ElementId Document::create_stair_layout(
    ElementId base_level_id,
    ElementId top_level_id,
    std::vector<Point2> path_points,
    double width_meters,
    double total_rise_meters,
    int riser_count,
    int tread_count,
    double landing_depth_meters,
    StairLayoutKind layout_kind,
    bool railing_enabled,
    ElementId material_id,
    ElementId assembly_id
) {
    (void)require_level(base_level_id);
    if (top_level_id != 0) {
        (void)require_level(top_level_id);
    }
    if (top_level_id != 0 && top_level_id != base_level_id &&
        level_elevation(top_level_id) <= level_elevation(base_level_id) + epsilon) {
        throw std::invalid_argument("stair top level must be above base level");
    }
    if (layout_kind != StairLayoutKind::Straight &&
        layout_kind != StairLayoutKind::LShape &&
        layout_kind != StairLayoutKind::UShape) {
        throw std::invalid_argument("stair layout kind is invalid");
    }
    const auto minimum_points = layout_kind == StairLayoutKind::Straight ? 2U :
        layout_kind == StairLayoutKind::LShape ? 3U : 4U;
    if (path_points.size() < minimum_points) {
        throw std::invalid_argument("stair path does not match its layout kind");
    }
    if (width_meters <= 0.0 || total_rise_meters <= 0.0 || riser_count <= 0 || tread_count <= 0 ||
        landing_depth_meters < 0.0) {
        throw std::invalid_argument("stair dimensions and counts must be positive");
    }
    double total_run_meters = 0.0;
    for (std::size_t index = 0; index < path_points.size(); ++index) {
        if (!std::isfinite(path_points[index].x) || !std::isfinite(path_points[index].y)) {
            throw std::invalid_argument("stair path points must be finite");
        }
        if (index > 0) {
            const auto segment = std::hypot(
                path_points[index].x - path_points[index - 1].x,
                path_points[index].y - path_points[index - 1].y
            );
            if (segment <= epsilon) {
                throw std::invalid_argument("stair path segments must be non-zero");
            }
            total_run_meters += segment;
        }
    }
    if (total_run_meters <= epsilon) {
        throw std::invalid_argument("stair path must have a positive run");
    }
    if (layout_kind == StairLayoutKind::Straight && path_points.size() != 2) {
        throw std::invalid_argument("straight stair must have exactly two path points");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("stair material does not exist");
    }
    if (assembly_id != 0) {
        const auto* assembly = get_layered_assembly(assembly_id);
        if (assembly == nullptr || assembly->kind != LayeredAssemblyKind::Stair) {
            throw std::invalid_argument("stair assembly must exist and have Stair kind");
        }
    }
    const auto direction = Point2{
        .x = path_points[1].x - path_points[0].x,
        .y = path_points[1].y - path_points[0].y,
    };
    const auto landing_count = static_cast<double>(path_points.size() - 2);
    const auto footprint_area = width_meters * total_run_meters +
        width_meters * landing_depth_meters * landing_count;
    const auto id = allocate_id();
    StairData stair{
        .base_level_id = base_level_id,
        .top_level_id = top_level_id,
        .start = path_points.front(),
        .direction = direction,
        .width_meters = width_meters,
        .total_rise_meters = total_rise_meters,
        .total_run_meters = total_run_meters,
        .riser_count = riser_count,
        .tread_count = tread_count,
        .material_id = material_id,
        .assembly_id = assembly_id,
        .generated_geometry_dirty = false,
        .mesh = {},
        .footprint_area_square_meters = footprint_area,
        .volume_cubic_meters = footprint_area * (total_rise_meters / 2.0),
        .layout_kind = layout_kind,
        .path_points = std::move(path_points),
        .landing_depth_meters = landing_depth_meters,
        .railing_enabled = railing_enabled,
    };
    stair.mesh = build_stair_mesh(stair);
    stair.envelope_geometry.dirty = false;
    stair.envelope_geometry.assembly_revision = cache_assembly_revision(
        assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id)
    );
    elements_.emplace_back(id, ElementKind::Stair, "Stair", stair);
    invalidate_dependency_graph_cache();
    return id;
}

void Document::update_stair_layout(
    ElementId stair_id,
    std::vector<Point2> path_points,
    double width_meters,
    double landing_depth_meters,
    StairLayoutKind layout_kind,
    bool railing_enabled
) {
    auto* element = find_ptr(stair_id);
    auto* stair = element == nullptr ? nullptr : element->stair();
    if (stair == nullptr) {
        throw std::invalid_argument("stair does not exist");
    }
    if (width_meters <= 0.0 || !std::isfinite(width_meters) ||
        landing_depth_meters < 0.0 || !std::isfinite(landing_depth_meters)) {
        throw std::invalid_argument("stair width and landing must be finite and positive");
    }
    if (layout_kind != StairLayoutKind::Straight &&
        layout_kind != StairLayoutKind::LShape &&
        layout_kind != StairLayoutKind::UShape) {
        throw std::invalid_argument("stair layout kind is invalid");
    }

    // Old straight stairs did not persist a centerline. Reconstruct it from
    // the legacy start/direction/run fields so editing remains safe for v1/v2
    // files instead of silently replacing the stair with a zero-length path.
    if (path_points.empty() && layout_kind == StairLayoutKind::Straight) {
        const auto direction_length = std::hypot(stair->direction.x, stair->direction.y);
        if (direction_length > epsilon && stair->total_run_meters > epsilon) {
            path_points = {
                stair->start,
                add(stair->start, scale(stair->direction, stair->total_run_meters / direction_length)),
            };
        }
    }

    const auto minimum_points = layout_kind == StairLayoutKind::Straight ? 2U :
        layout_kind == StairLayoutKind::LShape ? 3U : 4U;
    if (path_points.size() < minimum_points ||
        (layout_kind == StairLayoutKind::Straight && path_points.size() != 2)) {
        throw std::invalid_argument("stair path does not match its layout kind");
    }
    double total_run_meters = 0.0;
    for (std::size_t index = 0; index < path_points.size(); ++index) {
        if (!std::isfinite(path_points[index].x) || !std::isfinite(path_points[index].y)) {
            throw std::invalid_argument("stair path points must be finite");
        }
        if (index > 0) {
            const auto segment = std::hypot(
                path_points[index].x - path_points[index - 1].x,
                path_points[index].y - path_points[index - 1].y
            );
            if (segment <= epsilon) {
                throw std::invalid_argument("stair path segments must be non-zero");
            }
            total_run_meters += segment;
        }
    }
    if (total_run_meters <= epsilon) {
        throw std::invalid_argument("stair path must have a positive run");
    }

    stair->start = path_points.front();
    stair->direction = Point2{
        .x = path_points[1].x - path_points[0].x,
        .y = path_points[1].y - path_points[0].y,
    };
    stair->width_meters = width_meters;
    stair->total_run_meters = total_run_meters;
    stair->footprint_area_square_meters = width_meters * total_run_meters +
        width_meters * landing_depth_meters * static_cast<double>(path_points.size() - 2);
    stair->volume_cubic_meters = stair->footprint_area_square_meters *
        (stair->total_rise_meters / 2.0);
    stair->layout_kind = layout_kind;
    stair->path_points = std::move(path_points);
    stair->landing_depth_meters = landing_depth_meters;
    stair->railing_enabled = railing_enabled;
    stair->generated_geometry_dirty = true;
    stair->envelope_geometry.dirty = true;
    stair->layered_geometry.dirty = true;
    element->touch();
    invalidate_dependency_graph_cache();
}

ElementId Document::create_proxy(
    std::string name,
    ElementId level_id,
    Point2 position,
    double width_meters,
    double depth_meters,
    double height_meters
) {
    if (name.empty()) {
        throw std::invalid_argument("proxy name must not be empty");
    }
    (void)require_level(level_id);
    if (width_meters <= 0.0 || depth_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("proxy dimensions must be positive");
    }
    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Proxy, std::move(name), ProxyData{
        .level_id = level_id,
        .position = position,
        .width_meters = width_meters,
        .depth_meters = depth_meters,
        .height_meters = height_meters,
    });
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_floor_system_for_room(ElementId room_id, ElementId assembly_id) {
    const auto& room_element = require_room(room_id);
    const auto* room = room_element.room();
    const auto* assembly = assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id);
    if (assembly_id != 0 && assembly == nullptr) {
        throw std::invalid_argument("floor assembly does not exist");
    }
    if (assembly != nullptr && assembly->kind != LayeredAssemblyKind::Floor) {
        throw std::invalid_argument("assembly kind must be floor");
    }
    for (auto& [system_id, system] : floor_systems_) {
        if (system.room_id == room_id) {
            system.assembly_id = assembly_id;
            system.level_id = room->level_id;
            system.boundary_polygon = room->interior_boundary_polygon;
            system.area_square_meters = room->interior_area_square_meters;
            system.dirty = false;
            return system_id;
        }
    }
    const auto system_id = allocate_id();
    floor_systems_[system_id] = FloorSystemData{
        .system_id = system_id,
        .room_id = room_id,
        .level_id = room->level_id,
        .assembly_id = assembly_id,
        .boundary_polygon = room->interior_boundary_polygon,
        .area_square_meters = room->interior_area_square_meters,
        .dirty = false,
    };
    invalidate_dependency_graph_cache();
    return system_id;
}

ElementId Document::create_ceiling_system_for_room(ElementId room_id, ElementId assembly_id, double height_offset_meters) {
    const auto& room_element = require_room(room_id);
    const auto* room = room_element.room();
    const auto* assembly = assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id);
    if (assembly_id != 0 && assembly == nullptr) {
        throw std::invalid_argument("ceiling assembly does not exist");
    }
    if (assembly != nullptr && assembly->kind != LayeredAssemblyKind::Ceiling) {
        throw std::invalid_argument("assembly kind must be ceiling");
    }
    height_offset_meters = normalized_ceiling_height_offset(height_offset_meters);
    for (auto& [system_id, system] : ceiling_systems_) {
        if (system.room_id == room_id) {
            system.assembly_id = assembly_id;
            system.level_id = room->level_id;
            system.boundary_polygon = room->interior_boundary_polygon;
            system.area_square_meters = room->interior_area_square_meters;
            system.height_offset_meters = height_offset_meters;
            system.dirty = false;
            return system_id;
        }
    }
    const auto system_id = allocate_id();
    ceiling_systems_[system_id] = CeilingSystemData{
        .system_id = system_id,
        .room_id = room_id,
        .level_id = room->level_id,
        .assembly_id = assembly_id,
        .boundary_polygon = room->interior_boundary_polygon,
        .area_square_meters = room->interior_area_square_meters,
        .height_offset_meters = height_offset_meters,
        .dirty = false,
    };
    invalidate_dependency_graph_cache();
    return system_id;
}

ElementId Document::create_floor_system_from_profile(
    ElementId level_id,
    std::vector<Point2> boundary_polygon,
    ElementId assembly_id,
    double thickness_meters
) {
    (void)thickness_meters;
    if (level_id != 0) {
        (void)require_level(level_id);
    }
    const auto* assembly = assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id);
    if (assembly_id != 0 && assembly == nullptr) {
        throw std::invalid_argument("floor assembly does not exist");
    }
    if (assembly != nullptr && assembly->kind != LayeredAssemblyKind::Floor) {
        throw std::invalid_argument("assembly kind must be floor");
    }
    boundary_polygon = simplify_polygon(std::move(boundary_polygon));
    if (boundary_polygon.size() < 3 || polygon_area(boundary_polygon) <= epsilon) {
        throw std::invalid_argument("floor profile must be a valid closed polygon");
    }
    for (const auto& [existing_id, system] : floor_systems_) {
        if (system.level_id == level_id &&
            cyclic_polygon_equal(system.boundary_polygon, boundary_polygon)) {
            throw std::invalid_argument("a floor already exists for this boundary on the selected level");
        }
        (void)existing_id;
    }
    const auto area = polygon_area(boundary_polygon);
    const auto system_id = allocate_id();
    floor_systems_[system_id] = FloorSystemData{
        .system_id = system_id,
        .room_id = 0,
        .level_id = level_id,
        .assembly_id = assembly_id,
        .boundary_polygon = std::move(boundary_polygon),
        .area_square_meters = area,
        .dirty = false,
    };
    invalidate_dependency_graph_cache();
    return system_id;
}

ElementId Document::create_ceiling_system_from_profile(
    ElementId level_id,
    std::vector<Point2> boundary_polygon,
    ElementId assembly_id,
    double height_offset_meters
) {
    height_offset_meters = normalized_ceiling_height_offset(height_offset_meters);
    if (level_id != 0) {
        (void)require_level(level_id);
    }
    const auto* assembly = assembly_id == 0 ? nullptr : get_layered_assembly(assembly_id);
    if (assembly_id != 0 && assembly == nullptr) {
        throw std::invalid_argument("ceiling assembly does not exist");
    }
    if (assembly != nullptr && assembly->kind != LayeredAssemblyKind::Ceiling) {
        throw std::invalid_argument("assembly kind must be ceiling");
    }
    boundary_polygon = simplify_polygon(std::move(boundary_polygon));
    if (boundary_polygon.size() < 3 || polygon_area(boundary_polygon) <= epsilon) {
        throw std::invalid_argument("ceiling profile must be a valid closed polygon");
    }
    for (const auto& [existing_id, system] : ceiling_systems_) {
        if (system.level_id == level_id &&
            std::abs(system.height_offset_meters - height_offset_meters) <= epsilon &&
            cyclic_polygon_equal(system.boundary_polygon, boundary_polygon)) {
            throw std::invalid_argument("a ceiling already exists for this boundary on the selected level");
        }
        (void)existing_id;
    }
    const auto area = polygon_area(boundary_polygon);
    const auto system_id = allocate_id();
    ceiling_systems_[system_id] = CeilingSystemData{
        .system_id = system_id,
        .room_id = 0,
        .level_id = level_id,
        .assembly_id = assembly_id,
        .boundary_polygon = std::move(boundary_polygon),
        .area_square_meters = area,
        .height_offset_meters = height_offset_meters,
        .manual_profile = true,
        .dirty = false,
    };
    invalidate_dependency_graph_cache();
    return system_id;
}

std::vector<ElementId> Document::generate_floor_systems_for_all_rooms(ElementId default_assembly_id) {
    std::vector<ElementId> ids;
    for (const auto& element : elements_) {
        if (element.room() != nullptr) {
            ids.push_back(create_floor_system_for_room(element.id(), default_assembly_id));
        }
    }
    return ids;
}

std::vector<ElementId> Document::generate_ceiling_systems_for_all_rooms(ElementId default_assembly_id, double height_offset_meters) {
    std::vector<ElementId> ids;
    for (const auto& element : elements_) {
        if (element.room() != nullptr) {
            ids.push_back(create_ceiling_system_for_room(element.id(), default_assembly_id, height_offset_meters));
        }
    }
    return ids;
}

void Document::update_floor_system_from_room(ElementId room_id) {
    const auto& room_element = require_room(room_id);
    const auto* room = room_element.room();
    for (auto& [_, system] : floor_systems_) {
        if (system.room_id == room_id) {
            system.level_id = room->level_id;
            system.boundary_polygon = room->interior_boundary_polygon;
            system.area_square_meters = room->interior_area_square_meters;
            system.dirty = false;
        }
    }
    invalidate_dependency_graph_cache();
}

void Document::update_ceiling_system_from_room(ElementId room_id) {
    const auto& room_element = require_room(room_id);
    const auto* room = room_element.room();
    for (auto& [_, system] : ceiling_systems_) {
        if (system.room_id == room_id) {
            system.level_id = room->level_id;
            system.boundary_polygon = room->interior_boundary_polygon;
            system.area_square_meters = room->interior_area_square_meters;
            system.dirty = false;
        }
    }
    invalidate_dependency_graph_cache();
}

void Document::delete_element(ElementId element_id) {
    auto* element = find_ptr(element_id);
    if (element == nullptr) {
        throw std::invalid_argument("element does not exist");
    }
    const auto is_level = element->level() != nullptr;

    if (const auto* wall = element->wall()) {
        std::vector<ElementId> hosted_ids;
        for (const auto& opening : wall->openings) {
            // Doors and windows are owned by their host wall. Structural
            // voids are only derived cut relations: their column/beam cutter
            // remains an independent semantic element and must survive when
            // the wall is deleted.
            if (opening.kind == OpeningKind::Door || opening.kind == OpeningKind::Window) {
                hosted_ids.push_back(opening.element_id);
            }
        }
        for (const auto hosted_id : hosted_ids) {
            remove_element(hosted_id);
        }
        remove_element(element_id);
        auto_join_walls();
        detect_rooms();
        invalidate_dependency_graph_cache();
        return;
    }

    if (const auto* door = element->door()) {
        remove_hosted_opening(door->host_wall_id, element_id);
        remove_element(element_id);
        detect_rooms();
        invalidate_dependency_graph_cache();
        return;
    }

    if (const auto* window = element->window()) {
        remove_hosted_opening(window->host_wall_id, element_id);
        remove_element(element_id);
        detect_rooms();
        invalidate_dependency_graph_cache();
        return;
    }

    const auto is_structural = element->column() != nullptr || element->beam() != nullptr;
    remove_element(element_id);
    if (is_structural) {
        // Structural cuts and joins are derived, never owned by the deleted
        // element. Re-resolve immediately so no wall retains a stale void.
        auto_join_structural_elements();
    }
    if (is_level) {
        detect_rooms();
    }
    invalidate_dependency_graph_cache();
}

void Document::move_hosted_opening(ElementId opening_id, double offset_meters) {
    auto* opening_element = find_ptr(opening_id);
    if (opening_element == nullptr) {
        throw std::invalid_argument("opening does not exist");
    }

    if (const auto* door = opening_element->door()) {
        update_hosted_opening(
            opening_id,
            offset_meters,
            door->width_meters,
            door->height_meters,
            0.0
        );
        return;
    }

    if (const auto* window = opening_element->window()) {
        update_hosted_opening(
            opening_id,
            offset_meters,
            window->width_meters,
            window->height_meters,
            window->sill_height_meters
        );
        return;
    }

    throw std::invalid_argument("opening does not exist");
}

void Document::resize_door(ElementId door_id, double width_meters, double height_meters) {
    const auto& door = require_door(door_id);
    update_hosted_opening(
        door_id,
        door.door()->offset_meters,
        width_meters,
        height_meters,
        0.0
    );
}

void Document::resize_window(ElementId window_id, double width_meters, double height_meters, double sill_height_meters) {
    const auto& window = require_window(window_id);
    update_hosted_opening(
        window_id,
        window.window()->offset_meters,
        width_meters,
        height_meters,
        sill_height_meters
    );
}

void Document::update_hosted_opening(
    ElementId opening_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    auto* opening_element = find_ptr(opening_id);
    if (opening_element == nullptr) {
        throw std::invalid_argument("opening does not exist");
    }

    ElementId host_wall_id{};
    HostedOpening updated{};
    if (const auto* door = opening_element->door(); door != nullptr) {
        host_wall_id = door->host_wall_id;
        updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Door,
            .offset_meters = offset_meters,
            .width_meters = width_meters,
            .height_meters = height_meters,
            .sill_height_meters = 0.0,
            .vertical_offset_meters = door->vertical_offset_meters,
        };
    } else if (const auto* window = opening_element->window(); window != nullptr) {
        host_wall_id = window->host_wall_id;
        updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Window,
            .offset_meters = offset_meters,
            .width_meters = width_meters,
            .height_meters = height_meters,
            .sill_height_meters = sill_height_meters,
            .vertical_offset_meters = window->vertical_offset_meters,
        };
    } else {
        throw std::invalid_argument("element is not a hosted opening");
    }

    auto wall_copy = *require_wall(host_wall_id).wall();
    auto found = false;
    for (auto& opening : wall_copy.openings) {
        if (opening.element_id == opening_id) {
            opening = updated;
            found = true;
            break;
        }
    }
    if (!found) {
        throw std::invalid_argument("hosted opening does not exist on wall");
    }
    // Validate the entire resulting wall before touching either the opening
    // element or its host. This makes the compound edit all-or-nothing.
    validate_wall_openings(wall_copy);

    if (auto* door = opening_element->door(); door != nullptr) {
        door->offset_meters = offset_meters;
        door->width_meters = width_meters;
        door->height_meters = height_meters;
    } else if (auto* window = opening_element->window(); window != nullptr) {
        window->offset_meters = offset_meters;
        window->width_meters = width_meters;
        window->height_meters = height_meters;
        window->sill_height_meters = sill_height_meters;
    }
    opening_element->touch();
    update_wall_opening(host_wall_id, updated);
    invalidate_dependency_graph_cache();
}

void Document::auto_join_walls() {
    constexpr double endpoint_join_tolerance_meters = 0.35;

    for (auto& element : elements_) {
        if (auto* wall = element.wall()) {
            if (!wall->joins.empty()) {
                wall->joins.clear();
                mark_wall_dirty(element);
            }
        }
    }

    for (auto first = elements_.begin(); first != elements_.end(); ++first) {
        auto* first_wall = first->wall();
        if (first_wall == nullptr) {
            continue;
        }

        for (auto second = std::next(first); second != elements_.end(); ++second) {
            auto* second_wall = second->wall();
            if (second_wall == nullptr) {
                continue;
            }
            if (first_wall->level_id != second_wall->level_id) {
                continue;
            }

            // A curved wall's axis is an endpoint chord, not its visible
            // centerline. Never run the straight-line intersection/mitre
            // solver against that chord: it can pull the curve endpoint to a
            // false crossing and corrupt the authored arc. Curved walls only
            // participate in safe end-to-end joins for now.
            if (first_wall->arc.has_value() || second_wall->arc.has_value()) {
                auto closest_distance = endpoint_join_tolerance_meters;
                std::optional<Point2> first_contact;
                std::optional<Point2> second_contact;
                for (const auto first_point : {first_wall->axis.start, first_wall->axis.end}) {
                    for (const auto second_point : {second_wall->axis.start, second_wall->axis.end}) {
                        const auto distance = length(Line2{.start = first_point, .end = second_point});
                        if (distance <= closest_distance) {
                            closest_distance = distance;
                            first_contact = first_point;
                            second_contact = second_point;
                        }
                    }
                }
                if (!first_contact.has_value() || !second_contact.has_value()) {
                    continue;
                }
                const auto first_is_arc = first_wall->arc.has_value();
                const auto second_is_arc = second_wall->arc.has_value();
                // A small touch gap is repaired on the straight wall only.
                // Moving an arc endpoint would invalidate its circle, while
                // snapping the line endpoint preserves both authored curves
                // and a single exact cap plane at the join.
                auto straight_snapped = false;
                if (first_is_arc != second_is_arc) {
                    auto& straight_wall = first_is_arc ? *second_wall : *first_wall;
                    const auto straight_contact = first_is_arc ? *second_contact : *first_contact;
                    const auto arc_contact = first_is_arc ? *first_contact : *second_contact;
                    auto snapped_axis = straight_wall.axis;
                    const auto start_distance = length(Line2{
                        .start = snapped_axis.start,
                        .end = straight_contact});
                    const auto end_distance = length(Line2{
                        .start = snapped_axis.end,
                        .end = straight_contact});
                    if (start_distance <= end_distance) {
                        snapped_axis.start = arc_contact;
                    } else {
                        snapped_axis.end = arc_contact;
                    }
                    auto candidate = straight_wall;
                    candidate.axis = snapped_axis;
                    try {
                        validate_wall_axis(
                            candidate.axis,
                            candidate.thickness_meters,
                            resolved_wall_height(candidate));
                        validate_wall_openings(candidate);
                        straight_wall.axis = snapped_axis;
                        straight_snapped = true;
                    } catch (const std::invalid_argument&) {
                        // Keep the user's original line if snapping would
                        // invalidate an opening or collapse a short wall.
                    }
                    if (straight_snapped) {
                        if (first_is_arc) {
                            second_contact = arc_contact;
                        } else {
                            first_contact = arc_contact;
                        }
                    }
                }
                const auto join_point = straight_snapped
                    ? (first_is_arc ? *first_contact : *second_contact)
                    : Point2{
                        .x = (first_contact->x + second_contact->x) * 0.5,
                        .y = (first_contact->y + second_contact->y) * 0.5,
                    };
                const auto first_other_axis = second_wall->arc.has_value()
                    ? wall_join_reference_axis(*second_wall, *second_contact)
                    : second_wall->axis;
                const auto second_other_axis = first_wall->arc.has_value()
                    ? wall_join_reference_axis(*first_wall, *first_contact)
                    : first_wall->axis;
                first_wall->joins.push_back(WallJoin{
                    .other_wall_id = second->id(),
                    .point = join_point,
                    .other_axis = first_other_axis,
                    .kind = WallJoinKind::End,
                });
                second_wall->joins.push_back(WallJoin{
                    .other_wall_id = first->id(),
                    .point = join_point,
                    .other_axis = second_other_axis,
                    .kind = WallJoinKind::End,
                });
                mark_wall_dirty(*first);
                mark_wall_dirty(*second);
                continue;
            }

            auto line_intersection_point = line_intersection(first_wall->axis, second_wall->axis);
            auto parallel_endpoint_join = false;
            if (!line_intersection_point.has_value()) {
                // Parallel axes are normally not a join. The one safe
                // exception is a single, almost-collinear end-to-end contact
                // caused by hand-drawn noise. Reject overlapping parallel
                // segments so nearby walls never become accidental joins.
                constexpr double collinear_tolerance_meters = 0.15;
                const auto first_length = length(first_wall->axis);
                const auto second_length = length(second_wall->axis);
                if (first_length > epsilon && second_length > epsilon) {
                    const auto first_direction = unit_direction(first_wall->axis);
                    const auto second_offset = Point2{
                        .x = second_wall->axis.start.x - first_wall->axis.start.x,
                        .y = second_wall->axis.start.y - first_wall->axis.start.y,
                    };
                    const auto parallel_error = std::abs(
                        first_direction.x * second_offset.y - first_direction.y * second_offset.x);
                    if (parallel_error <= collinear_tolerance_meters) {
                        const auto project = [&](Point2 point) {
                            return (point.x - first_wall->axis.start.x) * first_direction.x +
                                (point.y - first_wall->axis.start.y) * first_direction.y;
                        };
                        const auto first_min = 0.0;
                        const auto first_max = first_length;
                        const auto second_a = project(second_wall->axis.start);
                        const auto second_b = project(second_wall->axis.end);
                        const auto second_min = std::min(second_a, second_b);
                        const auto second_max = std::max(second_a, second_b);
                        const auto overlap = std::min(first_max, second_max) -
                            std::max(first_min, second_min);
                        std::optional<Point2> first_contact;
                        std::optional<Point2> second_contact;
                        int contact_count = 0;
                        for (const auto first_point : {first_wall->axis.start, first_wall->axis.end}) {
                            for (const auto second_point : {second_wall->axis.start, second_wall->axis.end}) {
                                if (length(Line2{.start = first_point, .end = second_point}) <=
                                    endpoint_join_tolerance_meters) {
                                    ++contact_count;
                                    first_contact = first_point;
                                    second_contact = second_point;
                                }
                            }
                        }
                        if (contact_count == 1 && overlap <= collinear_tolerance_meters &&
                            first_contact.has_value() && second_contact.has_value()) {
                            line_intersection_point = Point2{
                                .x = (first_contact->x + second_contact->x) * 0.5,
                                .y = (first_contact->y + second_contact->y) * 0.5,
                            };
                            parallel_endpoint_join = true;
                        }
                    }
                }
            }
            if (!line_intersection_point.has_value()) {
                continue;
            }

            const auto endpoint_distance = [](Point2 point, Line2 line) {
                return std::min(length(Line2{.start = point, .end = line.start}),
                                length(Line2{.start = point, .end = line.end}));
            };
            const auto first_on_segment =
                between(line_intersection_point->x, first_wall->axis.start.x, first_wall->axis.end.x) &&
                between(line_intersection_point->y, first_wall->axis.start.y, first_wall->axis.end.y);
            const auto second_on_segment =
                between(line_intersection_point->x, second_wall->axis.start.x, second_wall->axis.end.x) &&
                between(line_intersection_point->y, second_wall->axis.start.y, second_wall->axis.end.y);
            const auto first_near_endpoint = endpoint_distance(*line_intersection_point, first_wall->axis) <= endpoint_join_tolerance_meters;
            const auto second_near_endpoint = endpoint_distance(*line_intersection_point, second_wall->axis) <= endpoint_join_tolerance_meters;
            if ((!first_on_segment && !first_near_endpoint) ||
                (!second_on_segment && !second_near_endpoint)) {
                continue;
            }

            // A short authoring chord is especially sensitive to the
            // infinite-line repair above: a later arc chord can cross a long
            // straight wall just beyond its own endpoint and get pulled onto
            // that unrelated intersection. Short segments may therefore join
            // only when one of their actual endpoints is close to an endpoint
            // of the other wall. Longer hand-drawn walls retain the tolerant
            // endpoint repair and true T-junction behavior.
            const auto first_length = length(first_wall->axis);
            const auto second_length = length(second_wall->axis);
            if (first_length <= endpoint_join_tolerance_meters * 2.0 ||
                second_length <= endpoint_join_tolerance_meters * 2.0) {
                const auto short_segment_length = std::min(first_length, second_length);
                const auto short_join_tolerance = std::min(
                    endpoint_join_tolerance_meters,
                    short_segment_length * 0.5);
                const auto endpoints_are_close = [&](Line2 first_axis, Line2 second_axis) {
                    for (const auto first_point : {first_axis.start, first_axis.end}) {
                        for (const auto second_point : {second_axis.start, second_axis.end}) {
                            if (length(Line2{.start = first_point, .end = second_point}) <=
                                short_join_tolerance) {
                                return true;
                            }
                        }
                    }
                    return false;
                };
                if (!endpoints_are_close(first_wall->axis, second_wall->axis)) {
                    continue;
                }
            }

            // Two short, gently turning wall chords can still have an
            // ambiguous intersection just beyond both endpoints. The
            // endpoint-pair rule above normally filters this already; retain
            // this explicit guard for the case where both axes are short and
            // their endpoints happen to be within tolerance on opposite
            // sides of the same crossing.
            if (!first_on_segment && !second_on_segment &&
                first_length <= endpoint_join_tolerance_meters * 2.0 &&
                second_length <= endpoint_join_tolerance_meters * 2.0) {
                continue;
            }

            // Extend only the endpoint that is close to the true line
            // intersection. This is the small automatic trim that makes a
            // hand-drawn 10–15 degree corner join without changing the rest
            // of either wall.
            const auto move_nearest_endpoint = [&](Line2& axis) {
                if (first_on_segment && second_on_segment) return;
                const auto start_distance = length(Line2{.start = axis.start, .end = *line_intersection_point});
                const auto end_distance = length(Line2{.start = axis.end, .end = *line_intersection_point});
                if (start_distance <= end_distance && start_distance <= endpoint_join_tolerance_meters) {
                    axis.start = *line_intersection_point;
                } else if (end_distance <= endpoint_join_tolerance_meters) {
                    axis.end = *line_intersection_point;
                }
            };
            auto first_axis = first_wall->axis;
            auto second_axis = second_wall->axis;
            if (parallel_endpoint_join) {
                const auto snap_nearest_endpoint = [&](Line2& axis) {
                    const auto start_distance = length(Line2{.start = axis.start, .end = *line_intersection_point});
                    const auto end_distance = length(Line2{.start = axis.end, .end = *line_intersection_point});
                    if (start_distance <= end_distance && start_distance <= endpoint_join_tolerance_meters) {
                        axis.start = *line_intersection_point;
                    } else if (end_distance <= endpoint_join_tolerance_meters) {
                        axis.end = *line_intersection_point;
                    }
                };
                snap_nearest_endpoint(first_axis);
                snap_nearest_endpoint(second_axis);
            } else {
                move_nearest_endpoint(first_axis);
                move_nearest_endpoint(second_axis);
            }
            if (!(first_axis.start.x == first_wall->axis.start.x &&
                  first_axis.start.y == first_wall->axis.start.y &&
                  first_axis.end.x == first_wall->axis.end.x &&
                  first_axis.end.y == first_wall->axis.end.y)) {
                first_wall->axis = first_axis;
                mark_wall_dirty(*first);
            }
            if (!(second_axis.start.x == second_wall->axis.start.x &&
                  second_axis.start.y == second_wall->axis.start.y &&
                  second_axis.end.x == second_wall->axis.end.x &&
                  second_axis.end.y == second_wall->axis.end.y)) {
                second_wall->axis = second_axis;
                mark_wall_dirty(*second);
            }

            auto intersection = segment_intersection(first_wall->axis, second_wall->axis);
            if (!intersection.has_value() && parallel_endpoint_join) {
                intersection = line_intersection_point;
            }
            if (!intersection.has_value()) {
                continue;
            }

            const auto kind = join_kind(*intersection, first_wall->axis, second_wall->axis);
            const auto duplicate_join = [&](const std::vector<WallJoin>& joins, ElementId other_wall_id) {
                return std::any_of(joins.begin(), joins.end(), [&](const WallJoin& join) {
                    return join.other_wall_id == other_wall_id && same_point(join.point, *intersection);
                });
            };
            if (!duplicate_join(first_wall->joins, second->id())) {
                first_wall->joins.push_back(WallJoin{
                    .other_wall_id = second->id(),
                    .point = *intersection,
                    .other_axis = second_wall->axis,
                    .kind = kind,
                });
            }
            if (!duplicate_join(second_wall->joins, first->id())) {
                second_wall->joins.push_back(WallJoin{
                    .other_wall_id = first->id(),
                    .point = *intersection,
                    .other_axis = first_wall->axis,
                    .kind = kind,
                });
            }
            mark_wall_dirty(*first);
            mark_wall_dirty(*second);
        }
    }

    auto_join_structural_elements();
    invalidate_dependency_graph_cache();
}

void Document::set_automatic_wall_join_enabled(bool enabled) noexcept {
    automatic_wall_join_enabled_ = enabled;
}

void Document::auto_join_structural_elements() {
    if (resolving_structural_relations_) {
        return;
    }
    struct ResolutionScope {
        bool& active;
        ~ResolutionScope() { active = false; }
    } scope{resolving_structural_relations_};
    resolving_structural_relations_ = true;

    // Relations are cheap semantic records. They deliberately do not boolean-
    // union meshes, keeping edits and save/reload deterministic on mobile.
    beam_column_joins_.clear();
    host_relations_.clear();
    for (auto& element : elements_) {
        if (auto* wall = element.wall()) {
            const auto before = wall->openings.size();
            wall->openings.erase(std::remove_if(wall->openings.begin(), wall->openings.end(), [](const HostedOpening& opening) {
                return opening.kind == OpeningKind::StructuralVoid;
            }), wall->openings.end());
            if (wall->openings.size() != before) mark_wall_dirty(element);
        }
    }
    for (const auto& beam_element : elements_) {
        const auto* beam = beam_element.beam();
        if (beam == nullptr) continue;
        const auto dx = beam->end.x - beam->start.x;
        const auto dy = beam->end.y - beam->start.y;
        const auto length_squared = dx * dx + dy * dy;
        if (length_squared <= epsilon) continue;
        for (const auto& column_element : elements_) {
            const auto* column = column_element.column();
            if (column == nullptr || column->level_id != beam->level_id) continue;
            const auto t = std::clamp(((column->position.x - beam->start.x) * dx +
                (column->position.y - beam->start.y) * dy) / length_squared, 0.0, 1.0);
            const auto px = beam->start.x + t * dx;
            const auto py = beam->start.y + t * dy;
            const auto distance = std::hypot(column->position.x - px, column->position.y - py);
            const auto tolerance = (beam->width_meters + std::max(column->width_meters, column->depth_meters)) * 0.5 + 0.02;
            if (distance <= tolerance) {
                beam_column_joins_.emplace_back(beam_element.id(), column_element.id());
                host_relations_.push_back({.host_id = column_element.id(), .guest_id = beam_element.id(), .kind = HostRelationKind::Join, .priority = 100});
            }
        }
    }

    // Columns precisely embedded in a same-level wall are cut automatically.
    // Beams retain Embed by default: an arbitrary beam crossing a wall is not
    // enough evidence for a destructive structural opening.
    for (const auto& column_element : elements_) {
        const auto* column = column_element.column();
        if (column == nullptr) continue;
        for (const auto& wall_element : elements_) {
            const auto* wall = wall_element.wall();
            if (wall == nullptr || wall->level_id != column->level_id) continue;
            const auto dx = wall->axis.end.x - wall->axis.start.x;
            const auto dy = wall->axis.end.y - wall->axis.start.y;
            const auto length_squared = dx * dx + dy * dy;
            if (length_squared <= epsilon) continue;
            const auto t = ((column->position.x - wall->axis.start.x) * dx +
                (column->position.y - wall->axis.start.y) * dy) / length_squared;
            if (t <= 0.0 || t >= 1.0) continue;
            const auto px = wall->axis.start.x + t * dx;
            const auto py = wall->axis.start.y + t * dy;
            const auto distance = std::hypot(column->position.x - px, column->position.y - py);
            if (distance <= wall->thickness_meters * 0.5 + 0.01) {
                if (disabled_auto_structural_cuts_.contains(std::make_pair(wall_element.id(), column_element.id()))) {
                    host_relations_.push_back({.host_id = wall_element.id(), .guest_id = column_element.id(), .kind = HostRelationKind::Embed, .priority = 10});
                    continue;
                }
                try {
                    set_structural_wall_cut(wall_element.id(), column_element.id(), true);
                    host_relations_.push_back({.host_id = wall_element.id(), .guest_id = column_element.id(), .kind = HostRelationKind::Cut, .priority = 100});
                } catch (const std::invalid_argument&) {
                    host_relations_.push_back({.host_id = wall_element.id(), .guest_id = column_element.id(), .kind = HostRelationKind::Embed, .priority = 10});
                }
            }
        }
    }

    for (auto& [system_id, system] : floor_systems_) {
        system.stair_opening_ids.clear();
        for (const auto& element : elements_) {
            const auto* stair = element.stair();
            if (stair != nullptr && stair->top_level_id != 0 && stair->top_level_id == system.level_id) {
                system.stair_opening_ids.push_back(element.id());
                host_relations_.push_back({.host_id = system_id, .guest_id = element.id(), .kind = HostRelationKind::Host, .priority = 50});
            }
        }
        system.dirty = true;
        (void)system_id;
    }
    for (auto& [system_id, system] : ceiling_systems_) {
        system.stair_opening_ids.clear();
        for (const auto& element : elements_) {
            const auto* stair = element.stair();
            if (stair != nullptr && stair->top_level_id != 0 && stair->top_level_id == system.level_id) {
                system.stair_opening_ids.push_back(element.id());
                host_relations_.push_back({.host_id = system_id, .guest_id = element.id(), .kind = HostRelationKind::Host, .priority = 50});
            }
        }
        system.dirty = true;
        (void)system_id;
    }
    invalidate_dependency_graph_cache();
}

const std::vector<HostRelation>& Document::host_relations() const noexcept {
    return host_relations_;
}

std::vector<ElementId> Document::detect_rooms() {
    return recompute_all_rooms();
}

std::vector<ElementId> Document::detect_rooms_for_levels(const std::vector<ElementId>& requested_level_ids) {
    std::set<ElementId> target_levels(requested_level_ids.begin(), requested_level_ids.end());
    std::map<std::string, ElementId> previous_room_ids;
    for (const auto& element : elements_) {
        const auto* room = element.room();
        if (room == nullptr) {
            continue;
        }
        if (!target_levels.empty() && target_levels.find(room->level_id) == target_levels.end()) {
            continue;
        }

        std::ostringstream key;
        for (const auto wall_id : room->boundary_wall_ids) {
            key << wall_id << '-';
        }
        previous_room_ids[key.str()] = element.id();
    }

    elements_.erase(std::remove_if(elements_.begin(), elements_.end(), [&target_levels](const Element& element) {
        return element.kind() == ElementKind::Room && (target_levels.empty() ||
            target_levels.find(element.room()->level_id) != target_levels.end());
    }), elements_.end());

    struct WallRef {
        ElementId id{};
        const WallData* wall{};
    };

    std::map<ElementId, std::vector<WallRef>> walls_by_level;
    std::vector<double> all_xs;
    std::vector<double> all_ys;

    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            walls_by_level[wall->level_id].push_back(WallRef{.id = element.id(), .wall = wall});
            all_xs.push_back(wall->axis.start.x);
            all_xs.push_back(wall->axis.end.x);
            all_ys.push_back(wall->axis.start.y);
            all_ys.push_back(wall->axis.end.y);
        }
    }

    if (all_xs.empty() || all_ys.empty()) {
        invalidate_dependency_graph_cache();
        return {};
    }

    const auto min_global_x = *std::min_element(all_xs.begin(), all_xs.end()) - 1.0;
    const auto max_global_x = *std::max_element(all_xs.begin(), all_xs.end()) + 1.0;
    const auto min_global_y = *std::min_element(all_ys.begin(), all_ys.end()) - 1.0;
    const auto max_global_y = *std::max_element(all_ys.begin(), all_ys.end()) + 1.0;

    std::vector<ElementId> room_ids;
    // Room detection reads wall pointers from elements_.  Appending a room to
    // that vector while the sweep is still running can reallocate it and
    // invalidate every WallRef above.  Keep the discovered semantic rooms
    // separate until all wall-derived work is complete, then publish them in
    // one pass.  This is particularly important for multi-storey templates,
    // where one level can discover many rooms.
    std::vector<std::pair<ElementId, RoomData>> pending_rooms;
    std::set<ElementId> graph_detected_levels;

    // The original sweep below is very fast for orthogonal plans. A wall
    // graph is needed for diagonal/non-rectangular footprints, where a grid
    // made only from X/Y barriers would silently leave the room open. Use the
    // graph path for any level that has a usable non-cardinal face and keep
    // the established sweep for purely orthogonal levels.
    for (const auto& [level_id, walls] : walls_by_level) {
        if (!target_levels.empty() && target_levels.find(level_id) == target_levels.end()) {
            continue;
        }
        std::vector<GraphWallRef> graph_walls;
        auto has_non_orthogonal_wall = false;
        for (const auto& wall : walls) {
            if (wall.wall == nullptr) {
                continue;
            }
            graph_walls.push_back(GraphWallRef{.id = wall.id, .wall = wall.wall});
            has_non_orthogonal_wall = has_non_orthogonal_wall || wall.wall->arc.has_value() ||
                (!is_horizontal(wall.wall->axis) && !is_vertical(wall.wall->axis));
        }
        if (!has_non_orthogonal_wall) {
            continue;
        }

        const auto candidates = graph_room_candidates(graph_walls, level_id);
        if (candidates.empty()) {
            continue;
        }
        graph_detected_levels.insert(level_id);
        for (const auto& candidate : candidates) {
            const auto polygon = candidate.boundary_polygon;
            if (polygon.size() < 3 || candidate.area_square_meters <= 1.0e-6) {
                continue;
            }

            const auto wall_thickness_for_edge = [&](std::size_t edge_index) {
                if (edge_index >= candidate.boundary_edge_wall_ids.size()) {
                    return 0.15;
                }
                const auto* boundary = find_ptr(candidate.boundary_edge_wall_ids[edge_index]);
                const auto* boundary_wall = boundary == nullptr ? nullptr : boundary->wall();
                return boundary_wall == nullptr ? 0.15 : boundary_wall->thickness_meters / 2.0;
            };

            const auto build_interior = [&](bool invert) {
                std::vector<Line2> shifted_lines;
                shifted_lines.reserve(polygon.size());
                for (std::size_t index = 0; index < polygon.size(); ++index) {
                    const auto current = polygon[index];
                    const auto next = polygon[(index + 1) % polygon.size()];
                    const auto direction = subtract(next, current);
                    const auto edge_length = std::hypot(direction.x, direction.y);
                    if (edge_length <= epsilon) {
                        continue;
                    }
                    const auto normal = Point2{
                        .x = -direction.y / edge_length,
                        .y = direction.x / edge_length,
                    };
                    auto inward = invert ? -1.0 : 1.0;
                    const auto offset = wall_thickness_for_edge(index) * inward;
                    const auto shift = scale(normal, offset);
                    shifted_lines.push_back(Line2{
                        .start = add(current, shift),
                        .end = add(next, shift),
                    });
                }

                std::vector<Point2> interior_polygon;
                if (shifted_lines.size() == polygon.size()) {
                    interior_polygon.reserve(shifted_lines.size());
                    for (std::size_t index = 0; index < shifted_lines.size(); ++index) {
                        const auto& previous = shifted_lines[(index + shifted_lines.size() - 1) % shifted_lines.size()];
                        const auto& current = shifted_lines[index];
                        interior_polygon.push_back(
                            line_intersection(previous, current).value_or(polygon[index]));
                    }
                }
                interior_polygon = simplify_polygon(std::move(interior_polygon));
                auto interior_area = polygon_area(interior_polygon);
                auto interior_perimeter = 0.0;
                for (std::size_t index = 0; index < interior_polygon.size(); ++index) {
                    const auto& first = interior_polygon[index];
                    const auto& second = interior_polygon[(index + 1) % interior_polygon.size()];
                    interior_perimeter += std::hypot(second.x - first.x, second.y - first.y);
                }
                return std::tuple<std::vector<Point2>, double, double>{
                    std::move(interior_polygon), interior_area, interior_perimeter};
            };

            auto [interior_polygon, interior_area, interior_perimeter] = build_interior(false);
            if (interior_area > candidate.area_square_meters) {
                auto [alternate_polygon, alternate_area, alternate_perimeter] = build_interior(true);
                if (alternate_area < interior_area) {
                    interior_polygon = std::move(alternate_polygon);
                    interior_area = alternate_area;
                    interior_perimeter = alternate_perimeter;
                }
            }

            auto boundary_wall_ids = candidate.boundary_wall_ids;
            std::sort(boundary_wall_ids.begin(), boundary_wall_ids.end());
            auto opening_area_on_boundary = 0.0;
            for (const auto wall_id : boundary_wall_ids) {
                const auto* boundary = find_ptr(wall_id);
                const auto* boundary_wall = boundary == nullptr ? nullptr : boundary->wall();
                if (boundary_wall == nullptr) {
                    continue;
                }
                for (const auto& opening : boundary_wall->openings) {
                    opening_area_on_boundary += opening.width_meters * opening.height_meters;
                }
            }
            std::ostringstream room_key;
            for (const auto wall_id : boundary_wall_ids) {
                room_key << wall_id << '-';
            }
            const auto reused = previous_room_ids.find(room_key.str());
            const auto room_id = reused == previous_room_ids.end() ? allocate_id() : reused->second;
            const auto wall_height = walls.empty() || walls.front().wall == nullptr
                ? 3.0
                : resolved_wall_height(*walls.front().wall);
            pending_rooms.emplace_back(room_id, RoomData{
                .boundary_wall_ids = std::move(boundary_wall_ids),
                .level_id = level_id,
                .preferred_boundary_mode = RoomBoundaryMode::InteriorFinishFace,
                .centerline_boundary_polygon = polygon,
                .interior_boundary_polygon = interior_polygon,
                .centerline_area_square_meters = candidate.area_square_meters,
                .interior_area_square_meters = interior_area,
                .centerline_perimeter_meters = candidate.perimeter_meters,
                .interior_perimeter_meters = interior_perimeter,
                .floor_finish_area_square_meters = interior_area,
                .ceiling_area_square_meters = interior_area,
                .baseboard_length_meters = interior_perimeter,
                .interior_wall_finish_area_square_meters = std::max(
                    0.0,
                    (interior_perimeter * wall_height) - opening_area_on_boundary),
            });
            room_ids.push_back(room_id);
        }
    }

    for (const auto& [level_id, walls] : walls_by_level) {
        if (graph_detected_levels.find(level_id) != graph_detected_levels.end()) {
            continue;
        }
        if (!target_levels.empty() && target_levels.find(level_id) == target_levels.end()) {
            continue;
        }
        std::vector<double> xs{min_global_x, max_global_x};
        std::vector<double> ys{min_global_y, max_global_y};
        std::vector<IntervalWallRef> vertical_walls;
        std::vector<IntervalWallRef> horizontal_walls;

        for (const auto& wall_ref : walls) {
            xs.push_back(wall_ref.wall->axis.start.x);
            xs.push_back(wall_ref.wall->axis.end.x);
            ys.push_back(wall_ref.wall->axis.start.y);
            ys.push_back(wall_ref.wall->axis.end.y);

            if (is_vertical(wall_ref.wall->axis)) {
                vertical_walls.push_back(IntervalWallRef{
                    .wall_id = wall_ref.id,
                    .fixed = wall_ref.wall->axis.start.x,
                    .range_min = min_y(wall_ref.wall->axis),
                    .range_max = max_y(wall_ref.wall->axis),
                });
            } else if (is_horizontal(wall_ref.wall->axis)) {
                horizontal_walls.push_back(IntervalWallRef{
                    .wall_id = wall_ref.id,
                    .fixed = wall_ref.wall->axis.start.y,
                    .range_min = min_x(wall_ref.wall->axis),
                    .range_max = max_x(wall_ref.wall->axis),
                });
            }
        }

        std::sort(xs.begin(), xs.end());
        xs.erase(std::unique(xs.begin(), xs.end(), [](double left, double right) {
            return near(left, right);
        }), xs.end());
        std::sort(ys.begin(), ys.end());
        ys.erase(std::unique(ys.begin(), ys.end(), [](double left, double right) {
            return near(left, right);
        }), ys.end());

        if (xs.size() < 2 || ys.size() < 2) {
            continue;
        }

        const auto width = xs.size() - 1;
        const auto height = ys.size() - 1;
        const auto cell_index = [width](std::size_t x, std::size_t y) {
            return (y * width) + x;
        };
        const auto total_cells = width * height;
        std::vector<bool> visited(total_cells, false);

        const auto vertical_barrier = [&](double x, double y0, double y1, std::vector<ElementId>* wall_ids = nullptr) {
            auto blocked = false;
            for (const auto& wall : vertical_walls) {
                if (near(wall.fixed, x) && interval_covered(y0, y1, wall.range_min, wall.range_max)) {
                    blocked = true;
                    if (wall_ids != nullptr) {
                        append_unique(*wall_ids, wall.wall_id);
                    }
                }
            }
            return blocked;
        };
        const auto horizontal_barrier = [&](double y, double x0, double x1, std::vector<ElementId>* wall_ids = nullptr) {
            auto blocked = false;
            for (const auto& wall : horizontal_walls) {
                if (near(wall.fixed, y) && interval_covered(x0, x1, wall.range_min, wall.range_max)) {
                    blocked = true;
                    if (wall_ids != nullptr) {
                        append_unique(*wall_ids, wall.wall_id);
                    }
                }
            }
            return blocked;
        };

        for (std::size_t start_y = 0; start_y < height; ++start_y) {
            for (std::size_t start_x = 0; start_x < width; ++start_x) {
                const auto start_index = cell_index(start_x, start_y);
                if (visited[start_index]) {
                    continue;
                }

                std::vector<std::pair<std::size_t, std::size_t>> component_cells;
                std::vector<std::pair<Point2, Point2>> boundary_edges;
                std::vector<ElementId> boundary_wall_ids;
                auto touches_outside = false;

                std::vector<std::pair<std::size_t, std::size_t>> queue{{start_x, start_y}};
                visited[start_index] = true;

                for (std::size_t cursor = 0; cursor < queue.size(); ++cursor) {
                    const auto [cell_x, cell_y] = queue[cursor];
                    component_cells.push_back({cell_x, cell_y});

                    if (cell_x == 0 || cell_y == 0 || cell_x + 1 == width || cell_y + 1 == height) {
                        touches_outside = true;
                    }

                    const auto x0 = xs[cell_x];
                    const auto x1 = xs[cell_x + 1];
                    const auto y0 = ys[cell_y];
                    const auto y1 = ys[cell_y + 1];

                    const auto try_visit = [&](std::size_t next_x, std::size_t next_y) {
                        const auto index = cell_index(next_x, next_y);
                        if (!visited[index]) {
                            visited[index] = true;
                            queue.push_back({next_x, next_y});
                        }
                    };

                    std::vector<ElementId> edge_walls;
                    if (!vertical_barrier(x0, y0, y1, &edge_walls)) {
                        if (cell_x > 0) {
                            try_visit(cell_x - 1, cell_y);
                        }
                    } else {
                        boundary_edges.push_back({Point2{.x = x0, .y = y1}, Point2{.x = x0, .y = y0}});
                        for (const auto wall_id : edge_walls) {
                            append_unique(boundary_wall_ids, wall_id);
                        }
                    }

                    edge_walls.clear();
                    if (!vertical_barrier(x1, y0, y1, &edge_walls)) {
                        if (cell_x + 1 < width) {
                            try_visit(cell_x + 1, cell_y);
                        }
                    } else {
                        boundary_edges.push_back({Point2{.x = x1, .y = y0}, Point2{.x = x1, .y = y1}});
                        for (const auto wall_id : edge_walls) {
                            append_unique(boundary_wall_ids, wall_id);
                        }
                    }

                    edge_walls.clear();
                    if (!horizontal_barrier(y0, x0, x1, &edge_walls)) {
                        if (cell_y > 0) {
                            try_visit(cell_x, cell_y - 1);
                        }
                    } else {
                        boundary_edges.push_back({Point2{.x = x0, .y = y0}, Point2{.x = x1, .y = y0}});
                        for (const auto wall_id : edge_walls) {
                            append_unique(boundary_wall_ids, wall_id);
                        }
                    }

                    edge_walls.clear();
                    if (!horizontal_barrier(y1, x0, x1, &edge_walls)) {
                        if (cell_y + 1 < height) {
                            try_visit(cell_x, cell_y + 1);
                        }
                    } else {
                        boundary_edges.push_back({Point2{.x = x1, .y = y1}, Point2{.x = x0, .y = y1}});
                        for (const auto wall_id : edge_walls) {
                            append_unique(boundary_wall_ids, wall_id);
                        }
                    }
                }

                if (touches_outside || boundary_edges.empty()) {
                    continue;
                }

                std::map<std::string, std::pair<Point2, Point2>> edges_by_start;
                for (const auto& edge : boundary_edges) {
                    std::ostringstream key;
                    key << edge.first.x << ':' << edge.first.y << ':' << edge.second.x << ':' << edge.second.y;
                    edges_by_start[key.str()] = edge;
                }

                std::vector<Point2> polygon;
                auto current_edge = boundary_edges.front();
                polygon.push_back(current_edge.first);
                auto guard = 0U;

                while (guard++ < boundary_edges.size() + 4) {
                    polygon.push_back(current_edge.second);
                    if (same_point(current_edge.second, polygon.front())) {
                        break;
                    }

                    auto found_next = false;
                    for (const auto& candidate : boundary_edges) {
                        if (same_point(candidate.first, current_edge.second)) {
                            current_edge = candidate;
                            found_next = true;
                            break;
                        }
                    }
                    if (!found_next) {
                        break;
                    }
                }

                if (!polygon.empty() && same_point(polygon.front(), polygon.back())) {
                    polygon.pop_back();
                }
                polygon = simplify_polygon(std::move(polygon));

                auto centerline_area = 0.0;
                for (const auto& [cell_x, cell_y] : component_cells) {
                    centerline_area += (xs[cell_x + 1] - xs[cell_x]) * (ys[cell_y + 1] - ys[cell_y]);
                }

                auto centerline_perimeter = 0.0;
                for (const auto& edge : boundary_edges) {
                    centerline_perimeter += std::abs(edge.first.x - edge.second.x) + std::abs(edge.first.y - edge.second.y);
                }

                const auto signed_area = [&]() {
                    auto value = 0.0;
                    for (std::size_t index = 0; index < polygon.size(); ++index) {
                        const auto& current = polygon[index];
                        const auto& next = polygon[(index + 1) % polygon.size()];
                        value += (current.x * next.y) - (next.x * current.y);
                    }
                    return value / 2.0;
                }();
                const auto clockwise = signed_area < 0.0;

                const auto build_interior = [&](bool invert) {
                    std::vector<std::pair<bool, double>> shifted_lines;
                    shifted_lines.reserve(polygon.size());
                    for (std::size_t index = 0; index < polygon.size(); ++index) {
                        const auto& current = polygon[index];
                        const auto& next = polygon[(index + 1) % polygon.size()];
                        const auto vertical = near(current.x, next.x);
                        auto offset = 0.0;
                        for (const auto wall_id : boundary_wall_ids) {
                            const auto* boundary = find_ptr(wall_id);
                            const auto* boundary_wall = boundary == nullptr ? nullptr : boundary->wall();
                            if (boundary_wall == nullptr) {
                                continue;
                            }
                            if (vertical && is_vertical(boundary_wall->axis) &&
                                near(boundary_wall->axis.start.x, current.x) &&
                                interval_covered(std::min(current.y, next.y), std::max(current.y, next.y), min_y(boundary_wall->axis), max_y(boundary_wall->axis))) {
                                offset = boundary_wall->thickness_meters / 2.0;
                                break;
                            }
                            if (!vertical && is_horizontal(boundary_wall->axis) &&
                                near(boundary_wall->axis.start.y, current.y) &&
                                interval_covered(std::min(current.x, next.x), std::max(current.x, next.x), min_x(boundary_wall->axis), max_x(boundary_wall->axis))) {
                                offset = boundary_wall->thickness_meters / 2.0;
                                break;
                            }
                        }

                        if (vertical) {
                            const auto moving_up = next.y > current.y;
                            auto inward = clockwise ? (moving_up ? -1.0 : 1.0) : (moving_up ? 1.0 : -1.0);
                            if (invert) {
                                inward *= -1.0;
                            }
                            shifted_lines.push_back({true, current.x + (inward * offset)});
                        } else {
                            const auto moving_right = next.x > current.x;
                            auto inward = clockwise ? (moving_right ? 1.0 : -1.0) : (moving_right ? -1.0 : 1.0);
                            if (invert) {
                                inward *= -1.0;
                            }
                            shifted_lines.push_back({false, current.y + (inward * offset)});
                        }
                    }

                    std::vector<Point2> candidate_polygon;
                    candidate_polygon.reserve(polygon.size());
                    for (std::size_t index = 0; index < polygon.size(); ++index) {
                        const auto previous_line = shifted_lines[(index + shifted_lines.size() - 1) % shifted_lines.size()];
                        const auto current_line = shifted_lines[index];
                        if (previous_line.first) {
                            candidate_polygon.push_back(Point2{.x = previous_line.second, .y = current_line.second});
                        } else {
                            candidate_polygon.push_back(Point2{.x = current_line.second, .y = previous_line.second});
                        }
                    }
                    candidate_polygon = simplify_polygon(std::move(candidate_polygon));

                    auto candidate_area = 0.0;
                    auto candidate_perimeter = 0.0;
                    if (candidate_polygon.size() >= 3) {
                        for (std::size_t index = 0; index < candidate_polygon.size(); ++index) {
                            const auto& current = candidate_polygon[index];
                            const auto& next = candidate_polygon[(index + 1) % candidate_polygon.size()];
                            candidate_area += (current.x * next.y) - (next.x * current.y);
                            candidate_perimeter += std::abs(current.x - next.x) + std::abs(current.y - next.y);
                        }
                        candidate_area = std::abs(candidate_area) / 2.0;
                    }
                    return std::tuple<std::vector<Point2>, double, double>{candidate_polygon, candidate_area, candidate_perimeter};
                };

                auto [interior_polygon, interior_area, interior_perimeter] = build_interior(false);
                if (interior_area > centerline_area) {
                    auto [alt_polygon, alt_area, alt_perimeter] = build_interior(true);
                    if (alt_area < interior_area) {
                        interior_polygon = std::move(alt_polygon);
                        interior_area = alt_area;
                        interior_perimeter = alt_perimeter;
                    }
                }

                std::sort(boundary_wall_ids.begin(), boundary_wall_ids.end());
                auto opening_area_on_boundary = 0.0;
                for (const auto wall_id : boundary_wall_ids) {
                    const auto* boundary = find_ptr(wall_id);
                    const auto* boundary_wall = boundary == nullptr ? nullptr : boundary->wall();
                    if (boundary_wall == nullptr) {
                        continue;
                    }
                    for (const auto& opening : boundary_wall->openings) {
                        opening_area_on_boundary += opening.width_meters * opening.height_meters;
                    }
                }
                std::ostringstream room_key;
                for (const auto wall_id : boundary_wall_ids) {
                    room_key << wall_id << '-';
                }

                const auto reused = previous_room_ids.find(room_key.str());
                const auto room_id = reused == previous_room_ids.end() ? allocate_id() : reused->second;
                pending_rooms.emplace_back(room_id, RoomData{
                    .boundary_wall_ids = boundary_wall_ids,
                    .level_id = level_id,
                    .preferred_boundary_mode = RoomBoundaryMode::InteriorFinishFace,
                    .centerline_boundary_polygon = polygon,
                    .interior_boundary_polygon = interior_polygon,
                    .centerline_area_square_meters = centerline_area,
                    .interior_area_square_meters = interior_area,
                    .centerline_perimeter_meters = centerline_perimeter,
                    .interior_perimeter_meters = interior_perimeter,
                    .floor_finish_area_square_meters = interior_area,
                    .ceiling_area_square_meters = interior_area,
                    .baseboard_length_meters = interior_perimeter,
                    .interior_wall_finish_area_square_meters = std::max(0.0, (interior_perimeter * resolved_wall_height(*walls.front().wall)) - opening_area_on_boundary),
                });
                room_ids.push_back(room_id);
            }
        }
    }

    // See pending_rooms above: only now is it safe to grow elements_.
    for (auto& [room_id, room] : pending_rooms) {
        elements_.emplace_back(room_id, ElementKind::Room, "Room", std::move(room));
    }

    for (auto it = floor_systems_.begin(); it != floor_systems_.end();) {
        if (it->second.room_id == 0) {
            ++it;
            continue;
        }
        const auto* room = find_ptr(it->second.room_id);
        if (room == nullptr || room->room() == nullptr) {
            it = floor_systems_.erase(it);
            continue;
        }
        update_floor_system_from_room(it->second.room_id);
        ++it;
    }

    for (auto it = ceiling_systems_.begin(); it != ceiling_systems_.end();) {
        if (it->second.room_id == 0) {
            ++it;
            continue;
        }
        const auto* room = find_ptr(it->second.room_id);
        if (room == nullptr || room->room() == nullptr) {
            it = ceiling_systems_.erase(it);
            continue;
        }
        update_ceiling_system_from_room(it->second.room_id);
        ++it;
    }

    invalidate_dependency_graph_cache();
    return room_ids;
}

void Document::mark_rooms_dirty_for_wall(ElementId wall_id) {
    const auto dependent_rooms = dependency_graph().dependent_rooms(wall_id);
    for (const auto room_id : dependent_rooms) {
        if (std::find(dirty_room_ids_.begin(), dirty_room_ids_.end(), room_id) == dirty_room_ids_.end()) {
            dirty_room_ids_.push_back(room_id);
        }
        for (auto& [_, system] : floor_systems_) {
            if (system.room_id == room_id) {
                system.dirty = true;
            }
        }
        for (auto& [_, system] : ceiling_systems_) {
            if (system.room_id == room_id) {
                system.dirty = true;
            }
        }
    }
    const auto* wall_element = find_ptr(wall_id);
    const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
    const auto level_id = wall == nullptr ? 0 : wall->level_id;
    if (level_id != 0 && std::find(dirty_room_level_ids_.begin(), dirty_room_level_ids_.end(), level_id) == dirty_room_level_ids_.end()) {
        dirty_room_level_ids_.push_back(level_id);
    }
}

double Document::level_elevation(ElementId level_id) const {
    if (level_id == 0) {
        return 0.0;
    }
    const auto* element = find_ptr(level_id);
    const auto* level = element == nullptr ? nullptr : element->level();
    if (level == nullptr) {
        throw std::invalid_argument("level does not exist");
    }
    return level->elevation_meters;
}

double Document::resolved_wall_base_elevation(const WallData& wall) const {
    return level_elevation(wall.base_level_id != 0 ? wall.base_level_id : wall.level_id) + wall.base_offset_meters;
}

double Document::resolved_wall_height(const WallData& wall) const {
    if (wall.height_mode == WallHeightMode::TopLevel && wall.top_level_id != 0) {
        const auto top = level_elevation(wall.top_level_id) + wall.top_offset_meters;
        return std::max(0.01, top - resolved_wall_base_elevation(wall));
    }
    return std::max(0.01, wall.height_meters);
}

double Document::resolved_roof_surface_area(const RoofData& roof) const {
    return roof_surface_area(roof);
}

void Document::update_level(
    ElementId level_id,
    std::optional<std::string> name,
    std::optional<double> elevation_meters,
    std::optional<double> default_wall_height_meters
) {
    auto& level_element = require_level(level_id);
    auto* level = const_cast<LevelData*>(level_element.level());
    if (level == nullptr) {
        throw std::invalid_argument("level does not exist");
    }
    if (name.has_value()) {
        if (name->empty()) {
            throw std::invalid_argument("level name must not be empty");
        }
        level->name = *name;
    }
    if (default_wall_height_meters.has_value()) {
        if (!std::isfinite(*default_wall_height_meters) || *default_wall_height_meters <= 0.0) {
            throw std::invalid_argument("default wall height must be positive");
        }
        level->default_wall_height_meters = *default_wall_height_meters;
    }
    if (elevation_meters.has_value()) {
        move_level_elevation(level_id, *elevation_meters);
        return;
    }
    level_element.touch();
    invalidate_dependency_graph_cache();
}

void Document::move_level_elevation(ElementId level_id, double elevation_meters) {
    auto& level_element = require_level(level_id);
    auto* level = const_cast<LevelData*>(level_element.level());
    if (level == nullptr) {
        throw std::invalid_argument("level does not exist");
    }
    if (!std::isfinite(elevation_meters)) {
        throw std::invalid_argument("level elevation must be finite");
    }
    if (std::abs(level->elevation_meters - elevation_meters) <= epsilon) {
        return;
    }
    for (const auto& element : elements_) {
        const auto* other = element.level();
        if (other != nullptr && element.id() != level_id &&
            std::abs(other->elevation_meters - elevation_meters) <= epsilon) {
            throw std::invalid_argument("level elevations must be unique");
        }
    }

    const auto elevation_for = [&](ElementId candidate_id) {
        return candidate_id == level_id ? elevation_meters : level_elevation(candidate_id);
    };
    for (const auto& element : elements_) {
        if (const auto* wall = element.wall(); wall != nullptr &&
            wall->height_mode == WallHeightMode::TopLevel && wall->top_level_id != 0) {
            const auto base_id = wall->base_level_id != 0 ? wall->base_level_id : wall->level_id;
            const auto base = elevation_for(base_id) + wall->base_offset_meters;
            const auto top = elevation_for(wall->top_level_id) + wall->top_offset_meters;
            if (!std::isfinite(base) || !std::isfinite(top) || top <= base + epsilon) {
                throw std::invalid_argument("moving level would invert a wall top/base constraint");
            }
        }
        if (const auto* stair = element.stair(); stair != nullptr &&
            stair->top_level_id != 0 && stair->top_level_id != stair->base_level_id &&
            elevation_for(stair->top_level_id) <= elevation_for(stair->base_level_id) + epsilon) {
            throw std::invalid_argument("moving level would invert a stair top/base constraint");
        }
    }
    level->elevation_meters = elevation_meters;
    level_element.touch();

    for (auto& element : elements_) {
        if (auto* wall = element.wall(); wall != nullptr) {
            if (wall->level_id == level_id || wall->base_level_id == level_id || wall->top_level_id == level_id) {
                mark_wall_dirty(element);
                for (const auto& opening : wall->openings) {
                    const auto* opening_element = find_ptr(opening.element_id);
                    const auto follows_level = opening_element != nullptr &&
                        ((opening_element->door() != nullptr && opening_element->door()->level_locked) ||
                         (opening_element->window() != nullptr && opening_element->window()->level_locked));
                    if (follows_level) {
                        sync_opening_level_constraint(opening.element_id);
                    }
                }
                refresh_dependencies_for_wall(element.id());
            }
        } else if (auto* door = element.door(); door != nullptr) {
            if (door->level_locked && door->level_id == level_id) {
                sync_opening_level_constraint(element.id());
                element.touch();
            }
        } else if (auto* window = element.window(); window != nullptr) {
            if (window->level_locked && window->level_id == level_id) {
                sync_opening_level_constraint(element.id());
                element.touch();
            }
        } else if (auto* slab = element.slab(); slab != nullptr) {
            if (slab->level_id == level_id) {
                slab->generated_geometry_dirty = true;
                element.touch();
            }
        } else if (auto* roof = element.roof(); roof != nullptr) {
            if (roof->level_id == level_id) {
                roof->generated_geometry_dirty = true;
                element.touch();
            }
        } else if (auto* column = element.column(); column != nullptr) {
            if (column->level_id == level_id) {
                column->generated_geometry_dirty = true;
                element.touch();
            }
        } else if (auto* beam = element.beam(); beam != nullptr) {
            if (beam->level_id == level_id) {
                beam->generated_geometry_dirty = true;
                element.touch();
            }
        } else if (auto* stair = element.stair(); stair != nullptr) {
            if (stair->base_level_id == level_id || stair->top_level_id == level_id) {
                stair->generated_geometry_dirty = true;
                element.touch();
            }
        }
    }

    for (auto& [system_id, system] : floor_systems_) {
        if (system.level_id == level_id) {
            system.dirty = true;
        }
    }
    for (auto& [system_id, system] : ceiling_systems_) {
        if (system.level_id == level_id) {
            system.dirty = true;
        }
    }
    invalidate_dependency_graph_cache();
}

void Document::set_wall_level_constraints(
    ElementId wall_id,
    ElementId base_level_id,
    ElementId top_level_id,
    double base_offset_meters,
    double top_offset_meters,
    WallHeightMode height_mode
) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (base_level_id != 0) {
        (void)require_level(base_level_id);
    }
    if (top_level_id != 0) {
        (void)require_level(top_level_id);
    }
    if (height_mode == WallHeightMode::TopLevel && top_level_id == 0) {
        throw std::invalid_argument("top level constraint requires top_level_id");
    }
    if (!std::isfinite(base_offset_meters) || !std::isfinite(top_offset_meters)) {
        throw std::invalid_argument("wall level offsets must be finite");
    }
    if (height_mode == WallHeightMode::TopLevel) {
        const auto base = level_elevation(base_level_id) + base_offset_meters;
        const auto top = level_elevation(top_level_id) + top_offset_meters;
        if (!std::isfinite(base) || !std::isfinite(top) || top <= base + epsilon) {
            throw std::invalid_argument("wall top level must be above base level");
        }
    }
    wall->base_level_id = base_level_id;
    wall->level_id = base_level_id;
    wall->top_level_id = top_level_id;
    wall->base_offset_meters = base_offset_meters;
    wall->top_offset_meters = top_offset_meters;
    wall->height_mode = height_mode;
    for (const auto& opening : wall->openings) {
        const auto* opening_element = find_ptr(opening.element_id);
        const auto follows_level = opening_element != nullptr &&
            ((opening_element->door() != nullptr && opening_element->door()->level_locked) ||
             (opening_element->window() != nullptr && opening_element->window()->level_locked));
        if (follows_level) {
            sync_opening_level_constraint(opening.element_id);
        }
    }
    validate_wall_axis(wall->axis, wall->thickness_meters, resolved_wall_height(*wall));
    validate_wall_openings(*wall);
    mark_wall_dirty(wall_element);
    refresh_dependencies_for_wall(wall_id);
    invalidate_dependency_graph_cache();
}

void Document::set_opening_level_lock(ElementId opening_id, bool locked) {
    auto* element = find_ptr(opening_id);
    if (element == nullptr) {
        throw std::invalid_argument("opening does not exist");
    }
    if (auto* door_data = element->door(); door_data != nullptr) {
        door_data->level_locked = locked;
        if (locked) {
            sync_opening_level_constraint(opening_id);
        }
        element->touch();
        invalidate_dependency_graph_cache();
        return;
    }
    if (auto* window_data = element->window(); window_data != nullptr) {
        window_data->level_locked = locked;
        if (locked) {
            sync_opening_level_constraint(opening_id);
        }
        element->touch();
        invalidate_dependency_graph_cache();
        return;
    }
    throw std::invalid_argument("element is not a hosted opening");
}

void Document::set_opening_level(ElementId opening_id, ElementId level_id) {
    set_opening_level_constraint(opening_id, level_id, 0.0);
}

void Document::set_opening_level_constraint(
    ElementId opening_id,
    ElementId level_id,
    double level_offset_meters
) {
    (void)require_level(level_id);
    auto* element = find_ptr(opening_id);
    if (element == nullptr) {
        throw std::invalid_argument("opening does not exist");
    }

    if (auto* door_data = element->door(); door_data != nullptr) {
        const auto* host = find_ptr(door_data->host_wall_id);
        const auto* host_wall = host == nullptr ? nullptr : host->wall();
        if (host_wall == nullptr) {
            throw std::invalid_argument("opening host wall does not exist");
        }
        const auto offset = level_elevation(level_id) + level_offset_meters - resolved_wall_base_elevation(*host_wall);
        auto updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Door,
            .offset_meters = door_data->offset_meters,
            .width_meters = door_data->width_meters,
            .height_meters = door_data->height_meters,
            .sill_height_meters = 0.0,
            .vertical_offset_meters = offset,
        };
        auto wall_copy = *host_wall;
        for (auto& opening : wall_copy.openings) {
            if (opening.element_id == opening_id) {
                opening = updated;
            }
        }
        validate_wall_openings(wall_copy);
        door_data->level_id = level_id;
        door_data->level_offset_meters = level_offset_meters;
        door_data->level_locked = true;
        door_data->vertical_offset_meters = offset;
        element->touch();
        update_wall_opening(door_data->host_wall_id, updated);
        invalidate_dependency_graph_cache();
        return;
    }

    if (auto* window_data = element->window(); window_data != nullptr) {
        const auto* host = find_ptr(window_data->host_wall_id);
        const auto* host_wall = host == nullptr ? nullptr : host->wall();
        if (host_wall == nullptr) {
            throw std::invalid_argument("opening host wall does not exist");
        }
        const auto offset = level_elevation(level_id) + level_offset_meters - resolved_wall_base_elevation(*host_wall);
        auto updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Window,
            .offset_meters = window_data->offset_meters,
            .width_meters = window_data->width_meters,
            .height_meters = window_data->height_meters,
            .sill_height_meters = window_data->sill_height_meters,
            .vertical_offset_meters = offset,
        };
        auto wall_copy = *host_wall;
        for (auto& opening : wall_copy.openings) {
            if (opening.element_id == opening_id) {
                opening = updated;
            }
        }
        validate_wall_openings(wall_copy);
        window_data->level_id = level_id;
        window_data->level_offset_meters = level_offset_meters;
        window_data->level_locked = true;
        window_data->vertical_offset_meters = offset;
        element->touch();
        update_wall_opening(window_data->host_wall_id, updated);
        invalidate_dependency_graph_cache();
        return;
    }

    throw std::invalid_argument("element is not a hosted opening");
}

std::vector<Point2> Document::normalized_profile_polygon(const ProfileDraft& draft) const {
    std::vector<Point2> polygon;
    switch (draft.mode) {
    case ProfileDraftMode::Rectangle: {
        if (draft.points.size() < 2) {
            break;
        }
        const auto first = draft.points.front();
        const auto last = draft.points.back();
        polygon = {
            Point2{.x = std::min(first.x, last.x), .y = std::min(first.y, last.y)},
            Point2{.x = std::max(first.x, last.x), .y = std::min(first.y, last.y)},
            Point2{.x = std::max(first.x, last.x), .y = std::max(first.y, last.y)},
            Point2{.x = std::min(first.x, last.x), .y = std::max(first.y, last.y)},
        };
        break;
    }
    case ProfileDraftMode::PickWalls: {
        polygon = build_pick_wall_loop(*this, draft.picked_wall_ids).polygon;
        break;
    }
    case ProfileDraftMode::Polyline:
    case ProfileDraftMode::AutoRoom:
        polygon = draft.points;
        break;
    }
    if (!polygon.empty() && same_point(polygon.front(), polygon.back())) {
        polygon.pop_back();
    }
    return simplify_polygon(std::move(polygon));
}

std::vector<ElementId> Document::create_elements_from_profile(const ProfileDraft& draft) {
    if (draft.level_id != 0) {
        (void)require_level(draft.level_id);
    }

    // Pick Walls is also an authoring operation: repair small touch gaps and
    // refresh joins before the profile solver validates the selected loop.
    if (draft.mode == ProfileDraftMode::PickWalls && automatic_wall_join_enabled_) {
        auto_join_walls();
    }

    std::vector<ElementId> created_ids;
    if (draft.target_kind == ProfileTargetKind::WallPath) {
        const auto points = normalized_profile_polygon(draft);
        if (points.size() < 2) {
            throw std::invalid_argument("wall path needs at least 2 points");
        }
        const auto default_height = draft.level_id == 0 ? 3.0 : require_level(draft.level_id).level()->default_wall_height_meters;
        for (std::size_t index = 1; index < points.size(); ++index) {
            if (same_point(points[index - 1], points[index])) {
                continue;
            }
            created_ids.push_back(create_wall(
                "Wall",
                Line2{.start = points[index - 1], .end = points[index]},
                draft.thickness_meters > 0.0 ? draft.thickness_meters : 0.2,
                draft.height_meters > 0.0 ? draft.height_meters : default_height,
                draft.level_id
            ));
        }
        if (draft.closed && points.size() > 2 && !same_point(points.front(), points.back())) {
            created_ids.push_back(create_wall(
                "Wall",
                Line2{.start = points.back(), .end = points.front()},
                draft.thickness_meters > 0.0 ? draft.thickness_meters : 0.2,
                draft.height_meters > 0.0 ? draft.height_meters : default_height,
                draft.level_id
            ));
        }
        auto_join_walls();
        return created_ids;
    }

    auto polygon = normalized_profile_polygon(draft);
    validate_profile_polygon(polygon, draft.target_kind);

    switch (draft.target_kind) {
    case ProfileTargetKind::FloorBoundary:
        created_ids.push_back(create_floor_system_from_profile(
            draft.level_id,
            std::move(polygon),
            draft.assembly_id,
            draft.thickness_meters
        ));
        break;
    case ProfileTargetKind::CeilingBoundary:
        created_ids.push_back(create_ceiling_system_from_profile(
            draft.level_id,
            std::move(polygon),
            draft.assembly_id,
            normalized_ceiling_height_offset(draft.vertical_offset_meters)
        ));
        break;
    case ProfileTargetKind::RoofBoundary: {
        // Keep the engine-side wall relationship.  The UI may provide a
        // preview polygon, but it must not become the only source of truth.
        std::vector<ElementId> roof_source_wall_ids;
        if (draft.mode == ProfileDraftMode::PickWalls) {
            roof_source_wall_ids = build_pick_wall_loop(*this, draft.picked_wall_ids).ordered_wall_ids;
        }
        created_ids.push_back(create_roof(
            draft.level_id,
            std::move(polygon),
            draft.roof_type,
            draft.thickness_meters > 0.0 ? draft.thickness_meters : 0.2,
            draft.material_id,
            draft.assembly_id,
            std::nullopt,
            std::nullopt,
            std::move(roof_source_wall_ids)
        ));
        break;
    }
    case ProfileTargetKind::WallPath:
        break;
    }
    invalidate_dependency_graph_cache();
    return created_ids;
}

std::vector<ElementId> Document::recompute_dirty_rooms() {
    if (dirty_room_ids_.empty() && dirty_room_level_ids_.empty()) {
        return {};
    }

    auto level_ids = dirty_room_level_ids_;
    for (const auto room_id : dirty_room_ids_) {
        const auto* room_element = find_ptr(room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room != nullptr && std::find(level_ids.begin(), level_ids.end(), room->level_id) == level_ids.end()) {
            level_ids.push_back(room->level_id);
        }
    }
    dirty_room_ids_.clear();
    dirty_room_level_ids_.clear();
    return detect_rooms_for_levels(level_ids);
}

std::vector<ElementId> Document::recompute_all_rooms() {
    std::vector<ElementId> level_ids;
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall != nullptr && std::find(level_ids.begin(), level_ids.end(), wall->level_id) == level_ids.end()) {
            level_ids.push_back(wall->level_id);
        }
    }
    return detect_rooms_for_levels(level_ids);
}

const std::vector<ElementId>& Document::dirty_room_ids() const noexcept {
    return dirty_room_ids_;
}

void Document::clear_dirty_room_requests() noexcept {
    dirty_room_ids_.clear();
    dirty_room_level_ids_.clear();
}

void Document::regenerate_dirty_geometry(GeometryDetail detail) {
    GeometryService geometry;
    for (auto& element : elements_) {
        auto* wall = element.wall();
        if (wall != nullptr) {
            auto resolved = *wall;
            resolved.height_meters = resolved_wall_height(*wall);
            const auto* wall_assembly = wall->assembly_id == 0 ? nullptr : get_layered_assembly(wall->assembly_id);
            const auto* wall_type = wall->wall_type_id == 0 ? nullptr : get_wall_type(wall->wall_type_id);
            // WallTypeData is authoritative whenever a malformed/legacy
            // record happens to carry both references. Normal project loads
            // remove the second reference, but regeneration must remain safe
            // for raw documents too.
            const auto* layers = wall_type != nullptr
                ? &wall_type->layers
                : (wall_assembly != nullptr ? &wall_assembly->layers : nullptr);
            const auto assembly_revision = cache_assembly_revision(wall_assembly);
            if (layers != nullptr && !layers->empty()) {
                resolved.thickness_meters = std::accumulate(layers->begin(), layers->end(), 0.0, [](double total, const auto& layer) {
                    return total + layer.thickness_meters;
                });
            }

            if (detail == GeometryDetail::Envelope) {
                const auto envelope_needs_rebuild = wall->geometry.dirty || wall->geometry_is_layered;
                if (envelope_needs_rebuild) {
                    wall->geometry = geometry.build_wall_geometry(
                        resolved,
                        element.revision(),
                        {}
                    );
                    wall->geometry_is_layered = false;
                }
                if (layers != nullptr && !layers->empty() &&
                    !wall->geometry.mesh.indices.empty()) {
                    // One proxy material slot keeps the envelope
                    // material-aware without expanding the viewport mesh
                    // into every compound layer. Refresh the slot even when
                    // only layer metadata changed and the envelope vertices
                    // were reusable.
                    const auto triangle_count = wall->geometry.mesh.indices.size() / 3;
                    const auto material_changed =
                        wall->geometry.mesh.triangle_material_ids.size() != triangle_count ||
                        std::any_of(
                            wall->geometry.mesh.triangle_material_ids.begin(),
                            wall->geometry.mesh.triangle_material_ids.end(),
                            [&](ElementId material_id) {
                                return material_id != layers->front().material_id;
                            }
                        );
                    if (material_changed) {
                        wall->geometry.mesh.triangle_material_ids.assign(
                            triangle_count,
                            layers->front().material_id
                        );
                    }
                }
            } else if (wall->layered_geometry.dirty ||
                       wall->layered_geometry.assembly_revision != assembly_revision) {
                wall->layered_geometry = geometry.build_wall_geometry(
                    resolved,
                    element.revision(),
                    layers == nullptr ? std::vector<WallAssemblyLayer>{} : *layers
                );
                wall->layered_geometry.assembly_revision = assembly_revision;
            }
            if (detail == GeometryDetail::Layered) {
                // Keep the historical geometry field as the requested active
                // detail for callers that explicitly ask for Layered. The
                // envelope cache remains available for the next interactive
                // preview without rebuilding the compound mesh.
                wall->geometry = wall->layered_geometry;
                wall->geometry_is_layered = true;
            }
        }

        auto* slab = element.slab();
        if (slab != nullptr) {
            const auto needs_recompute = slab->generated_geometry_dirty;
            const auto* slab_assembly = slab->assembly_id == 0 ? nullptr : get_layered_assembly(slab->assembly_id);
            const auto assembly_revision = cache_assembly_revision(slab_assembly);
            const auto thickness = slab_assembly == nullptr
                ? slab->thickness_meters
                : layered_assembly_total_thickness(*slab_assembly);
            if (needs_recompute) {
                slab->area_square_meters = polygon_area(slab->boundary_polygon);
                slab->thickness_meters = thickness;
                slab->volume_cubic_meters = slab->area_square_meters * thickness;
            }

            const auto build_envelope = [&]() {
                auto envelope_mesh = extrude_polygon_mesh(
                    slab->boundary_polygon,
                    thickness,
                    slab->elevation_offset_meters
                );
                if (slab_assembly != nullptr && !slab_assembly->layers.empty() &&
                    !envelope_mesh.indices.empty()) {
                    envelope_mesh.triangle_material_ids.assign(
                        envelope_mesh.indices.size() / 3,
                        slab_assembly->layers.front().material_id
                    );
                }
                slab->envelope_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(envelope_mesh),
                };
                slab->mesh = slab->envelope_geometry.mesh;
                slab->geometry_is_layered = false;
                slab->layered_geometry.dirty = slab_assembly != nullptr;
            };

            const auto refresh_envelope_material = [&]() {
                (void)rebind_envelope_material(
                    slab->envelope_geometry,
                    slab->mesh,
                    slab->geometry_is_layered,
                    slab_assembly
                );
            };
            if (!slab->envelope_geometry.dirty &&
                slab->envelope_geometry.assembly_revision != assembly_revision) {
                // Rebind only material metadata when the shared assembly
                // changed without changing its total thickness. This keeps
                // imported/exact vertices intact and avoids a full rebuild.
                refresh_envelope_material();
            }

            if (detail == GeometryDetail::Envelope) {
                if (needs_recompute || slab->geometry_is_layered ||
                    slab->envelope_geometry.dirty) {
                    if (!needs_recompute && !slab->envelope_geometry.dirty &&
                        !slab->envelope_geometry.mesh.indices.empty()) {
                        refresh_envelope_material();
                        slab->mesh = slab->envelope_geometry.mesh;
                        slab->geometry_is_layered = false;
                    } else {
                        build_envelope();
                    }
                }
            } else if (slab_assembly != nullptr &&
                       (needs_recompute || slab->layered_geometry.dirty ||
                        slab->layered_geometry.assembly_revision != assembly_revision)) {
                auto layered_mesh = build_layered_slab_mesh(
                    slab->boundary_polygon,
                    *slab_assembly,
                    slab->elevation_offset_meters
                );
                slab->layered_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(layered_mesh),
                };
                slab->mesh = slab->layered_geometry.mesh;
                slab->geometry_is_layered = true;
            } else if (slab_assembly == nullptr && needs_recompute) {
                build_envelope();
            }
            if (needs_recompute) {
                slab->generated_geometry_dirty = false;
            }
        }

        auto* roof = element.roof();
        if (roof != nullptr) {
            const auto needs_recompute = roof->generated_geometry_dirty;
            const auto* roof_assembly = roof->assembly_id == 0 ? nullptr : get_layered_assembly(roof->assembly_id);
            const auto assembly_revision = cache_assembly_revision(roof_assembly);
            if (needs_recompute && !roof->source_wall_ids.empty()) {
                // A wall can be moved through a short invalid intermediate
                // state while the user drags it.  Retain the last valid roof
                // footprint until all source walls close into a loop again.
                try {
                    auto refreshed = build_pick_wall_loop(*this, roof->source_wall_ids);
                    if (!cyclic_polygon_equal(roof->boundary_polygon, refreshed.polygon)) {
                        roof->boundary_polygon = std::move(refreshed.polygon);
                        element.touch();
                    }
                    roof->source_wall_ids = std::move(refreshed.ordered_wall_ids);
                } catch (const std::invalid_argument&) {
                    // Keep the previously valid boundary; the wall edit itself
                    // remains authoritative and can be completed or repaired.
                }
            }
            const auto thickness = roof_assembly != nullptr
                ? layered_assembly_total_thickness(*roof_assembly)
                : roof->thickness_meters;
            if (needs_recompute) {
                roof->thickness_meters = thickness;
                roof->area_square_meters = roof->roof_type == RoofType::Flat
                    ? roof_plan_area(*roof)
                    : roof_surface_area(RoofData{
                        .boundary_polygon = roof->boundary_polygon,
                        .roof_type = roof->roof_type,
                        .thickness_meters = thickness,
                        .slope_degrees = roof->slope_degrees,
                        .overhang_meters = roof->overhang_meters,
                    });
                roof->volume_cubic_meters = roof->area_square_meters * thickness;
            }

            const auto build_envelope = [&]() {
                auto envelope_mesh = roof->roof_type == RoofType::Flat
                    ? extrude_polygon_mesh(roof->boundary_polygon, thickness, 0.0)
                    : roof->roof_type == RoofType::SimpleGable
                        ? build_gable_roof_mesh(*roof, thickness)
                        : build_auto_footprint_roof_mesh(*roof, thickness);
                if (roof_assembly != nullptr && !roof_assembly->layers.empty() &&
                    !envelope_mesh.indices.empty()) {
                    assign_cache_material(envelope_mesh, roof_assembly->layers.front().material_id);
                }
                roof->envelope_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(envelope_mesh),
                };
                roof->mesh = roof->envelope_geometry.mesh;
                roof->geometry_is_layered = false;
                roof->layered_geometry.dirty = roof_assembly != nullptr;
            };

            const auto refresh_envelope_material = [&]() {
                (void)rebind_envelope_material(
                    roof->envelope_geometry,
                    roof->mesh,
                    roof->geometry_is_layered,
                    roof_assembly
                );
            };
            if (!roof->envelope_geometry.dirty &&
                roof->envelope_geometry.assembly_revision != assembly_revision) {
                refresh_envelope_material();
            }

            if (detail == GeometryDetail::Envelope) {
                if (needs_recompute || roof->geometry_is_layered ||
                    roof->envelope_geometry.dirty) {
                    if (!needs_recompute && !roof->envelope_geometry.dirty &&
                        !roof->envelope_geometry.mesh.indices.empty()) {
                        refresh_envelope_material();
                        roof->mesh = roof->envelope_geometry.mesh;
                        roof->geometry_is_layered = false;
                    } else {
                        build_envelope();
                    }
                }
            } else if (const auto* assembly = roof->assembly_id == 0
                           ? nullptr
                           : get_layered_assembly(roof->assembly_id);
                       assembly != nullptr &&
                       (needs_recompute || roof->layered_geometry.dirty ||
                        roof->layered_geometry.assembly_revision != assembly_revision)) {
                auto layered_mesh = build_layered_roof_mesh(*roof, *assembly);
                roof->layered_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(layered_mesh),
                };
                roof->mesh = roof->layered_geometry.mesh;
                roof->geometry_is_layered = true;
            } else if (roof->assembly_id == 0 && needs_recompute) {
                build_envelope();
            }
            if (needs_recompute) {
                roof->generated_geometry_dirty = false;
            }
        }

        auto* column = element.column();
        if (column != nullptr && column->generated_geometry_dirty) {
            column->volume_cubic_meters = column->width_meters * column->depth_meters * column->height_meters;
            column->mesh = extrude_column_mesh(column->position, column->width_meters, column->depth_meters, column->height_meters);
            column->generated_geometry_dirty = false;
        }

        auto* beam = element.beam();
        if (beam != nullptr && beam->generated_geometry_dirty) {
            beam->length_meters = length(Line2{.start = beam->start, .end = beam->end});
            beam->volume_cubic_meters = beam->length_meters * beam->width_meters * beam->height_meters;
            beam->mesh = extrude_beam_mesh(beam->start, beam->end, beam->width_meters, beam->height_meters);
            beam->generated_geometry_dirty = false;
        }

        auto* stair = element.stair();
        if (stair != nullptr) {
            const auto needs_recompute = stair->generated_geometry_dirty;
            const auto* stair_assembly = stair->assembly_id == 0 ? nullptr : get_layered_assembly(stair->assembly_id);
            const auto assembly_revision = cache_assembly_revision(stair_assembly);

            if (needs_recompute) {
                // Legacy/unconnected stairs may carry their own rise with
                // base and top set to the same level. Only a distinct top
                // level is a live vertical constraint.
                if (stair->top_level_id != 0 && stair->top_level_id != stair->base_level_id) {
                    const auto* base_element = find_ptr(stair->base_level_id);
                    const auto* top_element = find_ptr(stair->top_level_id);
                    const auto* base = base_element == nullptr ? nullptr : base_element->level();
                    const auto* top = top_element == nullptr ? nullptr : top_element->level();
                    if (base != nullptr && top != nullptr) {
                        stair->total_rise_meters = std::max(
                            epsilon, top->elevation_meters - base->elevation_meters);
                    }
                }
                stair->footprint_area_square_meters = stair->width_meters * stair->total_run_meters;
                stair->volume_cubic_meters = stair->footprint_area_square_meters * (stair->total_rise_meters / 2.0);
            }

            const auto build_envelope = [&]() {
                auto envelope_mesh = build_stair_mesh(*stair);
                if (stair_assembly != nullptr && !stair_assembly->layers.empty()) {
                    assign_cache_material(envelope_mesh, stair_assembly->layers.front().material_id);
                }
                stair->envelope_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(envelope_mesh),
                };
                stair->mesh = stair->envelope_geometry.mesh;
                stair->geometry_is_layered = false;
                stair->layered_geometry.dirty = stair_assembly != nullptr;
            };

            const auto refresh_envelope_material = [&]() {
                (void)rebind_envelope_material(
                    stair->envelope_geometry,
                    stair->mesh,
                    stair->geometry_is_layered,
                    stair_assembly
                );
            };
            if (!stair->envelope_geometry.dirty &&
                stair->envelope_geometry.assembly_revision != assembly_revision) {
                refresh_envelope_material();
            }

            if (detail == GeometryDetail::Envelope) {
                if (needs_recompute || stair->geometry_is_layered ||
                    stair->envelope_geometry.dirty) {
                    if (!needs_recompute && !stair->envelope_geometry.dirty &&
                        !stair->envelope_geometry.mesh.indices.empty()) {
                        refresh_envelope_material();
                        stair->mesh = stair->envelope_geometry.mesh;
                        stair->geometry_is_layered = false;
                    } else {
                        build_envelope();
                    }
                }
            } else if (stair_assembly != nullptr &&
                       (needs_recompute || stair->layered_geometry.dirty ||
                        stair->layered_geometry.assembly_revision != assembly_revision)) {
                auto layered_mesh = build_layered_stair_mesh(*stair, *stair_assembly);
                stair->layered_geometry = GeneratedMeshCache{
                    .dirty = false,
                    .source_revision = element.revision(),
                    .assembly_revision = assembly_revision,
                    .mesh = std::move(layered_mesh),
                };
                stair->mesh = stair->layered_geometry.mesh;
                stair->geometry_is_layered = true;
            } else if (stair_assembly == nullptr && needs_recompute) {
                build_envelope();
            }
            if (needs_recompute) {
                stair->generated_geometry_dirty = false;
            }
        }
    }
}

DependencyGraph Document::build_dependency_graph() const {
    DependencyGraph graph;

    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());

            for (const auto& join : wall->joins) {
                append_unique(graph.connected_walls_by_wall[element.id()], join.other_wall_id);
            }
            for (const auto& opening : wall->openings) {
                append_unique(graph.openings_by_wall[element.id()], opening.element_id);
                append_unique(graph.geometry_by_element[opening.element_id], element.id());
            }
        } else if (const auto* slab = element.slab()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[slab->level_id], element.id());
        } else if (const auto* roof = element.roof()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[roof->level_id], element.id());
            for (const auto wall_id : roof->source_wall_ids) {
                append_unique(graph.geometry_by_element[wall_id], element.id());
            }
        } else if (const auto* column = element.column()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[column->level_id], element.id());
        } else if (const auto* beam = element.beam()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[beam->level_id], element.id());
        } else if (const auto* stair = element.stair()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[stair->base_level_id], element.id());
            if (stair->top_level_id != 0) {
                append_unique(graph.geometry_by_element[stair->top_level_id], element.id());
            }
        } else if (const auto* room = element.room()) {
            for (const auto boundary_id : room->boundary_wall_ids) {
                append_unique(graph.rooms_by_wall[boundary_id], element.id());
                append_unique(graph.geometry_by_element[boundary_id], element.id());
            }
            for (const auto& [system_id, system] : floor_systems_) {
                if (system.room_id == element.id()) {
                    append_unique(graph.geometry_by_element[element.id()], system_id);
                }
            }
            for (const auto& [system_id, system] : ceiling_systems_) {
                if (system.room_id == element.id()) {
                    append_unique(graph.geometry_by_element[element.id()], system_id);
                }
            }
        }
    }

    return graph;
}

const DependencyGraph& Document::dependency_graph() const {
    if (dependency_graph_dirty_) {
        dependency_graph_cache_ = build_dependency_graph();
        dependency_graph_dirty_ = false;
        ++dependency_graph_version_;
    }
    return dependency_graph_cache_;
}

Revision Document::dependency_graph_version() const noexcept {
    return dependency_graph_version_;
}


void Document::export_floorplan_svg(const std::filesystem::path& path) const {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("failed to open svg export path");
    }

    out << "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-2 -2 20 20\">\n";
    out << "<rect x=\"-2\" y=\"-2\" width=\"20\" height=\"20\" fill=\"#faf7f0\"/>\n";

    for (const auto& element : elements_) {
        const auto kind_name = svg_element_kind_name(element.kind());
        const auto hit_kind_name = svg_hit_kind_name(element.kind());
        out << "<g id=\"tbe-" << kind_name << '-' << element.id()
            << "\" data-element-id=\"" << element.id()
            << "\" data-kind=\"" << kind_name
            << "\" data-hit-kind=\"" << hit_kind_name
            << "\">\n";

        if (const auto* slab = element.slab()) {
            out << "<polygon points=\"";
            for (const auto& point : slab->boundary_polygon) {
                out << point.x << ',' << -point.y << ' ';
            }
            out << "\" fill=\"none\" stroke=\"#7f8c8d\" stroke-width=\"0.05\" stroke-dasharray=\"0.18 0.12\"/>\n";
        } else if (const auto* roof = element.roof()) {
            out << "<polygon points=\"";
            for (const auto& point : roof->boundary_polygon) {
                out << point.x << ',' << -point.y << ' ';
            }
            out << "\" fill=\"none\" stroke=\"#8e5b3a\" stroke-width=\"0.05\" stroke-dasharray=\"0.12 0.10\"/>\n";
        } else if (const auto* column = element.column()) {
            out << "<rect x=\"" << (column->position.x - (column->width_meters / 2.0))
                << "\" y=\"" << (-(column->position.y + (column->depth_meters / 2.0)))
                << "\" width=\"" << column->width_meters
                << "\" height=\"" << column->depth_meters
                << "\" fill=\"#7f8c8d\" fill-opacity=\"0.35\" stroke=\"#34495e\" stroke-width=\"0.03\"/>\n";
        } else if (const auto* beam = element.beam()) {
            out << "<line x1=\"" << beam->start.x << "\" y1=\"" << -beam->start.y
                << "\" x2=\"" << beam->end.x << "\" y2=\"" << -beam->end.y
                << "\" stroke=\"#9b6b2f\" stroke-width=\"" << beam->width_meters << "\" stroke-linecap=\"square\"/>\n";
        } else if (const auto* stair = element.stair()) {
            const auto direction_length = std::sqrt((stair->direction.x * stair->direction.x) + (stair->direction.y * stair->direction.y));
            if (direction_length > epsilon) {
                const auto unit = Point2{.x = stair->direction.x / direction_length, .y = stair->direction.y / direction_length};
                const auto run_end = add(stair->start, scale(unit, stair->total_run_meters));
                const auto normal = scale(perpendicular_left(unit), stair->width_meters / 2.0);
                out << "<polygon points=\""
                    << add(stair->start, normal).x << ',' << -add(stair->start, normal).y << ' '
                    << add(run_end, normal).x << ',' << -add(run_end, normal).y << ' '
                    << add(run_end, scale(normal, -1.0)).x << ',' << -add(run_end, scale(normal, -1.0)).y << ' '
                    << add(stair->start, scale(normal, -1.0)).x << ',' << -add(stair->start, scale(normal, -1.0)).y
                    << "\" fill=\"#f4d35e\" fill-opacity=\"0.2\" stroke=\"#c26d00\" stroke-width=\"0.03\"/>\n";
            }
        } else if (const auto* wall = element.wall()) {
            out << "<line x1=\"" << wall->axis.start.x << "\" y1=\"" << -wall->axis.start.y
                << "\" x2=\"" << wall->axis.end.x << "\" y2=\"" << -wall->axis.end.y
                << "\" stroke=\"#243447\" stroke-width=\"" << wall->thickness_meters << "\" stroke-linecap=\"round\"/>\n";
            out << "<text x=\"" << ((wall->axis.start.x + wall->axis.end.x) / 2.0)
                << "\" y=\"" << (-(wall->axis.start.y + wall->axis.end.y) / 2.0)
                << "\" font-size=\"0.35\" fill=\"#7a3d1d\">W" << element.id() << "</text>\n";
            for (const auto& opening : wall->openings) {
                const auto opening_kind_name = opening.kind == OpeningKind::Door ? std::string{"door"} : std::string{"window"};
                out << "<g id=\"tbe-" << opening_kind_name << '-' << opening.element_id
                    << "\" data-element-id=\"" << opening.element_id
                    << "\" data-kind=\"" << opening_kind_name
                    << "\" data-hit-kind=\"opening\">\n";
                const auto start_x = wall->axis.start.x + opening.offset_meters - (opening.width_meters / 2.0);
                out << "<rect x=\"" << start_x << "\" y=\"" << (-wall->axis.start.y - (wall->thickness_meters / 2.0))
                    << "\" width=\"" << opening.width_meters << "\" height=\"" << wall->thickness_meters
                    << "\" fill=\"#f4d35e\" stroke=\"#c26d00\" stroke-width=\"0.03\"/>\n";
                out << "</g>\n";
            }
        } else if (const auto* room = element.room()) {
            out << "<polygon points=\"";
            for (const auto& point : room->centerline_boundary_polygon) {
                out << point.x << ',' << -point.y << ' ';
            }
            out << "\" fill=\"#6fb98f\" fill-opacity=\"0.18\" stroke=\"#3f7d5d\" stroke-width=\"0.05\"/>\n";
            if (!room->interior_boundary_polygon.empty()) {
                out << "<polygon points=\"";
                for (const auto& point : room->interior_boundary_polygon) {
                    out << point.x << ',' << -point.y << ' ';
                }
                out << "\" fill=\"none\" stroke=\"#c04c34\" stroke-width=\"0.04\" stroke-dasharray=\"0.15 0.12\"/>\n";
            }
            if (!room->centerline_boundary_polygon.empty()) {
                std::string floor_name;
                std::string ceiling_name;
                for (const auto& [system_id, system] : floor_systems_) {
                    if (system.room_id == element.id()) {
                        floor_name = layered_assembly_name(system.assembly_id);
                        break;
                    }
                }
                for (const auto& [system_id, system] : ceiling_systems_) {
                    if (system.room_id == element.id()) {
                        ceiling_name = layered_assembly_name(system.assembly_id);
                        break;
                    }
                }
                out << "<text x=\"" << room->centerline_boundary_polygon.front().x + 0.5
                    << "\" y=\"" << -room->centerline_boundary_polygon.front().y - 0.5
                    << "\" font-size=\"0.35\" fill=\"#204b36\">R" << element.id() << " " << room->interior_area_square_meters << "m2";
                if (!floor_name.empty()) {
                    out << " F:" << escape_xml(floor_name);
                }
                if (!ceiling_name.empty()) {
                    out << " C:" << escape_xml(ceiling_name);
                }
                out << "</text>\n";
            }
        }
        out << "</g>\n";
    }

    out << "</svg>\n";
}

void Document::export_mesh_obj(const std::filesystem::path& path) const {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("failed to open obj export path");
    }

    std::uint32_t vertex_base = 1;
    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            for (const auto& vertex : wall->geometry.mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < wall->geometry.mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + wall->geometry.mesh.indices[index]) << ' '
                    << (vertex_base + wall->geometry.mesh.indices[index + 1]) << ' '
                    << (vertex_base + wall->geometry.mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(wall->geometry.mesh.vertices.size());
        } else if (const auto* slab = element.slab()) {
            for (const auto& vertex : slab->mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < slab->mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + slab->mesh.indices[index]) << ' '
                    << (vertex_base + slab->mesh.indices[index + 1]) << ' '
                    << (vertex_base + slab->mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(slab->mesh.vertices.size());
        } else if (const auto* roof = element.roof()) {
            for (const auto& vertex : roof->mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < roof->mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + roof->mesh.indices[index]) << ' '
                    << (vertex_base + roof->mesh.indices[index + 1]) << ' '
                    << (vertex_base + roof->mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(roof->mesh.vertices.size());
        } else if (const auto* column = element.column()) {
            for (const auto& vertex : column->mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < column->mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + column->mesh.indices[index]) << ' '
                    << (vertex_base + column->mesh.indices[index + 1]) << ' '
                    << (vertex_base + column->mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(column->mesh.vertices.size());
        } else if (const auto* beam = element.beam()) {
            for (const auto& vertex : beam->mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < beam->mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + beam->mesh.indices[index]) << ' '
                    << (vertex_base + beam->mesh.indices[index + 1]) << ' '
                    << (vertex_base + beam->mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(beam->mesh.vertices.size());
        } else if (const auto* stair = element.stair()) {
            for (const auto& vertex : stair->mesh.vertices) {
                out << "v " << vertex.x << ' ' << vertex.y << ' ' << vertex.z << '\n';
            }
            for (std::size_t index = 0; index + 2 < stair->mesh.indices.size(); index += 3) {
                out << "f "
                    << (vertex_base + stair->mesh.indices[index]) << ' '
                    << (vertex_base + stair->mesh.indices[index + 1]) << ' '
                    << (vertex_base + stair->mesh.indices[index + 2]) << '\n';
            }
            vertex_base += static_cast<std::uint32_t>(stair->mesh.vertices.size());
        }
    }
}

void Document::export_debug_report_json(const std::filesystem::path& path) const {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("failed to open debug report path");
    }

    const auto dependencies = build_dependency_graph();
    const auto validation = validate_document();
    const auto adjacencies = wall_room_adjacencies();
    const auto wall_schedule = generate_wall_schedule();
    const auto opening_schedule = generate_opening_schedule();
    const auto room_schedule = generate_room_schedule();
    const auto slab_schedule = generate_slab_schedule();
    const auto roof_schedule = generate_roof_schedule();
    const auto column_schedule = generate_column_schedule();
    const auto beam_schedule = generate_beam_schedule();
    const auto stair_schedule = generate_stair_schedule();
    const auto floor_schedule = generate_floor_finish_schedule();
    const auto ceiling_schedule = generate_ceiling_schedule();
    const auto material_takeoff = generate_material_takeoff();

    out << "{";
    out << "\"document_name\":\"" << escape_json(name_) << "\",";
    out << "\"element_count\":" << elements_.size() << ',';
    out << "\"validation\":{\"issues\":" << validation.issue_count()
        << ",\"warnings\":" << validation.warning_count()
        << ",\"errors\":" << validation.error_count() << "},";
    out << "\"materials\":[";
    {
        auto first_material = true;
        for (const auto& [material_id, material] : materials_) {
            if (!first_material) {
                out << ',';
            }
            first_material = false;
            out << "{\"material_id\":" << material_id << ",\"name\":\"" << escape_json(material.name) << "\"}";
        }
    }
    out << "],\"wall_types\":[";
    {
        auto first_type = true;
        for (const auto& [wall_type_id, wall_type] : wall_types_) {
            if (!first_type) {
                out << ',';
            }
            first_type = false;
            out << "{\"wall_type_id\":" << wall_type_id << ",\"name\":\"" << escape_json(wall_type.name) << "\"}";
        }
    }
    out << "],\"assemblies\":[";
    {
        auto first_assembly = true;
        for (const auto& [assembly_id, assembly] : layered_assemblies_) {
            if (!first_assembly) {
                out << ',';
            }
            first_assembly = false;
            out << "{\"assembly_id\":" << assembly_id
                << ",\"kind\":\"" << (assembly.kind == LayeredAssemblyKind::Floor ? "floor" : "ceiling")
                << "\",\"name\":\"" << escape_json(assembly.name) << "\"}";
        }
    }
    out << "],\"elements\":[";
    for (std::size_t index = 0; index < elements_.size(); ++index) {
        const auto& element = elements_[index];
        if (index != 0) {
            out << ',';
        }
        out << "{\"id\":" << element.id() << ",\"name\":\"" << escape_json(element.name()) << "\",\"kind\":";
        if (element.wall() != nullptr) {
            out << "\"Wall\",\"dirty\":" << (element.wall()->geometry.dirty ? "true" : "false")
                << ",\"wall_type_id\":" << element.wall()->wall_type_id;
        } else if (element.room() != nullptr) {
            out << "\"Room\",\"dirty\":false";
        } else if (element.slab() != nullptr) {
            out << "\"Slab\",\"dirty\":" << (element.slab()->generated_geometry_dirty ? "true" : "false");
        } else if (element.roof() != nullptr) {
            out << "\"Roof\",\"dirty\":" << (element.roof()->generated_geometry_dirty ? "true" : "false");
        } else if (element.column() != nullptr) {
            out << "\"Column\",\"dirty\":" << (element.column()->generated_geometry_dirty ? "true" : "false");
        } else if (element.beam() != nullptr) {
            out << "\"Beam\",\"dirty\":" << (element.beam()->generated_geometry_dirty ? "true" : "false");
        } else if (element.stair() != nullptr) {
            out << "\"Stair\",\"dirty\":" << (element.stair()->generated_geometry_dirty ? "true" : "false");
        } else if (element.door() != nullptr) {
            out << "\"Door\",\"dirty\":false";
        } else if (element.window() != nullptr) {
            out << "\"Window\",\"dirty\":false";
        } else {
            out << "\"Level\",\"dirty\":false";
        }
        out << '}';
    }
    out << "],\"dependencies\":{\"rooms_by_wall\":{";
    auto first = true;
    for (const auto& [wall_id, room_ids] : dependencies.rooms_by_wall) {
        if (!first) {
            out << ',';
        }
        first = false;
        out << '"' << wall_id << "\":[";
        for (std::size_t index = 0; index < room_ids.size(); ++index) {
            if (index != 0) {
                out << ',';
            }
            out << room_ids[index];
        }
        out << ']';
    }
    out << "}},\"adjacencies\":[";
    for (std::size_t index = 0; index < adjacencies.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& adjacency = adjacencies[index];
        out << "{\"wall_id\":" << adjacency.wall_id << ",\"room_id\":" << adjacency.room_id << ",\"side\":\""
            << (adjacency.side == WallRoomSide::Left ? "left" : adjacency.side == WallRoomSide::Right ? "right" : "exterior") << "\"}";
    }
    out << "],\"floor_systems\":[";
    {
        auto first_system = true;
        for (const auto& [system_id, system] : floor_systems_) {
            if (!first_system) {
                out << ',';
            }
            first_system = false;
            out << "{\"system_id\":" << system_id << ",\"room_id\":" << system.room_id
                << ",\"assembly_name\":\"" << escape_json(layered_assembly_name(system.assembly_id))
                << "\",\"dirty\":" << (system.dirty ? "true" : "false") << "}";
        }
    }
    out << "],\"ceiling_systems\":[";
    {
        auto first_system = true;
        for (const auto& [system_id, system] : ceiling_systems_) {
            if (!first_system) {
                out << ',';
            }
            first_system = false;
            out << "{\"system_id\":" << system_id << ",\"room_id\":" << system.room_id
                << ",\"assembly_name\":\"" << escape_json(layered_assembly_name(system.assembly_id))
                << "\",\"dirty\":" << (system.dirty ? "true" : "false") << "}";
        }
    }
    out << "],\"schedules\":{\"walls\":[";
    for (std::size_t index = 0; index < wall_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = wall_schedule[index];
        out << "{\"wall_id\":" << row.wall_id << ",\"gross_area\":" << row.gross_area_square_meters
            << ",\"opening_area\":" << row.opening_area_square_meters << ",\"net_area\":" << row.net_area_square_meters
            << ",\"wall_type_name\":\"" << escape_json(row.wall_type_name) << "\"}";
    }
    out << "],\"openings\":[";
    for (std::size_t index = 0; index < opening_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = opening_schedule[index];
        out << "{\"element_id\":" << row.element_id << ",\"area\":" << row.area_square_meters << "}";
    }
    out << "],\"rooms\":[";
    for (std::size_t index = 0; index < room_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = room_schedule[index];
        out << "{\"room_id\":" << row.room_id << ",\"centerline_area\":" << row.centerline_area_square_meters
            << ",\"interior_area\":" << row.interior_area_square_meters
            << ",\"floor_area\":" << row.floor_finish_area_square_meters
            << ",\"wall_finish_area\":" << row.interior_wall_finish_area_square_meters << "}";
    }
    out << "],\"slabs\":[";
    for (std::size_t index = 0; index < slab_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = slab_schedule[index];
        out << "{\"slab_id\":" << row.slab_id << ",\"area\":" << row.area_square_meters
            << ",\"volume\":" << row.volume_cubic_meters
            << ",\"material_or_assembly\":\"" << escape_json(row.material_or_assembly_name) << "\"}";
    }
    out << "],\"roofs\":[";
    for (std::size_t index = 0; index < roof_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = roof_schedule[index];
        out << "{\"roof_id\":" << row.roof_id << ",\"area\":" << row.area_square_meters
            << ",\"volume\":" << row.volume_cubic_meters << "}";
    }
    out << "],\"columns\":[";
    for (std::size_t index = 0; index < column_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = column_schedule[index];
        out << "{\"column_id\":" << row.column_id << ",\"volume\":" << row.volume_cubic_meters << "}";
    }
    out << "],\"beams\":[";
    for (std::size_t index = 0; index < beam_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = beam_schedule[index];
        out << "{\"beam_id\":" << row.beam_id << ",\"length\":" << row.length_meters << ",\"volume\":" << row.volume_cubic_meters << "}";
    }
    out << "],\"stairs\":[";
    for (std::size_t index = 0; index < stair_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = stair_schedule[index];
        out << "{\"stair_id\":" << row.stair_id << ",\"run\":" << row.total_run_meters << ",\"rise\":" << row.total_rise_meters << "}";
    }
    out << "],\"floors\":[";
    for (std::size_t index = 0; index < floor_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = floor_schedule[index];
        out << "{\"floor_system_id\":" << row.floor_system_id << ",\"room_id\":" << row.room_id
            << ",\"area\":" << row.area_square_meters
            << ",\"assembly_name\":\"" << escape_json(row.assembly_name) << "\"}";
    }
    out << "],\"ceilings\":[";
    for (std::size_t index = 0; index < ceiling_schedule.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = ceiling_schedule[index];
        out << "{\"ceiling_system_id\":" << row.ceiling_system_id << ",\"room_id\":" << row.room_id
            << ",\"area\":" << row.area_square_meters
            << ",\"assembly_name\":\"" << escape_json(row.assembly_name) << "\"}";
    }
    out << "],\"material_takeoff\":[";
    for (std::size_t index = 0; index < material_takeoff.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& row = material_takeoff[index];
        out << "{\"material_id\":" << row.material_id << ",\"name\":\"" << escape_json(row.material_name)
            << "\",\"quantity\":" << row.quantity << ",\"unit\":\"" << row.unit << "\"}";
    }
    out << "],\"material_takeoff_by_category\":[";
    {
        std::map<std::string, double> quantities_by_category;
        for (const auto& row : material_takeoff) {
            const auto* material = get_material(row.material_id);
            const auto category = material == nullptr
                ? std::string{"Unknown"}
                : material_category_label(material->category);
            quantities_by_category[category] += row.quantity;
        }
        auto first_category = true;
        for (const auto& [category, quantity] : quantities_by_category) {
            if (!first_category) {
                out << ',';
            }
            first_category = false;
            out << "{\"category\":\"" << escape_json(category) << "\",\"quantity\":" << quantity << "}";
        }
    }
    out << "]},\"issues\":[";
    for (std::size_t index = 0; index < validation.issues.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& issue = validation.issues[index];
        out << "{\"element_id\":" << issue.element_id
            << ",\"message\":\"" << escape_json(issue.message) << "\"}";
    }
    out << "]}\n";
}

const std::vector<Element>& Document::elements() const noexcept {
    return elements_;
}

const std::map<ElementId, MaterialDefinition>& Document::materials() const noexcept {
    return materials_;
}

const std::map<ElementId, WallTypeData>& Document::wall_types() const noexcept {
    return wall_types_;
}

const std::map<ElementId, LayeredAssemblyData>& Document::layered_assemblies() const noexcept {
    return layered_assemblies_;
}

const std::map<ElementId, FloorSystemData>& Document::floor_systems() const noexcept {
    return floor_systems_;
}

const std::map<ElementId, CeilingSystemData>& Document::ceiling_systems() const noexcept {
    return ceiling_systems_;
}

std::optional<Element> Document::find(ElementId id) const {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return std::nullopt;
    }

    return *found;
}

const Element* Document::find_ptr(ElementId id) const noexcept {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return nullptr;
    }

    return &(*found);
}

Element* Document::find_ptr(ElementId id) noexcept {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return nullptr;
    }

    return &(*found);
}

void Document::restore_element(Element element) {
    if (auto* existing = find_ptr(element.id())) {
        *existing = std::move(element);
        invalidate_dependency_graph_cache();
        return;
    }

    elements_.push_back(std::move(element));
    invalidate_dependency_graph_cache();
}

void Document::remove_element(ElementId id) {
    elements_.erase(std::remove_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    }), elements_.end());
    invalidate_dependency_graph_cache();
}

ElementId Document::allocate_id() noexcept {
    return next_id_++;
}

Element& Document::require_level(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->level() == nullptr) {
        throw std::invalid_argument("level does not exist");
    }

    return *element;
}

Element& Document::require_wall(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->wall() == nullptr) {
        throw std::invalid_argument("host wall does not exist");
    }

    return *element;
}

const Element& Document::require_wall(ElementId id) const {
    const auto* element = find_ptr(id);
    if (element == nullptr || element->wall() == nullptr) {
        throw std::invalid_argument("host wall does not exist");
    }

    return *element;
}

const Element& Document::require_room(ElementId id) const {
    const auto* element = find_ptr(id);
    if (element == nullptr || element->room() == nullptr) {
        throw std::invalid_argument("room does not exist");
    }
    return *element;
}

Element& Document::require_room(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->room() == nullptr) {
        throw std::invalid_argument("room does not exist");
    }
    return *element;
}

Element& Document::require_door(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->door() == nullptr) {
        throw std::invalid_argument("door does not exist");
    }

    return *element;
}

Element& Document::require_window(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->window() == nullptr) {
        throw std::invalid_argument("window does not exist");
    }

    return *element;
}

const Element* Document::find_host_wall_for_opening(ElementId opening_id) const noexcept {
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }
        const auto found = std::find_if(wall->openings.begin(), wall->openings.end(), [opening_id](const HostedOpening& opening) {
            return opening.element_id == opening_id;
        });
        if (found != wall->openings.end()) {
            return &element;
        }
    }
    return nullptr;
}

double Document::wall_thickness(const WallData& wall) const {
    if (wall.wall_type_id != 0) {
        if (const auto* wall_type = get_wall_type(wall.wall_type_id)) {
            return total_wall_type_thickness(*wall_type);
        }
    }
    return wall.thickness_meters;
}

std::string Document::wall_type_name(ElementId wall_type_id) const {
    if (const auto* wall_type = get_wall_type(wall_type_id)) {
        return wall_type->name;
    }
    return {};
}

double Document::total_wall_type_thickness(const WallTypeData& wall_type) const {
    auto total = 0.0;
    for (const auto& layer : wall_type.layers) {
        total += layer.thickness_meters;
    }
    return total;
}

bool Document::wall_type_uses_glass(const WallTypeData& wall_type) const {
    return std::any_of(wall_type.layers.begin(), wall_type.layers.end(), [&](const auto& layer) {
        const auto* material = get_material(layer.material_id);
        return material != nullptr && material->category == MaterialCategory::Glass;
    });
}

bool Document::layered_assembly_uses_glass(const LayeredAssemblyData& assembly) const {
    return std::any_of(assembly.layers.begin(), assembly.layers.end(), [&](const auto& layer) {
        const auto* material = get_material(layer.material_id);
        return material != nullptr && material->category == MaterialCategory::Glass;
    });
}

bool Document::wall_uses_glass(const WallData& wall) const {
    if (wall.wall_type_id != 0) {
        const auto* wall_type = get_wall_type(wall.wall_type_id);
        if (wall_type != nullptr && wall_type_uses_glass(*wall_type)) {
            return true;
        }
    }
    if (wall.assembly_id != 0) {
        const auto* assembly = get_layered_assembly(wall.assembly_id);
        if (assembly != nullptr && assembly->kind == LayeredAssemblyKind::Wall && layered_assembly_uses_glass(*assembly)) {
            return true;
        }
    }
    return false;
}

std::string Document::layered_assembly_name(ElementId assembly_id) const {
    if (const auto* assembly = get_layered_assembly(assembly_id)) {
        return assembly->name;
    }
    return {};
}

void Document::add_opening_to_wall(ElementId host_wall_id, HostedOpening opening) {
    auto& wall_element = require_wall(host_wall_id);
    auto* wall = wall_element.wall();
    if (wall_uses_glass(*wall)) {
        throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
    }
    wall->openings.push_back(opening);
    validate_wall_openings(*wall);
    mark_wall_dirty(wall_element);
}

void Document::validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const {
    if (wall_uses_glass(wall)) {
        throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
    }
    if (!std::isfinite(offset_meters) ||
        !std::isfinite(width_meters) ||
        !std::isfinite(height_meters) ||
        offset_meters < 0.0 || width_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("opening dimensions must be positive");
    }

    if (height_meters > resolved_wall_height(wall) + epsilon) {
        throw std::invalid_argument("opening is taller than host wall");
    }

    const auto wall_length = wall_centerline_length(wall);
    const auto half_width = width_meters / 2.0;
    if ((offset_meters - half_width) < 0.0 || (offset_meters + half_width) > wall_length) {
        throw std::invalid_argument("opening must stay inside host wall");
    }

    for (const auto& opening : wall.openings) {
        if (openings_overlap(offset_meters, width_meters, opening.offset_meters, opening.width_meters)) {
            throw std::invalid_argument("opening overlaps an existing hosted opening");
        }
    }
}

void Document::validate_wall_axis(Line2 axis, double thickness_meters, double height_meters) const {
    if (length(axis) <= epsilon || height_meters <= 0.0 || thickness_meters <= 0.0) {
        throw std::invalid_argument("wall dimensions must be positive");
    }
}

void Document::validate_wall_openings(const WallData& wall, std::optional<ElementId> ignored_opening_id) const {
    if (!wall.openings.empty() && wall_uses_glass(wall)) {
        throw std::invalid_argument("doors and windows cannot be hosted by glass walls");
    }
    for (std::size_t index = 0; index < wall.openings.size(); ++index) {
        const auto& opening = wall.openings[index];
        if (ignored_opening_id.has_value() && opening.element_id == *ignored_opening_id) {
            continue;
        }
        if (!std::isfinite(opening.offset_meters) ||
            !std::isfinite(opening.width_meters) ||
            !std::isfinite(opening.height_meters) ||
            !std::isfinite(opening.sill_height_meters) ||
            !std::isfinite(opening.vertical_offset_meters) ||
            opening.offset_meters < 0.0 || opening.width_meters <= 0.0 ||
            opening.height_meters <= 0.0 || opening.sill_height_meters < 0.0) {
            throw std::invalid_argument("opening dimensions must be positive");
        }
        if (opening.vertical_offset_meters < 0.0) {
            throw std::invalid_argument("opening vertical offset must not be negative");
        }
        if ((opening.height_meters + opening.sill_height_meters + opening.vertical_offset_meters) > resolved_wall_height(wall) + epsilon) {
            throw std::invalid_argument(
                "opening is taller than host wall: opening=" +
                std::to_string(opening.element_id) + " required=" +
                std::to_string(opening.height_meters + opening.sill_height_meters + opening.vertical_offset_meters) +
                " host=" + std::to_string(resolved_wall_height(wall))
            );
        }
        const auto wall_length = wall_centerline_length(wall);
        const auto half_width = opening.width_meters / 2.0;
        if ((opening.offset_meters - half_width) < 0.0 || (opening.offset_meters + half_width) > wall_length) {
            throw std::invalid_argument("opening must stay inside host wall");
        }

        for (std::size_t other = index + 1; other < wall.openings.size(); ++other) {
            const auto& candidate = wall.openings[other];
            if (ignored_opening_id.has_value() && candidate.element_id == *ignored_opening_id) {
                continue;
            }
            if (openings_overlap(opening.offset_meters, opening.width_meters, candidate.offset_meters, candidate.width_meters)) {
                throw std::invalid_argument("opening overlaps an existing hosted opening");
            }
        }
    }
}

void Document::update_wall_opening(ElementId host_wall_id, const HostedOpening& opening) {
    auto& wall_element = require_wall(host_wall_id);
    auto* wall = wall_element.wall();
    auto found = false;
    for (auto& candidate : wall->openings) {
        if (candidate.element_id == opening.element_id) {
            candidate = opening;
            found = true;
            break;
        }
    }
    if (!found) {
        throw std::invalid_argument("hosted opening does not exist on wall");
    }
    validate_wall_openings(*wall);
    mark_wall_dirty(wall_element);
}

void Document::sync_opening_level_constraint(ElementId opening_id) {
    auto* opening_element = find_ptr(opening_id);
    if (opening_element == nullptr) {
        throw std::invalid_argument("opening does not exist");
    }

    const auto sync = [&](auto* data, OpeningKind kind, double sill_height_meters) {
        const auto* host_element = find_ptr(data->host_wall_id);
        const auto* host_wall = host_element == nullptr ? nullptr : host_element->wall();
        if (host_wall == nullptr) {
            throw std::invalid_argument("opening host wall does not exist");
        }
        const auto vertical_offset = level_elevation(data->level_id) +
            data->level_offset_meters - resolved_wall_base_elevation(*host_wall);
        HostedOpening updated{
            .element_id = opening_id,
            .kind = kind,
            .offset_meters = data->offset_meters,
            .width_meters = data->width_meters,
            .height_meters = data->height_meters,
            .sill_height_meters = sill_height_meters,
            .vertical_offset_meters = vertical_offset,
        };
        auto wall_copy = *host_wall;
        for (auto& opening : wall_copy.openings) {
            if (opening.element_id == opening_id) {
                opening = updated;
            }
        }
        validate_wall_openings(wall_copy);
        data->vertical_offset_meters = vertical_offset;
        update_wall_opening(data->host_wall_id, updated);
    };

    if (auto* door = opening_element->door(); door != nullptr) {
        sync(door, OpeningKind::Door, 0.0);
        return;
    }
    if (auto* window = opening_element->window(); window != nullptr) {
        sync(window, OpeningKind::Window, window->sill_height_meters);
        return;
    }
    throw std::invalid_argument("element is not a hosted opening");
}

void Document::remove_hosted_opening(ElementId host_wall_id, ElementId opening_id) {
    auto& wall_element = require_wall(host_wall_id);
    auto* wall = wall_element.wall();
    wall->openings.erase(std::remove_if(wall->openings.begin(), wall->openings.end(), [opening_id](const HostedOpening& opening) {
        return opening.element_id == opening_id;
    }), wall->openings.end());
    mark_wall_dirty(wall_element);
}

void Document::touch_related_rooms(ElementId wall_id) noexcept {
    for (auto& element : elements_) {
        auto* room = element.room();
        if (room == nullptr) {
            continue;
        }
        if (std::find(room->boundary_wall_ids.begin(), room->boundary_wall_ids.end(), wall_id) != room->boundary_wall_ids.end()) {
            element.touch();
        }
    }
}

void Document::refresh_dependencies_for_wall(ElementId wall_id) {
    // Bulk imports/templates deliberately defer global joins.  Re-running the
    // O(n²) join scan for each level-bound wall makes a 6×9 template behave
    // like O(n³) work and can stall or crash a tablet before its first frame.
    if (automatic_wall_join_enabled_) {
        auto_join_walls();
    }
    mark_rooms_dirty_for_wall(wall_id);
    touch_related_rooms(wall_id);
    invalidate_dependency_graph_cache();
}

void Document::add_issue(
    ValidationReport& report,
    ValidationSeverity severity,
    ValidationIssueCode code,
    ElementId element_id,
    std::string message
) const {
    report.issues.push_back(ValidationIssue{
        .severity = severity,
        .code = code,
        .element_id = element_id,
        .message = std::move(message),
    });
}

void Document::mark_wall_dirty(Element& wall) noexcept {
    auto* wall_data = wall.wall();
    if (wall_data == nullptr) {
        return;
    }

    wall_data->geometry.dirty = true;
    wall_data->layered_geometry.dirty = true;
    wall.touch();
    touch_related_rooms(wall.id());
}

void Document::replace_state(std::string name, std::vector<Element> elements, ElementId next_id) {
    if (name.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }
    if (next_id == 0) {
        throw std::invalid_argument("next element id must be positive");
    }

    name_ = std::move(name);
    elements_ = std::move(elements);
    next_id_ = next_id;
    invalidate_dependency_graph_cache();
}

void Document::invalidate_dependency_graph_cache() noexcept {
    dependency_graph_dirty_ = true;
}

} // namespace tbe::core
