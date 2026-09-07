#include "tbe/core/IfcExchange.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <map>
#include <optional>
#include <sstream>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace tbe::core {
namespace {

struct StepEntity {
    int id{};
    std::string type{};
    std::vector<std::string> arguments{};
};

struct Transform3 {
    std::array<std::array<double, 3>, 3> basis{{
        {{1.0, 0.0, 0.0}},
        {{0.0, 1.0, 0.0}},
        {{0.0, 0.0, 1.0}},
    }};
    Point3 origin{};
};

struct Bounds3 {
    Point3 minimum{
        std::numeric_limits<double>::max(),
        std::numeric_limits<double>::max(),
        std::numeric_limits<double>::max(),
    };
    Point3 maximum{
        std::numeric_limits<double>::lowest(),
        std::numeric_limits<double>::lowest(),
        std::numeric_limits<double>::lowest(),
    };
    bool valid{};
};

std::string trim(std::string value) {
    const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char ch) {
        return std::isspace(ch) != 0;
    });
    const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char ch) {
        return std::isspace(ch) != 0;
    }).base();
    if (first >= last) return {};
    return std::string(first, last);
}

std::vector<std::string> split_step_arguments(std::string_view value) {
    std::vector<std::string> arguments;
    std::size_t start = 0;
    int depth = 0;
    bool quoted = false;
    for (std::size_t index = 0; index < value.size(); ++index) {
        const auto ch = value[index];
        if (ch == '\'') {
            if (index + 1 < value.size() && value[index + 1] == '\'') {
                ++index;
            } else {
                quoted = !quoted;
            }
        } else if (!quoted && ch == '(') {
            ++depth;
        } else if (!quoted && ch == ')') {
            --depth;
        } else if (!quoted && depth == 0 && ch == ',') {
            arguments.push_back(trim(std::string(value.substr(start, index - start))));
            start = index + 1;
        }
    }
    arguments.push_back(trim(std::string(value.substr(start))));
    return arguments;
}

std::vector<StepEntity> parse_step_entities(std::string_view contents) {
    std::vector<StepEntity> entities;
    std::size_t cursor = 0;
    while (cursor < contents.size()) {
        const auto hash = contents.find('#', cursor);
        if (hash == std::string_view::npos) break;
        const auto equals = contents.find('=', hash + 1);
        if (equals == std::string_view::npos) break;
        const auto open = contents.find('(', equals + 1);
        if (open == std::string_view::npos) break;
        const auto id_text = trim(std::string(contents.substr(hash + 1, equals - hash - 1)));
        char* end = nullptr;
        const auto id = std::strtol(id_text.c_str(), &end, 10);
        if (end == id_text.c_str()) {
            cursor = open + 1;
            continue;
        }
        auto type = trim(std::string(contents.substr(equals + 1, open - equals - 1)));
        std::size_t close = open + 1;
        int depth = 1;
        bool quoted = false;
        for (; close < contents.size() && depth > 0; ++close) {
            const auto ch = contents[close];
            if (ch == '\'') {
                if (close + 1 < contents.size() && contents[close + 1] == '\'') {
                    ++close;
                } else {
                    quoted = !quoted;
                }
            } else if (!quoted && ch == '(') {
                ++depth;
            } else if (!quoted && ch == ')') {
                --depth;
            }
        }
        if (depth != 0) break;
        entities.push_back(StepEntity{
            .id = static_cast<int>(id),
            .type = std::move(type),
            .arguments = split_step_arguments(
                contents.substr(open + 1, close - open - 2)),
        });
        cursor = contents.find(';', close);
        if (cursor == std::string_view::npos) break;
        ++cursor;
    }
    return entities;
}

std::optional<int> step_reference(const std::string& value) {
    if (value.size() < 2 || value.front() != '#') return std::nullopt;
    char* end = nullptr;
    const auto result = std::strtol(value.c_str() + 1, &end, 10);
    if (end == value.c_str() + 1) return std::nullopt;
    return static_cast<int>(result);
}

