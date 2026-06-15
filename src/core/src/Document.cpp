#include "tbe/core/Document.hpp"

#include "tbe/core/GeometryService.hpp"

#include <algorithm>
#include <cmath>
#include <fstream>
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

Point2 add(Point2 left, Point2 right) {
    return Point2{.x = left.x + right.x, .y = left.y + right.y};
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
    case ElementKind::Level: return "level";
    }
    return "unknown";
}

std::optional<Point2> segment_intersection(Line2 first, Line2 second) {
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

    if (!between(px, x1, x2) || !between(py, y1, y2) || !between(px, x3, x4) || !between(py, y3, y4)) {
        return std::nullopt;
    }

    return Point2{.x = px, .y = py};
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
    std::vector<Point2> boundary_polygon{};
    double area_square_meters{};
    double perimeter_meters{};
    ElementId level_id{};
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

double layered_assembly_total_thickness(const LayeredAssemblyData& assembly) {
    auto total = 0.0;
    for (const auto& layer : assembly.layers) {
        total += layer.thickness_meters;
    }
    return total;
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

MeshBuffer build_stair_mesh(const StairData& stair) {
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
    std::vector<Point2> polygon{
        add(stair.start, normal),
        add(add(stair.start, run), normal),
        add(add(stair.start, run), scale(normal, -1.0)),
        add(stair.start, scale(normal, -1.0)),
    };
    return extrude_polygon_mesh(polygon, stair.total_rise_meters, 0.0);
}

double roof_plan_area(const RoofData& roof) {
    return polygon_area(roof.boundary_polygon);
}

double roof_surface_area(const RoofData& roof) {
    const auto plan_area = roof_plan_area(roof);
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
    std::map<std::string, std::string> metadata
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
    materials_[material.material_id] = std::move(material);
    invalidate_dependency_graph_cache();
}

ElementId Document::create_wall_type(std::string name, std::vector<WallAssemblyLayer> layers) {
    if (name.empty()) {
        throw std::invalid_argument("wall type name must not be empty");
    }
    if (layers.empty()) {
        throw std::invalid_argument("wall type must contain layers");
    }
    for (const auto& layer : layers) {
        if (layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("wall type layer thickness must be positive");
        }
    }

    const auto wall_type_id = allocate_id();
    wall_types_[wall_type_id] = WallTypeData{
        .wall_type_id = wall_type_id,
        .name = std::move(name),
        .layers = std::move(layers),
    };
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
    wall_types_[wall_type.wall_type_id] = std::move(wall_type);
    invalidate_dependency_graph_cache();
}

ElementId Document::create_layered_assembly(LayeredAssemblyKind kind, std::string name, std::vector<WallAssemblyLayer> layers) {
    if (name.empty() || layers.empty()) {
        throw std::invalid_argument("layered assembly is invalid");
    }
    for (const auto& layer : layers) {
        if (layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("assembly layer thickness must be positive");
        }
    }

    const auto assembly_id = allocate_id();
    layered_assemblies_[assembly_id] = LayeredAssemblyData{
        .assembly_id = assembly_id,
        .kind = kind,
        .name = std::move(name),
        .layers = std::move(layers),
    };
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
        if (layer.thickness_meters <= 0.0) {
            throw std::invalid_argument("assembly layer thickness must be positive");
        }
    }
    layered_assemblies_[assembly.assembly_id] = std::move(assembly);
    invalidate_dependency_graph_cache();
}

ElementId Document::create_level(std::string name, double elevation_meters, double default_wall_height_meters) {
    if (name.empty()) {
        throw std::invalid_argument("level name must not be empty");
    }
    if (default_wall_height_meters <= 0.0) {
        throw std::invalid_argument("default wall height must be positive");
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

ElementId Document::create_wall(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id) {
    if (name.empty()) {
        throw std::invalid_argument("wall name must not be empty");
    }
    validate_wall_axis(axis, thickness_meters, height_meters);
    if (level_id != 0) {
        (void)require_level(level_id);
    }

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Wall, std::move(name), WallData{
        .level_id = level_id,
        .axis = axis,
        .thickness_meters = thickness_meters,
        .height_meters = height_meters,
    });
    auto_join_walls();
    invalidate_dependency_graph_cache();
    return id;
}

void Document::set_wall_type(ElementId wall_id, ElementId wall_type_id) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    if (wall_type_id != 0 && get_wall_type(wall_type_id) == nullptr) {
        throw std::invalid_argument("wall type does not exist");
    }
    wall->wall_type_id = wall_type_id;
    if (const auto* wall_type = get_wall_type(wall_type_id)) {
        wall->thickness_meters = total_wall_type_thickness(*wall_type);
    }
    mark_wall_dirty(wall_element);
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
    if (const auto* wall_type = get_wall_type(wall_type_id)) {
        wall->thickness_meters = total_wall_type_thickness(*wall_type);
    }
    auto updated = *wall;
    validate_wall_axis(updated.axis, wall->thickness_meters, wall->height_meters);
    validate_wall_openings(updated);
    mark_wall_dirty(wall_element);
    refresh_dependencies_for_wall(wall_id);
    invalidate_dependency_graph_cache();
}

void Document::set_wall_axis(ElementId wall_id, Line2 axis) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
    validate_wall_axis(axis, wall->thickness_meters, wall->height_meters);

    auto updated = *wall;
    updated.axis = axis;
    validate_wall_openings(updated);

    wall->axis = axis;
    mark_wall_dirty(wall_element);
    refresh_dependencies_for_wall(wall_id);
    invalidate_dependency_graph_cache();
}

