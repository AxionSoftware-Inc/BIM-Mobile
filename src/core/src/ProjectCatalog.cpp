#include "tbe/core/ProjectCatalog.hpp"

#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <string_view>

namespace tbe::core {

namespace {

ElementId find_material(const Document& document, std::string_view name) noexcept {
    for (const auto& [id, material] : document.materials()) {
        if (material.name == name) return id;
    }
    return 0;
}

ElementId find_wall_type(const Document& document, std::string_view name) noexcept {
    for (const auto& [id, type] : document.wall_types()) {
        if (type.name == name) return id;
    }
    return 0;
}

ElementId find_assembly(
    const Document& document,
    LayeredAssemblyKind kind,
    std::string_view name
) noexcept {
    for (const auto& [id, assembly] : document.layered_assemblies()) {
        if (assembly.kind == kind && assembly.name == name) return id;
    }
    return 0;
}

ElementId ensure_material(
    Document& document,
    std::string_view name,
    MaterialCategory category,
    double density,
    double unit_cost,
    std::string_view color,
    std::initializer_list<std::string_view> legacy_names = {}
) {
    auto id = find_material(document, name);
    if (id == 0) {
        for (const auto legacy_name : legacy_names) {
            id = find_material(document, legacy_name);
            if (id != 0) break;
        }
    }
    if (id != 0) {
        // Keep the old document-local ID and all layer references, but expose
        // one stable semantic name to the Inspector and future saves.
        const auto* existing = document.get_material(id);
        if (existing != nullptr && existing->name != name) {
            auto canonical = *existing;
            canonical.name = std::string(name);
            document.update_material(std::move(canonical));
        }
        return id;
    }
    return document.create_material(
        std::string(name), category, density, unit_cost, {}, std::string(color));
}

ElementId ensure_wall_type(
    Document& document,
    std::string_view name,
    std::vector<WallAssemblyLayer> layers,
    WallTypeCategory category
) {
    if (const auto id = find_wall_type(document, name); id != 0) return id;
    return document.create_wall_type(std::string(name), std::move(layers), category);
}

ElementId ensure_assembly(
    Document& document,
    LayeredAssemblyKind kind,
    std::string_view name,
    std::vector<WallAssemblyLayer> layers,
    std::initializer_list<std::string_view> legacy_names = {}
) {
    if (const auto id = find_assembly(document, kind, name); id != 0) return id;
    const auto layers_equal = [](const auto& left, const auto& right) {
        if (left.size() != right.size()) return false;
        return std::equal(left.begin(), left.end(), right.begin(), [](const auto& first, const auto& second) {
            return first.material_id == second.material_id &&
                std::abs(first.thickness_meters - second.thickness_meters) <= 1.0e-9 &&
                first.function == second.function &&
                first.priority == second.priority &&
                first.structural == second.structural &&
                first.side == second.side &&
                first.wraps_openings == second.wraps_openings &&
                first.wraps_ends == second.wraps_ends;
        });
    };
    for (const auto legacy_name : legacy_names) {
        const auto legacy_id = find_assembly(document, kind, legacy_name);
        const auto* legacy = legacy_id == 0 ? nullptr : document.get_layered_assembly(legacy_id);
        if (legacy == nullptr || !layers_equal(legacy->layers, layers)) continue;
        auto canonical = *legacy;
        canonical.name = std::string(name);
        document.update_layered_assembly(std::move(canonical));
        return legacy_id;
    }
    return document.create_layered_assembly(kind, std::string(name), std::move(layers));
}

} // namespace

DefaultProjectCatalog find_default_project_catalog(const Document& document) noexcept {
    DefaultProjectCatalog catalog{};
    catalog.concrete_material = find_material(document, "Concrete");
    catalog.brick_material = find_material(document, "Brick");
    catalog.gypsum_material = find_material(document, "Gypsum Board");
    catalog.insulation_material = find_material(document, "Insulation");
    catalog.screed_material = find_material(document, "Screed");
    catalog.laminate_material = find_material(document, "Laminate");
    catalog.stair_tile_material = find_material(document, "Stair Tile");
    catalog.glass_material = find_material(document, "Glass");
    catalog.aluminum_material = find_material(document, "Aluminum");
    catalog.asphalt_material = find_material(document, "Asphalt");
    catalog.paving_material = find_material(document, "Paving Stone");
    catalog.grass_material = find_material(document, "Landscape Grass");
    catalog.timber_material = find_material(document, "Timber");

    catalog.exterior_wall_type = find_wall_type(document, "Exterior Wall");
    catalog.interior_wall_type = find_wall_type(document, "Interior Wall");
    catalog.basic_wall_type = find_wall_type(document, "Basic Wall");
    catalog.exterior_glass_wall_type = find_wall_type(document, "Exterior Glass Wall");
    catalog.interior_glass_wall_type = find_wall_type(document, "Interior Glass Partition");
    catalog.concrete_core_wall_type = find_wall_type(document, "Concrete Core Wall");

    catalog.residential_floor_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Residential Floor");
    catalog.asphalt_floor_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Asphalt Surface");
    catalog.concrete_floor_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Concrete Floor");
    catalog.foundation_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Foundation Slab");
    catalog.showcase_foundation_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Showcase Foundation");
    catalog.ceiling_assembly = find_assembly(document, LayeredAssemblyKind::Ceiling, "Ceiling");
    catalog.roof_assembly = find_assembly(document, LayeredAssemblyKind::Roof, "Roof");
    catalog.stair_assembly = find_assembly(document, LayeredAssemblyKind::Stair, "Stair");
    catalog.wood_floor_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Wood Floor");
    catalog.paving_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Paved Walkway");
    catalog.grass_assembly = find_assembly(document, LayeredAssemblyKind::Floor, "Landscape Ground");
    return catalog;
}

DefaultProjectCatalog ensure_default_project_catalog(Document& document) {
    auto catalog = find_default_project_catalog(document);

    catalog.concrete_material = catalog.concrete_material != 0
        ? catalog.concrete_material
        : ensure_material(document, "Concrete", MaterialCategory::Structural, 2400.0, 110.0, "#8796A5", {"Template Concrete", "Showcase Concrete"});
    catalog.brick_material = catalog.brick_material != 0
        ? catalog.brick_material
        : ensure_material(document, "Brick", MaterialCategory::Structural, 1800.0, 90.0, "#B86B4B", {"Template Brick"});
    catalog.gypsum_material = catalog.gypsum_material != 0
        ? catalog.gypsum_material
        : ensure_material(document, "Gypsum Board", MaterialCategory::Finish, 850.0, 28.0, "#F0E6D2", {"Template Gypsum", "Showcase Gypsum"});
    catalog.insulation_material = catalog.insulation_material != 0
        ? catalog.insulation_material
        : ensure_material(document, "Insulation", MaterialCategory::Insulation, 35.0, 18.0, "#F1C453", {"Template Insulation", "Showcase Insulation"});
    catalog.screed_material = catalog.screed_material != 0
        ? catalog.screed_material
        : ensure_material(document, "Screed", MaterialCategory::Structural, 2100.0, 36.0, "#C8B79B", {"Template Screed"});
    catalog.laminate_material = catalog.laminate_material != 0
        ? catalog.laminate_material
        : ensure_material(document, "Laminate", MaterialCategory::Finish, 700.0, 42.0, "#A8733E", {"Template Laminate"});
    catalog.stair_tile_material = catalog.stair_tile_material != 0
        ? catalog.stair_tile_material
        : ensure_material(document, "Stair Tile", MaterialCategory::Finish, 2100.0, 36.0, "#D6A84A", {"Template Stair Tile", "Showcase Stair Tile"});
    catalog.glass_material = catalog.glass_material != 0
        ? catalog.glass_material
        : ensure_material(document, "Glass", MaterialCategory::Glass, 2500.0, 80.0, "#A8D8E8", {"Template Glass", "Showcase Glass"});
    catalog.aluminum_material = catalog.aluminum_material != 0
        ? catalog.aluminum_material
        : ensure_material(document, "Aluminum", MaterialCategory::Structural, 2700.0, 95.0, "#B9C6D2", {"Showcase Aluminum"});
    catalog.asphalt_material = catalog.asphalt_material != 0
        ? catalog.asphalt_material
        : ensure_material(document, "Asphalt", MaterialCategory::Structural, 2300.0, 32.0, "#3E4652", {"Asphalt Surface"});
    catalog.paving_material = catalog.paving_material != 0
        ? catalog.paving_material
        : ensure_material(document, "Paving Stone", MaterialCategory::Finish, 2200.0, 45.0, "#B8B2A6");
    catalog.grass_material = catalog.grass_material != 0
        ? catalog.grass_material
        : ensure_material(document, "Landscape Grass", MaterialCategory::Finish, 450.0, 12.0, "#6F9B62");
    catalog.timber_material = catalog.timber_material != 0
        ? catalog.timber_material
        : ensure_material(document, "Timber", MaterialCategory::Finish, 700.0, 42.0, "#B57A45", {"Showcase Timber Floor"});

    catalog.exterior_wall_type = catalog.exterior_wall_type != 0
        ? catalog.exterior_wall_type
        : ensure_wall_type(document, "Exterior Wall", {
            {.material_id = catalog.brick_material, .thickness_meters = 0.012, .function = WallLayerFunction::ExteriorFinish, .priority = 5},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.08, .function = WallLayerFunction::Insulation, .priority = 70},
            {.material_id = catalog.brick_material, .thickness_meters = 0.20, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
            {.material_id = catalog.gypsum_material, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish, .priority = 10},
        }, WallTypeCategory::Exterior);
    catalog.interior_wall_type = catalog.interior_wall_type != 0
        ? catalog.interior_wall_type
        : ensure_wall_type(document, "Interior Wall", {
            {.material_id = catalog.gypsum_material, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish, .priority = 10},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.05, .function = WallLayerFunction::Insulation, .priority = 70},
            {.material_id = catalog.gypsum_material, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish, .priority = 10},
        }, WallTypeCategory::Interior);
    catalog.basic_wall_type = catalog.basic_wall_type != 0
        ? catalog.basic_wall_type
        : ensure_wall_type(document, "Basic Wall", {
            {.material_id = catalog.brick_material, .thickness_meters = 0.20, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
        }, WallTypeCategory::Generic);
    catalog.exterior_glass_wall_type = catalog.exterior_glass_wall_type != 0
        ? catalog.exterior_glass_wall_type
        : ensure_wall_type(document, "Exterior Glass Wall", {
            {.material_id = catalog.glass_material, .thickness_meters = 0.12, .function = WallLayerFunction::Core, .priority = 100},
            {.material_id = catalog.aluminum_material, .thickness_meters = 0.04, .function = WallLayerFunction::ExteriorFinish, .priority = 10},
            {.material_id = catalog.gypsum_material, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish, .priority = 5},
        }, WallTypeCategory::Exterior);
    catalog.interior_glass_wall_type = catalog.interior_glass_wall_type != 0
        ? catalog.interior_glass_wall_type
        : ensure_wall_type(document, "Interior Glass Partition", {
            {.material_id = catalog.glass_material, .thickness_meters = 0.10, .function = WallLayerFunction::Core, .priority = 100},
        }, WallTypeCategory::Interior);
    catalog.concrete_core_wall_type = catalog.concrete_core_wall_type != 0
        ? catalog.concrete_core_wall_type
        : ensure_wall_type(document, "Concrete Core Wall", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.20, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
        }, WallTypeCategory::Generic);

