#include "tbe/api/EngineApi.hpp"

#include "tbe/core/Project.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <limits>
#include <utility>

namespace tbe::api {

namespace {

inline constexpr std::string_view kEngineVersion = "TabletBimEngine 0.1.0";
inline constexpr std::string_view kCoreVersion = "tbe_core 0.1.0";
inline constexpr std::string_view kApiVersion = "tbe_api 0.1.0";

using tbe::core::Document;
using tbe::core::Element;
using tbe::core::ElementId;
using tbe::core::Line2;
using tbe::core::Point2;
using tbe::core::Point3;
using tbe::core::Project;

struct SessionTransaction {
    std::string name{};
    std::string before_json{};
    std::string after_json{};
};

struct JsonPatchResult {
    std::string json{};
    int changes{};
    std::vector<std::string> messages{};
};

struct SpatialEntry {
    ElementId element_id{};
    ElementId level_id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    HitKind preferred_hit_kind{HitKind::None};
    AABB2D bounds{};
    std::vector<Point2> polygon{};
    Line2 axis{};
    double thickness_meters{};
};

struct LevelSpatialIndex {
    std::vector<SpatialEntry> entries{};
    std::map<std::pair<int, int>, std::vector<std::size_t>> buckets{};
    double cell_size_meters{2.0};
};

bool is_non_clean(FreshnessState state) {
    return state == FreshnessState::Dirty || state == FreshnessState::Stale || state == FreshnessState::Failed;
}

bool has_cached_state(FreshnessState state) {
    return state == FreshnessState::Clean || state == FreshnessState::Stale;
}

double distance(Point2 left, Point2 right) {
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

double clamp(double value, double min_value, double max_value) {
    return std::max(min_value, std::min(value, max_value));
}

double line_length(Line2 line) {
    return distance(line.start, line.end);
}

bool near_zero(double value) {
    return std::abs(value) < 1.0e-9;
}

double distance_point_to_segment(Point2 point, Line2 line, double* out_param = nullptr, Point2* out_projected = nullptr) {
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    const auto length_squared = (dx * dx) + (dy * dy);
    if (length_squared <= 1.0e-12) {
        if (out_param != nullptr) {
            *out_param = 0.0;
        }
        if (out_projected != nullptr) {
            *out_projected = line.start;
        }
        return distance(point, line.start);
    }
    const auto t = clamp((((point.x - line.start.x) * dx) + ((point.y - line.start.y) * dy)) / length_squared, 0.0, 1.0);
    const auto projected = Point2{.x = line.start.x + (dx * t), .y = line.start.y + (dy * t)};
    if (out_param != nullptr) {
        *out_param = t;
    }
    if (out_projected != nullptr) {
        *out_projected = projected;
    }
    return distance(point, projected);
}

bool point_in_polygon(Point2 point, const std::vector<Point2>& polygon) {
    if (polygon.size() < 3) {
        return false;
    }
    auto inside = false;
    for (std::size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
        const auto intersects = ((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
            (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / ((polygon[j].y - polygon[i].y) + 1.0e-12) + polygon[i].x);
        if (intersects) {
            inside = !inside;
        }
    }
    return inside;
}

AABB2D bounds_from_points(const std::vector<Point2>& points) {
    AABB2D bounds{};
    if (points.empty()) {
        return bounds;
    }
    bounds.min_x = bounds.max_x = points.front().x;
    bounds.min_y = bounds.max_y = points.front().y;
    for (const auto& point : points) {
        bounds.min_x = std::min(bounds.min_x, point.x);
        bounds.min_y = std::min(bounds.min_y, point.y);
        bounds.max_x = std::max(bounds.max_x, point.x);
        bounds.max_y = std::max(bounds.max_y, point.y);
    }
    return bounds;
}

std::vector<Point2> wall_body_polygon(Line2 axis, double thickness_meters) {
    const auto length_value = line_length(axis);
    if (length_value <= 1.0e-12) {
        return {};
    }
    const auto direction = Point2{.x = (axis.end.x - axis.start.x) / length_value, .y = (axis.end.y - axis.start.y) / length_value};
    const auto normal = Point2{.x = -direction.y * (thickness_meters / 2.0), .y = direction.x * (thickness_meters / 2.0)};
    return {
        Point2{.x = axis.start.x + normal.x, .y = axis.start.y + normal.y},
        Point2{.x = axis.end.x + normal.x, .y = axis.end.y + normal.y},
        Point2{.x = axis.end.x - normal.x, .y = axis.end.y - normal.y},
        Point2{.x = axis.start.x - normal.x, .y = axis.start.y - normal.y},
    };
}

int hit_priority(HitKind kind) {
    switch (kind) {
    case HitKind::Opening: return 10;
    case HitKind::Column: return 15;
    case HitKind::Stair: return 16;
    case HitKind::WallBody: return 20;
    case HitKind::Beam: return 22;
    case HitKind::WallAxis: return 30;
    case HitKind::FloorSystem: return 40;
    case HitKind::CeilingSystem: return 41;
    case HitKind::Slab: return 42;
    case HitKind::Roof: return 45;
    case HitKind::RoomInterior: return 100;
    case HitKind::None: return 1000;
    }
    return 1000;
}

int snap_priority(SnapType type) {
    switch (type) {
    case SnapType::Endpoint: return 10;
    case SnapType::WallIntersection: return 11;
    case SnapType::RoomCorner: return 12;
    case SnapType::Midpoint: return 20;
    case SnapType::OrthogonalProjection: return 30;
    case SnapType::WallAxis: return 35;
    case SnapType::Grid: return 50;
    case SnapType::None: return 1000;
    }
    return 1000;
}

ApiStatus status_from_exception(const std::exception& error) {
    if (dynamic_cast<const std::invalid_argument*>(&error) != nullptr) {
        return ApiStatus::InvalidArgument;
    }
    return ApiStatus::InternalError;
}

ElementIdDTO to_id(ElementId id) {
    return ElementIdDTO{.value = id};
}

Vec2 to_vec2(Point2 point) {
    return Vec2{.x = point.x, .y = point.y};
}

std::vector<Vec2> to_vec2_list(const std::vector<Point2>& points) {
    std::vector<Vec2> values;
    values.reserve(points.size());
    for (const auto& point : points) {
        values.push_back(to_vec2(point));
    }
    return values;
}

Vec3 to_vec3(Point3 point) {
    return Vec3{.x = point.x, .y = point.y, .z = point.z};
}

AABB3D make_bounds3d(const std::vector<Vec3>& positions) {
    AABB3D bounds{};
    if (positions.empty()) {
        return bounds;
    }
    bounds.min = bounds.max = positions.front();
    for (const auto& point : positions) {
        bounds.min.x = std::min(bounds.min.x, point.x);
        bounds.min.y = std::min(bounds.min.y, point.y);
        bounds.min.z = std::min(bounds.min.z, point.z);
        bounds.max.x = std::max(bounds.max.x, point.x);
        bounds.max.y = std::max(bounds.max.y, point.y);
        bounds.max.z = std::max(bounds.max.z, point.z);
    }
    return bounds;
}

bool is_finite_vec3(Vec3 point) {
    return std::isfinite(point.x) && std::isfinite(point.y) && std::isfinite(point.z);
}

double safe_value(double value) {
    return std::isfinite(value) ? value : 0.0;
}

std::string escape_json(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const auto character : value) {
        switch (character) {
        case '\\': escaped += "\\\\"; break;
        case '"': escaped += "\\\""; break;
        case '\b': escaped += "\\b"; break;
        case '\f': escaped += "\\f"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (static_cast<unsigned char>(character) < 0x20) {
                escaped += "\\u00";
                const auto value_byte = static_cast<unsigned char>(character);
                const char* digits = "0123456789abcdef";
                escaped.push_back(digits[(value_byte >> 4) & 0x0f]);
                escaped.push_back(digits[value_byte & 0x0f]);
            } else {
                escaped.push_back(character);
            }
            break;
        }
    }
    return escaped;
}

std::string api_kind_name(ApiElementKind kind) {
    switch (kind) {
    case ApiElementKind::Level: return "Level";
    case ApiElementKind::Wall: return "Wall";
    case ApiElementKind::Door: return "Door";
    case ApiElementKind::Window: return "Window";
    case ApiElementKind::Room: return "Room";
    case ApiElementKind::Slab: return "Slab";
    case ApiElementKind::FloorSystem: return "FloorSystem";
    case ApiElementKind::CeilingSystem: return "CeilingSystem";
    case ApiElementKind::Roof: return "Roof";
    case ApiElementKind::Column: return "Column";
    case ApiElementKind::Beam: return "Beam";
    case ApiElementKind::Stair: return "Stair";
    case ApiElementKind::Unknown: return "Unknown";
    }
    return "Unknown";
}

std::string material_category_name(ApiElementKind kind) {
    switch (kind) {
    case ApiElementKind::Window: return "glass";
    case ApiElementKind::Door: return "generic";
    case ApiElementKind::Wall:
    case ApiElementKind::Slab:
    case ApiElementKind::FloorSystem:
    case ApiElementKind::CeilingSystem:
    case ApiElementKind::Roof:
    case ApiElementKind::Column:
    case ApiElementKind::Beam:
    case ApiElementKind::Stair:
        return "structural";
    case ApiElementKind::Level:
    case ApiElementKind::Room:
    case ApiElementKind::Unknown:
        return "generic";
    }
    return "generic";
}

std::vector<Vec3> mesh_positions(const tbe::core::MeshBuffer& mesh) {
    std::vector<Vec3> positions;
    positions.reserve(mesh.vertices.size());
    for (const auto& vertex : mesh.vertices) {
        positions.push_back(to_vec3(vertex));
    }
    return positions;
}

RenderSceneMeshDTO mesh_dto_from_mesh_buffer(const tbe::core::MeshBuffer& mesh) {
    RenderSceneMeshDTO dto;
    dto.positions = mesh_positions(mesh);
    dto.indices = mesh.indices;
    return dto;
}

RenderSceneMeshDTO make_flat_polygon_mesh(const std::vector<tbe::core::Point2>& polygon, double z, double thickness = 0.02) {
    RenderSceneMeshDTO dto;
    if (polygon.size() < 3) {
        return dto;
    }
    dto.positions.reserve(polygon.size() * 2);
    for (const auto& point : polygon) {
        dto.positions.push_back(Vec3{.x = point.x, .y = point.y, .z = z});
    }
    for (const auto& point : polygon) {
        dto.positions.push_back(Vec3{.x = point.x, .y = point.y, .z = z + thickness});
    }
    for (std::uint32_t index = 1; index + 1 < polygon.size(); ++index) {
        dto.indices.push_back(0);
        dto.indices.push_back(index);
        dto.indices.push_back(index + 1);
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size()));
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size() + index + 1));
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size() + index));
    }
    return dto;
}

RenderSceneMeshDTO make_opening_mesh(const tbe::core::Line2& axis, const tbe::core::HostedOpening& opening, double wall_thickness) {
    RenderSceneMeshDTO dto;
    const auto dx = axis.end.x - axis.start.x;
    const auto dy = axis.end.y - axis.start.y;
    const auto length = std::sqrt((dx * dx) + (dy * dy));
    if (length <= 1.0e-9 || opening.width_meters <= 0.0 || opening.height_meters <= 0.0 || wall_thickness <= 0.0) {
        return dto;
    }
    const auto ux = dx / length;
    const auto uy = dy / length;
    const auto nx = -uy;
    const auto ny = ux;
    const auto center_x = axis.start.x + (ux * opening.offset_meters);
    const auto center_y = axis.start.y + (uy * opening.offset_meters);
    const auto sill = safe_value(opening.sill_height_meters);
    const auto width = opening.width_meters;
    const auto height = opening.height_meters;
    const auto half_width = width / 2.0;
    const auto half_thickness = wall_thickness / 2.0;
    const auto bottom = sill;
    const auto top = sill + height;
    const auto corners = std::array<Vec3, 8>{
        Vec3{.x = center_x - (ux * half_width) - (nx * half_thickness), .y = center_y - (uy * half_width) - (ny * half_thickness), .z = bottom},
        Vec3{.x = center_x + (ux * half_width) - (nx * half_thickness), .y = center_y + (uy * half_width) - (ny * half_thickness), .z = bottom},
        Vec3{.x = center_x + (ux * half_width) + (nx * half_thickness), .y = center_y + (uy * half_width) + (ny * half_thickness), .z = bottom},
        Vec3{.x = center_x - (ux * half_width) + (nx * half_thickness), .y = center_y - (uy * half_width) + (ny * half_thickness), .z = bottom},
        Vec3{.x = center_x - (ux * half_width) - (nx * half_thickness), .y = center_y - (uy * half_width) - (ny * half_thickness), .z = top},
        Vec3{.x = center_x + (ux * half_width) - (nx * half_thickness), .y = center_y + (uy * half_width) - (ny * half_thickness), .z = top},
        Vec3{.x = center_x + (ux * half_width) + (nx * half_thickness), .y = center_y + (uy * half_width) + (ny * half_thickness), .z = top},
        Vec3{.x = center_x - (ux * half_width) + (nx * half_thickness), .y = center_y - (uy * half_width) + (ny * half_thickness), .z = top},
    };
    dto.positions.assign(corners.begin(), corners.end());
    dto.indices = {
        0, 1, 2, 0, 2, 3,
        4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1,
        1, 5, 6, 1, 6, 2,
        2, 6, 7, 2, 7, 3,
        3, 7, 4, 3, 4, 0,
    };
    return dto;
}