ElementId Document::split_wall(ElementId wall_id, double offset_meters) {
    auto& wall_element = require_wall(wall_id);
    auto* wall = wall_element.wall();
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
        .axis = Line2{.start = split_point, .end = original_end},
        .thickness_meters = wall->thickness_meters,
        .height_meters = wall->height_meters,
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
    validate_opening(*wall, offset_meters, width_meters, height_meters);

    const auto id = allocate_id();
    const auto level_id = wall->level_id;
    elements_.emplace_back(id, ElementKind::Door, std::move(name), DoorData{
        .level_id = level_id,
        .host_wall_id = host_wall_id,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Door,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = 0.0,
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
    if (sill_height_meters < 0.0) {
        throw std::invalid_argument("window sill height must not be negative");
    }

    auto& wall_element = require_wall(host_wall_id);
    const auto* wall = wall_element.wall();
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
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Window,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
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
    if (assembly_id != 0 && get_layered_assembly(assembly_id) == nullptr) {
        throw std::invalid_argument("slab assembly does not exist");
    }

    const auto id = allocate_id();
    auto area = polygon_area(boundary_polygon);
    auto mesh = extrude_polygon_mesh(boundary_polygon, thickness_meters, elevation_offset_meters);
    elements_.emplace_back(id, ElementKind::Slab, "Slab", SlabData{
        .level_id = level_id,
        .boundary_polygon = std::move(boundary_polygon),
        .thickness_meters = thickness_meters,
        .material_id = material_id,
        .assembly_id = assembly_id,
        .elevation_offset_meters = elevation_offset_meters,
        .generated_geometry_dirty = false,
        .mesh = std::move(mesh),
        .area_square_meters = area,
        .volume_cubic_meters = area * thickness_meters,
    });
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
    std::optional<double> overhang_meters
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

    const auto id = allocate_id();
    const auto area = roof_type == RoofType::SimpleGable
        ? roof_surface_area(RoofData{.boundary_polygon = boundary_polygon, .roof_type = roof_type, .slope_degrees = slope_degrees})
        : polygon_area(boundary_polygon);
    const auto mesh = roof_type == RoofType::Flat
        ? extrude_polygon_mesh(boundary_polygon, thickness_meters, 0.0)
        : MeshBuffer{};
    elements_.emplace_back(id, ElementKind::Roof, "Roof", RoofData{
        .level_id = level_id,
        .boundary_polygon = std::move(boundary_polygon),
        .roof_type = roof_type,
        .thickness_meters = thickness_meters,
        .slope_degrees = slope_degrees,
        .overhang_meters = overhang_meters,
        .material_id = material_id,
        .assembly_id = assembly_id,
        .generated_geometry_dirty = roof_type != RoofType::Flat,
        .mesh = mesh,
        .area_square_meters = area,
        .volume_cubic_meters = area * thickness_meters,
    });
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
    ElementId material_id
) {
    (void)require_level(base_level_id);
    if (top_level_id != 0) {
        (void)require_level(top_level_id);
    }
    if (width_meters <= 0.0 || total_rise_meters <= 0.0 || total_run_meters <= 0.0 || riser_count <= 0 || tread_count <= 0) {
        throw std::invalid_argument("stair dimensions and counts must be positive");
    }
    if (material_id != 0 && get_material(material_id) == nullptr) {
        throw std::invalid_argument("stair material does not exist");
    }
    const auto footprint_area = width_meters * total_run_meters;
    const auto id = allocate_id();
    StairData stair{
        .base_level_id = base_level_id,
        .top_level_id = top_level_id,
        .start = start,
        .direction = direction,
        .width_meters = width_meters,
        .total_rise_meters = total_rise_meters,
        .total_run_meters = total_run_meters,
        .riser_count = riser_count,
        .tread_count = tread_count,
        .material_id = material_id,
        .generated_geometry_dirty = false,
        .mesh = {},
        .footprint_area_square_meters = footprint_area,
        .volume_cubic_meters = footprint_area * (total_rise_meters / 2.0),
    };
    stair.mesh = build_stair_mesh(stair);
    elements_.emplace_back(id, ElementKind::Stair, "Stair", stair);
    invalidate_dependency_graph_cache();
    return id;
}

ElementId Document::create_floor_system_for_room(ElementId room_id, ElementId assembly_id) {
    const auto& room_element = require_room(room_id);
    const auto* room = room_element.room();
    const auto* assembly = get_layered_assembly(assembly_id);
    if (assembly == nullptr) {
        throw std::invalid_argument("floor assembly does not exist");
    }
    if (assembly->kind != LayeredAssemblyKind::Floor) {
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
    const auto* assembly = get_layered_assembly(assembly_id);
    if (assembly == nullptr) {
        throw std::invalid_argument("ceiling assembly does not exist");
    }
    if (assembly->kind != LayeredAssemblyKind::Ceiling) {
        throw std::invalid_argument("assembly kind must be ceiling");
    }
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
            hosted_ids.push_back(opening.element_id);
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

    remove_element(element_id);
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

    if (auto* door = opening_element->door()) {
        const auto host_wall_id = door->host_wall_id;
        auto updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Door,
            .offset_meters = offset_meters,
            .width_meters = door->width_meters,
            .height_meters = door->height_meters,
            .sill_height_meters = 0.0,
        };
        auto wall_copy = *require_wall(host_wall_id).wall();
        for (auto& opening : wall_copy.openings) {
            if (opening.element_id == opening_id) {
                opening = updated;
            }
        }
        validate_wall_openings(wall_copy);
        door->offset_meters = offset_meters;
        opening_element->touch();
        update_wall_opening(host_wall_id, updated);
        invalidate_dependency_graph_cache();
        return;
    }

    if (auto* window = opening_element->window()) {
        const auto host_wall_id = window->host_wall_id;
        auto updated = HostedOpening{
            .element_id = opening_id,
            .kind = OpeningKind::Window,
            .offset_meters = offset_meters,
            .width_meters = window->width_meters,
            .height_meters = window->height_meters,
            .sill_height_meters = window->sill_height_meters,
        };
        auto wall_copy = *require_wall(host_wall_id).wall();
        for (auto& opening : wall_copy.openings) {
            if (opening.element_id == opening_id) {
                opening = updated;
            }
        }
        validate_wall_openings(wall_copy);
        window->offset_meters = offset_meters;
        opening_element->touch();
        update_wall_opening(host_wall_id, updated);
        invalidate_dependency_graph_cache();
        return;
    }

    throw std::invalid_argument("opening does not exist");
}

void Document::resize_door(ElementId door_id, double width_meters, double height_meters) {
    auto& door_element = require_door(door_id);
    auto* door = door_element.door();
    auto updated = HostedOpening{
        .element_id = door_id,
        .kind = OpeningKind::Door,
        .offset_meters = door->offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = 0.0,
    };
    auto wall_copy = *require_wall(door->host_wall_id).wall();
    for (auto& opening : wall_copy.openings) {
        if (opening.element_id == door_id) {
            opening = updated;
        }
    }
    validate_wall_openings(wall_copy);
    door->width_meters = width_meters;
    door->height_meters = height_meters;
    door_element.touch();
    update_wall_opening(door->host_wall_id, updated);
    invalidate_dependency_graph_cache();
}

void Document::resize_window(ElementId window_id, double width_meters, double height_meters, double sill_height_meters) {
    auto& window_element = require_window(window_id);
    auto* window = window_element.window();
    auto updated = HostedOpening{
        .element_id = window_id,
        .kind = OpeningKind::Window,
        .offset_meters = window->offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
    };
    auto wall_copy = *require_wall(window->host_wall_id).wall();
    for (auto& opening : wall_copy.openings) {
        if (opening.element_id == window_id) {
            opening = updated;
        }
    }
    validate_wall_openings(wall_copy);
    window->width_meters = width_meters;
    window->height_meters = height_meters;
    window->sill_height_meters = sill_height_meters;
    window_element.touch();
    update_wall_opening(window->host_wall_id, updated);
    invalidate_dependency_graph_cache();
}

void Document::auto_join_walls() {
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

            const auto intersection = segment_intersection(first_wall->axis, second_wall->axis);
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

    invalidate_dependency_graph_cache();
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

    for (const auto& [level_id, walls] : walls_by_level) {
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
                elements_.emplace_back(room_id, ElementKind::Room, "Room", RoomData{
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
                    .interior_wall_finish_area_square_meters = std::max(0.0, (interior_perimeter * walls.front().wall->height_meters) - opening_area_on_boundary),
                });
                room_ids.push_back(room_id);
            }
        }
    }

    for (auto it = floor_systems_.begin(); it != floor_systems_.end();) {
        const auto* room = find_ptr(it->second.room_id);
        if (room == nullptr || room->room() == nullptr) {
            it = floor_systems_.erase(it);
            continue;
        }
        update_floor_system_from_room(it->second.room_id);
        ++it;
    }

    for (auto it = ceiling_systems_.begin(); it != ceiling_systems_.end();) {
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
    dirty_room_ids_ = dependency_graph().dependent_rooms(wall_id);
    for (const auto room_id : dirty_room_ids_) {
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
}

std::vector<ElementId> Document::recompute_dirty_rooms() {
    if (dirty_room_ids_.empty()) {
        return {};
    }

    std::vector<ElementId> level_ids;
    for (const auto room_id : dirty_room_ids_) {
        const auto* room_element = find_ptr(room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room != nullptr && std::find(level_ids.begin(), level_ids.end(), room->level_id) == level_ids.end()) {
            level_ids.push_back(room->level_id);
        }
    }
    dirty_room_ids_.clear();
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

void Document::regenerate_dirty_geometry() {
    GeometryService geometry;
    for (auto& element : elements_) {
        auto* wall = element.wall();
        if (wall != nullptr && wall->geometry.dirty) {
            wall->geometry = geometry.build_wall_geometry(*wall, element.revision());
        }

        auto* slab = element.slab();
        if (slab != nullptr && slab->generated_geometry_dirty) {
            slab->area_square_meters = polygon_area(slab->boundary_polygon);
            slab->volume_cubic_meters = slab->area_square_meters * slab->thickness_meters;
            const auto thickness = slab->assembly_id != 0
                ? (get_layered_assembly(slab->assembly_id) == nullptr ? slab->thickness_meters : layered_assembly_total_thickness(*get_layered_assembly(slab->assembly_id)))
                : slab->thickness_meters;
            slab->mesh = extrude_polygon_mesh(slab->boundary_polygon, thickness, slab->elevation_offset_meters);
            slab->generated_geometry_dirty = false;
        }

        auto* roof = element.roof();
        if (roof != nullptr && roof->generated_geometry_dirty) {
            const auto thickness = roof->assembly_id != 0
                ? (get_layered_assembly(roof->assembly_id) == nullptr ? roof->thickness_meters : layered_assembly_total_thickness(*get_layered_assembly(roof->assembly_id)))
                : roof->thickness_meters;
            roof->area_square_meters = roof_surface_area(*roof);
            roof->volume_cubic_meters = roof->area_square_meters * thickness;
            roof->mesh = roof->roof_type == RoofType::Flat
                ? extrude_polygon_mesh(roof->boundary_polygon, thickness, 0.0)
                : MeshBuffer{};
            roof->generated_geometry_dirty = false;
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
        if (stair != nullptr && stair->generated_geometry_dirty) {
            stair->footprint_area_square_meters = stair->width_meters * stair->total_run_meters;
            stair->volume_cubic_meters = stair->footprint_area_square_meters * (stair->total_rise_meters / 2.0);
            stair->mesh = build_stair_mesh(*stair);
            stair->generated_geometry_dirty = false;
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

ValidationReport Document::validate_document() const {
    ValidationReport report;
    (void)dependency_graph();

    for (const auto& [wall_type_id, wall_type] : wall_types_) {
        if (total_wall_type_thickness(wall_type) <= 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, wall_type_id, "wall type total thickness must be positive");
        }
        for (const auto& layer : wall_type.layers) {
            if (layer.thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, wall_type_id, "wall type layer thickness must be positive");
            }
            if (layer.material_id != 0 && get_material(layer.material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "wall type references missing material");
            }
        }
    }
    for (const auto& [assembly_id, assembly] : layered_assemblies_) {
        if (layered_assembly_total_thickness(assembly) <= 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, assembly_id, "assembly total thickness must be positive");
        }
        for (const auto& layer : assembly.layers) {
            if (layer.thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, assembly_id, "assembly layer thickness must be positive");
            }
            if (layer.material_id != 0 && get_material(layer.material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "assembly references missing material");
            }
        }
    }

    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            if (length(wall->axis) <= epsilon) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "wall length must be positive");
            }
            if (wall->wall_type_id != 0 && get_wall_type(wall->wall_type_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "wall references missing wall type");
            }

            std::set<std::pair<ElementId, std::string>> seen_joins;
            for (const auto& join : wall->joins) {
                if (find_ptr(join.other_wall_id) == nullptr || find_ptr(join.other_wall_id)->wall() == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "join references missing wall");
                    continue;
                }

                std::ostringstream key;
                key << join.other_wall_id << ':' << join.point.x << ':' << join.point.y;
                if (!seen_joins.insert({join.other_wall_id, key.str()}).second) {
                    add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::DuplicateJoin, element.id(), "duplicate join detected");
                }
            }

            for (std::size_t index = 0; index < wall->openings.size(); ++index) {
                const auto& opening = wall->openings[index];
                const auto* opening_element = find_ptr(opening.element_id);
                if (opening_element == nullptr || (opening_element->door() == nullptr && opening_element->window() == nullptr)) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "wall references missing opening");
                    continue;
                }

                const auto opening_level_id = opening_element->door() != nullptr ? opening_element->door()->level_id : opening_element->window()->level_id;
                if (opening_level_id != wall->level_id) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, opening.element_id, "opening level does not match host wall");
                }

                try {
                    validate_wall_openings(*wall);
                } catch (const std::invalid_argument& error) {
                    const auto message = std::string(error.what());
                    const auto code = message.find("overlaps") != std::string::npos
                        ? ValidationIssueCode::OverlappingOpenings
                        : ValidationIssueCode::OpeningOutsideWall;
                    add_issue(report, ValidationSeverity::Error, code, opening.element_id, message);
                    break;
                }
            }
        } else if (const auto* door = element.door()) {
            const auto* host = find_ptr(door->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "door host wall does not exist");
            } else if (host->wall()->level_id != door->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "door level does not match host wall");
            }
        } else if (const auto* window = element.window()) {
            const auto* host = find_ptr(window->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "window host wall does not exist");
            } else if (host->wall()->level_id != window->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "window level does not match host wall");
            }
        } else if (const auto* room = element.room()) {
            if (room->centerline_area_square_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room area must be positive");
            }
            if (room->interior_area_square_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room interior area must be positive");
            }
            if (std::abs(room->floor_finish_area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room floor area should match interior area");
            }
            if (std::abs(room->ceiling_area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room ceiling area should match interior area");
            }
            for (const auto boundary_id : room->boundary_wall_ids) {
                const auto* boundary = find_ptr(boundary_id);
                if (boundary == nullptr || boundary->wall() == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, element.id(), "room boundary references missing wall");
                }
            }
        } else if (const auto* slab = element.slab()) {
            if (slab->thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "slab thickness must be positive");
            }
            if (polygon_area(slab->boundary_polygon) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "slab boundary area must be positive");
            }
            if (slab->material_id != 0 && get_material(slab->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "slab references missing material");
            }
            if (slab->assembly_id != 0 && get_layered_assembly(slab->assembly_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "slab references missing assembly");
            }
        } else if (const auto* roof = element.roof()) {
            if (roof->thickness_meters <= 0.0 || roof_plan_area(*roof) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "roof dimensions must be positive");
            }
            if (roof->material_id != 0 && get_material(roof->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "roof references missing material");
            }
            if (roof->assembly_id != 0 && get_layered_assembly(roof->assembly_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "roof references missing assembly");
            }
        } else if (const auto* column = element.column()) {
            if (column->width_meters <= 0.0 || column->depth_meters <= 0.0 || column->height_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "column dimensions must be positive");
            }
            if (column->material_id != 0 && get_material(column->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "column references missing material");
            }
        } else if (const auto* beam = element.beam()) {
            if (beam->width_meters <= 0.0 || beam->height_meters <= 0.0 || length(Line2{.start = beam->start, .end = beam->end}) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "beam dimensions must be positive");
            }
            if (beam->material_id != 0 && get_material(beam->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "beam references missing material");
            }
        } else if (const auto* stair = element.stair()) {
            if (stair->width_meters <= 0.0 || stair->total_rise_meters <= 0.0 || stair->total_run_meters <= 0.0 || stair->riser_count <= 0 || stair->tread_count <= 0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "stair dimensions and counts must be positive");
            }
            if (find_ptr(stair->base_level_id) == nullptr || find_ptr(stair->base_level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "stair base level does not exist");
            }
            if (stair->top_level_id != 0 && (find_ptr(stair->top_level_id) == nullptr || find_ptr(stair->top_level_id)->level() == nullptr)) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "stair top level does not exist");
            }
            if (stair->material_id != 0 && get_material(stair->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "stair references missing material");
            }
        }
    }

    for (const auto& [system_id, system] : floor_systems_) {
        const auto* room_element = find_ptr(system.room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "floor system references missing room");
        } else {
            if (system.area_square_meters < 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "floor system area cannot be negative");
            }
            if (!cyclic_polygon_equal(system.boundary_polygon, room->interior_boundary_polygon)) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "floor system boundary should match room interior boundary");
            }
            if (std::abs(system.area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, system_id, "floor system area should match room interior area");
            }
            if (system.level_id != room->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "floor system level does not match room");
            }
        }
        const auto* assembly = get_layered_assembly(system.assembly_id);
        if (assembly == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "floor system references missing assembly");
        } else if (assembly->kind != LayeredAssemblyKind::Floor) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "floor system assembly must be floor kind");
        }
    }

    for (const auto& [system_id, system] : ceiling_systems_) {
        const auto* room_element = find_ptr(system.room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "ceiling system references missing room");
        } else {
            if (system.area_square_meters < 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "ceiling system area cannot be negative");
            }
            if (!cyclic_polygon_equal(system.boundary_polygon, room->interior_boundary_polygon)) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "ceiling system boundary should match room interior boundary");
            }
            if (std::abs(system.area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, system_id, "ceiling system area should match room interior area");
            }
            if (system.level_id != room->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "ceiling system level does not match room");
            }
        }
        const auto* assembly = get_layered_assembly(system.assembly_id);
        if (assembly == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "ceiling system references missing assembly");
        } else if (assembly->kind != LayeredAssemblyKind::Ceiling) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "ceiling system assembly must be ceiling kind");
        }
    }

    for (const auto& row : generate_wall_schedule()) {
        if (row.opening_area_square_meters > row.gross_area_square_meters) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OpeningOutsideWall, row.wall_id, "opening area exceeds wall gross area");
        }
        if (row.net_area_square_meters < 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OpeningOutsideWall, row.wall_id, "wall net area cannot be negative");
        }
    }
    for (const auto& row : generate_material_takeoff()) {
        if (row.quantity < 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OpeningOutsideWall, row.material_id, "material takeoff quantity cannot be negative");
        }
    }

    return report;
}