std::vector<int> references_in(std::string_view value) {
    std::vector<int> result;
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (value[index] != '#') continue;
        const auto start = index + 1;
        auto end = start;
        while (end < value.size() &&
               std::isdigit(static_cast<unsigned char>(value[end])) != 0) {
            ++end;
        }
        if (end == start) continue;
        result.push_back(static_cast<int>(std::strtol(
            std::string(value.substr(start, end - start)).c_str(), nullptr, 10)));
        index = end - 1;
    }
    return result;
}

std::optional<double> step_number(std::string_view value) {
    if (value.empty() || value == "$" || value.front() == '.') return std::nullopt;
    const std::string copy(value);
    char* end = nullptr;
    const auto result = std::strtod(copy.c_str(), &end);
    if (end == copy.c_str() || !std::isfinite(result)) return std::nullopt;
    return result;
}

std::string step_string(const std::string& value) {
    if (value.size() < 2 || value.front() != '\'' || value.back() != '\'') return {};
    std::string result;
    result.reserve(value.size() - 2);
    for (std::size_t index = 1; index + 1 < value.size(); ++index) {
        if (value[index] == '\'' && index + 2 < value.size() && value[index + 1] == '\'') {
            ++index;
        }
        result.push_back(value[index]);
    }
    return result;
}

std::vector<std::vector<double>> nested_number_tuples(std::string_view value) {
    std::vector<std::vector<double>> tuples;
    int depth = 0;
    std::size_t tuple_start = std::string_view::npos;
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (value[index] == '(') {
            ++depth;
            if (depth == 2) tuple_start = index + 1;
        } else if (value[index] == ')') {
            if (depth == 2 && tuple_start != std::string_view::npos) {
                const auto parts = split_step_arguments(
                    value.substr(tuple_start, index - tuple_start));
                std::vector<double> tuple;
                tuple.reserve(parts.size());
                bool valid = true;
                for (const auto& part : parts) {
                    const auto number = step_number(part);
                    if (!number.has_value()) {
                        valid = false;
                        break;
                    }
                    tuple.push_back(*number);
                }
                if (valid && !tuple.empty()) tuples.push_back(std::move(tuple));
                tuple_start = std::string_view::npos;
            }
            --depth;
        }
    }
    return tuples;
}

std::vector<std::vector<int>> nested_integer_tuples(std::string_view value) {
    std::vector<std::vector<int>> result;
    for (const auto& tuple : nested_number_tuples(value)) {
        std::vector<int> converted;
        converted.reserve(tuple.size());
        bool valid = true;
        for (const auto number : tuple) {
            const auto rounded = std::llround(number);
            if (std::abs(number - static_cast<double>(rounded)) > 1.0e-8 ||
                rounded < 1 || rounded > std::numeric_limits<int>::max()) {
                valid = false;
                break;
            }
            converted.push_back(static_cast<int>(rounded));
        }
        if (valid) result.push_back(std::move(converted));
    }
    return result;
}

std::vector<int> integer_list(std::string_view value) {
    if (value.size() >= 2 && value.front() == '(' && value.back() == ')') {
        value = value.substr(1, value.size() - 2);
    }
    std::vector<int> result;
    for (const auto& part : split_step_arguments(value)) {
        const auto number = step_number(part);
        if (!number.has_value()) continue;
        const auto rounded = std::llround(*number);
        if (rounded >= 1 && rounded <= std::numeric_limits<int>::max()) {
            result.push_back(static_cast<int>(rounded));
        }
    }
    return result;
}

Point3 add(Point3 left, Point3 right) {
    return {left.x + right.x, left.y + right.y, left.z + right.z};
}

Point3 subtract(Point3 left, Point3 right) {
    return {left.x - right.x, left.y - right.y, left.z - right.z};
}

Point3 scale(Point3 point, double factor) {
    return {point.x * factor, point.y * factor, point.z * factor};
}

double dot(Point3 left, Point3 right) {
    return left.x * right.x + left.y * right.y + left.z * right.z;
}

Point3 cross(Point3 left, Point3 right) {
    return {
        left.y * right.z - left.z * right.y,
        left.z * right.x - left.x * right.z,
        left.x * right.y - left.y * right.x,
    };
}

