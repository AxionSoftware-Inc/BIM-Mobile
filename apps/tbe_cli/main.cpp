#include "tbe/core/Command.hpp"
#include "tbe/core/GeometryService.hpp"
#include "tbe/core/Project.hpp"

#include <algorithm>
#include <filesystem>
#include <iostream>
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

} // namespace

int main() {
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