std::vector<WallRoomAdjacency> Document::wall_room_adjacencies() const {
    std::vector<WallRoomAdjacency> rows;
    std::map<ElementId, std::vector<WallRoomAdjacency>> by_wall;
    for (const auto& element : elements_) {
        const auto* room = element.room();
        if (room == nullptr) {
            continue;
        }

        for (const auto wall_id : room->boundary_wall_ids) {
            const auto* wall_element = find_ptr(wall_id);
            const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
            if (wall == nullptr) {
                continue;
            }

            const auto polygon = room->centerline_boundary_polygon;
            auto side = WallRoomSide::Exterior;
            if (polygon.size() >= 2) {
                const auto center = Point2{
                    .x = (wall->axis.start.x + wall->axis.end.x) / 2.0,
                    .y = (wall->axis.start.y + wall->axis.end.y) / 2.0,
                };
                const auto probe = is_vertical(wall->axis)
                    ? Point2{.x = center.x + 0.01, .y = center.y}
                    : Point2{.x = center.x, .y = center.y + 0.01};
                auto inside = false;
                for (std::size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
                    const auto intersect = ((polygon[i].y > probe.y) != (polygon[j].y > probe.y)) &&
                        (probe.x < (polygon[j].x - polygon[i].x) * (probe.y - polygon[i].y) / (polygon[j].y - polygon[i].y + epsilon) + polygon[i].x);
                    if (intersect) {
                        inside = !inside;
                    }
                }
                if (is_vertical(wall->axis)) {
                    side = inside ? WallRoomSide::Right : WallRoomSide::Left;
                } else {
                    side = inside ? WallRoomSide::Left : WallRoomSide::Right;
                }
            }

            by_wall[wall_id].push_back(WallRoomAdjacency{
                .wall_id = wall_id,
                .room_id = element.id(),
                .side = side,
            });
        }
    }
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }
        auto& entries = by_wall[element.id()];
        if (entries.empty()) {
            entries.push_back(WallRoomAdjacency{
                .wall_id = element.id(),
                .room_id = 0,
                .side = WallRoomSide::Exterior,
            });
        } else if (entries.size() == 1) {
            entries.push_back(WallRoomAdjacency{
                .wall_id = element.id(),
                .room_id = 0,
                .side = WallRoomSide::Exterior,
            });
        }
        for (const auto& entry : entries) {
            rows.push_back(entry);
        }
    }
    return rows;
}

