#include "tbe/api/EngineApi.hpp"
#include "tbe/core/Command.hpp"
#include "tbe/core/GeometryService.hpp"
#include "tbe/core/Project.hpp"
#include "tbe/core/StressModel.hpp"

#include <chrono>
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <numeric>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

std::vector<double> sorted_room_areas(const tbe::core::Document& document, const std::vector<tbe::core::ElementId>& room_ids) {
    std::vector<double> areas;
    areas.reserve(room_ids.size());
    for (const auto room_id : room_ids) {
        const auto* room = document.find_ptr(room_id)->room();
        if (room != nullptr) {
            areas.push_back(room->centerline_area_square_meters);
        }
    }
    std::sort(areas.begin(), areas.end());
    return areas;
}

std::vector<double> sorted_room_interior_areas(const tbe::core::Document& document, const std::vector<tbe::core::ElementId>& room_ids) {
    std::vector<double> areas;
    areas.reserve(room_ids.size());
    for (const auto room_id : room_ids) {
        const auto* room = document.find_ptr(room_id)->room();
        if (room != nullptr) {
            areas.push_back(room->interior_area_square_meters);
        }
    }
    std::sort(areas.begin(), areas.end());
    return areas;
}

void print_areas(const std::string& label, const std::vector<double>& areas) {
    std::cout << label;
    for (std::size_t index = 0; index < areas.size(); ++index) {
        if (index != 0) {
            std::cout << ", ";
        }
        std::cout << areas[index];
    }
    std::cout << '\n';
}

void print_ids(const std::string& label, const std::vector<tbe::core::ElementId>& ids) {
    std::cout << label;
    for (std::size_t index = 0; index < ids.size(); ++index) {
        if (index != 0) {
            std::cout << ", ";
        }
        std::cout << ids[index];
    }
    std::cout << '\n';
}

template <typename Fn>
double measure_ms(Fn&& fn) {
    const auto start = std::chrono::steady_clock::now();
    std::forward<Fn>(fn)();
    const auto end = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::milli>(end - start).count();
}

int run_torture_wall_room() {
    using namespace tbe::core;

    Project project{"Wall Room Torture"};
    auto& document = project.active_document();
    CommandProcessor processor;

    CreateLevelCommand level{"Level 1", 0.0, 3.0};
    processor.execute(document, level);
    const auto level_id = level.created_id();

    CreateWallCommand bottom{"Bottom", Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 12.0, .y = 0.0}}, 0.2, 3.0, level_id};
    CreateWallCommand top{"Top", Line2{.start = {.x = 12.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}}, 0.2, 3.0, level_id};
    CreateWallCommand right{"Right", Line2{.start = {.x = 12.0, .y = 0.0}, .end = {.x = 12.0, .y = 4.0}}, 0.2, 3.0, level_id};
    CreateWallCommand left{"Left", Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}}, 0.2, 3.0, level_id};
    CreateWallCommand shared_a{"Shared A", Line2{.start = {.x = 4.0, .y = 0.0}, .end = {.x = 4.0, .y = 4.0}}, 0.2, 3.0, level_id};
    CreateWallCommand shared_b{"Shared B", Line2{.start = {.x = 8.0, .y = 0.0}, .end = {.x = 8.0, .y = 4.0}}, 0.2, 3.0, level_id};
    CreateWallCommand temp_delete{"Temp Delete", Line2{.start = {.x = 14.0, .y = 0.0}, .end = {.x = 15.0, .y = 0.0}}, 0.2, 3.0, level_id};
    CreateWallCommand temp_split{"Temp Split", Line2{.start = {.x = 14.0, .y = 1.0}, .end = {.x = 18.0, .y = 1.0}}, 0.2, 3.0, level_id};

    processor.execute(document, bottom);
    processor.execute(document, top);
    processor.execute(document, right);
    processor.execute(document, left);
    processor.execute(document, shared_a);
    processor.execute(document, shared_b);
    processor.execute(document, temp_delete);
    processor.execute(document, temp_split);

    AutoJoinWallsCommand join;
    processor.execute(document, join);

    InsertDoorCommand door_left{"Door Left", left.created_id(), 1.2, 0.9, 2.1};
    InsertWindowCommand window_right{"Window Right", right.created_id(), 1.8, 1.2, 1.0, 0.9};
    InsertDoorCommand door_shared{"Door Shared", shared_a.created_id(), 1.6, 0.9, 2.1};
    InsertWindowCommand window_shared{"Window Shared", shared_b.created_id(), 2.1, 1.0, 1.0, 0.9};
    processor.execute(document, door_left);
    processor.execute(document, window_right);
    processor.execute(document, door_shared);
    processor.execute(document, window_shared);

    MoveHostedOpeningCommand move_door{door_shared.created_id(), 2.0};
    ResizeWindowCommand resize_window{window_shared.created_id(), 1.1, 1.0, 0.9};
    processor.execute(document, move_door);
    processor.execute(document, resize_window);
    const auto* moved_host_wall = document.find_ptr(shared_a.created_id())->wall();
    const bool host_wall_dirty_after_opening_edit = moved_host_wall != nullptr && moved_host_wall->geometry.dirty;

    SplitWallCommand split_temp{temp_split.created_id(), 2.0};
    processor.execute(document, split_temp);
    DeleteElementCommand delete_temp{temp_delete.created_id()};
    processor.execute(document, delete_temp);

    DetectRoomsCommand detect;
    processor.execute(document, detect);
    document.regenerate_dirty_geometry();
    document.generate_floor_systems_for_all_rooms(
        document.create_layered_assembly(
            LayeredAssemblyKind::Floor,
            "Torture Floor",
            {
                WallAssemblyLayer{.material_id = document.create_material("Torture Tile", MaterialCategory::Finish, 2100.0, 55.0), .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
            }
        )
    );
    const auto validation_before = document.validate_document();
    const auto wall_schedule_before = document.generate_wall_schedule();
    const auto opening_schedule_before = document.generate_opening_schedule();
    const auto room_schedule_before = document.generate_room_schedule();
    const auto takeoff_before = document.generate_material_takeoff();

    const auto room_ids = document.detect_rooms();
    const auto room_ids_repeat = document.detect_rooms();
    document.mark_rooms_dirty_for_wall(shared_a.created_id());
    document.mark_rooms_dirty_for_wall(shared_b.created_id());
    const auto dirty_rooms = document.recompute_dirty_rooms();
    const auto dirty_room_areas = sorted_room_areas(document, dirty_rooms);
    const auto full_room_areas = sorted_room_areas(document, document.recompute_all_rooms());
    const bool incremental_equals_full = dirty_room_areas == full_room_areas;

    const auto json = project.to_json();
    auto api_session_result = tbe::api::create_session("Wall Room Torture Repair");
    if (!api_session_result.ok() || !api_session_result.value.has_value()) {
        std::cerr << "Failed to create API session for torture repair\n";
        return 1;
    }
    auto api_session = std::move(*api_session_result.value);
    const auto load_result = api_session->load_project_json_with_mode(json, tbe::api::LoadMode::Repair);
    const auto repair_report = api_session->repair_current_project();
    const auto api_validation = api_session->get_validation_report();
    const auto api_schedules = api_session->generate_schedules();
    const auto api_takeoff = api_session->generate_material_takeoff_summary();
    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_torture_bridge";
    std::filesystem::create_directories(export_dir);
    const auto export_result = api_session->export_project_package(export_dir.string());

    std::cout << "Torture mode: wall-room\n";
    std::cout << "Project: " << project.name() << '\n';
    std::cout << "Elements: " << document.elements().size() << '\n';
    const auto wall_count = std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) {
        return element.wall() != nullptr;
    });
    std::size_t join_count = 0;
    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall(); wall != nullptr) {
            join_count += wall->joins.size();
        }
    }
    const auto opening_count = std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) {
        return element.door() != nullptr || element.window() != nullptr;
    });
    std::cout << "Wall count: " << wall_count << '\n';
    std::cout << "Join count: " << join_count << '\n';
    std::cout << "Opening count: " << opening_count << '\n';
    std::cout << "Room count: " << room_ids.size() << '\n';
    print_ids("Room ids: ", room_ids);
    std::cout << "Repeat room count: " << room_ids_repeat.size() << '\n';
    std::cout << "Room ids stable: " << (room_ids == room_ids_repeat ? "yes" : "no") << '\n';
    std::cout << "Incremental equals full recompute: " << (incremental_equals_full ? "yes" : "no") << '\n';
    std::cout << "Host wall dirty after opening edit: " << (host_wall_dirty_after_opening_edit ? "yes" : "no") << '\n';
    std::cout << "Wall schedule rows: " << wall_schedule_before.size() << '\n';
    std::cout << "Opening schedule rows: " << opening_schedule_before.size() << '\n';
    std::cout << "Room schedule rows: " << room_schedule_before.size() << '\n';
    std::cout << "Takeoff rows: " << takeoff_before.size() << '\n';
    std::cout << "Validation issues: " << validation_before.issue_count() << '\n';
    std::cout << "Validation warnings: " << validation_before.warning_count() << '\n';
    std::cout << "Validation errors: " << validation_before.error_count() << '\n';
    std::cout << "API repair load: " << (load_result.ok() ? "ok" : "failed") << '\n';
    std::cout << "API repair report: " << (repair_report.ok() ? "ok" : "failed") << '\n';
    if (api_validation.ok() && api_validation.value.has_value()) {
        std::cout << "API validation errors: " << api_validation.value->error_count << '\n';
        std::cout << "API validation warnings: " << api_validation.value->warning_count << '\n';
    } else {
        std::cout << "API validation errors: -1\n";
        std::cout << "API validation warnings: -1\n";
    }
    if (api_schedules.ok() && api_schedules.value.has_value()) {
        std::cout << "API wall rows: " << api_schedules.value->wall_rows << '\n';
        std::cout << "API room rows: " << api_schedules.value->room_rows << '\n';
    }
    if (api_takeoff.ok() && api_takeoff.value.has_value()) {
        std::cout << "API takeoff rows: " << api_takeoff.value->size() << '\n';
    }
    std::cout << "API export dir: " << export_dir << '\n';
    std::cout << "API export: " << (export_result.ok() ? "ok" : "failed") << '\n';
    return 0;
}

