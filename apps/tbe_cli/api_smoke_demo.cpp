#include "tbe/api/EngineApi.hpp"

#include <chrono>
#include <filesystem>
#include <iostream>

namespace {

void run_stress_demo() {
    using clock = std::chrono::steady_clock;
    auto session_result = tbe::api::create_session("Stress Demo");
    if (!session_result.ok() || !session_result.value.has_value()) {
        std::cerr << "failed to create stress session\n";
        return;
    }
    auto session = std::move(*session_result.value);
    const auto level = session->create_level("Level 1", 0.0, 3.0);
    if (!level.ok() || !level.value.has_value()) {
        std::cerr << "failed to create stress level\n";
        return;
    }
    const auto level_id = level.value->value;
    constexpr int grid_size = 10;

    for (int y = 0; y <= grid_size; ++y) {
        for (int x = 0; x < grid_size; ++x) {
            session->create_wall("H", {.x = static_cast<double>(x), .y = static_cast<double>(y)}, {.x = static_cast<double>(x + 1), .y = static_cast<double>(y)}, 0.2, 3.0, level_id);
        }
    }
    for (int x = 0; x <= grid_size; ++x) {
        for (int y = 0; y < grid_size; ++y) {
            session->create_wall("V", {.x = static_cast<double>(x), .y = static_cast<double>(y)}, {.x = static_cast<double>(x), .y = static_cast<double>(y + 1)}, 0.2, 3.0, level_id);
        }
    }

    session->auto_join_walls();
    session->detect_rooms();
    session->rebuild_spatial_index();
    const auto before_save = clock::now();
    const auto saved = session->save_project_json();
    const auto after_save = clock::now();
    auto reload_result = tbe::api::create_session("Stress Reload");
    auto reload = std::move(*reload_result.value);
    const auto before_load = clock::now();
    reload->load_project_json(*saved.value);
    const auto after_load = clock::now();
    const auto before_validate = clock::now();
    const auto validation = reload->get_validation_report();
    const auto after_validate = clock::now();
    const auto schedule = session->generate_schedules();
    const auto takeoff = session->get_material_takeoff_summary();
    const auto spatial_stats = session->spatial_index_stats();

    std::cout << "Stress mode\n";
    std::cout << "Wall count: " << schedule.value->wall_rows << '\n';
    std::cout << "Room count: " << schedule.value->room_rows << '\n';
    std::cout << "Material takeoff rows: " << takeoff.value->size() << '\n';
    std::cout << "Spatial buckets: " << spatial_stats.value->bucket_count << '\n';
    std::cout << "Spatial avg occupancy: " << spatial_stats.value->average_bucket_occupancy << '\n';
    std::cout << "Save ms: " << std::chrono::duration_cast<std::chrono::milliseconds>(after_save - before_save).count() << '\n';
    std::cout << "Load ms: " << std::chrono::duration_cast<std::chrono::milliseconds>(after_load - before_load).count() << '\n';
    std::cout << "Validation ms: " << std::chrono::duration_cast<std::chrono::milliseconds>(after_validate - before_validate).count() << '\n';
    std::cout << "Validation errors: " << validation.value->error_count << '\n';
}

} // namespace

