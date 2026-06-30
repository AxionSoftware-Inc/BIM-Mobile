#include "tbe/core/Document.hpp"

#include <cmath>
#include <cctype>
#include <cerrno>
#include <map>
#include <sstream>
#include <cstdlib>
#include <stdexcept>

namespace tbe::core {

namespace {

struct JsonValue {
    using Object = std::map<std::string, JsonValue>;
    using Array = std::vector<JsonValue>;

    enum class Type {
        Null,
        Bool,
        Number,
        String,
        Object,
        Array
    };

    Type type{Type::Null};
    bool bool_value{};
    double number_value{};
    std::string string_value{};
    Object object_value{};
    Array array_value{};
};

class JsonParser {
public:
    explicit JsonParser(std::string_view input)
        : input_(input) {}

    JsonValue parse() {
        auto value = parse_value();
        skip_ws();
        if (pos_ != input_.size()) {
            fail("unexpected trailing JSON data");
        }
        return value;
    }

private:
    std::string context(std::size_t position) const {
        const auto begin = position > 24 ? position - 24 : 0;
        const auto end = std::min(input_.size(), position + 24);
        std::string snippet{input_.substr(begin, end - begin)};
        for (char& ch : snippet) {
            if (ch == '\n' || ch == '\r' || ch == '\t') {
                ch = ' ';
            }
        }
        return snippet;
    }

    [[noreturn]] void fail(std::string_view message) const {
        throw std::invalid_argument(std::string(message) + " at position " + std::to_string(pos_) + " near: " + context(pos_));
    }

    void skip_ws() {
        while (pos_ < input_.size() && std::isspace(static_cast<unsigned char>(input_[pos_]))) {
            ++pos_;
        }
    }

    char peek() {
        skip_ws();
        if (pos_ >= input_.size()) {
            fail("unexpected end of JSON");
        }
        return input_[pos_];
    }

    char consume() {
        if (pos_ >= input_.size()) {
            fail("unexpected end of JSON");
        }
        return input_[pos_++];
    }

    void expect(char expected) {
        skip_ws();
        if (consume() != expected) {
            fail("unexpected JSON token");
        }
    }

    JsonValue parse_value() {
        const auto token = peek();
        if (token == '{') {
            return parse_object();
        }
        if (token == '[') {
            return parse_array();
        }
        if (token == '"') {
            JsonValue value;
            value.type = JsonValue::Type::String;
            value.string_value = parse_string();
            return value;
        }
        if (token == '-' || std::isdigit(static_cast<unsigned char>(token))) {
            return parse_number();
        }
        if (input_.substr(pos_, 4) == "true") {
            pos_ += 4;
            JsonValue value;
            value.type = JsonValue::Type::Bool;
            value.bool_value = true;
            return value;
        }
        if (input_.substr(pos_, 5) == "false") {
            pos_ += 5;
            JsonValue value;
            value.type = JsonValue::Type::Bool;
            value.bool_value = false;
            return value;
        }
        if (input_.substr(pos_, 4) == "null") {
            pos_ += 4;
            return JsonValue{};
        }
        fail("invalid JSON value");
    }

    JsonValue parse_object() {
        JsonValue value;
        value.type = JsonValue::Type::Object;
        expect('{');
        skip_ws();
        if (peek() == '}') {
            consume();
            return value;
        }

        while (true) {
            const auto key = parse_string();
            expect(':');
            value.object_value.emplace(key, parse_value());
            skip_ws();
            const auto token = consume();
            if (token == '}') {
                break;
            }
            if (token != ',') {
                fail("expected JSON object separator");
            }
        }

        return value;
    }

    JsonValue parse_array() {
        JsonValue value;
        value.type = JsonValue::Type::Array;
        expect('[');
        skip_ws();
        if (peek() == ']') {
            consume();
            return value;
        }

        while (true) {
            value.array_value.push_back(parse_value());
            skip_ws();
            const auto token = consume();
            if (token == ']') {
                break;
            }
            if (token != ',') {
                fail("expected JSON array separator");
            }
        }

        return value;
    }

    std::string parse_string() {
        expect('"');
        std::string output;
        while (true) {
            const auto token = consume();
            if (token == '"') {
                break;
            }
            if (token == '\\') {
                const auto escaped = consume();
                if (escaped == '"' || escaped == '\\' || escaped == '/') {
                    output.push_back(escaped);
                } else if (escaped == 'n') {
                    output.push_back('\n');
                } else if (escaped == 't') {
                    output.push_back('\t');
                } else {
                    fail("unsupported JSON escape");
                }
            } else {
                output.push_back(token);
            }
        }
        return output;
    }

    JsonValue parse_number() {
        const auto start = pos_;
        if (input_[pos_] == '-') {
            ++pos_;
        }
        while (pos_ < input_.size() && std::isdigit(static_cast<unsigned char>(input_[pos_]))) {
            ++pos_;
        }
        if (pos_ < input_.size() && input_[pos_] == '.') {
            ++pos_;
            while (pos_ < input_.size() && std::isdigit(static_cast<unsigned char>(input_[pos_]))) {
                ++pos_;
            }
        }
        if (pos_ < input_.size() && (input_[pos_] == 'e' || input_[pos_] == 'E')) {
            ++pos_;
            if (pos_ < input_.size() && (input_[pos_] == '+' || input_[pos_] == '-')) {
                ++pos_;
            }
            const auto exponent_start = pos_;
            while (pos_ < input_.size() && std::isdigit(static_cast<unsigned char>(input_[pos_]))) {
                ++pos_;
            }
            if (exponent_start == pos_) {
                fail("invalid JSON number");
            }
        }

        const auto token = input_.substr(start, pos_ - start);
        std::string buffer{token};
        char* parse_end = nullptr;
        errno = 0;
        const auto value = std::strtod(buffer.c_str(), &parse_end);
        if (parse_end != (buffer.c_str() + buffer.size()) || errno == ERANGE) {
            fail("invalid JSON number");
        }

        JsonValue json;
        json.type = JsonValue::Type::Number;
        json.number_value = value;
        return json;
    }

