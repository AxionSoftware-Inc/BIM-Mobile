#include "tbe/core/Command.hpp"
#include "tbe/core/Document.hpp"
#include "tbe/core/GeometryService.hpp"
#include "tbe/core/JobSystem.hpp"
#include "tbe/core/Project.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <stdexcept>
#include <vector>

namespace {

bool near(double left, double right) {
    return std::abs(left - right) < 1.0e-9;
}

double min_x(const std::vector<tbe::core::Point2>& points) {
    return std::min_element(points.begin(), points.end(), [](auto left, auto right) {
        return left.x < right.x;
    })->x;
}

double max_x(const std::vector<tbe::core::Point2>& points) {
    return std::max_element(points.begin(), points.end(), [](auto left, auto right) {
        return left.x < right.x;
    })->x;
}

double min_y(const std::vector<tbe::core::Point2>& points) {
    return std::min_element(points.begin(), points.end(), [](auto left, auto right) {
        return left.y < right.y;
    })->y;
}

double max_y(const std::vector<tbe::core::Point2>& points) {
    return std::max_element(points.begin(), points.end(), [](auto left, auto right) {
        return left.y < right.y;
    })->y;
}

} // namespace

int main() {
    tbe::core::Project project{"Test Project"};
    assert(project.name() == "Test Project");
    assert(project.active_document().name() == "Test Project Model");

    auto& document = project.active_document();
    const auto wall_a_id = document.create_wall(
        "Wall A",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.5, .y = 0.0}},
        0.2,
        3.0
    );
    const auto wall_b_id = document.create_wall(
        "Wall B",
        tbe::core::Line2{.start = {.x = 4.5, .y = 0.0}, .end = {.x = 4.5, .y = 3.0}},
        0.2,
        3.0
    );

    assert(document.elements().size() == 2);

    tbe::core::GeometryService geometry;
    const auto isolated_profile = geometry.build_wall_profile(tbe::core::WallData{
        .axis = tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.5, .y = 0.0}},
        .thickness_meters = 0.2,
        .height_meters = 3.0,
    });
    assert(isolated_profile.polygon.size() == 4);
    assert(near(max_x(isolated_profile.polygon) - min_x(isolated_profile.polygon), 4.5));
    assert(near(max_y(isolated_profile.polygon) - min_y(isolated_profile.polygon), 0.2));
    assert(!isolated_profile.has_miter_join);

    const auto* wall_a_element = document.find_ptr(wall_a_id);
    assert(wall_a_element != nullptr);
    assert(wall_a_element->name() == "Wall A");

    const auto* wall_a = wall_a_element->wall();
    assert(wall_a != nullptr);
    assert(wall_a->axis.end.x == 4.5);
    assert(wall_a->thickness_meters == 0.2);
    assert(wall_a->height_meters == 3.0);
    assert(wall_a->joins.size() == 1);
    assert(wall_a->joins.front().other_wall_id == wall_b_id);

    const auto joined_profile = geometry.build_wall_profile(*wall_a);
    assert(joined_profile.has_miter_join);
    assert(max_x(joined_profile.polygon) > 4.5);

    const auto wall_t_id = document.create_wall(
        "Wall T",
        tbe::core::Line2{.start = {.x = 2.25, .y = -1.0}, .end = {.x = 2.25, .y = 1.0}},
        0.2,
        3.0
    );
    assert(wall_t_id != wall_a_id);
    wall_a_element = document.find_ptr(wall_a_id);
    wall_a = wall_a_element->wall();
    const auto tee_profile = geometry.build_wall_profile(*wall_a);
    assert(tee_profile.t_junction_placeholders >= 1);

    const auto door_id = document.create_door("Door A", wall_a_id, 2.0, 0.9, 2.1);
    const auto window_id = document.create_window("Window A", wall_a_id, 3.4, 0.8, 1.0, 0.9);
    assert(door_id != window_id);

    wall_a_element = document.find_ptr(wall_a_id);
    wall_a = wall_a_element->wall();
    assert(wall_a->openings.size() == 2);
    assert(wall_a->geometry.dirty);

    const auto profile_with_openings = geometry.build_wall_profile(*wall_a);
    assert(profile_with_openings.openings.size() == 2);
    assert(near(profile_with_openings.openings.front().x_min, 1.55));
    assert(near(profile_with_openings.openings.front().x_max, 2.45));
    assert(near(profile_with_openings.openings.front().z_min, 0.0));
    assert(near(profile_with_openings.openings.front().z_max, 2.1));

    document.regenerate_dirty_geometry();
    wall_a_element = document.find_ptr(wall_a_id);
    wall_a = wall_a_element->wall();
    assert(!wall_a->geometry.dirty);
    assert(wall_a->geometry.vertices == 24);
    assert(wall_a->geometry.triangles == 28);
    assert(wall_a->geometry.mesh.vertices.size() == 24);
    assert(wall_a->geometry.mesh.indices.size() == 84);
    assert(wall_a->geometry.profile.openings.size() == 2);
    assert(wall_a->geometry.openings_cut == 2);
    assert(wall_a->geometry.solid_volume_cubic_meters > 1.5);
    assert(wall_a->geometry.solid_volume_cubic_meters < 2.7);

    const auto* door = document.find_ptr(door_id)->door();
    assert(door != nullptr);
    assert(door->host_wall_id == wall_a_id);

    tbe::core::JobSystem jobs{2};
    auto async_area = jobs.submit([]() {
        return 12;
    });
    assert(jobs.worker_count() == 2);
    assert(async_area.get() == 12);

    bool rejected_bad_wall = false;
    try {
        document.create_wall(
            "Bad Wall",
            tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 0.0, .y = 0.0}},
            0.2,
            3.0
        );
    } catch (const std::invalid_argument&) {
        rejected_bad_wall = true;
    }
    assert(rejected_bad_wall);

    bool rejected_outside_opening = false;
    try {
        document.create_window("Bad Window", wall_a_id, 4.3, 0.8, 1.0, 0.9);
    } catch (const std::invalid_argument&) {
        rejected_outside_opening = true;
    }
    assert(rejected_outside_opening);

    bool rejected_overlapping_opening = false;
    try {
        document.create_door("Bad Door", wall_a_id, 2.2, 0.9, 2.1);
    } catch (const std::invalid_argument&) {
        rejected_overlapping_opening = true;
    }
    assert(rejected_overlapping_opening);

    tbe::core::Document room_document{"Room Test"};
    const auto level_id = room_document.create_level("Level 1", 0.0, 3.0);
    tbe::core::CommandProcessor processor;

    tbe::core::CreateWallCommand room_wall_a{
        "Room Wall A",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 6.0, .y = 0.0}},
        0.2,
        3.0,
        level_id
    };
    tbe::core::CreateWallCommand room_wall_b{
        "Room Wall B",
        tbe::core::Line2{.start = {.x = 6.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.2,
        3.0,
        level_id
    };
    tbe::core::CreateWallCommand room_wall_c{
        "Room Wall C",
        tbe::core::Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 4.0}},
        0.2,
        3.0,
        level_id
    };
    tbe::core::CreateWallCommand room_wall_d{
        "Room Wall D",
        tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}},
        0.2,
        3.0,
        level_id
    };

    processor.execute(room_document, room_wall_a);
    processor.execute(room_document, room_wall_b);
    processor.execute(room_document, room_wall_c);
    processor.execute(room_document, room_wall_d);

    tbe::core::AutoJoinWallsCommand room_join;
    processor.execute(room_document, room_join);

    tbe::core::InsertDoorCommand room_door{"Room Door", room_wall_a.created_id(), 1.2, 0.9, 2.1};
    tbe::core::InsertWindowCommand room_window{"Room Window", room_wall_a.created_id(), 4.0, 1.2, 1.0, 0.9};
    processor.execute(room_document, room_door);
    processor.execute(room_document, room_window);

    tbe::core::DetectRoomsCommand room_detect;
    processor.execute(room_document, room_detect);
    assert(room_detect.detected_room_ids().size() == 1);
    assert(processor.transaction_log().size() == 8);

    const auto* detected_room = room_document.find_ptr(room_detect.detected_room_ids().front())->room();
    assert(detected_room != nullptr);
    assert(near(detected_room->area_square_meters, 24.0));
    assert(near(detected_room->perimeter_meters, 20.0));
    assert(detected_room->level_id == level_id);
    assert(detected_room->boundary_polygon.size() == 4);

    room_document.regenerate_dirty_geometry();
    const auto* original_wall = room_document.find_ptr(room_wall_a.created_id())->wall();
    const auto original_vertices = original_wall->geometry.mesh.vertices.size();
    const auto original_indices = original_wall->geometry.mesh.indices.size();
    assert(original_vertices == 24);
    assert(original_indices == 84);

    const auto json = room_document.to_json();
    auto loaded = tbe::core::Document::from_json(json);
    loaded.regenerate_dirty_geometry();

    const auto* loaded_door = loaded.find_ptr(room_door.created_id())->door();
    const auto* loaded_window = loaded.find_ptr(room_window.created_id())->window();
    const auto* loaded_wall = loaded.find_ptr(room_wall_a.created_id())->wall();
    const auto* loaded_room = loaded.find_ptr(room_detect.detected_room_ids().front())->room();

    assert(loaded_door != nullptr);
    assert(loaded_door->host_wall_id == room_wall_a.created_id());
    assert(loaded_window != nullptr);
    assert(loaded_window->host_wall_id == room_wall_a.created_id());
    assert(loaded_room != nullptr);
    assert(near(loaded_room->area_square_meters, 24.0));
    assert(near(loaded_room->perimeter_meters, 20.0));
    assert(loaded_wall != nullptr);
    assert(!loaded_wall->geometry.dirty);
    assert(loaded_wall->geometry.mesh.vertices.size() == original_vertices);
    assert(loaded_wall->geometry.mesh.indices.size() == original_indices);

    tbe::core::Document invalid_room_document{"Invalid Room Test"};
    const auto invalid_level_id = invalid_room_document.create_level("Level 1", 0.0, 3.0);
    invalid_room_document.create_wall(
        "Incomplete A",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.0, .y = 0.0}},
        0.2,
        3.0,
        invalid_level_id
    );
    invalid_room_document.create_wall(
        "Incomplete B",
        tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 4.0}},
        0.2,
        3.0,
        invalid_level_id
    );
    invalid_room_document.create_wall(
        "Incomplete C",
        tbe::core::Line2{.start = {.x = 4.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.2,
        3.0,
        invalid_level_id
    );
    assert(invalid_room_document.detect_rooms().empty());

    return 0;
}