std::vector<WallScheduleRow> Document::generate_wall_schedule() const {
    std::vector<WallScheduleRow> rows;
    const auto adjacencies = wall_room_adjacencies();
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }

        const auto length_meters = length(wall->axis);
        const auto gross_area = length_meters * wall->height_meters;
        auto opening_area = 0.0;
        for (const auto& opening : wall->openings) {
            opening_area += opening.width_meters * opening.height_meters;
        }
        const auto net_area = std::max(0.0, gross_area - opening_area);
        std::map<ElementId, double> material_volumes;
        if (const auto* wall_type = get_wall_type(wall->wall_type_id)) {
            for (const auto& layer : wall_type->layers) {
                material_volumes[layer.material_id] += net_area * layer.thickness_meters;
            }
        }
        const auto room_count = std::count_if(adjacencies.begin(), adjacencies.end(), [&](const WallRoomAdjacency& adjacency) {
            return adjacency.wall_id == element.id() && adjacency.room_id != 0;
        });
        rows.push_back(WallScheduleRow{
            .wall_id = element.id(),
            .level_id = wall->level_id,
            .wall_type_id = wall->wall_type_id,
            .wall_type_name = wall_type_name(wall->wall_type_id),
            .length_meters = length_meters,
            .thickness_meters = wall_thickness(*wall),
            .height_meters = wall->height_meters,
            .gross_area_square_meters = gross_area,
            .opening_area_square_meters = opening_area,
            .net_area_square_meters = net_area,
            .gross_volume_cubic_meters = gross_area * wall_thickness(*wall),
            .net_volume_cubic_meters = net_area * wall_thickness(*wall),
            .interior_finish_area_square_meters = room_count == 0 ? 0.0 : net_area * static_cast<double>(std::min<std::size_t>(room_count, 2)),
            .exterior_finish_area_square_meters = room_count < 2 ? net_area : 0.0,
            .material_volume_by_id = std::move(material_volumes),
        });
    }
    return rows;
}