    std::string_view input_;
    std::size_t pos_{};
};

std::string escape_json(std::string_view value) {
    std::string escaped;
    for (const auto ch : value) {
        if (ch == '"' || ch == '\\') {
            escaped.push_back('\\');
            escaped.push_back(ch);
        } else if (ch == '\n') {
            escaped += "\\n";
        } else if (ch == '\t') {
            escaped += "\\t";
        } else {
            escaped.push_back(ch);
        }
    }
    return escaped;
}

void ensure_finite(double value, std::string_view field_name) {
    if (!std::isfinite(value)) {
        throw std::invalid_argument(std::string("non-finite JSON numeric value in ") + std::string(field_name));
    }
}

void ensure_finite_point(const Point2& point, std::string_view field_name) {
    ensure_finite(point.x, std::string(field_name) + ".x");
    ensure_finite(point.y, std::string(field_name) + ".y");
}

void ensure_finite_line(const Line2& line, std::string_view field_name) {
    ensure_finite_point(line.start, std::string(field_name) + ".start");
    ensure_finite_point(line.end, std::string(field_name) + ".end");
}

std::string kind_to_string(ElementKind kind) {
    switch (kind) {
    case ElementKind::Level:
        return "Level";
    case ElementKind::Wall:
        return "Wall";
    case ElementKind::Door:
        return "Door";
    case ElementKind::Window:
        return "Window";
    case ElementKind::Room:
        return "Room";
    case ElementKind::Roof:
        return "Roof";
    case ElementKind::Column:
        return "Column";
    case ElementKind::Beam:
        return "Beam";
    case ElementKind::Stair:
        return "Stair";
    case ElementKind::Slab:
        return "Slab";
    }
    return "Unknown";
}

std::string material_category_to_string(MaterialCategory category) {
    switch (category) {
    case MaterialCategory::Structural: return "Structural";
    case MaterialCategory::Finish: return "Finish";
    case MaterialCategory::Insulation: return "Insulation";
    case MaterialCategory::Glass: return "Glass";
    case MaterialCategory::Generic: return "Generic";
    }
    return "Generic";
}

MaterialCategory string_to_material_category(const std::string& value) {
    if (value == "Structural") return MaterialCategory::Structural;
    if (value == "Finish") return MaterialCategory::Finish;
    if (value == "Insulation") return MaterialCategory::Insulation;
    if (value == "Glass") return MaterialCategory::Glass;
    return MaterialCategory::Generic;
}

std::string wall_layer_function_to_string(WallLayerFunction function) {
    switch (function) {
    case WallLayerFunction::Core: return "Core";
    case WallLayerFunction::InteriorFinish: return "InteriorFinish";
    case WallLayerFunction::ExteriorFinish: return "ExteriorFinish";
    case WallLayerFunction::Insulation: return "Insulation";
    case WallLayerFunction::AirGap: return "AirGap";
    case WallLayerFunction::Generic: return "Generic";
    }
    return "Generic";
}

WallLayerFunction string_to_wall_layer_function(const std::string& value) {
    if (value == "Core") return WallLayerFunction::Core;
    if (value == "InteriorFinish") return WallLayerFunction::InteriorFinish;
    if (value == "ExteriorFinish") return WallLayerFunction::ExteriorFinish;
    if (value == "Insulation") return WallLayerFunction::Insulation;
    if (value == "AirGap") return WallLayerFunction::AirGap;
    return WallLayerFunction::Generic;
}

std::string layered_assembly_kind_to_string(LayeredAssemblyKind kind) {
    switch (kind) {
    case LayeredAssemblyKind::Floor: return "Floor";
    case LayeredAssemblyKind::Ceiling: return "Ceiling";
    }
    return "Floor";
}

LayeredAssemblyKind string_to_layered_assembly_kind(const std::string& value) {
    if (value == "Ceiling") {
        return LayeredAssemblyKind::Ceiling;
    }
    return LayeredAssemblyKind::Floor;
}

std::string roof_type_to_string(RoofType roof_type) {
    switch (roof_type) {
    case RoofType::Flat: return "Flat";
    case RoofType::SimpleGable: return "SimpleGable";
    }
    return "Flat";
}

RoofType string_to_roof_type(const std::string& value) {
    if (value == "SimpleGable") {
        return RoofType::SimpleGable;
    }
    return RoofType::Flat;
}

ElementKind string_to_kind(const std::string& kind) {
    if (kind == "Level") {
        return ElementKind::Level;
    }
    if (kind == "Wall") {
        return ElementKind::Wall;
    }
    if (kind == "Door") {
        return ElementKind::Door;
    }
    if (kind == "Window") {
        return ElementKind::Window;
    }
    if (kind == "Room") {
        return ElementKind::Room;
    }
    if (kind == "Roof") {
        return ElementKind::Roof;
    }
    if (kind == "Column") {
        return ElementKind::Column;
    }
    if (kind == "Beam") {
        return ElementKind::Beam;
    }
    if (kind == "Stair") {
        return ElementKind::Stair;
    }
    if (kind == "Slab") {
        return ElementKind::Slab;
    }
    throw std::invalid_argument("unsupported element kind in JSON");
}

const JsonValue& field(const JsonValue::Object& object, const std::string& key) {
    const auto found = object.find(key);
    if (found == object.end()) {
        throw std::invalid_argument("missing JSON field: " + key);
    }
    return found->second;
}

const JsonValue::Object& as_object(const JsonValue& value) {
    if (value.type != JsonValue::Type::Object) {
        throw std::invalid_argument("expected JSON object");
    }
    return value.object_value;
}

const JsonValue::Array& as_array(const JsonValue& value) {
    if (value.type != JsonValue::Type::Array) {
        throw std::invalid_argument("expected JSON array");
    }
    return value.array_value;
}

std::string as_string(const JsonValue& value) {
    if (value.type != JsonValue::Type::String) {
        throw std::invalid_argument("expected JSON string");
    }
    return value.string_value;
}

double as_number(const JsonValue& value) {
    if (value.type != JsonValue::Type::Number) {
        throw std::invalid_argument("expected JSON number");
    }
    return value.number_value;
}

bool as_bool(const JsonValue& value) {
    if (value.type != JsonValue::Type::Bool) {
        throw std::invalid_argument("expected JSON bool");
    }
    return value.bool_value;
}

ElementId as_id(const JsonValue& value) {
    const auto number = as_number(value);
    if (number < 0.0) {
        throw std::invalid_argument("expected non-negative id");
    }
    return static_cast<ElementId>(number);
}

Point2 parse_point(const JsonValue& value) {
    const auto& object = as_object(value);
    return Point2{
        .x = as_number(field(object, "x")),
        .y = as_number(field(object, "y")),
    };
}

Line2 parse_line(const JsonValue& value) {
    const auto& object = as_object(value);
    return Line2{
        .start = parse_point(field(object, "start")),
        .end = parse_point(field(object, "end")),
    };
}

WallJoinKind parse_join_kind(const std::string& value) {
    if (value == "End") {
        return WallJoinKind::End;
    }
    if (value == "Tee") {
        return WallJoinKind::Tee;
    }
    if (value == "Cross") {
        return WallJoinKind::Cross;
    }
    throw std::invalid_argument("invalid wall join kind");
}

OpeningKind parse_opening_kind(const std::string& value) {
    if (value == "Door") {
        return OpeningKind::Door;
    }
    if (value == "Window") {
        return OpeningKind::Window;
    }
    throw std::invalid_argument("invalid opening kind");
}

std::string join_kind_to_string(WallJoinKind kind) {
    switch (kind) {
    case WallJoinKind::End:
        return "End";
    case WallJoinKind::Tee:
        return "Tee";
    case WallJoinKind::Cross:
        return "Cross";
    }
    return "End";
}

std::string opening_kind_to_string(OpeningKind kind) {
    switch (kind) {
    case OpeningKind::Door:
        return "Door";
    case OpeningKind::Window:
        return "Window";
    }
    return "Door";
}

void write_point(std::ostream& out, Point2 point) {
    out << "{\"x\":" << point.x << ",\"y\":" << point.y << '}';
}

void write_line(std::ostream& out, Line2 line) {
    out << "{\"start\":";
    write_point(out, line.start);
    out << ",\"end\":";
    write_point(out, line.end);
    out << '}';
}

void write_ids(std::ostream& out, const std::vector<ElementId>& ids) {
    out << '[';
    for (std::size_t index = 0; index < ids.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        out << ids[index];
    }
    out << ']';
}

void write_points(std::ostream& out, const std::vector<Point2>& points) {
    out << '[';
    for (std::size_t index = 0; index < points.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        write_point(out, points[index]);
    }
    out << ']';
}

} // namespace

std::string Document::to_json() const {
    for (const auto& [material_id, material] : materials()) {
        (void)material_id;
        if (material.density_kg_per_m3.has_value()) {
            ensure_finite(*material.density_kg_per_m3, "material.density");
        }
        if (material.unit_cost.has_value()) {
            ensure_finite(*material.unit_cost, "material.unit_cost");
        }
    }
    for (const auto& [wall_type_id, wall_type] : wall_types()) {
        (void)wall_type_id;
        for (const auto& layer : wall_type.layers) {
            ensure_finite(layer.thickness_meters, "wall_type.layer.thickness");
        }
    }
    for (const auto& [assembly_id, assembly] : layered_assemblies()) {
        (void)assembly_id;
        for (const auto& layer : assembly.layers) {
            ensure_finite(layer.thickness_meters, "assembly.layer.thickness");
        }
    }
    for (const auto& [system_id, system] : floor_systems()) {
        (void)system_id;
        ensure_finite(system.area_square_meters, "floor_system.area");
        for (const auto& point : system.boundary_polygon) {
            ensure_finite_point(point, "floor_system.boundary_polygon");
        }
    }
    for (const auto& [system_id, system] : ceiling_systems()) {
        (void)system_id;
        ensure_finite(system.area_square_meters, "ceiling_system.area");
        ensure_finite(system.height_offset_meters, "ceiling_system.height_offset");
        for (const auto& point : system.boundary_polygon) {
            ensure_finite_point(point, "ceiling_system.boundary_polygon");
        }
    }
    for (const auto& element : elements_) {
        if (const auto* level = element.level()) {
            ensure_finite(level->elevation_meters, "level.elevation");
            ensure_finite(level->default_wall_height_meters, "level.default_wall_height");
        } else if (const auto* wall = element.wall()) {
            ensure_finite_line(wall->axis, "wall.axis");
            ensure_finite(wall->thickness_meters, "wall.thickness");
            ensure_finite(wall->height_meters, "wall.height");
            for (const auto& join : wall->joins) {
                ensure_finite_point(join.point, "wall.join.point");
                ensure_finite_line(join.other_axis, "wall.join.other_axis");
            }
            for (const auto& opening : wall->openings) {
                ensure_finite(opening.offset_meters, "wall.opening.offset");
                ensure_finite(opening.width_meters, "wall.opening.width");
                ensure_finite(opening.height_meters, "wall.opening.height");
                ensure_finite(opening.sill_height_meters, "wall.opening.sill_height");
            }
        } else if (const auto* door = element.door()) {
            ensure_finite(door->offset_meters, "door.offset");
            ensure_finite(door->width_meters, "door.width");
            ensure_finite(door->height_meters, "door.height");
        } else if (const auto* window = element.window()) {
            ensure_finite(window->offset_meters, "window.offset");
            ensure_finite(window->width_meters, "window.width");
            ensure_finite(window->height_meters, "window.height");
            ensure_finite(window->sill_height_meters, "window.sill_height");
        } else if (const auto* room = element.room()) {
            ensure_finite(room->centerline_area_square_meters, "room.centerline_area");
            ensure_finite(room->interior_area_square_meters, "room.interior_area");
            ensure_finite(room->centerline_perimeter_meters, "room.centerline_perimeter");
            ensure_finite(room->interior_perimeter_meters, "room.interior_perimeter");
            ensure_finite(room->floor_finish_area_square_meters, "room.floor_finish_area");
            ensure_finite(room->ceiling_area_square_meters, "room.ceiling_area");
            ensure_finite(room->baseboard_length_meters, "room.baseboard_length");
            ensure_finite(room->interior_wall_finish_area_square_meters, "room.interior_wall_finish_area");
            for (const auto& point : room->centerline_boundary_polygon) {
                ensure_finite_point(point, "room.centerline_boundary_polygon");
            }
            for (const auto& point : room->interior_boundary_polygon) {
                ensure_finite_point(point, "room.interior_boundary_polygon");
            }
        } else if (const auto* slab = element.slab()) {
            ensure_finite(slab->thickness_meters, "slab.thickness");
            ensure_finite(slab->area_square_meters, "slab.area");
            ensure_finite(slab->volume_cubic_meters, "slab.volume");
            ensure_finite(slab->elevation_offset_meters, "slab.elevation_offset");
            for (const auto& point : slab->boundary_polygon) {
                ensure_finite_point(point, "slab.boundary_polygon");
            }
        } else if (const auto* roof = element.roof()) {
            ensure_finite(roof->thickness_meters, "roof.thickness");
            ensure_finite(roof->area_square_meters, "roof.area");
            ensure_finite(roof->volume_cubic_meters, "roof.volume");
            if (roof->slope_degrees.has_value()) {
                ensure_finite(*roof->slope_degrees, "roof.slope_degrees");
            }
            if (roof->overhang_meters.has_value()) {
                ensure_finite(*roof->overhang_meters, "roof.overhang_meters");
            }
            for (const auto& point : roof->boundary_polygon) {
                ensure_finite_point(point, "roof.boundary_polygon");
            }
        } else if (const auto* column = element.column()) {
            ensure_finite_point(column->position, "column.position");
            ensure_finite(column->width_meters, "column.width");
            ensure_finite(column->depth_meters, "column.depth");
            ensure_finite(column->height_meters, "column.height");
            ensure_finite(column->volume_cubic_meters, "column.volume");
        } else if (const auto* beam = element.beam()) {
            ensure_finite_point(beam->start, "beam.start");
            ensure_finite_point(beam->end, "beam.end");
            ensure_finite(beam->width_meters, "beam.width");
            ensure_finite(beam->height_meters, "beam.height");
            ensure_finite(beam->length_meters, "beam.length");
            ensure_finite(beam->volume_cubic_meters, "beam.volume");
        } else if (const auto* stair = element.stair()) {
            ensure_finite_point(stair->start, "stair.start");
            ensure_finite_point(stair->direction, "stair.direction");
            ensure_finite(stair->width_meters, "stair.width");
            ensure_finite(stair->total_rise_meters, "stair.total_rise");
            ensure_finite(stair->total_run_meters, "stair.total_run");
            ensure_finite(stair->footprint_area_square_meters, "stair.footprint_area");
            ensure_finite(stair->volume_cubic_meters, "stair.volume");
        }
    }

    std::ostringstream out;
    out << "{\"schema\":\"tbe.document.v1\",";
    out << "\"name\":\"" << escape_json(name_) << "\",";
    out << "\"next_id\":" << next_id_ << ',';
    out << "\"materials\":[";
    {
        auto first = true;
        for (const auto& [material_id, material] : materials()) {
            if (!first) {
                out << ',';
            }
            first = false;
            out << "{\"material_id\":" << material_id
                << ",\"name\":\"" << escape_json(material.name) << "\""
                << ",\"category\":\"" << material_category_to_string(material.category) << "\"";
            if (material.density_kg_per_m3.has_value()) {
                out << ",\"density\":" << *material.density_kg_per_m3;
            }
            if (material.unit_cost.has_value()) {
                out << ",\"unit_cost\":" << *material.unit_cost;
            }
            out << ",\"metadata\":{";
            auto first_meta = true;
            for (const auto& [key, value] : material.metadata) {
                if (!first_meta) {
                    out << ',';
                }
                first_meta = false;
                out << "\"" << escape_json(key) << "\":\"" << escape_json(value) << "\"";
            }
            out << "}}";
        }
    }
    out << "],";
    out << "\"wall_types\":[";
    {
        auto first = true;
        for (const auto& [wall_type_id, wall_type] : wall_types()) {
            if (!first) {
                out << ',';
            }
            first = false;
            out << "{\"wall_type_id\":" << wall_type_id
                << ",\"name\":\"" << escape_json(wall_type.name) << "\",\"layers\":[";
            for (std::size_t index = 0; index < wall_type.layers.size(); ++index) {
                if (index != 0) {
                    out << ',';
                }
                const auto& layer = wall_type.layers[index];
                out << "{\"material_id\":" << layer.material_id
                    << ",\"thickness\":" << layer.thickness_meters
                    << ",\"function\":\"" << wall_layer_function_to_string(layer.function) << "\"}";
            }
            out << "]}";
        }
    }
    out << "],";
    out << "\"assemblies\":[";
    {
        auto first = true;
        for (const auto& [assembly_id, assembly] : layered_assemblies()) {
            if (!first) {
                out << ',';
            }
            first = false;
            out << "{\"assembly_id\":" << assembly_id
                << ",\"kind\":\"" << layered_assembly_kind_to_string(assembly.kind) << "\""
                << ",\"name\":\"" << escape_json(assembly.name) << "\",\"layers\":[";
            for (std::size_t index = 0; index < assembly.layers.size(); ++index) {
                if (index != 0) {
                    out << ',';
                }
                const auto& layer = assembly.layers[index];
                out << "{\"material_id\":" << layer.material_id
                    << ",\"thickness\":" << layer.thickness_meters
                    << ",\"function\":\"" << wall_layer_function_to_string(layer.function) << "\"}";
            }
            out << "]}";
        }
    }
    out << "],";
    out << "\"floor_systems\":[";
    {
        auto first = true;
        for (const auto& [system_id, system] : floor_systems()) {
            if (!first) {
                out << ',';
            }
            first = false;
            out << "{\"system_id\":" << system_id
                << ",\"room_id\":" << system.room_id
                << ",\"level_id\":" << system.level_id
                << ",\"assembly_id\":" << system.assembly_id
                << ",\"area\":" << system.area_square_meters
                << ",\"manual_profile\":" << (system.manual_profile ? "true" : "false")
                << ",\"dirty\":" << (system.dirty ? "true" : "false")
                << ",\"boundary_polygon\":";
            write_points(out, system.boundary_polygon);
            out << '}';
        }
    }
    out << "],";
    out << "\"ceiling_systems\":[";
    {
        auto first = true;
        for (const auto& [system_id, system] : ceiling_systems()) {
            if (!first) {
                out << ',';
            }
            first = false;
            out << "{\"system_id\":" << system_id
                << ",\"room_id\":" << system.room_id
                << ",\"level_id\":" << system.level_id
                << ",\"assembly_id\":" << system.assembly_id
                << ",\"area\":" << system.area_square_meters
                << ",\"height_offset\":" << system.height_offset_meters
                << ",\"manual_profile\":" << (system.manual_profile ? "true" : "false")
                << ",\"dirty\":" << (system.dirty ? "true" : "false")
                << ",\"boundary_polygon\":";
            write_points(out, system.boundary_polygon);
            out << '}';
        }
    }
    out << "],";
    out << "\"elements\":[";

    for (std::size_t index = 0; index < elements_.size(); ++index) {
        const auto& element = elements_[index];
        if (index != 0) {
            out << ',';
        }

        out << "{\"id\":" << element.id();
        out << ",\"kind\":\"" << kind_to_string(element.kind()) << '"';
        out << ",\"name\":\"" << escape_json(element.name()) << '"';
        out << ",\"revision\":" << element.revision();

        if (const auto* level = element.level()) {
            out << ",\"level\":{\"name\":\"" << escape_json(level->name) << "\",";
            out << "\"elevation\":" << level->elevation_meters << ',';
            out << "\"default_wall_height\":" << level->default_wall_height_meters << ',';
            out << "\"is_story\":" << (level->is_story ? "true" : "false") << '}';
        } else if (const auto* wall = element.wall()) {
            out << ",\"wall\":{\"level_id\":" << wall->level_id << ",\"wall_type_id\":" << wall->wall_type_id << ",\"axis\":";
            write_line(out, wall->axis);
            out << ",\"thickness\":" << wall->thickness_meters;
            out << ",\"height\":" << wall->height_meters;
            out << ",\"base_level_id\":" << wall->base_level_id;
            out << ",\"top_level_id\":" << wall->top_level_id;
            out << ",\"base_offset\":" << wall->base_offset_meters;
            out << ",\"top_offset\":" << wall->top_offset_meters;
            out << ",\"height_mode\":\"" << (wall->height_mode == WallHeightMode::TopLevel ? "TopLevel" : "Unconnected") << "\"";
            out << ",\"joins\":[";
            for (std::size_t join_index = 0; join_index < wall->joins.size(); ++join_index) {
                if (join_index != 0) {
                    out << ',';
                }
                const auto& join = wall->joins[join_index];
                out << "{\"other_wall_id\":" << join.other_wall_id << ",\"point\":";
                write_point(out, join.point);
                out << ",\"other_axis\":";
                write_line(out, join.other_axis);
                out << ",\"kind\":\"" << join_kind_to_string(join.kind) << "\"}";
            }
            out << "],\"openings\":[";
            for (std::size_t opening_index = 0; opening_index < wall->openings.size(); ++opening_index) {
                if (opening_index != 0) {
                    out << ',';
                }
                const auto& opening = wall->openings[opening_index];
                out << "{\"element_id\":" << opening.element_id;
                out << ",\"kind\":\"" << opening_kind_to_string(opening.kind) << '"';
                out << ",\"offset\":" << opening.offset_meters;
                out << ",\"width\":" << opening.width_meters;
                out << ",\"height\":" << opening.height_meters;
                out << ",\"sill_height\":" << opening.sill_height_meters << '}';
            }
            out << "]}";
        } else if (const auto* door = element.door()) {
            out << ",\"door\":{\"level_id\":" << door->level_id;
            out << ",\"host_wall_id\":" << door->host_wall_id;
            out << ",\"offset\":" << door->offset_meters;
            out << ",\"width\":" << door->width_meters;
            out << ",\"height\":" << door->height_meters;
            out << ",\"level_locked\":" << (door->level_locked ? "true" : "false") << '}';
        } else if (const auto* window = element.window()) {
            out << ",\"window\":{\"level_id\":" << window->level_id;
            out << ",\"host_wall_id\":" << window->host_wall_id;
            out << ",\"offset\":" << window->offset_meters;
            out << ",\"width\":" << window->width_meters;
            out << ",\"height\":" << window->height_meters;
            out << ",\"sill_height\":" << window->sill_height_meters;
            out << ",\"level_locked\":" << (window->level_locked ? "true" : "false") << '}';
        } else if (const auto* room = element.room()) {
            out << ",\"room\":{\"boundary_wall_ids\":";
            write_ids(out, room->boundary_wall_ids);
            out << ",\"level_id\":" << room->level_id;
            out << ",\"preferred_boundary_mode\":\"" << (room->preferred_boundary_mode == RoomBoundaryMode::InteriorFinishFace ? "InteriorFinishFace" : "Centerline") << '"';
            out << ",\"centerline_area\":" << room->centerline_area_square_meters;
            out << ",\"interior_area\":" << room->interior_area_square_meters;
            out << ",\"centerline_perimeter\":" << room->centerline_perimeter_meters;
            out << ",\"interior_perimeter\":" << room->interior_perimeter_meters;
            out << ",\"floor_finish_area\":" << room->floor_finish_area_square_meters;
            out << ",\"ceiling_area\":" << room->ceiling_area_square_meters;
            out << ",\"baseboard_length\":" << room->baseboard_length_meters;
            out << ",\"interior_wall_finish_area\":" << room->interior_wall_finish_area_square_meters;
            out << ",\"centerline_boundary_polygon\":";
            write_points(out, room->centerline_boundary_polygon);
            out << ",\"interior_boundary_polygon\":";
            write_points(out, room->interior_boundary_polygon);
            out << '}';
        } else if (const auto* slab = element.slab()) {
            out << ",\"slab\":{\"level_id\":" << slab->level_id
                << ",\"thickness\":" << slab->thickness_meters
                << ",\"material_id\":" << slab->material_id
                << ",\"assembly_id\":" << slab->assembly_id
                << ",\"elevation_offset\":" << slab->elevation_offset_meters
                << ",\"generated_geometry_dirty\":" << (slab->generated_geometry_dirty ? "true" : "false")
                << ",\"area\":" << slab->area_square_meters
                << ",\"volume\":" << slab->volume_cubic_meters
                << ",\"boundary_polygon\":";
            write_points(out, slab->boundary_polygon);
            out << '}';
        } else if (const auto* roof = element.roof()) {
            out << ",\"roof\":{\"level_id\":" << roof->level_id
                << ",\"roof_type\":\"" << roof_type_to_string(roof->roof_type) << "\""
                << ",\"thickness\":" << roof->thickness_meters
                << ",\"material_id\":" << roof->material_id
                << ",\"assembly_id\":" << roof->assembly_id
                << ",\"generated_geometry_dirty\":" << (roof->generated_geometry_dirty ? "true" : "false")
                << ",\"area\":" << roof->area_square_meters
                << ",\"volume\":" << roof->volume_cubic_meters;
            if (roof->slope_degrees.has_value()) {
                out << ",\"slope_degrees\":" << *roof->slope_degrees;
            }
            if (roof->overhang_meters.has_value()) {
                out << ",\"overhang_meters\":" << *roof->overhang_meters;
            }
            out << ",\"boundary_polygon\":";
            write_points(out, roof->boundary_polygon);
            out << '}';
        } else if (const auto* column = element.column()) {
            out << ",\"column\":{\"level_id\":" << column->level_id
                << ",\"position\":";
            write_point(out, column->position);
            out << ",\"width\":" << column->width_meters
                << ",\"depth\":" << column->depth_meters
                << ",\"height\":" << column->height_meters
                << ",\"material_id\":" << column->material_id
                << ",\"generated_geometry_dirty\":" << (column->generated_geometry_dirty ? "true" : "false")
                << ",\"volume\":" << column->volume_cubic_meters << '}';
        } else if (const auto* beam = element.beam()) {
            out << ",\"beam\":{\"level_id\":" << beam->level_id
                << ",\"start\":";
            write_point(out, beam->start);
            out << ",\"end\":";
            write_point(out, beam->end);
            out << ",\"width\":" << beam->width_meters
                << ",\"height\":" << beam->height_meters
                << ",\"material_id\":" << beam->material_id
                << ",\"generated_geometry_dirty\":" << (beam->generated_geometry_dirty ? "true" : "false")
                << ",\"length\":" << beam->length_meters
                << ",\"volume\":" << beam->volume_cubic_meters << '}';
        } else if (const auto* stair = element.stair()) {
            out << ",\"stair\":{\"base_level_id\":" << stair->base_level_id
                << ",\"top_level_id\":" << stair->top_level_id
                << ",\"start\":";
            write_point(out, stair->start);
            out << ",\"direction\":";
            write_point(out, stair->direction);
            out << ",\"width\":" << stair->width_meters
                << ",\"total_rise\":" << stair->total_rise_meters
                << ",\"total_run\":" << stair->total_run_meters
                << ",\"riser_count\":" << stair->riser_count
                << ",\"tread_count\":" << stair->tread_count
                << ",\"material_id\":" << stair->material_id
                << ",\"generated_geometry_dirty\":" << (stair->generated_geometry_dirty ? "true" : "false")
                << ",\"footprint_area\":" << stair->footprint_area_square_meters
                << ",\"volume\":" << stair->volume_cubic_meters << '}';
        }

        out << '}';
    }

    out << "]}";
    return out.str();
}

Document Document::from_json(std::string_view json) {
    const auto root = JsonParser(json).parse();
    const auto& root_object = as_object(root);

    auto document = Document(as_string(field(root_object, "name")));
    std::vector<Element> elements;

    if (const auto materials_it = root_object.find("materials"); materials_it != root_object.end()) {
        for (const auto& item : as_array(materials_it->second)) {
            const auto& object = as_object(item);
            MaterialDefinition material{
                .material_id = as_id(field(object, "material_id")),
                .name = as_string(field(object, "name")),
                .category = string_to_material_category(as_string(field(object, "category"))),
            };
            if (const auto density = object.find("density"); density != object.end()) {
                material.density_kg_per_m3 = as_number(density->second);
            }
            if (const auto unit_cost = object.find("unit_cost"); unit_cost != object.end()) {
                material.unit_cost = as_number(unit_cost->second);
            }
            if (const auto metadata = object.find("metadata"); metadata != object.end()) {
                for (const auto& [key, value] : as_object(metadata->second)) {
                    material.metadata[key] = as_string(value);
                }
            }
            document.update_material(std::move(material));
        }
    }

    if (const auto wall_types_it = root_object.find("wall_types"); wall_types_it != root_object.end()) {
        for (const auto& item : as_array(wall_types_it->second)) {
            const auto& object = as_object(item);
            WallTypeData wall_type{
                .wall_type_id = as_id(field(object, "wall_type_id")),
                .name = as_string(field(object, "name")),
            };
            for (const auto& layer_value : as_array(field(object, "layers"))) {
                const auto& layer = as_object(layer_value);
                wall_type.layers.push_back(WallAssemblyLayer{
                    .material_id = as_id(field(layer, "material_id")),
                    .thickness_meters = as_number(field(layer, "thickness")),
                    .function = string_to_wall_layer_function(as_string(field(layer, "function"))),
                });
            }
            document.update_wall_type(std::move(wall_type));
        }
    }

    if (const auto assemblies_it = root_object.find("assemblies"); assemblies_it != root_object.end()) {
        for (const auto& item : as_array(assemblies_it->second)) {
            const auto& object = as_object(item);
            LayeredAssemblyData assembly{
                .assembly_id = as_id(field(object, "assembly_id")),
                .kind = string_to_layered_assembly_kind(as_string(field(object, "kind"))),
                .name = as_string(field(object, "name")),
            };
            for (const auto& layer_value : as_array(field(object, "layers"))) {
                const auto& layer = as_object(layer_value);
                assembly.layers.push_back(WallAssemblyLayer{
                    .material_id = as_id(field(layer, "material_id")),
                    .thickness_meters = as_number(field(layer, "thickness")),
                    .function = string_to_wall_layer_function(as_string(field(layer, "function"))),
                });
            }
            document.update_layered_assembly(std::move(assembly));
        }
    }

    if (const auto systems_it = root_object.find("floor_systems"); systems_it != root_object.end()) {
        for (const auto& item : as_array(systems_it->second)) {
            const auto& object = as_object(item);
            FloorSystemData system{
                .system_id = as_id(field(object, "system_id")),
                .room_id = as_id(field(object, "room_id")),
                .level_id = as_id(field(object, "level_id")),
                .assembly_id = as_id(field(object, "assembly_id")),
                .area_square_meters = as_number(field(object, "area")),
                .manual_profile = object.find("manual_profile") != object.end() && as_bool(field(object, "manual_profile")),
                .dirty = object.find("dirty") != object.end() && as_bool(field(object, "dirty")),
            };
            for (const auto& point_value : as_array(field(object, "boundary_polygon"))) {
                system.boundary_polygon.push_back(parse_point(point_value));
            }
            document.floor_systems_[system.system_id] = std::move(system);
        }
    }

    if (const auto systems_it = root_object.find("ceiling_systems"); systems_it != root_object.end()) {
        for (const auto& item : as_array(systems_it->second)) {
            const auto& object = as_object(item);
            CeilingSystemData system{
                .system_id = as_id(field(object, "system_id")),
                .room_id = as_id(field(object, "room_id")),
                .level_id = as_id(field(object, "level_id")),
                .assembly_id = as_id(field(object, "assembly_id")),
                .area_square_meters = as_number(field(object, "area")),
                .height_offset_meters = object.find("height_offset") != object.end() ? as_number(field(object, "height_offset")) : 0.0,
                .manual_profile = object.find("manual_profile") != object.end() && as_bool(field(object, "manual_profile")),
                .dirty = object.find("dirty") != object.end() && as_bool(field(object, "dirty")),
            };
            for (const auto& point_value : as_array(field(object, "boundary_polygon"))) {
                system.boundary_polygon.push_back(parse_point(point_value));
            }
            document.ceiling_systems_[system.system_id] = std::move(system);
        }
    }

    for (const auto& item : as_array(field(root_object, "elements"))) {
        const auto& object = as_object(item);
        const auto id = as_id(field(object, "id"));
        const auto kind = string_to_kind(as_string(field(object, "kind")));
        auto name = as_string(field(object, "name"));
        const auto revision = static_cast<Revision>(as_id(field(object, "revision")));

        if (kind == ElementKind::Level) {
            const auto& level = as_object(field(object, "level"));
            elements.emplace_back(id, kind, std::move(name), LevelData{
                .name = as_string(field(level, "name")),
                .elevation_meters = as_number(field(level, "elevation")),
                .default_wall_height_meters = as_number(field(level, "default_wall_height")),
                .is_story = level.find("is_story") == level.end() ? true : as_bool(field(level, "is_story")),
            }, revision);
        } else if (kind == ElementKind::Wall) {
            const auto& wall = as_object(field(object, "wall"));
            WallData data{
                .level_id = as_id(field(wall, "level_id")),
                .base_level_id = wall.find("base_level_id") != wall.end() ? as_id(field(wall, "base_level_id")) : as_id(field(wall, "level_id")),
                .top_level_id = wall.find("top_level_id") != wall.end() ? as_id(field(wall, "top_level_id")) : 0,
                .wall_type_id = wall.find("wall_type_id") != wall.end() ? as_id(field(wall, "wall_type_id")) : 0,
                .axis = parse_line(field(wall, "axis")),
                .thickness_meters = as_number(field(wall, "thickness")),
                .height_meters = as_number(field(wall, "height")),
                .base_offset_meters = wall.find("base_offset") != wall.end() ? as_number(field(wall, "base_offset")) : 0.0,
                .top_offset_meters = wall.find("top_offset") != wall.end() ? as_number(field(wall, "top_offset")) : 0.0,
                .height_mode = wall.find("height_mode") != wall.end() && as_string(field(wall, "height_mode")) == "TopLevel"
                    ? WallHeightMode::TopLevel
                    : WallHeightMode::Unconnected,
            };

            for (const auto& join_value : as_array(field(wall, "joins"))) {
                const auto& join = as_object(join_value);
                data.joins.push_back(WallJoin{
                    .other_wall_id = as_id(field(join, "other_wall_id")),
                    .point = parse_point(field(join, "point")),
                    .other_axis = parse_line(field(join, "other_axis")),
                    .kind = parse_join_kind(as_string(field(join, "kind"))),
                });
            }
            for (const auto& opening_value : as_array(field(wall, "openings"))) {
                const auto& opening = as_object(opening_value);
                data.openings.push_back(HostedOpening{
                    .element_id = as_id(field(opening, "element_id")),
                    .kind = parse_opening_kind(as_string(field(opening, "kind"))),
                    .offset_meters = as_number(field(opening, "offset")),
                    .width_meters = as_number(field(opening, "width")),
                    .height_meters = as_number(field(opening, "height")),
                    .sill_height_meters = as_number(field(opening, "sill_height")),
                });
            }
            data.geometry.dirty = true;
            elements.emplace_back(id, kind, std::move(name), data, revision);
        } else if (kind == ElementKind::Door) {
            const auto& door = as_object(field(object, "door"));
            elements.emplace_back(id, kind, std::move(name), DoorData{
                .level_id = as_id(field(door, "level_id")),
                .host_wall_id = as_id(field(door, "host_wall_id")),
                .offset_meters = as_number(field(door, "offset")),
                .width_meters = as_number(field(door, "width")),
                .height_meters = as_number(field(door, "height")),
                .level_locked = door.find("level_locked") == door.end() ? true : as_bool(field(door, "level_locked")),
            }, revision);
        } else if (kind == ElementKind::Window) {
            const auto& window = as_object(field(object, "window"));
            elements.emplace_back(id, kind, std::move(name), WindowData{
                .level_id = as_id(field(window, "level_id")),
                .host_wall_id = as_id(field(window, "host_wall_id")),
                .offset_meters = as_number(field(window, "offset")),
                .width_meters = as_number(field(window, "width")),
                .height_meters = as_number(field(window, "height")),
                .sill_height_meters = as_number(field(window, "sill_height")),
                .level_locked = window.find("level_locked") == window.end() ? true : as_bool(field(window, "level_locked")),
            }, revision);
        } else if (kind == ElementKind::Room) {
            const auto& room = as_object(field(object, "room"));
            RoomData data{
                .level_id = as_id(field(room, "level_id")),
            };
            const auto preferred_mode = room.find("preferred_boundary_mode");
            if (preferred_mode != room.end() && as_string(preferred_mode->second) == "InteriorFinishFace") {
                data.preferred_boundary_mode = RoomBoundaryMode::InteriorFinishFace;
            }
            for (const auto& id_value : as_array(field(room, "boundary_wall_ids"))) {
                data.boundary_wall_ids.push_back(as_id(id_value));
            }
            if (const auto found = room.find("centerline_boundary_polygon"); found != room.end()) {
                for (const auto& point_value : as_array(found->second)) {
                    data.centerline_boundary_polygon.push_back(parse_point(point_value));
                }
            } else {
                for (const auto& point_value : as_array(field(room, "boundary_polygon"))) {
                    data.centerline_boundary_polygon.push_back(parse_point(point_value));
                }
            }
            if (const auto found = room.find("interior_boundary_polygon"); found != room.end()) {
                for (const auto& point_value : as_array(found->second)) {
                    data.interior_boundary_polygon.push_back(parse_point(point_value));
                }
            }
            data.centerline_area_square_meters = room.find("centerline_area") != room.end()
                ? as_number(field(room, "centerline_area"))
                : as_number(field(room, "area"));
            data.interior_area_square_meters = room.find("interior_area") != room.end()
                ? as_number(field(room, "interior_area"))
                : data.centerline_area_square_meters;
            data.centerline_perimeter_meters = room.find("centerline_perimeter") != room.end()
                ? as_number(field(room, "centerline_perimeter"))
                : as_number(field(room, "perimeter"));
            data.interior_perimeter_meters = room.find("interior_perimeter") != room.end()
                ? as_number(field(room, "interior_perimeter"))
                : data.centerline_perimeter_meters;
            data.floor_finish_area_square_meters = room.find("floor_finish_area") != room.end()
                ? as_number(field(room, "floor_finish_area"))
                : data.interior_area_square_meters;
            data.ceiling_area_square_meters = room.find("ceiling_area") != room.end()
                ? as_number(field(room, "ceiling_area"))
                : data.interior_area_square_meters;
            data.baseboard_length_meters = room.find("baseboard_length") != room.end()
                ? as_number(field(room, "baseboard_length"))
                : data.interior_perimeter_meters;
            data.interior_wall_finish_area_square_meters = room.find("interior_wall_finish_area") != room.end()
                ? as_number(field(room, "interior_wall_finish_area"))
                : 0.0;
            elements.emplace_back(id, kind, std::move(name), data, revision);
        } else if (kind == ElementKind::Slab) {
            const auto& slab = as_object(field(object, "slab"));
            SlabData data{
                .level_id = as_id(field(slab, "level_id")),
                .thickness_meters = as_number(field(slab, "thickness")),
                .material_id = slab.find("material_id") != slab.end() ? as_id(field(slab, "material_id")) : 0,
                .assembly_id = slab.find("assembly_id") != slab.end() ? as_id(field(slab, "assembly_id")) : 0,
                .elevation_offset_meters = slab.find("elevation_offset") != slab.end() ? as_number(field(slab, "elevation_offset")) : 0.0,
                .generated_geometry_dirty = true,
                .area_square_meters = slab.find("area") != slab.end() ? as_number(field(slab, "area")) : 0.0,
                .volume_cubic_meters = slab.find("volume") != slab.end() ? as_number(field(slab, "volume")) : 0.0,
            };
            for (const auto& point_value : as_array(field(slab, "boundary_polygon"))) {
                data.boundary_polygon.push_back(parse_point(point_value));
            }
            data.mesh = {};
            elements.emplace_back(id, kind, std::move(name), data, revision);
        } else if (kind == ElementKind::Roof) {
            const auto& roof = as_object(field(object, "roof"));
            RoofData data{
                .level_id = as_id(field(roof, "level_id")),
                .boundary_polygon = {},
                .roof_type = string_to_roof_type(as_string(field(roof, "roof_type"))),
                .thickness_meters = as_number(field(roof, "thickness")),
                .material_id = roof.find("material_id") != roof.end() ? as_id(field(roof, "material_id")) : 0,
                .assembly_id = roof.find("assembly_id") != roof.end() ? as_id(field(roof, "assembly_id")) : 0,
                .generated_geometry_dirty = true,
                .mesh = {},
                .area_square_meters = roof.find("area") != roof.end() ? as_number(field(roof, "area")) : 0.0,
                .volume_cubic_meters = roof.find("volume") != roof.end() ? as_number(field(roof, "volume")) : 0.0,
            };
            if (const auto found = roof.find("slope_degrees"); found != roof.end()) {
                data.slope_degrees = as_number(found->second);
            }
            if (const auto found = roof.find("overhang_meters"); found != roof.end()) {
                data.overhang_meters = as_number(found->second);
            }
            for (const auto& point_value : as_array(field(roof, "boundary_polygon"))) {
                data.boundary_polygon.push_back(parse_point(point_value));
            }
            elements.emplace_back(id, kind, std::move(name), data, revision);
        } else if (kind == ElementKind::Column) {
            const auto& column = as_object(field(object, "column"));
            elements.emplace_back(id, kind, std::move(name), ColumnData{
                .level_id = as_id(field(column, "level_id")),
                .position = parse_point(field(column, "position")),
                .width_meters = as_number(field(column, "width")),
                .depth_meters = as_number(field(column, "depth")),
                .height_meters = as_number(field(column, "height")),
                .material_id = column.find("material_id") != column.end() ? as_id(field(column, "material_id")) : 0,
                .generated_geometry_dirty = true,
                .mesh = {},
                .volume_cubic_meters = column.find("volume") != column.end() ? as_number(field(column, "volume")) : 0.0,
            }, revision);
        } else if (kind == ElementKind::Beam) {
            const auto& beam = as_object(field(object, "beam"));
            elements.emplace_back(id, kind, std::move(name), BeamData{
                .level_id = as_id(field(beam, "level_id")),
                .start = parse_point(field(beam, "start")),
                .end = parse_point(field(beam, "end")),
                .width_meters = as_number(field(beam, "width")),
                .height_meters = as_number(field(beam, "height")),
                .material_id = beam.find("material_id") != beam.end() ? as_id(field(beam, "material_id")) : 0,
                .generated_geometry_dirty = true,
                .mesh = {},
                .length_meters = beam.find("length") != beam.end() ? as_number(field(beam, "length")) : 0.0,
                .volume_cubic_meters = beam.find("volume") != beam.end() ? as_number(field(beam, "volume")) : 0.0,
            }, revision);
        } else if (kind == ElementKind::Stair) {
            const auto& stair = as_object(field(object, "stair"));
            elements.emplace_back(id, kind, std::move(name), StairData{
                .base_level_id = as_id(field(stair, "base_level_id")),
                .top_level_id = stair.find("top_level_id") != stair.end() ? as_id(field(stair, "top_level_id")) : 0,
                .start = parse_point(field(stair, "start")),
                .direction = parse_point(field(stair, "direction")),
                .width_meters = as_number(field(stair, "width")),
                .total_rise_meters = as_number(field(stair, "total_rise")),
                .total_run_meters = as_number(field(stair, "total_run")),
                .riser_count = static_cast<int>(as_number(field(stair, "riser_count"))),
                .tread_count = static_cast<int>(as_number(field(stair, "tread_count"))),
                .material_id = stair.find("material_id") != stair.end() ? as_id(field(stair, "material_id")) : 0,
                .generated_geometry_dirty = true,
                .mesh = {},
                .footprint_area_square_meters = stair.find("footprint_area") != stair.end() ? as_number(field(stair, "footprint_area")) : 0.0,
                .volume_cubic_meters = stair.find("volume") != stair.end() ? as_number(field(stair, "volume")) : 0.0,
            }, revision);
        }
    }

    document.replace_state(as_string(field(root_object, "name")), std::move(elements), as_id(field(root_object, "next_id")));
    return document;
}

} // namespace tbe::core
