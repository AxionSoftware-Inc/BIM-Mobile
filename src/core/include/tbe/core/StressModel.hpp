#pragma once

#include "tbe/core/Project.hpp"

#include <algorithm>
#include <cmath>
#include <string>
#include <utility>
#include <vector>

namespace tbe::core {

struct StressModelOptions {
    int grid_size{10};
    bool include_openings{true};
    bool include_building_elements{true};
};

struct StressModel {
    Project project;
    int grid_size{};
    ElementId base_level_id{};
    ElementId upper_level_id{};
    ElementId wall_type_id{};
    ElementId floor_assembly_id{};
    ElementId ceiling_assembly_id{};
    ElementId concrete_material_id{};
    ElementId finish_material_id{};
    ElementId glass_material_id{};
    std::vector<ElementId> wall_ids{};
    std::vector<ElementId> shared_wall_ids{};
    std::vector<ElementId> perimeter_wall_ids{};
    std::vector<ElementId> opening_ids{};
    std::vector<ElementId> room_ids{};
    std::vector<ElementId> floor_system_ids{};
    std::vector<ElementId> ceiling_system_ids{};
    std::vector<ElementId> slab_ids{};
    std::vector<ElementId> roof_ids{};
    std::vector<ElementId> column_ids{};
    std::vector<ElementId> beam_ids{};
    std::vector<ElementId> stair_ids{};
};

inline StressModel create_stress_model(std::string name, const StressModelOptions& options) {
    StressModel model{Project{std::move(name)}};
    auto& document = model.project.active_document();
    const auto grid_size = std::max(1, options.grid_size);
    model.grid_size = grid_size;

    model.base_level_id = document.create_level("Level 1", 0.0, 3.2);
    if (options.include_building_elements) {
        model.upper_level_id = document.create_level("Level 2", 3.2, 3.2);
    }

    const auto brick = document.create_material("Brick", MaterialCategory::Structural, 1800.0, 120.0);
    const auto plaster = document.create_material("Plaster", MaterialCategory::Finish, 950.0, 40.0);
    const auto concrete = document.create_material("Concrete", MaterialCategory::Structural, 2400.0, 110.0);
    const auto tile = document.create_material("Tile", MaterialCategory::Finish, 2100.0, 55.0);
    const auto gypsum = document.create_material("Gypsum", MaterialCategory::Finish, 850.0, 28.0);
    const auto glass = document.create_material("Glass", MaterialCategory::Glass, 2500.0, 80.0);
    model.concrete_material_id = concrete;
    model.finish_material_id = tile;
    model.glass_material_id = glass;

    model.wall_type_id = document.create_wall_type("Stress Wall", {
        WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = WallLayerFunction::InteriorFinish},
        WallAssemblyLayer{.material_id = brick, .thickness_meters = 0.20, .function = WallLayerFunction::Core},
        WallAssemblyLayer{.material_id = plaster, .thickness_meters = 0.02, .function = WallLayerFunction::ExteriorFinish},
    });
    model.floor_assembly_id = document.create_layered_assembly(LayeredAssemblyKind::Floor, "Stress Floor", {
        WallAssemblyLayer{.material_id = tile, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
        WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.12, .function = WallLayerFunction::Core},
    });
    model.ceiling_assembly_id = document.create_layered_assembly(LayeredAssemblyKind::Ceiling, "Stress Ceiling", {
        WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
    });

    model.wall_ids.reserve(static_cast<std::size_t>((grid_size + 1) * grid_size * 2));
    model.shared_wall_ids.reserve(static_cast<std::size_t>((std::max(0, grid_size - 1) * grid_size * 2)));
    model.perimeter_wall_ids.reserve(static_cast<std::size_t>(grid_size * 4));