std::map<ElementId, double> level_elevation_map(const Document& document) {
    std::map<ElementId, double> elevations;
    for (const auto& element : document.elements()) {
        if (const auto* level = element.level(); level != nullptr) {
            elevations[element.id()] = safe_value(level->elevation_meters);
        }
    }
    return elevations;
}

double level_elevation(const std::map<ElementId, double>& levels, ElementId level_id, double fallback = 0.0) {
    const auto found = levels.find(level_id);
    return found == levels.end() ? fallback : found->second;
}

RenderSceneObjectDTO make_object_dto(
    ElementId element_id,
    ApiElementKind kind,
    ElementId level_id,
    std::uint64_t revision,
    RenderSceneMeshDTO mesh,
    std::string material_category,
    bool selectable = true,
    bool visible_by_default = true
) {
    RenderSceneObjectDTO object;
    object.element_id = to_id(element_id);
    object.kind = kind;
    object.level_id = to_id(level_id);
    object.selectable = selectable;
    object.visible_by_default = visible_by_default;
    object.revision = revision;
    object.mesh = std::move(mesh);
    object.material_category = std::move(material_category);
    object.bounds = make_bounds3d(object.mesh.positions);
    return object;
}

RenderSceneDTO build_render_scene(const Document& document) {
    RenderSceneDTO scene;
    scene.scene_version = 1;
    scene.units = "meters";
    scene.coordinate_system = "X/Y plan, Z up";

    const auto elevations = level_elevation_map(document);

    auto append_object = [&](RenderSceneObjectDTO object) {
        if (object.mesh.positions.empty() || object.mesh.indices.empty()) {
            return;
        }
        for (const auto& point : object.mesh.positions) {
            if (!is_finite_vec3(point)) {
                return;
            }
        }
        scene.vertex_count += object.mesh.positions.size();
        scene.index_count += object.mesh.indices.size();
        scene.objects.push_back(std::move(object));
    };

    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall(); wall != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Wall,
                wall->level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(wall->geometry.mesh),
                material_category_name(ApiElementKind::Wall)
            ));
            for (const auto& opening : wall->openings) {
                const auto opening_kind = opening.kind == tbe::core::OpeningKind::Door ? ApiElementKind::Door : ApiElementKind::Window;
                append_object(make_object_dto(
                    opening.element_id,
                    opening_kind,
                    wall->level_id,
                    element.revision(),
                    make_opening_mesh(wall->axis, opening, wall->thickness_meters),
                    material_category_name(opening_kind)
                ));
            }
            continue;
        }
        if (const auto* slab = element.slab(); slab != nullptr) {
            const auto elevation = level_elevation(elevations, slab->level_id, 0.0) + slab->elevation_offset_meters;
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Slab,
                slab->level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(slab->mesh),
                material_category_name(ApiElementKind::Slab)
            ));
            (void)elevation;
            continue;
        }
        if (const auto* roof = element.roof(); roof != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Roof,
                roof->level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(roof->mesh),
                material_category_name(ApiElementKind::Roof)
            ));
            continue;
        }
        if (const auto* column = element.column(); column != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Column,
                column->level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(column->mesh),
                material_category_name(ApiElementKind::Column)
            ));
            continue;
        }
        if (const auto* beam = element.beam(); beam != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Beam,
                beam->level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(beam->mesh),
                material_category_name(ApiElementKind::Beam)
            ));
            continue;
        }
        if (const auto* stair = element.stair(); stair != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Stair,
                stair->base_level_id,
                element.revision(),
                mesh_dto_from_mesh_buffer(stair->mesh),
                material_category_name(ApiElementKind::Stair)
            ));
        }
    }

    for (const auto& [system_id, system] : document.floor_systems()) {
        const auto elevation = level_elevation(elevations, system.level_id, 0.0);
        auto mesh = make_flat_polygon_mesh(system.boundary_polygon, elevation, 0.02);
        append_object(make_object_dto(
            system_id,
            ApiElementKind::FloorSystem,
            system.level_id,
            system.dirty ? 0 : 1,
            std::move(mesh),
            material_category_name(ApiElementKind::FloorSystem)
        ));
    }

    for (const auto& [system_id, system] : document.ceiling_systems()) {
        const auto elevation = level_elevation(elevations, system.level_id, 0.0) + system.height_offset_meters;
        auto mesh = make_flat_polygon_mesh(system.boundary_polygon, elevation, 0.02);
        append_object(make_object_dto(
            system_id,
            ApiElementKind::CeilingSystem,
            system.level_id,
            system.dirty ? 0 : 1,
            std::move(mesh),
            material_category_name(ApiElementKind::CeilingSystem)
        ));
    }

    scene.object_count = scene.objects.size();
    return scene;
}

std::string api_kind_json_name(ApiElementKind kind) {
    return api_kind_name(kind);
}

std::string render_scene_to_json(const RenderSceneDTO& scene) {
    std::ostringstream out;
    out << '{';
    out << "\"scene_version\":" << scene.scene_version << ',';
    out << "\"units\":\"" << "meters" << "\",";
    out << "\"coordinate_system\":\"" << "X/Y plan, Z up" << "\",";
    out << "\"object_count\":" << scene.object_count << ',';
    out << "\"vertex_count\":" << scene.vertex_count << ',';
    out << "\"index_count\":" << scene.index_count << ',';
    out << "\"objects\":[";
    for (std::size_t object_index = 0; object_index < scene.objects.size(); ++object_index) {
        const auto& object = scene.objects[object_index];
        if (object_index != 0) {
            out << ',';
        }
        out << '{';
        out << "\"element_id\":" << object.element_id.value << ',';
        out << "\"kind\":\"" << api_kind_json_name(object.kind) << "\",";
        out << "\"level_id\":" << object.level_id.value << ',';
        out << "\"selectable\":" << (object.selectable ? "true" : "false") << ',';
        out << "\"visible_by_default\":" << (object.visible_by_default ? "true" : "false") << ',';
        out << "\"revision\":" << object.revision << ',';
        out << "\"material_category\":\"" << escape_json(object.material_category) << "\",";
        out << "\"bounds\":{\"min\":{\"x\":" << safe_value(object.bounds.min.x) << ",\"y\":" << safe_value(object.bounds.min.y) << ",\"z\":" << safe_value(object.bounds.min.z)
            << "},\"max\":{\"x\":" << safe_value(object.bounds.max.x) << ",\"y\":" << safe_value(object.bounds.max.y) << ",\"z\":" << safe_value(object.bounds.max.z) << "}},";
        out << "\"mesh\":{\"positions\":[";
        for (std::size_t index = 0; index < object.mesh.positions.size(); ++index) {
            if (index != 0) {
                out << ',';
            }
            const auto& point = object.mesh.positions[index];
            out << "{\"x\":" << safe_value(point.x) << ",\"y\":" << safe_value(point.y) << ",\"z\":" << safe_value(point.z) << "}";
        }
        out << "],\"indices\":[";
        for (std::size_t index = 0; index < object.mesh.indices.size(); ++index) {
            if (index != 0) {
                out << ',';
            }
            out << object.mesh.indices[index];
        }
        out << ']';
        if (object.mesh.normals.has_value()) {
            out << ",\"normals\":[";
            const auto& normals = *object.mesh.normals;
            for (std::size_t index = 0; index < normals.size(); ++index) {
                if (index != 0) {
                    out << ',';
                }
                const auto& normal = normals[index];
                out << "{\"x\":" << safe_value(normal.x) << ",\"y\":" << safe_value(normal.y) << ",\"z\":" << safe_value(normal.z) << "}";
            }
            out << ']';
        }
        out << "}}";
    }
    out << "]}";
    return out.str();
}

ApiElementKind to_api_kind(tbe::core::ElementKind kind) {
    switch (kind) {
    case tbe::core::ElementKind::Level: return ApiElementKind::Level;
    case tbe::core::ElementKind::Wall: return ApiElementKind::Wall;
    case tbe::core::ElementKind::Door: return ApiElementKind::Door;
    case tbe::core::ElementKind::Window: return ApiElementKind::Window;
    case tbe::core::ElementKind::Room: return ApiElementKind::Room;
    case tbe::core::ElementKind::Slab: return ApiElementKind::Slab;
    case tbe::core::ElementKind::Roof: return ApiElementKind::Roof;
    case tbe::core::ElementKind::Column: return ApiElementKind::Column;
    case tbe::core::ElementKind::Beam: return ApiElementKind::Beam;
    case tbe::core::ElementKind::Stair: return ApiElementKind::Stair;
    }
    return ApiElementKind::Unknown;
}

ApiValidationSeverity to_api_severity(tbe::core::ValidationSeverity severity) {
    return severity == tbe::core::ValidationSeverity::Warning ? ApiValidationSeverity::Warning : ApiValidationSeverity::Error;
}

ApiQuantityType to_api_quantity_type(tbe::core::QuantityType type) {
    switch (type) {
    case tbe::core::QuantityType::Area: return ApiQuantityType::Area;
    case tbe::core::QuantityType::Volume: return ApiQuantityType::Volume;
    case tbe::core::QuantityType::Length: return ApiQuantityType::Length;
    case tbe::core::QuantityType::Count: return ApiQuantityType::Count;
    }
    return ApiQuantityType::Volume;
}

tbe::core::RoofType to_core_roof_type(ApiRoofType type) {
    return type == ApiRoofType::SimpleGable ? tbe::core::RoofType::SimpleGable : tbe::core::RoofType::Flat;
}

ValidationIssueDTO to_validation_issue(const tbe::core::ValidationIssue& issue) {
    return ValidationIssueDTO{
        .severity = to_api_severity(issue.severity),
        .element_id = to_id(issue.element_id),
        .message = issue.message,
    };
}

ValidationReportDTO to_validation_report(const tbe::core::ValidationReport& report) {
    ValidationReportDTO dto{
        .issue_count = report.issue_count(),
        .warning_count = report.warning_count(),
        .error_count = report.error_count(),
    };
    dto.issues.reserve(report.issues.size());
    for (const auto& issue : report.issues) {
        dto.issues.push_back(to_validation_issue(issue));
    }
    return dto;
}

ElementSummaryDTO to_element_summary(const Element& element) {
    return ElementSummaryDTO{
        .id = to_id(element.id()),
        .kind = to_api_kind(element.kind()),
        .name = std::string(element.name()),
    };
}

RoomDTO to_room_dto(const Element& element) {
    const auto* room = element.room();
    return RoomDTO{
        .id = to_id(element.id()),
        .level_id = to_id(room == nullptr ? 0 : room->level_id),
        .centerline_boundary_polygon = room == nullptr ? std::vector<Vec2>{} : to_vec2_list(room->centerline_boundary_polygon),
        .interior_boundary_polygon = room == nullptr ? std::vector<Vec2>{} : to_vec2_list(room->interior_boundary_polygon),
        .centerline_area_square_meters = room == nullptr ? 0.0 : room->centerline_area_square_meters,
        .interior_area_square_meters = room == nullptr ? 0.0 : room->interior_area_square_meters,
        .centerline_perimeter_meters = room == nullptr ? 0.0 : room->centerline_perimeter_meters,
        .interior_perimeter_meters = room == nullptr ? 0.0 : room->interior_perimeter_meters,
        .baseboard_length_meters = room == nullptr ? 0.0 : room->baseboard_length_meters,
    };
}