int main(int argc, char** argv) {
    if (argc > 1 && std::string_view(argv[1]) == "--stress") {
        run_stress_demo();
        return 0;
    }

    auto session_result = tbe::api::create_session("API Smoke");
    if (!session_result.ok() || !session_result.value.has_value()) {
        std::cerr << "Failed to create API session\n";
        return 1;
    }

    auto session = std::move(*session_result.value);
    const auto level = session->create_level("Level 1", 0.0, 3.0);
    if (!level.ok() || !level.value.has_value()) {
        std::cerr << level.message << '\n';
        return 1;
    }

    const auto level_id = level.value->value;
    const auto bottom_wall = session->create_wall("Bottom", {.x = 0.0, .y = 0.0}, {.x = 6.0, .y = 0.0}, 0.2, 3.0, level_id);
    const auto right_wall = session->create_wall("Right", {.x = 6.0, .y = 0.0}, {.x = 6.0, .y = 4.0}, 0.2, 3.0, level_id);
    session->create_wall("Top", {.x = 6.0, .y = 4.0}, {.x = 0.0, .y = 4.0}, 0.2, 3.0, level_id);
    session->create_wall("Left", {.x = 0.0, .y = 4.0}, {.x = 0.0, .y = 0.0}, 0.2, 3.0, level_id);
    session->create_door("Door", bottom_wall.value->value, 1.2, 0.9, 2.1);
    session->create_window("Window", right_wall.value->value, 1.8, 1.2, 1.2, 1.0);
    session->auto_join_walls();
    session->detect_rooms();
    session->rebuild_spatial_index();

    const auto schedule = session->generate_schedules();
    const auto validation = session->get_validation_report();
    const auto saved = session->save_project_json();
    if (!schedule.ok() || !validation.ok() || !saved.ok() || !saved.value.has_value()) {
        std::cerr << "API smoke demo failed\n";
        return 1;
    }

    auto reloaded = tbe::api::create_session("Reloaded");
    if (!reloaded.ok() || !reloaded.value.has_value()) {
        return 1;
    }
    auto reload_session = std::move(*reloaded.value);
    if (!reload_session->load_project_json(*saved.value).ok()) {
        return 1;
    }
    reload_session->rebuild_spatial_index();
    const auto reload_validation = reload_session->get_validation_report();
    if (!reload_validation.ok()) {
        return 1;
    }
    const auto schema_version = session->get_schema_version();
    const auto engine_version = session->get_engine_version();
    const auto core_version = session->get_core_version();
    const auto api_version = session->get_api_version();
    const auto migration_report = session->get_last_migration_report();
    const auto repair_report = session->get_last_repair_report();
    const auto wall_hit = session->hit_test_point({.level_id = {.value = level_id}, .point = {.x = 0.0, .y = 2.0}, .tolerance_meters = 0.2});
    const auto snap = session->best_snap({.value = level_id}, {.x = 0.05, .y = 0.05}, 0.2);
    const auto spatial_stats = session->spatial_index_stats();
    const auto intervals = session->compute_wall_free_intervals(bottom_wall.value->value, 1.0, 0.1);
    const auto host = session->find_wall_host_at_point({.value = level_id}, {.x = 1.2, .y = 0.03}, 0.2, 1.0, 0.1);
    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_api_spatial_demo";
    std::filesystem::create_directories(export_dir);
    const auto svg_path = export_dir / "api_spatial_demo.svg";
    const auto package_dir = export_dir / "package";
    session->export_svg(svg_path.string());
    session->export_project_package(package_dir.string());

    std::cout << "Project: " << *session->current_project().value << '\n';
    if (engine_version.ok() && engine_version.value.has_value()) {
        std::cout << "Engine version: " << *engine_version.value << '\n';
    }
    if (core_version.ok() && core_version.value.has_value()) {
        std::cout << "Core version: " << *core_version.value << '\n';
    }
    if (api_version.ok() && api_version.value.has_value()) {
        std::cout << "API version: " << *api_version.value << '\n';
    }
    if (schema_version.ok() && schema_version.value.has_value()) {
        std::cout << "Schema version: " << *schema_version.value << '\n';
    }
    std::cout << "Wall rows: " << schedule.value->wall_rows << '\n';
    std::cout << "Room rows: " << schedule.value->room_rows << '\n';
    std::cout << "Spatial index version: " << *session->spatial_index_version().value << '\n';
    if (spatial_stats.ok() && spatial_stats.value.has_value()) {
        std::cout << "Spatial stats: elements=" << spatial_stats.value->element_bounds_count
                  << " buckets=" << spatial_stats.value->bucket_count
                  << " avg_occ=" << spatial_stats.value->average_bucket_occupancy
                  << " max_occ=" << spatial_stats.value->max_bucket_occupancy << '\n';
    }
    std::cout << "Hit candidates at left wall: " << (wall_hit.value.has_value() ? wall_hit.value->size() : 0) << '\n';
    if (wall_hit.ok() && wall_hit.value.has_value()) {
        for (const auto& candidate : *wall_hit.value) {
            std::cout << "  hit element=" << candidate.element_id.value
                      << " kind=" << static_cast<int>(candidate.element_kind)
                      << " hit=" << static_cast<int>(candidate.hit_kind)
                      << " dist=" << candidate.distance_meters << '\n';
        }
    }
    if (snap.ok() && snap.value.has_value()) {
        std::cout << "Best snap: (" << snap.value->point.x << ", " << snap.value->point.y
                  << ") type=" << static_cast<int>(snap.value->type) << '\n';
    }
    if (intervals.ok() && intervals.value.has_value()) {
        std::cout << "Free intervals on bottom wall: " << intervals.value->size() << '\n';
        for (const auto& interval : *intervals.value) {
            std::cout << "  [" << interval.start_offset_meters << ", " << interval.end_offset_meters << "]\n";
        }
    }
    if (host.ok() && host.value.has_value()) {
        std::cout << "Wall host id: " << host.value->wall_id.value
                  << " requested=" << host.value->requested_offset_meters
                  << " adjusted=" << host.value->adjusted_valid_offset_meters
                  << " valid=" << (host.value->valid ? "yes" : "no") << '\n';
    }
    if (migration_report.ok() && migration_report.value.has_value()) {
        std::cout << "Migration report: migrated=" << migration_report.value->migrated_count
                  << " warnings=" << migration_report.value->warning_count
                  << " errors=" << migration_report.value->error_count << '\n';
    }
    if (repair_report.ok() && repair_report.value.has_value()) {
        std::cout << "Repair report: repaired=" << repair_report.value->repaired_count
                  << " warnings=" << repair_report.value->warning_count
                  << " errors=" << repair_report.value->error_count << '\n';
    }
    std::cout << "Validation errors: " << validation.value->error_count << '\n';
    std::cout << "Reload validation errors: " << reload_validation.value->error_count << '\n';
    std::cout << "SVG export: " << svg_path << '\n';
    std::cout << "Package export: " << package_dir << '\n';

    return validation.value->error_count == 0 && reload_validation.value->error_count == 0 ? 0 : 1;
}
