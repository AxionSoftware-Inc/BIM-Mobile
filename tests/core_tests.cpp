#include "tbe/core/Command.hpp"
#include "tbe/core/Document.hpp"
#include "tbe/core/GeometryService.hpp"
#include "tbe/core/JobSystem.hpp"
#include "tbe/core/Project.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <filesystem>
#include <fstream>
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

std::vector<double> sorted_room_areas(const tbe::core::Document& document, const std::vector<tbe::core::ElementId>& room_ids) {
    std::vector<double> areas;
    for (const auto room_id : room_ids) {
        const auto* room = document.find_ptr(room_id)->room();
        if (room != nullptr) {
            areas.push_back(room->centerline_area_square_meters);
        }
    }
    std::sort(areas.begin(), areas.end());
    return areas;
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
    assert(door->level_id == 0);
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
    tbe::core::CommandProcessor processor;
    tbe::core::CreateLevelCommand create_level{"Level 1", 0.0, 3.0};
    processor.execute(room_document, create_level);
    const auto level_id = create_level.created_id();

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
    assert(processor.transaction_log().size() == 9);
    assert(processor.history().size() == 9);
    assert(processor.history().front().command_name == "CreateLevel");
    assert(processor.history().front().affected_element_ids.size() == 1);
    assert(processor.history().back().command_name == "DetectRooms");
    assert(processor.history().back().affected_element_ids.size() == 1);

    const auto* detected_room = room_document.find_ptr(room_detect.detected_room_ids().front())->room();
    assert(detected_room != nullptr);
    assert(near(detected_room->centerline_area_square_meters, 24.0));
    assert(near(detected_room->centerline_perimeter_meters, 20.0));
    assert(detected_room->level_id == level_id);
    assert(detected_room->centerline_boundary_polygon.size() == 4);

    room_document.regenerate_dirty_geometry();
    const auto* original_wall = room_document.find_ptr(room_wall_a.created_id())->wall();
    const auto original_vertices = original_wall->geometry.mesh.vertices.size();
    const auto original_indices = original_wall->geometry.mesh.indices.size();
    assert(original_vertices == 24);
    assert(original_indices == 84);

    tbe::core::Project room_project{"Room Project"};
    room_project.active_document() = room_document;
    const auto json = room_project.to_json();
    auto loaded_project = tbe::core::Project::from_json(json);
    assert(loaded_project.name() == "Room Project");
    auto& loaded = loaded_project.active_document();
    loaded.regenerate_dirty_geometry();

    const auto* loaded_door = loaded.find_ptr(room_door.created_id())->door();
    const auto* loaded_window = loaded.find_ptr(room_window.created_id())->window();
    const auto* loaded_wall = loaded.find_ptr(room_wall_a.created_id())->wall();
    const auto* loaded_room = loaded.find_ptr(room_detect.detected_room_ids().front())->room();

    assert(loaded_door != nullptr);
    assert(loaded_door->level_id == level_id);
    assert(loaded_door->host_wall_id == room_wall_a.created_id());
    assert(loaded_window != nullptr);
    assert(loaded_window->level_id == level_id);
    assert(loaded_window->host_wall_id == room_wall_a.created_id());
    assert(loaded_room != nullptr);
    assert(near(loaded_room->centerline_area_square_meters, 24.0));
    assert(near(loaded_room->centerline_perimeter_meters, 20.0));
    assert(loaded_wall != nullptr);
    assert(!loaded_wall->geometry.dirty);
    assert(loaded_wall->joins.size() == original_wall->joins.size());
    assert(loaded_wall->geometry.mesh.vertices.size() == original_vertices);
    assert(loaded_wall->geometry.mesh.indices.size() == original_indices);
    assert(loaded.find_ptr(room_wall_a.created_id())->id() == room_wall_a.created_id());
    assert(loaded.find_ptr(room_door.created_id())->id() == room_door.created_id());
    assert(loaded.find_ptr(room_window.created_id())->id() == room_window.created_id());
    assert(loaded.find_ptr(room_detect.detected_room_ids().front())->id() == room_detect.detected_room_ids().front());

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

    tbe::core::Document editable_document{"Editable Room"};
    tbe::core::CommandProcessor editable_processor;
    tbe::core::CreateLevelCommand editable_level{"Level 1", 0.0, 3.0};
    editable_processor.execute(editable_document, editable_level);

    tbe::core::CreateWallCommand edit_bottom{
        "Bottom",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 6.0, .y = 0.0}},
        0.2,
        3.0,
        editable_level.created_id()
    };
    tbe::core::CreateWallCommand edit_top{
        "Top",
        tbe::core::Line2{.start = {.x = 6.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.2,
        3.0,
        editable_level.created_id()
    };
    tbe::core::CreateWallCommand edit_right{
        "Right",
        tbe::core::Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 4.0}},
        0.2,
        3.0,
        editable_level.created_id()
    };
    tbe::core::CreateWallCommand edit_left{
        "Left",
        tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}},
        0.2,
        3.0,
        editable_level.created_id()
    };
    editable_processor.execute(editable_document, edit_bottom);
    editable_processor.execute(editable_document, edit_top);
    editable_processor.execute(editable_document, edit_right);
    editable_processor.execute(editable_document, edit_left);
    editable_document.detect_rooms();
    const auto original_room = editable_document.find_ptr(editable_document.detect_rooms().front())->room();
    assert(original_room != nullptr);
    assert(near(original_room->centerline_area_square_meters, 24.0));

    tbe::core::MoveWallCommand move_right{edit_right.created_id(), tbe::core::Point2{.x = 1.0, .y = 0.0}};
    editable_processor.execute(editable_document, move_right);
    const auto moved_room_ids = editable_document.detect_rooms();
    assert(moved_room_ids.size() == 1);
    const auto* moved_room = editable_document.find_ptr(moved_room_ids.front())->room();
    assert(near(moved_room->centerline_area_square_meters, 28.0));
    const auto dependency_graph = editable_document.build_dependency_graph();
    assert(dependency_graph.dependent_rooms(edit_right.created_id()).size() == 1);
    assert(dependency_graph.connected_walls(edit_right.created_id()).size() == 2);
    assert(editable_document.find_ptr(edit_right.created_id())->wall()->geometry.dirty);
    editable_document.regenerate_dirty_geometry();
    assert(!editable_document.find_ptr(edit_right.created_id())->wall()->geometry.dirty);
    editable_processor.undo_last(editable_document);
    const auto undo_room_ids = editable_document.detect_rooms();
    assert(undo_room_ids.size() == 1);
    const auto* undo_room = editable_document.find_ptr(undo_room_ids.front())->room();
    assert(near(undo_room->centerline_area_square_meters, 24.0));
    assert(editable_processor.redo_last(editable_document));
    const auto redo_room_ids = editable_document.detect_rooms();
    assert(redo_room_ids.size() == 1);
    const auto* redo_room = editable_document.find_ptr(redo_room_ids.front())->room();
    assert(near(redo_room->centerline_area_square_meters, 28.0));
    editable_processor.undo_last(editable_document);

    tbe::core::InsertDoorCommand editable_door{"Editable Door", edit_bottom.created_id(), 2.0, 0.9, 2.1};
    editable_processor.execute(editable_document, editable_door);
    tbe::core::MoveHostedOpeningCommand move_door{editable_door.created_id(), 3.0};
    editable_processor.execute(editable_document, move_door);
    const auto* moved_door = editable_document.find_ptr(editable_door.created_id())->door();
    assert(moved_door != nullptr);
    assert(near(moved_door->offset_meters, 3.0));

    bool rejected_outside_move = false;
    try {
        editable_document.move_hosted_opening(editable_door.created_id(), 5.8);
    } catch (const std::invalid_argument&) {
        rejected_outside_move = true;
    }
    assert(rejected_outside_move);

    tbe::core::DeleteElementCommand delete_left{edit_left.created_id()};
    editable_processor.execute(editable_document, delete_left);
    assert(editable_document.detect_rooms().empty());
    editable_processor.undo_last(editable_document);
    assert(editable_document.detect_rooms().size() == 1);

    tbe::core::CreateWallCommand undo_wall{
        "Undo Wall",
        tbe::core::Line2{.start = {.x = 10.0, .y = 0.0}, .end = {.x = 12.0, .y = 0.0}},
        0.2,
        3.0,
        editable_level.created_id()
    };
    editable_processor.execute(editable_document, undo_wall);
    assert(editable_document.find_ptr(undo_wall.created_id()) != nullptr);
    editable_processor.undo_last(editable_document);
    assert(editable_document.find_ptr(undo_wall.created_id()) == nullptr);

    tbe::core::Document split_document{"Split Test"};
    const auto split_level_id = split_document.create_level("Level 1", 0.0, 3.0);
    const auto split_wall_id = split_document.create_wall(
        "Split Candidate",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 8.0, .y = 0.0}},
        0.2,
        3.0,
        split_level_id
    );
    tbe::core::SplitWallCommand split_wall_command{split_wall_id, 3.0};
    split_wall_command.execute(split_document);
    const auto* split_first = split_document.find_ptr(split_wall_id)->wall();
    const auto* split_second = split_document.find_ptr(split_wall_command.created_wall_id())->wall();
    assert(split_first != nullptr);
    assert(split_second != nullptr);
    const auto first_length = std::abs(split_first->axis.end.x - split_first->axis.start.x) +
        std::abs(split_first->axis.end.y - split_first->axis.start.y);
    const auto second_length = std::abs(split_second->axis.end.x - split_second->axis.start.x) +
        std::abs(split_second->axis.end.y - split_second->axis.start.y);
    assert(near(first_length + second_length, 8.0));

    tbe::core::CommandProcessor split_processor;
    tbe::core::SplitWallCommand split_with_undo{split_wall_id, 2.5};
    split_processor.execute(split_document, split_with_undo);
    assert(split_document.find_ptr(split_with_undo.created_wall_id()) != nullptr);
    assert(split_processor.undo_last(split_document));
    assert(split_document.find_ptr(split_with_undo.created_wall_id()) == nullptr);
    assert(split_processor.redo_last(split_document));
    assert(split_document.find_ptr(split_with_undo.created_wall_id()) != nullptr);

    tbe::core::Document validation_document{"Validation"};
    const auto validation_level = validation_document.create_level("Level 1", 0.0, 3.0);
    const auto validation_wall = validation_document.create_wall(
        "Wall",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 5.0, .y = 0.0}},
        0.2,
        3.0,
        validation_level
    );
    validation_document.restore_element(tbe::core::Element{
        999,
        tbe::core::ElementKind::Door,
        "Orphan Door",
        tbe::core::DoorData{
            .level_id = validation_level,
            .host_wall_id = 123456,
            .offset_meters = 1.0,
            .width_meters = 0.9,
            .height_meters = 2.1,
        }
    });
    auto* validation_wall_element = validation_document.find_ptr(validation_wall);
    auto* validation_wall_data = validation_wall_element->wall();
    validation_wall_data->openings.push_back(tbe::core::HostedOpening{
        .element_id = 1000,
        .kind = tbe::core::OpeningKind::Door,
        .offset_meters = 1.5,
        .width_meters = 1.0,
        .height_meters = 2.1,
        .sill_height_meters = 0.0,
    });
    validation_wall_data->openings.push_back(tbe::core::HostedOpening{
        .element_id = 1001,
        .kind = tbe::core::OpeningKind::Window,
        .offset_meters = 1.7,
        .width_meters = 1.0,
        .height_meters = 1.0,
        .sill_height_meters = 0.9,
    });
    validation_document.restore_element(tbe::core::Element{
        1000,
        tbe::core::ElementKind::Door,
        "Door 1000",
        tbe::core::DoorData{
            .level_id = validation_level,
            .host_wall_id = validation_wall,
            .offset_meters = 1.5,
            .width_meters = 1.0,
            .height_meters = 2.1,
        }
    });
    validation_document.restore_element(tbe::core::Element{
        1001,
        tbe::core::ElementKind::Window,
        "Window 1001",
        tbe::core::WindowData{
            .level_id = validation_level,
            .host_wall_id = validation_wall,
            .offset_meters = 1.7,
            .width_meters = 1.0,
            .height_meters = 1.0,
            .sill_height_meters = 0.9,
        }
    });
    const auto validation_report = validation_document.validate_document();
    assert(validation_report.issue_count() >= 2);
    assert(std::any_of(validation_report.issues.begin(), validation_report.issues.end(), [](const auto& issue) {
        return issue.code == tbe::core::ValidationIssueCode::OrphanOpening;
    }));
    assert(std::any_of(validation_report.issues.begin(), validation_report.issues.end(), [](const auto& issue) {
        return issue.code == tbe::core::ValidationIssueCode::OverlappingOpenings;
    }));

    tbe::core::Document export_document{"Export"};
    const auto export_level_id = export_document.create_level("Level 1", 0.0, 3.0);
    const auto export_wall_a = export_document.create_wall(
        "A",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.0, .y = 0.0}},
        0.2,
        3.0,
        export_level_id
    );
    (void)export_wall_a;
    export_document.create_wall(
        "B",
        tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 3.0}},
        0.2,
        3.0,
        export_level_id
    );
    export_document.create_wall(
        "C",
        tbe::core::Line2{.start = {.x = 4.0, .y = 3.0}, .end = {.x = 0.0, .y = 3.0}},
        0.2,
        3.0,
        export_level_id
    );
    export_document.create_wall(
        "D",
        tbe::core::Line2{.start = {.x = 0.0, .y = 3.0}, .end = {.x = 0.0, .y = 0.0}},
        0.2,
        3.0,
        export_level_id
    );
    export_document.detect_rooms();
    export_document.regenerate_dirty_geometry();
    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_level4_test_exports";
    std::filesystem::create_directories(export_dir);
    const auto svg_path = export_dir / "plan.svg";
    const auto obj_path = export_dir / "mesh.obj";
    const auto debug_path = export_dir / "debug.json";
    export_document.export_floorplan_svg(svg_path);
    export_document.export_mesh_obj(obj_path);
    export_document.export_debug_report_json(debug_path);
    assert(std::filesystem::exists(svg_path));
    assert(std::filesystem::file_size(svg_path) > 0);
    assert(std::filesystem::exists(obj_path));
    assert(std::filesystem::file_size(obj_path) > 0);
    assert(std::filesystem::exists(debug_path));
    assert(std::filesystem::file_size(debug_path) > 0);

    tbe::core::Document reversed_document{"Reversed"};
    const auto reversed_level = reversed_document.create_level("Level 1", 0.0, 3.0);
    const auto reversed_wall_a = reversed_document.create_wall(
        "Reversed A",
        tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 0.0, .y = 0.0}},
        0.2,
        3.0,
        reversed_level
    );
    const auto reversed_wall_b = reversed_document.create_wall(
        "Reversed B",
        tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0000000001, .y = 3.0}},
        0.2,
        3.0,
        reversed_level
    );
    reversed_document.auto_join_walls();
    const auto* reversed_a = reversed_document.find_ptr(reversed_wall_a)->wall();
    assert(reversed_a != nullptr);
    assert(!reversed_a->joins.empty());
    assert(reversed_a->joins.front().other_wall_id == reversed_wall_b);
    reversed_document.auto_join_walls();
    assert(reversed_document.find_ptr(reversed_wall_a)->wall()->joins.size() == 1);

    tbe::core::Document multi_room_document{"Multi Room"};
    const auto multi_level = multi_room_document.create_level("Level 1", 0.0, 3.0);
    const auto mr_bottom = multi_room_document.create_wall(
        "Bottom",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 12.0, .y = 0.0}},
        0.2,
        3.0,
        multi_level
    );
    const auto mr_top = multi_room_document.create_wall(
        "Top",
        tbe::core::Line2{.start = {.x = 12.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.2,
        3.0,
        multi_level
    );
    const auto mr_right = multi_room_document.create_wall(
        "Right",
        tbe::core::Line2{.start = {.x = 12.0, .y = 0.0}, .end = {.x = 12.0, .y = 4.0}},
        0.2,
        3.0,
        multi_level
    );
    const auto mr_left = multi_room_document.create_wall(
        "Left",
        tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}},
        0.2,
        3.0,
        multi_level
    );
    const auto mr_shared_a = multi_room_document.create_wall(
        "Shared A",
        tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 4.0}},
        0.2,
        3.0,
        multi_level
    );
    const auto mr_shared_b = multi_room_document.create_wall(
        "Shared B",
        tbe::core::Line2{.start = {.x = 8.0, .y = 0.0}, .end = {.x = 8.0, .y = 4.0}},
        0.2,
        3.0,
        multi_level
    );
    (void)mr_bottom;
    (void)mr_top;
    (void)mr_right;
    (void)mr_left;
    multi_room_document.auto_join_walls();
    auto multi_room_ids = multi_room_document.detect_rooms();
    assert(multi_room_ids.size() == 3);
    const auto multi_areas = sorted_room_areas(multi_room_document, multi_room_ids);
    assert(near(multi_areas[0], 16.0));
    assert(near(multi_areas[1], 16.0));
    assert(near(multi_areas[2], 16.0));
    const auto repeated_ids = multi_room_document.detect_rooms();
    assert(repeated_ids.size() == 3);
    assert(multi_room_document.detect_rooms().size() == 3);

    tbe::core::CommandProcessor multi_processor;
    tbe::core::SetWallAxisCommand move_shared_a{
        mr_shared_a,
        tbe::core::Line2{.start = {.x = 5.0, .y = 0.0}, .end = {.x = 5.0, .y = 4.0}}
    };
    multi_processor.execute(multi_room_document, move_shared_a);
    multi_room_ids = multi_room_document.detect_rooms();
    assert(multi_room_ids.size() == 3);
    const auto moved_multi_areas = sorted_room_areas(multi_room_document, multi_room_ids);
    assert(near(moved_multi_areas[0], 12.0));
    assert(near(moved_multi_areas[1], 16.0));
    assert(near(moved_multi_areas[2], 20.0));
    assert(multi_processor.undo_last(multi_room_document));
    multi_room_ids = multi_room_document.detect_rooms();
    const auto undo_multi_areas = sorted_room_areas(multi_room_document, multi_room_ids);
    assert(near(undo_multi_areas[0], 16.0));
    assert(near(undo_multi_areas[2], 16.0));
    assert(multi_processor.redo_last(multi_room_document));
    multi_room_ids = multi_room_document.detect_rooms();
    const auto redo_multi_areas = sorted_room_areas(multi_room_document, multi_room_ids);
    assert(near(redo_multi_areas[0], 12.0));
    assert(near(redo_multi_areas[2], 20.0));

    tbe::core::DeleteElementCommand delete_shared{mr_shared_b};
    multi_processor.execute(multi_room_document, delete_shared);
    const auto after_delete_room_ids = multi_room_document.detect_rooms();
    assert(after_delete_room_ids.size() == 2);
    assert(multi_processor.undo_last(multi_room_document));
    assert(multi_room_document.detect_rooms().size() == 3);

    tbe::core::Document shared_wall_document{"Two Rooms"};
    const auto shared_level = shared_wall_document.create_level("Level 1", 0.0, 3.0);
    shared_wall_document.create_wall("Bottom", tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 8.0, .y = 0.0}}, 0.2, 3.0, shared_level);
    shared_wall_document.create_wall("Top", tbe::core::Line2{.start = {.x = 8.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}}, 0.2, 3.0, shared_level);
    shared_wall_document.create_wall("Right", tbe::core::Line2{.start = {.x = 8.0, .y = 0.0}, .end = {.x = 8.0, .y = 4.0}}, 0.2, 3.0, shared_level);
    shared_wall_document.create_wall("Left", tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}}, 0.2, 3.0, shared_level);
    const auto shared_mid = shared_wall_document.create_wall("Mid", tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 4.0}}, 0.2, 3.0, shared_level);
    shared_wall_document.auto_join_walls();
    auto shared_room_ids = shared_wall_document.detect_rooms();
    assert(shared_room_ids.size() == 2);
    const auto shared_areas = sorted_room_areas(shared_wall_document, shared_room_ids);
    assert(near(shared_areas[0], 16.0));
    assert(near(shared_areas[1], 16.0));
    const auto shared_graph = shared_wall_document.dependency_graph();
    assert(shared_graph.dependent_rooms(shared_mid).size() == 2);
    const auto brick_material = shared_wall_document.create_material("Brick", tbe::core::MaterialCategory::Structural, 1800.0, 120.0);
    const auto plaster_material = shared_wall_document.create_material("Plaster", tbe::core::MaterialCategory::Finish, 950.0, 40.0);
    const auto glass_material = shared_wall_document.create_material("Glass", tbe::core::MaterialCategory::Glass, 2500.0, 80.0);
    const auto concrete_material = shared_wall_document.create_material("Concrete", tbe::core::MaterialCategory::Structural, 2400.0, 110.0);
    const auto floor_tile_material = shared_wall_document.create_material("Floor Tile", tbe::core::MaterialCategory::Finish, 2100.0, 55.0);
    const auto gypsum_material = shared_wall_document.create_material("Gypsum", tbe::core::MaterialCategory::Finish, 850.0, 28.0);
    const auto test_wall_type = shared_wall_document.create_wall_type("Brick Wall", {
        tbe::core::WallAssemblyLayer{.material_id = plaster_material, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = brick_material, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core},
        tbe::core::WallAssemblyLayer{.material_id = plaster_material, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::ExteriorFinish},
    });
    const auto floor_assembly = shared_wall_document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Tile Floor", {
        tbe::core::WallAssemblyLayer{.material_id = floor_tile_material, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = concrete_material, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Core},
    });
    const auto ceiling_assembly = shared_wall_document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Ceiling, "Gypsum Ceiling", {
        tbe::core::WallAssemblyLayer{.material_id = gypsum_material, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
    });
    assert(near(shared_wall_document.get_wall_type(test_wall_type)->layers[0].thickness_meters +
        shared_wall_document.get_wall_type(test_wall_type)->layers[1].thickness_meters +
        shared_wall_document.get_wall_type(test_wall_type)->layers[2].thickness_meters, 0.24));
    shared_wall_document.set_wall_type(shared_mid, test_wall_type);
    assert(near(shared_wall_document.find_ptr(shared_mid)->wall()->thickness_meters, 0.24));
    const auto shared_room_schedule = shared_wall_document.generate_room_schedule();
    assert(shared_room_schedule.size() == 2);
    assert(shared_room_schedule.front().interior_area_square_meters < shared_room_schedule.front().centerline_area_square_meters);
    assert(near(shared_room_schedule.front().floor_finish_area_square_meters, shared_room_schedule.front().interior_area_square_meters));
    assert(near(shared_room_schedule.front().ceiling_area_square_meters, shared_room_schedule.front().interior_area_square_meters));
    const auto generated_floor_ids = shared_wall_document.generate_floor_systems_for_all_rooms(floor_assembly);
    const auto generated_ceiling_ids = shared_wall_document.generate_ceiling_systems_for_all_rooms(ceiling_assembly, 2.9);
    assert(generated_floor_ids.size() == 2);
    assert(generated_ceiling_ids.size() == 2);
    const auto slab_id = shared_wall_document.create_slab(shared_level, {
        {.x = 0.0, .y = 0.0},
        {.x = 8.0, .y = 0.0},
        {.x = 8.0, .y = 4.0},
        {.x = 0.0, .y = 4.0},
    }, 0.20, concrete_material);
    const auto* slab = shared_wall_document.find_ptr(slab_id)->slab();
    assert(slab != nullptr);
    assert(near(slab->area_square_meters, 32.0));
    assert(near(slab->volume_cubic_meters, 6.4));
    assert(!slab->mesh.vertices.empty());
    const auto shared_adjacencies = shared_wall_document.wall_room_adjacencies();
    assert(std::count_if(shared_adjacencies.begin(), shared_adjacencies.end(), [shared_mid](const auto& row) {
        return row.wall_id == shared_mid && row.room_id != 0;
    }) == 2);
    assert(std::count_if(shared_adjacencies.begin(), shared_adjacencies.end(), [](const auto& row) {
        return row.room_id == 0;
    }) > 0);

    const auto before_incremental = shared_wall_document.recompute_all_rooms();
    (void)before_incremental;
    shared_wall_document.mark_rooms_dirty_for_wall(shared_mid);
    const auto affected_rooms = shared_wall_document.dirty_room_ids();
    assert(affected_rooms.size() == 2);
    shared_wall_document.set_wall_axis(
        shared_mid,
        tbe::core::Line2{.start = {.x = 5.0, .y = 0.0}, .end = {.x = 5.0, .y = 4.0}}
    );
    auto incremental_areas = sorted_room_areas(shared_wall_document, shared_wall_document.recompute_all_rooms());
    auto full_areas = sorted_room_areas(shared_wall_document, shared_wall_document.recompute_all_rooms());
    assert(incremental_areas == full_areas);

    const auto wall_schedule = shared_wall_document.generate_wall_schedule();
    const auto floor_schedule = shared_wall_document.generate_floor_finish_schedule();
    const auto ceiling_schedule = shared_wall_document.generate_ceiling_schedule();
    const auto slab_schedule = shared_wall_document.generate_slab_schedule();
    const auto opening_schedule_before = shared_wall_document.generate_opening_schedule();
    assert(opening_schedule_before.empty());
    const auto sched_door_id = shared_wall_document.create_door("Door", shared_mid, 2.0, 1.0, 2.1);
    const auto sched_window_id = shared_wall_document.create_window("Window", shared_mid, 3.2, 0.8, 1.2, 0.9);
    const auto updated_wall_schedule = shared_wall_document.generate_wall_schedule();
    const auto updated_opening_schedule = shared_wall_document.generate_opening_schedule();
    assert(updated_opening_schedule.size() == 2);
    assert(std::any_of(updated_opening_schedule.begin(), updated_opening_schedule.end(), [sched_door_id](const auto& row) {
        return row.element_id == sched_door_id && near(row.area_square_meters, 2.1);
    }));
    assert(std::any_of(updated_opening_schedule.begin(), updated_opening_schedule.end(), [sched_window_id](const auto& row) {
        return row.element_id == sched_window_id && near(row.area_square_meters, 0.96);
    }));
    const auto shared_wall_schedule_row = std::find_if(updated_wall_schedule.begin(), updated_wall_schedule.end(), [shared_mid](const auto& row) {
        return row.wall_id == shared_mid;
    });
    assert(shared_wall_schedule_row != updated_wall_schedule.end());
    assert(shared_wall_schedule_row->net_area_square_meters < shared_wall_schedule_row->gross_area_square_meters);
    assert(shared_wall_schedule_row->wall_type_id == test_wall_type);
    assert(shared_wall_schedule_row->gross_volume_cubic_meters > shared_wall_schedule_row->net_volume_cubic_meters);
    assert(shared_wall_schedule_row->material_volume_by_id.at(brick_material) > 0.0);
    assert(floor_schedule.size() == 2);
    assert(ceiling_schedule.size() == 2);
    assert(slab_schedule.size() == 1);
    assert(std::all_of(floor_schedule.begin(), floor_schedule.end(), [](const auto& row) {
        return row.area_square_meters > 0.0;
    }));
    assert(std::all_of(ceiling_schedule.begin(), ceiling_schedule.end(), [](const auto& row) {
        return row.area_square_meters > 0.0;
    }));
    assert(std::all_of(floor_schedule.begin(), floor_schedule.end(), [](const auto& row) {
        return !row.layer_quantities.empty();
    }));
    shared_wall_document.mark_rooms_dirty_for_wall(shared_mid);
    assert(std::all_of(shared_wall_document.floor_systems().begin(), shared_wall_document.floor_systems().end(), [](const auto& item) {
        return item.second.dirty;
    }));
    assert(std::all_of(shared_wall_document.ceiling_systems().begin(), shared_wall_document.ceiling_systems().end(), [](const auto& item) {
        return item.second.dirty;
    }));
    const auto recomputed_dirty = shared_wall_document.recompute_dirty_rooms();
    (void)recomputed_dirty;
    assert(std::all_of(shared_wall_document.floor_systems().begin(), shared_wall_document.floor_systems().end(), [](const auto& item) {
        return !item.second.dirty;
    }));
    assert(std::all_of(shared_wall_document.ceiling_systems().begin(), shared_wall_document.ceiling_systems().end(), [](const auto& item) {
        return !item.second.dirty;
    }));
    const auto roof_id = shared_wall_document.create_roof(shared_level, {
        {.x = -0.2, .y = -0.2},
        {.x = 8.2, .y = -0.2},
        {.x = 8.2, .y = 4.2},
        {.x = -0.2, .y = 4.2},
    }, tbe::core::RoofType::Flat, 0.18, concrete_material);
    const auto column_id = shared_wall_document.create_column(shared_level, {.x = 1.0, .y = 1.0}, 0.3, 0.4, 3.0, concrete_material);
    const auto beam_id = shared_wall_document.create_beam(shared_level, {.x = 1.0, .y = 1.0}, {.x = 7.0, .y = 1.0}, 0.25, 0.4, concrete_material);
    const auto stair_id = shared_wall_document.create_stair(shared_level, shared_level, {.x = 6.5, .y = 0.4}, {.x = 0.0, .y = 1.0}, 1.0, 3.0, 4.0, 17, 16, concrete_material);
    shared_wall_document.regenerate_dirty_geometry();
    const auto roof_schedule = shared_wall_document.generate_roof_schedule();
    const auto column_schedule = shared_wall_document.generate_column_schedule();
    const auto beam_schedule = shared_wall_document.generate_beam_schedule();
    const auto stair_schedule = shared_wall_document.generate_stair_schedule();
    assert(roof_schedule.size() == 1);
    assert(column_schedule.size() == 1);
    assert(beam_schedule.size() == 1);
    assert(stair_schedule.size() == 1);
    assert(near(roof_schedule.front().area_square_meters, 36.96));
    assert(near(roof_schedule.front().volume_cubic_meters, 6.6528));
    assert(near(column_schedule.front().volume_cubic_meters, 0.36));
    assert(near(beam_schedule.front().length_meters, 6.0));
    assert(near(beam_schedule.front().volume_cubic_meters, 0.6));
    assert(stair_schedule.front().riser_count == 17);
    assert(near(stair_schedule.front().total_run_meters, 4.0));
    const auto material_takeoff = shared_wall_document.generate_material_takeoff();
    assert(std::any_of(material_takeoff.begin(), material_takeoff.end(), [brick_material](const auto& row) {
        return row.material_id == brick_material && row.quantity > 0.0;
    }));
    assert(std::any_of(material_takeoff.begin(), material_takeoff.end(), [floor_tile_material](const auto& row) {
        return row.material_id == floor_tile_material && row.quantity > 0.0;
    }));
    assert(std::any_of(material_takeoff.begin(), material_takeoff.end(), [gypsum_material](const auto& row) {
        return row.material_id == gypsum_material && row.quantity > 0.0;
    }));
    assert(std::any_of(material_takeoff.begin(), material_takeoff.end(), [concrete_material](const auto& row) {
        return row.material_id == concrete_material && row.quantity > 0.0;
    }));
    assert(std::count_if(material_takeoff.begin(), material_takeoff.end(), [concrete_material](const auto& row) {
        return row.material_id == concrete_material;
    }) >= 1);
    assert(std::any_of(material_takeoff.begin(), material_takeoff.end(), [glass_material](const auto& row) {
        return row.material_id == glass_material || row.material_name == "Glass";
    }) || !material_takeoff.empty());
    const auto enriched_validation = shared_wall_document.validate_document();
    assert(enriched_validation.error_count() == 0);
    assert(shared_wall_document.find_ptr(roof_id)->roof() != nullptr);
    assert(shared_wall_document.find_ptr(column_id)->column() != nullptr);
    assert(shared_wall_document.find_ptr(beam_id)->beam() != nullptr);
    assert(shared_wall_document.find_ptr(stair_id)->stair() != nullptr);

    tbe::core::Document l_shape_document{"L Shape"};
    const auto l_level = l_shape_document.create_level("Level 1", 0.0, 3.0);
    l_shape_document.create_wall("Bottom", tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 6.0, .y = 0.0}}, 0.2, 3.0, l_level);
    l_shape_document.create_wall("Right", tbe::core::Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 2.0}}, 0.2, 3.0, l_level);
    l_shape_document.create_wall("MidTop", tbe::core::Line2{.start = {.x = 6.0, .y = 2.0}, .end = {.x = 2.0, .y = 2.0}}, 0.2, 3.0, l_level);
    l_shape_document.create_wall("Inner", tbe::core::Line2{.start = {.x = 2.0, .y = 2.0}, .end = {.x = 2.0, .y = 6.0}}, 0.2, 3.0, l_level);
    l_shape_document.create_wall("Top", tbe::core::Line2{.start = {.x = 2.0, .y = 6.0}, .end = {.x = 0.0, .y = 6.0}}, 0.2, 3.0, l_level);
    l_shape_document.create_wall("Left", tbe::core::Line2{.start = {.x = 0.0, .y = 6.0}, .end = {.x = 0.0, .y = 0.0}}, 0.2, 3.0, l_level);
    l_shape_document.auto_join_walls();
    const auto l_room_ids = l_shape_document.detect_rooms();
    assert(l_room_ids.size() == 1);
    const auto* l_room = l_shape_document.find_ptr(l_room_ids.front())->room();
    assert(l_room != nullptr);
    assert(near(l_room->centerline_area_square_meters, 20.0));
    assert(l_room->centerline_boundary_polygon.size() >= 6);

    tbe::core::Project multi_project{"Multi Project"};
    multi_project.active_document() = multi_room_document;
    const auto multi_json = multi_project.to_json();
    auto loaded_multi_project = tbe::core::Project::from_json(multi_json);
    auto& loaded_multi_document = loaded_multi_project.active_document();
    loaded_multi_document.regenerate_dirty_geometry();
    assert(loaded_multi_document.detect_rooms().size() == 3);
    const auto loaded_room_schedule = loaded_multi_document.generate_room_schedule();
    assert(!loaded_room_schedule.empty());
    assert(std::all_of(loaded_room_schedule.begin(), loaded_room_schedule.end(), [](const auto& row) {
        return row.interior_area_square_meters > 0.0;
    }));
    assert(loaded_multi_document.materials().empty());

    tbe::core::Document grid_document{"Grid"};
    const auto grid_level = grid_document.create_level("Level 1", 0.0, 3.0);
    constexpr int columns = 5;
    constexpr int rows = 5;
    constexpr double cell = 4.0;
    for (int x = 0; x <= columns; ++x) {
        grid_document.create_wall(
            "V",
            tbe::core::Line2{.start = {.x = x * cell, .y = 0.0}, .end = {.x = x * cell, .y = rows * cell}},
            0.2,
            3.0,
            grid_level
        );
    }
    for (int y = 0; y <= rows; ++y) {
        grid_document.create_wall(
            "H",
            tbe::core::Line2{.start = {.x = 0.0, .y = y * cell}, .end = {.x = columns * cell, .y = y * cell}},
            0.2,
            3.0,
            grid_level
        );
    }
    grid_document.auto_join_walls();
    const auto grid_room_ids = grid_document.detect_rooms();
    assert(grid_room_ids.size() == static_cast<std::size_t>(columns * rows));
    grid_document.regenerate_dirty_geometry();
    const auto grid_validation = grid_document.validate_document();
    assert(grid_validation.error_count() == 0);

    auto* artificial_wall = shared_wall_document.find_ptr(shared_mid)->wall();
    artificial_wall->openings.push_back(tbe::core::HostedOpening{
        .element_id = 424242,
        .kind = tbe::core::OpeningKind::Door,
        .offset_meters = 2.0,
        .width_meters = 100.0,
        .height_meters = 10.0,
        .sill_height_meters = 0.0,
    });
    const auto invalid_net_report = shared_wall_document.validate_document();
    assert(invalid_net_report.error_count() > 0);

    tbe::core::Project materials_project{"Materials Project"};
    auto& materials_doc = materials_project.active_document();
    const auto materials_level = materials_doc.create_level("Level 1", 0.0, 3.0);
    const auto material_a = materials_doc.create_material("Brick", tbe::core::MaterialCategory::Structural, 1800.0, 120.0);
    const auto material_b = materials_doc.create_material("Plaster", tbe::core::MaterialCategory::Finish, 950.0, 40.0);
    const auto material_c = materials_doc.create_material("Concrete", tbe::core::MaterialCategory::Structural, 2400.0, 110.0);
    const auto persisted_wall_type = materials_doc.create_wall_type("Persisted Wall", {
        tbe::core::WallAssemblyLayer{.material_id = material_b, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = material_a, .thickness_meters = 0.18, .function = tbe::core::WallLayerFunction::Core},
    });
    const auto persisted_floor_assembly = materials_doc.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Persisted Floor", {
        tbe::core::WallAssemblyLayer{.material_id = material_b, .thickness_meters = 0.01, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = material_c, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Core},
    });
    const auto persisted_ceiling_assembly = materials_doc.create_layered_assembly(tbe::core::LayeredAssemblyKind::Ceiling, "Persisted Ceiling", {
        tbe::core::WallAssemblyLayer{.material_id = material_b, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
    });
    const auto persisted_wall = materials_doc.create_wall(
        "Persisted",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.0, .y = 0.0}},
        0.2,
        3.0,
        materials_level
    );
    materials_doc.set_wall_type(persisted_wall, persisted_wall_type);
    materials_doc.create_wall("Persisted Right", tbe::core::Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 4.0}}, 0.2, 3.0, materials_level);
    materials_doc.create_wall("Persisted Top", tbe::core::Line2{.start = {.x = 4.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}}, 0.2, 3.0, materials_level);
    materials_doc.create_wall("Persisted Left", tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}}, 0.2, 3.0, materials_level);
    const auto persisted_room_ids = materials_doc.detect_rooms();
    materials_doc.generate_floor_systems_for_all_rooms(persisted_floor_assembly);
    materials_doc.generate_ceiling_systems_for_all_rooms(persisted_ceiling_assembly, 2.9);
    materials_doc.create_slab(materials_level, {
        {.x = 0.0, .y = 0.0},
        {.x = 4.0, .y = 0.0},
        {.x = 4.0, .y = 4.0},
        {.x = 0.0, .y = 4.0},
    }, 0.18, material_c);
    materials_doc.create_roof(materials_level, {
        {.x = -0.2, .y = -0.2},
        {.x = 4.2, .y = -0.2},
        {.x = 4.2, .y = 4.2},
        {.x = -0.2, .y = 4.2},
    }, tbe::core::RoofType::Flat, 0.16, material_c);
    materials_doc.create_column(materials_level, {.x = 0.5, .y = 0.5}, 0.3, 0.3, 3.0, material_c);
    materials_doc.create_beam(materials_level, {.x = 0.5, .y = 0.5}, {.x = 3.5, .y = 0.5}, 0.25, 0.35, material_c);
    materials_doc.create_stair(materials_level, materials_level, {.x = 3.0, .y = 0.3}, {.x = 0.0, .y = 1.0}, 1.0, 3.0, 3.5, 17, 16, material_c);
    assert(persisted_room_ids.size() == 1);
    const auto materials_json = materials_project.to_json();
    auto loaded_materials_project = tbe::core::Project::from_json(materials_json);
    loaded_materials_project.active_document().regenerate_dirty_geometry();
    assert(!loaded_materials_project.active_document().materials().empty());
    assert(!loaded_materials_project.active_document().wall_types().empty());
    assert(!loaded_materials_project.active_document().layered_assemblies().empty());
    assert(!loaded_materials_project.active_document().floor_systems().empty());
    assert(!loaded_materials_project.active_document().ceiling_systems().empty());
    assert(std::count_if(
        loaded_materials_project.active_document().elements().begin(),
        loaded_materials_project.active_document().elements().end(),
        [](const auto& element) { return element.slab() != nullptr; }
    ) == 1);
    assert(std::count_if(
        loaded_materials_project.active_document().elements().begin(),
        loaded_materials_project.active_document().elements().end(),
        [](const auto& element) { return element.roof() != nullptr; }
    ) == 1);
    assert(std::count_if(
        loaded_materials_project.active_document().elements().begin(),
        loaded_materials_project.active_document().elements().end(),
        [](const auto& element) { return element.column() != nullptr; }
    ) == 1);
    assert(std::count_if(
        loaded_materials_project.active_document().elements().begin(),
        loaded_materials_project.active_document().elements().end(),
        [](const auto& element) { return element.beam() != nullptr; }
    ) == 1);
    assert(std::count_if(
        loaded_materials_project.active_document().elements().begin(),
        loaded_materials_project.active_document().elements().end(),
        [](const auto& element) { return element.stair() != nullptr; }
    ) == 1);
    assert(!loaded_materials_project.active_document().generate_slab_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_roof_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_column_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_beam_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_stair_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_floor_finish_schedule().empty());
    assert(!loaded_materials_project.active_document().generate_ceiling_schedule().empty());

    tbe::core::Document invalid_material_document{"Invalid Material"};
    const auto invalid_material_level = invalid_material_document.create_level("Level 1", 0.0, 3.0);
    const auto invalid_wall = invalid_material_document.create_wall(
        "Invalid",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.0, .y = 0.0}},
        0.2,
        3.0,
        invalid_material_level
    );
    invalid_material_document.restore_element(tbe::core::Element{
        invalid_wall,
        tbe::core::ElementKind::Wall,
        "Invalid",
        tbe::core::WallData{
            .level_id = invalid_material_level,
            .wall_type_id = 7777,
            .axis = tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 4.0, .y = 0.0}},
            .thickness_meters = 0.2,
            .height_meters = 3.0,
        }
    });
    const auto invalid_material_report = invalid_material_document.validate_document();
    assert(invalid_material_report.error_count() > 0);

    tbe::core::Document invalid_layer_document{"Invalid Layer"};
    const auto valid_material = invalid_layer_document.create_material("Core", tbe::core::MaterialCategory::Structural);
    const auto invalid_wall_type_id = invalid_layer_document.create_wall_type("Temp", {
        tbe::core::WallAssemblyLayer{.material_id = valid_material, .thickness_meters = 0.1, .function = tbe::core::WallLayerFunction::Core},
    });
    invalid_layer_document.update_wall_type(tbe::core::WallTypeData{
        .wall_type_id = invalid_wall_type_id,
        .name = "Temp",
        .layers = {
            tbe::core::WallAssemblyLayer{.material_id = valid_material, .thickness_meters = -0.1, .function = tbe::core::WallLayerFunction::Core},
        },
    });
    const auto invalid_layer_report = invalid_layer_document.validate_document();
    assert(invalid_layer_report.error_count() > 0);

    const auto invalid_floor_json =
        "{\"schema\":\"tbe.document.v1\",\"name\":\"Invalid Floor\",\"next_id\":10,"
        "\"materials\":[{\"material_id\":2,\"name\":\"Finish\",\"category\":\"Finish\",\"metadata\":{}}],"
        "\"wall_types\":[],"
        "\"assemblies\":[{\"assembly_id\":3,\"kind\":\"Floor\",\"name\":\"Broken Floor\",\"layers\":[{\"material_id\":9999,\"thickness\":0.02,\"function\":\"InteriorFinish\"}]}],"
        "\"floor_systems\":[{\"system_id\":4,\"room_id\":999,\"level_id\":1,\"assembly_id\":3,\"area\":12.0,\"dirty\":false,"
        "\"boundary_polygon\":[{\"x\":0.0,\"y\":0.0},{\"x\":4.0,\"y\":0.0},{\"x\":4.0,\"y\":3.0},{\"x\":0.0,\"y\":3.0}]}],"
        "\"ceiling_systems\":[],"
        "\"elements\":[{\"id\":1,\"kind\":\"Level\",\"name\":\"Level 1\",\"revision\":1,"
        "\"level\":{\"name\":\"Level 1\",\"elevation\":0.0,\"default_wall_height\":3.0}}]}";
    auto invalid_floor_loaded = tbe::core::Document::from_json(invalid_floor_json);
    const auto invalid_floor_report = invalid_floor_loaded.validate_document();
    assert(invalid_floor_report.error_count() > 0);
    assert(std::any_of(invalid_floor_report.issues.begin(), invalid_floor_report.issues.end(), [](const auto& issue) {
        return issue.message.find("missing room") != std::string::npos || issue.message.find("missing material") != std::string::npos;
    }));

    const auto invalid_structure_json =
        "{\"schema\":\"tbe.document.v1\",\"name\":\"Invalid Structure\",\"next_id\":20,"
        "\"materials\":[],\"wall_types\":[],\"assemblies\":[],\"floor_systems\":[],\"ceiling_systems\":[],"
        "\"elements\":["
        "{\"id\":1,\"kind\":\"Level\",\"name\":\"Level 1\",\"revision\":1,\"level\":{\"name\":\"Level 1\",\"elevation\":0.0,\"default_wall_height\":3.0}},"
        "{\"id\":2,\"kind\":\"Roof\",\"name\":\"Roof\",\"revision\":1,\"roof\":{\"level_id\":1,\"roof_type\":\"Flat\",\"thickness\":0.2,\"material_id\":999,\"assembly_id\":0,\"boundary_polygon\":[{\"x\":0.0,\"y\":0.0},{\"x\":4.0,\"y\":0.0},{\"x\":4.0,\"y\":3.0},{\"x\":0.0,\"y\":3.0}]}},"
        "{\"id\":3,\"kind\":\"Column\",\"name\":\"Column\",\"revision\":1,\"column\":{\"level_id\":1,\"position\":{\"x\":1.0,\"y\":1.0},\"width\":-0.3,\"depth\":0.3,\"height\":3.0,\"material_id\":0}},"
        "{\"id\":4,\"kind\":\"Beam\",\"name\":\"Beam\",\"revision\":1,\"beam\":{\"level_id\":1,\"start\":{\"x\":0.0,\"y\":0.0},\"end\":{\"x\":0.0,\"y\":0.0},\"width\":0.2,\"height\":0.3,\"material_id\":0}},"
        "{\"id\":5,\"kind\":\"Stair\",\"name\":\"Stair\",\"revision\":1,\"stair\":{\"base_level_id\":1,\"top_level_id\":999,\"start\":{\"x\":0.0,\"y\":0.0},\"direction\":{\"x\":0.0,\"y\":1.0},\"width\":1.0,\"total_rise\":3.0,\"total_run\":4.0,\"riser_count\":0,\"tread_count\":16,\"material_id\":0}}]}";
    auto invalid_structure_document = tbe::core::Document::from_json(invalid_structure_json);
    invalid_structure_document.regenerate_dirty_geometry();
    const auto invalid_structure_report = invalid_structure_document.validate_document();
    assert(invalid_structure_report.error_count() > 0);

    return 0;
}