    for (int y = 0; y <= grid_size; ++y) {
        for (int x = 0; x < grid_size; ++x) {
            const auto wall_id = document.create_wall(
                "H",
                Line2{.start = {.x = static_cast<double>(x), .y = static_cast<double>(y)}, .end = {.x = static_cast<double>(x + 1), .y = static_cast<double>(y)}},
                0.24,
                3.2,
                model.base_level_id
            );
            document.set_wall_type(wall_id, model.wall_type_id);
            model.wall_ids.push_back(wall_id);
            if (y == 0 || y == grid_size) {
                model.perimeter_wall_ids.push_back(wall_id);
            } else {
                model.shared_wall_ids.push_back(wall_id);
            }
        }
    }

    for (int x = 0; x <= grid_size; ++x) {
        for (int y = 0; y < grid_size; ++y) {
            const auto wall_id = document.create_wall(
                "V",
                Line2{.start = {.x = static_cast<double>(x), .y = static_cast<double>(y)}, .end = {.x = static_cast<double>(x), .y = static_cast<double>(y + 1)}},
                0.24,
                3.2,
                model.base_level_id
            );
            document.set_wall_type(wall_id, model.wall_type_id);
            model.wall_ids.push_back(wall_id);
            if (x == 0 || x == grid_size) {
                model.perimeter_wall_ids.push_back(wall_id);
            } else {
                model.shared_wall_ids.push_back(wall_id);
            }
        }
    }

    if (options.include_openings && !model.perimeter_wall_ids.empty()) {
        const auto door_wall = model.perimeter_wall_ids.front();
        const auto window_wall = model.perimeter_wall_ids.size() > 1 ? model.perimeter_wall_ids[1] : model.perimeter_wall_ids.front();
        model.opening_ids.push_back(document.create_door("Stress Door", door_wall, 0.5, 0.4, 2.1));
        model.opening_ids.push_back(document.create_window("Stress Window", window_wall, 0.5, 0.4, 1.0, 0.9));
    }

    return model;
}

inline void add_building_element_stress_details(StressModel& model) {
    auto& document = model.project.active_document();
    if (model.room_ids.empty()) {
        model.room_ids = document.detect_rooms();
    }

    if (model.room_ids.empty()) {
        return;
    }

    if (model.floor_assembly_id != 0) {
        model.floor_system_ids = document.generate_floor_systems_for_all_rooms(model.floor_assembly_id);
    }
    if (model.ceiling_assembly_id != 0) {
        model.ceiling_system_ids = document.generate_ceiling_systems_for_all_rooms(model.ceiling_assembly_id, 3.0);
    }

    const auto size = static_cast<double>(std::max(1, model.grid_size));
    const auto boundary = std::vector<Point2>{
        {.x = 0.0, .y = 0.0},
        {.x = size, .y = 0.0},
        {.x = size, .y = size},
        {.x = 0.0, .y = size},
    };
    model.slab_ids.push_back(document.create_slab(model.base_level_id, boundary, 0.18, model.concrete_material_id));
    model.roof_ids.push_back(document.create_roof(model.base_level_id, {
        {.x = -0.2, .y = -0.2},
        {.x = size + 0.2, .y = -0.2},
        {.x = size + 0.2, .y = size + 0.2},
        {.x = -0.2, .y = size + 0.2},
    }, RoofType::Flat, 0.16, model.concrete_material_id));
    model.column_ids.push_back(document.create_column(model.base_level_id, {.x = 1.0, .y = 1.0}, 0.3, 0.4, 3.2, model.concrete_material_id));
    model.column_ids.push_back(document.create_column(model.base_level_id, {.x = std::max(1.5, size - 1.0), .y = std::max(1.5, size - 1.0)}, 0.3, 0.4, 3.2, model.concrete_material_id));
    model.beam_ids.push_back(document.create_beam(model.base_level_id, {.x = 1.0, .y = 1.0}, {.x = std::max(2.0, size - 1.0), .y = 1.0}, 0.25, 0.4, model.concrete_material_id));
    if (model.upper_level_id != 0) {
        model.stair_ids.push_back(document.create_stair(model.base_level_id, model.upper_level_id, {.x = std::max(1.0, size - 1.5), .y = 0.4}, {.x = 0.0, .y = 1.0}, 1.0, 3.2, 4.0, 18, 17, model.concrete_material_id));
    }

}

} // namespace tbe::core