Point2 to_point(Vec2 point) {
    return Point2{.x = point.x, .y = point.y};
}

std::vector<Point2> to_point_list(const std::vector<Vec2>& points) {
    std::vector<Point2> values;
    values.reserve(points.size());
    for (const auto& point : points) {
        values.push_back(to_point(point));
    }
    return values;
}

template <typename T>
ApiResult<T> success_result(T value) {
    ApiResult<T> result;
    result.value = std::move(value);
    return result;
}

ApiVoidResult success_void() {
    return ApiVoidResult{};
}

template <typename T>
ApiResult<T> error_result(ApiStatus status, std::string message) {
    ApiResult<T> result;
    result.status = status;
    result.message = std::move(message);
    return result;
}

ApiVoidResult error_void(ApiStatus status, std::string message) {
    ApiVoidResult result;
    result.status = status;
    result.message = std::move(message);
    return result;
}

FreshnessState dirty_or_stale(FreshnessState state) {
    return has_cached_state(state) ? FreshnessState::Stale : FreshnessState::Dirty;
}

int detect_schema_version_value(std::string_view json) {
    const auto key = std::string_view{"\"schema_version\":"};
    const auto pos = json.find(key);
    if (pos == std::string_view::npos) {
        return 0;
    }
    auto begin = pos + key.size();
    while (begin < json.size() && std::isspace(static_cast<unsigned char>(json[begin]))) {
        ++begin;
    }
    auto end = begin;
    while (end < json.size() && std::isdigit(static_cast<unsigned char>(json[end]))) {
        ++end;
    }
    if (end == begin) {
        return 0;
    }
    return std::stoi(std::string(json.substr(begin, end - begin)));
}

JsonPatchResult ensure_project_schema_version(std::string_view json) {
    JsonPatchResult result{.json = std::string(json)};
    if (detect_schema_version_value(result.json) != 0) {
        return result;
    }
    const auto schema_key = std::string_view{"\"schema\":\"tbe.project.v1\","};
    const auto schema_pos = result.json.find(schema_key);
    if (schema_pos != std::string::npos) {
        result.json.insert(schema_pos + schema_key.size(), "\"schema_version\":1,\"engine_version\":\"mvp-level12\",");
        ++result.changes;
        result.messages.push_back("added missing schema_version for legacy project");
    }
    return result;
}

JsonPatchResult patch_missing_opening_level_ids(std::string_view json) {
    JsonPatchResult result{.json = std::string(json)};
    std::size_t search_from = 0;
    while ((search_from = result.json.find("\"door\":{", search_from)) != std::string::npos) {
        const auto object_end = result.json.find('}', search_from);
        if (object_end == std::string::npos) {
            break;
        }
        if (result.json.find("\"level_id\":", search_from) > object_end) {
            result.json.insert(search_from + std::string("\"door\":{").size(), "\"level_id\":0,");
            ++result.changes;
            result.messages.push_back("added missing door level_id placeholder");
            search_from = object_end + std::string("\"level_id\":0,").size();
        } else {
            search_from = object_end;
        }
    }
    search_from = 0;
    while ((search_from = result.json.find("\"window\":{", search_from)) != std::string::npos) {
        const auto object_end = result.json.find('}', search_from);
        if (object_end == std::string::npos) {
            break;
        }
        if (result.json.find("\"level_id\":", search_from) > object_end) {
            result.json.insert(search_from + std::string("\"window\":{").size(), "\"level_id\":0,");
            ++result.changes;
            result.messages.push_back("added missing window level_id placeholder");
            search_from = object_end + std::string("\"level_id\":0,").size();
        } else {
            search_from = object_end;
        }
    }
    return result;
}

MigrationReportDTO migrate_json_to_current(std::string_view input_json, std::string& migrated_json, int from_version, int to_version) {
    migrated_json = std::string(input_json);
    MigrationReportDTO report{
        .from_version = from_version,
        .to_version = to_version,
    };
    if (from_version == to_version) {
        return report;
    }
    if (from_version == 0 && to_version == tbe::core::TBE_SCHEMA_VERSION) {
        auto schema_patch = ensure_project_schema_version(migrated_json);
        migrated_json = std::move(schema_patch.json);
        report.migrated_count += schema_patch.changes;
        report.messages.insert(report.messages.end(), schema_patch.messages.begin(), schema_patch.messages.end());

        auto opening_patch = patch_missing_opening_level_ids(migrated_json);
        migrated_json = std::move(opening_patch.json);
        report.migrated_count += opening_patch.changes;
        report.messages.insert(report.messages.end(), opening_patch.messages.begin(), opening_patch.messages.end());
        return report;
    }
    report.error_count = 1;
    report.messages.push_back("unsupported schema migration path");
    return report;
}

AABB2D expanded_bounds(AABB2D bounds, double amount) {
    return AABB2D{
        .min_x = bounds.min_x - amount,
        .min_y = bounds.min_y - amount,
        .max_x = bounds.max_x + amount,
        .max_y = bounds.max_y + amount,
    };
}

bool bounds_overlap(AABB2D left, AABB2D right) {
    return left.min_x <= right.max_x && left.max_x >= right.min_x &&
        left.min_y <= right.max_y && left.max_y >= right.min_y;
}

double interval_length(double start, double end) {
    return std::max(0.0, end - start);
}

} // namespace

struct EngineSession::Impl {
    explicit Impl(std::string project_name)
        : project(std::move(project_name)) {}

    Project project;
    std::vector<SessionTransaction> undo_stack{};
    std::vector<SessionTransaction> redo_stack{};
    PerformanceProfile performance_profile{PerformanceProfile::Balanced};
    ComputeMode compute_mode{ComputeMode::Normal};
    FreshnessSummaryDTO freshness{};
    std::optional<std::vector<RoomDTO>> cached_rooms{};
    std::optional<std::vector<WallScheduleDTO>> cached_wall_schedule{};
    std::optional<std::vector<OpeningScheduleDTO>> cached_opening_schedule{};
    std::optional<std::vector<RoomScheduleDTO>> cached_room_schedule{};
    std::optional<std::vector<MaterialTakeoffSummaryDTO>> cached_material_takeoff{};
    std::optional<ValidationReportDTO> cached_validation{};
    MigrationReportDTO last_migration_report{};
    RepairReportDTO last_repair_report{};
    std::map<ElementId, LevelSpatialIndex> spatial_index_by_level{};
    std::uint64_t spatial_index_version{0};
    bool spatial_index_dirty{true};

    [[nodiscard]] Document& document() noexcept {
        return project.active_document();
    }

    [[nodiscard]] const Document& document() const noexcept {
        return project.active_document();
    }

    void clear_caches() {
        cached_rooms.reset();
        cached_wall_schedule.reset();
        cached_opening_schedule.reset();
        cached_room_schedule.reset();
        cached_material_takeoff.reset();
        cached_validation.reset();
    }

    void mark_all_derived_dirty() {
        freshness.room_metrics = dirty_or_stale(freshness.room_metrics);
        freshness.geometry = dirty_or_stale(freshness.geometry);
        freshness.schedules = dirty_or_stale(freshness.schedules);
        freshness.material_takeoff = dirty_or_stale(freshness.material_takeoff);
        freshness.validation_report = dirty_or_stale(freshness.validation_report);
        freshness.exports = dirty_or_stale(freshness.exports);
        spatial_index_dirty = true;
    }
};

EngineSession::EngineSession()
    : EngineSession("API Project") {}

EngineSession::EngineSession(std::string project_name)
    : impl_(std::make_unique<Impl>(std::move(project_name))) {}

EngineSession::~EngineSession() = default;
EngineSession::EngineSession(EngineSession&&) noexcept = default;
EngineSession& EngineSession::operator=(EngineSession&&) noexcept = default;