int run_torture_building_elements() {
    using namespace tbe::core;

    Project project{"Building Elements Torture"};
    auto& document = project.active_document();
    CommandProcessor processor;

    const auto level = document.create_level("Level 1", 0.0, 3.2);
    const auto upper_level = document.create_level("Level 2", 3.2, 3.2);

    const auto brick = document.create_material("Brick", MaterialCategory::Structural, 1800.0, 120.0);
    const auto plaster = document.create_material("Plaster", MaterialCategory::Finish, 950.0, 40.0);
    const auto concrete = document.create_material("Concrete", MaterialCategory::Structural, 2400.0, 110.0);
    const auto tile = document.create_material("Tile", MaterialCategory::Finish, 2100.0, 55.0);
    const auto gypsum = document.create_material("Gypsum", MaterialCategory::Finish, 850.0, 28.0);
    const auto wall_type = document.create_wall_type("Masonry", {
        WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = WallLayerFunction::InteriorFinish},
        WallAssemblyLayer{.material_id = brick, .thickness_meters = 0.20, .function = WallLayerFunction::Core},
        WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = WallLayerFunction::ExteriorFinish},
    });
    const auto floor_assembly = document.create_layered_assembly(LayeredAssemblyKind::Floor, "Tile Floor", {
        WallAssemblyLayer{.material_id = tile, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
        WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.12, .function = WallLayerFunction::Core},
    });
    const auto ceiling_assembly = document.create_layered_assembly(LayeredAssemblyKind::Ceiling, "Gypsum Ceiling", {
        WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
    });

    CreateWallCommand bottom{"Bottom", Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 12.0, .y = 0.0}}, 0.24, 3.2, level};
    CreateWallCommand top{"Top", Line2{.start = {.x = 12.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}}, 0.24, 3.2, level};
    CreateWallCommand right{"Right", Line2{.start = {.x = 12.0, .y = 0.0}, .end = {.x = 12.0, .y = 4.0}}, 0.24, 3.2, level};
    CreateWallCommand left{"Left", Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}}, 0.24, 3.2, level};
    CreateWallCommand shared{"Shared", Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 4.0}}, 0.24, 3.2, level};
    processor.execute(document, bottom);
    processor.execute(document, top);
    processor.execute(document, right);
    processor.execute(document, left);
    processor.execute(document, shared);
    document.set_wall_type(bottom.created_id(), wall_type);
    document.set_wall_type(top.created_id(), wall_type);
    document.set_wall_type(right.created_id(), wall_type);
    document.set_wall_type(left.created_id(), wall_type);
    document.set_wall_type(shared.created_id(), wall_type);

    AutoJoinWallsCommand join;
    processor.execute(document, join);
    InsertDoorCommand entry_door{"Entry Door", left.created_id(), 1.5, 0.95, 2.1};
    InsertWindowCommand living_window{"Living Window", right.created_id(), 1.8, 1.2, 1.1, 0.9};
    processor.execute(document, entry_door);
    processor.execute(document, living_window);

    DetectRoomsCommand detect_rooms;
    processor.execute(document, detect_rooms);
    document.generate_floor_systems_for_all_rooms(floor_assembly);
    document.generate_ceiling_systems_for_all_rooms(ceiling_assembly, 3.0);
    document.set_wall_axis(shared.created_id(), Line2{.start = {.x = 6.5, .y = 0.0}, .end = {.x = 6.5, .y = 4.0}});
    document.mark_rooms_dirty_for_wall(shared.created_id());
    const auto dirty_rooms = document.recompute_dirty_rooms();
    document.create_slab(level, {
        {.x = 0.0, .y = 0.0},
        {.x = 12.0, .y = 0.0},
        {.x = 12.0, .y = 4.0},
        {.x = 0.0, .y = 4.0},
    }, 0.18, concrete);
    document.create_roof(level, {
        {.x = -0.2, .y = -0.2},
        {.x = 12.2, .y = -0.2},
        {.x = 12.2, .y = 4.2},
        {.x = -0.2, .y = 4.2},
    }, RoofType::Flat, 0.16, concrete);
    document.create_column(level, {.x = 1.0, .y = 1.0}, 0.3, 0.4, 3.2, concrete);
    document.create_column(level, {.x = 10.5, .y = 3.0}, 0.3, 0.4, 3.2, concrete);
    document.create_beam(level, {.x = 1.0, .y = 1.0}, {.x = 11.0, .y = 1.0}, 0.25, 0.4, concrete);
    document.create_stair(level, upper_level, {.x = 9.5, .y = 0.4}, {.x = 0.0, .y = 1.0}, 1.0, 3.2, 4.0, 18, 17, concrete);
    document.regenerate_dirty_geometry();

    const auto validation = document.validate_document();
    const auto wall_schedule = document.generate_wall_schedule();
    const auto opening_schedule = document.generate_opening_schedule();
    const auto room_schedule = document.generate_room_schedule();
    const auto floor_schedule = document.generate_floor_finish_schedule();
    const auto ceiling_schedule = document.generate_ceiling_schedule();
    const auto slab_schedule = document.generate_slab_schedule();
    const auto roof_schedule = document.generate_roof_schedule();
    const auto column_schedule = document.generate_column_schedule();
    const auto beam_schedule = document.generate_beam_schedule();
    const auto stair_schedule = document.generate_stair_schedule();
    const auto takeoff = document.generate_material_takeoff();

    const auto json = project.to_json();
    auto api_session_result = tbe::api::create_session("Building Elements Torture");
    if (!api_session_result.ok() || !api_session_result.value.has_value()) {
        std::cerr << "Failed to create API session for building torture\n";
        return 1;
    }
    auto api_session = std::move(*api_session_result.value);
    const auto load_result = api_session->load_project_json_with_mode(json, tbe::api::LoadMode::Repair);
    const auto repair_report = api_session->repair_current_project();
    const auto final_recompute = api_session->recompute_all_final();
    const auto final_freshness = api_session->get_freshness_summary();
    const auto api_validation = api_session->get_validation_report();
    const auto api_schedule_summary = api_session->generate_schedules();
    const auto api_takeoff = api_session->generate_material_takeoff_summary();
    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_torture_building";
    std::filesystem::create_directories(export_dir);
    const auto export_result = api_session->export_project_package(export_dir.string());

    std::cout << "Torture mode: quantities\n";
    std::cout << "Wall count: " << std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) { return element.wall() != nullptr; }) << '\n';
    std::size_t join_count = 0;
    std::size_t opening_count = 0;
    std::size_t slab_count = 0;
    std::size_t roof_count = 0;
    std::size_t column_count = 0;
    std::size_t beam_count = 0;
    std::size_t stair_count = 0;
    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall(); wall != nullptr) {
            join_count += wall->joins.size();
            opening_count += wall->openings.size();
        }
        slab_count += element.slab() != nullptr;
        roof_count += element.roof() != nullptr;
        column_count += element.column() != nullptr;
        beam_count += element.beam() != nullptr;
        stair_count += element.stair() != nullptr;
    }
    std::cout << "Join count: " << join_count << '\n';
    std::cout << "Opening count: " << opening_count << '\n';
    std::cout << "Room count: " << detect_rooms.detected_room_ids().size() << '\n';
    std::cout << "Dirty room count: " << dirty_rooms.size() << '\n';
    std::cout << "Slab count: " << slab_count << '\n';
    std::cout << "Floor system count: " << document.floor_systems().size() << '\n';
    std::cout << "Ceiling system count: " << document.ceiling_systems().size() << '\n';
    std::cout << "Roof count: " << roof_count << '\n';
    std::cout << "Column count: " << column_count << '\n';
    std::cout << "Beam count: " << beam_count << '\n';
    std::cout << "Stair count: " << stair_count << '\n';
    std::cout << "Wall schedule rows: " << wall_schedule.size() << '\n';
    std::cout << "Opening schedule rows: " << opening_schedule.size() << '\n';
    std::cout << "Room schedule rows: " << room_schedule.size() << '\n';
    std::cout << "Floor schedule rows: " << floor_schedule.size() << '\n';
    std::cout << "Ceiling schedule rows: " << ceiling_schedule.size() << '\n';
    std::cout << "Slab schedule rows: " << slab_schedule.size() << '\n';
    std::cout << "Roof schedule rows: " << roof_schedule.size() << '\n';
    std::cout << "Column schedule rows: " << column_schedule.size() << '\n';
    std::cout << "Beam schedule rows: " << beam_schedule.size() << '\n';
    std::cout << "Stair schedule rows: " << stair_schedule.size() << '\n';
    std::cout << "Material takeoff rows: " << takeoff.size() << '\n';
    std::cout << "Validation issues: " << validation.issue_count() << '\n';
    std::cout << "Validation warnings: " << validation.warning_count() << '\n';
    std::cout << "Validation errors: " << validation.error_count() << '\n';
    std::cout << "API load: " << (load_result.ok() ? "ok" : "failed") << '\n';
    std::cout << "API repair: " << (repair_report.ok() ? "ok" : "failed") << '\n';
    std::cout << "API final recompute: " << (final_recompute.ok() ? "ok" : "failed") << '\n';
    if (final_freshness.ok() && final_freshness.value.has_value()) {
        const auto freshness_name = [](tbe::api::FreshnessState state) {
            switch (state) {
                case tbe::api::FreshnessState::Clean: return "clean";
                case tbe::api::FreshnessState::Dirty: return "dirty";
                case tbe::api::FreshnessState::Stale: return "stale";
                case tbe::api::FreshnessState::Computing: return "computing";
                case tbe::api::FreshnessState::Failed: return "failed";
            }
            return "unknown";
        };
        std::cout << "API final freshness room metrics: " << freshness_name(final_freshness.value->room_metrics) << '\n';
        std::cout << "API final freshness schedules: " << freshness_name(final_freshness.value->schedules) << '\n';
        std::cout << "API final freshness takeoff: " << freshness_name(final_freshness.value->material_takeoff) << '\n';
        std::cout << "API final freshness validation: " << freshness_name(final_freshness.value->validation_report) << '\n';
    }
    std::cout << "API validation errors: " << (api_validation.ok() && api_validation.value.has_value() ? api_validation.value->error_count : -1) << '\n';
    std::cout << "API wall rows: " << (api_schedule_summary.ok() && api_schedule_summary.value.has_value() ? api_schedule_summary.value->wall_rows : 0) << '\n';
    std::cout << "API room rows: " << (api_schedule_summary.ok() && api_schedule_summary.value.has_value() ? api_schedule_summary.value->room_rows : 0) << '\n';
    std::cout << "API takeoff rows: " << (api_takeoff.ok() && api_takeoff.value.has_value() ? api_takeoff.value->size() : 0) << '\n';
    std::cout << "Package export: " << (export_result.ok() ? "ok" : "failed") << '\n';
    return 0;
}