std::vector<OpeningScheduleRow> Document::generate_opening_schedule() const {
    std::vector<OpeningScheduleRow> rows;
    for (const auto& element : elements_) {
        if (const auto* door = element.door()) {
            rows.push_back(OpeningScheduleRow{
                .element_id = element.id(),
                .type = OpeningKind::Door,
                .host_wall_id = door->host_wall_id,
                .width_meters = door->width_meters,
                .height_meters = door->height_meters,
                .area_square_meters = door->width_meters * door->height_meters,
                .level_id = door->level_id,
            });
        } else if (const auto* window = element.window()) {
            rows.push_back(OpeningScheduleRow{
                .element_id = element.id(),
                .type = OpeningKind::Window,
                .host_wall_id = window->host_wall_id,
                .width_meters = window->width_meters,
                .height_meters = window->height_meters,
                .area_square_meters = window->width_meters * window->height_meters,
                .level_id = window->level_id,
            });
        }
    }
    return rows;
}

std::vector<RoomScheduleRow> Document::generate_room_schedule() const {
    std::vector<RoomScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* room = element.room();
        if (room == nullptr) {
            continue;
        }
        rows.push_back(RoomScheduleRow{
            .room_id = element.id(),
            .level_id = room->level_id,
            .centerline_area_square_meters = room->centerline_area_square_meters,
            .interior_area_square_meters = room->interior_area_square_meters,
            .interior_perimeter_meters = room->interior_perimeter_meters,
            .baseboard_length_meters = room->baseboard_length_meters,
            .floor_finish_area_square_meters = room->floor_finish_area_square_meters,
            .ceiling_area_square_meters = room->ceiling_area_square_meters,
            .interior_wall_finish_area_square_meters = room->interior_wall_finish_area_square_meters,
        });
    }
    return rows;
}