    catalog.residential_floor_assembly = catalog.residential_floor_assembly != 0
        ? catalog.residential_floor_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Residential Floor", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.18, .function = WallLayerFunction::Core},
            {.material_id = catalog.screed_material, .thickness_meters = 0.05, .function = WallLayerFunction::Core},
            {.material_id = catalog.laminate_material, .thickness_meters = 0.012, .function = WallLayerFunction::InteriorFinish},
        });
    catalog.asphalt_floor_assembly = catalog.asphalt_floor_assembly != 0
        ? catalog.asphalt_floor_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Asphalt Surface", {
            {.material_id = catalog.asphalt_material, .thickness_meters = 0.08, .function = WallLayerFunction::ExteriorFinish},
        }, {"Asphalt Drive"});
    catalog.concrete_floor_assembly = catalog.concrete_floor_assembly != 0
        ? catalog.concrete_floor_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Concrete Floor", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.20, .function = WallLayerFunction::Core, .structural = true},
        });
    catalog.foundation_assembly = catalog.foundation_assembly != 0
        ? catalog.foundation_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Foundation Slab", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.25, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.08, .function = WallLayerFunction::Insulation, .priority = 70},
        });
    catalog.showcase_foundation_assembly = catalog.showcase_foundation_assembly != 0
        ? catalog.showcase_foundation_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Showcase Foundation", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.26, .function = WallLayerFunction::Core, .structural = true},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.08, .function = WallLayerFunction::Insulation},
        });
    catalog.ceiling_assembly = catalog.ceiling_assembly != 0
        ? catalog.ceiling_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Ceiling, "Ceiling", {
            {.material_id = catalog.gypsum_material, .thickness_meters = 0.015, .function = WallLayerFunction::InteriorFinish},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.04, .function = WallLayerFunction::Insulation},
        }, {"Residential Ceiling", "Showcase Ceiling"});
    catalog.roof_assembly = catalog.roof_assembly != 0
        ? catalog.roof_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Roof, "Roof", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.20, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
            {.material_id = catalog.insulation_material, .thickness_meters = 0.10, .function = WallLayerFunction::Insulation, .priority = 70},
        }, {"Residential Roof", "Showcase Flat Roof"});
    catalog.stair_assembly = catalog.stair_assembly != 0
        ? catalog.stair_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Stair, "Stair", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.16, .function = WallLayerFunction::Core, .priority = 100, .structural = true},
            {.material_id = catalog.stair_tile_material, .thickness_meters = 0.02, .function = WallLayerFunction::InteriorFinish, .priority = 10},
        }, {"Residential Stair", "Showcase Stair"});
    catalog.wood_floor_assembly = catalog.wood_floor_assembly != 0
        ? catalog.wood_floor_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Wood Floor", {
            {.material_id = catalog.concrete_material, .thickness_meters = 0.18, .function = WallLayerFunction::Core},
            {.material_id = catalog.timber_material, .thickness_meters = 0.018, .function = WallLayerFunction::InteriorFinish},
        }, {"Showcase Wood Floor"});
    catalog.paving_assembly = catalog.paving_assembly != 0
        ? catalog.paving_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Paved Walkway", {
            {.material_id = catalog.paving_material, .thickness_meters = 0.06, .function = WallLayerFunction::ExteriorFinish},
        });
    catalog.grass_assembly = catalog.grass_assembly != 0
        ? catalog.grass_assembly
        : ensure_assembly(document, LayeredAssemblyKind::Floor, "Landscape Ground", {
            {.material_id = catalog.grass_material, .thickness_meters = 0.12, .function = WallLayerFunction::ExteriorFinish},
        }, {"Landscape Lawn Ground"});
    return catalog;
}

} // namespace tbe::core