namespace {

std::vector<RoomDTO> build_room_cache(const Document& document) {
    std::vector<RoomDTO> rooms;
    for (const auto& element : document.elements()) {
        if (element.room() != nullptr) {
            rooms.push_back(to_room_dto(element));
        }
    }
    return rooms;
}

std::vector<WallScheduleDTO> build_wall_schedule_cache(const Document& document) {
    std::vector<WallScheduleDTO> rows;
    for (const auto& row : document.generate_wall_schedule()) {
        rows.push_back(WallScheduleDTO{
            .wall_id = to_id(row.wall_id),
            .level_id = to_id(row.level_id),
            .wall_type_name = row.wall_type_name,
            .length_meters = row.length_meters,
            .thickness_meters = row.thickness_meters,
            .height_meters = row.height_meters,
            .gross_area_square_meters = row.gross_area_square_meters,
            .opening_area_square_meters = row.opening_area_square_meters,
            .net_area_square_meters = row.net_area_square_meters,
            .gross_volume_cubic_meters = row.gross_volume_cubic_meters,
            .net_volume_cubic_meters = row.net_volume_cubic_meters,
        });
    }
    return rows;
}

std::vector<OpeningScheduleDTO> build_opening_schedule_cache(const Document& document) {
    std::vector<OpeningScheduleDTO> rows;
    for (const auto& row : document.generate_opening_schedule()) {
        rows.push_back(OpeningScheduleDTO{
            .element_id = to_id(row.element_id),
            .type = row.type == tbe::core::OpeningKind::Door ? "Door" : "Window",
            .host_wall_id = to_id(row.host_wall_id),
            .width_meters = row.width_meters,
            .height_meters = row.height_meters,
            .area_square_meters = row.area_square_meters,
            .level_id = to_id(row.level_id),
        });
    }
    return rows;
}

std::vector<RoomScheduleDTO> build_room_schedule_cache(const Document& document) {
    std::vector<RoomScheduleDTO> rows;
    for (const auto& row : document.generate_room_schedule()) {
        rows.push_back(RoomScheduleDTO{
            .room_id = to_id(row.room_id),
            .level_id = to_id(row.level_id),
            .centerline_area_square_meters = row.centerline_area_square_meters,
            .interior_area_square_meters = row.interior_area_square_meters,
            .interior_perimeter_meters = row.interior_perimeter_meters,
            .baseboard_length_meters = row.baseboard_length_meters,
            .floor_finish_area_square_meters = row.floor_finish_area_square_meters,
            .ceiling_area_square_meters = row.ceiling_area_square_meters,
            .interior_wall_finish_area_square_meters = row.interior_wall_finish_area_square_meters,
        });
    }
    return rows;
}

std::vector<MaterialTakeoffSummaryDTO> build_material_takeoff_cache(const Document& document) {
    std::vector<MaterialTakeoffSummaryDTO> rows;
    for (const auto& row : document.generate_material_takeoff()) {
        rows.push_back(MaterialTakeoffSummaryDTO{
            .material_id = to_id(row.material_id),
            .material_name = row.material_name,
            .quantity_type = to_api_quantity_type(row.quantity_type),
            .quantity = row.quantity,
            .unit = row.unit,
        });
    }
    return rows;
}

DirtySummaryDTO build_dirty_summary(const FreshnessSummaryDTO& freshness) {
    DirtySummaryDTO summary{
        .has_room_metrics_work = is_non_clean(freshness.room_metrics),
        .has_geometry_work = is_non_clean(freshness.geometry),
        .has_schedule_work = is_non_clean(freshness.schedules),
        .has_material_takeoff_work = is_non_clean(freshness.material_takeoff),
        .has_validation_work = is_non_clean(freshness.validation_report),
        .has_export_work = is_non_clean(freshness.exports),
    };
    const auto count_state = [&](FreshnessState state) {
        if (state == FreshnessState::Dirty) {
            ++summary.dirty_categories;
        } else if (state == FreshnessState::Stale) {
            ++summary.stale_categories;
        }
    };
    count_state(freshness.room_metrics);
    count_state(freshness.geometry);
    count_state(freshness.schedules);
    count_state(freshness.material_takeoff);
    count_state(freshness.validation_report);
    count_state(freshness.exports);
    return summary;
}

template <typename SessionImpl>
void rebuild_spatial_index_impl(SessionImpl& impl) {
    impl.spatial_index_by_level.clear();

    const auto append_entry = [&](ElementId level_id, SpatialEntry entry) {
        auto& level_index = impl.spatial_index_by_level[level_id];
        level_index.entries.push_back(std::move(entry));
    };

    for (const auto& element : impl.document().elements()) {
        if (const auto* wall = element.wall()) {
            const auto polygon = wall_body_polygon(wall->axis, wall->thickness_meters);
            append_entry(wall->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = wall->level_id,
                .kind = ApiElementKind::Wall,
                .preferred_hit_kind = HitKind::WallBody,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
                .axis = wall->axis,
                .thickness_meters = wall->thickness_meters,
            });
            const auto length_value = line_length(wall->axis);
            const auto direction = length_value <= 1.0e-12 ? Point2{} : Point2{.x = (wall->axis.end.x - wall->axis.start.x) / length_value, .y = (wall->axis.end.y - wall->axis.start.y) / length_value};
            const auto normal = Point2{.x = -direction.y * (wall->thickness_meters / 2.0), .y = direction.x * (wall->thickness_meters / 2.0)};
            for (const auto& opening : wall->openings) {
                const auto center = Point2{
                    .x = wall->axis.start.x + (direction.x * opening.offset_meters),
                    .y = wall->axis.start.y + (direction.y * opening.offset_meters),
                };
                const auto half_width = opening.width_meters / 2.0;
                std::vector<Point2> opening_polygon{
                    Point2{.x = center.x + (direction.x * half_width) + normal.x, .y = center.y + (direction.y * half_width) + normal.y},
                    Point2{.x = center.x - (direction.x * half_width) + normal.x, .y = center.y - (direction.y * half_width) + normal.y},
                    Point2{.x = center.x - (direction.x * half_width) - normal.x, .y = center.y - (direction.y * half_width) - normal.y},
                    Point2{.x = center.x + (direction.x * half_width) - normal.x, .y = center.y + (direction.y * half_width) - normal.y},
                };
                append_entry(wall->level_id, SpatialEntry{
                    .element_id = opening.element_id,
                    .level_id = wall->level_id,
                    .kind = opening.kind == tbe::core::OpeningKind::Door ? ApiElementKind::Door : ApiElementKind::Window,
                    .preferred_hit_kind = HitKind::Opening,
                    .bounds = bounds_from_points(opening_polygon),
                    .polygon = opening_polygon,
                    .axis = wall->axis,
                    .thickness_meters = wall->thickness_meters,
                });
            }
        } else if (const auto* room = element.room()) {
            append_entry(room->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = room->level_id,
                .kind = ApiElementKind::Room,
                .preferred_hit_kind = HitKind::RoomInterior,
                .bounds = bounds_from_points(room->interior_boundary_polygon.empty() ? room->centerline_boundary_polygon : room->interior_boundary_polygon),
                .polygon = room->interior_boundary_polygon.empty() ? room->centerline_boundary_polygon : room->interior_boundary_polygon,
            });
        } else if (const auto* slab = element.slab()) {
            append_entry(slab->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = slab->level_id,
                .kind = ApiElementKind::Slab,
                .preferred_hit_kind = HitKind::Slab,
                .bounds = bounds_from_points(slab->boundary_polygon),
                .polygon = slab->boundary_polygon,
            });
        } else if (const auto* roof = element.roof()) {
            append_entry(roof->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = roof->level_id,
                .kind = ApiElementKind::Roof,
                .preferred_hit_kind = HitKind::Roof,
                .bounds = bounds_from_points(roof->boundary_polygon),
                .polygon = roof->boundary_polygon,
            });
        } else if (const auto* column = element.column()) {
            const auto polygon = std::vector<Point2>{
                Point2{.x = column->position.x - (column->width_meters / 2.0), .y = column->position.y - (column->depth_meters / 2.0)},
                Point2{.x = column->position.x + (column->width_meters / 2.0), .y = column->position.y - (column->depth_meters / 2.0)},
                Point2{.x = column->position.x + (column->width_meters / 2.0), .y = column->position.y + (column->depth_meters / 2.0)},
                Point2{.x = column->position.x - (column->width_meters / 2.0), .y = column->position.y + (column->depth_meters / 2.0)},
            };
            append_entry(column->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = column->level_id,
                .kind = ApiElementKind::Column,
                .preferred_hit_kind = HitKind::Column,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
            });
        } else if (const auto* beam = element.beam()) {
            const auto polygon = wall_body_polygon(Line2{.start = beam->start, .end = beam->end}, beam->width_meters);
            append_entry(beam->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = beam->level_id,
                .kind = ApiElementKind::Beam,
                .preferred_hit_kind = HitKind::Beam,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
                .axis = Line2{.start = beam->start, .end = beam->end},
                .thickness_meters = beam->width_meters,
            });
        } else if (const auto* stair = element.stair()) {
            const auto direction_length = std::sqrt((stair->direction.x * stair->direction.x) + (stair->direction.y * stair->direction.y));
            if (direction_length > 1.0e-12) {
                const auto unit = Point2{.x = stair->direction.x / direction_length, .y = stair->direction.y / direction_length};
                const auto end = Point2{.x = stair->start.x + (unit.x * stair->total_run_meters), .y = stair->start.y + (unit.y * stair->total_run_meters)};
                const auto polygon = wall_body_polygon(Line2{.start = stair->start, .end = end}, stair->width_meters);
                append_entry(stair->base_level_id, SpatialEntry{
                    .element_id = element.id(),
                    .level_id = stair->base_level_id,
                    .kind = ApiElementKind::Stair,
                    .preferred_hit_kind = HitKind::Stair,
                    .bounds = bounds_from_points(polygon),
                    .polygon = polygon,
                });
            }
        }
    }

    for (const auto& [system_id, system] : impl.document().floor_systems()) {
        append_entry(system.level_id, SpatialEntry{
            .element_id = system_id,
            .level_id = system.level_id,
            .kind = ApiElementKind::FloorSystem,
            .preferred_hit_kind = HitKind::FloorSystem,
            .bounds = bounds_from_points(system.boundary_polygon),
            .polygon = system.boundary_polygon,
        });
    }
    for (const auto& [system_id, system] : impl.document().ceiling_systems()) {
        append_entry(system.level_id, SpatialEntry{
            .element_id = system_id,
            .level_id = system.level_id,
            .kind = ApiElementKind::CeilingSystem,
            .preferred_hit_kind = HitKind::CeilingSystem,
            .bounds = bounds_from_points(system.boundary_polygon),
            .polygon = system.boundary_polygon,
        });
    }

    for (auto& [_, level_index] : impl.spatial_index_by_level) {
        for (std::size_t index = 0; index < level_index.entries.size(); ++index) {
            const auto& bounds = level_index.entries[index].bounds;
            const auto min_x = static_cast<int>(std::floor(bounds.min_x / level_index.cell_size_meters));
            const auto max_x = static_cast<int>(std::floor(bounds.max_x / level_index.cell_size_meters));
            const auto min_y = static_cast<int>(std::floor(bounds.min_y / level_index.cell_size_meters));
            const auto max_y = static_cast<int>(std::floor(bounds.max_y / level_index.cell_size_meters));
            for (int gx = min_x; gx <= max_x; ++gx) {
                for (int gy = min_y; gy <= max_y; ++gy) {
                    level_index.buckets[{gx, gy}].push_back(index);
                }
            }
        }
    }

    impl.spatial_index_dirty = false;
    ++impl.spatial_index_version;
}

template <typename SessionImpl>
void ensure_spatial_index(SessionImpl& impl) {
    if (impl.spatial_index_dirty) {
        rebuild_spatial_index_impl(impl);
    }
}

template <typename SessionImpl>
const LevelSpatialIndex* find_level_spatial_index(SessionImpl& impl, ElementId level_id) {
    ensure_spatial_index(impl);
    const auto found = impl.spatial_index_by_level.find(level_id);
    if (found == impl.spatial_index_by_level.end()) {
        return nullptr;
    }
    return &found->second;
}

std::vector<std::size_t> query_level_indices(const LevelSpatialIndex& level_index, AABB2D bounds) {
    std::set<std::size_t> unique_indices;
    const auto min_x = static_cast<int>(std::floor(bounds.min_x / level_index.cell_size_meters));
    const auto max_x = static_cast<int>(std::floor(bounds.max_x / level_index.cell_size_meters));
    const auto min_y = static_cast<int>(std::floor(bounds.min_y / level_index.cell_size_meters));
    const auto max_y = static_cast<int>(std::floor(bounds.max_y / level_index.cell_size_meters));
    for (int gx = min_x; gx <= max_x; ++gx) {
        for (int gy = min_y; gy <= max_y; ++gy) {
            const auto found = level_index.buckets.find({gx, gy});
            if (found == level_index.buckets.end()) {
                continue;
            }
            unique_indices.insert(found->second.begin(), found->second.end());
        }
    }

    std::vector<std::size_t> filtered;
    filtered.reserve(unique_indices.size());
    for (const auto index : unique_indices) {
        if (index < level_index.entries.size() && bounds_overlap(level_index.entries[index].bounds, bounds)) {
            filtered.push_back(index);
        }
    }
    return filtered;
}

std::vector<WallFreeIntervalDTO> compute_wall_free_intervals_for_entry(const Element& wall_element, double requested_width_meters, double clearance_meters) {
    const auto* wall = wall_element.wall();
    if (wall == nullptr) {
        throw std::invalid_argument("element is not a wall");
    }

    const auto wall_length = line_length(wall->axis);
    const auto edge_margin = std::max(0.0, (requested_width_meters / 2.0) + clearance_meters);
    if (wall_length <= (2.0 * edge_margin)) {
        return {};
    }

    std::vector<std::pair<double, double>> blocked;
    blocked.push_back({0.0, edge_margin});
    blocked.push_back({wall_length - edge_margin, wall_length});
    for (const auto& opening : wall->openings) {
        const auto half_width = (opening.width_meters / 2.0) + clearance_meters + (requested_width_meters / 2.0);
        blocked.push_back({
            clamp(opening.offset_meters - half_width, 0.0, wall_length),
            clamp(opening.offset_meters + half_width, 0.0, wall_length),
        });
    }

    std::sort(blocked.begin(), blocked.end(), [](const auto& left, const auto& right) {
        if (std::abs(left.first - right.first) > 1.0e-9) {
            return left.first < right.first;
        }
        return left.second < right.second;
    });

    std::vector<std::pair<double, double>> merged;
    for (const auto& interval : blocked) {
        if (merged.empty() || interval.first > merged.back().second + 1.0e-9) {
            merged.push_back(interval);
            continue;
        }
        merged.back().second = std::max(merged.back().second, interval.second);
    }

    std::vector<WallFreeIntervalDTO> free_intervals;
    double cursor = 0.0;
    for (const auto& interval : merged) {
        if (interval.first > cursor + 1.0e-9) {
            free_intervals.push_back(WallFreeIntervalDTO{
                .start_offset_meters = cursor,
                .end_offset_meters = interval.first,
                .length_meters = interval_length(cursor, interval.first),
            });
        }
        cursor = std::max(cursor, interval.second);
    }
    if (cursor < wall_length - 1.0e-9) {
        free_intervals.push_back(WallFreeIntervalDTO{
            .start_offset_meters = cursor,
            .end_offset_meters = wall_length,
            .length_meters = interval_length(cursor, wall_length),
        });
    }

    free_intervals.erase(std::remove_if(free_intervals.begin(), free_intervals.end(), [](const auto& interval) {
        return interval.length_meters <= 1.0e-9;
    }), free_intervals.end());
    return free_intervals;
}

