#include "tbe/core/Document.hpp"

#include <charconv>
#include <cctype>
#include <map>
#include <sstream>
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
            throw std::invalid_argument("unexpected trailing JSON data");
        }
        return value;
    }

private:
    void skip_ws() {
        while (pos_ < input_.size() && std::isspace(static_cast<unsigned char>(input_[pos_]))) {
            ++pos_;
        }
    }

    char peek() {
        skip_ws();
        if (pos_ >= input_.size()) {
            throw std::invalid_argument("unexpected end of JSON");
        }
        return input_[pos_];
    }

    char consume() {
        if (pos_ >= input_.size()) {
            throw std::invalid_argument("unexpected end of JSON");
        }
        return input_[pos_++];
    }

    void expect(char expected) {
        skip_ws();
        if (consume() != expected) {
            throw std::invalid_argument("unexpected JSON token");
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
        throw std::invalid_argument("invalid JSON value");
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
                throw std::invalid_argument("expected JSON object separator");
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
                throw std::invalid_argument("expected JSON array separator");
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
                    throw std::invalid_argument("unsupported JSON escape");
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

        auto value = 0.0;
        const auto token = input_.substr(start, pos_ - start);
        const auto parsed = std::from_chars(token.data(), token.data() + token.size(), value);
        if (parsed.ec != std::errc{}) {
            throw std::invalid_argument("invalid JSON number");
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
    case ElementKind::Column:
        return "Column";
    case ElementKind::Slab:
        return "Slab";
    }
    return "Unknown";
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
    std::ostringstream out;
    out << "{\"schema\":\"tbe.document.v1\",";
    out << "\"name\":\"" << escape_json(name_) << "\",";
    out << "\"next_id\":" << next_id_ << ',';
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
            out << "\"default_wall_height\":" << level->default_wall_height_meters << '}';
        } else if (const auto* wall = element.wall()) {
            out << ",\"wall\":{\"level_id\":" << wall->level_id << ",\"axis\":";
            write_line(out, wall->axis);
            out << ",\"thickness\":" << wall->thickness_meters;
            out << ",\"height\":" << wall->height_meters;
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
            out << ",\"door\":{\"host_wall_id\":" << door->host_wall_id;
            out << ",\"offset\":" << door->offset_meters;
            out << ",\"width\":" << door->width_meters;
            out << ",\"height\":" << door->height_meters << '}';
        } else if (const auto* window = element.window()) {
            out << ",\"window\":{\"host_wall_id\":" << window->host_wall_id;
            out << ",\"offset\":" << window->offset_meters;
            out << ",\"width\":" << window->width_meters;
            out << ",\"height\":" << window->height_meters;
            out << ",\"sill_height\":" << window->sill_height_meters << '}';
        } else if (const auto* room = element.room()) {
            out << ",\"room\":{\"boundary_wall_ids\":";
            write_ids(out, room->boundary_wall_ids);
            out << ",\"area\":" << room->area_square_meters;
            out << ",\"perimeter\":" << room->perimeter_meters;
            out << ",\"level_id\":" << room->level_id;
            out << ",\"boundary_polygon\":";
            write_points(out, room->boundary_polygon);
            out << '}';
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
            }, revision);
        } else if (kind == ElementKind::Wall) {
            const auto& wall = as_object(field(object, "wall"));
            WallData data{
                .level_id = as_id(field(wall, "level_id")),
                .axis = parse_line(field(wall, "axis")),
                .thickness_meters = as_number(field(wall, "thickness")),
                .height_meters = as_number(field(wall, "height")),
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
                .host_wall_id = as_id(field(door, "host_wall_id")),
                .offset_meters = as_number(field(door, "offset")),
                .width_meters = as_number(field(door, "width")),
                .height_meters = as_number(field(door, "height")),
            }, revision);
        } else if (kind == ElementKind::Window) {
            const auto& window = as_object(field(object, "window"));
            elements.emplace_back(id, kind, std::move(name), WindowData{
                .host_wall_id = as_id(field(window, "host_wall_id")),
                .offset_meters = as_number(field(window, "offset")),
                .width_meters = as_number(field(window, "width")),
                .height_meters = as_number(field(window, "height")),
                .sill_height_meters = as_number(field(window, "sill_height")),
            }, revision);
        } else if (kind == ElementKind::Room) {
            const auto& room = as_object(field(object, "room"));
            RoomData data{
                .area_square_meters = as_number(field(room, "area")),
                .perimeter_meters = as_number(field(room, "perimeter")),
                .level_id = as_id(field(room, "level_id")),
            };
            for (const auto& id_value : as_array(field(room, "boundary_wall_ids"))) {
                data.boundary_wall_ids.push_back(as_id(id_value));
            }
            for (const auto& point_value : as_array(field(room, "boundary_polygon"))) {
                data.boundary_polygon.push_back(parse_point(point_value));
            }
            elements.emplace_back(id, kind, std::move(name), data, revision);
        }
    }

    document.replace_state(as_string(field(root_object, "name")), std::move(elements), as_id(field(root_object, "next_id")));
    return document;
}

} // namespace tbe::core
