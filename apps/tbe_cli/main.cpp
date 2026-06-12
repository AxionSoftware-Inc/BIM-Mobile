#include "tbe/core/Command.hpp"
#include "tbe/core/GeometryService.hpp"
#include "tbe/core/Project.hpp"

#include <iostream>

int main() {
    tbe::core::Project project{"Tablet BIM Sample"};
    auto& document = project.active_document();
    tbe::core::CommandProcessor commands;

    const auto level_id = document.create_level("Level 1", 0.0, 3.2);

    tbe::core::CreateWallCommand west_wall{
        "West Exterior Wall",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 6.0, .y = 0.0}},
        0.24,
        3.2,
        level_id
    };
    commands.execute(document, west_wall);

    tbe::core::CreateWallCommand east_wall{
        "East Exterior Wall",
        tbe::core::Line2{.start = {.x = 6.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.24,
        3.2,
        level_id
    };
    commands.execute(document, east_wall);

    tbe::core::CreateWallCommand north_wall{
        "North Exterior Wall",
        tbe::core::Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 4.0}},
        0.24,
        3.2,
        level_id
    };
    commands.execute(document, north_wall);

    tbe::core::CreateWallCommand south_wall{
        "South Exterior Wall",
        tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}},
        0.24,
        3.2,
        level_id
    };
    commands.execute(document, south_wall);

    tbe::core::AutoJoinWallsCommand auto_join;
    commands.execute(document, auto_join);

    tbe::core::InsertDoorCommand door{"Entry Door", west_wall.created_id(), 1.4, 0.95, 2.1};
    commands.execute(document, door);

    tbe::core::InsertWindowCommand window{"Living Window", west_wall.created_id(), 4.2, 1.2, 1.1, 0.9};
    commands.execute(document, window);

    tbe::core::DetectRoomsCommand detect_rooms;
    commands.execute(document, detect_rooms);
    document.regenerate_dirty_geometry();

    tbe::core::GeometryService geometry;
    const auto* wall = document.find_ptr(west_wall.created_id())->wall();
    const auto* room = document.find_ptr(detect_rooms.detected_room_ids().front())->room();

    const auto json = document.to_json();
    auto reloaded = tbe::core::Document::from_json(json);
    reloaded.regenerate_dirty_geometry();
    const auto* reloaded_wall = reloaded.find_ptr(west_wall.created_id())->wall();
    const auto* reloaded_room = reloaded.find_ptr(detect_rooms.detected_room_ids().front())->room();

    std::cout << "Project: " << project.name() << '\n';
    std::cout << "Geometry backend: " << geometry.backend_name() << '\n';
    std::cout << "Elements: " << document.elements().size() << '\n';
    std::cout << "Transaction log entries: " << commands.transaction_log().size() << '\n';
    std::cout << "Detected rooms: " << detect_rooms.detected_room_ids().size() << '\n';
    std::cout << "Room area: " << room->area_square_meters << " m2\n";
    std::cout << "Room perimeter: " << room->perimeter_meters << " m\n";
    std::cout << "West wall joins: " << wall->joins.size() << '\n';
    std::cout << "West wall hosted openings: " << wall->openings.size() << '\n';
    std::cout << "West wall profile vertices: " << wall->geometry.profile.polygon.size() << '\n';
    std::cout << "West wall opening rectangles: " << wall->geometry.profile.openings.size() << '\n';
    std::cout << "West wall geometry dirty: " << (wall->geometry.dirty ? "yes" : "no") << '\n';
    std::cout << "West wall fallback mesh: " << wall->geometry.mesh.vertices.size() << " vertices, "
              << wall->geometry.mesh.indices.size() << " indices, "
              << wall->geometry.triangles << " triangles\n";
    std::cout << "West wall volume estimate: " << wall->geometry.solid_volume_cubic_meters << " m3\n";
    std::cout << "Serialized JSON bytes: " << json.size() << '\n';
    std::cout << "Reload validation: "
              << (reloaded_room != nullptr && reloaded_wall != nullptr && !reloaded_wall->geometry.dirty ? "ok" : "failed")
              << '\n';

    return 0;
}