template <typename SessionImpl>
ApiVoidResult recompute_impl(SessionImpl& impl, ComputeMode mode) {
    try {
        if (mode == ComputeMode::FinalExact) {
            impl.freshness = FreshnessSummaryDTO{
                .room_metrics = FreshnessState::Computing,
                .geometry = FreshnessState::Computing,
                .schedules = FreshnessState::Computing,
                .material_takeoff = FreshnessState::Computing,
                .validation_report = FreshnessState::Computing,
                .exports = FreshnessState::Computing,
            };
            impl.document().recompute_all_rooms();
            impl.document().regenerate_dirty_geometry();
            (void)impl.document().dependency_graph();
            impl.cached_rooms = build_room_cache(impl.document());
            impl.cached_wall_schedule = build_wall_schedule_cache(impl.document());
            impl.cached_opening_schedule = build_opening_schedule_cache(impl.document());
            impl.cached_room_schedule = build_room_schedule_cache(impl.document());
            impl.cached_material_takeoff = build_material_takeoff_cache(impl.document());
            impl.cached_validation = to_validation_report(impl.document().validate_document());
            impl.freshness = FreshnessSummaryDTO{
                .room_metrics = FreshnessState::Clean,
                .geometry = FreshnessState::Clean,
                .schedules = FreshnessState::Clean,
                .material_takeoff = FreshnessState::Clean,
                .validation_report = FreshnessState::Clean,
                .exports = FreshnessState::Clean,
            };
            rebuild_spatial_index_impl(impl);
            return success_void();
        }

        impl.freshness.room_metrics = FreshnessState::Computing;
        impl.freshness.geometry = FreshnessState::Computing;
        impl.document().detect_rooms();
        impl.document().regenerate_dirty_geometry();
        impl.cached_rooms = build_room_cache(impl.document());
        impl.freshness.room_metrics = FreshnessState::Clean;
        impl.freshness.geometry = FreshnessState::Clean;

        if (mode == ComputeMode::Normal && impl.performance_profile != PerformanceProfile::BatterySaver) {
            impl.freshness.schedules = FreshnessState::Computing;
            impl.freshness.material_takeoff = FreshnessState::Computing;
            impl.cached_wall_schedule = build_wall_schedule_cache(impl.document());
            impl.cached_opening_schedule = build_opening_schedule_cache(impl.document());
            impl.cached_room_schedule = build_room_schedule_cache(impl.document());
            impl.cached_material_takeoff = build_material_takeoff_cache(impl.document());
            impl.freshness.schedules = FreshnessState::Clean;
            impl.freshness.material_takeoff = FreshnessState::Clean;
        }

        if (mode == ComputeMode::InteractivePreview) {
            impl.freshness.schedules = dirty_or_stale(impl.freshness.schedules);
            impl.freshness.material_takeoff = dirty_or_stale(impl.freshness.material_takeoff);
            impl.freshness.validation_report = dirty_or_stale(impl.freshness.validation_report);
        }
        impl.spatial_index_dirty = true;

        return success_void();
    } catch (const std::exception& error) {
        impl.freshness.room_metrics = FreshnessState::Failed;
        impl.freshness.geometry = FreshnessState::Failed;
        return error_void(status_from_exception(error), error.what());
    }
}

template <typename SessionImpl>
RepairReportDTO repair_project_impl(SessionImpl& impl, RepairOptionsDTO options) {
    RepairReportDTO report;
    auto& document = impl.document();

    std::vector<ElementId> elements_to_delete;
    const auto queue_delete = [&](ElementId element_id, std::string message) {
        if (std::find(elements_to_delete.begin(), elements_to_delete.end(), element_id) == elements_to_delete.end()) {
            elements_to_delete.push_back(element_id);
        }
        ++report.repaired_count;
        report.messages.push_back(std::move(message));
    };
    for (const auto& element : document.elements()) {
        if (const auto* door = element.door()) {
            const auto* host = document.find_ptr(door->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                if (options.remove_orphan_openings) {
                    queue_delete(element.id(), "removed orphan door");
                } else {
                    ++report.warning_count;
                    report.messages.push_back("orphan door left in place");
                }
                continue;
            }
            if (options.fix_opening_levels_from_host) {
                auto* mutable_element = document.find_ptr(element.id());
                auto* mutable_door = mutable_element == nullptr ? nullptr : mutable_element->door();
                if (mutable_door != nullptr && mutable_door->level_id != host->wall()->level_id) {
                    mutable_door->level_id = host->wall()->level_id;
                    mutable_element->touch();
                    ++report.repaired_count;
                    report.messages.push_back("fixed door level_id from host wall");
                }
            }
        } else if (const auto* window = element.window()) {
            const auto* host = document.find_ptr(window->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                if (options.remove_orphan_openings) {
                    queue_delete(element.id(), "removed orphan window");
                } else {
                    ++report.warning_count;
                    report.messages.push_back("orphan window left in place");
                }
                continue;
            }
            if (options.fix_opening_levels_from_host) {
                auto* mutable_element = document.find_ptr(element.id());
                auto* mutable_window = mutable_element == nullptr ? nullptr : mutable_element->window();
                if (mutable_window != nullptr && mutable_window->level_id != host->wall()->level_id) {
                    mutable_window->level_id = host->wall()->level_id;
                    mutable_element->touch();
                    ++report.repaired_count;
                    report.messages.push_back("fixed window level_id from host wall");
                }
            }
        } else if (const auto* wall = element.wall()) {
            auto* mutable_element = document.find_ptr(element.id());
            auto* mutable_wall = mutable_element == nullptr ? nullptr : mutable_element->wall();
            if (mutable_wall != nullptr && !mutable_wall->openings.empty()) {
                std::vector<tbe::core::HostedOpening> filtered;
                filtered.reserve(mutable_wall->openings.size());
                bool removed_orphans = false;
                for (const auto& opening : mutable_wall->openings) {
                    const auto* opening_element = document.find_ptr(opening.element_id);
                    const bool opening_matches_type =
                        (opening.kind == tbe::core::OpeningKind::Door && opening_element != nullptr && opening_element->door() != nullptr) ||
                        (opening.kind == tbe::core::OpeningKind::Window && opening_element != nullptr && opening_element->window() != nullptr);
                    if (!opening_matches_type) {
                        removed_orphans = true;
                        if (options.remove_orphan_openings) {
                            ++report.repaired_count;
                            report.messages.push_back("removed orphan wall opening");
                            continue;
                        }
                        ++report.warning_count;
                        report.messages.push_back("orphan wall opening left in place");
                    }
                    filtered.push_back(opening);
                }
                if (removed_orphans && options.remove_orphan_openings) {
                    mutable_wall->openings = std::move(filtered);
                    mutable_element->touch();
                }
            }
        } else if (const auto* room = element.room()) {
            auto invalid_boundary = false;
            for (const auto boundary_id : room->boundary_wall_ids) {
                const auto* boundary = document.find_ptr(boundary_id);
                if (boundary == nullptr || boundary->wall() == nullptr) {
                    invalid_boundary = true;
                    break;
                }
            }
            if (invalid_boundary && options.remove_invalid_rooms) {
                queue_delete(element.id(), "removed room with invalid boundary walls");
            }
        } else if (const auto* slab = element.slab()) {
            const auto missing_material = slab->material_id != 0 && document.get_material(slab->material_id) == nullptr;
            const auto missing_assembly = slab->assembly_id != 0 && document.get_layered_assembly(slab->assembly_id) == nullptr;
            if (slab->thickness_meters <= 0.0 || slab->boundary_polygon.size() < 3 || slab->area_square_meters <= 0.0 || missing_material || missing_assembly) {
                queue_delete(element.id(), "removed invalid slab");
            }
        } else if (const auto* roof = element.roof()) {
            const auto missing_material = roof->material_id != 0 && document.get_material(roof->material_id) == nullptr;
            const auto missing_assembly = roof->assembly_id != 0 && document.get_layered_assembly(roof->assembly_id) == nullptr;
            if (roof->thickness_meters <= 0.0 || roof->boundary_polygon.size() < 3 || roof->area_square_meters <= 0.0 || missing_material || missing_assembly) {
                queue_delete(element.id(), "removed invalid roof");
            }
        } else if (const auto* column = element.column()) {
            const auto missing_material = column->material_id != 0 && document.get_material(column->material_id) == nullptr;
            if (column->width_meters <= 0.0 || column->depth_meters <= 0.0 || column->height_meters <= 0.0 || missing_material) {
                queue_delete(element.id(), "removed invalid column");
            }
        } else if (const auto* beam = element.beam()) {
            const auto missing_material = beam->material_id != 0 && document.get_material(beam->material_id) == nullptr;
            const auto dx = beam->end.x - beam->start.x;
            const auto dy = beam->end.y - beam->start.y;
            if (beam->width_meters <= 0.0 || beam->height_meters <= 0.0 || std::sqrt((dx * dx) + (dy * dy)) <= 1.0e-9 || missing_material) {
                queue_delete(element.id(), "removed invalid beam");
            }
        } else if (const auto* stair = element.stair()) {
            const auto missing_material = stair->material_id != 0 && document.get_material(stair->material_id) == nullptr;
            const auto invalid_levels = document.find_ptr(stair->base_level_id) == nullptr || document.find_ptr(stair->base_level_id)->level() == nullptr ||
                (stair->top_level_id != 0 && (document.find_ptr(stair->top_level_id) == nullptr || document.find_ptr(stair->top_level_id)->level() == nullptr));
            if (stair->width_meters <= 0.0 || stair->total_rise_meters <= 0.0 || stair->total_run_meters <= 0.0 ||
                stair->riser_count <= 0 || stair->tread_count <= 0 || missing_material || invalid_levels) {
                queue_delete(element.id(), "removed invalid stair");
            }
        }
    }

    for (const auto element_id : elements_to_delete) {
        if (document.find_ptr(element_id) != nullptr) {
            document.delete_element(element_id);
        }
    }

    if (options.remove_duplicate_joins) {
        for (const auto& element : document.elements()) {
            const auto* wall = element.wall();
            if (wall == nullptr) {
                continue;
            }
            auto* mutable_element = document.find_ptr(element.id());
            auto* mutable_wall = mutable_element == nullptr ? nullptr : mutable_element->wall();
            if (mutable_wall == nullptr) {
                continue;
            }
            std::set<std::tuple<ElementId, long long, long long>> seen;
            std::vector<tbe::core::WallJoin> filtered;
            filtered.reserve(mutable_wall->joins.size());
            for (const auto& join : mutable_wall->joins) {
                const auto key = std::make_tuple(
                    join.other_wall_id,
                    static_cast<long long>(std::llround(join.point.x * 1000000.0)),
                    static_cast<long long>(std::llround(join.point.y * 1000000.0))
                );
                if (seen.insert(key).second) {
                    filtered.push_back(join);
                }
            }
            if (filtered.size() != mutable_wall->joins.size()) {
                mutable_wall->joins = std::move(filtered);
                mutable_element->touch();
                ++report.repaired_count;
                report.messages.push_back("removed duplicate wall joins");
            }
        }
    }

    if (options.regenerate_room_metrics) {
        document.recompute_all_rooms();
        ++report.repaired_count;
        report.messages.push_back("recomputed room metrics");
    }
    if (options.regenerate_geometry) {
        document.regenerate_dirty_geometry();
        ++report.repaired_count;
        report.messages.push_back("regenerated dirty geometry");
    }

    (void)document.dependency_graph();
    return report;
}