std::vector<SlabScheduleRow> Document::generate_slab_schedule() const {
    std::vector<SlabScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* slab = element.slab();
        if (slab == nullptr) {
            continue;
        }
        std::string label;
        if (slab->assembly_id != 0) {
            label = layered_assembly_name(slab->assembly_id);
        } else if (slab->material_id != 0) {
            const auto* material = get_material(slab->material_id);
            label = material == nullptr ? std::string{} : material->name;
        }
        rows.push_back(SlabScheduleRow{
            .slab_id = element.id(),
            .level_id = slab->level_id,
            .area_square_meters = slab->area_square_meters > 0.0 ? slab->area_square_meters : polygon_area(slab->boundary_polygon),
            .thickness_meters = slab->thickness_meters,
            .volume_cubic_meters = slab->volume_cubic_meters > 0.0 ? slab->volume_cubic_meters : polygon_area(slab->boundary_polygon) * slab->thickness_meters,
            .material_or_assembly_name = std::move(label),
        });
    }
    return rows;
}

std::vector<RoofScheduleRow> Document::generate_roof_schedule() const {
    std::vector<RoofScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* roof = element.roof();
        if (roof == nullptr) {
            continue;
        }
        std::string label;
        if (roof->assembly_id != 0) {
            label = layered_assembly_name(roof->assembly_id);
        } else if (roof->material_id != 0) {
            const auto* material = get_material(roof->material_id);
            label = material == nullptr ? std::string{} : material->name;
        }
        rows.push_back(RoofScheduleRow{
            .roof_id = element.id(),
            .level_id = roof->level_id,
            .roof_type = roof->roof_type,
            .area_square_meters = roof->area_square_meters > 0.0 ? roof->area_square_meters : roof_surface_area(*roof),
            .thickness_meters = roof->thickness_meters,
            .volume_cubic_meters = roof->volume_cubic_meters > 0.0 ? roof->volume_cubic_meters : roof_surface_area(*roof) * roof->thickness_meters,
            .material_or_assembly_name = std::move(label),
        });
    }
    return rows;
}

