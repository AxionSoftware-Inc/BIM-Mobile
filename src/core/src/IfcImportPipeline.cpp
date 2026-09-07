#include "tbe/core/IfcExchange.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <limits>
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

struct RecoveredMesh {
    MeshBuffer mesh{};
    bool exact{true};
    std::string stage{"tessellation"};
};

using GuidIndex = std::unordered_map<std::string, ElementId>;
using LevelIndex = std::vector<std::pair<ElementId, double>>;

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
            .arguments = split_step_arguments(contents.substr(open + 1, close - open - 2)),
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

std::string untyped_value(std::string value) {
    value = trim(std::move(value));
    if (value.empty() || value == "$" || value == "*") return {};
    const auto open = value.find('(');
    if (open != std::string::npos && value.back() == ')') {
        value = trim(value.substr(open + 1, value.size() - open - 2));
    }
    const auto text = step_string(value);
    return text.empty() ? value : text;
}

std::string metadata_key_part(std::string value) {
    for (auto& ch : value) {
        if (!std::isalnum(static_cast<unsigned char>(ch)) && ch != '_' && ch != '-') ch = '_';
    }
    while (value.find("__") != std::string::npos) {
        value.replace(value.find("__"), 2, "_");
    }
    if (value.size() > 80) value.resize(80);
    return value.empty() ? std::string{"unnamed"} : value;
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
                const auto parts = split_step_arguments(value.substr(tuple_start, index - tuple_start));
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

void append_polygon(
    const std::vector<Point3>& polygon,
    const Transform3& transform,
    double unit_scale,
    MeshBuffer& output
) {
    if (polygon.size() < 3) return;
    const auto base = static_cast<std::uint32_t>(output.vertices.size());
    output.vertices.reserve(output.vertices.size() + polygon.size());
    for (const auto point : polygon) {
        output.vertices.push_back(scale(transform_point(transform, point), unit_scale));
    }
    for (std::size_t index = 1; index + 1 < polygon.size(); ++index) {
        output.indices.insert(output.indices.end(), {
            base,
            base + static_cast<std::uint32_t>(index),
            base + static_cast<std::uint32_t>(index + 1),
        });
    }
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

std::vector<Point3> polyloop_points(
    const StepEntity& loop,
    const std::unordered_map<int, StepEntity>& entities
) {
    std::vector<Point3> result;
    if (loop.type != "IFCPOLYLOOP" || loop.arguments.empty()) return result;
    for (const auto point_id : references_in(loop.arguments.front())) {
        const auto point = cartesian_point(point_id, entities);
        if (point.has_value()) result.push_back(*point);
    }
    return result;
}

void append_geometry_item(
    int id,
    const std::unordered_map<int, StepEntity>& entities,
    const Transform3& transform,
    double unit_scale,
    RecoveredMesh& output,
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
                output.mesh);
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
            if (face->second.type == "IFCINDEXEDPOLYGONALFACEWITHVOIDS") {
                output.exact = false;
                output.stage = "polygonal-face-set-with-voids";
            }
        }
        if (!point_refs.empty()) {
            append_indexed_faces(
                point_list(point_refs.front(), entities),
                faces,
                transform,
                unit_scale,
                output.mesh);
        }
    } else if (entity.type == "IFCFACETEDBREP" ||
               entity.type == "IFCMANIFOLDSOLIDBREP" ||
               entity.type == "IFCADVANCEDBREP") {
        if (entity.type == "IFCADVANCEDBREP") {
            output.exact = false;
            output.stage = "advanced-brep-boundary";
        } else if (output.stage == "tessellation") {
            output.stage = "faceted-brep";
        }
        for (const auto child : references_in(entity.arguments.empty() ? std::string{} : entity.arguments[0])) {
            append_geometry_item(child, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCCLOSEDSHELL" ||
               entity.type == "IFCOPENSHELL" ||
               entity.type == "IFCCONNECTEDFACESET" ||
               entity.type == "IFCSHELLBASEDSURFACEMODEL" ||
               entity.type == "IFCFACEBASEDSURFACEMODEL") {
        for (const auto& argument : entity.arguments) {
            for (const auto child : references_in(argument)) {
                append_geometry_item(child, entities, transform, unit_scale, output, recursion_guard);
            }
        }
    } else if (entity.type == "IFCFACE" || entity.type == "IFCADVANCEDFACE") {
        if (entity.type == "IFCADVANCEDFACE") {
            output.exact = false;
            output.stage = "advanced-face-boundary";
        }
        if (!entity.arguments.empty()) {
            bool emitted_outer = false;
            for (const auto bound_id : references_in(entity.arguments.front())) {
                const auto bound = entities.find(bound_id);
                if (bound == entities.end() || bound->second.arguments.empty()) continue;
                if (bound->second.type != "IFCFACEOUTERBOUND" &&
                    bound->second.type != "IFCFACEBOUND") continue;
                if (bound->second.type == "IFCFACEBOUND" && emitted_outer) {
                    output.exact = false;
                    output.stage = "brep-face-with-inner-bound";
                    continue;
                }
                const auto loop_ref = step_reference(bound->second.arguments[0]);
                if (!loop_ref.has_value()) continue;
                const auto loop = entities.find(*loop_ref);
                if (loop == entities.end()) continue;
                const auto points = polyloop_points(loop->second, entities);
                if (points.size() >= 3) {
                    append_polygon(points, transform, unit_scale, output.mesh);
                    emitted_outer = true;
                }
            }
        }
    } else if (entity.type == "IFCBOOLEANRESULT" ||
               entity.type == "IFCBOOLEANCLIPPINGRESULT") {
        // Showing the first operand is preferable to dropping the entire wall
        // or slab, but it is explicitly marked approximate because the cut is
        // not evaluated by this lightweight recovery stage.
        if (entity.arguments.size() > 1) {
            output.exact = false;
            output.stage = "boolean-first-operand";
            for (const auto child : references_in(entity.arguments[1])) {
                append_geometry_item(child, entities, transform, unit_scale, output, recursion_guard);
            }
        }
    } else if (entity.type == "IFCCSGSOLID" && !entity.arguments.empty()) {
        output.exact = false;
        output.stage = "csg-tree-fallback";
        for (const auto child : references_in(entity.arguments[0])) {
            append_geometry_item(child, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCREPRESENTATIONMAP" && entity.arguments.size() > 1) {
        for (const auto representation_id : references_in(entity.arguments[1])) {
            append_geometry_item(
                representation_id, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCMAPPEDITEM" && !entity.arguments.empty()) {
        // Mapping source geometry is preserved. The mature semantic importer
        // remains responsible for placement when it understands the product.
        // Unknown mapped proxies are marked approximate until mapped-target
        // affine transforms are promoted into this recovery stage.
        output.exact = false;
        output.stage = "mapped-item-source";
        for (const auto map_id : references_in(entity.arguments[0])) {
            append_geometry_item(map_id, entities, transform, unit_scale, output, recursion_guard);
        }
    } else if (entity.type == "IFCSHAPEREPRESENTATION" ||
               entity.type == "IFCREPRESENTATION") {
        if (entity.arguments.size() > 3) {
            for (const auto item_id : references_in(entity.arguments[3])) {
                append_geometry_item(item_id, entities, transform, unit_scale, output, recursion_guard);
            }
        }
    }
    recursion_guard.erase(id);
}

RecoveredMesh product_recovered_mesh(
    const StepEntity& product,
    const std::unordered_map<int, StepEntity>& entities,
    double unit_scale,
    std::unordered_map<int, Transform3>& placement_cache
) {
    RecoveredMesh output;
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
        append_geometry_item(
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

std::string source_guid(const StepEntity& entity) {
    return entity.arguments.empty() ? std::string{} : step_string(entity.arguments.front());
}

void set_metadata(Element& element, std::string key, std::string value,
                  MetadataValueKind kind = MetadataValueKind::Text) {
    if (value.empty()) return;
    element.metadata()[std::move(key)] = MetadataValue{
        .kind = kind,
        .value = std::move(value),
    };
}

void mark_source_identity(
    Element& element,
    const StepEntity& source,
    bool exact_geometry,
    std::string geometry_stage
) {
    const auto guid = source_guid(source);
    set_metadata(element, "ifc_guid", guid);
    set_metadata(element, "ifc_entity", source.type);
    set_metadata(element, "ifc_step_id", std::to_string(source.id), MetadataValueKind::Number);
    if (source.arguments.size() > 2) {
        set_metadata(element, "ifc_source_name", step_string(source.arguments[2]));
    }
    if (source.arguments.size() > 4) {
        set_metadata(element, "ifc_source_object_type", step_string(source.arguments[4]));
    }
    set_metadata(
        element,
        "ifc_exact_geometry",
        exact_geometry ? "true" : "false",
        MetadataValueKind::Boolean);
    set_metadata(element, "ifc_geometry_stage", geometry_stage);
}

bool assign_mesh(
    Document& document,
    Element& element,
    const StepEntity& source,
    RecoveredMesh recovered
) {
    auto& mesh = recovered.mesh;
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
    mark_source_identity(element, source, recovered.exact, recovered.stage);
    return true;
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
           entity.type != "IFCOPENINGELEMENT" && entity.type != "IFCVOIDINGFEATURE" &&
           entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCBUILDING" &&
           entity.type != "IFCSITE" && entity.type != "IFCPROJECT";
}

GuidIndex build_guid_index(const Document& document) {
    GuidIndex index;
    index.reserve(document.elements().size());
    for (const auto& element : document.elements()) {
        const auto found = element.metadata().find("ifc_guid");
        if (found == element.metadata().end() || found->second.value.empty()) continue;
        index.emplace(found->second.value, element.id());
    }
    return index;
}

LevelIndex build_level_index(const Document& document) {
    LevelIndex levels;
    for (const auto& element : document.elements()) {
        const auto* level = element.level();
        if (level != nullptr) levels.emplace_back(element.id(), level->elevation_meters);
    }
    std::sort(levels.begin(), levels.end(), [](const auto& left, const auto& right) {
        return left.second < right.second;
    });
    return levels;
}

std::pair<ElementId, double> nearest_level(
    Document& document,
    LevelIndex& levels,
    double z
) {
    if (levels.empty()) {
        const auto id = document.create_level("Level 1", 0.0, 3.0);
        levels.emplace_back(id, 0.0);
        return {id, 0.0};
    }
    auto best = levels.front();
    auto best_distance = std::abs(z - best.second);
    for (const auto& level : levels) {
        const auto distance = std::abs(z - level.second);
        if (distance < best_distance) {
            best = level;
            best_distance = distance;
        }
    }
    return best;
}

std::string product_name(const StepEntity& entity) {
    if (entity.arguments.size() > 2) {
        const auto name = step_string(entity.arguments[2]);
        if (!name.empty()) return name;
    }
    return entity.type + " " + std::to_string(entity.id);
}

void add_issue(
    IfcExchangeReport* report,
    const StepEntity& source,
    std::string stage,
    std::string message
) {
    if (report == nullptr) return;
    report->issues.push_back(IfcImportIssue{
        .step_id = source.id,
        .global_id = source_guid(source),
        .entity_type = source.type,
        .stage = std::move(stage),
        .message = std::move(message),
    });
}

std::size_t attach_property_sets(
    Document& document,
    const std::vector<StepEntity>& parsed,
    const std::unordered_map<int, StepEntity>& entities,
    const GuidIndex& guid_index
) {
    std::unordered_map<int, std::vector<std::pair<std::string, std::string>>> psets;
    psets.reserve(256);

    for (const auto& pset : parsed) {
        if (pset.type != "IFCPROPERTYSET" || pset.arguments.size() <= 4) continue;
        const auto pset_name = metadata_key_part(step_string(pset.arguments[2]));
        auto& values = psets[pset.id];
        for (const auto property_id : references_in(pset.arguments[4])) {
            const auto property = entities.find(property_id);
            if (property == entities.end() || property->second.arguments.empty()) continue;
            const auto& item = property->second;
            if (item.type == "IFCPROPERTYSINGLEVALUE" && item.arguments.size() > 2) {
                const auto name = metadata_key_part(step_string(item.arguments[0]));
                const auto value = untyped_value(item.arguments[2]);
                if (!value.empty()) values.emplace_back("ifc_pset." + pset_name + "." + name, value);
            }
        }
    }

    std::size_t imported = 0;
    for (const auto& relation : parsed) {
        if (relation.type != "IFCRELDEFINESBYPROPERTIES" || relation.arguments.size() <= 5) continue;
        const auto pset_ref = step_reference(relation.arguments[5]);
        if (!pset_ref.has_value()) continue;
        const auto values = psets.find(*pset_ref);
        if (values == psets.end() || values->second.empty()) continue;
        for (const auto object_id : references_in(relation.arguments[4])) {
            const auto source = entities.find(object_id);
            if (source == entities.end()) continue;
            const auto guid = source_guid(source->second);
            const auto imported_id = guid_index.find(guid);
            if (imported_id == guid_index.end()) continue;
            auto* element = document.find_ptr(imported_id->second);
            if (element == nullptr) continue;
            for (const auto& [key, value] : values->second) {
                set_metadata(*element, key, value);
                ++imported;
            }
        }
    }
    return imported;
}

} // namespace

Document import_ifc(
    const std::filesystem::path& path,
    std::string document_name,
    IfcExchangeReport* report
) {
    // The compatibility importer remains the semantic authority. Every stage
    // below is additive: recover source geometry/properties and audit coverage
    // without deleting semantic elements already produced by the mature path.
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
    placement_cache.reserve(parsed.size() / 8 + 16);
    auto guid_index = build_guid_index(document);
    auto levels = build_level_index(document);
    std::unordered_set<std::string> source_guids;
    source_guids.reserve(parsed.size() / 4 + 16);

    std::size_t recovered_existing = 0;
    std::size_t recovered_proxies = 0;
    std::size_t native_semantic = 0;
    std::size_t exact_mesh = 0;
    std::size_t approximate = 0;
    std::size_t failed = 0;
    std::size_t source_products = 0;
    std::size_t source_without_guid = 0;
    std::size_t duplicate_source_guid = 0;

    for (const auto& source : parsed) {
        if (!is_physical_product(source, entities)) continue;
        ++source_products;
        const auto guid = source_guid(source);
        if (guid.empty()) {
            ++source_without_guid;
        } else if (!source_guids.insert(guid).second) {
            ++duplicate_source_guid;
        }

        Element* existing = nullptr;
        if (!guid.empty()) {
            const auto indexed = guid_index.find(guid);
            if (indexed != guid_index.end()) existing = document.find_ptr(indexed->second);
        }

        auto recovered = product_recovered_mesh(source, entities, unit_scale, placement_cache);
        const auto has_recovered_mesh =
            !recovered.mesh.vertices.empty() && !recovered.mesh.indices.empty();

        if (existing != nullptr) {
            ++native_semantic;
            mark_source_identity(*existing, source, false, "native-semantic");
            if (has_recovered_mesh && assign_mesh(document, *existing, source, std::move(recovered))) {
                ++recovered_existing;
                const auto exact = existing->metadata().find("ifc_exact_geometry");
                if (exact != existing->metadata().end() && exact->second.value == "true") {
                    ++exact_mesh;
                } else {
                    ++approximate;
                }
            }
            continue;
        }

        if (!has_recovered_mesh) {
            ++failed;
            add_issue(
                report,
                source,
                "geometry-recovery",
                "No supported semantic or recoverable source geometry representation was found.");
            continue;
        }

        const auto bounds = mesh_bounds(recovered.mesh);
        if (!bounds.valid) {
            ++failed;
            add_issue(report, source, "geometry-bounds", "Recovered mesh has no finite bounds.");
            continue;
        }
        const auto [level_id, elevation] = nearest_level(document, levels, bounds.minimum.z);
        const auto width = std::max(0.01, bounds.maximum.x - bounds.minimum.x);
        const auto depth = std::max(0.01, bounds.maximum.y - bounds.minimum.y);
        const auto height = std::max(0.01, bounds.maximum.z - bounds.minimum.z);
        const auto center = Point2{
            (bounds.minimum.x + bounds.maximum.x) * 0.5,
            (bounds.minimum.y + bounds.maximum.y) * 0.5,
        };
        const auto was_exact = recovered.exact;
        const auto stage = recovered.stage;
        const auto id = document.create_proxy(
            product_name(source),
            level_id,
            center,
            width,
            depth,
            height,
            relative_to_level(std::move(recovered.mesh), elevation));
        if (auto* created = document.find_ptr(id); created != nullptr) {
            mark_source_identity(*created, source, was_exact, stage);
            if (!guid.empty()) guid_index[guid] = id;
        }
        ++recovered_proxies;
        if (was_exact) {
            ++exact_mesh;
        } else {
            ++approximate;
        }
    }

    const auto imported_properties = attach_property_sets(document, parsed, entities, guid_index);

    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        report->source_physical_products = source_products;
        report->native_semantic_products = native_semantic;
        report->exact_mesh_products = exact_mesh;
        report->recovered_proxy_products = recovered_proxies;
        report->approximate_products = approximate;
        report->failed_geometry_products = failed;
        report->source_products_without_guid = source_without_guid;
        report->duplicate_source_identity_products = duplicate_source_guid;
        report->silent_dropped_products = 0;
        report->imported_property_values = imported_properties;
        report->warnings.push_back(
            "IFC import coverage: source=" + std::to_string(source_products) +
            ", native=" + std::to_string(native_semantic) +
            ", exact_mesh=" + std::to_string(exact_mesh) +
            ", proxy=" + std::to_string(recovered_proxies) +
            ", approximate=" + std::to_string(approximate) +
            ", failed_geometry=" + std::to_string(failed) +
            ", silent_dropped=0, properties=" + std::to_string(imported_properties) + ".");
        if (recovered_existing != 0 || recovered_proxies != 0) {
            report->warnings.push_back(
                "IFC staged recovery: restored source mesh for " +
                std::to_string(recovered_existing) + " semantic elements and " +
                std::to_string(recovered_proxies) + " additional physical products.");
        }
    }
    return document;
}

} // namespace tbe::core