Point3 normalize(Point3 point, Point3 fallback) {
    const auto length = std::sqrt(dot(point, point));
    if (length <= 1.0e-12) return fallback;
    return scale(point, 1.0 / length);
}

Point3 transform_vector(const Transform3& transform, Point3 point) {
    return {
        transform.basis[0][0] * point.x + transform.basis[0][1] * point.y + transform.basis[0][2] * point.z,
        transform.basis[1][0] * point.x + transform.basis[1][1] * point.y + transform.basis[1][2] * point.z,
        transform.basis[2][0] * point.x + transform.basis[2][1] * point.y + transform.basis[2][2] * point.z,
    };
}

Point3 transform_point(const Transform3& transform, Point3 point) {
    return add(transform_vector(transform, point), transform.origin);
}

Transform3 compose(const Transform3& left, const Transform3& right) {
    Transform3 result;
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t column = 0; column < 3; ++column) {
            result.basis[row][column] =
                left.basis[row][0] * right.basis[0][column] +
                left.basis[row][1] * right.basis[1][column] +
                left.basis[row][2] * right.basis[2][column];
        }
    }
    result.origin = transform_point(left, right.origin);
    return result;
}

std::optional<Point3> cartesian_point(
    int id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.type != "IFCCARTESIANPOINT" ||
        found->second.arguments.empty()) return std::nullopt;
    auto tuples = nested_number_tuples('(' + found->second.arguments.front() + ')');
    if (tuples.empty()) {
        auto raw = found->second.arguments.front();
        if (raw.size() >= 2 && raw.front() == '(' && raw.back() == ')') {
            raw = raw.substr(1, raw.size() - 2);
        }
        const auto parts = split_step_arguments(raw);
        if (parts.size() < 2) return std::nullopt;
        return Point3{
            step_number(parts[0]).value_or(0.0),
            step_number(parts[1]).value_or(0.0),
            parts.size() > 2 ? step_number(parts[2]).value_or(0.0) : 0.0,
        };
    }
    const auto& tuple = tuples.front();
    if (tuple.size() < 2) return std::nullopt;
    return Point3{tuple[0], tuple[1], tuple.size() > 2 ? tuple[2] : 0.0};
}

std::optional<Point3> direction(
    int id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.type != "IFCDIRECTION" ||
        found->second.arguments.empty()) return std::nullopt;
    auto raw = found->second.arguments.front();
    if (raw.size() >= 2 && raw.front() == '(' && raw.back() == ')') {
        raw = raw.substr(1, raw.size() - 2);
    }
    const auto parts = split_step_arguments(raw);
    if (parts.size() < 2) return std::nullopt;
    return Point3{
        step_number(parts[0]).value_or(0.0),
        step_number(parts[1]).value_or(0.0),
        parts.size() > 2 ? step_number(parts[2]).value_or(0.0) : 0.0,
    };
}

Transform3 placement_transform(
    int id,
    const std::unordered_map<int, StepEntity>& entities,
    std::unordered_map<int, Transform3>& cache,
    std::unordered_set<int>& guard
) {
    if (const auto cached = cache.find(id); cached != cache.end()) return cached->second;
    if (!guard.insert(id).second) return {};
    const auto found = entities.find(id);
    if (found == entities.end()) {
        guard.erase(id);
        return {};
    }
    Transform3 result;
    const auto& entity = found->second;
    if (entity.type == "IFCLOCALPLACEMENT" && entity.arguments.size() > 1) {
        if (const auto parent = step_reference(entity.arguments[0]); parent.has_value()) {
            result = placement_transform(*parent, entities, cache, guard);
        }
        if (const auto relative = step_reference(entity.arguments[1]); relative.has_value()) {
            result = compose(result, placement_transform(*relative, entities, cache, guard));
        }
    } else if (entity.type == "IFCAXIS2PLACEMENT3D" ||
               entity.type == "IFCAXIS2PLACEMENT2D") {
        if (!entity.arguments.empty()) {
            if (const auto location = step_reference(entity.arguments[0]); location.has_value()) {
                result.origin = cartesian_point(*location, entities).value_or(Point3{});
            }
        }
        auto x = Point3{1.0, 0.0, 0.0};
        auto z = Point3{0.0, 0.0, 1.0};
        if (entity.type == "IFCAXIS2PLACEMENT3D") {
            if (entity.arguments.size() > 1) {
                if (const auto axis = step_reference(entity.arguments[1]); axis.has_value()) {
                    z = direction(*axis, entities).value_or(z);
                }
            }
            if (entity.arguments.size() > 2) {
                if (const auto ref = step_reference(entity.arguments[2]); ref.has_value()) {
                    x = direction(*ref, entities).value_or(x);
                }
            }
        } else if (entity.arguments.size() > 1) {
            if (const auto ref = step_reference(entity.arguments[1]); ref.has_value()) {
                x = direction(*ref, entities).value_or(x);
                x.z = 0.0;
            }
        }
        z = normalize(z, {0.0, 0.0, 1.0});
        x = normalize(subtract(x, scale(z, dot(x, z))), {1.0, 0.0, 0.0});
        const auto y = normalize(cross(z, x), {0.0, 1.0, 0.0});
        result.basis = {{{x.x, y.x, z.x}, {x.y, y.y, z.y}, {x.z, y.z, z.z}}};
    }
    guard.erase(id);
    cache[id] = result;
    return result;
}

