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
#include <set>
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
    std::string stage{"source-mesh"};
    int mapping_source_step_id{};
};

using EntityIndex = std::unordered_map<int, StepEntity>;
using GuidIndex = std::unordered_map<std::string, ElementId>;
using PlacementCache = std::unordered_map<int, Transform3>;
using MappingCache = std::unordered_map<int, RecoveredMesh>;
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
        while (end < value.size() && std::isdigit(static_cast<unsigned char>(value[end])) != 0) ++end;
        if (end == start) continue;
        result.push_back(static_cast<int>(std::strtol(
            std::string(value.substr(start, end - start)).c_str(), nullptr, 10)));
        index = end - 1;
    }
    return result;
}

std::optional<double> step_number(std::string_view value) {
    if (value.empty() || value == "$" || value == "*" || value.front() == '.') return std::nullopt;
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
        if (value[index] == '\'' && index + 2 < value.size() && value[index + 1] == '\'') ++index;
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
    while (value.find("__") != std::string::npos) value.replace(value.find("__"), 2, "_");
    if (value.size() > 80) value.resize(80);
    return value.empty() ? std::string{"unnamed"} : value;
}

Point3 add(Point3 a, Point3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
Point3 subtract(Point3 a, Point3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
Point3 scale(Point3 p, double s) { return {p.x * s, p.y * s, p.z * s}; }
double dot(Point3 a, Point3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
Point3 cross(Point3 a, Point3 b) {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
Point3 normalize(Point3 p, Point3 fallback) {
    const auto length = std::sqrt(dot(p, p));
    return length <= 1.0e-12 ? fallback : scale(p, 1.0 / length);
}

Point3 transform_vector(const Transform3& t, Point3 p) {
    return {
        t.basis[0][0] * p.x + t.basis[0][1] * p.y + t.basis[0][2] * p.z,
        t.basis[1][0] * p.x + t.basis[1][1] * p.y + t.basis[1][2] * p.z,
        t.basis[2][0] * p.x + t.basis[2][1] * p.y + t.basis[2][2] * p.z,
    };
}
Point3 transform_point(const Transform3& t, Point3 p) { return add(transform_vector(t, p), t.origin); }

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

std::optional<Transform3> inverse(const Transform3& transform) {
    const auto& m = transform.basis;
    const auto determinant =
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if (std::abs(determinant) <= 1.0e-12) return std::nullopt;
    const auto k = 1.0 / determinant;
    Transform3 result;
    result.basis = {{
        {(m[1][1] * m[2][2] - m[1][2] * m[2][1]) * k,
         (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * k,
         (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * k},
        {(m[1][2] * m[2][0] - m[1][0] * m[2][2]) * k,
         (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * k,
         (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * k},
        {(m[1][0] * m[2][1] - m[1][1] * m[2][0]) * k,
         (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * k,
         (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * k},
    }};
    result.origin = scale(transform_vector(result, transform.origin), -1.0);
    return result;
}

std::optional<Point3> cartesian_point(int id, const EntityIndex& entities) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.type != "IFCCARTESIANPOINT" || found->second.arguments.empty()) return std::nullopt;
    auto raw = found->second.arguments.front();
    if (raw.size() >= 2 && raw.front() == '(' && raw.back() == ')') raw = raw.substr(1, raw.size() - 2);
    const auto parts = split_step_arguments(raw);
    if (parts.size() < 2) return std::nullopt;
    return Point3{
        step_number(parts[0]).value_or(0.0),
        step_number(parts[1]).value_or(0.0),
        parts.size() > 2 ? step_number(parts[2]).value_or(0.0) : 0.0,
    };
}

std::optional<Point3> direction(int id, const EntityIndex& entities) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.type != "IFCDIRECTION" || found->second.arguments.empty()) return std::nullopt;
    auto raw = found->second.arguments.front();
    if (raw.size() >= 2 && raw.front() == '(' && raw.back() == ')') raw = raw.substr(1, raw.size() - 2);
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
    const EntityIndex& entities,
    PlacementCache& cache,
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
    } else if (entity.type == "IFCAXIS2PLACEMENT3D" || entity.type == "IFCAXIS2PLACEMENT2D") {
        if (!entity.arguments.empty()) {
            if (const auto location = step_reference(entity.arguments[0]); location.has_value()) {
                result.origin = cartesian_point(*location, entities).value_or(Point3{});
            }
        }
        auto x = Point3{1.0, 0.0, 0.0};
        auto z = Point3{0.0, 0.0, 1.0};
        if (entity.type == "IFCAXIS2PLACEMENT3D") {
            if (entity.arguments.size() > 1) {
                if (const auto axis = step_reference(entity.arguments[1]); axis.has_value()) z = direction(*axis, entities).value_or(z);
            }
            if (entity.arguments.size() > 2) {
                if (const auto ref = step_reference(entity.arguments[2]); ref.has_value()) x = direction(*ref, entities).value_or(x);
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

Transform3 cartesian_operator_transform(int id, const EntityIndex& entities) {
    const auto found = entities.find(id);
    if (found == entities.end()) return {};
    const auto& entity = found->second;
    const bool is_3d = entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR3D" ||
        entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR3DNONUNIFORM";
    const bool is_2d = entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR2D" ||
        entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR2DNONUNIFORM";
    if (!is_3d && !is_2d) return {};

    Transform3 result;
    if (entity.arguments.size() > 2) {
        if (const auto origin = step_reference(entity.arguments[2]); origin.has_value()) {
            result.origin = cartesian_point(*origin, entities).value_or(Point3{});
        }
    }
    auto x = Point3{1.0, 0.0, 0.0};
    auto y_hint = Point3{0.0, 1.0, 0.0};
    auto z = Point3{0.0, 0.0, 1.0};
    if (!entity.arguments.empty()) {
        if (const auto axis = step_reference(entity.arguments[0]); axis.has_value()) x = direction(*axis, entities).value_or(x);
    }
    if (entity.arguments.size() > 1) {
        if (const auto axis = step_reference(entity.arguments[1]); axis.has_value()) y_hint = direction(*axis, entities).value_or(y_hint);
    }
    if (is_3d && entity.arguments.size() > 4) {
        if (const auto axis = step_reference(entity.arguments[4]); axis.has_value()) z = direction(*axis, entities).value_or(z);
    }
    x = normalize(x, {1.0, 0.0, 0.0});
    if (is_3d) {
        z = normalize(z, {0.0, 0.0, 1.0});
        auto y = cross(z, x);
        if (dot(y, y) <= 1.0e-12) y = y_hint;
        y = normalize(y, {0.0, 1.0, 0.0});
        z = normalize(cross(x, y), z);
        const auto s1 = entity.arguments.size() > 3 ? step_number(entity.arguments[3]).value_or(1.0) : 1.0;
        const auto s2 = entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR3DNONUNIFORM" && entity.arguments.size() > 5
            ? step_number(entity.arguments[5]).value_or(s1) : s1;
        const auto s3 = entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR3DNONUNIFORM" && entity.arguments.size() > 6
            ? step_number(entity.arguments[6]).value_or(s1) : s1;
        result.basis = {{{x.x * s1, y.x * s2, z.x * s3},
                         {x.y * s1, y.y * s2, z.y * s3},
                         {x.z * s1, y.z * s2, z.z * s3}}};
    } else {
        x.z = 0.0;
        x = normalize(x, {1.0, 0.0, 0.0});
        auto y = Point3{-x.y, x.x, 0.0};
        if (dot(y_hint, y) < 0.0) y = scale(y, -1.0);
        const auto s1 = entity.arguments.size() > 3 ? step_number(entity.arguments[3]).value_or(1.0) : 1.0;
        const auto s2 = entity.type == "IFCCARTESIANTRANSFORMATIONOPERATOR2DNONUNIFORM" && entity.arguments.size() > 4
            ? step_number(entity.arguments[4]).value_or(s1) : s1;
        result.basis = {{{x.x * s1, y.x * s2, 0.0},
                         {x.y * s1, y.y * s2, 0.0},
                         {0.0, 0.0, 1.0}}};
    }
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
                bool valid = true;
                for (const auto& part : parts) {
                    const auto number = step_number(part);
                    if (!number.has_value()) { valid = false; break; }
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

std::vector<int> integer_list(std::string_view value) {
    if (value.size() >= 2 && value.front() == '(' && value.back() == ')') value = value.substr(1, value.size() - 2);
    std::vector<int> result;
    for (const auto& part : split_step_arguments(value)) {
        const auto number = step_number(part);
        if (!number.has_value()) continue;
        const auto rounded = std::llround(*number);
        if (rounded >= 1 && rounded <= std::numeric_limits<int>::max()) result.push_back(static_cast<int>(rounded));
    }
    return result;
}

std::vector<std::vector<int>> nested_integer_tuples(std::string_view value) {
    std::vector<std::vector<int>> result;
    for (const auto& tuple : nested_number_tuples(value)) {
        std::vector<int> values;
        bool valid = true;
        for (const auto number : tuple) {
            const auto rounded = std::llround(number);
            if (std::abs(number - static_cast<double>(rounded)) > 1.0e-8 || rounded < 1) { valid = false; break; }
            values.push_back(static_cast<int>(rounded));
        }
        if (valid && values.size() >= 3) result.push_back(std::move(values));
    }
    return result;
}

std::vector<Point3> point_list(int id, const EntityIndex& entities) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.arguments.empty()) return {};
    if (found->second.type != "IFCCARTESIANPOINTLIST3D" && found->second.type != "IFCCARTESIANPOINTLIST2D") return {};
    std::vector<Point3> result;
    for (const auto& tuple : nested_number_tuples(found->second.arguments.front())) {
        if (tuple.size() >= 2) result.push_back({tuple[0], tuple[1], tuple.size() > 2 ? tuple[2] : 0.0});
    }
    return result;
}

void append_mesh_transformed(const MeshBuffer& source, const Transform3& transform, double unit_scale, MeshBuffer& output) {
    if (source.vertices.empty() || source.indices.empty()) return;
    const auto base = static_cast<std::uint32_t>(output.vertices.size());
    output.vertices.reserve(output.vertices.size() + source.vertices.size());
    for (const auto& p : source.vertices) output.vertices.push_back(scale(transform_point(transform, p), unit_scale));
    output.indices.reserve(output.indices.size() + source.indices.size());
    for (const auto index : source.indices) output.indices.push_back(base + index);
}

void append_polygon(const std::vector<Point3>& polygon, const Transform3& transform, double unit_scale, MeshBuffer& output, bool reverse = false) {
    if (polygon.size() < 3) return;
    const auto base = static_cast<std::uint32_t>(output.vertices.size());
    for (const auto& p : polygon) output.vertices.push_back(scale(transform_point(transform, p), unit_scale));
    for (std::size_t i = 1; i + 1 < polygon.size(); ++i) {
        if (!reverse) output.indices.insert(output.indices.end(), {base, base + static_cast<std::uint32_t>(i), base + static_cast<std::uint32_t>(i + 1)});
        else output.indices.insert(output.indices.end(), {base, base + static_cast<std::uint32_t>(i + 1), base + static_cast<std::uint32_t>(i)});
    }
}

void append_indexed_faces(const std::vector<Point3>& points, const std::vector<std::vector<int>>& faces, const Transform3& transform, double unit_scale, MeshBuffer& output) {
    if (points.empty() || faces.empty()) return;
    const auto base = static_cast<std::uint32_t>(output.vertices.size());
    for (const auto& p : points) output.vertices.push_back(scale(transform_point(transform, p), unit_scale));
    for (const auto& face : faces) {
        if (face.size() < 3) continue;
        const auto first = face.front() - 1;
        if (first < 0 || static_cast<std::size_t>(first) >= points.size()) continue;
        for (std::size_t i = 1; i + 1 < face.size(); ++i) {
            const auto b = face[i] - 1;
            const auto c = face[i + 1] - 1;
            if (b < 0 || c < 0 || static_cast<std::size_t>(b) >= points.size() || static_cast<std::size_t>(c) >= points.size()) continue;
            output.indices.insert(output.indices.end(), {base + static_cast<std::uint32_t>(first), base + static_cast<std::uint32_t>(b), base + static_cast<std::uint32_t>(c)});
        }
    }
}

std::vector<Point3> curve_points(int curve_id, const EntityIndex& entities) {
    const auto found = entities.find(curve_id);
    if (found == entities.end() || found->second.arguments.empty()) return {};
    const auto& curve = found->second;
    std::vector<Point3> result;
    if (curve.type == "IFCPOLYLINE") {
        for (const auto id : references_in(curve.arguments[0])) {
            if (const auto p = cartesian_point(id, entities); p.has_value()) result.push_back(*p);
        }
    } else if (curve.type == "IFCINDEXEDPOLYCURVE") {
        const auto refs = references_in(curve.arguments[0]);
        if (!refs.empty()) result = point_list(refs.front(), entities);
    }
    if (result.size() > 1 && dot(subtract(result.front(), result.back()), subtract(result.front(), result.back())) <= 1.0e-12) result.pop_back();
    return result;
}

std::vector<Point3> profile_polygon(int profile_id, const EntityIndex& entities, PlacementCache& placement_cache, bool& exact) {
    const auto found = entities.find(profile_id);
    if (found == entities.end()) return {};
    const auto& profile = found->second;
    std::vector<Point3> polygon;
    if (profile.type == "IFCRECTANGLEPROFILEDEF" && profile.arguments.size() > 3) {
        const auto x = step_number(profile.arguments[2]).value_or(0.0) * 0.5;
        const auto y = step_number(profile.arguments[3]).value_or(0.0) * 0.5;
        polygon = {{-x, -y, 0.0}, {x, -y, 0.0}, {x, y, 0.0}, {-x, y, 0.0}};
    } else if (profile.type == "IFCCIRCLEPROFILEDEF" && profile.arguments.size() > 2) {
        const auto radius = step_number(profile.arguments[2]).value_or(0.0);
        constexpr int segments = 32;
        for (int i = 0; i < segments; ++i) {
            const auto angle = 2.0 * 3.14159265358979323846 * static_cast<double>(i) / static_cast<double>(segments);
            polygon.push_back({radius * std::cos(angle), radius * std::sin(angle), 0.0});
        }
    } else if ((profile.type == "IFCARBITRARYCLOSEDPROFILEDEF" || profile.type == "IFCARBITRARYPROFILEDEFWITHVOIDS") && profile.arguments.size() > 2) {
        const auto refs = references_in(profile.arguments[2]);
        if (!refs.empty()) polygon = curve_points(refs.front(), entities);
        if (profile.type == "IFCARBITRARYPROFILEDEFWITHVOIDS") exact = false;
    }
    if (polygon.empty()) return polygon;
    if (profile.arguments.size() > 1) {
        if (const auto position_id = step_reference(profile.arguments[1]); position_id.has_value()) {
            std::unordered_set<int> guard;
            const auto t = placement_transform(*position_id, entities, placement_cache, guard);
            for (auto& p : polygon) p = transform_point(t, p);
        }
    }
    return polygon;
}

void append_extruded_area_solid(const StepEntity& solid, const EntityIndex& entities, const Transform3& parent, double unit_scale, RecoveredMesh& output) {
    if (solid.arguments.size() < 4) return;
    const auto profile_refs = references_in(solid.arguments[0]);
    if (profile_refs.empty()) return;
    PlacementCache local_cache;
    bool profile_exact = true;
    auto polygon = profile_polygon(profile_refs.front(), entities, local_cache, profile_exact);
    if (polygon.size() < 3) return;
    auto solid_transform = Transform3{};
    if (const auto position = step_reference(solid.arguments[1]); position.has_value()) {
        std::unordered_set<int> guard;
        solid_transform = placement_transform(*position, entities, local_cache, guard);
    }
    const auto transform = compose(parent, solid_transform);
    const auto direction_refs = references_in(solid.arguments[2]);
    auto sweep = direction_refs.empty() ? Point3{0.0, 0.0, 1.0} : direction(direction_refs.front(), entities).value_or(Point3{0.0, 0.0, 1.0});
    sweep = normalize(sweep, {0.0, 0.0, 1.0});
    const auto depth = step_number(solid.arguments[3]).value_or(0.0);
    if (depth <= 0.0) return;
    const auto base = static_cast<std::uint32_t>(output.mesh.vertices.size());
    for (const auto& p : polygon) output.mesh.vertices.push_back(scale(transform_point(transform, p), unit_scale));
    for (const auto& p : polygon) output.mesh.vertices.push_back(scale(transform_point(transform, add(p, scale(sweep, depth))), unit_scale));
    const auto count = static_cast<std::uint32_t>(polygon.size());
    for (std::uint32_t i = 1; i + 1 < count; ++i) {
        output.mesh.indices.insert(output.mesh.indices.end(), {base, base + i + 1, base + i});
        output.mesh.indices.insert(output.mesh.indices.end(), {base + count, base + count + i, base + count + i + 1});
    }
    for (std::uint32_t i = 0; i < count; ++i) {
        const auto next = (i + 1) % count;
        output.mesh.indices.insert(output.mesh.indices.end(), {
            base + i, base + next, base + count + next,
            base + i, base + count + next, base + count + i,
        });
    }
    if (!profile_exact) {
        output.exact = false;
        output.stage = "extruded-profile-with-voids";
    } else if (output.stage == "source-mesh") {
        output.stage = "extruded-area-solid";
    }
}

void append_geometry_item(
    int id,
    const EntityIndex& entities,
    const Transform3& transform,
    double unit_scale,
    RecoveredMesh& output,
    PlacementCache& placement_cache,
    MappingCache& mapping_cache,
    std::unordered_set<int>& guard
);

void append_representation(
    int id,
    const EntityIndex& entities,
    const Transform3& transform,
    double unit_scale,
    RecoveredMesh& output,
    PlacementCache& placement_cache,
    MappingCache& mapping_cache,
    std::unordered_set<int>& guard
) {
    const auto found = entities.find(id);
    if (found == entities.end() || found->second.arguments.size() <= 3) return;
    for (const auto item_id : references_in(found->second.arguments[3])) {
        append_geometry_item(item_id, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
    }
}

void append_geometry_item(
    int id,
    const EntityIndex& entities,
    const Transform3& transform,
    double unit_scale,
    RecoveredMesh& output,
    PlacementCache& placement_cache,
    MappingCache& mapping_cache,
    std::unordered_set<int>& guard
) {
    if (!guard.insert(id).second) return;
    const auto found = entities.find(id);
    if (found == entities.end()) { guard.erase(id); return; }
    const auto& entity = found->second;

    if (entity.type == "IFCTRIANGULATEDFACESET" && entity.arguments.size() > 3) {
        const auto refs = references_in(entity.arguments[0]);
        if (!refs.empty()) append_indexed_faces(point_list(refs.front(), entities), nested_integer_tuples(entity.arguments[3]), transform, unit_scale, output.mesh);
        if (output.stage == "source-mesh") output.stage = "triangulated-face-set";
    } else if (entity.type == "IFCPOLYGONALFACESET" && entity.arguments.size() > 2) {
        const auto refs = references_in(entity.arguments[0]);
        std::vector<std::vector<int>> faces;
        for (const auto face_id : references_in(entity.arguments[2])) {
            const auto face = entities.find(face_id);
            if (face == entities.end() || face->second.arguments.empty()) continue;
            if (face->second.type == "IFCINDEXEDPOLYGONALFACE" || face->second.type == "IFCINDEXEDPOLYGONALFACEWITHVOIDS") {
                auto indices = integer_list(face->second.arguments[0]);
                if (indices.size() >= 3) faces.push_back(std::move(indices));
                if (face->second.type == "IFCINDEXEDPOLYGONALFACEWITHVOIDS") {
                    output.exact = false;
                    output.stage = "polygonal-face-set-with-voids";
                }
            }
        }
        if (!refs.empty()) append_indexed_faces(point_list(refs.front(), entities), faces, transform, unit_scale, output.mesh);
        if (output.stage == "source-mesh") output.stage = "polygonal-face-set";
    } else if (entity.type == "IFCEXTRUDEDAREASOLID") {
        append_extruded_area_solid(entity, entities, transform, unit_scale, output);
    } else if (entity.type == "IFCFACETEDBREP" || entity.type == "IFCMANIFOLDSOLIDBREP" || entity.type == "IFCADVANCEDBREP") {
        if (entity.type == "IFCADVANCEDBREP") {
            output.exact = false;
            output.stage = "advanced-brep-boundary";
        } else if (output.stage == "source-mesh") output.stage = "faceted-brep";
        if (!entity.arguments.empty()) {
            for (const auto child : references_in(entity.arguments[0])) append_geometry_item(child, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
        }
    } else if (entity.type == "IFCCLOSEDSHELL" || entity.type == "IFCOPENSHELL" || entity.type == "IFCCONNECTEDFACESET" || entity.type == "IFCSHELLBASEDSURFACEMODEL" || entity.type == "IFCFACEBASEDSURFACEMODEL") {
        for (const auto& argument : entity.arguments) {
            for (const auto child : references_in(argument)) append_geometry_item(child, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
        }
    } else if (entity.type == "IFCFACE" || entity.type == "IFCADVANCEDFACE") {
        if (entity.type == "IFCADVANCEDFACE") { output.exact = false; output.stage = "advanced-face-boundary"; }
        if (!entity.arguments.empty()) {
            bool emitted = false;
            for (const auto bound_id : references_in(entity.arguments[0])) {
                const auto bound = entities.find(bound_id);
                if (bound == entities.end() || bound->second.arguments.empty()) continue;
                if (bound->second.type != "IFCFACEOUTERBOUND" && bound->second.type != "IFCFACEBOUND") continue;
                if (bound->second.type == "IFCFACEBOUND" && emitted) {
                    output.exact = false;
                    output.stage = "brep-face-with-inner-bound";
                    continue;
                }
                const auto loop_ref = step_reference(bound->second.arguments[0]);
                if (!loop_ref.has_value()) continue;
                const auto loop = entities.find(*loop_ref);
                if (loop == entities.end() || loop->second.type != "IFCPOLYLOOP" || loop->second.arguments.empty()) continue;
                std::vector<Point3> polygon;
                for (const auto point_id : references_in(loop->second.arguments[0])) {
                    if (const auto p = cartesian_point(point_id, entities); p.has_value()) polygon.push_back(*p);
                }
                const bool reverse = bound->second.arguments.size() > 1 && bound->second.arguments[1].find(".F.") != std::string::npos;
                if (polygon.size() >= 3) { append_polygon(polygon, transform, unit_scale, output.mesh, reverse); emitted = true; }
            }
        }
    } else if (entity.type == "IFCMAPPEDITEM" && !entity.arguments.empty()) {
        const auto map_refs = references_in(entity.arguments[0]);
        if (!map_refs.empty()) {
            const auto map_id = map_refs.front();
            const auto map = entities.find(map_id);
            if (map != entities.end() && map->second.type == "IFCREPRESENTATIONMAP" && map->second.arguments.size() > 1) {
                RecoveredMesh local;
                if (const auto cached = mapping_cache.find(map_id); cached != mapping_cache.end()) {
                    local = cached->second;
                } else {
                    const auto representation_refs = references_in(map->second.arguments[1]);
                    if (!representation_refs.empty()) {
                        std::unordered_set<int> local_guard;
                        append_representation(representation_refs.front(), entities, Transform3{}, 1.0, local, placement_cache, mapping_cache, local_guard);
                    }
                    mapping_cache[map_id] = local;
                }
                auto source_origin = Transform3{};
                const auto source_refs = references_in(map->second.arguments[0]);
                if (!source_refs.empty()) {
                    std::unordered_set<int> placement_guard;
                    source_origin = placement_transform(source_refs.front(), entities, placement_cache, placement_guard);
                }
                auto target = Transform3{};
                if (entity.arguments.size() > 1) {
                    const auto target_refs = references_in(entity.arguments[1]);
                    if (!target_refs.empty()) target = cartesian_operator_transform(target_refs.front(), entities);
                }
                const auto mapped = compose(transform, compose(target, inverse(source_origin).value_or(Transform3{})));
                append_mesh_transformed(local.mesh, mapped, unit_scale, output.mesh);
                output.exact = output.exact && local.exact;
                if (!local.exact) output.stage = local.stage;
                else output.stage = "mapped-item";
                output.mapping_source_step_id = map_id;
            }
        }
    } else if (entity.type == "IFCREPRESENTATIONMAP" && entity.arguments.size() > 1) {
        const auto reps = references_in(entity.arguments[1]);
        if (!reps.empty()) append_representation(reps.front(), entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
    } else if (entity.type == "IFCBOOLEANRESULT" || entity.type == "IFCBOOLEANCLIPPINGRESULT") {
        if (entity.arguments.size() > 1) {
            output.exact = false;
            output.stage = "boolean-first-operand";
            for (const auto child : references_in(entity.arguments[1])) append_geometry_item(child, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
        }
    } else if (entity.type == "IFCCSGSOLID" && !entity.arguments.empty()) {
        output.exact = false;
        output.stage = "csg-tree-fallback";
        for (const auto child : references_in(entity.arguments[0])) append_geometry_item(child, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
    } else if (entity.type == "IFCSHAPEREPRESENTATION" || entity.type == "IFCREPRESENTATION") {
        append_representation(id, entities, transform, unit_scale, output, placement_cache, mapping_cache, guard);
    }
    guard.erase(id);
}

RecoveredMesh product_recovered_mesh(const StepEntity& product, const EntityIndex& entities, double unit_scale, PlacementCache& placement_cache, MappingCache& mapping_cache) {
    RecoveredMesh output;
    if (product.arguments.size() <= 6) return output;
    const auto shape_id = step_reference(product.arguments[6]);
    if (!shape_id.has_value()) return output;
    const auto shape = entities.find(*shape_id);
    if (shape == entities.end() || shape->second.type != "IFCPRODUCTDEFINITIONSHAPE" || shape->second.arguments.size() <= 2) return output;

    Transform3 product_transform;
    if (const auto placement_id = step_reference(product.arguments[5]); placement_id.has_value()) {
        std::unordered_set<int> guard;
        product_transform = placement_transform(*placement_id, entities, placement_cache, guard);
    }
    const auto representation_ids = references_in(shape->second.arguments[2]);
    std::vector<int> candidates;
    const auto add = [&candidates](int id) {
        if (std::find(candidates.begin(), candidates.end(), id) == candidates.end()) candidates.push_back(id);
    };
    for (const auto id : representation_ids) {
        const auto representation = entities.find(id);
        if (representation == entities.end()) continue;
        const auto identifier = representation->second.arguments.size() > 1 ? step_string(representation->second.arguments[1]) : std::string{};
        if (identifier == "Body" || identifier == "Body-Fallback" || identifier == "Facetation") add(id);
    }
    for (const auto id : representation_ids) add(id);
    for (const auto id : candidates) {
        RecoveredMesh candidate;
        std::unordered_set<int> guard;
        append_representation(id, entities, product_transform, unit_scale, candidate, placement_cache, mapping_cache, guard);
        if (!candidate.mesh.vertices.empty() && !candidate.mesh.indices.empty()) return candidate;
    }
    return output;
}

Bounds3 mesh_bounds(const MeshBuffer& mesh) {
    Bounds3 bounds;
    for (const auto& p : mesh.vertices) {
        if (!std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z)) continue;
        bounds.minimum.x = std::min(bounds.minimum.x, p.x);
        bounds.minimum.y = std::min(bounds.minimum.y, p.y);
        bounds.minimum.z = std::min(bounds.minimum.z, p.z);
        bounds.maximum.x = std::max(bounds.maximum.x, p.x);
        bounds.maximum.y = std::max(bounds.maximum.y, p.y);
        bounds.maximum.z = std::max(bounds.maximum.z, p.z);
        bounds.valid = true;
    }
    return bounds;
}

std::string source_guid(const StepEntity& entity) {
    return entity.arguments.empty() ? std::string{} : step_string(entity.arguments.front());
}

std::string product_name(const StepEntity& entity) {
    if (entity.arguments.size() > 2) {
        const auto name = step_string(entity.arguments[2]);
        if (!name.empty()) return name;
    }
    return entity.type + " " + std::to_string(entity.id);
}

void set_metadata(Element& element, std::string key, std::string value, MetadataValueKind kind = MetadataValueKind::Text) {
    if (value.empty()) return;
    element.metadata()[std::move(key)] = MetadataValue{.kind = kind, .value = std::move(value)};
}

bool metadata_true(const Element& element, std::string_view key) {
    const auto found = element.metadata().find(std::string(key));
    if (found == element.metadata().end()) return false;
    auto value = found->second.value;
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value == "true" || value == "1" || value == "yes";
}

void mark_source_identity(Element& element, const StepEntity& source, bool exact_geometry, std::string stage, int mapping_source_step_id = 0) {
    set_metadata(element, "ifc_guid", source_guid(source));
    set_metadata(element, "ifc_entity", source.type);
    set_metadata(element, "ifc_step_id", std::to_string(source.id), MetadataValueKind::Number);
    if (source.arguments.size() > 2) set_metadata(element, "ifc_source_name", step_string(source.arguments[2]));
    if (source.arguments.size() > 4) set_metadata(element, "ifc_source_object_type", step_string(source.arguments[4]));
    if (source.arguments.size() > 5) {
        if (const auto placement = step_reference(source.arguments[5]); placement.has_value()) set_metadata(element, "ifc_placement_step_id", std::to_string(*placement), MetadataValueKind::Number);
    }
    if (source.arguments.size() > 6) {
        if (const auto representation = step_reference(source.arguments[6]); representation.has_value()) set_metadata(element, "ifc_representation_step_id", std::to_string(*representation), MetadataValueKind::Number);
    }
    if (mapping_source_step_id != 0) set_metadata(element, "ifc_mapping_source_step_id", std::to_string(mapping_source_step_id), MetadataValueKind::Number);
    set_metadata(element, "ifc_exact_geometry", exact_geometry ? "true" : "false", MetadataValueKind::Boolean);
    set_metadata(element, "ifc_geometry_stage", std::move(stage));
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
    case ElementKind::Room: return 0;
    }
    return 0;
}

double level_elevation(const Document& document, ElementId level_id) {
    const auto* level = document.find_ptr(level_id);
    return level != nullptr && level->level() != nullptr ? level->level()->elevation_meters : 0.0;
}

MeshBuffer relative_to_level(MeshBuffer mesh, double elevation) {
    for (auto& p : mesh.vertices) p.z -= elevation;
    return mesh;
}

bool assign_mesh(Document& document, Element& element, const StepEntity& source, RecoveredMesh recovered) {
    if (recovered.mesh.vertices.empty() || recovered.mesh.indices.empty()) return false;
    auto mesh = relative_to_level(std::move(recovered.mesh), level_elevation(document, element_level_id(element)));
    switch (element.kind()) {
    case ElementKind::Wall: element.wall()->geometry.mesh = std::move(mesh); element.wall()->geometry.dirty = false; break;
    case ElementKind::Door: element.door()->mesh = std::move(mesh); break;
    case ElementKind::Window: element.window()->mesh = std::move(mesh); break;
    case ElementKind::Slab: element.slab()->mesh = std::move(mesh); element.slab()->generated_geometry_dirty = false; break;
    case ElementKind::Roof: element.roof()->mesh = std::move(mesh); element.roof()->generated_geometry_dirty = false; break;
    case ElementKind::Column: element.column()->mesh = std::move(mesh); element.column()->generated_geometry_dirty = false; break;
    case ElementKind::Beam: element.beam()->mesh = std::move(mesh); element.beam()->generated_geometry_dirty = false; break;
    case ElementKind::Stair: element.stair()->mesh = std::move(mesh); element.stair()->generated_geometry_dirty = false; break;
    case ElementKind::Proxy: element.proxy()->mesh = std::move(mesh); break;
    case ElementKind::Level:
    case ElementKind::Room: return false;
    }
    mark_source_identity(element, source, recovered.exact, recovered.stage, recovered.mapping_source_step_id);
    return true;
}

bool is_physical_product(const StepEntity& entity, const EntityIndex& entities) {
    if (entity.type.rfind("IFC", 0) != 0 || entity.type.rfind("IFCREL", 0) == 0 || entity.arguments.size() <= 6) return false;
    if (entity.type == "IFCSPACE" || entity.type == "IFCANNOTATION" || entity.type == "IFCOPENINGELEMENT" || entity.type == "IFCVOIDINGFEATURE" || entity.type == "IFCBUILDINGSTOREY" || entity.type == "IFCBUILDING" || entity.type == "IFCSITE" || entity.type == "IFCPROJECT") return false;
    const auto shape_id = step_reference(entity.arguments[6]);
    if (!shape_id.has_value()) return false;
    const auto shape = entities.find(*shape_id);
    return shape != entities.end() && shape->second.type == "IFCPRODUCTDEFINITIONSHAPE";
}

GuidIndex build_guid_index(const Document& document) {
    GuidIndex result;
    for (const auto& element : document.elements()) {
        const auto found = element.metadata().find("ifc_guid");
        if (found != element.metadata().end() && !found->second.value.empty()) result.emplace(found->second.value, element.id());
    }
    return result;
}

LevelIndex build_level_index(const Document& document) {
    LevelIndex result;
    for (const auto& element : document.elements()) {
        if (const auto* level = element.level(); level != nullptr) result.emplace_back(element.id(), level->elevation_meters);
    }
    std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) { return a.second < b.second; });
    return result;
}

ElementId nearest_level(const LevelIndex& levels, double elevation) {
    if (levels.empty()) return 0;
    auto best = levels.front();
    auto distance = std::abs(best.second - elevation);
    for (const auto& current : levels) {
        const auto current_distance = std::abs(current.second - elevation);
        if (current_distance < distance) { best = current; distance = current_distance; }
    }
    return best.first;
}

std::unordered_map<int, int> build_spatial_parent_index(const std::vector<StepEntity>& parsed) {
    std::unordered_map<int, int> parent;
    for (const auto& relation : parsed) {
        if (relation.type == "IFCRELCONTAINEDINSPATIALSTRUCTURE" && relation.arguments.size() > 5) {
            const auto parent_ref = step_reference(relation.arguments[5]);
            if (!parent_ref.has_value()) continue;
            for (const auto child : references_in(relation.arguments[4])) parent[child] = *parent_ref;
        } else if ((relation.type == "IFCRELAGGREGATES" || relation.type == "IFCRELDECOMPOSES" || relation.type == "IFCRELNESTS") && relation.arguments.size() > 5) {
            const auto parent_ref = step_reference(relation.arguments[4]);
            if (!parent_ref.has_value()) continue;
            for (const auto child : references_in(relation.arguments[5])) parent.emplace(child, *parent_ref);
        }
    }
    return parent;
}

std::optional<int> storey_for_product(int product_id, const EntityIndex& entities, const std::unordered_map<int, int>& parents) {
    auto current = product_id;
    std::unordered_set<int> visited;
    for (std::size_t depth = 0; depth < 64 && visited.insert(current).second; ++depth) {
        const auto entity = entities.find(current);
        if (entity != entities.end() && (entity->second.type == "IFCBUILDINGSTOREY" || entity->second.type == "IFCLEVEL")) return current;
        const auto parent = parents.find(current);
        if (parent == parents.end()) break;
        current = parent->second;
    }
    return std::nullopt;
}

std::unordered_map<int, ElementId> map_storeys_to_levels(const std::vector<StepEntity>& parsed, const EntityIndex& entities, Document& document, PlacementCache& placement_cache, double unit_scale) {
    std::unordered_map<int, ElementId> result;
    auto levels = build_level_index(document);
    if (levels.empty()) {
        const auto id = document.create_level("Level 1", 0.0, 3.0);
        levels.emplace_back(id, 0.0);
    }
    for (const auto& entity : parsed) {
        if (entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCLEVEL") continue;
        double elevation = 0.0;
        bool placement_known = false;
        if (entity.arguments.size() > 5) {
            if (const auto placement_id = step_reference(entity.arguments[5]); placement_id.has_value()) {
                std::unordered_set<int> guard;
                const auto placement = placement_transform(*placement_id, entities, placement_cache, guard);
                elevation = placement.origin.z * unit_scale;
                placement_known = true;
            }
        }
        if (!placement_known) {
            for (auto it = entity.arguments.rbegin(); it != entity.arguments.rend(); ++it) {
                if (const auto value = step_number(*it); value.has_value()) { elevation = *value * unit_scale; break; }
            }
        }
        const auto level_id = nearest_level(levels, elevation);
        if (level_id != 0) {
            result[entity.id] = level_id;
            if (auto* level = document.find_ptr(level_id); level != nullptr) {
                const auto key = "ifc_storey_step_ids";
                const auto existing = level->metadata().find(key);
                auto value = existing == level->metadata().end() ? std::string{} : existing->second.value;
                if (!value.empty()) value += ",";
                value += std::to_string(entity.id);
                set_metadata(*level, key, value);
                const auto guid = source_guid(entity);
                if (!guid.empty()) set_metadata(*level, "ifc_storey_guid_" + std::to_string(entity.id), guid);
            }
        }
    }
    return result;
}

void add_issue(IfcExchangeReport* report, const StepEntity& source, std::string stage, std::string message) {
    if (report == nullptr) return;
    report->issues.push_back(IfcImportIssue{
        .step_id = source.id,
        .global_id = source_guid(source),
        .entity_type = source.type,
        .stage = std::move(stage),
        .message = std::move(message),
    });
}

std::string entity_display_name(int id, const EntityIndex& entities, std::unordered_set<int>& guard) {
    if (!guard.insert(id).second) return {};
    const auto found = entities.find(id);
    if (found == entities.end()) { guard.erase(id); return {}; }
    const auto& entity = found->second;
    std::vector<std::string> names;
    if (entity.type == "IFCMATERIAL" && !entity.arguments.empty()) {
        const auto name = step_string(entity.arguments[0]);
        if (!name.empty()) names.push_back(name);
    } else if (entity.type == "IFCCLASSIFICATIONREFERENCE") {
        for (std::size_t i = 0; i < std::min<std::size_t>(3, entity.arguments.size()); ++i) {
            const auto value = step_string(entity.arguments[i]);
            if (!value.empty()) names.push_back(value);
        }
    } else {
        for (const auto& arg : entity.arguments) {
            for (const auto child : references_in(arg)) {
                const auto value = entity_display_name(child, entities, guard);
                if (!value.empty() && std::find(names.begin(), names.end(), value) == names.end()) names.push_back(value);
            }
        }
        if (names.empty()) {
            for (const auto& arg : entity.arguments) {
                const auto value = step_string(arg);
                if (!value.empty()) { names.push_back(value); break; }
            }
        }
    }
    guard.erase(id);
    std::string joined;
    for (const auto& name : names) {
        if (!joined.empty()) joined += " | ";
        joined += name;
        if (joined.size() > 512) break;
    }
    return joined;
}

std::size_t attach_metadata_relations(Document& document, const std::vector<StepEntity>& parsed, const EntityIndex& entities, const GuidIndex& guid_index) {
    std::unordered_map<int, std::vector<std::pair<std::string, std::string>>> property_sets;
    std::unordered_map<int, std::vector<std::pair<std::string, std::string>>> quantity_sets;

    for (const auto& set : parsed) {
        if (set.type == "IFCPROPERTYSET" && set.arguments.size() > 4) {
            const auto set_name = metadata_key_part(step_string(set.arguments[2]));
            auto& values = property_sets[set.id];
            for (const auto property_id : references_in(set.arguments[4])) {
                const auto property = entities.find(property_id);
                if (property == entities.end() || property->second.arguments.empty()) continue;
                const auto& item = property->second;
                if (item.type == "IFCPROPERTYSINGLEVALUE" && item.arguments.size() > 2) {
                    const auto name = metadata_key_part(step_string(item.arguments[0]));
                    const auto value = untyped_value(item.arguments[2]);
                    if (!value.empty()) values.emplace_back("ifc_pset." + set_name + "." + name, value);
                }
            }
        } else if (set.type == "IFCELEMENTQUANTITY" && set.arguments.size() > 5) {
            const auto set_name = metadata_key_part(step_string(set.arguments[2]));
            auto& values = quantity_sets[set.id];
            for (const auto quantity_id : references_in(set.arguments[5])) {
                const auto quantity = entities.find(quantity_id);
                if (quantity == entities.end() || quantity->second.arguments.size() <= 3) continue;
                if (quantity->second.type.rfind("IFCQUANTITY", 0) != 0) continue;
                const auto name = metadata_key_part(step_string(quantity->second.arguments[0]));
                const auto value = untyped_value(quantity->second.arguments[3]);
                if (!value.empty()) values.emplace_back("ifc_qto." + set_name + "." + name, value);
            }
        }
    }

    std::size_t imported = 0;
    const auto element_for_source_id = [&](int source_id) -> Element* {
        const auto source = entities.find(source_id);
        if (source == entities.end()) return nullptr;
        const auto guid = source_guid(source->second);
        if (guid.empty()) return nullptr;
        const auto target = guid_index.find(guid);
        return target == guid_index.end() ? nullptr : document.find_ptr(target->second);
    };

    for (const auto& relation : parsed) {
        if (relation.type == "IFCRELDEFINESBYPROPERTIES" && relation.arguments.size() > 5) {
            const auto definition = step_reference(relation.arguments[5]);
            if (!definition.has_value()) continue;
            const auto pset = property_sets.find(*definition);
            const auto qto = quantity_sets.find(*definition);
            if (pset == property_sets.end() && qto == quantity_sets.end()) continue;
            for (const auto object_id : references_in(relation.arguments[4])) {
                auto* element = element_for_source_id(object_id);
                if (element == nullptr) continue;
                if (pset != property_sets.end()) for (const auto& [key, value] : pset->second) { set_metadata(*element, key, value); ++imported; }
                if (qto != quantity_sets.end()) for (const auto& [key, value] : qto->second) { set_metadata(*element, key, value, MetadataValueKind::Number); ++imported; }
            }
        } else if (relation.type == "IFCRELASSOCIATESMATERIAL" && relation.arguments.size() > 5) {
            const auto material = step_reference(relation.arguments[5]);
            if (!material.has_value()) continue;
            std::unordered_set<int> guard;
            const auto value = entity_display_name(*material, entities, guard);
            if (value.empty()) continue;
            for (const auto object_id : references_in(relation.arguments[4])) {
                if (auto* element = element_for_source_id(object_id); element != nullptr) { set_metadata(*element, "ifc_material", value); ++imported; }
            }
        } else if (relation.type == "IFCRELASSOCIATESCLASSIFICATION" && relation.arguments.size() > 5) {
            const auto classification = step_reference(relation.arguments[5]);
            if (!classification.has_value()) continue;
            std::unordered_set<int> guard;
            const auto value = entity_display_name(*classification, entities, guard);
            if (value.empty()) continue;
            for (const auto object_id : references_in(relation.arguments[4])) {
                if (auto* element = element_for_source_id(object_id); element != nullptr) { set_metadata(*element, "ifc_classification", value); ++imported; }
            }
        } else if (relation.type == "IFCRELVOIDSELEMENT" && relation.arguments.size() > 5) {
            const auto host = step_reference(relation.arguments[4]);
            const auto opening = step_reference(relation.arguments[5]);
            if (!host.has_value() || !opening.has_value()) continue;
            if (auto* element = element_for_source_id(*host); element != nullptr) {
                set_metadata(*element, "ifc_void_opening_step_" + std::to_string(*opening), std::to_string(*opening), MetadataValueKind::Number);
                const auto opening_entity = entities.find(*opening);
                if (opening_entity != entities.end()) set_metadata(*element, "ifc_void_opening_guid_" + std::to_string(*opening), source_guid(opening_entity->second));
                ++imported;
            }
        } else if (relation.type == "IFCRELFILLSELEMENT" && relation.arguments.size() > 5) {
            const auto opening = step_reference(relation.arguments[4]);
            const auto fill = step_reference(relation.arguments[5]);
            if (!opening.has_value() || !fill.has_value()) continue;
            if (auto* element = element_for_source_id(*fill); element != nullptr) {
                set_metadata(*element, "ifc_fills_opening_step_id", std::to_string(*opening), MetadataValueKind::Number);
                for (const auto& void_relation : parsed) {
                    if (void_relation.type != "IFCRELVOIDSELEMENT" || void_relation.arguments.size() <= 5) continue;
                    const auto related_opening = step_reference(void_relation.arguments[5]);
                    if (!related_opening.has_value() || *related_opening != *opening) continue;
                    const auto host = step_reference(void_relation.arguments[4]);
                    if (!host.has_value()) continue;
                    const auto host_entity = entities.find(*host);
                    if (host_entity != entities.end()) {
                        set_metadata(*element, "ifc_host_step_id", std::to_string(*host), MetadataValueKind::Number);
                        set_metadata(*element, "ifc_host_guid", source_guid(host_entity->second));
                    }
                    break;
                }
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
    // The legacy reader remains the semantic layer. This production stage is
    // intentionally monotonic: exact geometry already produced by the legacy
    // reader is never replaced by an approximate fallback.
    auto document = import_ifc_legacy(path, std::move(document_name), report);

    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to reopen IFC import path");
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const auto contents = buffer.str();
    if (contents.find("/* TBE_DOCUMENT_JSON_HEX ") != std::string::npos) return document;

    const auto parsed = parse_step_entities(contents);
    EntityIndex entities;
    entities.reserve(parsed.size());
    for (const auto& entity : parsed) entities.emplace(entity.id, entity);

    const auto unit_scale = length_scale(parsed);
    PlacementCache placement_cache;
    placement_cache.reserve(parsed.size() / 8 + 16);
    MappingCache mapping_cache;
    mapping_cache.reserve(parsed.size() / 16 + 16);
    auto guid_index = build_guid_index(document);
    const auto spatial_parents = build_spatial_parent_index(parsed);
    const auto storey_levels = map_storeys_to_levels(parsed, entities, document, placement_cache, unit_scale);
    auto levels = build_level_index(document);

    std::unordered_set<std::string> source_guids;
    std::size_t source_products = 0;
    std::size_t native_semantic = 0;
    std::size_t exact_mesh = 0;
    std::size_t recovered_existing = 0;
    std::size_t recovered_proxies = 0;
    std::size_t approximate = 0;
    std::size_t failed = 0;
    std::size_t source_without_guid = 0;
    std::size_t duplicate_guid = 0;
    std::size_t exact_preserved = 0;

    for (const auto& source : parsed) {
        if (!is_physical_product(source, entities)) continue;
        ++source_products;
        const auto guid = source_guid(source);
        if (guid.empty()) ++source_without_guid;
        else if (!source_guids.insert(guid).second) ++duplicate_guid;

        Element* existing = nullptr;
        if (!guid.empty()) {
            const auto found = guid_index.find(guid);
            if (found != guid_index.end()) existing = document.find_ptr(found->second);
        }

        // Critical invariant: a later recovery stage must never downgrade a
        // placement-correct exact mesh that the semantic importer already got
        // right. The previous pipeline violated this for IfcMappedItem and was
        // able to scatter furniture/windows back to map-source coordinates.
        if (existing != nullptr && metadata_true(*existing, "ifc_exact_geometry")) {
            ++native_semantic;
            ++exact_mesh;
            ++exact_preserved;
            const auto current_stage = existing->metadata().find("ifc_geometry_stage");
            mark_source_identity(
                *existing,
                source,
                true,
                current_stage == existing->metadata().end() ? "legacy-exact-preserved" : current_stage->second.value);
            continue;
        }

        auto recovered = product_recovered_mesh(source, entities, unit_scale, placement_cache, mapping_cache);
        const bool has_mesh = !recovered.mesh.vertices.empty() && !recovered.mesh.indices.empty();

        if (existing != nullptr) {
            ++native_semantic;
            if (has_mesh && assign_mesh(document, *existing, source, recovered)) {
                ++recovered_existing;
                if (recovered.exact) ++exact_mesh; else ++approximate;
            } else {
                mark_source_identity(*existing, source, false, "native-semantic-no-source-mesh");
                ++approximate;
                add_issue(report, source, "geometry-recovery", "Semantic element preserved, but no supported source mesh representation was recovered.");
            }
            continue;
        }

        if (!has_mesh) {
            ++failed;
            add_issue(report, source, "geometry-recovery", "No semantic element or supported source geometry could be recovered.");
            continue;
        }

        const auto bounds = mesh_bounds(recovered.mesh);
        if (!bounds.valid) {
            ++failed;
            add_issue(report, source, "geometry-bounds", "Recovered source mesh has no finite bounds.");
            continue;
        }

        ElementId level_id{};
        if (const auto storey = storey_for_product(source.id, entities, spatial_parents); storey.has_value()) {
            const auto mapped = storey_levels.find(*storey);
            if (mapped != storey_levels.end()) level_id = mapped->second;
        }
        if (level_id == 0) level_id = nearest_level(levels, bounds.minimum.z);
        if (level_id == 0) {
            level_id = document.create_level("Level 1", 0.0, 3.0);
            levels = build_level_index(document);
        }
        const auto elevation = level_elevation(document, level_id);
        const auto width = std::max(0.01, bounds.maximum.x - bounds.minimum.x);
        const auto depth = std::max(0.01, bounds.maximum.y - bounds.minimum.y);
        const auto height = std::max(0.01, bounds.maximum.z - bounds.minimum.z);
        const auto center = Point2{(bounds.minimum.x + bounds.maximum.x) * 0.5, (bounds.minimum.y + bounds.maximum.y) * 0.5};
        const auto id = document.create_proxy(
            product_name(source), level_id, center, width, depth, height,
            relative_to_level(std::move(recovered.mesh), elevation));
        if (auto* created = document.find_ptr(id); created != nullptr) {
            mark_source_identity(*created, source, recovered.exact, recovered.stage, recovered.mapping_source_step_id);
            if (const auto storey = storey_for_product(source.id, entities, spatial_parents); storey.has_value()) {
                set_metadata(*created, "ifc_storey_step_id", std::to_string(*storey), MetadataValueKind::Number);
            }
            if (!guid.empty()) guid_index[guid] = id;
        }
        ++recovered_proxies;
        if (recovered.exact) ++exact_mesh; else ++approximate;
    }

    const auto imported_metadata = attach_metadata_relations(document, parsed, entities, guid_index);

    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        report->source_physical_products = source_products;
        report->native_semantic_products = native_semantic;
        report->exact_mesh_products = exact_mesh;
        report->recovered_proxy_products = recovered_proxies;
        report->approximate_products = approximate;
        report->failed_geometry_products = failed;
        report->source_products_without_guid = source_without_guid;
        report->duplicate_source_identity_products = duplicate_guid;
        report->silent_dropped_products = 0;
        report->imported_property_values = imported_metadata;
        report->warnings.push_back(
            "IFC production coverage: source=" + std::to_string(source_products) +
            ", native=" + std::to_string(native_semantic) +
            ", exact=" + std::to_string(exact_mesh) +
            ", proxy=" + std::to_string(recovered_proxies) +
            ", approximate=" + std::to_string(approximate) +
            ", failed=" + std::to_string(failed) +
            ", exact_preserved=" + std::to_string(exact_preserved) +
            ", silent_dropped=0.");
        report->warnings.push_back(
            "IFC placement contract: recursive IfcLocalPlacement + Axis2Placement, mapped source/target transforms, spatial-storey containment and level-relative meshes are applied exactly once.");
        if (recovered_existing != 0 || recovered_proxies != 0) {
            report->warnings.push_back(
                "IFC source recovery restored geometry for " + std::to_string(recovered_existing) +
                " semantic elements and " + std::to_string(recovered_proxies) + " additional physical products.");
        }
    }
    return document;
}

} // namespace tbe::core