std::vector<std::string> takeoff_signature(const std::vector<tbe::core::MaterialTakeoffRow>& rows) {
    std::vector<std::string> signature;
    signature.reserve(rows.size());
    for (const auto& row : rows) {
        const auto scaled = static_cast<long long>(std::llround(row.quantity * 1'000'000.0));
        signature.push_back(
            std::to_string(row.material_id) + "|" +
            std::to_string(static_cast<int>(row.quantity_type)) + "|" +
            std::to_string(scaled)
        );
    }
    std::sort(signature.begin(), signature.end());
    return signature;
}

int run_torture_performance(int grid_size) {
    using namespace tbe::core;

    StressModel model{Project{"Performance Torture"}};
    const auto build_ms = measure_ms([&]() {
        model = create_stress_model("Performance Torture", StressModelOptions{.grid_size = grid_size, .include_openings = true, .include_building_elements = true});
    });

    auto& document = model.project.active_document();
    const auto auto_join_ms = measure_ms([&]() {
        document.auto_join_walls();
    });
    const auto detect_ms = measure_ms([&]() {
        model.room_ids = document.detect_rooms();
    });
    const auto detail_ms = measure_ms([&]() {
        add_building_element_stress_details(model);
    });
    const auto regen_ms = measure_ms([&]() {
        document.regenerate_dirty_geometry();
    });

    const auto validation_ms = measure_ms([&]() {
        (void)document.validate_document();
    });
    const auto wall_schedule_ms = measure_ms([&]() {
        (void)document.generate_wall_schedule();
    });
    const auto room_schedule_ms = measure_ms([&]() {
        (void)document.generate_room_schedule();
    });
    const auto floor_schedule_ms = measure_ms([&]() {
        (void)document.generate_floor_finish_schedule();
    });
    const auto ceiling_schedule_ms = measure_ms([&]() {
        (void)document.generate_ceiling_schedule();
    });
    const auto takeoff_ms = measure_ms([&]() {
        (void)document.generate_material_takeoff();
    });

    const auto original_room_areas = sorted_room_areas(document, model.room_ids);
    bool incremental_matches_full_rooms = true;
    bool incremental_matches_full_takeoff = true;
    if (!model.shared_wall_ids.empty()) {
        const auto edit_wall_id = model.shared_wall_ids[model.shared_wall_ids.size() / 2];
        const auto* wall = document.find_ptr(edit_wall_id)->wall();
        if (wall != nullptr) {
            document.set_wall_axis(
                edit_wall_id,
                Line2{
                    .start = {.x = wall->axis.start.x + 1.0e-6, .y = wall->axis.start.y + 1.0e-6},
                    .end = {.x = wall->axis.end.x + 1.0e-6, .y = wall->axis.end.y + 1.0e-6},
                }
            );
            document.mark_rooms_dirty_for_wall(edit_wall_id);
            const auto dirty_rooms = document.recompute_dirty_rooms();
            const auto dirty_room_areas = sorted_room_areas(document, dirty_rooms);
            const auto dirty_takeoff_signature = takeoff_signature(document.generate_material_takeoff());
            const auto full_rooms = document.recompute_all_rooms();
            const auto full_room_areas = sorted_room_areas(document, full_rooms);
            const auto full_takeoff_signature = takeoff_signature(document.generate_material_takeoff());
            incremental_matches_full_rooms = dirty_room_areas == full_room_areas;
            incremental_matches_full_takeoff = dirty_takeoff_signature == full_takeoff_signature;
        }
    }

    const auto edit_validation = document.validate_document();
    document.regenerate_dirty_geometry();
    const auto post_edit_takeoff = document.generate_material_takeoff();
    const auto post_edit_takeoff_signature = takeoff_signature(post_edit_takeoff);
    const auto repeated_takeoff_signature = takeoff_signature(document.generate_material_takeoff());
    const bool repeated_takeoff_stable = post_edit_takeoff_signature == repeated_takeoff_signature;

    const auto save_ms = measure_ms([&]() {
        (void)model.project.to_json();
    });
    const auto json = model.project.to_json();
    bool core_load_ok = true;
    std::optional<std::string> core_load_error;
    const auto load_ms = measure_ms([&]() {
        try {
            auto loaded = tbe::core::Project::from_json(json);
            loaded.active_document().regenerate_dirty_geometry();
        } catch (const std::exception& error) {
            core_load_ok = false;
            core_load_error = error.what();
        }
    });

    auto api_session_result = tbe::api::create_session("Performance Torture");
    if (!api_session_result.ok() || !api_session_result.value.has_value()) {
        std::cerr << "Failed to create API session for performance torture\n";
        return 1;
    }
    auto api_session = std::move(*api_session_result.value);
    bool api_load_ok = true;
    std::optional<std::string> api_load_error;
    const auto api_load_ms = measure_ms([&]() {
        try {
            const auto load_result = api_session->load_project_json_with_mode(json, tbe::api::LoadMode::Repair);
            api_load_ok = load_result.ok();
            if (!load_result.ok()) {
                api_load_error = load_result.message;
            }
        } catch (const std::exception& error) {
            api_load_ok = false;
            api_load_error = error.what();
        }
    });
    const auto api_rebuild_ms = measure_ms([&]() {
        (void)api_session->rebuild_spatial_index();
    });
    const auto api_hit_ms = measure_ms([&]() {
        (void)api_session->hit_test_point({.level_id = {.value = model.base_level_id}, .point = {.x = 1.5, .y = 1.5}, .tolerance_meters = 0.2});
    });
    const auto api_snap_ms = measure_ms([&]() {
        (void)api_session->best_snap({.value = model.base_level_id}, {.x = 1.5, .y = 1.5}, 0.2);
    });
    const auto api_query_rect = api_session->query_rect({.value = model.base_level_id}, {.min_x = 0.0, .min_y = 0.0, .max_x = static_cast<double>(grid_size), .max_y = static_cast<double>(grid_size)});
    const auto api_stats = api_session->spatial_index_stats();
    const auto api_save_ms = measure_ms([&]() {
        (void)api_session->save_project_json();
    });
    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_perf_torture";
    std::filesystem::remove_all(export_dir);
    std::filesystem::create_directories(export_dir);
    bool package_export_ok = true;
    std::optional<std::string> package_export_error;
    const auto package_export_ms = measure_ms([&]() {
        try {
            const auto export_result = api_session->export_project_package(export_dir.string());
            package_export_ok = export_result.ok();
            if (!export_result.ok()) {
                package_export_error = export_result.message;
            }
        } catch (const std::exception& error) {
            package_export_ok = false;
            package_export_error = error.what();
        }
    });
    auto import_session_result = tbe::api::create_session("Performance Torture Import");
    bool package_import_ok = false;
    std::optional<std::string> package_import_error;
    std::optional<tbe::api::ValidationReportDTO> import_validation;
    std::optional<tbe::api::SpatialIndexStatsDTO> import_stats;
    double package_import_ms = 0.0;
    if (!import_session_result.ok() || !import_session_result.value.has_value()) {
        std::cerr << "Failed to create import session for performance torture\n";
    } else {
        auto import_session = std::move(*import_session_result.value);
        package_import_ms = measure_ms([&]() {
            try {
                const auto import_result = import_session->import_project_package(export_dir.string(), tbe::api::LoadMode::Repair);
                package_import_ok = import_result.ok();
                if (!import_result.ok()) {
                    package_import_error = import_result.message;
                }
            } catch (const std::exception& error) {
                package_import_ok = false;
                package_import_error = error.what();
            }
        });
        const auto validation_result = import_session->get_validation_report();
        if (validation_result.ok() && validation_result.value.has_value()) {
            import_validation = *validation_result.value;
        }
        const auto stats_result = import_session->spatial_index_stats();
        if (stats_result.ok() && stats_result.value.has_value()) {
            import_stats = *stats_result.value;
        }
    }

    std::cout << "Torture mode: performance\n";
    std::cout << "Grid size: " << grid_size << '\n';
    std::cout << "Element count: " << document.elements().size() << '\n';
    std::cout << "Wall count: " << std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) { return element.wall() != nullptr; }) << '\n';
    std::cout << "Room count: " << model.room_ids.size() << '\n';
    std::cout << "Opening count: " << std::count_if(document.elements().begin(), document.elements().end(), [](const auto& element) { return element.door() != nullptr || element.window() != nullptr; }) << '\n';
    std::cout << "Floor rows: " << document.generate_floor_finish_schedule().size() << '\n';
    std::cout << "Ceiling rows: " << document.generate_ceiling_schedule().size() << '\n';
    std::cout << "Slab rows: " << document.generate_slab_schedule().size() << '\n';
    std::cout << "Roof rows: " << document.generate_roof_schedule().size() << '\n';
    std::cout << "Column rows: " << document.generate_column_schedule().size() << '\n';
    std::cout << "Beam rows: " << document.generate_beam_schedule().size() << '\n';
    std::cout << "Stair rows: " << document.generate_stair_schedule().size() << '\n';
    std::cout << "Material takeoff rows: " << post_edit_takeoff.size() << '\n';
    std::cout << "Validation errors: " << edit_validation.error_count() << '\n';
    std::cout << "Validation warnings: " << edit_validation.warning_count() << '\n';
    std::cout << "Incremental rooms match full: " << (incremental_matches_full_rooms ? "yes" : "no") << '\n';
    std::cout << "Incremental takeoff match full: " << (incremental_matches_full_takeoff ? "yes" : "no") << '\n';
    std::cout << "Repeated takeoff stable: " << (repeated_takeoff_stable ? "yes" : "no") << '\n';
    std::cout << "Original room areas: ";
    for (std::size_t index = 0; index < original_room_areas.size(); ++index) {
        if (index != 0) {
            std::cout << ", ";
        }
        std::cout << original_room_areas[index];
    }
    std::cout << '\n';
    std::cout << "Timings ms:\n";
    std::cout << "  build=" << build_ms << '\n';
    std::cout << "  auto_join=" << auto_join_ms << '\n';
    std::cout << "  detect_rooms=" << detect_ms << '\n';
    std::cout << "  detail_generation=" << detail_ms << '\n';
    std::cout << "  geometry_regen=" << regen_ms << '\n';
    std::cout << "  validation=" << validation_ms << '\n';
    std::cout << "  wall_schedule=" << wall_schedule_ms << '\n';
    std::cout << "  room_schedule=" << room_schedule_ms << '\n';
    std::cout << "  floor_schedule=" << floor_schedule_ms << '\n';
    std::cout << "  ceiling_schedule=" << ceiling_schedule_ms << '\n';
    std::cout << "  takeoff=" << takeoff_ms << '\n';
    std::cout << "  save_json=" << save_ms << '\n';
    std::cout << "  load_json=" << load_ms << '\n';
    std::cout << "  api_load=" << api_load_ms << '\n';
    std::cout << "  api_rebuild_spatial_index=" << api_rebuild_ms << '\n';
    std::cout << "  api_hit_test=" << api_hit_ms << '\n';
    std::cout << "  api_snap=" << api_snap_ms << '\n';
    std::cout << "  api_save=" << api_save_ms << '\n';
    std::cout << "  package_export=" << package_export_ms << '\n';
    std::cout << "  package_import=" << package_import_ms << '\n';
    std::cout << "Raw JSON round-trip: " << (core_load_ok ? "ok" : "failed") << '\n';
    if (core_load_error.has_value()) {
        std::cout << "Core load error: " << *core_load_error << '\n';
    }
    std::cout << "API load ok: " << (api_load_ok ? "yes" : "no") << '\n';
    if (api_load_error.has_value()) {
        std::cout << "API load error: " << *api_load_error << '\n';
    }
    std::cout << "Package export ok: " << (package_export_ok ? "yes" : "no") << '\n';
    if (package_export_error.has_value()) {
        std::cout << "Package export error: " << *package_export_error << '\n';
    }
    if (api_stats.ok() && api_stats.value.has_value()) {
        std::cout << "Spatial version: " << api_stats.value->version << '\n';
        std::cout << "Spatial dirty: " << (api_stats.value->dirty ? "yes" : "no") << '\n';
        std::cout << "Spatial buckets: " << api_stats.value->bucket_count << '\n';
        std::cout << "Spatial occupancy avg: " << api_stats.value->average_bucket_occupancy << '\n';
        std::cout << "Spatial occupancy max: " << api_stats.value->max_bucket_occupancy << '\n';
    }
    if (api_query_rect.ok() && api_query_rect.value.has_value()) {
        std::cout << "Spatial query rect hits: " << api_query_rect.value->size() << '\n';
    }
    if (import_validation.has_value()) {
        std::cout << "Imported validation errors: " << import_validation->error_count << '\n';
        std::cout << "Imported validation warnings: " << import_validation->warning_count << '\n';
    }
    if (import_stats.has_value()) {
        std::cout << "Imported spatial version: " << import_stats->version << '\n';
    }
    std::cout << "Package import ok: " << (package_import_ok ? "yes" : "no") << '\n';
    if (package_import_error.has_value()) {
        std::cout << "Package import error: " << *package_import_error << '\n';
    }
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    int performance_grid_size = 10;
    bool run_performance_mode = false;
    for (int index = 1; index < argc; ++index) {
        const std::string_view argument = argv[index];
        if (argument == "--torture-performance") {
            run_performance_mode = true;
        } else if (argument == "--grid-size" && index + 1 < argc) {
            performance_grid_size = std::max(1, std::stoi(argv[++index]));
        }
    }

    if (argc > 1 && std::string_view(argv[1]) == "--torture-wall-room") {
        return run_torture_wall_room();
    }
    if (argc > 1 && std::string_view(argv[1]) == "--torture-building-elements") {
        return run_torture_building_elements();
    }
    if (argc > 1 && std::string_view(argv[1]) == "--torture-quantities") {
        return run_torture_building_elements();
    }
    if (run_performance_mode) {
        try {
            return run_torture_performance(performance_grid_size);
        } catch (const std::exception& error) {
            std::cerr << "Performance torture failed: " << error.what() << '\n';
            return 1;
        }
    }

    tbe::core::Project project{"Tablet BIM Sample"};
    auto& document = project.active_document();
    tbe::core::CommandProcessor commands;

    tbe::core::CreateLevelCommand level{"Level 1", 0.0, 3.2};
    commands.execute(document, level);
    const auto level_id = level.created_id();

    const auto brick = document.create_material("Brick", tbe::core::MaterialCategory::Structural, 1800.0, 120.0);
    const auto plaster = document.create_material("Plaster", tbe::core::MaterialCategory::Finish, 950.0, 40.0);
    const auto paint = document.create_material("Paint", tbe::core::MaterialCategory::Finish, std::nullopt, 12.0);
    const auto glass = document.create_material("Glass", tbe::core::MaterialCategory::Glass, 2500.0, 80.0);
    const auto concrete = document.create_material("Concrete", tbe::core::MaterialCategory::Structural, 2400.0, 110.0);
    const auto floor_tile = document.create_material("Floor Tile", tbe::core::MaterialCategory::Finish, 2100.0, 55.0);
    const auto gypsum = document.create_material("Gypsum", tbe::core::MaterialCategory::Finish, 850.0, 28.0);
    (void)paint;
    const auto masonry_wall_type = document.create_wall_type("Brick Wall", {
        tbe::core::WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = brick, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core},
        tbe::core::WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::ExteriorFinish},
    });
    const auto floor_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Tile Floor", {
        tbe::core::WallAssemblyLayer{.material_id = floor_tile, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Core},
    });
    const auto ceiling_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Ceiling, "Gypsum Ceiling", {
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
    });

    tbe::core::CreateWallCommand bottom{
        "Bottom Wall",
        tbe::core::Line2{.start = {.x = 0.0, .y = 0.0}, .end = {.x = 10.0, .y = 0.0}},
        0.24,
        3.2,
        level_id
    };
    tbe::core::CreateWallCommand top{
        "Top Wall",
        tbe::core::Line2{.start = {.x = 10.0, .y = 4.0}, .end = {.x = 0.0, .y = 4.0}},
        0.24,
        3.2,
        level_id
    };
    tbe::core::CreateWallCommand right{
        "Right Wall",
        tbe::core::Line2{.start = {.x = 10.0, .y = 0.0}, .end = {.x = 10.0, .y = 4.0}},
        0.24,
        3.2,
        level_id
    };
    tbe::core::CreateWallCommand left{
        "Left Wall",
        tbe::core::Line2{.start = {.x = 0.0, .y = 4.0}, .end = {.x = 0.0, .y = 0.0}},
        0.24,
        3.2,
        level_id
    };
    tbe::core::CreateWallCommand shared{
        "Shared Wall",
        tbe::core::Line2{.start = {.x = 5.0, .y = 0.0}, .end = {.x = 5.0, .y = 4.0}},
        0.20,
        3.2,
        level_id
    };

    commands.execute(document, bottom);
    commands.execute(document, top);
    commands.execute(document, right);
    commands.execute(document, left);
    commands.execute(document, shared);
    document.set_wall_type(bottom.created_id(), masonry_wall_type);
    document.set_wall_type(top.created_id(), masonry_wall_type);
    document.set_wall_type(right.created_id(), masonry_wall_type);
    document.set_wall_type(left.created_id(), masonry_wall_type);
    document.set_wall_type(shared.created_id(), masonry_wall_type);

    tbe::core::AutoJoinWallsCommand auto_join;
    commands.execute(document, auto_join);

    tbe::core::InsertDoorCommand door{"Entry Door", left.created_id(), 1.6, 0.95, 2.1};
    tbe::core::InsertWindowCommand window{"Living Window", right.created_id(), 2.0, 1.2, 1.1, 0.9};
    commands.execute(document, door);
    commands.execute(document, window);

    tbe::core::DetectRoomsCommand detect_rooms;
    commands.execute(document, detect_rooms);
    document.regenerate_dirty_geometry();
    document.generate_floor_systems_for_all_rooms(floor_assembly);
    document.generate_ceiling_systems_for_all_rooms(ceiling_assembly, 3.0);
    const auto slab_id = document.create_slab(level_id, {
        {.x = 0.0, .y = 0.0},
        {.x = 10.0, .y = 0.0},
        {.x = 10.0, .y = 4.0},
        {.x = 0.0, .y = 4.0},
    }, 0.20, concrete);
    const auto roof_id = document.create_roof(level_id, {
        {.x = -0.2, .y = -0.2},
        {.x = 10.2, .y = -0.2},
        {.x = 10.2, .y = 4.2},
        {.x = -0.2, .y = 4.2},
    }, tbe::core::RoofType::Flat, 0.18, concrete);
    const auto column_a_id = document.create_column(level_id, {.x = 1.0, .y = 1.0}, 0.3, 0.3, 3.2, concrete);
    const auto column_b_id = document.create_column(level_id, {.x = 9.0, .y = 3.0}, 0.3, 0.3, 3.2, concrete);
    const auto beam_id = document.create_beam(level_id, {.x = 1.0, .y = 1.0}, {.x = 9.0, .y = 1.0}, 0.25, 0.4, concrete);
    const auto stair_id = document.create_stair(level_id, level_id, {.x = 7.0, .y = 0.4}, {.x = 0.0, .y = 1.0}, 1.0, 3.2, 4.0, 18, 17, concrete);

    const auto initial_room_ids = document.detect_rooms();
    const auto initial_areas = sorted_room_areas(document, initial_room_ids);
    const auto initial_interior_areas = sorted_room_interior_areas(document, initial_room_ids);

    tbe::core::SetWallAxisCommand move_shared{
        shared.created_id(),
        tbe::core::Line2{.start = {.x = 6.0, .y = 0.0}, .end = {.x = 6.0, .y = 4.0}}
    };
    document.mark_rooms_dirty_for_wall(shared.created_id());
    const auto affected_room_ids = document.dirty_room_ids();
    commands.execute(document, move_shared);
    const auto moved_room_ids = document.detect_rooms();
    const auto moved_areas = sorted_room_areas(document, moved_room_ids);
    const auto moved_interior_areas = sorted_room_interior_areas(document, moved_room_ids);

    commands.undo_last(document);
    const auto undo_room_ids = document.detect_rooms();
    const auto undo_areas = sorted_room_areas(document, undo_room_ids);

    commands.redo_last(document);
    const auto redo_room_ids = document.detect_rooms();
    const auto redo_areas = sorted_room_areas(document, redo_room_ids);

    document.regenerate_dirty_geometry();
    const auto validation = document.validate_document();
    const auto wall_schedule = document.generate_wall_schedule();
    const auto opening_schedule = document.generate_opening_schedule();
    const auto room_schedule = document.generate_room_schedule();
    const auto floor_schedule = document.generate_floor_finish_schedule();
    const auto ceiling_schedule = document.generate_ceiling_schedule();
    const auto slab_schedule = document.generate_slab_schedule();
    const auto roof_schedule = document.generate_roof_schedule();
    const auto column_schedule = document.generate_column_schedule();
    const auto beam_schedule = document.generate_beam_schedule();
    const auto stair_schedule = document.generate_stair_schedule();
    const auto material_takeoff = document.generate_material_takeoff();
    const auto full_recompute_ids = document.recompute_all_rooms();
    const auto incremental_equals_full = sorted_room_areas(document, redo_room_ids) == sorted_room_areas(document, full_recompute_ids);

    const auto export_dir = std::filesystem::temp_directory_path() / "tbe_level9_exports";
    std::filesystem::create_directories(export_dir);
    const auto svg_path = export_dir / "floorplan.svg";
    const auto obj_path = export_dir / "walls.obj";
    const auto report_path = export_dir / "debug_report.json";
    document.export_floorplan_svg(svg_path);
    document.export_mesh_obj(obj_path);
    document.export_debug_report_json(report_path);

    tbe::core::GeometryService geometry;
    const auto* left_wall = document.find_ptr(left.created_id())->wall();

    const auto json = project.to_json();
    auto reloaded_project = tbe::core::Project::from_json(json);
    auto& reloaded = reloaded_project.active_document();
    reloaded.regenerate_dirty_geometry();
    const auto reloaded_room_ids = reloaded.detect_rooms();
    const auto reloaded_validation = reloaded.validate_document();

    std::cout << "Project: " << project.name() << '\n';
    std::cout << "Geometry backend: " << geometry.backend_name() << '\n';
    std::cout << "Elements: " << document.elements().size() << '\n';
    std::cout << "Room count: " << initial_room_ids.size() << '\n';
    print_areas("Initial room areas: ", initial_areas);
    print_areas("Initial interior areas: ", initial_interior_areas);
    print_areas("Moved room areas: ", moved_areas);
    print_areas("Moved interior areas: ", moved_interior_areas);
    print_areas("Undo room areas: ", undo_areas);
    print_areas("Redo room areas: ", redo_areas);
    std::cout << "Affected room ids: ";
    for (std::size_t index = 0; index < affected_room_ids.size(); ++index) {
        if (index != 0) {
            std::cout << ", ";
        }
        std::cout << affected_room_ids[index];
    }
    std::cout << '\n';
    std::cout << "Left wall mesh: " << left_wall->geometry.mesh.vertices.size() << " vertices, "
              << left_wall->geometry.mesh.indices.size() << " indices\n";
    std::cout << "Wall schedule rows: " << wall_schedule.size() << '\n';
    std::cout << "Opening schedule rows: " << opening_schedule.size() << '\n';
    std::cout << "Room schedule rows: " << room_schedule.size() << '\n';
    std::cout << "Floor schedule rows: " << floor_schedule.size() << '\n';
    std::cout << "Ceiling schedule rows: " << ceiling_schedule.size() << '\n';
    std::cout << "Slab schedule rows: " << slab_schedule.size() << '\n';
    std::cout << "Roof schedule rows: " << roof_schedule.size() << '\n';
    std::cout << "Column schedule rows: " << column_schedule.size() << '\n';
    std::cout << "Beam schedule rows: " << beam_schedule.size() << '\n';
    std::cout << "Stair schedule rows: " << stair_schedule.size() << '\n';
    std::cout << "Material takeoff rows: " << material_takeoff.size() << '\n';
    if (!wall_schedule.empty()) {
        std::cout << "First wall type: " << wall_schedule.front().wall_type_name << '\n';
        std::cout << "First wall net area: " << wall_schedule.front().net_area_square_meters << '\n';
    }
    if (!opening_schedule.empty()) {
        std::cout << "First opening area: " << opening_schedule.front().area_square_meters << '\n';
    }
    if (!room_schedule.empty()) {
        std::cout << "First room floor area: " << room_schedule.front().floor_finish_area_square_meters << '\n';
        std::cout << "First room wall finish area: " << room_schedule.front().interior_wall_finish_area_square_meters << '\n';
    }
    if (!floor_schedule.empty()) {
        std::cout << "First floor assembly: " << floor_schedule.front().assembly_name << '\n';
        std::cout << "First floor area: " << floor_schedule.front().area_square_meters << '\n';
    }
    if (!ceiling_schedule.empty()) {
        std::cout << "First ceiling assembly: " << ceiling_schedule.front().assembly_name << '\n';
        std::cout << "First ceiling area: " << ceiling_schedule.front().area_square_meters << '\n';
    }
    if (!slab_schedule.empty()) {
        std::cout << "Slab " << slab_id << " area: " << slab_schedule.front().area_square_meters << '\n';
        std::cout << "Slab " << slab_id << " volume: " << slab_schedule.front().volume_cubic_meters << '\n';
    }
    if (!roof_schedule.empty()) {
        std::cout << "Roof " << roof_id << " area: " << roof_schedule.front().area_square_meters << '\n';
    }
    if (!column_schedule.empty()) {
        std::cout << "Column " << column_a_id << " volume: " << column_schedule.front().volume_cubic_meters << '\n';
    }
    if (!beam_schedule.empty()) {
        std::cout << "Beam " << beam_id << " length: " << beam_schedule.front().length_meters << '\n';
    }
    if (!stair_schedule.empty()) {
        std::cout << "Stair " << stair_id << " run: " << stair_schedule.front().total_run_meters << '\n';
    }
    if (!material_takeoff.empty()) {
        for (const auto& row : material_takeoff) {
            std::cout << "Takeoff: " << row.material_name << ' ' << row.quantity << ' ' << row.unit << '\n';
        }
    }
    const auto print_row_summary = [](const auto& rows, const char* label, auto predicate, auto printer) {
        const auto it = std::find_if(rows.begin(), rows.end(), predicate);
        if (it == rows.end()) {
            return;
        }
        std::cout << label;
        printer(*it);
        std::cout << '\n';
    };
    print_row_summary(wall_schedule, "Wall summary: ", [shared](const auto& row) { return row.wall_id == shared.created_id(); }, [](const auto& row) {
        std::cout << "gross=" << row.gross_area_square_meters
                  << " opening=" << row.opening_area_square_meters
                  << " net=" << row.net_area_square_meters
                  << " volume=" << row.net_volume_cubic_meters;
    });
    print_row_summary(opening_schedule, "Door summary: ", [door](const auto& row) { return row.element_id == door.created_id(); }, [](const auto& row) {
        std::cout << "area=" << row.area_square_meters
                  << " width=" << row.width_meters
                  << " height=" << row.height_meters;
    });
    print_row_summary(room_schedule, "Room summary: ", [](const auto& row) { return row.room_id != 0; }, [](const auto& row) {
        std::cout << "centerline=" << row.centerline_area_square_meters
                  << " interior=" << row.interior_area_square_meters
                  << " perimeter=" << row.interior_perimeter_meters;
    });
    print_row_summary(floor_schedule, "Floor summary: ", [](const auto& row) { return row.floor_system_id != 0; }, [](const auto& row) {
        std::cout << "area=" << row.area_square_meters;
    });
    print_row_summary(ceiling_schedule, "Ceiling summary: ", [](const auto& row) { return row.ceiling_system_id != 0; }, [](const auto& row) {
        std::cout << "area=" << row.area_square_meters;
    });
    print_row_summary(slab_schedule, "Slab summary: ", [](const auto& row) { return row.slab_id != 0; }, [](const auto& row) {
        std::cout << "area=" << row.area_square_meters << " volume=" << row.volume_cubic_meters;
    });
    print_row_summary(roof_schedule, "Roof summary: ", [](const auto& row) { return row.roof_id != 0; }, [](const auto& row) {
        std::cout << "area=" << row.area_square_meters << " volume=" << row.volume_cubic_meters;
    });
    print_row_summary(column_schedule, "Column summary: ", [](const auto& row) { return row.column_id != 0; }, [](const auto& row) {
        std::cout << "volume=" << row.volume_cubic_meters;
    });
    print_row_summary(beam_schedule, "Beam summary: ", [](const auto& row) { return row.beam_id != 0; }, [](const auto& row) {
        std::cout << "length=" << row.length_meters << " volume=" << row.volume_cubic_meters;
    });
    print_row_summary(stair_schedule, "Stair summary: ", [](const auto& row) { return row.stair_id != 0; }, [](const auto& row) {
        std::cout << "run=" << row.total_run_meters << " volume=" << row.volume_cubic_meters;
    });
    (void)column_b_id;
    std::cout << "Dependency graph version: " << document.dependency_graph_version() << '\n';
    std::cout << "Incremental equals full recompute: " << (incremental_equals_full ? "yes" : "no") << '\n';
    std::cout << "Validation issues: " << validation.issue_count() << '\n';
    std::cout << "Validation warnings: " << validation.warning_count() << '\n';
    std::cout << "Validation errors: " << validation.error_count() << '\n';
    std::cout << "SVG export: " << svg_path << '\n';
    std::cout << "OBJ export: " << obj_path << '\n';
    std::cout << "Debug report export: " << report_path << '\n';
    std::cout << "Reload room count: " << reloaded_room_ids.size() << '\n';
    std::cout << "Reload validation: "
              << (reloaded_project.name() == project.name() &&
                  reloaded_validation.error_count() == 0 &&
                  reloaded_room_ids.size() == redo_room_ids.size() ? "ok" : "failed")
              << '\n';

    return 0;
}