double length_scale(const std::vector<StepEntity>& entities) {
    for (const auto& entity : entities) {
        if (entity.type != "IFCSIUNIT" || entity.arguments.size() < 4) continue;
        if (entity.arguments[1].find("LENGTHUNIT") == std::string::npos) continue;
        const auto& prefix = entity.arguments[2];
        if (prefix.find("MILLI") != std::string::npos) return 0.001;
        if (prefix.find("CENTI") != std::string::npos) return 0.01;
        if (prefix.find("DECI") != std::string::npos) return 0.1;
        if (prefix.find("KILO") != std::string::npos) return 1000.0;
        if (prefix.find("MICRO") != std::string::npos) return 0.000001;
        return 1.0;
    }
    return 1.0;
}

void append_indexed_faces(
    const std::vector<Point3>& points,
    const std::vector<std::vector<int>>& faces,
    const Transform3& transform,
    double unit_scale,
    MeshBuffer& output
) {
    if (points.empty() || faces.empty()) return;
    const auto base = static_cast<std::uint32_t>(output.vertices.size());
    output.vertices.reserve(output.vertices.size() + points.size());
    for (const auto point : points) {
        output.vertices.push_back(scale(transform_point(transform, point), unit_scale));
    }
    for (const auto& face : faces) {
        if (face.size() < 3) continue;
        const auto first = face.front() - 1;
        if (first < 0 || static_cast<std::size_t>(first) >= points.size()) continue;
        for (std::size_t index = 1; index + 1 < face.size(); ++index) {
            const auto second = face[index] - 1;
            const auto third = face[index + 1] - 1;
            if (second < 0 || third < 0 ||
                static_cast<std::size_t>(second) >= points.size() ||
                static_cast<std::size_t>(third) >= points.size()) continue;
            output.indices.insert(output.indices.end(), {
                base + static_cast<std::uint32_t>(first),
                base + static_cast<std::uint32_t>(second),
                base + static_cast<std::uint32_t>(third),
            });
        }
    }
}

std::vector<Point3> point_list(
    int id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.arguments.empty()) return {};
    if (found->second.type != "IFCCARTESIANPOINTLIST3D" &&
        found->second.type != "IFCCARTESIANPOINTLIST2D") return {};
    std::vector<Point3> result;
    for (const auto& tuple : nested_number_tuples(found->second.arguments.front())) {
        if (tuple.size() < 2) continue;
        result.push_back({tuple[0], tuple[1], tuple.size() > 2 ? tuple[2] : 0.0});
    }
    return result;
}

