#include "tbe/api/EngineApi.hpp"
#include "tbe/api/EngineCApi.h"
#include "tbe/core/StressModel.hpp"
#include "tbe/core/Project.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

int main() {
    const auto nearly_equal = [](double left, double right, double epsilon = 1.0e-6) {
        return std::abs(left - right) <= epsilon;
    };

    const auto read_text = [](const std::filesystem::path& path) {
        std::ifstream in(path);
        return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    };

    for (int iteration = 0; iteration < 5; ++iteration) {
        auto session_result = tbe::api::create_session("API Test");
        assert(session_result.ok());
        assert(session_result.value.has_value());
        auto session = std::move(*session_result.value);

        const auto level = session->create_level("Level 1", 0.0, 3.0);
        assert(level.ok());
        assert(level.value.has_value());
        const auto level_id = level.value->value;

        const auto wall_a = session->create_wall("A", {.x = 0.0, .y = 0.0}, {.x = 4.0, .y = 0.0}, 0.2, 3.0, level_id);
        const auto wall_b = session->create_wall("B", {.x = 4.0, .y = 0.0}, {.x = 4.0, .y = 3.0}, 0.2, 3.0, level_id);
        const auto wall_c = session->create_wall("C", {.x = 4.0, .y = 3.0}, {.x = 0.0, .y = 3.0}, 0.2, 3.0, level_id);
        const auto wall_d = session->create_wall("D", {.x = 0.0, .y = 3.0}, {.x = 0.0, .y = 0.0}, 0.2, 3.0, level_id);
        assert(wall_a.ok() && wall_b.ok() && wall_c.ok() && wall_d.ok());

        assert(session->auto_join_walls().ok());
        const auto rooms = session->detect_rooms();
        assert(rooms.ok());
        assert(rooms.value.has_value());
        assert(rooms.value->size() == 1);

        const auto validation = session->get_validation_report();
        assert(validation.ok());
        assert(validation.value.has_value());
        assert(validation.value->error_count == 0);

        const auto schedule = session->generate_schedules();
        assert(schedule.ok());
        assert(schedule.value.has_value());
        assert(schedule.value->wall_rows == 4);
        assert(schedule.value->room_rows == 1);

        const auto wall_schedule = session->get_wall_schedule();
        assert(wall_schedule.ok());
        assert(wall_schedule.value.has_value());
        assert(wall_schedule.value->size() == 4);
        const auto room_schedule = session->get_room_schedule();
        assert(room_schedule.ok());
        const auto cached_validation = session->get_cached_validation_report();
        assert(cached_validation.status == tbe::api::ApiStatus::Ok || cached_validation.status == tbe::api::ApiStatus::NotFound);
        const auto fresh_validation = session->get_validation_report();
        assert(fresh_validation.ok());
        const auto takeoff = session->get_material_takeoff_summary();
        assert(takeoff.ok());

        const auto saved = session->save_project_json();
        assert(saved.ok());
        assert(saved.value.has_value());
        assert(saved.value->find("\"elements\"") != std::string::npos);

        const auto export_dir = std::filesystem::temp_directory_path() / "tbe_api_perf_contract";
        std::filesystem::create_directories(export_dir);
        const auto closed_svg_path = export_dir / ("api_export_closed_" + std::to_string(iteration) + ".svg");
        assert(session->export_svg(closed_svg_path.string()).ok());
        assert(std::filesystem::exists(closed_svg_path));
        const auto closed_svg_text = read_text(closed_svg_path);
        assert(closed_svg_text.find("data-element-id=\"") != std::string::npos);
        assert(closed_svg_text.find("data-kind=\"wall\"") != std::string::npos);

        auto reloaded_result = tbe::api::create_session("Reload");
        assert(reloaded_result.ok());
        assert(reloaded_result.value.has_value());
        auto reloaded = std::move(*reloaded_result.value);
        assert(reloaded->load_project_json(*saved.value).ok());
        const auto reloaded_schedule = reloaded->generate_schedules();
        assert(reloaded_schedule.ok());
        assert(reloaded_schedule.value->room_rows == 1);

        const auto moved = session->set_wall_axis(wall_b.value->value, {.x = 5.0, .y = 0.0}, {.x = 5.0, .y = 3.0});
        assert(moved.ok());
        const auto freshness_after_move = session->get_freshness_summary();
        assert(freshness_after_move.ok());
        assert(freshness_after_move.value->room_metrics != tbe::api::FreshnessState::Clean);
        assert(freshness_after_move.value->schedules != tbe::api::FreshnessState::Clean);
        assert(freshness_after_move.value->material_takeoff != tbe::api::FreshnessState::Clean);
        assert(freshness_after_move.value->validation_report != tbe::api::FreshnessState::Clean);
        const auto cached_room_schedule = session->get_cached_room_schedule();
        assert(cached_room_schedule.freshness != tbe::api::FreshnessState::Clean);
        const auto regenerated_room_schedule = session->generate_room_schedule();
        assert(regenerated_room_schedule.ok());
        assert(regenerated_room_schedule.freshness == tbe::api::FreshnessState::Clean);
        assert(session->recompute_all_final().ok());
        const auto freshness_after_final = session->get_freshness_summary();
        assert(freshness_after_final.ok());
        assert(freshness_after_final.value->room_metrics == tbe::api::FreshnessState::Clean);
        assert(freshness_after_final.value->schedules == tbe::api::FreshnessState::Clean);
        assert(freshness_after_final.value->material_takeoff == tbe::api::FreshnessState::Clean);
        assert(freshness_after_final.value->validation_report == tbe::api::FreshnessState::Clean);

        assert(session->set_performance_profile(tbe::api::PerformanceProfile::BatterySaver).ok());
        assert(session->set_compute_mode(tbe::api::ComputeMode::InteractivePreview).ok());
        assert(session->set_wall_axis(wall_b.value->value, {.x = 4.5, .y = 0.0}, {.x = 4.5, .y = 3.0}).ok());
        assert(session->recompute_dirty().ok());
        const auto battery_freshness = session->get_freshness_summary();
        assert(battery_freshness.ok());
        assert(battery_freshness.value->room_metrics == tbe::api::FreshnessState::Clean);
        assert(battery_freshness.value->validation_report != tbe::api::FreshnessState::Clean);

        const auto stale_save = session->save_project_json_cached(true);
        assert(stale_save.ok());
        assert(stale_save.freshness != tbe::api::FreshnessState::Clean);
        const auto final_save = session->save_project_json();
        assert(final_save.ok());
        assert(final_save.freshness == tbe::api::FreshnessState::Clean);

        const auto freshness_after_export = session->get_freshness_summary();
        assert(freshness_after_export.ok());
        assert(freshness_after_export.value->validation_report == tbe::api::FreshnessState::Clean);

        assert(session->undo().ok());
        assert(session->redo().ok());

        auto stale_load_result = tbe::api::create_session("Stale Load");
        assert(stale_load_result.ok());
        auto stale_loaded = std::move(*stale_load_result.value);
        assert(stale_loaded->load_project_json(*stale_save.value).ok());
        const auto loaded_cached_schedule = stale_loaded->get_cached_room_schedule();
        assert(loaded_cached_schedule.status == tbe::api::ApiStatus::NotFound);
        const auto loaded_generated_schedule = stale_loaded->get_room_schedule();
        assert(loaded_generated_schedule.ok());
    }

    {
        tbe::core::Document document{"Edit Core Test"};
        const auto level_id = document.create_level("Level 1", 0.0, 3.0);

        const auto wall_a = document.create_wall("A", {{0.0, 0.0}, {8.0, 0.0}}, 0.2, 3.0, level_id);
        const auto wall_b = document.create_wall("B", {{8.0, 0.0}, {8.0, 3.0}}, 0.2, 3.0, level_id);
        const auto wall_c = document.create_wall("C", {{8.0, 3.0}, {0.0, 3.0}}, 0.2, 3.0, level_id);
        const auto wall_d = document.create_wall("D", {{0.0, 3.0}, {0.0, 0.0}}, 0.2, 3.0, level_id);
        const auto wall_e = document.create_wall("E", {{4.0, 0.0}, {4.0, 3.0}}, 0.2, 3.0, level_id);
        assert(wall_c != 0);
        assert(wall_d != 0);
        assert(wall_e != 0);
        document.auto_join_walls();
        const auto rooms_before = document.detect_rooms();
        assert(rooms_before.size() == 2);
        const auto room_before = document.generate_room_schedule();
        assert(room_before.size() == 2);
        const auto room_areas_before = [&]() {
            std::vector<double> areas;
            areas.reserve(room_before.size());
            for (const auto& row : room_before) {
                areas.push_back(row.interior_area_square_meters);
            }
            std::sort(areas.begin(), areas.end());
            return areas;
        }();

        const auto wall_schedule_before = document.generate_wall_schedule();
        const auto wall_before = std::find_if(wall_schedule_before.begin(), wall_schedule_before.end(), [wall_a](const auto& row) {
            return row.wall_id == wall_a;
        });
        assert(wall_before != wall_schedule_before.end());
        assert(nearly_equal(wall_before->thickness_meters, 0.2));
        assert(nearly_equal(wall_before->height_meters, 3.0));

        const auto door_1 = document.create_door("Door 1", wall_a, 1.0, 0.9, 2.1);
        const auto door_2 = document.create_door("Door 2", wall_a, 2.6, 0.9, 2.1);
        bool rejected_overlap = false;
        try {
            document.move_hosted_opening(door_2, 1.05);
        } catch (const std::exception&) {
            rejected_overlap = true;
        }
        assert(rejected_overlap);

        const auto window = document.create_window("Window 1", wall_b, 1.5, 1.0, 1.2, 0.9);
        bool rejected_outside = false;
        try {
            document.move_hosted_opening(window, 5.0);
        } catch (const std::exception&) {
            rejected_outside = true;
        }
        assert(rejected_outside);

        document.set_wall_properties(wall_a, 0.25, 3.4);
        const auto updated_wall_schedule = document.generate_wall_schedule();
        const auto wall_after = std::find_if(updated_wall_schedule.begin(), updated_wall_schedule.end(), [wall_a](const auto& row) {
            return row.wall_id == wall_a;
        });
        assert(wall_after != updated_wall_schedule.end());
        assert(nearly_equal(wall_after->thickness_meters, 0.25));
        assert(nearly_equal(wall_after->height_meters, 3.4));

        document.set_wall_axis(wall_e, {{4.5, 0.0}, {4.5, 3.0}});
        const auto rooms_after_move = document.detect_rooms();
        assert(rooms_after_move.size() == 2);
        const auto room_after = document.generate_room_schedule();
        assert(room_after.size() == 2);
        const auto room_areas_after = [&]() {
            std::vector<double> areas;
            areas.reserve(room_after.size());
            for (const auto& row : room_after) {
                areas.push_back(row.interior_area_square_meters);
            }
            std::sort(areas.begin(), areas.end());
            return areas;
        }();
        assert(room_areas_before != room_areas_after);

        document.delete_element(wall_a);
        const auto deleted_door = document.find_ptr(door_1);
        const auto deleted_door_2 = document.find_ptr(door_2);
        assert(deleted_door == nullptr || deleted_door->door() == nullptr);
        assert(deleted_door_2 == nullptr || deleted_door_2->door() == nullptr);
        const auto rooms_after_delete = document.detect_rooms();
        assert(rooms_after_delete.empty());
    }

    {
        auto session_result = tbe::api::create_session("Spatial API Test");
        assert(session_result.ok());
        assert(session_result.value.has_value());
        auto session = std::move(*session_result.value);

        const auto level = session->create_level("Level 1", 0.0, 3.0);
        assert(level.ok());
        const auto level_id = level.value->value;

        const auto wall_a = session->create_wall("Bottom", {.x = 0.0, .y = 0.0}, {.x = 4.0, .y = 0.0}, 0.2, 3.0, level_id);
        const auto wall_b = session->create_wall("Right", {.x = 4.0, .y = 0.0}, {.x = 4.0, .y = 3.0}, 0.2, 3.0, level_id);
        const auto wall_c = session->create_wall("Top", {.x = 4.0, .y = 3.0}, {.x = 0.0, .y = 3.0}, 0.2, 3.0, level_id);
        const auto wall_d = session->create_wall("Left", {.x = 0.0, .y = 3.0}, {.x = 0.0, .y = 0.0}, 0.2, 3.0, level_id);
        assert(wall_a.ok() && wall_b.ok() && wall_c.ok() && wall_d.ok());
        const auto door = session->create_door("Door", wall_a.value->value, 1.0, 0.9, 2.1);
        const auto window = session->create_window("Window", wall_b.value->value, 1.5, 1.0, 1.2, 1.0);
        assert(door.ok());
        assert(window.ok());
        const auto column = session->create_column(level_id, {.x = 1.0, .y = 1.0}, 0.3, 0.3, 3.0, 0);
        assert(column.ok());

        assert(session->auto_join_walls().ok());
        const auto rooms = session->detect_rooms();
        assert(rooms.ok());
        assert(rooms.value->size() == 1);
        assert(session->rebuild_spatial_index().ok());

        const auto stats = session->spatial_index_stats();
        assert(stats.ok());
        assert(stats.value.has_value());
        assert(stats.value->element_bounds_count >= 7);
        assert(stats.value->bucket_count >= 1);
        assert(stats.value->average_bucket_occupancy >= 1.0);
        const auto initial_spatial_version = stats.value->version;

        const auto wall_axis_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 0.0, .y = 2.0}, .tolerance_meters = 0.2});
        assert(wall_axis_hit.ok());
        assert(wall_axis_hit.value.has_value());
        assert(!wall_axis_hit.value->empty());
        assert(wall_axis_hit.value->front().hit_kind == tbe::api::HitKind::WallAxis || wall_axis_hit.value->front().hit_kind == tbe::api::HitKind::WallBody);

        const auto room_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 2.0, .y = 2.0}, .tolerance_meters = 0.2});
        assert(room_hit.ok());
        assert(room_hit.value.has_value());
        assert(!room_hit.value->empty());
        assert(room_hit.value->front().hit_kind == tbe::api::HitKind::RoomInterior);

        const auto wall_over_room_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 2.0, .y = 2.95}, .tolerance_meters = 0.2});
        assert(wall_over_room_hit.ok());
        assert(wall_over_room_hit.value.has_value());
        assert(wall_over_room_hit.value->size() >= 2);
        assert(wall_over_room_hit.value->front().hit_kind == tbe::api::HitKind::WallBody || wall_over_room_hit.value->front().hit_kind == tbe::api::HitKind::WallAxis);

        const auto opening_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 1.0, .y = 0.0}, .tolerance_meters = 0.25});
        assert(opening_hit.ok());
        assert(opening_hit.value.has_value());
        assert(!opening_hit.value->empty());
        assert(opening_hit.value->front().hit_kind == tbe::api::HitKind::Opening);

        const auto column_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 1.0, .y = 1.0}, .tolerance_meters = 0.2});
        assert(column_hit.ok());
        assert(column_hit.value.has_value());
        assert(!column_hit.value->empty());
        assert(column_hit.value->front().hit_kind == tbe::api::HitKind::Column);

        const auto endpoint_snap = session->best_snap({.value = level_id}, {.x = 0.05, .y = 0.04}, 0.2);
        assert(endpoint_snap.ok());
        assert(endpoint_snap.value.has_value());
        assert(endpoint_snap.value->type == tbe::api::SnapType::Endpoint);
        assert(nearly_equal(endpoint_snap.value->point.x, 0.0));
        assert(nearly_equal(endpoint_snap.value->point.y, 0.0));

        const auto midpoint_snap = session->best_snap({.value = level_id}, {.x = 3.98, .y = 1.52}, 0.25);
        assert(midpoint_snap.ok());
        assert(midpoint_snap.value.has_value());
        assert(midpoint_snap.value->type == tbe::api::SnapType::Midpoint);
        assert(nearly_equal(midpoint_snap.value->point.x, 4.0));
        assert(nearly_equal(midpoint_snap.value->point.y, 1.5));

        const auto grid_snap = session->best_snap({.value = level_id}, {.x = 8.2, .y = 7.7}, 0.1);
        assert(grid_snap.ok());
        assert(grid_snap.value.has_value());
        assert(grid_snap.value->type == tbe::api::SnapType::Grid);
        assert(nearly_equal(grid_snap.value->point.x, 8.0));
        assert(nearly_equal(grid_snap.value->point.y, 8.0));

        const auto snap_candidates = session->get_snap_candidates({.value = level_id}, {.x = 0.08, .y = 0.06}, 0.25);
        assert(snap_candidates.ok());
        assert(snap_candidates.value.has_value());
        bool found_intersection = false;
        for (const auto& candidate : *snap_candidates.value) {
            if (candidate.type == tbe::api::SnapType::WallIntersection && nearly_equal(candidate.point.x, 0.0) && nearly_equal(candidate.point.y, 0.0)) {
                found_intersection = true;
                break;
            }
        }
        assert(found_intersection);

        const auto snap_options_filtered = session->get_snap_candidates(
            {.value = level_id},
            {.x = 0.05, .y = 0.04},
            0.2,
            tbe::api::SnapOptionsDTO{
                .enable_grid = false,
                .enable_endpoints = false,
                .enable_midpoints = false,
                .enable_intersections = false,
                .enable_wall_axis = false,
                .enable_orthogonal_projection = false,
                .enable_room_corners = false,
            }
        );
        assert(snap_options_filtered.ok());
        assert(snap_options_filtered.value.has_value());
        assert(snap_options_filtered.value->empty());

        const auto grid_only_snap = session->best_snap(
            {.value = level_id},
            {.x = 8.2, .y = 7.7},
            0.1,
            tbe::api::SnapOptionsDTO{
                .enable_grid = true,
                .enable_endpoints = false,
                .enable_midpoints = false,
                .enable_intersections = false,
                .enable_wall_axis = false,
                .enable_orthogonal_projection = false,
                .enable_room_corners = false,
                .grid_size_meters = 0.5,
            }
        );
        assert(grid_only_snap.ok());
        assert(grid_only_snap.value.has_value());
        assert(grid_only_snap.value->type == tbe::api::SnapType::Grid);
        assert(nearly_equal(grid_only_snap.value->point.x, 8.0));
        assert(nearly_equal(grid_only_snap.value->point.y, 7.5));

        const auto free_intervals = session->compute_wall_free_intervals(wall_a.value->value, 1.0, 0.1);
        assert(free_intervals.ok());
        assert(free_intervals.value.has_value());
        assert(free_intervals.value->size() == 1);
        assert(nearly_equal(free_intervals.value->front().start_offset_meters, 2.05, 1.0e-3));
        assert(nearly_equal(free_intervals.value->front().end_offset_meters, 3.4, 1.0e-3));

        const auto blocked_host = session->find_wall_host_at_point({.value = level_id}, {.x = 1.0, .y = 0.02}, 0.2, 1.0, 0.1);
        assert(blocked_host.ok());
        assert(blocked_host.value.has_value());
        assert(blocked_host.value->wall_id.value == wall_a.value->value);
        assert(!blocked_host.value->valid);
        assert(nearly_equal(blocked_host.value->adjusted_valid_offset_meters, 2.05, 1.0e-3));
        assert(!blocked_host.value->warnings.empty());

        const auto no_interval = session->find_wall_host_at_point({.value = level_id}, {.x = 2.0, .y = 0.02}, 0.2, 3.5, 0.4);
        assert(no_interval.ok());
        assert(no_interval.value.has_value());
        assert(!no_interval.value->valid);
        assert(no_interval.value->free_intervals.empty());

        const auto host = session->find_wall_host_at_point({.value = level_id}, {.x = 0.03, .y = 2.4}, 0.2, 0.9, 0.05);
        assert(host.ok());
        assert(host.value.has_value());
        assert(host.value->wall_id.value == wall_d.value->value);
        assert(nearly_equal(host.value->wall_local_offset_meters, 0.6, 1.0e-3));
        assert(host.value->valid);

        const auto old_right_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 4.0, .y = 2.6}, .tolerance_meters = 0.2});
        assert(old_right_hit.ok());
        assert(old_right_hit.value.has_value());
        assert(!old_right_hit.value->empty());
        assert(old_right_hit.value->front().element_id.value == wall_b.value->value);

        assert(session->set_wall_axis(wall_b.value->value, {.x = 5.0, .y = 0.0}, {.x = 5.0, .y = 3.0}).ok());

        const auto moved_stats = session->spatial_index_stats();
        assert(moved_stats.ok());
        assert(moved_stats.value.has_value());
        assert(moved_stats.value->dirty || moved_stats.value->version > initial_spatial_version);

        const auto new_right_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 5.0, .y = 2.6}, .tolerance_meters = 0.2});
        assert(new_right_hit.ok());
        assert(new_right_hit.value.has_value());
        assert(!new_right_hit.value->empty());
        assert(new_right_hit.value->front().element_id.value == wall_b.value->value);

        assert(session->undo().ok());
        const auto undo_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 4.0, .y = 2.6}, .tolerance_meters = 0.2});
        assert(undo_hit.ok());
        assert(undo_hit.value.has_value());
        assert(!undo_hit.value->empty());
        assert(undo_hit.value->front().element_id.value == wall_b.value->value);

        assert(session->redo().ok());
        const auto redo_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 5.0, .y = 2.6}, .tolerance_meters = 0.2});
        assert(redo_hit.ok());
        assert(redo_hit.value.has_value());
        assert(!redo_hit.value->empty());
        assert(redo_hit.value->front().element_id.value == wall_b.value->value);

        const auto stale_right_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 4.0, .y = 2.6}, .tolerance_meters = 0.2});
        assert(stale_right_hit.ok());
        assert(stale_right_hit.value.has_value());
        if (!stale_right_hit.value->empty()) {
            assert(stale_right_hit.value->front().element_id.value != wall_b.value->value);
        }

        const auto saved = session->save_project_json();
        assert(saved.ok());
        assert(saved.value.has_value());

        auto reload_result = tbe::api::create_session("Spatial Reload");
        assert(reload_result.ok());
        assert(reload_result.value.has_value());
        auto reload = std::move(*reload_result.value);
        assert(reload->load_project_json(*saved.value).ok());
        assert(reload->rebuild_spatial_index().ok());
        const auto reload_hit = reload->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 0.0, .y = 2.0}, .tolerance_meters = 0.2});
        assert(reload_hit.ok());
        assert(reload_hit.value.has_value());
        assert(!reload_hit.value->empty());
        assert(reload_hit.value->front().hit_kind == tbe::api::HitKind::WallAxis || reload_hit.value->front().hit_kind == tbe::api::HitKind::WallBody);
    }

    {
        tbe::core::Project project("Floor Ceiling JSON");
        auto& document = project.active_document();
        const auto level_id = document.create_level("Level 1", 0.0, 3.0);
        const auto material_id = document.create_material("Gypsum", tbe::core::MaterialCategory::Finish);
        const auto floor_assembly_id = document.create_layered_assembly(
            tbe::core::LayeredAssemblyKind::Floor,
            "Floor",
            {tbe::core::WallAssemblyLayer{.material_id = material_id, .thickness_meters = 0.05, .function = tbe::core::WallLayerFunction::Generic}}
        );
        const auto ceiling_assembly_id = document.create_layered_assembly(
            tbe::core::LayeredAssemblyKind::Ceiling,
            "Ceiling",
            {tbe::core::WallAssemblyLayer{.material_id = material_id, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::Generic}}
        );
        document.create_wall("A", {{0.0, 0.0}, {4.0, 0.0}}, 0.2, 3.0, level_id);
        document.create_wall("B", {{4.0, 0.0}, {4.0, 3.0}}, 0.2, 3.0, level_id);
        document.create_wall("C", {{4.0, 3.0}, {0.0, 3.0}}, 0.2, 3.0, level_id);
        document.create_wall("D", {{0.0, 3.0}, {0.0, 0.0}}, 0.2, 3.0, level_id);
        document.auto_join_walls();
        const auto rooms = document.detect_rooms();
        assert(rooms.size() == 1);
        document.create_floor_system_for_room(rooms.front(), floor_assembly_id);
        document.create_ceiling_system_for_room(rooms.front(), ceiling_assembly_id, 0.0);

        auto session_result = tbe::api::create_session("Floor Ceiling API");
        assert(session_result.ok());
        assert(session_result.value.has_value());
        auto session = std::move(*session_result.value);
        assert(session->load_project_json(project.to_json()).ok());
        assert(session->rebuild_spatial_index().ok());

        const auto floor_ceiling_hits = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 2.0, .y = 2.0}, .tolerance_meters = 0.2});
        assert(floor_ceiling_hits.ok());
        assert(floor_ceiling_hits.value.has_value());
        bool saw_floor = false;
        bool saw_ceiling = false;
        bool saw_room = false;
        for (const auto& candidate : *floor_ceiling_hits.value) {
            if (candidate.hit_kind == tbe::api::HitKind::FloorSystem) {
                saw_floor = true;
            } else if (candidate.hit_kind == tbe::api::HitKind::CeilingSystem) {
                saw_ceiling = true;
            } else if (candidate.hit_kind == tbe::api::HitKind::RoomInterior) {
                saw_room = true;
            }
        }
        assert(saw_floor);
        assert(saw_ceiling);
        assert(saw_room);
        assert(floor_ceiling_hits.value->front().hit_kind == tbe::api::HitKind::FloorSystem);
    }

    {
        auto session_result = tbe::api::create_session("Schema API");
        assert(session_result.ok());
        auto session = std::move(*session_result.value);

        const auto schema_version = session->get_schema_version();
        assert(schema_version.ok());
        assert(schema_version.value.has_value());
        assert(*schema_version.value == 1);

        const auto level = session->create_level("Level 1", 0.0, 3.0);
        assert(level.ok());
        assert(session->create_wall("A", {.x = 0.0, .y = 0.0}, {.x = 4.0, .y = 0.0}, 0.2, 3.0, level.value->value).ok());
        const auto json = session->save_project_json();
        assert(json.ok());
        assert(json.value.has_value());
        assert(json.value->find("\"schema_version\":1") != std::string::npos);

        const auto detected = session->detect_schema_version_from_json(*json.value);
        assert(detected.ok());
        assert(detected.value.has_value());
        assert(*detected.value == 1);

        const auto legacy_json = std::string("{\"schema\":\"tbe.project.v1\",\"project_name\":\"Legacy Project\",\"document\":{\"schema\":\"tbe.document.v1\",\"name\":\"Legacy Project Model\",\"next_id\":7,\"elements\":[{\"id\":1,\"kind\":\"Level\",\"name\":\"Level 1\",\"revision\":1,\"level\":{\"name\":\"Level 1\",\"elevation\":0,\"default_wall_height\":3}},{\"id\":2,\"kind\":\"Wall\",\"name\":\"Wall A\",\"revision\":1,\"wall\":{\"level_id\":1,\"axis\":{\"start\":{\"x\":0,\"y\":0},\"end\":{\"x\":4,\"y\":0}},\"thickness\":0.2,\"height\":3,\"joins\":[],\"openings\":[{\"element_id\":6,\"kind\":\"Door\",\"offset\":1,\"width\":0.9,\"height\":2.1,\"sill_height\":0}]}},{\"id\":3,\"kind\":\"Wall\",\"name\":\"Wall B\",\"revision\":1,\"wall\":{\"level_id\":1,\"axis\":{\"start\":{\"x\":4,\"y\":0},\"end\":{\"x\":4,\"y\":3}},\"thickness\":0.2,\"height\":3,\"joins\":[],\"openings\":[]}},{\"id\":4,\"kind\":\"Wall\",\"name\":\"Wall C\",\"revision\":1,\"wall\":{\"level_id\":1,\"axis\":{\"start\":{\"x\":4,\"y\":3},\"end\":{\"x\":0,\"y\":3}},\"thickness\":0.2,\"height\":3,\"joins\":[],\"openings\":[]}},{\"id\":5,\"kind\":\"Wall\",\"name\":\"Wall D\",\"revision\":1,\"wall\":{\"level_id\":1,\"axis\":{\"start\":{\"x\":0,\"y\":3},\"end\":{\"x\":0,\"y\":0}},\"thickness\":0.2,\"height\":3,\"joins\":[],\"openings\":[]}},{\"id\":6,\"kind\":\"Door\",\"name\":\"Door\",\"revision\":1,\"door\":{\"host_wall_id\":2,\"offset\":1,\"width\":0.9,\"height\":2.1}}]}}");
        const auto detected_legacy = session->detect_schema_version_from_json(legacy_json);
        assert(detected_legacy.ok());
        assert(detected_legacy.value.has_value());
        assert(*detected_legacy.value == 0);

        const auto migrated = session->migrate_project_json(legacy_json, 0, 1);
        assert(migrated.ok());
        assert(migrated.value.has_value());
        assert(migrated.value->find("\"schema_version\":1") != std::string::npos);
        assert(migrated.value->find("\"level_id\":0") != std::string::npos);

        const auto strict_legacy_load = session->load_project_json_with_mode(legacy_json, tbe::api::LoadMode::Strict);
        assert(strict_legacy_load.status == tbe::api::ApiStatus::ValidationError);

        const auto tolerant_legacy_load = session->load_project_json_with_mode(legacy_json, tbe::api::LoadMode::Tolerant);
        assert(tolerant_legacy_load.ok());
        assert(!tolerant_legacy_load.validation_issues.empty() || !tolerant_legacy_load.message.empty());
        const auto migration_report = session->get_last_migration_report();
        assert(migration_report.ok());
        assert(migration_report.value.has_value());
        assert(migration_report.value->from_version == 0);
        assert(migration_report.value->to_version == 1);
        assert(migration_report.value->migrated_count >= 1);

        tbe::core::Project orphan_project{"Orphan Repair"};
        auto& orphan_document = orphan_project.active_document();
        const auto orphan_level = orphan_document.create_level("Level 1", 0.0, 3.0);
        const auto orphan_wall = orphan_document.create_wall("Wall A", {{0.0, 0.0}, {4.0, 0.0}}, 0.2, 3.0, orphan_level);
        auto* orphan_wall_element = orphan_document.find_ptr(orphan_wall);
        assert(orphan_wall_element != nullptr);
        auto* orphan_wall_data = orphan_wall_element->wall();
        assert(orphan_wall_data != nullptr);
        orphan_wall_data->openings.push_back(tbe::core::HostedOpening{
            .element_id = 999,
            .kind = tbe::core::OpeningKind::Door,
            .offset_meters = 1.0,
            .width_meters = 0.9,
            .height_meters = 2.1,
            .sill_height_meters = 0.0,
        });
        const auto orphan_json = orphan_project.to_json();
        auto orphan_session_result = tbe::api::create_session("Orphan Repair");
        assert(orphan_session_result.ok());
        auto orphan_session = std::move(*orphan_session_result.value);
        assert(orphan_session->load_project_json_with_mode(orphan_json, tbe::api::LoadMode::Tolerant).ok());
        const auto orphan_repair = orphan_session->repair_current_project();
        assert(orphan_repair.ok());
        assert(orphan_repair.value.has_value());
        const auto orphan_validation = orphan_session->get_validation_report();
        assert(orphan_validation.ok());
        assert(orphan_validation.value.has_value());
        assert(orphan_validation.value->error_count == 0);

        const auto repair_load = session->load_project_json_with_mode(legacy_json, tbe::api::LoadMode::Repair);
        assert(repair_load.ok());
        const auto repair_report = session->get_last_repair_report();
        assert(repair_report.ok());
        assert(repair_report.value.has_value());
        assert(repair_report.value->repaired_count >= 1);
        const auto repaired_validation = session->get_validation_report();
        assert(repaired_validation.ok());
        assert(repaired_validation.value.has_value());
        assert(repaired_validation.value->error_count == 0);

        const auto package_dir = std::filesystem::temp_directory_path() / "tbe_api_package_test";
        std::filesystem::remove_all(package_dir);
        assert(session->export_project_package(package_dir.string()).ok());
        assert(std::filesystem::exists(package_dir / "project.json"));
        assert(std::filesystem::exists(package_dir / "metadata.json"));
        assert(std::filesystem::exists(package_dir / "exports" / "floorplan.svg"));
        assert(std::filesystem::exists(package_dir / "exports" / "walls.obj"));
        assert(std::filesystem::exists(package_dir / "debug" / "debug_report.json"));

        auto imported_result = tbe::api::create_session("Package Import");
        assert(imported_result.ok());
        auto imported = std::move(*imported_result.value);
        assert(imported->import_project_package(package_dir.string(), tbe::api::LoadMode::Repair).ok());
        const auto imported_validation = imported->get_validation_report();
        assert(imported_validation.ok());
        assert(imported_validation.value.has_value());
        assert(imported_validation.value->error_count == 0);
        const auto resaved = imported->save_project_json();
        assert(resaved.ok());
        assert(resaved.value.has_value());
        assert(resaved.value->find("\"schema_version\":1") != std::string::npos);

        tbe::core::Project package_project{"Package Building"};
        auto& package_document = package_project.active_document();
        const auto package_level = package_document.create_level("Level 1", 0.0, 3.2);
        const auto package_upper_level = package_document.create_level("Level 2", 3.2, 3.2);
        const auto package_brick = package_document.create_material("Brick", tbe::core::MaterialCategory::Structural, 1800.0, 120.0);
        const auto package_plaster = package_document.create_material("Plaster", tbe::core::MaterialCategory::Finish, 950.0, 40.0);
        const auto package_concrete = package_document.create_material("Concrete", tbe::core::MaterialCategory::Structural, 2400.0, 110.0);
        const auto package_tile = package_document.create_material("Tile", tbe::core::MaterialCategory::Finish, 2100.0, 55.0);
        const auto package_gypsum = package_document.create_material("Gypsum", tbe::core::MaterialCategory::Finish, 850.0, 28.0);
        const auto package_wall_type = package_document.create_wall_type("Masonry", {
            tbe::core::WallAssemblyLayer{.material_id = package_plaster, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::InteriorFinish},
            tbe::core::WallAssemblyLayer{.material_id = package_brick, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core},
            tbe::core::WallAssemblyLayer{.material_id = package_plaster, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::ExteriorFinish},
        });
        const auto package_floor_assembly = package_document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Floor", {
            tbe::core::WallAssemblyLayer{.material_id = package_tile, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
            tbe::core::WallAssemblyLayer{.material_id = package_concrete, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Core},
        });
        const auto package_ceiling_assembly = package_document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Ceiling, "Ceiling", {
            tbe::core::WallAssemblyLayer{.material_id = package_gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
        });
        const auto package_bottom = package_document.create_wall("Bottom", {{0.0, 0.0}, {12.0, 0.0}}, 0.24, 3.2, package_level);
        const auto package_top = package_document.create_wall("Top", {{12.0, 4.0}, {0.0, 4.0}}, 0.24, 3.2, package_level);
        const auto package_right = package_document.create_wall("Right", {{12.0, 0.0}, {12.0, 4.0}}, 0.24, 3.2, package_level);
        const auto package_left = package_document.create_wall("Left", {{0.0, 4.0}, {0.0, 0.0}}, 0.24, 3.2, package_level);
        const auto package_shared = package_document.create_wall("Shared", {{6.0, 0.0}, {6.0, 4.0}}, 0.24, 3.2, package_level);
        package_document.set_wall_type(package_bottom, package_wall_type);
        package_document.set_wall_type(package_top, package_wall_type);
        package_document.set_wall_type(package_right, package_wall_type);
        package_document.set_wall_type(package_left, package_wall_type);
        package_document.set_wall_type(package_shared, package_wall_type);
        package_document.auto_join_walls();
        package_document.create_door("Door", package_left, 1.5, 0.95, 2.1);
        package_document.create_window("Window", package_right, 1.8, 1.2, 1.1, 0.9);
        const auto package_rooms = package_document.detect_rooms();
        assert(package_rooms.size() == 2);
        package_document.generate_floor_systems_for_all_rooms(package_floor_assembly);
        package_document.generate_ceiling_systems_for_all_rooms(package_ceiling_assembly, 3.0);
        package_document.create_slab(package_level, {{0.0, 0.0}, {12.0, 0.0}, {12.0, 4.0}, {0.0, 4.0}}, 0.18, package_concrete);
        package_document.create_roof(package_level, {{-0.2, -0.2}, {12.2, -0.2}, {12.2, 4.2}, {-0.2, 4.2}}, tbe::core::RoofType::Flat, 0.16, package_concrete);
        package_document.create_column(package_level, {.x = 1.0, .y = 1.0}, 0.3, 0.4, 3.2, package_concrete);
        package_document.create_beam(package_level, {.x = 1.0, .y = 1.0}, {.x = 11.0, .y = 1.0}, 0.25, 0.4, package_concrete);
        package_document.create_stair(package_level, package_upper_level, {.x = 9.5, .y = 0.4}, {.x = 0.0, .y = 1.0}, 1.0, 3.2, 4.0, 18, 17, package_concrete);
        package_document.regenerate_dirty_geometry();
        const auto package_json = package_project.to_json();
        auto package_session_result = tbe::api::create_session("Package Building");
        assert(package_session_result.ok());
        auto package_session = std::move(*package_session_result.value);
        assert(package_session->load_project_json(package_json).ok());
        const auto package_render_scene = package_session->get_render_scene();
        assert(package_render_scene.ok());
        assert(package_render_scene.value.has_value());
        assert(package_render_scene.value->object_count == package_render_scene.value->objects.size());
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Door;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Window;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Slab;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Roof;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Column;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Beam;
        }));
        assert(std::any_of(package_render_scene.value->objects.begin(), package_render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Stair;
        }));
        assert(package_session->export_project_package(package_dir.string()).ok());
        auto package_import_session_result = tbe::api::create_session("Package Building Import");
        assert(package_import_session_result.ok());
        auto package_import_session = std::move(*package_import_session_result.value);
        assert(package_import_session->import_project_package(package_dir.string(), tbe::api::LoadMode::Repair).ok());
        const auto package_import_render_scene = package_import_session->get_render_scene();
        assert(package_import_render_scene.ok());
        assert(package_import_render_scene.value.has_value());
        assert(package_import_render_scene.value->object_count == package_import_render_scene.value->objects.size());
        const auto package_import_validation = package_import_session->get_validation_report();
        assert(package_import_validation.ok());
        assert(package_import_validation.value.has_value());
        assert(package_import_validation.value->error_count == 0);
        const auto package_import_schedule = package_import_session->generate_schedules();
        assert(package_import_schedule.ok());
        assert(package_import_schedule.value.has_value());
        assert(package_import_schedule.value->slab_rows == 1);
        assert(package_import_schedule.value->roof_rows == 1);
        assert(package_import_schedule.value->column_rows == 1);
        assert(package_import_schedule.value->beam_rows == 1);
        assert(package_import_schedule.value->stair_rows == 1);

        const auto broken_building_json = std::string(
            "{\"schema\":\"tbe.project.v1\",\"schema_version\":1,\"project_name\":\"Broken Building\","
            "\"document\":{\"schema\":\"tbe.document.v1\",\"name\":\"Broken Building Model\",\"next_id\":7,"
            "\"elements\":["
            "{\"id\":1,\"kind\":\"Level\",\"name\":\"Level 1\",\"revision\":1,\"level\":{\"name\":\"Level 1\",\"elevation\":0.0,\"default_wall_height\":3.2}},"
            "{\"id\":2,\"kind\":\"Slab\",\"name\":\"Bad Slab\",\"revision\":1,\"slab\":{\"level_id\":1,\"boundary_polygon\":[{\"x\":0.0,\"y\":0.0},{\"x\":0.0,\"y\":0.0},{\"x\":0.0,\"y\":0.0}],\"thickness\":0.0,\"material_id\":999,\"assembly_id\":999,\"elevation_offset\":0.0}},"
            "{\"id\":3,\"kind\":\"Roof\",\"name\":\"Bad Roof\",\"revision\":1,\"roof\":{\"level_id\":1,\"boundary_polygon\":[{\"x\":0.0,\"y\":0.0},{\"x\":0.0,\"y\":0.0},{\"x\":0.0,\"y\":0.0}],\"roof_type\":\"Flat\",\"thickness\":0.0,\"material_id\":999,\"assembly_id\":999}},"
            "{\"id\":4,\"kind\":\"Column\",\"name\":\"Bad Column\",\"revision\":1,\"column\":{\"level_id\":1,\"position\":{\"x\":1.0,\"y\":1.0},\"width\":-0.3,\"depth\":0.3,\"height\":3.2,\"material_id\":999}},"
            "{\"id\":5,\"kind\":\"Beam\",\"name\":\"Bad Beam\",\"revision\":1,\"beam\":{\"level_id\":1,\"start\":{\"x\":0.0,\"y\":0.0},\"end\":{\"x\":0.0,\"y\":0.0},\"width\":0.0,\"height\":0.4,\"material_id\":999}},"
            "{\"id\":6,\"kind\":\"Stair\",\"name\":\"Bad Stair\",\"revision\":1,\"stair\":{\"base_level_id\":1,\"top_level_id\":999,\"start\":{\"x\":0.0,\"y\":0.0},\"direction\":{\"x\":0.0,\"y\":1.0},\"width\":0.0,\"total_rise\":0.0,\"total_run\":0.0,\"riser_count\":0,\"tread_count\":0,\"material_id\":999}}]}}"
        );
        auto broken_session_result = tbe::api::create_session("Broken Building");
        assert(broken_session_result.ok());
        auto broken_session = std::move(*broken_session_result.value);
        assert(broken_session->load_project_json_with_mode(broken_building_json, tbe::api::LoadMode::Tolerant).ok());
        const auto broken_repair = broken_session->repair_current_project();
        assert(broken_repair.ok());
        assert(broken_repair.value.has_value());
        assert(broken_repair.value->repaired_count >= 5);
        const auto broken_validation = broken_session->get_validation_report();
        assert(broken_validation.ok());
        assert(broken_validation.value.has_value());
        assert(broken_validation.value->error_count == 0);
    }

    {
        auto session_result = tbe::api::create_session("API Stress Grid");
        assert(session_result.ok());
        auto session = std::move(*session_result.value);
        const auto level = session->create_level("Level 1", 0.0, 3.0);
        assert(level.ok());
        constexpr int grid_size = 10;
        for (int y = 0; y <= grid_size; ++y) {
            for (int x = 0; x < grid_size; ++x) {
                assert(session->create_wall("H", {.x = static_cast<double>(x), .y = static_cast<double>(y)}, {.x = static_cast<double>(x + 1), .y = static_cast<double>(y)}, 0.2, 3.0, level.value->value).ok());
            }
        }
        for (int x = 0; x <= grid_size; ++x) {
            for (int y = 0; y < grid_size; ++y) {
                assert(session->create_wall("V", {.x = static_cast<double>(x), .y = static_cast<double>(y)}, {.x = static_cast<double>(x), .y = static_cast<double>(y + 1)}, 0.2, 3.0, level.value->value).ok());
            }
        }
        assert(session->auto_join_walls().ok());
        const auto rooms = session->detect_rooms();
        assert(rooms.ok());
        assert(rooms.value.has_value());
        assert(rooms.value->size() == 100);
        const auto schedule = session->generate_schedules();
        assert(schedule.ok());
        assert(schedule.value.has_value());
        assert(schedule.value->wall_rows == 220);
        assert(schedule.value->room_rows == 100);
        const auto validation = session->get_validation_report();
        assert(validation.ok());
        assert(validation.value.has_value());
        assert(validation.value->error_count == 0);
        const auto render_scene = session->get_render_scene();
        assert(render_scene.ok());
        assert(render_scene.value.has_value());
        assert(render_scene.value->scene_version == 1);
        assert(render_scene.value->units == "meters");
        assert(render_scene.value->coordinate_system == "X/Y plan, Z up");
        assert(render_scene.value->object_count == render_scene.value->objects.size());
        assert(render_scene.value->vertex_count > 0);
        assert(render_scene.value->index_count > 0);
        assert(std::all_of(render_scene.value->objects.begin(), render_scene.value->objects.end(), [](const auto& object) {
            return std::isfinite(object.bounds.min.x) && std::isfinite(object.bounds.min.y) && std::isfinite(object.bounds.min.z) &&
                   std::isfinite(object.bounds.max.x) && std::isfinite(object.bounds.max.y) && std::isfinite(object.bounds.max.z) &&
                   object.bounds.min.x <= object.bounds.max.x &&
                   object.bounds.min.y <= object.bounds.max.y &&
                   object.bounds.min.z <= object.bounds.max.z;
        }));
        assert(std::any_of(render_scene.value->objects.begin(), render_scene.value->objects.end(), [](const auto& object) {
            return object.kind == tbe::api::ApiElementKind::Wall;
        }));
        const auto stats = session->spatial_index_stats();
        assert(stats.ok());
        assert(stats.value.has_value());
        assert(stats.value->bucket_count > 0);
        const auto saved = session->save_project_json();
        assert(saved.ok());
        auto reload_result = tbe::api::create_session("API Stress Grid Reload");
        assert(reload_result.ok());
        auto reload = std::move(*reload_result.value);
        assert(reload->load_project_json(*saved.value).ok());
        const auto reload_validation = reload->get_validation_report();
        assert(reload_validation.ok());
        assert(reload_validation.value.has_value());
        assert(reload_validation.value->error_count == 0);
    }

    {
        auto model = tbe::core::create_stress_model(
            "API Performance Stress",
            tbe::core::StressModelOptions{
                .grid_size = 10,
                .include_openings = true,
                .include_building_elements = true,
            }
        );
        auto& document = model.project.active_document();
        document.auto_join_walls();
        model.room_ids = document.detect_rooms();
        tbe::core::add_building_element_stress_details(model);
        document.regenerate_dirty_geometry();
        const auto validation = document.validate_document();
        assert(validation.error_count() == 0);
        assert(model.room_ids.size() == 100);
        assert(std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) { return element.wall() != nullptr; }) > 0);
        assert(std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) { return element.door() != nullptr || element.window() != nullptr; }) > 0);
        assert(!document.generate_wall_schedule().empty());
        assert(!document.generate_room_schedule().empty());
        assert(!document.generate_floor_finish_schedule().empty());
        assert(!document.generate_ceiling_schedule().empty());
        assert(!document.generate_material_takeoff().empty());

        auto session_result = tbe::api::create_session("API Performance Stress");
        assert(session_result.ok());
        auto session = std::move(*session_result.value);
        const auto json = model.project.to_json();
        assert(session->load_project_json_with_mode(json, tbe::api::LoadMode::Repair).ok());
        assert(session->rebuild_spatial_index().ok());
        const auto stats = session->spatial_index_stats();
        assert(stats.ok());
        assert(stats.value.has_value());
        assert(stats.value->bucket_count > 0);
        const auto rect_hits = session->query_rect({.value = model.base_level_id}, {.min_x = 0.0, .min_y = 0.0, .max_x = 2.0, .max_y = 2.0});
        assert(rect_hits.ok());
        assert(rect_hits.value.has_value());
        assert(!rect_hits.value->empty());
        assert(session->hit_test_point({.level_id = {.value = model.base_level_id}, .point = {.x = 0.5, .y = 0.5}, .tolerance_meters = 0.2}).ok());
        assert(session->save_project_json().ok());

        const auto shared_wall_id = model.shared_wall_ids.empty() ? 0 : model.shared_wall_ids.front();
        if (shared_wall_id != 0) {
            const auto takeoff_signature = [](const auto& rows) {
                std::vector<std::string> signature;
                signature.reserve(rows.size());
                for (const auto& row : rows) {
                    signature.push_back(
                        std::to_string(row.material_id.value) + "|" +
                        std::to_string(static_cast<int>(row.quantity_type)) + "|" +
                        std::to_string(static_cast<long long>(std::llround(row.quantity * 1'000'000.0)))
                    );
                }
                std::sort(signature.begin(), signature.end());
                return signature;
            };
            const auto version_before = session->spatial_index_version();
            assert(version_before.ok());
            assert(version_before.value.has_value());
            const auto* shared_wall_element = model.project.active_document().find_ptr(shared_wall_id);
            assert(shared_wall_element != nullptr);
            const auto* shared_wall = shared_wall_element->wall();
            assert(shared_wall != nullptr);
            assert(session->set_wall_axis(
                shared_wall_id,
                {.x = shared_wall->axis.start.x + 1.0e-6, .y = shared_wall->axis.start.y + 1.0e-6},
                {.x = shared_wall->axis.end.x + 1.0e-6, .y = shared_wall->axis.end.y + 1.0e-6}
            ).ok());
            const auto version_after = session->spatial_index_version();
            assert(version_after.ok());
            assert(version_after.value.has_value());
            assert(*version_after.value >= *version_before.value);
            const auto cached_schedule = session->get_cached_room_schedule();
            assert(cached_schedule.freshness != tbe::api::FreshnessState::Clean);
            assert(session->recompute_dirty().ok());
            const auto dirty_summary = session->get_freshness_summary();
            assert(dirty_summary.ok());
            assert(dirty_summary.value.has_value());
            assert(dirty_summary.value->room_metrics == tbe::api::FreshnessState::Clean);
            assert(session->recompute_all_final().ok());
            const auto final_summary = session->get_freshness_summary();
            assert(final_summary.ok());
            assert(final_summary.value.has_value());
            assert(final_summary.value->room_metrics == tbe::api::FreshnessState::Clean);
            assert(final_summary.value->schedules == tbe::api::FreshnessState::Clean);
            const auto final_room_schedule = session->generate_room_schedule();
            assert(final_room_schedule.ok());
            assert(final_room_schedule.freshness == tbe::api::FreshnessState::Clean);
            const auto final_takeoff = session->generate_material_takeoff_summary();
            assert(final_takeoff.ok());
            assert(final_takeoff.value.has_value());
            assert(!final_takeoff.value->empty());
            const auto final_takeoff_rows = final_takeoff.value->size();
            assert(final_takeoff_rows > 0);
            const auto final_takeoff_signature = takeoff_signature(*final_takeoff.value);
            assert(session->recompute_all_final().ok());
            const auto repeated_final_takeoff = session->generate_material_takeoff_summary();
            assert(repeated_final_takeoff.ok());
            assert(repeated_final_takeoff.value.has_value());
            assert(takeoff_signature(*repeated_final_takeoff.value) == final_takeoff_signature);
        const auto package_dir = std::filesystem::temp_directory_path() / "tbe_api_perf_package";
        std::filesystem::remove_all(package_dir);
        assert(session->export_project_package(package_dir.string()).ok());
        assert(std::filesystem::exists(package_dir / "exports" / "render_scene.json"));
        auto import_session_result = tbe::api::create_session("API Performance Stress Import");
        assert(import_session_result.ok());
        auto import_session = std::move(*import_session_result.value);
        const auto import_result = import_session->import_project_package(package_dir.string(), tbe::api::LoadMode::Repair);
        if (import_result.ok()) {
                const auto import_validation = import_session->get_validation_report();
                assert(import_validation.ok());
                assert(import_validation.value.has_value());
                assert(import_validation.value->error_count == 0);
            }
        }
    }

    {
        for (const auto grid_size : {2, 5, 10}) {
            auto model = tbe::core::create_stress_model(
                "API Stress Roundtrip",
                tbe::core::StressModelOptions{
                    .grid_size = grid_size,
                    .include_openings = true,
                    .include_building_elements = true,
                }
            );
            auto& document = model.project.active_document();
            document.auto_join_walls();
            model.room_ids = document.detect_rooms();
            tbe::core::add_building_element_stress_details(model);
            document.regenerate_dirty_geometry();

            const auto json = model.project.to_json();
            auto parsed_project = tbe::core::Project::from_json(json);
            auto& parsed_document = parsed_project.active_document();
            const auto parsed_validation = parsed_document.validate_document();
            assert(parsed_validation.error_count() == 0);
            assert(parsed_document.elements().size() == document.elements().size());
            assert(parsed_document.detect_rooms().size() == model.room_ids.size());

            auto api_session_result = tbe::api::create_session("API Stress Roundtrip");
            assert(api_session_result.ok());
            auto api_session = std::move(*api_session_result.value);
            assert(api_session->load_project_json(json).ok());
            const auto api_validation = api_session->get_validation_report();
            assert(api_validation.ok());
            assert(api_validation.value.has_value());
            assert(api_validation.value->error_count == 0);

            const auto package_dir = std::filesystem::temp_directory_path() / ("tbe_api_stress_roundtrip_" + std::to_string(grid_size));
            std::filesystem::remove_all(package_dir);
            assert(api_session->export_project_package(package_dir.string()).ok());
            assert(std::filesystem::exists(package_dir / "exports" / "render_scene.json"));
            auto package_import_result = tbe::api::create_session("API Stress Roundtrip Import");
            assert(package_import_result.ok());
            auto package_import_session = std::move(*package_import_result.value);
            assert(package_import_session->import_project_package(package_dir.string(), tbe::api::LoadMode::Repair).ok());
            const auto package_validation = package_import_session->get_validation_report();
            assert(package_validation.ok());
            assert(package_validation.value.has_value());
            assert(package_validation.value->error_count == 0);
        }
    }

    TbeEngineHandle* handle = tbe_engine_create();
    assert(handle != nullptr);

    uint64_t wall1 = 0;
    uint64_t wall2 = 0;
    uint64_t wall3 = 0;
    uint64_t wall4 = 0;
    assert(tbe_create_wall(handle, "A", 0, TbeVec2{0.0, 0.0}, TbeVec2{4.0, 0.0}, 0.2, 3.0, &wall1) == TBE_API_OK);
    assert(tbe_create_wall(handle, "B", 0, TbeVec2{4.0, 0.0}, TbeVec2{4.0, 3.0}, 0.2, 3.0, &wall2) == TBE_API_OK);
    assert(tbe_create_wall(handle, "C", 0, TbeVec2{4.0, 3.0}, TbeVec2{0.0, 3.0}, 0.2, 3.0, &wall3) == TBE_API_OK);
    assert(tbe_create_wall(handle, "D", 0, TbeVec2{0.0, 3.0}, TbeVec2{0.0, 0.0}, 0.2, 3.0, &wall4) == TBE_API_OK);

    uint64_t room_count = 0;
    assert(tbe_detect_rooms(handle, &room_count) == TBE_API_OK);
    assert(room_count == 1);

    TbeScheduleSummary summary{};
    assert(tbe_generate_schedules(handle, &summary) == TBE_API_OK);
    assert(summary.wall_rows == 4);

    TbeValidationSummary validation{};
    const auto validation_status = tbe_validate(handle, &validation);
    assert(validation_status == TBE_API_OK);
    assert(validation.error_count == 0);

    assert(tbe_rebuild_spatial_index(handle) == TBE_API_OK);
    TbeSpatialIndexStats spatial_stats{};
    assert(tbe_spatial_index_stats(handle, &spatial_stats) == TBE_API_OK);
    assert(spatial_stats.bucket_count >= 1);
    TbeHitTestResult hit_result{};
    assert(tbe_hit_test_point(handle, 0, TbeVec2{0.0, 2.0}, 0.2, &hit_result) == TBE_API_OK);
    assert(hit_result.candidate_count >= 1);
    assert(hit_result.element_id == wall4);

    TbeSnapResult snap_result{};
    assert(tbe_best_snap(handle, 0, TbeVec2{0.05, 0.05}, 0.2, &snap_result) == TBE_API_OK);
    assert(snap_result.source_element_id != 0);

    TbeWallFreeIntervalsResult intervals_result{};
    assert(tbe_compute_wall_free_intervals(handle, wall1, 1.0, 0.1, &intervals_result) == TBE_API_OK);
    assert(intervals_result.interval_count >= 1);

    TbeWallHostPlacement host_result{};
    assert(tbe_find_wall_host_at_point(handle, 0, TbeVec2{0.03, 2.4}, 0.2, 0.9, 0.05, &host_result) == TBE_API_OK);
    assert(host_result.wall_id == wall4);
    assert(host_result.valid == 1);
    tbe_free_memory(intervals_result.intervals);
    tbe_free_memory(host_result.intervals);

    char* json = nullptr;
    assert(tbe_project_save_json(handle, &json) == TBE_API_OK);
    assert(json != nullptr);
    assert(std::string(json).find("\"project_name\"") != std::string::npos);

    int c_schema_version = 0;
    assert(tbe_get_schema_version(handle, &c_schema_version) == TBE_API_OK);
    assert(c_schema_version == 1);

    const char* c_legacy_json = "{\"schema\":\"tbe.project.v1\",\"project_name\":\"Legacy C\",\"document\":{\"schema\":\"tbe.document.v1\",\"name\":\"Legacy C Model\",\"next_id\":1,\"elements\":[]}}";
    int detected_schema_version = -1;
    assert(tbe_detect_schema_version_from_json(handle, c_legacy_json, &detected_schema_version) == TBE_API_OK);
    assert(detected_schema_version == 0);
    char* migrated_json = nullptr;
    assert(tbe_migrate_project_json(handle, c_legacy_json, 0, 1, &migrated_json) == TBE_API_OK);
    assert(std::string(migrated_json).find("\"schema_version\":1") != std::string::npos);
    tbe_free_string(migrated_json);

    TbeRepairSummary repair_summary{};
    assert(tbe_repair_current_project(handle, &repair_summary) == TBE_API_OK);

    tbe_free_string(json);
    tbe_free_string(nullptr);
    tbe_free_memory(nullptr);

    tbe_engine_destroy(handle);

    for (int iteration = 0; iteration < 10; ++iteration) {
        TbeEngineHandle* loop_handle = tbe_engine_create();
        assert(loop_handle != nullptr);
        uint64_t loop_wall = 0;
        assert(tbe_create_wall(loop_handle, "LoopWall", 0, TbeVec2{0.0, 0.0}, TbeVec2{4.0, 0.0}, 0.2, 3.0, &loop_wall) == TBE_API_OK);

        char* loop_engine_version = nullptr;
        char* loop_api_version = nullptr;
        char* loop_core_version = nullptr;
        assert(tbe_get_engine_version(loop_handle, &loop_engine_version) == TBE_API_OK);
        assert(tbe_get_api_version(loop_handle, &loop_api_version) == TBE_API_OK);
        assert(tbe_get_core_version(loop_handle, &loop_core_version) == TBE_API_OK);
        assert(std::string(loop_engine_version).find("0.1.0") != std::string::npos);
        tbe_free_string(loop_engine_version);
        tbe_free_string(loop_api_version);
        tbe_free_string(loop_core_version);

        for (int inner = 0; inner < 3; ++inner) {
            char* loop_json = nullptr;
            assert(tbe_project_save_json(loop_handle, &loop_json) == TBE_API_OK);
            assert(loop_json != nullptr);
            assert(tbe_project_load_json(loop_handle, loop_json) == TBE_API_OK);
            tbe_free_string(loop_json);

            TbeHitTestResult loop_hit{};
            TbeSnapResult loop_snap{};
            TbeWallFreeIntervalsResult loop_intervals{};
            assert(tbe_hit_test_point(loop_handle, 0, TbeVec2{0.0, 0.0}, 0.2, &loop_hit) == TBE_API_OK);
            assert(tbe_best_snap(loop_handle, 0, TbeVec2{0.1, 0.0}, 0.2, &loop_snap) == TBE_API_OK);
            assert(tbe_compute_wall_free_intervals(loop_handle, loop_wall, 0.5, 0.05, &loop_intervals) == TBE_API_OK);
            tbe_free_memory(loop_intervals.intervals);
        }

    const auto package_dir = std::filesystem::temp_directory_path() / ("tbe_capi_loop_package_" + std::to_string(iteration));
        std::filesystem::remove_all(package_dir);
        assert(tbe_export_project_package(loop_handle, package_dir.string().c_str()) == TBE_API_OK);
        const auto render_scene_path = package_dir / "exports" / "render_scene.json";
        assert(std::filesystem::exists(render_scene_path));
        assert(std::filesystem::file_size(render_scene_path) > 0);
        const auto render_scene_only = package_dir / "render_scene.json";
        std::filesystem::remove(render_scene_only);
        assert(tbe_export_render_scene_json(loop_handle, render_scene_only.string().c_str()) == TBE_API_OK);
        assert(std::filesystem::exists(render_scene_only));
        assert(tbe_import_project_package(loop_handle, package_dir.string().c_str(), static_cast<int>(tbe::api::LoadMode::Repair)) == TBE_API_OK);

        const auto invalid_status = tbe_create_wall(loop_handle, nullptr, 0, TbeVec2{0.0, 0.0}, TbeVec2{1.0, 0.0}, 0.2, 3.0, &loop_wall);
        assert(invalid_status == TBE_API_INVALID_ARGUMENT);
        assert(std::string(tbe_get_last_error(loop_handle)).find("null") != std::string::npos || !std::string(tbe_get_last_error(loop_handle)).empty());

        char* clear_error_probe = nullptr;
        assert(tbe_get_engine_version(loop_handle, &clear_error_probe) == TBE_API_OK);
        assert(std::string(tbe_get_last_error(loop_handle)).empty());
        tbe_free_string(clear_error_probe);

        tbe_engine_destroy(loop_handle);
    }

    return 0;
}