template <typename SessionImpl, typename Fn>
ApiVoidResult apply_mutation(SessionImpl& impl, const std::string& name, Fn&& fn) {
    const auto before = impl.project.to_json();
    try {
        fn(impl.document());
        const auto after = impl.project.to_json();
        if (after != before) {
            impl.undo_stack.push_back(SessionTransaction{
                .name = name,
                .before_json = before,
                .after_json = after,
            });
            impl.redo_stack.clear();
            impl.mark_all_derived_dirty();
            if (impl.performance_profile == PerformanceProfile::Performance && impl.compute_mode != ComputeMode::InteractivePreview) {
                (void)recompute_impl(impl, ComputeMode::Normal);
            }
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

template <typename SessionImpl, typename T, typename Fn>
ApiResult<T> apply_mutation_with_value(SessionImpl& impl, const std::string& name, T& value, Fn&& fn) {
    const auto before = impl.project.to_json();
    try {
        fn(impl.document(), value);
        const auto after = impl.project.to_json();
        if (after != before) {
            impl.undo_stack.push_back(SessionTransaction{
                .name = name,
                .before_json = before,
                .after_json = after,
            });
            impl.redo_stack.clear();
            impl.mark_all_derived_dirty();
            if (impl.performance_profile == PerformanceProfile::Performance && impl.compute_mode != ComputeMode::InteractivePreview) {
                (void)recompute_impl(impl, ComputeMode::Normal);
            }
        }
        return success_result(std::move(value));
    } catch (const std::exception& error) {
        return error_result<T>(status_from_exception(error), error.what());
    }
}

template <typename T, typename Fn>
ApiResult<T> query_result(Fn&& fn) {
    try {
        return success_result(fn());
    } catch (const std::exception& error) {
        return error_result<T>(status_from_exception(error), error.what());
    }
}

ApiVoidResult query_void(const std::function<void()>& fn) {
    try {
        fn();
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

} // namespace

ApiVoidResult EngineSession::new_project(std::string project_name) {
    try {
        impl_->project = Project(std::move(project_name));
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_migration_report = MigrationReportDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::current_project() const {
    return success_result(std::string(impl_->project.name()));
}

ApiVoidResult EngineSession::clear_project() {
    try {
        const auto current_name = std::string(impl_->project.name());
        impl_->project = Project(current_name.empty() ? "API Project" : current_name);
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_migration_report = MigrationReportDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::load_project_json(std::string_view json) {
    return load_project_json_with_mode(json, LoadMode::Strict);
}

ApiVoidResult EngineSession::load_project_json_with_mode(std::string_view json, LoadMode mode) {
    try {
        std::string migrated_json;
        const auto detected_version = detect_schema_version_value(json);
        impl_->last_migration_report = migrate_json_to_current(json, migrated_json, detected_version, tbe::core::TBE_SCHEMA_VERSION);
        if (impl_->last_migration_report.error_count > 0) {
            return error_void(ApiStatus::InvalidArgument, impl_->last_migration_report.messages.front());
        }
        impl_->project = Project::from_json(migrated_json);
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        const auto validation = impl_->document().validate_document();
        if (mode == LoadMode::Repair) {
            impl_->last_repair_report = repair_project_impl(*impl_, RepairOptionsDTO{});
            impl_->clear_caches();
            impl_->mark_all_derived_dirty();
            rebuild_spatial_index_impl(*impl_);
            return success_void();
        }
        if (mode == LoadMode::Strict && validation.error_count() > 0) {
            return error_void(ApiStatus::ValidationError, "strict load rejected invalid project data");
        }
        if (mode == LoadMode::Tolerant && (validation.warning_count() > 0 || validation.error_count() > 0)) {
            ApiVoidResult result = success_void();
            result.message = "project loaded in tolerant mode with validation warnings";
            for (const auto& issue : validation.issues) {
                result.validation_issues.push_back(to_validation_issue(issue));
            }
            return result;
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<int> EngineSession::get_schema_version() const {
    return success_result(tbe::core::TBE_SCHEMA_VERSION);
}

ApiResult<int> EngineSession::detect_schema_version_from_json(std::string_view json) const {
    return success_result(detect_schema_version_value(json));
}

ApiResult<std::string> EngineSession::migrate_project_json(std::string_view json, int from_version, int to_version) const {
    std::string migrated_json;
    auto report = migrate_json_to_current(json, migrated_json, from_version, to_version);
    if (report.error_count > 0) {
        return error_result<std::string>(ApiStatus::InvalidArgument, report.messages.empty() ? "migration failed" : report.messages.front());
    }
    return success_result(std::move(migrated_json));
}

ApiResult<MigrationReportDTO> EngineSession::get_last_migration_report() const {
    return success_result(impl_->last_migration_report);
}

ApiResult<RepairReportDTO> EngineSession::get_last_repair_report() const {
    return success_result(impl_->last_repair_report);
}

ApiResult<RepairReportDTO> EngineSession::repair_current_project(RepairOptionsDTO options) {
    impl_->last_repair_report = repair_project_impl(*impl_, options);
    impl_->clear_caches();
    impl_->mark_all_derived_dirty();
    rebuild_spatial_index_impl(*impl_);
    return success_result(impl_->last_repair_report);
}

ApiVoidResult EngineSession::export_project_package(const std::string& path, PackageExportOptionsDTO options) const {
    namespace fs = std::filesystem;
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return error_void(recompute.status, recompute.message);
        }
        const fs::path root(path);
        fs::create_directories(root / "exports");
        fs::create_directories(root / "debug");
        {
            std::ofstream project_file(root / "project.json");
            project_file << impl_->project.to_json();
        }
        {
            std::ofstream metadata_file(root / "metadata.json");
            metadata_file << "{\"schema_version\":" << tbe::core::TBE_SCHEMA_VERSION
                          << ",\"engine_version\":\"" << tbe::core::TBE_ENGINE_VERSION
                          << "\",\"project_name\":\"" << impl_->project.name() << "\"}";
        }
        if (options.include_floorplan_svg) {
            impl_->document().export_floorplan_svg(root / "exports" / "floorplan.svg");
        }
        if (options.include_walls_obj) {
            impl_->document().export_mesh_obj(root / "exports" / "walls.obj");
        }
        if (options.include_debug_report_json) {
            impl_->document().export_debug_report_json(root / "debug" / "debug_report.json");
        }
        {
            std::ofstream render_scene_file(root / "exports" / "render_scene.json");
            render_scene_file << render_scene_to_json(build_render_scene(impl_->document()));
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::import_project_package(const std::string& path, LoadMode mode) {
    namespace fs = std::filesystem;
    try {
        const fs::path root(path);
        std::ifstream project_file(root / "project.json");
        if (!project_file) {
            return error_void(ApiStatus::NotFound, "project package is missing project.json");
        }
        std::ostringstream buffer;
        buffer << project_file.rdbuf();
        return load_project_json_with_mode(buffer.str(), mode);
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<RenderSceneDTO> EngineSession::get_render_scene() const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return error_result<RenderSceneDTO>(recompute.status, recompute.message);
        }
        return success_result(build_render_scene(impl_->document()));
    } catch (const std::exception& error) {
        return error_result<RenderSceneDTO>(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::export_render_scene_json(const std::string& path) const {
    namespace fs = std::filesystem;
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return error_void(recompute.status, recompute.message);
        }
        const fs::path output(path);
        if (!output.parent_path().empty()) {
            fs::create_directories(output.parent_path());
        }
        std::ofstream file(output);
        if (!file) {
            return error_void(ApiStatus::InternalError, "failed to open render scene export path");
        }
        file << render_scene_to_json(build_render_scene(impl_->document()));
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::save_project_json() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<std::string>(recompute.status, recompute.message);
    }
    return query_result<std::string>([&]() {
        return impl_->project.to_json();
    });
}

ApiResult<std::string> EngineSession::save_project_json_cached(bool allow_stale) const {
    if (!allow_stale) {
        return save_project_json();
    }
    ApiResult<std::string> result = query_result<std::string>([&]() {
        return impl_->project.to_json();
    });
    result.freshness = impl_->freshness.exports;
    if (impl_->freshness.exports != FreshnessState::Clean) {
        result.message = "project JSON may include stale derived metrics";
    }
    return result;
}

ApiResult<std::string> EngineSession::get_engine_version() const {
    return success_result(std::string(kEngineVersion));
}

ApiResult<std::string> EngineSession::get_core_version() const {
    return success_result(std::string(kCoreVersion));
}

ApiResult<std::string> EngineSession::get_api_version() const {
    return success_result(std::string(kApiVersion));
}

ApiVoidResult EngineSession::set_performance_profile(PerformanceProfile profile) {
    impl_->performance_profile = profile;
    return success_void();
}

ApiResult<PerformanceProfile> EngineSession::get_performance_profile() const {
    return success_result(impl_->performance_profile);
}

ApiVoidResult EngineSession::set_compute_mode(ComputeMode mode) {
    impl_->compute_mode = mode;
    return success_void();
}

ApiResult<ComputeMode> EngineSession::get_compute_mode() const {
    return success_result(impl_->compute_mode);
}

ApiResult<DirtySummaryDTO> EngineSession::get_dirty_summary() const {
    return success_result(build_dirty_summary(impl_->freshness));
}

ApiResult<FreshnessSummaryDTO> EngineSession::get_freshness_summary() const {
    return success_result(impl_->freshness);
}

ApiVoidResult EngineSession::recompute_dirty() {
    return recompute_impl(*impl_, impl_->compute_mode);
}

ApiVoidResult EngineSession::recompute_all_final() {
    return recompute_impl(*impl_, ComputeMode::FinalExact);
}

ApiVoidResult EngineSession::rebuild_spatial_index() {
    return query_void([&]() {
        ensure_spatial_index(*impl_);
    });
}

ApiResult<std::uint64_t> EngineSession::spatial_index_version() const {
    ensure_spatial_index(*impl_);
    return success_result(impl_->spatial_index_version);
}

ApiResult<SpatialIndexStatsDTO> EngineSession::spatial_index_stats() const {
    ensure_spatial_index(*impl_);
    std::size_t total_entries = 0;
    std::size_t total_buckets = 0;
    std::size_t total_bucket_occupancy = 0;
    std::size_t max_bucket_occupancy = 0;
    for (const auto& [_, level_index] : impl_->spatial_index_by_level) {
        total_entries += level_index.entries.size();
        total_buckets += level_index.buckets.size();
        for (const auto& [__, indices] : level_index.buckets) {
            total_bucket_occupancy += indices.size();
            max_bucket_occupancy = std::max(max_bucket_occupancy, indices.size());
        }
    }
    return success_result(SpatialIndexStatsDTO{
        .version = impl_->spatial_index_version,
        .element_bounds_count = total_entries,
        .bucket_count = total_buckets,
        .average_bucket_occupancy = total_buckets == 0 ? 0.0 : static_cast<double>(total_bucket_occupancy) / static_cast<double>(total_buckets),
        .max_bucket_occupancy = max_bucket_occupancy,
        .dirty = impl_->spatial_index_dirty,
    });
}

ApiResult<std::vector<ElementSummaryDTO>> EngineSession::query_rect(ElementIdDTO level_id, AABB2D bounds) const {
    ensure_spatial_index(*impl_);
    const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
    if (level_index == nullptr) {
        return error_result<std::vector<ElementSummaryDTO>>(ApiStatus::NotFound, "level spatial index not found");
    }

    std::vector<ElementSummaryDTO> result;
    for (const auto entry_index : query_level_indices(*level_index, bounds)) {
        const auto& entry = level_index->entries.at(entry_index);
        const auto* element = impl_->document().find_ptr(entry.element_id);
        result.push_back(ElementSummaryDTO{
            .id = to_id(entry.element_id),
            .kind = entry.kind,
            .name = element == nullptr ? std::string{} : std::string(element->name()),
        });
    }
    return success_result(std::move(result));
}

ApiResult<ElementIdDTO> EngineSession::create_level(std::string name, double elevation_meters, double default_wall_height_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_level", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_level(std::move(name), elevation_meters, default_wall_height_meters));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_wall(std::string name, Vec2 start, Vec2 end, double thickness_meters, double height_meters, std::uint64_t level_id) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_wall", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_wall(std::move(name), Line2{.start = to_point(start), .end = to_point(end)}, thickness_meters, height_meters, level_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_door(std::string name, std::uint64_t host_wall_id, double offset_meters, double width_meters, double height_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_door", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_door(std::move(name), host_wall_id, offset_meters, width_meters, height_meters));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_window(
    std::string name,
    std::uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_window", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_window(std::move(name), host_wall_id, offset_meters, width_meters, height_meters, sill_height_meters));
    });
}

ApiResult<std::vector<RoomDTO>> EngineSession::detect_rooms() {
    std::vector<RoomDTO> rooms;
    auto result = apply_mutation_with_value(*impl_, "detect_rooms", rooms, [&](Document& document, std::vector<RoomDTO>& out) {
        const auto room_ids = document.detect_rooms();
        out.reserve(room_ids.size());
        for (const auto room_id : room_ids) {
            const auto* element = document.find_ptr(room_id);
            if (element != nullptr && element->room() != nullptr) {
                out.push_back(to_room_dto(*element));
            }
        }
    });
    if (result.ok() && result.value.has_value()) {
        impl_->cached_rooms = *result.value;
        impl_->freshness.room_metrics = FreshnessState::Clean;
        impl_->freshness.geometry = dirty_or_stale(impl_->freshness.geometry);
        impl_->freshness.schedules = dirty_or_stale(impl_->freshness.schedules);
        result.freshness = FreshnessState::Clean;
    }
    return result;
}

ApiVoidResult EngineSession::auto_join_walls() {
    return apply_mutation(*impl_, "auto_join_walls", [&](Document& document) {
        document.auto_join_walls();
    });
}

ApiVoidResult EngineSession::set_wall_axis(std::uint64_t wall_id, Vec2 start, Vec2 end) {
    return apply_mutation(*impl_, "set_wall_axis", [&](Document& document) {
        document.set_wall_axis(wall_id, Line2{.start = to_point(start), .end = to_point(end)});
    });
}

ApiVoidResult EngineSession::update_wall_properties(std::uint64_t wall_id, double thickness_meters, double height_meters, std::uint64_t wall_type_id) {
    return apply_mutation(*impl_, "update_wall_properties", [&](Document& document) {
        document.set_wall_properties(wall_id, thickness_meters, height_meters, wall_type_id);
    });
}

ApiResult<ElementIdDTO> EngineSession::split_wall(std::uint64_t wall_id, double offset_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "split_wall", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.split_wall(wall_id, offset_meters));
    });
}

ApiVoidResult EngineSession::delete_element(std::uint64_t element_id) {
    return apply_mutation(*impl_, "delete_element", [&](Document& document) {
        document.delete_element(element_id);
    });
}

ApiVoidResult EngineSession::move_hosted_opening(std::uint64_t opening_id, double offset_meters) {
    return apply_mutation(*impl_, "move_hosted_opening", [&](Document& document) {
        document.move_hosted_opening(opening_id, offset_meters);
    });
}

ApiVoidResult EngineSession::resize_door(std::uint64_t door_id, double width_meters, double height_meters) {
    return apply_mutation(*impl_, "resize_door", [&](Document& document) {
        document.resize_door(door_id, width_meters, height_meters);
    });
}

ApiVoidResult EngineSession::resize_window(std::uint64_t window_id, double width_meters, double height_meters, double sill_height_meters) {
    return apply_mutation(*impl_, "resize_window", [&](Document& document) {
        document.resize_window(window_id, width_meters, height_meters, sill_height_meters);
    });
}

ApiResult<ElementIdDTO> EngineSession::create_floor_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_floor_system_for_room", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_floor_system_for_room(room_id, assembly_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_ceiling_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id, double height_offset_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_ceiling_system_for_room", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_ceiling_system_for_room(room_id, assembly_id, height_offset_meters));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_roof(
    std::uint64_t level_id,
    std::vector<Vec2> boundary_polygon,
    ApiRoofType roof_type,
    double thickness_meters,
    std::uint64_t material_id,
    std::uint64_t assembly_id,
    std::optional<double> slope_degrees,
    std::optional<double> overhang_meters
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_roof", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_roof(
            level_id,
            to_point_list(boundary_polygon),
            to_core_roof_type(roof_type),
            thickness_meters,
            material_id,
            assembly_id,
            slope_degrees,
            overhang_meters
        ));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_column(
    std::uint64_t level_id,
    Vec2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_column", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_column(level_id, to_point(position), width_meters, depth_meters, height_meters, material_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_beam(
    std::uint64_t level_id,
    Vec2 start,
    Vec2 end,
    double width_meters,
    double height_meters,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_beam", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_beam(level_id, to_point(start), to_point(end), width_meters, height_meters, material_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_stair(
    std::uint64_t base_level_id,
    std::uint64_t top_level_id,
    Vec2 start,
    Vec2 direction,
    double width_meters,
    double total_rise_meters,
    double total_run_meters,
    int riser_count,
    int tread_count,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_stair", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_stair(
            base_level_id,
            top_level_id,
            to_point(start),
            to_point(direction),
            width_meters,
            total_rise_meters,
            total_run_meters,
            riser_count,
            tread_count,
            material_id
        ));
    });
}

ApiVoidResult EngineSession::undo() {
    if (impl_->undo_stack.empty()) {
        return error_void(ApiStatus::NotFound, "no API undo transaction available");
    }
    try {
        auto transaction = impl_->undo_stack.back();
        impl_->undo_stack.pop_back();
        impl_->project = Project::from_json(transaction.before_json);
        impl_->redo_stack.push_back(std::move(transaction));
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::redo() {
    if (impl_->redo_stack.empty()) {
        return error_void(ApiStatus::NotFound, "no API redo transaction available");
    }
    try {
        auto transaction = impl_->redo_stack.back();
        impl_->redo_stack.pop_back();
        impl_->project = Project::from_json(transaction.after_json);
        impl_->undo_stack.push_back(std::move(transaction));
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::vector<ElementSummaryDTO>> EngineSession::list_elements() const {
    return query_result<std::vector<ElementSummaryDTO>>([&]() {
        std::vector<ElementSummaryDTO> rows;
        rows.reserve(impl_->document().elements().size());
        for (const auto& element : impl_->document().elements()) {
            rows.push_back(to_element_summary(element));
        }
        return rows;
    });
}

ApiResult<ElementSummaryDTO> EngineSession::get_element_summary(std::uint64_t element_id) const {
    return query_result<ElementSummaryDTO>([&]() {
        const auto* element = impl_->document().find_ptr(element_id);
        if (element == nullptr) {
            throw std::invalid_argument("element does not exist");
        }
        return to_element_summary(*element);
    });
}

ApiResult<WallDTO> EngineSession::get_wall(std::uint64_t wall_id) const {
    return query_result<WallDTO>([&]() {
        const auto* element = impl_->document().find_ptr(wall_id);
        if (element == nullptr || element->wall() == nullptr) {
            throw std::invalid_argument("wall does not exist");
        }
        const auto* wall = element->wall();
        return WallDTO{
            .id = to_id(element->id()),
            .name = std::string(element->name()),
            .level_id = to_id(wall->level_id),
            .start = to_vec2(wall->axis.start),
            .end = to_vec2(wall->axis.end),
            .thickness_meters = wall->thickness_meters,
            .height_meters = wall->height_meters,
        };
    });
}

ApiResult<std::vector<RoomDTO>> EngineSession::get_rooms() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<RoomDTO>>(recompute.status, recompute.message);
    }
    ApiResult<std::vector<RoomDTO>> result = success_result(impl_->cached_rooms.value_or(build_room_cache(impl_->document())));
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomDTO>> EngineSession::get_cached_rooms() const {
    ApiResult<std::vector<RoomDTO>> result;
    result.freshness = impl_->freshness.room_metrics;
    if (impl_->cached_rooms.has_value()) {
        result.value = *impl_->cached_rooms;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached room data available";
    return result;
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::get_wall_schedule() const {
    return const_cast<EngineSession*>(this)->generate_wall_schedule();
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::get_cached_wall_schedule() const {
    ApiResult<std::vector<WallScheduleDTO>> result;
    result.freshness = impl_->freshness.schedules;
    if (impl_->cached_wall_schedule.has_value()) {
        result.value = *impl_->cached_wall_schedule;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached wall schedule available";
    return result;
}

ApiResult<std::vector<OpeningScheduleDTO>> EngineSession::get_opening_schedule() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<OpeningScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_opening_schedule = build_opening_schedule_cache(impl_->document());
    ApiResult<std::vector<OpeningScheduleDTO>> result = success_result(*impl_->cached_opening_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::get_room_schedule() const {
    return const_cast<EngineSession*>(this)->generate_room_schedule();
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::get_cached_room_schedule() const {
    ApiResult<std::vector<RoomScheduleDTO>> result;
    result.freshness = impl_->freshness.schedules;
    if (impl_->cached_room_schedule.has_value()) {
        result.value = *impl_->cached_room_schedule;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached room schedule available";
    return result;
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::get_material_takeoff_summary() const {
    return const_cast<EngineSession*>(this)->generate_material_takeoff_summary();
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::get_cached_material_takeoff_summary() const {
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> result;
    result.freshness = impl_->freshness.material_takeoff;
    if (impl_->cached_material_takeoff.has_value()) {
        result.value = *impl_->cached_material_takeoff;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached material takeoff available";
    return result;
}

ApiResult<ValidationReportDTO> EngineSession::get_validation_report() const {
    return const_cast<EngineSession*>(this)->generate_validation_report();
}

ApiResult<ValidationReportDTO> EngineSession::get_cached_validation_report() const {
    ApiResult<ValidationReportDTO> result;
    result.freshness = impl_->freshness.validation_report;
    if (impl_->cached_validation.has_value()) {
        result.value = *impl_->cached_validation;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached validation report available";
    return result;
}

ApiResult<DependencyGraphSummaryDTO> EngineSession::get_dependency_graph_summary() const {
    return query_result<DependencyGraphSummaryDTO>([&]() {
        const auto& graph = impl_->document().dependency_graph();
        return DependencyGraphSummaryDTO{
            .version = impl_->document().dependency_graph_version(),
            .rooms_by_wall_entries = graph.rooms_by_wall.size(),
            .openings_by_wall_entries = graph.openings_by_wall.size(),
            .connected_walls_entries = graph.connected_walls_by_wall.size(),
            .geometry_dependency_entries = graph.geometry_by_element.size(),
        };
    });
}

ApiResult<ScheduleSummaryDTO> EngineSession::generate_schedules() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<ScheduleSummaryDTO>(recompute.status, recompute.message);
    }
    ApiResult<ScheduleSummaryDTO> result = success_result(ScheduleSummaryDTO{
        .wall_rows = impl_->document().generate_wall_schedule().size(),
        .opening_rows = impl_->document().generate_opening_schedule().size(),
        .room_rows = impl_->document().generate_room_schedule().size(),
        .slab_rows = impl_->document().generate_slab_schedule().size(),
        .roof_rows = impl_->document().generate_roof_schedule().size(),
        .column_rows = impl_->document().generate_column_schedule().size(),
        .beam_rows = impl_->document().generate_beam_schedule().size(),
        .stair_rows = impl_->document().generate_stair_schedule().size(),
        .floor_rows = impl_->document().generate_floor_finish_schedule().size(),
        .ceiling_rows = impl_->document().generate_ceiling_schedule().size(),
        .material_takeoff_rows = impl_->document().generate_material_takeoff().size(),
    });
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<HitTestCandidateDTO>> EngineSession::hit_test_point(HitTestPoint query) const {
    ensure_spatial_index(*impl_);
    return query_result<std::vector<HitTestCandidateDTO>>([&]() {
        std::vector<HitTestCandidateDTO> candidates;
        const auto* level_index = find_level_spatial_index(*impl_, query.level_id.value);
        if (level_index == nullptr) {
            return candidates;
        }
        const auto point = to_point(query.point);
        const auto query_bounds = AABB2D{
            .min_x = point.x - query.tolerance_meters,
            .min_y = point.y - query.tolerance_meters,
            .max_x = point.x + query.tolerance_meters,
            .max_y = point.y + query.tolerance_meters,
        };
        for (const auto entry_index : query_level_indices(*level_index, query_bounds)) {
            const auto& entry = level_index->entries[entry_index];

            auto push_candidate = [&](HitKind hit_kind, double distance_meters) {
                candidates.push_back(HitTestCandidateDTO{
                    .element_id = to_id(entry.element_id),
                    .element_kind = entry.kind,
                    .hit_kind = hit_kind,
                    .distance_meters = distance_meters,
                    .priority = hit_priority(hit_kind),
                });
            };

            switch (entry.kind) {
            case ApiElementKind::Wall: {
                const auto axis_distance = distance_point_to_segment(point, entry.axis);
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::WallBody, axis_distance);
                }
                if (axis_distance <= query.tolerance_meters) {
                    push_candidate(HitKind::WallAxis, axis_distance);
                }
                break;
            }
            case ApiElementKind::Door:
            case ApiElementKind::Window:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Opening, 0.0);
                }
                break;
            case ApiElementKind::Room:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::RoomInterior, 0.0);
                }
                break;
            case ApiElementKind::Slab:
            case ApiElementKind::FloorSystem:
            case ApiElementKind::CeilingSystem:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(entry.preferred_hit_kind, 0.0);
                }
                break;
            case ApiElementKind::Roof:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Roof, 0.0);
                }
                break;
            case ApiElementKind::Column:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Column, 0.0);
                }
                break;
            case ApiElementKind::Beam: {
                const auto beam_distance = distance_point_to_segment(point, entry.axis);
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Beam, beam_distance);
                }
                break;
            }
            case ApiElementKind::Stair:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Stair, 0.0);
                }
                break;
            default:
                break;
            }
        }

        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
            if (left.priority != right.priority) {
                return left.priority < right.priority;
            }
            if (std::abs(left.distance_meters - right.distance_meters) > 1.0e-9) {
                return left.distance_meters < right.distance_meters;
            }
            return left.element_id.value < right.element_id.value;
        });
        return candidates;
    });
}