void append_tessellated_item(
    int id,
    const std::unordered_map<int, StepEntity>& entities,
    const Transform3& transform,
    double unit_scale,
    MeshBuffer& output,
    std::unordered_set<int>& recursion_guard
) {
    if (!recursion_guard.insert(id).second) return;
    const auto found = entities.find(id);
    if (found == entities.end()) {
        recursion_guard.erase(id);
        return;
    }
    const auto& entity = found->second;
    if (entity.type == "IFCTRIANGULATEDFACESET" && entity.arguments.size() > 3) {
        const auto point_refs = references_in(entity.arguments[0]);
        if (!point_refs.empty()) {
            append_indexed_faces(
                point_list(point_refs.front(), entities),
                nested_integer_tuples(entity.arguments[3]),
                transform,
                unit_scale,
                output);
        }
    } else if (entity.type == "IFCPOLYGONALFACESET" && entity.arguments.size() > 2) {
        const auto point_refs = references_in(entity.arguments[0]);
        std::vector<std::vector<int>> faces;
        for (const auto face_id : references_in(entity.arguments[2])) {
            const auto face = entities.find(face_id);
            if (face == entities.end() || face->second.arguments.empty()) continue;
            if (face->second.type != "IFCINDEXEDPOLYGONALFACE" &&
                face->second.type != "IFCINDEXEDPOLYGONALFACEWITHVOIDS") continue;
            auto indices = integer_list(face->second.arguments[0]);
            if (indices.size() >= 3) faces.push_back(std::move(indices));
        }
        if (!point_refs.empty()) {
            append_indexed_faces(
                point_list(point_refs.front(), entities),
                faces,
                transform,
                unit_scale,
                output);
        }
    } else if (entity.type == "IFCREPRESENTATIONMAP" && entity.arguments.size() > 1) {
        for (const auto representation_id : references_in(entity.arguments[1])) {
            append_tessellated_item(
                representation_id, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCMAPPEDITEM" && !entity.arguments.empty()) {
        for (const auto map_id : references_in(entity.arguments[0])) {
            append_tessellated_item(
                map_id, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCSHAPEREPRESENTATION" ||
               entity.type == "IFCREPRESENTATION") {
        if (entity.arguments.size() > 3) {
            for (const auto item_id : references_in(entity.arguments[3])) {
                append_tessellated_item(
                    item_id, entities, transform, unit_scale, output, recursion_guard);
            }
        }
    }
    recursion_guard.erase(id);
}

MeshBuffer product_tessellated_mesh(
    const StepEntity& product,
    const std::unordered_map<int, StepEntity>& entities,
    double unit_scale,
    std::unordered_map<int, Transform3>& placement_cache
) {
    MeshBuffer output;
    if (product.arguments.size() <= 6) return output;
    const auto shape_id = step_reference(product.arguments[6]);
    if (!shape_id.has_value()) return output;
    const auto shape = entities.find(*shape_id);
    if (shape == entities.end() || shape->second.type != "IFCPRODUCTDEFINITIONSHAPE" ||
        shape->second.arguments.size() <= 2) return output;

    Transform3 transform;
    if (const auto placement_id = step_reference(product.arguments[5]); placement_id.has_value()) {
        std::unordered_set<int> guard;
        transform = placement_transform(*placement_id, entities, placement_cache, guard);
    }
    std::unordered_set<int> recursion_guard;
    for (const auto representation_id : references_in(shape->second.arguments[2])) {
        append_tessellated_item(
            representation_id, entities, transform, unit_scale, output, recursion_guard);
    }
    return output;
}

Bounds3 mesh_bounds(const MeshBuffer& mesh) {
    Bounds3 bounds;
    for (const auto& point : mesh.vertices) {
        if (!std::isfinite(point.x) || !std::isfinite(point.y) || !std::isfinite(point.z)) continue;
        bounds.minimum.x = std::min(bounds.minimum.x, point.x);
        bounds.minimum.y = std::min(bounds.minimum.y, point.y);
        bounds.minimum.z = std::min(bounds.minimum.z, point.z);
        bounds.maximum.x = std::max(bounds.maximum.x, point.x);
        bounds.maximum.y = std::max(bounds.maximum.y, point.y);
        bounds.maximum.z = std::max(bounds.maximum.z, point.z);
        bounds.valid = true;
    }
    return bounds;
}

ElementId element_level_id(const Element& element) {
    switch (element.kind()) {
    case ElementKind::Wall: return element.wall()->level_id;
    case ElementKind::Door: return element.door()->level_id;
    case ElementKind::Window: return element.window()->level_id;
    case ElementKind::Slab: return element.slab()->level_id;
    case ElementKind::Roof: return element.roof()->level_id;
    case ElementKind::Column: return element.column()->level_id;
    case ElementKind::Beam: return element.beam()->level_id;
    case ElementKind::Stair: return element.stair()->base_level_id;
    case ElementKind::Proxy: return element.proxy()->level_id;
    case ElementKind::Level:
    case ElementKind::Room:
        return 0;
    }
    return 0;
}

double level_elevation(const Document& document, ElementId level_id) {
    const auto* level = document.find_ptr(level_id);
    return level != nullptr && level->level() != nullptr
        ? level->level()->elevation_meters
        : 0.0;
}

MeshBuffer relative_to_level(MeshBuffer mesh, double elevation) {
    for (auto& point : mesh.vertices) point.z -= elevation;
    return mesh;
}

void mark_exact(Element& element, const StepEntity& source) {
    if (!source.arguments.empty()) {
        const auto guid = step_string(source.arguments.front());
        if (!guid.empty()) {
            element.metadata()["ifc_guid"] = MetadataValue{
                .kind = MetadataValueKind::Text,
                .value = guid,
            };
        }
    }
    element.metadata()["ifc_entity"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = source.type,
    };
    element.metadata()["ifc_exact_geometry"] = MetadataValue{
        .kind = MetadataValueKind::Boolean,
        .value = "true",
    };
    element.metadata()["ifc_import_note"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = "IFC4 tessellated geometry recovered by the staged importer.",
    };
}

bool assign_mesh(Document& document, Element& element, const StepEntity& source, MeshBuffer mesh) {
    if (mesh.vertices.empty() || mesh.indices.empty()) return false;
    const auto elevation = level_elevation(document, element_level_id(element));
    mesh = relative_to_level(std::move(mesh), elevation);
    switch (element.kind()) {
    case ElementKind::Wall:
        element.wall()->geometry.mesh = std::move(mesh);
        element.wall()->geometry.dirty = false;
        break;
    case ElementKind::Door:
        element.door()->mesh = std::move(mesh);
        break;
    case ElementKind::Window:
        element.window()->mesh = std::move(mesh);
        break;
    case ElementKind::Slab:
        element.slab()->mesh = std::move(mesh);
        element.slab()->generated_geometry_dirty = false;
        break;
    case ElementKind::Roof:
        element.roof()->mesh = std::move(mesh);
        element.roof()->generated_geometry_dirty = false;
        break;
    case ElementKind::Column:
        element.column()->mesh = std::move(mesh);
        element.column()->generated_geometry_dirty = false;
        break;
    case ElementKind::Beam:
        element.beam()->mesh = std::move(mesh);
        element.beam()->generated_geometry_dirty = false;
        break;
    case ElementKind::Stair:
        element.stair()->mesh = std::move(mesh);
        element.stair()->generated_geometry_dirty = false;
        break;
    case ElementKind::Proxy:
        element.proxy()->mesh = std::move(mesh);
        break;
    case ElementKind::Level:
    case ElementKind::Room:
        return false;
    }
    mark_exact(element, source);
    return true;
}

std::string source_guid(const StepEntity& entity) {
    return entity.arguments.empty() ? std::string{} : step_string(entity.arguments.front());
}

Element* find_by_ifc_guid(Document& document, const std::string& guid) {
    if (guid.empty()) return nullptr;
    ElementId id{};
    for (const auto& element : document.elements()) {
        const auto found = element.metadata().find("ifc_guid");
        if (found != element.metadata().end() && found->second.value == guid) {
            id = element.id();
            break;
        }
    }
    return id == 0 ? nullptr : document.find_ptr(id);
}

bool is_physical_product(const StepEntity& entity,
                         const std::unordered_map<int, StepEntity>& entities) {
    if (entity.type.rfind("IFC", 0) != 0 || entity.type.rfind("IFCREL", 0) == 0) return false;
    if (entity.arguments.size() <= 6) return false;
    const auto shape_id = step_reference(entity.arguments[6]);
    if (!shape_id.has_value()) return false;
    const auto shape = entities.find(*shape_id);
    if (shape == entities.end() || shape->second.type != "IFCPRODUCTDEFINITIONSHAPE") return false;
    return entity.type != "IFCSPACE" && entity.type != "IFCANNOTATION" &&
           entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCBUILDING" &&
           entity.type != "IFCSITE" && entity.type != "IFCPROJECT";
}

std::pair<ElementId, double> nearest_level(Document& document, double z) {
    ElementId best_id{};
    double best_elevation{};
    double best_distance = std::numeric_limits<double>::max();
    for (const auto& element : document.elements()) {
        const auto* level = element.level();
        if (level == nullptr) continue;
        const auto distance = std::abs(z - level->elevation_meters);
        if (distance < best_distance) {
            best_distance = distance;
            best_id = element.id();
            best_elevation = level->elevation_meters;
        }
    }
    if (best_id == 0) {
        best_id = document.create_level("Level 1", 0.0, 3.0);
        best_elevation = 0.0;
    }
    return {best_id, best_elevation};
}

std::string product_name(const StepEntity& entity) {
    if (entity.arguments.size() > 2) {
        const auto name = step_string(entity.arguments[2]);
        if (!name.empty()) return name;
    }
    return entity.type + " " + std::to_string(entity.id);
}

} // namespace

Document import_ifc(
    const std::filesystem::path& path,
    std::string document_name,
    IfcExchangeReport* report
) {
    // First retain the mature semantic/IFC2x3 path. Recovery below is additive:
    // it replaces missing geometry or creates an exact proxy, never deletes a
    // semantic element produced by the compatibility importer.
    auto document = import_ifc_legacy(path, std::move(document_name), report);

    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to reopen IFC import path");
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const auto contents = buffer.str();
    if (contents.find("/* TBE_DOCUMENT_JSON_HEX ") != std::string::npos) {
        return document;
    }

    const auto parsed = parse_step_entities(contents);
    std::unordered_map<int, StepEntity> entities;
    entities.reserve(parsed.size());
    for (const auto& entity : parsed) entities.emplace(entity.id, entity);
    const auto unit_scale = length_scale(parsed);
    std::unordered_map<int, Transform3> placement_cache;

    std::size_t recovered_existing = 0;
    std::size_t recovered_proxies = 0;
    for (const auto& source : parsed) {
        if (!is_physical_product(source, entities)) continue;
        auto mesh = product_tessellated_mesh(
            source, entities, unit_scale, placement_cache);
        if (mesh.vertices.empty() || mesh.indices.empty()) continue;

        const auto guid = source_guid(source);
        if (auto* existing = find_by_ifc_guid(document, guid); existing != nullptr) {
            if (assign_mesh(document, *existing, source, std::move(mesh))) {
                ++recovered_existing;
            }
            continue;
        }

        const auto bounds = mesh_bounds(mesh);
        if (!bounds.valid) continue;
        const auto [level_id, elevation] = nearest_level(document, bounds.minimum.z);
        const auto width = std::max(0.01, bounds.maximum.x - bounds.minimum.x);
        const auto depth = std::max(0.01, bounds.maximum.y - bounds.minimum.y);
        const auto height = std::max(0.01, bounds.maximum.z - bounds.minimum.z);
        const auto center = Point2{
            (bounds.minimum.x + bounds.maximum.x) * 0.5,
            (bounds.minimum.y + bounds.maximum.y) * 0.5,
        };
        const auto id = document.create_proxy(
            product_name(source),
            level_id,
            center,
            width,
            depth,
            height,
            relative_to_level(std::move(mesh), elevation));
        if (auto* created = document.find_ptr(id); created != nullptr) {
            mark_exact(*created, source);
        }
        ++recovered_proxies;
    }

    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        if (recovered_existing != 0 || recovered_proxies != 0) {
            report->warnings.push_back(
                "IFC4 tessellation recovery: restored exact mesh for " +
                std::to_string(recovered_existing) + " semantic elements and " +
                std::to_string(recovered_proxies) +
                " additional physical products that the legacy reader could not render.");
        }
    }
    return document;
}

} // namespace tbe::core