std::vector<ColumnScheduleRow> Document::generate_column_schedule() const {
    std::vector<ColumnScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* column = element.column();
        if (column == nullptr) {
            continue;
        }
        const auto* material = get_material(column->material_id);
        rows.push_back(ColumnScheduleRow{
            .column_id = element.id(),
            .level_id = column->level_id,
            .width_meters = column->width_meters,
            .depth_meters = column->depth_meters,
            .height_meters = column->height_meters,
            .volume_cubic_meters = column->volume_cubic_meters > 0.0 ? column->volume_cubic_meters : column->width_meters * column->depth_meters * column->height_meters,
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<BeamScheduleRow> Document::generate_beam_schedule() const {
    std::vector<BeamScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* beam = element.beam();
        if (beam == nullptr) {
            continue;
        }
        const auto* material = get_material(beam->material_id);
        const auto beam_length = beam->length_meters > 0.0 ? beam->length_meters : length(Line2{.start = beam->start, .end = beam->end});
        rows.push_back(BeamScheduleRow{
            .beam_id = element.id(),
            .level_id = beam->level_id,
            .length_meters = beam_length,
            .width_meters = beam->width_meters,
            .height_meters = beam->height_meters,
            .volume_cubic_meters = beam->volume_cubic_meters > 0.0 ? beam->volume_cubic_meters : beam_length * beam->width_meters * beam->height_meters,
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<StairScheduleRow> Document::generate_stair_schedule() const {
    std::vector<StairScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* stair = element.stair();
        if (stair == nullptr) {
            continue;
        }
        const auto* material = get_material(stair->material_id);
        rows.push_back(StairScheduleRow{
            .stair_id = element.id(),
            .base_level_id = stair->base_level_id,
            .top_level_id = stair->top_level_id,
            .width_meters = stair->width_meters,
            .total_rise_meters = stair->total_rise_meters,
            .total_run_meters = stair->total_run_meters,
            .riser_count = stair->riser_count,
            .tread_count = stair->tread_count,
            .footprint_area_square_meters = stair->footprint_area_square_meters > 0.0 ? stair->footprint_area_square_meters : stair->width_meters * stair->total_run_meters,
            .volume_cubic_meters = stair->volume_cubic_meters > 0.0 ? stair->volume_cubic_meters : (stair->width_meters * stair->total_run_meters * stair->total_rise_meters / 2.0),
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<FloorFinishScheduleRow> Document::generate_floor_finish_schedule() const {
    std::vector<FloorFinishScheduleRow> rows;
    for (const auto& [system_id, system] : floor_systems_) {
        FloorFinishScheduleRow row{
            .floor_system_id = system_id,
            .room_id = system.room_id,
            .area_square_meters = system.area_square_meters,
            .assembly_name = layered_assembly_name(system.assembly_id),
        };
        if (const auto* assembly = get_layered_assembly(system.assembly_id)) {
            for (const auto& layer : assembly->layers) {
                row.layer_quantities[layer.material_id] += system.area_square_meters * layer.thickness_meters;
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}

std::vector<CeilingScheduleRow> Document::generate_ceiling_schedule() const {
    std::vector<CeilingScheduleRow> rows;
    for (const auto& [system_id, system] : ceiling_systems_) {
        CeilingScheduleRow row{
            .ceiling_system_id = system_id,
            .room_id = system.room_id,
            .area_square_meters = system.area_square_meters,
            .assembly_name = layered_assembly_name(system.assembly_id),
        };
        if (const auto* assembly = get_layered_assembly(system.assembly_id)) {
            for (const auto& layer : assembly->layers) {
                row.layer_quantities[layer.material_id] += system.area_square_meters * layer.thickness_meters;
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}

std::vector<MaterialTakeoffRow> Document::generate_material_takeoff() const {
    std::map<std::pair<ElementId, QuantityType>, MaterialTakeoffRow> aggregated;

    for (const auto& row : generate_wall_schedule()) {
        for (const auto& [material_id, volume] : row.material_volume_by_id) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.wall_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& row : generate_opening_schedule()) {
        if (row.type != OpeningKind::Window) {
            continue;
        }
        ElementId material_id = 0;
        if (const auto material = std::find_if(materials_.begin(), materials_.end(), [](const auto& item) {
                return item.second.category == MaterialCategory::Glass;
            }); material != materials_.end()) {
            material_id = material->first;
        }
        if (material_id == 0) {
            continue;
        }
        auto& takeoff = aggregated[{material_id, QuantityType::Area}];
        takeoff.material_id = material_id;
        takeoff.material_name = materials_.at(material_id).name;
        takeoff.quantity_type = QuantityType::Area;
        takeoff.unit = "m2";
        takeoff.quantity += row.area_square_meters;
        takeoff.source_element_ids.push_back(row.element_id);
    }

    for (const auto& row : generate_floor_finish_schedule()) {
        for (const auto& [material_id, volume] : row.layer_quantities) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.floor_system_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& row : generate_ceiling_schedule()) {
        for (const auto& [material_id, volume] : row.layer_quantities) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.ceiling_system_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& element : elements_) {
        const auto* slab = element.slab();
        if (slab == nullptr) {
            if (const auto* roof = element.roof()) {
                const auto area = roof->area_square_meters > 0.0 ? roof->area_square_meters : roof_surface_area(*roof);
                const auto thickness = roof->assembly_id != 0
                    ? (get_layered_assembly(roof->assembly_id) == nullptr ? roof->thickness_meters : layered_assembly_total_thickness(*get_layered_assembly(roof->assembly_id)))
                    : roof->thickness_meters;
                if (roof->assembly_id != 0) {
                    if (const auto* assembly = get_layered_assembly(roof->assembly_id)) {
                        for (const auto& layer : assembly->layers) {
                            const auto volume = area * layer.thickness_meters;
                            const auto* material = get_material(layer.material_id);
                            auto& takeoff = aggregated[{layer.material_id, QuantityType::Volume}];
                            takeoff.material_id = layer.material_id;
                            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                            takeoff.quantity_type = QuantityType::Volume;
                            takeoff.unit = "m3";
                            takeoff.quantity += volume;
                            takeoff.source_element_ids.push_back(element.id());
                            if (material != nullptr && material->unit_cost.has_value()) {
                                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
                            }
                        }
                    }
                } else if (roof->material_id != 0) {
                    const auto* material = get_material(roof->material_id);
                    auto& takeoff = aggregated[{roof->material_id, QuantityType::Volume}];
                    takeoff.material_id = roof->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += area * thickness;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (area * thickness * *material->unit_cost);
                    }
                }
            } else if (const auto* column = element.column()) {
                if (column->material_id != 0) {
                    const auto* material = get_material(column->material_id);
                    auto& takeoff = aggregated[{column->material_id, QuantityType::Volume}];
                    takeoff.material_id = column->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += column->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (column->volume_cubic_meters * *material->unit_cost);
                    }
                }
            } else if (const auto* beam = element.beam()) {
                if (beam->material_id != 0) {
                    const auto* material = get_material(beam->material_id);
                    auto& takeoff = aggregated[{beam->material_id, QuantityType::Volume}];
                    takeoff.material_id = beam->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += beam->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (beam->volume_cubic_meters * *material->unit_cost);
                    }
                }
            } else if (const auto* stair = element.stair()) {
                if (stair->material_id != 0) {
                    const auto* material = get_material(stair->material_id);
                    auto& takeoff = aggregated[{stair->material_id, QuantityType::Volume}];
                    takeoff.material_id = stair->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += stair->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (stair->volume_cubic_meters * *material->unit_cost);
                    }
                }
            }
            continue;
        }
        const auto slab_area = slab->area_square_meters > 0.0 ? slab->area_square_meters : polygon_area(slab->boundary_polygon);
        if (slab->assembly_id != 0) {
            if (const auto* assembly = get_layered_assembly(slab->assembly_id)) {
                for (const auto& layer : assembly->layers) {
                    const auto volume = slab_area * layer.thickness_meters;
                    const auto* material = get_material(layer.material_id);
                    auto& takeoff = aggregated[{layer.material_id, QuantityType::Volume}];
                    takeoff.material_id = layer.material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += volume;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
                    }
                }
            }
        } else if (slab->material_id != 0) {
            const auto volume = slab_area * slab->thickness_meters;
            const auto* material = get_material(slab->material_id);
            auto& takeoff = aggregated[{slab->material_id, QuantityType::Volume}];
            takeoff.material_id = slab->material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(element.id());
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    std::vector<MaterialTakeoffRow> rows;
    for (auto& [_, row] : aggregated) {
        std::sort(row.source_element_ids.begin(), row.source_element_ids.end());
        row.source_element_ids.erase(std::unique(row.source_element_ids.begin(), row.source_element_ids.end()), row.source_element_ids.end());
        rows.push_back(std::move(row));
    }
    return rows;
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

std::string Document::layered_assembly_name(ElementId assembly_id) const {
    if (const auto* assembly = get_layered_assembly(assembly_id)) {
        return assembly->name;
    }
    return {};
}

void Document::add_opening_to_wall(ElementId host_wall_id, HostedOpening opening) {
    auto& wall_element = require_wall(host_wall_id);
    auto* wall = wall_element.wall();
    wall->openings.push_back(opening);
    validate_wall_openings(*wall);
    mark_wall_dirty(wall_element);
}

void Document::validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const {
    if (offset_meters < 0.0 || width_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("opening dimensions must be positive");
    }

    if (height_meters > wall.height_meters) {
        throw std::invalid_argument("opening is taller than host wall");
    }

    const auto wall_length = length(wall.axis);
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
    for (std::size_t index = 0; index < wall.openings.size(); ++index) {
        const auto& opening = wall.openings[index];
        if (ignored_opening_id.has_value() && opening.element_id == *ignored_opening_id) {
            continue;
        }
        if (opening.offset_meters < 0.0 || opening.width_meters <= 0.0 || opening.height_meters <= 0.0 || opening.sill_height_meters < 0.0) {
            throw std::invalid_argument("opening dimensions must be positive");
        }
        if ((opening.height_meters + opening.sill_height_meters) > wall.height_meters) {
            throw std::invalid_argument("opening is taller than host wall");
        }
        const auto wall_length = length(wall.axis);
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
    auto_join_walls();
    mark_rooms_dirty_for_wall(wall_id);
    touch_related_rooms(wall_id);
    auto recomputed = recompute_dirty_rooms();
    if (recomputed.empty()) {
        const auto* wall_element = find_ptr(wall_id);
        const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
        if (wall != nullptr) {
            (void)detect_rooms_for_levels({wall->level_id});
        }
    }
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