ApiResult<std::vector<SnapCandidateDTO>> EngineSession::get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap) const {
    return get_snap_candidates(level_id, point, tolerance_meters, SnapOptionsDTO{.enable_grid = include_grid_snap});
}

ApiResult<std::vector<SnapCandidateDTO>> EngineSession::get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const {
    ensure_spatial_index(*impl_);
    return query_result<std::vector<SnapCandidateDTO>>([&]() {
        std::vector<SnapCandidateDTO> candidates;
        const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
        if (level_index == nullptr) {
            return candidates;
        }
        const auto query_point = to_point(point);
        const auto query_bounds = AABB2D{
            .min_x = query_point.x - tolerance_meters,
            .min_y = query_point.y - tolerance_meters,
            .max_x = query_point.x + tolerance_meters,
            .max_y = query_point.y + tolerance_meters,
        };
        auto push_snap = [&](Point2 candidate_point, SnapType type, std::optional<ElementId> source) {
            const auto dist = distance(query_point, candidate_point);
            if (dist > tolerance_meters && type != SnapType::Grid) {
                return;
            }
            candidates.push_back(SnapCandidateDTO{
                .point = to_vec2(candidate_point),
                .type = type,
                .source_element_id = source.has_value() ? std::optional<ElementIdDTO>{to_id(*source)} : std::nullopt,
                .distance_meters = dist,
                .priority = snap_priority(type),
            });
        };

        for (const auto entry_index : query_level_indices(*level_index, expanded_bounds(query_bounds, tolerance_meters))) {
            const auto& entry = level_index->entries[entry_index];
            if (entry.kind == ApiElementKind::Wall || entry.kind == ApiElementKind::Beam) {
                if (options.enable_endpoints) {
                    push_snap(entry.axis.start, SnapType::Endpoint, entry.element_id);
                    push_snap(entry.axis.end, SnapType::Endpoint, entry.element_id);
                }
                if (options.enable_midpoints) {
                    push_snap(Point2{
                        .x = (entry.axis.start.x + entry.axis.end.x) / 2.0,
                        .y = (entry.axis.start.y + entry.axis.end.y) / 2.0,
                    }, SnapType::Midpoint, entry.element_id);
                }
                Point2 projected{};
                const auto axis_distance = distance_point_to_segment(query_point, entry.axis, nullptr, &projected);
                if (axis_distance <= tolerance_meters) {
                    if (options.enable_orthogonal_projection) {
                        push_snap(projected, SnapType::OrthogonalProjection, entry.element_id);
                    }
                    if (options.enable_wall_axis) {
                        push_snap(projected, SnapType::WallAxis, entry.element_id);
                    }
                }
            }
            if (options.enable_room_corners &&
                (entry.kind == ApiElementKind::Room || entry.kind == ApiElementKind::Slab || entry.kind == ApiElementKind::FloorSystem ||
                    entry.kind == ApiElementKind::CeilingSystem || entry.kind == ApiElementKind::Roof || entry.kind == ApiElementKind::Stair) &&
                !entry.polygon.empty()) {
                for (const auto& polygon_point : entry.polygon) {
                    push_snap(polygon_point, SnapType::RoomCorner, entry.element_id);
                }
            }
        }

        if (options.enable_intersections) {
            for (const auto& first : level_index->entries) {
            if (!(first.kind == ApiElementKind::Wall || first.kind == ApiElementKind::Beam)) {
                continue;
            }
                for (const auto& second : level_index->entries) {
                if (first.element_id >= second.element_id || !(second.kind == ApiElementKind::Wall || second.kind == ApiElementKind::Beam)) {
                    continue;
                }
                const auto denominator = ((first.axis.start.x - first.axis.end.x) * (second.axis.start.y - second.axis.end.y)) -
                    ((first.axis.start.y - first.axis.end.y) * (second.axis.start.x - second.axis.end.x));
                if (near_zero(denominator)) {
                    continue;
                }
                const auto x1 = first.axis.start.x;
                const auto y1 = first.axis.start.y;
                const auto x2 = first.axis.end.x;
                const auto y2 = first.axis.end.y;
                const auto x3 = second.axis.start.x;
                const auto y3 = second.axis.start.y;
                const auto x4 = second.axis.end.x;
                const auto y4 = second.axis.end.y;
                const auto px = (((x1 * y2) - (y1 * x2)) * (x3 - x4) - (x1 - x2) * ((x3 * y4) - (y3 * x4))) / denominator;
                const auto py = (((x1 * y2) - (y1 * x2)) * (y3 - y4) - (y1 - y2) * ((x3 * y4) - (y3 * x4))) / denominator;
                push_snap(Point2{.x = px, .y = py}, SnapType::WallIntersection, first.element_id);
            }
        }
        }

        if (options.enable_grid) {
            const auto grid_size = options.grid_size_meters > 1.0e-9 ? options.grid_size_meters : 1.0;
            push_snap(Point2{
                .x = std::round(query_point.x / grid_size) * grid_size,
                .y = std::round(query_point.y / grid_size) * grid_size,
            }, SnapType::Grid, std::nullopt);
        }

        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
            if (left.priority != right.priority) {
                return left.priority < right.priority;
            }
            if (std::abs(left.distance_meters - right.distance_meters) > 1.0e-9) {
                return left.distance_meters < right.distance_meters;
            }
            return left.source_element_id.value_or(ElementIdDTO{}).value < right.source_element_id.value_or(ElementIdDTO{}).value;
        });
        return candidates;
    });
}

