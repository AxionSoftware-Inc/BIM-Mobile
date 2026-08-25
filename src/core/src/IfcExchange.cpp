#include "tbe/core/IfcExchange.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <unordered_set>
#include <unordered_map>
#include <utility>

namespace tbe::core {

namespace {

std::string hex_encode(std::string_view value) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (const auto ch : value) {
        out << std::setw(2) << static_cast<unsigned int>(static_cast<unsigned char>(ch));
    }
    return out.str();
}

std::string hex_decode(std::string_view value) {
    if ((value.size() % 2) != 0) throw std::invalid_argument("invalid IFC semantic sidecar encoding");
    std::string output;
    output.reserve(value.size() / 2);
    for (std::size_t index = 0; index < value.size(); index += 2) {
        unsigned int byte{};
        std::istringstream input{std::string(value.substr(index, 2))};
        input >> std::hex >> byte;
        if (input.fail()) throw std::invalid_argument("invalid IFC semantic sidecar byte");
        output.push_back(static_cast<char>(byte));
    }
    return output;
}

std::string guid_for(std::size_t index) {
    std::ostringstream out;
    out << "'TBE" << std::setw(20) << std::setfill('0') << index << "'";
    return out.str();
}

std::string ifc_name(const Element& element) {
    return hex_encode(element.name());
}

std::string entity_for(ElementKind kind) {
    switch (kind) {
    case ElementKind::Level: return "IFCBUILDINGSTOREY";
    case ElementKind::Wall: return "IFCWALLSTANDARDCASE";
    case ElementKind::Door: return "IFCDOOR";
    case ElementKind::Window: return "IFCWINDOW";
    case ElementKind::Room: return "IFCSPACE";
    case ElementKind::Slab: return "IFCSLAB";
    case ElementKind::Roof: return "IFCROOF";
    case ElementKind::Column: return "IFCCOLUMN";
    case ElementKind::Beam: return "IFCBEAM";
    case ElementKind::Stair: return "IFCSTAIRFLIGHT";
    case ElementKind::Proxy: return "IFCBUILDINGELEMENTPROXY";
    }
    return "IFCBUILDINGELEMENTPROXY";
}

struct StepEntity {
    int id{};
    std::string type{};
    std::vector<std::string> arguments{};
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

std::optional<int> step_reference(const std::string& value);
std::optional<double> step_number(const std::string& value);

struct IfcTransform {
    std::array<std::array<double, 3>, 3> basis{};
    Point3 origin{};
};

IfcTransform identity_transform() {
    return IfcTransform{
        .basis = {{{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}}},
        .origin = {},
    };
}

Point3 point_add(Point3 left, Point3 right) {
    return {.x = left.x + right.x, .y = left.y + right.y, .z = left.z + right.z};
}

Point3 point_subtract(Point3 left, Point3 right) {
    return {.x = left.x - right.x, .y = left.y - right.y, .z = left.z - right.z};
}

Point3 point_scale(Point3 point, double scale) {
    return {.x = point.x * scale, .y = point.y * scale, .z = point.z * scale};
}

double point_dot(Point3 left, Point3 right) {
    return left.x * right.x + left.y * right.y + left.z * right.z;
}

Point3 point_cross(Point3 left, Point3 right) {
    return {
        .x = left.y * right.z - left.z * right.y,
        .y = left.z * right.x - left.x * right.z,
        .z = left.x * right.y - left.y * right.x,
    };
}

Point3 point_normalize(Point3 point, Point3 fallback) {
    const auto length = std::sqrt(point_dot(point, point));
    if (length <= 1.0e-12) return fallback;
    return point_scale(point, 1.0 / length);
}

Point3 transform_vector(const IfcTransform& transform, Point3 point) {
    return {
        .x = transform.basis[0][0] * point.x + transform.basis[0][1] * point.y + transform.basis[0][2] * point.z,
        .y = transform.basis[1][0] * point.x + transform.basis[1][1] * point.y + transform.basis[1][2] * point.z,
        .z = transform.basis[2][0] * point.x + transform.basis[2][1] * point.y + transform.basis[2][2] * point.z,
    };
}

Point3 transform_point(const IfcTransform& transform, Point3 point) {
    return point_add(transform_vector(transform, point), transform.origin);
}

IfcTransform compose_transform(const IfcTransform& left, const IfcTransform& right) {
    IfcTransform result = identity_transform();
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

std::optional<IfcTransform> inverse_transform(const IfcTransform& transform) {
    const auto& m = transform.basis;
    const auto determinant =
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if (std::abs(determinant) <= 1.0e-12) return std::nullopt;
    const auto inverse_determinant = 1.0 / determinant;
    IfcTransform inverse = identity_transform();
    inverse.basis = {{
        {(m[1][1] * m[2][2] - m[1][2] * m[2][1]) * inverse_determinant,
         (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * inverse_determinant,
         (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * inverse_determinant},
        {(m[1][2] * m[2][0] - m[1][0] * m[2][2]) * inverse_determinant,
         (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * inverse_determinant,
         (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * inverse_determinant},
        {(m[1][0] * m[2][1] - m[1][1] * m[2][0]) * inverse_determinant,
         (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * inverse_determinant,
         (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * inverse_determinant},
    }};
    inverse.origin = point_scale(transform_vector(inverse, transform.origin), -1.0);
    return inverse;
}

std::vector<int> references_in(std::string_view value) {
    std::vector<int> references;
    for (std::size_t index = 0; index < value.size(); ++index) {
        if (value[index] != '#') continue;
        const auto start = index + 1;
        auto end = start;
        while (end < value.size() && std::isdigit(static_cast<unsigned char>(value[end])) != 0) ++end;
        if (end == start) continue;
        references.push_back(static_cast<int>(std::strtol(std::string(value.substr(start, end - start)).c_str(), nullptr, 10)));
        index = end - 1;
    }
    return references;
}

std::optional<Point3> point3_from_entity(const StepEntity& entity) {
    if (entity.type != "IFCCARTESIANPOINT" || entity.arguments.empty()) return std::nullopt;
    const auto& tuple = entity.arguments.front();
    if (tuple.size() < 2 || tuple.front() != '(' || tuple.back() != ')') return std::nullopt;
    const auto values = split_step_arguments(std::string_view(tuple).substr(1, tuple.size() - 2));
    if (values.size() < 2) return std::nullopt;
    return Point3{
        .x = step_number(values[0]).value_or(0.0),
        .y = step_number(values[1]).value_or(0.0),
        .z = values.size() > 2 ? step_number(values[2]).value_or(0.0) : 0.0,
    };
}

std::optional<Point3> direction3_from_entity(const StepEntity& entity) {
    if (entity.type != "IFCDIRECTION" || entity.arguments.empty()) return std::nullopt;
    const auto& tuple = entity.arguments.front();
    if (tuple.size() < 2 || tuple.front() != '(' || tuple.back() != ')') return std::nullopt;
    const auto values = split_step_arguments(std::string_view(tuple).substr(1, tuple.size() - 2));
    if (values.size() < 2) return std::nullopt;
    return Point3{
        .x = step_number(values[0]).value_or(0.0),
        .y = step_number(values[1]).value_or(0.0),
        .z = values.size() > 2 ? step_number(values[2]).value_or(0.0) : 0.0,
    };
}

std::optional<Point3> point3_by_id(
    int id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(id);
    return found == entities.end() ? std::nullopt : point3_from_entity(found->second);
}

std::optional<Point3> direction3_by_id(
    int id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(id);
    return found == entities.end() ? std::nullopt : direction3_from_entity(found->second);
}

IfcTransform axis_placement_transform(
    int placement_id,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, IfcTransform>& cache,
    std::vector<int>& recursion_guard
) {
    if (const auto found = cache.find(placement_id); found != cache.end()) return found->second;
    if (std::find(recursion_guard.begin(), recursion_guard.end(), placement_id) != recursion_guard.end()) return identity_transform();
    const auto found = entities.find(placement_id);
    if (found == entities.end()) return identity_transform();
    recursion_guard.push_back(placement_id);
    auto result = identity_transform();
    const auto& entity = found->second;
    if (entity.type == "IFCLOCALPLACEMENT" && entity.arguments.size() > 1) {
        if (const auto parent = step_reference(entity.arguments[0]); parent.has_value()) {
            result = axis_placement_transform(*parent, entities, cache, recursion_guard);
        }
        if (const auto relative = step_reference(entity.arguments[1]); relative.has_value()) {
            result = compose_transform(result, axis_placement_transform(*relative, entities, cache, recursion_guard));
        }
    } else if (entity.type == "IFCAXIS2PLACEMENT3D" || entity.type == "IFCAXIS2PLACEMENT2D") {
        if (!entity.arguments.empty()) {
            if (const auto location = step_reference(entity.arguments[0]); location.has_value()) {
                result.origin = point3_by_id(*location, entities).value_or(Point3{});
            }
        }
        auto x_axis = Point3{1.0, 0.0, 0.0};
        auto z_axis = Point3{0.0, 0.0, 1.0};
        if (entity.type == "IFCAXIS2PLACEMENT3D") {
            if (entity.arguments.size() > 1) {
                if (const auto axis = step_reference(entity.arguments[1]); axis.has_value()) {
                    z_axis = direction3_by_id(*axis, entities).value_or(z_axis);
                }
            }
            if (entity.arguments.size() > 2) {
                if (const auto ref = step_reference(entity.arguments[2]); ref.has_value()) {
                    x_axis = direction3_by_id(*ref, entities).value_or(x_axis);
                }
            }
        } else {
            z_axis = {0.0, 0.0, 1.0};
            if (entity.arguments.size() > 1) {
                if (const auto ref = step_reference(entity.arguments[1]); ref.has_value()) {
                    const auto direction = direction3_by_id(*ref, entities).value_or(Point3{1.0, 0.0, 0.0});
                    x_axis = {direction.x, direction.y, 0.0};
                }
            }
        }
        z_axis = point_normalize(z_axis, {0.0, 0.0, 1.0});
        x_axis = point_subtract(x_axis, point_scale(z_axis, point_dot(x_axis, z_axis)));
        x_axis = point_normalize(x_axis, {1.0, 0.0, 0.0});
        const auto y_axis = point_normalize(point_cross(z_axis, x_axis), {0.0, 1.0, 0.0});
        result.basis = {{{x_axis.x, y_axis.x, z_axis.x}, {x_axis.y, y_axis.y, z_axis.y}, {x_axis.z, y_axis.z, z_axis.z}}};
    }
    recursion_guard.pop_back();
    cache[placement_id] = result;
    return result;
}

IfcTransform cartesian_operator_transform(
    int operator_id,
    const std::unordered_map<int, StepEntity>& entities
) {
    const auto found = entities.find(operator_id);
    if (found == entities.end() || found->second.type != "IFCCARTESIANTRANSFORMATIONOPERATOR3D") return identity_transform();
    const auto& entity = found->second;
    auto result = identity_transform();
    if (entity.arguments.size() > 2) {
        if (const auto origin = step_reference(entity.arguments[2]); origin.has_value()) {
            result.origin = point3_by_id(*origin, entities).value_or(Point3{});
        }
    }
    auto x_axis = Point3{1.0, 0.0, 0.0};
    auto y_axis = Point3{0.0, 1.0, 0.0};
    auto z_axis = Point3{0.0, 0.0, 1.0};
    if (!entity.arguments.empty()) {
        if (const auto axis = step_reference(entity.arguments[0]); axis.has_value()) x_axis = direction3_by_id(*axis, entities).value_or(x_axis);
    }
    if (entity.arguments.size() > 1) {
        if (const auto axis = step_reference(entity.arguments[1]); axis.has_value()) y_axis = direction3_by_id(*axis, entities).value_or(y_axis);
    }
    if (entity.arguments.size() > 4) {
        if (const auto axis = step_reference(entity.arguments[4]); axis.has_value()) z_axis = direction3_by_id(*axis, entities).value_or(z_axis);
    }
    x_axis = point_normalize(x_axis, {1.0, 0.0, 0.0});
    z_axis = point_normalize(z_axis, {0.0, 0.0, 1.0});
    y_axis = point_normalize(point_cross(z_axis, x_axis), y_axis);
    const auto scale = entity.arguments.size() > 3 ? step_number(entity.arguments[3]).value_or(1.0) : 1.0;
    const auto scale2 = entity.arguments.size() > 5 ? step_number(entity.arguments[5]).value_or(scale) : scale;
    const auto scale3 = entity.arguments.size() > 6 ? step_number(entity.arguments[6]).value_or(scale) : scale;
    result.basis = {{{x_axis.x * scale, y_axis.x * scale2, z_axis.x * scale3},
                     {x_axis.y * scale, y_axis.y * scale2, z_axis.y * scale3},
                     {x_axis.z * scale, y_axis.z * scale2, z_axis.z * scale3}}};
    return result;
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

std::string step_string(const std::string& value) {
    if (value.size() >= 2 && value.front() == '\'' && value.back() == '\'') {
        std::string decoded = value.substr(1, value.size() - 2);
        std::string output;
        for (std::size_t index = 0; index < decoded.size(); ++index) {
            if (decoded[index] == '\'' && index + 1 < decoded.size() && decoded[index + 1] == '\'') ++index;
            output.push_back(decoded[index]);
        }
        return output;
    }
    return {};
}

std::optional<int> step_reference(const std::string& value) {
    if (value.size() < 2 || value.front() != '#') return std::nullopt;
    char* end = nullptr;
    const auto id = std::strtol(value.c_str() + 1, &end, 10);
    if (end == value.c_str() + 1) return std::nullopt;
    return static_cast<int>(id);
}

std::optional<double> step_number(const std::string& value) {
    if (value.empty() || value == "$" || value.front() == '.') return std::nullopt;
    char* end = nullptr;
    const auto number = std::strtod(value.c_str(), &end);
    if (end == value.c_str() || !std::isfinite(number)) return std::nullopt;
    return number;
}

std::optional<double> last_step_number(const StepEntity& entity) {
    for (auto index = entity.arguments.rbegin(); index != entity.arguments.rend(); ++index) {
        if (const auto number = step_number(*index); number.has_value()) return number;
    }
    return std::nullopt;
}

double length_scale_from_units(const std::vector<StepEntity>& entities) {
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

void append_transformed_brep(
    const StepEntity& brep,
    const std::unordered_map<int, StepEntity>& entities,
    const IfcTransform& transform,
    double length_scale,
    MeshBuffer& mesh
) {
    if (brep.arguments.empty()) return;
    const auto shell_ids = references_in(brep.arguments.front());
    if (shell_ids.empty()) return;
    const auto shell = entities.find(shell_ids.front());
    if (shell == entities.end() || shell->second.arguments.empty()) return;
    for (const auto face_id : references_in(shell->second.arguments.front())) {
        const auto face = entities.find(face_id);
        if (face == entities.end() || face->second.arguments.empty()) continue;
        const auto bound_ids = references_in(face->second.arguments.front());
        if (bound_ids.empty()) continue;
        const StepEntity* outer_bound = nullptr;
        for (const auto bound_id : bound_ids) {
            const auto bound = entities.find(bound_id);
            if (bound != entities.end() && bound->second.type == "IFCFACEOUTERBOUND") {
                outer_bound = &bound->second;
                break;
            }
        }
        if (outer_bound == nullptr) {
            const auto bound = entities.find(bound_ids.front());
            if (bound != entities.end()) outer_bound = &bound->second;
        }
        if (outer_bound == nullptr || outer_bound->arguments.empty()) continue;
        const auto loop_ids = references_in(outer_bound->arguments.front());
        if (loop_ids.empty()) continue;
        const auto loop = entities.find(loop_ids.front());
        if (loop == entities.end() || loop->second.arguments.empty()) continue;
        auto point_ids = references_in(loop->second.arguments.front());
        if (point_ids.size() < 3) continue;
        const bool reverse = outer_bound->arguments.size() > 1 && outer_bound->arguments[1].find(".F.") != std::string::npos;
        const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
        for (const auto point_id : point_ids) {
            const auto point = point3_by_id(point_id, entities);
            if (!point.has_value()) continue;
            mesh.vertices.push_back(point_scale(transform_point(transform, *point), length_scale));
        }
        const auto appended = mesh.vertices.size() - base;
        if (appended < 3 || appended != point_ids.size()) {
            mesh.vertices.resize(base);
            continue;
        }
        for (std::uint32_t index = 1; index + 1 < appended; ++index) {
            if (!reverse) {
                mesh.indices.insert(mesh.indices.end(), {base, base + index, base + index + 1});
            } else {
                mesh.indices.insert(mesh.indices.end(), {base, base + index + 1, base + index});
            }
        }
    }
}

void append_ifc_mesh_item(
    int item_id,
    const std::unordered_map<int, StepEntity>& entities,
    const IfcTransform& transform,
    double length_scale,
    MeshBuffer& mesh,
    std::vector<int>& recursion_guard
);

void append_ifc_mesh_representation(
    int representation_id,
    const std::unordered_map<int, StepEntity>& entities,
    const IfcTransform& transform,
    double length_scale,
    MeshBuffer& mesh,
    std::vector<int>& recursion_guard
) {
    const auto found = entities.find(representation_id);
    if (found == entities.end() || found->second.arguments.size() <= 3) return;
    for (const auto item_id : references_in(found->second.arguments[3])) {
        append_ifc_mesh_item(item_id, entities, transform, length_scale, mesh, recursion_guard);
    }
}

std::vector<Point3> profile_polygon(
    int profile_id,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, IfcTransform>& placement_cache
) {
    const auto found = entities.find(profile_id);
    if (found == entities.end()) return {};
    const auto& profile = found->second;
    if (profile.type == "IFCRECTANGLEPROFILEDEF" && profile.arguments.size() > 3) {
        const auto x = step_number(profile.arguments[2]).value_or(0.0) * 0.5;
        const auto y = step_number(profile.arguments[3]).value_or(0.0) * 0.5;
        return {{-x, -y, 0.0}, {x, -y, 0.0}, {x, y, 0.0}, {-x, y, 0.0}};
    }
    if (profile.type == "IFCCIRCLEPROFILEDEF" && profile.arguments.size() > 2) {
        const auto radius = step_number(profile.arguments[2]).value_or(0.0);
        std::vector<Point3> polygon;
        constexpr int segment_count = 24;
        polygon.reserve(segment_count);
        for (int index = 0; index < segment_count; ++index) {
            const auto angle = (2.0 * 3.14159265358979323846 * index) / segment_count;
            polygon.push_back({radius * std::cos(angle), radius * std::sin(angle), 0.0});
        }
        return polygon;
    }
    if (profile.type == "IFCARBITRARYCLOSEDPROFILEDEF" && profile.arguments.size() > 2) {
        const auto curve_ids = references_in(profile.arguments[2]);
        if (!curve_ids.empty()) {
            const auto curve = entities.find(curve_ids.front());
            if (curve != entities.end() && curve->second.type == "IFCPOLYLINE" && !curve->second.arguments.empty()) {
                std::vector<Point3> polygon;
                for (const auto point_id : references_in(curve->second.arguments.front())) {
                    if (const auto point = point3_by_id(point_id, entities); point.has_value()) {
                        polygon.push_back({point->x, point->y, 0.0});
                    }
                }
                if (polygon.size() > 1 && point_dot(point_subtract(polygon.front(), polygon.back()), point_subtract(polygon.front(), polygon.back())) <= 1.0e-12) {
                    polygon.pop_back();
                }
                if (polygon.size() >= 3) return polygon;
            }
        }
    }
    (void)placement_cache;
    return {};
}

void append_extruded_area_solid(
    const StepEntity& solid,
    const std::unordered_map<int, StepEntity>& entities,
    const IfcTransform& parent_transform,
    double length_scale,
    MeshBuffer& mesh
) {
    if (solid.arguments.size() < 4) return;
    const auto profile_ids = references_in(solid.arguments[0]);
    if (profile_ids.empty()) return;
    std::map<int, IfcTransform> cache;
    auto solid_transform = identity_transform();
    if (const auto position_id = step_reference(solid.arguments[1]); position_id.has_value()) {
        std::vector<int> guard;
        solid_transform = axis_placement_transform(*position_id, entities, cache, guard);
    }
    const auto world_transform = compose_transform(parent_transform, solid_transform);
    auto profile_transform = identity_transform();
    const auto profile = entities.find(profile_ids.front());
    if (profile != entities.end() && profile->second.arguments.size() > 1) {
        if (const auto position_id = step_reference(profile->second.arguments[1]); position_id.has_value()) {
            std::vector<int> guard;
            profile_transform = axis_placement_transform(*position_id, entities, cache, guard);
        }
    }
    const auto transform = compose_transform(world_transform, profile_transform);
    const auto polygon = profile_polygon(profile_ids.front(), entities, cache);
    const auto direction_ids = references_in(solid.arguments[2]);
    const auto direction = direction_ids.empty()
        ? Point3{0.0, 0.0, 1.0}
        : direction3_by_id(direction_ids.front(), entities).value_or(Point3{0.0, 0.0, 1.0});
    const auto depth = step_number(solid.arguments[3]).value_or(0.0);
    if (polygon.size() < 3 || depth <= 0.0) return;
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    for (const auto& point : polygon) {
        mesh.vertices.push_back(point_scale(transform_point(transform, point), length_scale));
    }
    for (const auto& point : polygon) {
        mesh.vertices.push_back(point_scale(transform_point(transform, point_add(point, point_scale(direction, depth))), length_scale));
    }
    const auto count = static_cast<std::uint32_t>(polygon.size());
    for (std::uint32_t index = 1; index + 1 < count; ++index) {
        mesh.indices.insert(mesh.indices.end(), {base, base + index + 1, base + index});
        mesh.indices.insert(mesh.indices.end(), {base + count, base + count + index, base + count + index + 1});
    }
    for (std::uint32_t index = 0; index < count; ++index) {
        const auto next = (index + 1) % count;
        mesh.indices.insert(mesh.indices.end(), {
            base + index, base + next, base + count + next,
            base + index, base + count + next, base + count + index,
        });
    }
}

void append_ifc_mesh_item(
    int item_id,
    const std::unordered_map<int, StepEntity>& entities,
    const IfcTransform& transform,
    double length_scale,
    MeshBuffer& mesh,
    std::vector<int>& recursion_guard
) {
    if (std::find(recursion_guard.begin(), recursion_guard.end(), item_id) != recursion_guard.end()) return;
    const auto found = entities.find(item_id);
    if (found == entities.end()) return;
    recursion_guard.push_back(item_id);
    const auto& item = found->second;
    if (item.type == "IFCFACETEDBREP") {
        append_transformed_brep(item, entities, transform, length_scale, mesh);
    } else if (item.type == "IFCEXTRUDEDAREASOLID") {
        append_extruded_area_solid(item, entities, transform, length_scale, mesh);
    } else if (item.type == "IFCSTYLEDITEM") {
        if (!item.arguments.empty()) {
            for (const auto child_id : references_in(item.arguments.front())) {
                append_ifc_mesh_item(child_id, entities, transform, length_scale, mesh, recursion_guard);
            }
        }
    } else if (item.type == "IFCMAPPEDITEM") {
        const auto map_ids = item.arguments.empty() ? std::vector<int>{} : references_in(item.arguments[0]);
        if (!map_ids.empty()) {
            const auto map = entities.find(map_ids.front());
            if (map != entities.end() && map->second.arguments.size() > 1) {
                const auto origin_ids = references_in(map->second.arguments[0]);
                const auto representation_ids = references_in(map->second.arguments[1]);
                if (!representation_ids.empty()) {
                    auto source_origin = identity_transform();
                    std::map<int, IfcTransform> origin_cache;
                    std::vector<int> origin_guard;
                    if (!origin_ids.empty()) source_origin = axis_placement_transform(origin_ids.front(), entities, origin_cache, origin_guard);
                    const auto inverse_source = inverse_transform(source_origin).value_or(identity_transform());
                    auto target = identity_transform();
                    const auto target_ids = item.arguments.size() > 1 ? references_in(item.arguments[1]) : std::vector<int>{};
                    if (!target_ids.empty()) target = cartesian_operator_transform(target_ids.front(), entities);
                    const auto mapped_transform = compose_transform(transform, compose_transform(target, inverse_source));
                    append_ifc_mesh_representation(representation_ids.front(), entities, mapped_transform, length_scale, mesh, recursion_guard);
                }
            }
        }
    } else if (item.type == "IFCREPRESENTATIONMAP") {
        if (item.arguments.size() > 1) {
            const auto representation_ids = references_in(item.arguments[1]);
            if (!representation_ids.empty()) append_ifc_mesh_representation(representation_ids.front(), entities, transform, length_scale, mesh, recursion_guard);
        }
    } else if (item.type == "IFCBOOLEANRESULT") {
        // A boolean result still contains the operand solids. Rendering both
        // operands is a safe first pass for files without a kernel; direct
        // BREP products, which are the common architectural export, remain
        // exact and are never reduced to an envelope.
        for (std::size_t index = 1; index < item.arguments.size(); ++index) {
            for (const auto child_id : references_in(item.arguments[index])) {
                append_ifc_mesh_item(child_id, entities, transform, length_scale, mesh, recursion_guard);
            }
        }
    }
    recursion_guard.pop_back();
}

bool has_product_shape(const StepEntity& product, const std::unordered_map<int, StepEntity>& entities) {
    if (product.arguments.size() <= 6) return false;
    const auto representation = step_reference(product.arguments[6]);
    if (!representation.has_value()) return false;
    const auto found = entities.find(*representation);
    return found != entities.end() && found->second.type == "IFCPRODUCTDEFINITIONSHAPE";
}

MeshBuffer product_mesh(
    const StepEntity& product,
    const std::unordered_map<int, StepEntity>& entities,
    double length_scale,
    std::map<int, IfcTransform>& placement_cache,
    std::map<int, MeshBuffer>& mesh_cache
) {
    if (const auto cached = mesh_cache.find(product.id); cached != mesh_cache.end()) return cached->second;
    MeshBuffer mesh;
    if (!has_product_shape(product, entities)) {
        mesh_cache[product.id] = mesh;
        return mesh;
    }
    auto placement = identity_transform();
    if (const auto placement_id = step_reference(product.arguments[5]); placement_id.has_value()) {
        std::vector<int> guard;
        placement = axis_placement_transform(*placement_id, entities, placement_cache, guard);
    }
    const auto shape_id = step_reference(product.arguments[6]);
    const auto shape = shape_id.has_value() ? entities.find(*shape_id) : entities.end();
    if (shape != entities.end() && shape->second.arguments.size() > 2) {
        const auto representation_ids = references_in(shape->second.arguments[2]);
        std::vector<int> candidates;
        const auto add_candidate = [&candidates](int representation_id) {
            if (std::find(candidates.begin(), candidates.end(), representation_id) == candidates.end()) {
                candidates.push_back(representation_id);
            }
        };

        // Prefer the authored Body representation. Brep/mapped geometry is a
        // fallback; appending both creates coplanar duplicate faces and z-fighting.
        for (const auto representation_id : representation_ids) {
            const auto representation = entities.find(representation_id);
            if (representation == entities.end() || representation->second.arguments.size() <= 3) continue;
            const auto identifier = representation->second.arguments.size() > 1 ? step_string(representation->second.arguments[1]) : std::string{};
            if (identifier == "Body") add_candidate(representation_id);
        }
        for (const auto representation_id : representation_ids) {
            const auto representation = entities.find(representation_id);
            if (representation == entities.end() || representation->second.arguments.size() <= 3) continue;
            const auto type = representation->second.arguments.size() > 2 ? step_string(representation->second.arguments[2]) : std::string{};
            if (type == "Brep" || type == "MappedRepresentation") add_candidate(representation_id);
        }
        for (const auto representation_id : representation_ids) add_candidate(representation_id);

        for (const auto representation_id : candidates) {
            MeshBuffer candidate;
            std::vector<int> recursion_guard;
            append_ifc_mesh_representation(representation_id, entities, placement, length_scale, candidate, recursion_guard);
            if (!candidate.vertices.empty() && !candidate.indices.empty()) {
                mesh = std::move(candidate);
                break;
            }
        }
    }
    mesh_cache[product.id] = mesh;
    return mesh;
}

struct MeshBounds {
    Point3 minimum{};
    Point3 maximum{};
    bool valid{};
};

MeshBounds mesh_bounds(const MeshBuffer& mesh) {
    MeshBounds bounds{
        .minimum = {std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max()},
        .maximum = {std::numeric_limits<double>::lowest(), std::numeric_limits<double>::lowest(), std::numeric_limits<double>::lowest()},
        .valid = false,
    };
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

MeshBuffer mesh_relative_to_level(const MeshBuffer& mesh, double level_elevation) {
    auto result = mesh;
    for (auto& point : result.vertices) point.z -= level_elevation;
    return result;
}

void mark_exact_ifc_geometry(Element& element);

bool assign_exact_mesh(Element& element, const MeshBuffer& global_mesh, double level_elevation) {
    if (global_mesh.vertices.empty() || global_mesh.indices.empty()) return false;
    const auto local_mesh = mesh_relative_to_level(global_mesh, level_elevation);
    switch (element.kind()) {
    case ElementKind::Wall:
        element.wall()->geometry.mesh = local_mesh;
        element.wall()->geometry.dirty = false;
        break;
    case ElementKind::Door:
        element.door()->mesh = local_mesh;
        break;
    case ElementKind::Window:
        element.window()->mesh = local_mesh;
        break;
    case ElementKind::Slab:
        element.slab()->mesh = local_mesh;
        element.slab()->generated_geometry_dirty = false;
        break;
    case ElementKind::Roof:
        element.roof()->mesh = local_mesh;
        element.roof()->generated_geometry_dirty = false;
        break;
    case ElementKind::Column:
        element.column()->mesh = local_mesh;
        element.column()->generated_geometry_dirty = false;
        break;
    case ElementKind::Beam:
        element.beam()->mesh = local_mesh;
        element.beam()->generated_geometry_dirty = false;
        break;
    case ElementKind::Stair:
        element.stair()->mesh = local_mesh;
        element.stair()->generated_geometry_dirty = false;
        break;
    case ElementKind::Level:
    case ElementKind::Room:
    case ElementKind::Proxy:
        return false;
    }
    mark_exact_ifc_geometry(element);
    return true;
}

Point2 placement_point(
    int placement_id,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, Point2>& cache,
    std::vector<int>& recursion_guard
) {
    if (const auto found = cache.find(placement_id); found != cache.end()) return found->second;
    if (std::find(recursion_guard.begin(), recursion_guard.end(), placement_id) != recursion_guard.end()) return {};
    const auto found = entities.find(placement_id);
    if (found == entities.end()) return {};
    recursion_guard.push_back(placement_id);
    Point2 result{};
    if (found->second.type == "IFCLOCALPLACEMENT" && found->second.arguments.size() > 1) {
        if (const auto parent = step_reference(found->second.arguments[0]); parent.has_value()) {
            result = placement_point(*parent, entities, cache, recursion_guard);
        }
        if (const auto relative = step_reference(found->second.arguments[1]); relative.has_value()) {
            const auto point = placement_point(*relative, entities, cache, recursion_guard);
            result.x += point.x;
            result.y += point.y;
        }
    } else if (found->second.type == "IFCAXIS2PLACEMENT3D" && !found->second.arguments.empty()) {
        if (const auto point = step_reference(found->second.arguments[0]); point.has_value()) {
            result = placement_point(*point, entities, cache, recursion_guard);
        }
    } else if (found->second.type == "IFCCARTESIANPOINT" && !found->second.arguments.empty()) {
        const auto values = found->second.arguments.front();
        if (values.size() > 2 && values.front() == '(' && values.back() == ')') {
            const auto coordinates = split_step_arguments(std::string_view(values).substr(1, values.size() - 2));
            if (coordinates.size() > 1) {
                result.x = step_number(coordinates[0]).value_or(0.0);
                result.y = step_number(coordinates[1]).value_or(0.0);
            }
        }
    }
    recursion_guard.pop_back();
    cache[placement_id] = result;
    return result;
}

Point2 product_location(
    const StepEntity& entity,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, Point2>& cache,
    double length_scale
) {
    if (entity.arguments.size() <= 5) return {};
    const auto placement = step_reference(entity.arguments[5]);
    if (!placement.has_value()) return {};
    std::vector<int> guard;
    const auto point = placement_point(*placement, entities, cache, guard);
    return {.x = point.x * length_scale, .y = point.y * length_scale};
}

std::string product_name(const StepEntity& entity) {
    if (entity.arguments.size() > 2) {
        const auto name = step_string(entity.arguments[2]);
        if (!name.empty()) return name;
    }
    return entity.type + " " + std::to_string(entity.id);
}

void set_ifc_metadata(Element& element, const StepEntity& source, std::string warning = {}) {
    if (!source.arguments.empty()) {
        element.metadata()["ifc_guid"] = MetadataValue{
            .kind = MetadataValueKind::Text,
            .value = step_string(source.arguments.front()),
        };
    }
    element.metadata()["ifc_entity"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = source.type,
    };
    if (!warning.empty()) {
        element.metadata()["ifc_import_note"] = MetadataValue{
            .kind = MetadataValueKind::Text,
            .value = std::move(warning),
        };
    }
}

void mark_exact_ifc_geometry(Element& element) {
    element.metadata()["ifc_exact_geometry"] = MetadataValue{
        .kind = MetadataValueKind::Boolean,
        .value = "true",
    };
}

struct ProxyProfile {
    double width_meters{};
    double depth_meters{};
    double height_meters{};
};

std::optional<ProxyProfile> proxy_profile_for(std::string_view type) {
    // These are physical IFC products commonly emitted by architectural,
    // structural and MEP exporters. They are only used when the source has no
    // representation that the native tessellator can decode; preserve their
    // location and identity instead of silently dropping them.
    if (type == "IFCFURNISHINGELEMENT" || type == "IFCFURNITURE") return ProxyProfile{1.2, 0.8, 1.0};
    if (type == "IFCRAILING") return ProxyProfile{2.0, 0.08, 1.0};
    if (type == "IFCPLATE" || type == "IFCFOOTING") return ProxyProfile{2.0, 2.0, 0.20};
    if (type == "IFCMEMBER") return ProxyProfile{2.0, 0.20, 0.20};
    if (type == "IFCPILE") return ProxyProfile{0.40, 0.40, 3.0};
    if (type == "IFCCURTAINWALL") return ProxyProfile{4.0, 0.15, 3.0};
    if (type == "IFCRAMP") return ProxyProfile{3.0, 1.0, 0.80};
    if (type == "IFCCHIMNEY") return ProxyProfile{1.0, 1.0, 2.0};
    if (type == "IFCBUILDINGELEMENTPROXY") return ProxyProfile{1.0, 1.0, 1.0};
    if (type == "IFCFLOWSEGMENT") return ProxyProfile{2.0, 0.25, 0.25};
    if (type == "IFCFLOWFITTING") return ProxyProfile{0.50, 0.50, 0.50};
    if (type == "IFCFLOWTERMINAL") return ProxyProfile{0.50, 0.50, 0.80};
    if (type == "IFCDISTRIBUTIONELEMENT") return ProxyProfile{0.80, 0.80, 1.0};
    if (type == "IFCENERGYCONVERSIONDEVICE") return ProxyProfile{1.0, 1.0, 1.0};
    if (type == "IFCELECTRICAPPLIANCE") return ProxyProfile{0.60, 0.60, 0.80};
    if (type == "IFCMOTORCONNECTION") return ProxyProfile{0.40, 0.40, 0.40};
    if (type == "IFCFASTENER" || type == "IFCMECHANICALFASTENER") return ProxyProfile{0.15, 0.15, 0.15};
    if (type == "IFCDISCRETEACCESSORY") return ProxyProfile{0.40, 0.40, 0.40};
    if (type == "IFCGEOGRAPHICELEMENT") return ProxyProfile{4.0, 4.0, 0.50};
    if (type == "IFCVEHICLE") return ProxyProfile{2.0, 4.0, 1.50};
    return std::nullopt;
}

} // namespace

void export_ifc(const Document& document, const std::filesystem::path& path, IfcExchangeReport* report) {
    std::ofstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to open IFC export path");

    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    file << "ISO-10303-21;\nHEADER;\n"
         << "FILE_DESCRIPTION(('ViewDefinition [CoordinationView_V2.0]'),'2;1');\n"
         << "FILE_NAME('" << path.filename().string() << "'," << now
         << ",('Tablet BIM'),('AxionSoftware-Inc'),'Tablet BIM IFC4 exporter','Tablet BIM','');\n"
         << "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";

    // These are intentionally simple semantic entities. Geometry consumers
    // can still identify every authored category while the sidecar below
    // carries the exact engine model for a lossless internal round-trip.
    file << "#1=IFCPROJECT(" << guid_for(1) << ",$,'" << hex_encode(document.name())
         << "',$,$,$,$,(#2),#3);\n";
    file << "#2=IFCUNITASSIGNMENT((#4,#5,#6));\n";
    file << "#3=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.0E-05,#7,$);\n";
    file << "#4=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n"
         << "#5=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);\n"
         << "#6=IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);\n"
         << "#7=IFCAXIS2PLACEMENT3D(#8,$,$);\n"
         << "#8=IFCCARTESIANPOINT((0.,0.,0.));\n";

    std::size_t entity_id = 100;
    std::size_t ordinal = 10;
    for (const auto& element : document.elements()) {
        const auto entity_name = entity_for(element.kind());
        file << '#' << entity_id << '=' << entity_name << '(' << guid_for(ordinal++)
             << ",$,#" << (entity_id + 1) << ",'" << ifc_name(element) << "',$,$,$,$,$);\n";
        ++entity_id;
        file << '#' << entity_id << "=IFCLOCALPLACEMENT($,#7);\n";
        ++entity_id;
        if (report != nullptr) ++report->exported_elements;
    }

    // IFC permits comments in the STEP exchange structure. Keeping this
    // marker after DATA makes the contract discoverable and avoids a hidden
    // proprietary file format while preserving every native relation/value.
    file << "/* TBE_DOCUMENT_JSON_HEX " << hex_encode(document.to_json()) << " */\n";
    file << "ENDSEC;\nEND-ISO-10303-21;\n";
    if (!file) throw std::runtime_error("IFC export failed while writing");
}

Document import_ifc(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to open IFC import path");
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const auto contents = buffer.str();
    constexpr std::string_view marker = "/* TBE_DOCUMENT_JSON_HEX ";
    const auto begin = contents.find(marker);
    if (begin != std::string::npos) {
        const auto value_begin = begin + marker.size();
        const auto value_end = contents.find(" */", value_begin);
        if (value_end == std::string::npos) throw std::invalid_argument("truncated IFC semantic sidecar");
        auto document = Document::from_json(hex_decode(std::string_view(contents).substr(value_begin, value_end - value_begin)));
        if (report != nullptr) report->imported_elements = document.elements().size();
        return document;
    }

    const auto entities = parse_step_entities(contents);
    std::unordered_map<int, StepEntity> by_id;
    for (const auto& entity : entities) by_id.emplace(entity.id, entity);
    Document document(std::move(document_name));
    // Third-party files can contain hundreds of walls with incomplete
    // placement/connection data. Rebuilding automatic joins for every
    // approximated fallback wall is both unnecessary and quadratic; the
    // imported geometry is regenerated once by the render-scene query.
    document.set_automatic_wall_join_enabled(false);
    const auto length_scale = length_scale_from_units(entities);
    std::map<int, ElementId> levels;
    std::map<int, Point2> placement_point_cache;
    std::map<int, IfcTransform> placement_transform_cache;
    std::map<int, MeshBuffer> exact_mesh_cache;
    bool used_approximation = false;
    const auto supported_type = [](std::string_view type) {
        return type == "IFCBUILDINGSTOREY" || type == "IFCLEVEL" ||
            type == "IFCWALL" || type == "IFCWALLSTANDARDCASE" ||
            type == "IFCDOOR" || type == "IFCWINDOW" || type == "IFCSLAB" ||
            type == "IFCROOF" || type == "IFCCOLUMN" || type == "IFCBEAM" ||
            type == "IFCSTAIR" || type == "IFCSTAIRFLIGHT";
    };
    const auto has_supported_entity = std::any_of(entities.begin(), entities.end(), [&](const auto& entity) {
        return supported_type(entity.type) || proxy_profile_for(entity.type).has_value();
    });
    if (!has_supported_entity) {
        if (report != nullptr) {
            report->warnings.push_back("IFC STEP data did not contain supported semantic entities.");
        }
        return document;
    }

    for (const auto& entity : entities) {
        if (entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCLEVEL") continue;
        const auto elevation = last_step_number(entity).value_or(0.0) * length_scale;
        const auto level_id = document.create_level(product_name(entity), elevation, 3.0);
        levels[entity.id] = level_id;
        if (auto* created = document.find_ptr(level_id); created != nullptr) set_ifc_metadata(*created, entity);
    }
    if (levels.empty()) {
        const auto level_id = document.create_level("Level 1", 0.0, 3.0);
        levels[-1] = level_id;
    }
    const auto default_level = levels.begin()->second;
    const auto level_elevation_for = [&](ElementId level_id) {
        const auto* level_element = document.find_ptr(level_id);
        return level_element != nullptr && level_element->level() != nullptr
            ? level_element->level()->elevation_meters
            : 0.0;
    };
    const auto exact_mesh_for = [&](const StepEntity& entity) {
        return product_mesh(entity, by_id, length_scale, placement_transform_cache, exact_mesh_cache);
    };
    const auto level_for = [&](const StepEntity& entity) {
        // IFC containment relations are intentionally optional for this
        // lightweight path. A stable first storey keeps imported geometry
        // visible while preserving the source ids in metadata.
        (void)entity;
        return default_level;
    };

    struct ImportedWall {
        ElementId id{};
        Line2 axis{};
    };
    std::vector<ImportedWall> imported_walls;
    for (const auto& entity : entities) {
        if (entity.type != "IFCWALL" && entity.type != "IFCWALLSTANDARDCASE") continue;
        const auto origin = product_location(entity, by_id, placement_point_cache, length_scale);
        const auto wall_id = document.create_wall(product_name(entity),
            Line2{.start = origin, .end = {.x = origin.x + 4.0, .y = origin.y}},
            0.2, 3.0, level_for(entity));
        if (auto* created = document.find_ptr(wall_id); created != nullptr) {
            const auto exact_mesh = exact_mesh_for(entity);
            if (!exact_mesh.vertices.empty() && !exact_mesh.indices.empty()) {
                created->wall()->geometry.mesh = mesh_relative_to_level(exact_mesh, level_elevation_for(level_for(entity)));
                created->wall()->geometry.dirty = false;
                set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                mark_exact_ifc_geometry(*created);
            } else {
                set_ifc_metadata(*created, entity,
                    "Third-party IFC geometry was imported through the semantic fallback; default wall dimensions were used.");
            }
        }
        imported_walls.push_back(ImportedWall{
            .id = wall_id,
            .axis = Line2{.start = origin, .end = {.x = origin.x + 4.0, .y = origin.y}},
        });
        used_approximation = true;
    }
    std::size_t skipped_openings = 0;
    std::map<std::string, std::size_t> proxy_counts;
    std::map<std::string, std::size_t> proxy_exact_counts;
    std::map<std::string, std::size_t> proxy_fallback_counts;
    std::map<std::string, std::size_t> skipped_non_renderable_counts;
    for (const auto& entity : entities) {
        if (entity.type != "IFCDOOR" && entity.type != "IFCWINDOW") continue;
        const auto origin = product_location(entity, by_id, placement_point_cache, length_scale);
        if (imported_walls.empty()) {
            ++skipped_openings;
            continue;
        }

        std::vector<std::pair<double, std::size_t>> candidates;
        candidates.reserve(imported_walls.size());
        for (std::size_t index = 0; index < imported_walls.size(); ++index) {
            const auto& axis = imported_walls[index].axis;
            const auto dx = axis.end.x - axis.start.x;
            const auto dy = axis.end.y - axis.start.y;
            const auto length_squared = dx * dx + dy * dy;
            const auto projection = length_squared <= 0.0
                ? 0.0
                : ((origin.x - axis.start.x) * dx + (origin.y - axis.start.y) * dy) / length_squared;
            const auto clamped = std::clamp(projection, 0.0, 1.0);
            const auto closest_x = axis.start.x + dx * clamped;
            const auto closest_y = axis.start.y + dy * clamped;
            const auto distance_x = origin.x - closest_x;
            const auto distance_y = origin.y - closest_y;
            candidates.emplace_back(distance_x * distance_x + distance_y * distance_y, index);
        }
        std::sort(candidates.begin(), candidates.end());

        const auto is_door = entity.type == "IFCDOOR";
        const auto opening_width = is_door ? 0.9 : 1.2;
        const auto opening_height = is_door ? 2.1 : 1.2;
        const auto sill_height = is_door ? 0.0 : 1.0;
        bool imported_opening = false;
        for (const auto& [distance, candidate_index] : candidates) {
            (void)distance;
            const auto& host = imported_walls[candidate_index];
            const auto dx = host.axis.end.x - host.axis.start.x;
            const auto dy = host.axis.end.y - host.axis.start.y;
            const auto host_length = std::sqrt(dx * dx + dy * dy);
            if (host_length <= 0.0) continue;
            const auto projected = ((origin.x - host.axis.start.x) * dx +
                (origin.y - host.axis.start.y) * dy) / host_length;
            const auto offset = std::clamp(
                projected,
                opening_width * 0.5,
                host_length - opening_width * 0.5);
            try {
                const auto id = is_door
                    ? document.create_door(product_name(entity), host.id, offset, opening_width, opening_height)
                    : document.create_window(product_name(entity), host.id, offset, opening_width, opening_height, sill_height);
                if (auto* created = document.find_ptr(id); created != nullptr) {
                    const auto exact_mesh = exact_mesh_for(entity);
                    if (!exact_mesh.vertices.empty() && !exact_mesh.indices.empty()) {
                        if (auto* door = created->door(); door != nullptr) {
                            door->mesh = mesh_relative_to_level(exact_mesh, level_elevation_for(level_for(entity)));
                        } else if (auto* window = created->window(); window != nullptr) {
                            window->mesh = mesh_relative_to_level(exact_mesh, level_elevation_for(level_for(entity)));
                        }
                        set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                        mark_exact_ifc_geometry(*created);
                    } else {
                        set_ifc_metadata(*created, entity,
                            "Opening host was inferred from the nearest imported wall; source profile was approximated.");
                    }
                }
                imported_opening = true;
                break;
            } catch (const std::invalid_argument&) {
                // Another source opening may already occupy this fallback
                // slot. Try the next nearest wall instead of aborting the
                // complete third-party import.
            }
        }
        if (!imported_opening) ++skipped_openings;
    }
    for (const auto& entity : entities) {
        const auto origin = product_location(entity, by_id, placement_point_cache, length_scale);
        const auto level_id = level_for(entity);
        if (entity.type == "IFCSLAB") {
            const auto id = document.create_slab(level_id, {{origin.x, origin.y}, {origin.x + 4.0, origin.y},
                {origin.x + 4.0, origin.y + 4.0}, {origin.x, origin.y + 4.0}}, 0.2);
            if (auto* created = document.find_ptr(id); created != nullptr) {
                const auto exact_mesh = exact_mesh_for(entity);
                if (assign_exact_mesh(*created, exact_mesh, level_elevation_for(level_id))) {
                    set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                } else {
                    set_ifc_metadata(*created, entity,
                        "Slab profile was approximated because no supported swept profile was found.");
                    used_approximation = true;
                }
            }
        } else if (entity.type == "IFCROOF") {
            const auto id = document.create_roof(level_id, {{origin.x, origin.y}, {origin.x + 4.0, origin.y},
                {origin.x + 4.0, origin.y + 4.0}, {origin.x, origin.y + 4.0}}, RoofType::Flat, 0.2);
            if (auto* created = document.find_ptr(id); created != nullptr) {
                const auto exact_mesh = exact_mesh_for(entity);
                if (assign_exact_mesh(*created, exact_mesh, level_elevation_for(level_id))) {
                    set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                } else {
                    set_ifc_metadata(*created, entity,
                        "Roof profile was approximated because no supported swept profile was found.");
                    used_approximation = true;
                }
            }
        } else if (entity.type == "IFCCOLUMN") {
            const auto id = document.create_column(level_id, origin, 0.3, 0.3, 3.0, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) {
                const auto exact_mesh = exact_mesh_for(entity);
                if (assign_exact_mesh(*created, exact_mesh, level_elevation_for(level_id))) {
                    set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                } else {
                    set_ifc_metadata(*created, entity,
                        "Column profile was approximated because no supported swept profile was found.");
                    used_approximation = true;
                }
            }
        } else if (entity.type == "IFCBEAM") {
            const auto id = document.create_beam(level_id, origin, {.x = origin.x + 4.0, .y = origin.y}, 0.25, 0.35, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) {
                const auto exact_mesh = exact_mesh_for(entity);
                if (assign_exact_mesh(*created, exact_mesh, level_elevation_for(level_id))) {
                    set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                } else {
                    set_ifc_metadata(*created, entity,
                        "Beam profile was approximated because no supported swept profile was found.");
                    used_approximation = true;
                }
            }
        } else if (entity.type == "IFCSTAIR" || entity.type == "IFCSTAIRFLIGHT") {
            const auto id = document.create_stair(level_id, level_id, origin, {.x = 1.0, .y = 0.0},
                1.0, 3.0, 4.0, 12, 12, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) {
                const auto exact_mesh = exact_mesh_for(entity);
                if (assign_exact_mesh(*created, exact_mesh, level_elevation_for(level_id))) {
                    set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                } else {
                    set_ifc_metadata(*created, entity,
                        "Stair profile was approximated because no supported swept profile was found.");
                    used_approximation = true;
                }
            }
        }
    }
    for (const auto& entity : entities) {
        if (entity.type == "IFCWALL" || entity.type == "IFCWALLSTANDARDCASE" ||
            entity.type == "IFCDOOR" || entity.type == "IFCWINDOW" ||
            entity.type == "IFCSLAB" || entity.type == "IFCROOF" ||
            entity.type == "IFCCOLUMN" || entity.type == "IFCBEAM" ||
            entity.type == "IFCSTAIR" || entity.type == "IFCSTAIRFLIGHT") {
            continue;
        }
        const auto profile = proxy_profile_for(entity.type);
        const auto exact_mesh = exact_mesh_for(entity);
        const auto exact_bounds = mesh_bounds(exact_mesh);
        const auto has_exact_mesh = !exact_mesh.vertices.empty() && !exact_mesh.indices.empty() && exact_bounds.valid;
        if (!profile.has_value() && !has_exact_mesh) {
            if (entity.type == "IFCSPACE" || entity.type == "IFCANNOTATION") {
                ++skipped_non_renderable_counts[entity.type];
            }
            continue;
        }
        const auto origin = product_location(entity, by_id, placement_point_cache, length_scale);
        const auto level_id = level_for(entity);
        const auto proxy_position = has_exact_mesh
            ? Point2{
                .x = (exact_bounds.minimum.x + exact_bounds.maximum.x) * 0.5,
                .y = (exact_bounds.minimum.y + exact_bounds.maximum.y) * 0.5,
            }
            : origin;
        const auto width = has_exact_mesh
            ? std::max(0.01, exact_bounds.maximum.x - exact_bounds.minimum.x)
            : profile->width_meters;
        const auto depth = has_exact_mesh
            ? std::max(0.01, exact_bounds.maximum.y - exact_bounds.minimum.y)
            : profile->depth_meters;
        const auto height = has_exact_mesh
            ? std::max(0.01, exact_bounds.maximum.z - exact_bounds.minimum.z)
            : profile->height_meters;
        const auto id = document.create_proxy(
            product_name(entity),
            level_id,
            proxy_position,
            width,
            depth,
            height
        );
        if (auto* created = document.find_ptr(id); created != nullptr) {
            if (has_exact_mesh) {
                created->proxy()->mesh = exact_mesh;
                set_ifc_metadata(*created, entity, "Exact IFC BREP mesh imported.");
                mark_exact_ifc_geometry(*created);
            } else {
                set_ifc_metadata(*created, entity,
                    "Exact IFC profile was not available in the lightweight reader; a selectable envelope was created.");
                used_approximation = true;
            }
        }
        ++proxy_counts[entity.type];
        if (has_exact_mesh) {
            ++proxy_exact_counts[entity.type];
        } else {
            ++proxy_fallback_counts[entity.type];
        }
    }
    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        if (skipped_openings != 0) {
            report->warnings.push_back("Skipped " + std::to_string(skipped_openings) +
                " overlapping or unhosted third-party openings in the lightweight fallback.");
        }
        if (!proxy_fallback_counts.empty()) {
            std::ostringstream proxy_warning;
            proxy_warning << "Imported unsupported physical IFC products as lightweight envelopes: ";
            bool first = true;
            for (const auto& [type, count] : proxy_fallback_counts) {
                if (!first) proxy_warning << ", ";
                first = false;
                proxy_warning << type << " (" << count << ")";
            }
            report->warnings.push_back(proxy_warning.str());
        }
        if (!proxy_exact_counts.empty()) {
            std::ostringstream exact_warning;
            exact_warning << "Imported exact IFC mesh for physical products: ";
            bool first = true;
            for (const auto& [type, count] : proxy_exact_counts) {
                if (!first) exact_warning << ", ";
                first = false;
                exact_warning << type << " (" << count << ")";
            }
            report->warnings.push_back(exact_warning.str());
        }
        if (!skipped_non_renderable_counts.empty()) {
            std::ostringstream skipped_warning;
            skipped_warning << "Skipped non-renderable IFC semantic entities: ";
            bool first = true;
            for (const auto& [type, count] : skipped_non_renderable_counts) {
                if (!first) skipped_warning << ", ";
                first = false;
                skipped_warning << type << " (" << count << ")";
            }
            skipped_warning << ". These require room/annotation-specific views rather than 3D product geometry.";
            report->warnings.push_back(skipped_warning.str());
        }
        if (used_approximation) {
            report->warnings.push_back(
                "Third-party IFC imported with semantic fallback. Some profiles and containment relations were approximated; review marked elements before editing.");
        } else if (report->imported_elements == 1 && entities.empty()) {
            report->warnings.push_back("IFC file did not contain supported semantic entities.");
        }
    }
    if (document.elements().size() == 1 && entities.empty()) {
        if (report != nullptr) report->warnings.push_back("IFC STEP data could not be parsed.");
    }
    return document;
}

} // namespace tbe::core
