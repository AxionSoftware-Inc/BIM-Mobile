#include "tbe/api/EngineApi.hpp"

#include <filesystem>
#include <iostream>

int main() {
    auto session_result = tbe::api::create_session("CPP Example");
    if (!session_result.ok() || !session_result.value.has_value()) {
        std::cerr << "failed to create session\n";
        return 1;
    }

    auto session = std::move(*session_result.value);
    const auto level = session->create_level("Level 1", 0.0, 3.0);
    const auto level_id = level.value->value;

    const auto wall_a = session->create_wall("A", {.x = 0.0, .y = 0.0}, {.x = 4.0, .y = 0.0}, 0.2, 3.0, level_id);
    const auto wall_b = session->create_wall("B", {.x = 4.0, .y = 0.0}, {.x = 4.0, .y = 3.0}, 0.2, 3.0, level_id);
    session->create_wall("C", {.x = 4.0, .y = 3.0}, {.x = 0.0, .y = 3.0}, 0.2, 3.0, level_id);
    session->create_wall("D", {.x = 0.0, .y = 3.0}, {.x = 0.0, .y = 0.0}, 0.2, 3.0, level_id);
    session->create_door("Door", wall_a.value->value, 1.0, 0.9, 2.1);
    session->create_window("Window", wall_b.value->value, 1.5, 1.0, 1.2, 1.0);

    session->auto_join_walls();
    session->detect_rooms();
    const auto schedules = session->generate_schedules();
    const auto validation = session->get_validation_report();

    const auto out_dir = std::filesystem::temp_directory_path() / "tbe_cpp_example";
    std::filesystem::create_directories(out_dir);
    const auto json = session->save_project_json();
    session->export_project_package((out_dir / "package").string());

    std::cout << "project=" << *session->current_project().value << '\n';
    std::cout << "wall_rows=" << schedules.value->wall_rows << '\n';
    std::cout << "room_rows=" << schedules.value->room_rows << '\n';
    std::cout << "validation_errors=" << validation.value->error_count << '\n';
    std::cout << "json_size=" << json.value->size() << '\n';
    std::cout << "package=" << (out_dir / "package") << '\n';
    return validation.value->error_count == 0 ? 0 : 1;
}