ApiResult<SnapCandidateDTO> EngineSession::best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap) const {
    return best_snap(level_id, point, tolerance_meters, SnapOptionsDTO{.enable_grid = include_grid_snap});
}

ApiResult<SnapCandidateDTO> EngineSession::best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const {
    const auto candidates = get_snap_candidates(level_id, point, tolerance_meters, options);
    if (!candidates.ok()) {
        return error_result<SnapCandidateDTO>(candidates.status, candidates.message);
    }
    if (!candidates.value.has_value() || candidates.value->empty()) {
        return error_result<SnapCandidateDTO>(ApiStatus::NotFound, "no snap candidate available");
    }
    auto result = success_result(candidates.value->front());
    result.freshness = candidates.freshness;
    return result;
}

ApiResult<std::vector<WallFreeIntervalDTO>> EngineSession::compute_wall_free_intervals(std::uint64_t wall_id, double requested_width_meters, double clearance_meters) const {
    return query_result<std::vector<WallFreeIntervalDTO>>([&]() {
        const auto* wall_element = impl_->document().find_ptr(wall_id);
        if (wall_element == nullptr) {
            throw std::invalid_argument("wall does not exist");
        }
        return compute_wall_free_intervals_for_entry(*wall_element, requested_width_meters, clearance_meters);
    });
}

ApiResult<WallHostPlacementDTO> EngineSession::find_wall_host_at_point(
    ElementIdDTO level_id,
    Vec2 point,
    double tolerance_meters,
    double requested_width_meters,
    double clearance_meters
) const {
    ensure_spatial_index(*impl_);
    return query_result<WallHostPlacementDTO>([&]() {
        const auto query_point = to_point(point);
        const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
        if (level_index == nullptr) {
            throw std::invalid_argument("level has no spatial entries");
        }

        const SpatialEntry* best_wall = nullptr;
        double best_distance = tolerance_meters;
        double best_param = 0.0;
        const auto query_bounds = AABB2D{
            .min_x = query_point.x - tolerance_meters,
            .min_y = query_point.y - tolerance_meters,
            .max_x = query_point.x + tolerance_meters,
            .max_y = query_point.y + tolerance_meters,
        };
        for (const auto entry_index : query_level_indices(*level_index, expanded_bounds(query_bounds, tolerance_meters))) {
            const auto& entry = level_index->entries[entry_index];
            if (entry.kind != ApiElementKind::Wall) {
                continue;
            }
            double param = 0.0;
            const auto axis_distance = distance_point_to_segment(query_point, entry.axis, &param, nullptr);
            if (axis_distance <= best_distance) {
                best_distance = axis_distance;
                best_param = param;
                best_wall = &entry;
            }
        }
        if (best_wall == nullptr) {
            throw std::invalid_argument("no wall host found at point");
        }

        const auto* wall_element = impl_->document().find_ptr(best_wall->element_id);
        const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
        if (wall == nullptr) {
            throw std::invalid_argument("wall host entry is invalid");
        }

        const auto length_value = line_length(best_wall->axis);
        const auto requested_offset = best_param * length_value;
        const auto direction = length_value <= 1.0e-12 ? Point2{} : Point2{.x = (best_wall->axis.end.x - best_wall->axis.start.x) / length_value, .y = (best_wall->axis.end.y - best_wall->axis.start.y) / length_value};
        const auto cross = ((query_point.x - best_wall->axis.start.x) * direction.y) - ((query_point.y - best_wall->axis.start.y) * direction.x);
        const auto free_intervals = compute_wall_free_intervals_for_entry(*wall_element, requested_width_meters, clearance_meters);
        WallHostPlacementDTO result{
            .wall_id = to_id(best_wall->element_id),
            .requested_offset_meters = requested_offset,
            .wall_local_offset_meters = requested_offset,
            .adjusted_valid_offset_meters = requested_offset,
            .side = cross >= 0.0 ? "left" : "right",
            .valid = false,
            .free_intervals = free_intervals,
        };

        for (const auto& interval : free_intervals) {
            if (requested_offset >= interval.start_offset_meters - 1.0e-9 && requested_offset <= interval.end_offset_meters + 1.0e-9) {
                result.valid = true;
                result.adjusted_valid_offset_meters = clamp(requested_offset, interval.start_offset_meters, interval.end_offset_meters);
                break;
            }
        }

        if (!result.valid && !free_intervals.empty()) {
            double best_adjusted = free_intervals.front().start_offset_meters;
            double best_delta = std::abs(best_adjusted - requested_offset);
            for (const auto& interval : free_intervals) {
                const auto candidate = clamp(requested_offset, interval.start_offset_meters, interval.end_offset_meters);
                const auto delta = std::abs(candidate - requested_offset);
                if (delta < best_delta) {
                    best_delta = delta;
                    best_adjusted = candidate;
                }
            }
            result.adjusted_valid_offset_meters = best_adjusted;
            result.warnings.push_back("requested offset adjusted to nearest valid interval");
        }

        for (const auto& opening : wall->openings) {
            if (std::abs(opening.offset_meters - requested_offset) <= std::max(tolerance_meters, clearance_meters)) {
                result.warnings.push_back("near existing opening");
            }
        }
        if (free_intervals.empty()) {
            result.warnings.push_back("no valid wall placement interval available");
        }
        return result;
    });
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::generate_wall_schedule() {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<WallScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_wall_schedule = build_wall_schedule_cache(impl_->document());
    impl_->freshness.schedules = FreshnessState::Clean;
    ApiResult<std::vector<WallScheduleDTO>> result = success_result(*impl_->cached_wall_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::generate_room_schedule() {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<RoomScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_room_schedule = build_room_schedule_cache(impl_->document());
    impl_->freshness.schedules = FreshnessState::Clean;
    ApiResult<std::vector<RoomScheduleDTO>> result = success_result(*impl_->cached_room_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::generate_material_takeoff_summary() {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<std::vector<MaterialTakeoffSummaryDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_material_takeoff = build_material_takeoff_cache(impl_->document());
    impl_->freshness.material_takeoff = FreshnessState::Clean;
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> result = success_result(*impl_->cached_material_takeoff);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<ValidationReportDTO> EngineSession::generate_validation_report() {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<ValidationReportDTO>(recompute.status, recompute.message);
    }
    impl_->cached_validation = to_validation_report(impl_->document().validate_document());
    impl_->freshness.validation_report = FreshnessState::Clean;
    ApiResult<ValidationReportDTO> result = success_result(*impl_->cached_validation);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiVoidResult EngineSession::export_svg(const std::string& path) const {
    return const_cast<EngineSession*>(this)->export_svg_cached(path, false);
}

ApiVoidResult EngineSession::export_svg_cached(const std::string& path, bool allow_stale) const {
    if (!allow_stale) {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return recompute;
        }
    }
    auto result = query_void([&]() {
        impl_->document().export_floorplan_svg(path);
    });
    result.freshness = allow_stale ? impl_->freshness.exports : FreshnessState::Clean;
    if (result.ok()) {
        impl_->freshness.exports = FreshnessState::Clean;
    }
    return result;
}

ApiVoidResult EngineSession::export_obj(const std::string& path) const {
    return const_cast<EngineSession*>(this)->export_obj_cached(path, false);
}

ApiVoidResult EngineSession::export_obj_cached(const std::string& path, bool allow_stale) const {
    if (!allow_stale) {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return recompute;
        }
    }
    auto result = query_void([&]() {
        impl_->document().export_mesh_obj(path);
    });
    result.freshness = allow_stale ? impl_->freshness.exports : FreshnessState::Clean;
    if (result.ok()) {
        impl_->freshness.exports = FreshnessState::Clean;
    }
    return result;
}

ApiResult<std::unique_ptr<EngineSession>> create_session(std::string project_name) {
    try {
        return success_result(std::make_unique<EngineSession>(std::move(project_name)));
    } catch (const std::exception& error) {
        return error_result<std::unique_ptr<EngineSession>>(status_from_exception(error), error.what());
    }
}

} // namespace tbe::api
