#include "tbe/api/EngineApi.hpp"

#include <filesystem>
#include <fstream>
#include <cerrno>
#include <cstdlib>
#include <cmath>
#include <iostream>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <stdexcept>
#include <utility>

namespace fs = std::filesystem;

namespace {

struct CreateWallCommand {
    double start_x{0.0};
    double start_y{0.0};
    double end_x{0.0};
    double end_y{0.0};
    double height_meters{3.0};
    double thickness_meters{0.2};
    std::uint64_t level_id{0};
    std::uint64_t wall_type_id{0};
};

enum class CommandType {
    CreateWall,
    InsertDoor,
    InsertWindow,
    DeleteElement,
    SetWallAxis,
    UpdateWallProperties,
    UpdateDoorProperties,
    UpdateWindowProperties,
    MoveHostedOpening,
};

struct ParsedCommand {
    CommandType type{CommandType::CreateWall};
    CreateWallCommand wall{};
    std::uint64_t element_id{0};
    std::uint64_t wall_id{0};
    std::uint64_t door_id{0};
    std::uint64_t window_id{0};
    std::uint64_t opening_id{0};
    std::uint64_t host_wall_id{0};
    double offset_meters{0.0};
    double width_meters{0.0};
    double height_meters{0.0};
    double sill_height_meters{0.0};
    double clearance_meters{0.05};
};

std::string read_text_file(const fs::path& path) {
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("failed to open " + path.string());
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    return buffer.str();
}

std::optional<double> match_double(std::string_view text, std::string_view pattern) {
    const std::regex re(std::string(pattern), std::regex::ECMAScript);
    std::cmatch match;
    const auto begin = text.data();
    const auto end = text.data() + text.size();
    if (std::regex_search(begin, end, match, re) && match.size() >= 2) {
        try {
            return std::stod(match[1].str());
        } catch (...) {
            return std::nullopt;
        }
    }
    return std::nullopt;
}

std::optional<std::uint64_t> match_uint(std::string_view text, std::string_view pattern) {
    const auto value = match_double(text, pattern);
    if (!value.has_value() || *value < 0.0) {
        return std::nullopt;
    }
    return static_cast<std::uint64_t>(*value);
}

std::optional<std::string> match_string(std::string_view text, std::string_view pattern) {
    const std::regex re(std::string(pattern), std::regex::ECMAScript);
    std::cmatch match;
    const auto begin = text.data();
    const auto end = text.data() + text.size();
    if (std::regex_search(begin, end, match, re) && match.size() >= 2) {
        return match[1].str();
    }
    return std::nullopt;
}

std::optional<std::string> extract_json_string(std::string_view json, std::string_view key) {
    const auto key_pattern = std::string("\"") + std::string(key) + "\"";
    const auto key_pos = json.find(key_pattern);
    if (key_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto colon_pos = json.find(':', key_pos + key_pattern.size());
    if (colon_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto quote_pos = json.find('"', colon_pos + 1);
    if (quote_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto end_quote = json.find('"', quote_pos + 1);
    if (end_quote == std::string_view::npos) {
        return std::nullopt;
    }
    return std::string(json.substr(quote_pos + 1, end_quote - quote_pos - 1));
}

std::optional<double> extract_json_number(std::string_view json, std::string_view key) {
    const auto key_pattern = std::string("\"") + std::string(key) + "\"";
    const auto key_pos = json.find(key_pattern);
    if (key_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto colon_pos = json.find(':', key_pos + key_pattern.size());
    if (colon_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto begin = json.find_first_not_of(" \t\r\n", colon_pos + 1);
    if (begin == std::string_view::npos) {
        return std::nullopt;
    }
    const auto end = json.find_first_of(",}", begin);
    const auto raw_text = std::string(json.substr(begin, end == std::string_view::npos ? json.size() - begin : end - begin));
    const auto last = raw_text.find_last_not_of(" \t\r\n");
    const auto number_text = last == std::string::npos ? std::string{} : raw_text.substr(0, last + 1);
    if (number_text.empty()) {
        return std::nullopt;
    }
    char* parse_end = nullptr;
    errno = 0;
    const auto value = std::strtod(number_text.c_str(), &parse_end);
    if (parse_end != number_text.c_str() + number_text.size() || errno == ERANGE) {
        return std::nullopt;
    }
    return value;
}

std::optional<std::uint64_t> extract_json_uint(std::string_view json, std::string_view key) {
    const auto value = extract_json_number(json, key);
    if (!value.has_value() || *value < 0.0) {
        return std::nullopt;
    }
    return static_cast<std::uint64_t>(*value);
}

struct JsonPoint {
    double x{0.0};
    double y{0.0};
};

std::optional<JsonPoint> extract_json_point(std::string_view json, std::string_view key) {
    const auto key_pattern = std::string("\"") + std::string(key) + "\"";
    const auto key_pos = json.find(key_pattern);
    if (key_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto object_start = json.find('{', key_pos + key_pattern.size());
    if (object_start == std::string_view::npos) {
        return std::nullopt;
    }
    const auto object_end = json.find('}', object_start + 1);
    if (object_end == std::string_view::npos) {
        return std::nullopt;
    }
    const auto object = json.substr(object_start + 1, object_end - object_start - 1);
    const auto x = extract_json_number(object, "x");
    const auto y = extract_json_number(object, "y");
    if (!x.has_value() || !y.has_value()) {
        return std::nullopt;
    }
    return JsonPoint{.x = *x, .y = *y};
}

ParsedCommand parse_command(const std::string& json) {
    ParsedCommand command{};
    if (auto value = extract_json_string(json, "type"); value.has_value()) {
        if (*value == "create_wall") {
            command.type = CommandType::CreateWall;
        } else if (*value == "insert_door") {
            command.type = CommandType::InsertDoor;
        } else if (*value == "insert_window") {
            command.type = CommandType::InsertWindow;
        } else if (*value == "delete_element") {
            command.type = CommandType::DeleteElement;
        } else if (*value == "set_wall_axis") {
            command.type = CommandType::SetWallAxis;
        } else if (*value == "update_wall_properties") {
            command.type = CommandType::UpdateWallProperties;
        } else if (*value == "update_door_properties") {
            command.type = CommandType::UpdateDoorProperties;
        } else if (*value == "update_window_properties") {
            command.type = CommandType::UpdateWindowProperties;
        } else if (*value == "move_hosted_opening") {
            command.type = CommandType::MoveHostedOpening;
        }
    }
    if (const auto start = extract_json_point(json, "start"); start.has_value()) {
        command.wall.start_x = start->x;
        command.wall.start_y = start->y;
    }
    if (const auto end = extract_json_point(json, "end"); end.has_value()) {
        command.wall.end_x = end->x;
        command.wall.end_y = end->y;
    }
    if (auto value = extract_json_number(json, "height_meters"); value.has_value()) {
        command.wall.height_meters = *value;
        command.height_meters = *value;
    }
    if (auto value = extract_json_number(json, "thickness_meters"); value.has_value()) {
        command.wall.thickness_meters = *value;
    }
    if (auto value = extract_json_uint(json, "level_id"); value.has_value()) {
        command.wall.level_id = *value;
    }
    if (auto value = extract_json_uint(json, "wall_type_id"); value.has_value()) {
        command.wall.wall_type_id = *value;
    }
    if (auto value = extract_json_uint(json, "element_id"); value.has_value()) {
        command.element_id = *value;
    }
    if (auto value = extract_json_uint(json, "wall_id"); value.has_value()) {
        command.wall_id = *value;
    }
    if (auto value = extract_json_uint(json, "door_id"); value.has_value()) {
        command.door_id = *value;
    }
    if (auto value = extract_json_uint(json, "window_id"); value.has_value()) {
        command.window_id = *value;
    }
    if (auto value = extract_json_uint(json, "opening_id"); value.has_value()) {
        command.opening_id = *value;
    }
    if (auto value = extract_json_uint(json, "host_wall_id"); value.has_value()) {
        command.host_wall_id = *value;
    }
    if (auto value = extract_json_number(json, "offset_meters"); value.has_value()) {
        command.offset_meters = *value;
    }
    if (auto value = extract_json_number(json, "width_meters"); value.has_value()) {
        command.width_meters = *value;
    }
    if (auto value = extract_json_number(json, "sill_height_meters"); value.has_value()) {
        command.sill_height_meters = *value;
    }
    if (auto value = extract_json_number(json, "clearance_meters"); value.has_value()) {
        command.clearance_meters = *value;
    }
    return command;
}

fs::path resolve_project_file(const fs::path& path) {
    if (fs::is_directory(path)) {
        return path / "project.json";
    }
    return path;
}

std::uint64_t choose_level_id(tbe::api::EngineSession& session, std::uint64_t requested_level_id) {
    if (requested_level_id != 0) {
        return requested_level_id;
    }
    const auto elements = session.list_elements();
    if (elements.ok() && elements.value.has_value()) {
        for (const auto& element : *elements.value) {
            if (element.kind == tbe::api::ApiElementKind::Level) {
                return element.id.value;
            }
        }
    }
    const auto created = session.create_level("Level 1", 0.0, 3.0);
    if (created.ok() && created.value.has_value()) {
        return created.value->value;
    }
    throw std::runtime_error("failed to create fallback level");
}

std::string escape_json(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (const char ch : value) {
        switch (ch) {
        case '\\': out += "\\\\"; break;
        case '"': out += "\\\""; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default: out += ch; break;
        }
    }
    return out;
}

std::string command_type_name(CommandType type) {
    switch (type) {
    case CommandType::CreateWall:
        return "create_wall";
    case CommandType::InsertDoor:
        return "insert_door";
    case CommandType::InsertWindow:
        return "insert_window";
    case CommandType::DeleteElement:
        return "delete_element";
    case CommandType::SetWallAxis:
        return "set_wall_axis";
    case CommandType::UpdateWallProperties:
        return "update_wall_properties";
    case CommandType::UpdateDoorProperties:
        return "update_door_properties";
    case CommandType::UpdateWindowProperties:
        return "update_window_properties";
    case CommandType::MoveHostedOpening:
        return "move_hosted_opening";
    }
    return "create_wall";
}

bool contains_offset(const std::vector<tbe::api::WallFreeIntervalDTO>& intervals, double offset) {
    for (const auto& interval : intervals) {
        if (offset >= interval.start_offset_meters - 1.0e-9 && offset <= interval.end_offset_meters + 1.0e-9) {
            return true;
        }
    }
    return false;
}

std::string intervals_to_json(const std::vector<tbe::api::WallFreeIntervalDTO>& intervals) {
    std::ostringstream out;
    out << '[';
    for (std::size_t index = 0; index < intervals.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& interval = intervals[index];
        out << "{\"start_offset_meters\":" << interval.start_offset_meters
            << ",\"end_offset_meters\":" << interval.end_offset_meters << '}';
    }
    out << ']';
    return out.str();
}

void print_error_json(const std::string& message) {
    std::cout << "{\"success\":false,\"error\":\"" << escape_json(message) << "\"}\n";
}

} // namespace

int main(int argc, char** argv) {
    fs::path project_path;
    fs::path command_path;
    fs::path output_dir;

    for (int index = 1; index < argc; ++index) {
        const std::string_view arg = argv[index];
        if (arg == "--project" && index + 1 < argc) {
            project_path = argv[++index];
        } else if (arg == "--command" && index + 1 < argc) {
            command_path = argv[++index];
        } else if (arg == "--output" && index + 1 < argc) {
            output_dir = argv[++index];
        }
    }

    try {
        if (project_path.empty() || command_path.empty() || output_dir.empty()) {
            throw std::runtime_error("usage: tbe_apply_command --project <project.json|dir> --command <command.json> --output <export-dir>");
        }

        const auto project_file = resolve_project_file(project_path);
        if (!fs::exists(project_file)) {
            throw std::runtime_error("project file not found: " + project_file.string());
        }
        if (!fs::exists(command_path)) {
            throw std::runtime_error("command file not found: " + command_path.string());
        }

        auto session_result = tbe::api::create_session("Local Edit Bridge");
        if (!session_result.ok() || !session_result.value.has_value()) {
            throw std::runtime_error("failed to create engine session");
        }
        auto session = std::move(*session_result.value);

        const auto load_result = session->load_project_json(read_text_file(project_file));
        if (!load_result.ok()) {
            throw std::runtime_error("failed to load project: " + load_result.message);
        }

        const auto command = parse_command(read_text_file(command_path));
        const auto level_id = choose_level_id(*session, command.wall.level_id);
        std::uint64_t wall_id = 0;
        std::uint64_t opening_id = 0;

        switch (command.type) {
        case CommandType::CreateWall: {
            const auto wall = session->create_wall(
                "Draft Wall",
                {.x = command.wall.start_x, .y = command.wall.start_y},
                {.x = command.wall.end_x, .y = command.wall.end_y},
                command.wall.thickness_meters,
                command.wall.height_meters,
                level_id
            );
            if (!wall.ok() || !wall.value.has_value()) {
                throw std::runtime_error("failed to create wall: " + wall.message);
            }
            wall_id = wall.value->value;
            break;
        }
        case CommandType::InsertDoor:
        case CommandType::InsertWindow: {
            if (command.host_wall_id == 0) {
                throw std::runtime_error("host_wall_id is required for door/window insertion");
            }
            if (command.width_meters <= 0.0 || command.height_meters <= 0.0) {
                throw std::runtime_error("opening width and height must be greater than zero");
            }
            if (command.offset_meters < 0.0) {
                throw std::runtime_error("offset_meters must not be negative");
            }

            const auto free_intervals = session->compute_wall_free_intervals(command.host_wall_id, command.width_meters, command.clearance_meters);
            if (!free_intervals.ok() || !free_intervals.value.has_value()) {
                throw std::runtime_error("failed to compute wall free intervals: " + free_intervals.message);
            }
            if (!contains_offset(*free_intervals.value, command.offset_meters)) {
                std::ostringstream message;
                message << "requested opening offset is outside valid wall intervals; free intervals: "
                        << intervals_to_json(*free_intervals.value);
                throw std::runtime_error(message.str());
            }

            if (command.type == CommandType::InsertDoor) {
                const auto door = session->create_door("Draft Door", command.host_wall_id, command.offset_meters, command.width_meters, command.height_meters);
                if (!door.ok() || !door.value.has_value()) {
                    throw std::runtime_error("failed to create door: " + door.message);
                }
                opening_id = door.value->value;
            } else {
                const auto window = session->create_window(
                    "Draft Window",
                    command.host_wall_id,
                    command.offset_meters,
                    command.width_meters,
                    command.height_meters,
                    command.sill_height_meters
                );
                if (!window.ok() || !window.value.has_value()) {
                    throw std::runtime_error("failed to create window: " + window.message);
                }
                opening_id = window.value->value;
            }
            wall_id = command.host_wall_id;
            break;
        }
        case CommandType::DeleteElement: {
            if (command.element_id == 0) {
                throw std::runtime_error("element_id is required");
            }
            const auto delete_result = session->delete_element(command.element_id);
            if (!delete_result.ok()) {
                throw std::runtime_error("failed to delete element: " + delete_result.message);
            }
            wall_id = command.element_id;
            break;
        }
        case CommandType::SetWallAxis: {
            if (command.wall_id == 0) {
                throw std::runtime_error("wall_id is required");
            }
            const auto set_result = session->set_wall_axis(
                command.wall_id,
                {.x = command.wall.start_x, .y = command.wall.start_y},
                {.x = command.wall.end_x, .y = command.wall.end_y}
            );
            if (!set_result.ok()) {
                throw std::runtime_error("failed to set wall axis: " + set_result.message);
            }
            wall_id = command.wall_id;
            break;
        }
        case CommandType::UpdateWallProperties: {
            if (command.wall_id == 0) {
                throw std::runtime_error("wall_id is required");
            }
            const auto update_result = session->update_wall_properties(
                command.wall_id,
                command.wall.thickness_meters,
                command.wall.height_meters,
                command.wall.wall_type_id
            );
            if (!update_result.ok()) {
                throw std::runtime_error("failed to update wall: " + update_result.message);
            }
            wall_id = command.wall_id;
            break;
        }
        case CommandType::UpdateDoorProperties: {
            if (command.door_id == 0) {
                throw std::runtime_error("door_id is required");
            }
            if (command.offset_meters < 0.0 || command.width_meters <= 0.0 || command.height_meters <= 0.0) {
                throw std::runtime_error("door offset, width, and height must be valid");
            }
            const auto move_result = session->move_hosted_opening(command.door_id, command.offset_meters);
            if (!move_result.ok()) {
                throw std::runtime_error("failed to move door: " + move_result.message);
            }
            const auto resize_result = session->resize_door(command.door_id, command.width_meters, command.height_meters);
            if (!resize_result.ok()) {
                throw std::runtime_error("failed to resize door: " + resize_result.message);
            }
            opening_id = command.door_id;
            break;
        }
        case CommandType::UpdateWindowProperties: {
            if (command.window_id == 0) {
                throw std::runtime_error("window_id is required");
            }
            if (command.offset_meters < 0.0 || command.width_meters <= 0.0 || command.height_meters <= 0.0) {
                throw std::runtime_error("window offset, width, and height must be valid");
            }
            if (command.sill_height_meters < 0.0) {
                throw std::runtime_error("window sill_height_meters must not be negative");
            }
            const auto move_result = session->move_hosted_opening(command.window_id, command.offset_meters);
            if (!move_result.ok()) {
                throw std::runtime_error("failed to move window: " + move_result.message);
            }
            const auto resize_result = session->resize_window(command.window_id, command.width_meters, command.height_meters, command.sill_height_meters);
            if (!resize_result.ok()) {
                throw std::runtime_error("failed to resize window: " + resize_result.message);
            }
            opening_id = command.window_id;
            break;
        }
        case CommandType::MoveHostedOpening: {
            const auto opening_id_value = command.element_id != 0 ? command.element_id : (command.opening_id != 0 ? command.opening_id : (command.door_id != 0 ? command.door_id : command.window_id));
            if (opening_id_value == 0) {
                throw std::runtime_error("opening_id is required");
            }
            if (command.offset_meters < 0.0) {
                throw std::runtime_error("offset_meters must not be negative");
            }
            const auto move_result = session->move_hosted_opening(opening_id_value, command.offset_meters);
            if (!move_result.ok()) {
                throw std::runtime_error("failed to move opening: " + move_result.message);
            }
            opening_id = opening_id_value;
            break;
        }
        }

        session->auto_join_walls();
        session->detect_rooms();
        session->recompute_dirty();
        session->rebuild_spatial_index();
        session->generate_schedules();
        session->generate_material_takeoff_summary();
        const auto validation = session->generate_validation_report();
        if (!validation.ok() || !validation.value.has_value()) {
            throw std::runtime_error("validation failed: " + validation.message);
        }

        fs::create_directories(output_dir);
        const auto package_result = session->export_project_package(output_dir.string());
        if (!package_result.ok()) {
            throw std::runtime_error(package_result.message);
        }

        const auto project_copy = output_dir / "project.json";
        const auto debug_copy = output_dir / "debug" / "debug_report.json";
        const auto svg_copy = output_dir / "exports" / "floorplan.svg";
        const auto obj_copy = output_dir / "exports" / "walls.obj";
        const auto metadata_copy = output_dir / "metadata.json";

        std::cout << "{"
                  << "\"success\":true,"
                  << "\"command_type\":\"" << command_type_name(command.type) << "\","
                  << "\"wall_id\":" << wall_id << ","
                  << "\"opening_id\":" << opening_id << ","
                  << "\"validation\":{\"issues\":" << validation.value->issue_count
                  << ",\"warnings\":" << validation.value->warning_count
                  << ",\"errors\":" << validation.value->error_count << "},"
                  << "\"artifact_paths\":{"
                  << "\"project_json\":\"" << escape_json(project_copy.string()) << "\","
                  << "\"debug_report_json\":\"" << escape_json(debug_copy.string()) << "\","
                  << "\"floorplan_svg\":\"" << escape_json(svg_copy.string()) << "\","
                  << "\"walls_obj\":\"" << escape_json(obj_copy.string()) << "\","
                  << "\"metadata_json\":\"" << escape_json(metadata_copy.string()) << "\""
                  << "}"
                  << "}\n";
        return 0;
    } catch (const std::exception& error) {
        print_error_json(error.what());
        return 1;
    }
}
