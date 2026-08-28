#include "tbe/api/EngineApi.hpp"

#include "RuntimeSceneCache.hpp"

#include "tbe/core/Project.hpp"
#include "tbe/core/IfcExchange.hpp"
#include "tbe/core/JobSystem.hpp"
#include "tbe/core/PolygonTriangulation.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <limits>
#include <utility>

namespace tbe::api {

namespace {

inline constexpr std::string_view kEngineVersion = "TabletBimEngine 0.1.0";
inline constexpr std::string_view kCoreVersion = "tbe_core 0.1.0";
inline constexpr std::string_view kApiVersion = "tbe_api 0.1.0";

using tbe::core::Document;
using tbe::core::Element;
using tbe::core::ElementId;
using tbe::core::Line2;
using tbe::core::Point2;
using tbe::core::Point3;
using tbe::core::Project;
using tbe::core::UnitSettings;

ApiMaterialCategory to_api_material_category(tbe::core::MaterialCategory category);
ApiWallLayerFunction to_api_layer_function(tbe::core::WallLayerFunction function);
ApiWallLayerSide to_api_layer_side(tbe::core::WallLayerSide side);
ApiWallTypeCategory to_api_wall_type_category(tbe::core::WallTypeCategory category);

struct SessionTransaction {
    std::string name{};
    std::string before_json{};
    std::string after_json{};
};

struct JsonPatchResult {
    std::string json{};
    int changes{};
    std::vector<std::string> messages{};
};

struct SpatialEntry {
    ElementId element_id{};
    ElementId level_id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    HitKind preferred_hit_kind{HitKind::None};
    AABB2D bounds{};
    std::vector<Point2> polygon{};
    Line2 axis{};
    double thickness_meters{};
};

struct LevelSpatialIndex {
    std::vector<SpatialEntry> entries{};
    std::map<std::pair<int, int>, std::vector<std::size_t>> buckets{};
    double cell_size_meters{2.0};
};

bool is_non_clean(FreshnessState state) {
    return state == FreshnessState::Dirty || state == FreshnessState::Stale || state == FreshnessState::Failed;
}

bool has_cached_state(FreshnessState state) {
    return state == FreshnessState::Clean || state == FreshnessState::Stale;
}

std::size_t recommended_final_compute_workers() {
    // Keep one logical core available for Flutter/Filament and the OS. The
    // remaining read-only final jobs may run in parallel; cap the pool so a
    // large ARM CPU does not turn an explicit report/export into a thermal
    // spike. This is a compute budget, not a "two-core engine" limit.
    const auto logical_cores = std::max(1u, std::thread::hardware_concurrency());
    if (logical_cores <= 2u) {
        return 1;
    }
    return std::min<std::size_t>(4u, static_cast<std::size_t>(logical_cores - 1u));
}

Project make_residential_template(int building_count, int story_count) {
    if (building_count < 1 || building_count > 12 || story_count < 1 || story_count > 30) {
        throw std::invalid_argument("residential template supports 1-12 buildings and 1-30 stories");
    }

    const auto project_name = building_count == 1
        ? "9 Storey Residential Tower"
        : "Residential Campus";
    Project project{project_name};
    auto& document = project.active_document();
    // Calling auto_join for every one of hundreds of walls turns a template
    // import into an O(n^3) operation. The fixture has exact endpoints and
    // explicit roof source walls, so joins and room discovery can safely be
    // deferred until the user asks for final analysis.
    document.set_automatic_wall_join_enabled(false);

    const auto concrete = document.create_material("Template Concrete", tbe::core::MaterialCategory::Structural, 2400.0, 110.0, {}, "#8796A5");
    const auto masonry = document.create_material("Template Brick", tbe::core::MaterialCategory::Structural, 1800.0, 90.0, {}, "#B86B4B");
    const auto gypsum = document.create_material("Template Gypsum", tbe::core::MaterialCategory::Finish, 850.0, 28.0, {}, "#F0E6D2");
    const auto insulation = document.create_material("Template Insulation", tbe::core::MaterialCategory::Insulation, 35.0, 18.0, {}, "#F1C453");
    const auto screed = document.create_material("Template Screed", tbe::core::MaterialCategory::Structural, 2100.0, 36.0, {}, "#C8B79B");
    const auto laminate = document.create_material("Template Laminate", tbe::core::MaterialCategory::Finish, 700.0, 42.0, {}, "#A8733E");
    const auto tile = document.create_material("Template Stair Tile", tbe::core::MaterialCategory::Finish, 2100.0, 36.0, {}, "#D6A84A");
    const auto wall_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Wall, "Residential Wall", {
        tbe::core::WallAssemblyLayer{.material_id = masonry, .thickness_meters = 0.012, .function = tbe::core::WallLayerFunction::ExteriorFinish, .priority = 5},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.08, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
        tbe::core::WallAssemblyLayer{.material_id = masonry, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    });
    const auto exterior_wall_type = document.create_wall_type("Exterior Wall", {
        tbe::core::WallAssemblyLayer{.material_id = masonry, .thickness_meters = 0.012, .function = tbe::core::WallLayerFunction::ExteriorFinish, .priority = 5},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.08, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
        tbe::core::WallAssemblyLayer{.material_id = masonry, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    }, tbe::core::WallTypeCategory::Exterior);
    const auto interior_wall_type = document.create_wall_type("Interior Wall", {
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.05, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    }, tbe::core::WallTypeCategory::Interior);
    const auto generic_wall_type = document.create_wall_type("Generic Wall", {
        tbe::core::WallAssemblyLayer{.material_id = masonry, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Generic, .priority = 50, .structural = true},
    }, tbe::core::WallTypeCategory::Generic);
    const auto glass = document.create_material("Template Glass", tbe::core::MaterialCategory::Glass, 2500.0, 80.0, {}, "#A8D8E8");
    const auto exterior_glass_wall_type = document.create_wall_type("Exterior Glass Wall", {
        tbe::core::WallAssemblyLayer{.material_id = glass, .thickness_meters = 0.12, .function = tbe::core::WallLayerFunction::Core, .priority = 100},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.08, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    }, tbe::core::WallTypeCategory::Exterior);
    const auto interior_glass_wall_type = document.create_wall_type("Interior Glass Partition", {
        tbe::core::WallAssemblyLayer{.material_id = glass, .thickness_meters = 0.10, .function = tbe::core::WallLayerFunction::Core, .priority = 100},
    }, tbe::core::WallTypeCategory::Interior);
    const auto concrete_core_wall_type = document.create_wall_type("Concrete Core Wall", {
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
    }, tbe::core::WallTypeCategory::Generic);
    (void)wall_assembly;
    (void)generic_wall_type;
    (void)exterior_glass_wall_type;
    (void)interior_glass_wall_type;
    (void)concrete_core_wall_type;
    const auto floor_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Residential Floor", {
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.18, .function = tbe::core::WallLayerFunction::Core},
        tbe::core::WallAssemblyLayer{.material_id = screed, .thickness_meters = 0.05, .function = tbe::core::WallLayerFunction::Core},
        tbe::core::WallAssemblyLayer{.material_id = laminate, .thickness_meters = 0.012, .function = tbe::core::WallLayerFunction::InteriorFinish},
    });
    const auto foundation_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Floor, "Foundation Slab", {
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.25, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.08, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
    });
    const auto ceiling_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Ceiling, "Residential Ceiling", {
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.04, .function = tbe::core::WallLayerFunction::Insulation},
    });
    const auto roof_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Roof, "Residential Roof", {
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.20, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
        tbe::core::WallAssemblyLayer{.material_id = insulation, .thickness_meters = 0.10, .function = tbe::core::WallLayerFunction::Insulation, .priority = 70},
        tbe::core::WallAssemblyLayer{.material_id = gypsum, .thickness_meters = 0.015, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    });
    const auto stair_assembly = document.create_layered_assembly(tbe::core::LayeredAssemblyKind::Stair, "Residential Stair", {
        tbe::core::WallAssemblyLayer{.material_id = concrete, .thickness_meters = 0.16, .function = tbe::core::WallLayerFunction::Core, .priority = 100, .structural = true},
        tbe::core::WallAssemblyLayer{.material_id = tile, .thickness_meters = 0.02, .function = tbe::core::WallLayerFunction::InteriorFinish, .priority = 10},
    });

    std::vector<ElementId> levels;
    // Storeys are semantic building levels; the roof has its own level above
    // the last storey so it is visible and editable as Level N+1.
    levels.reserve(static_cast<std::size_t>(story_count + 1));
    for (int story = 0; story < story_count; ++story) {
        levels.push_back(document.create_level("Level " + std::to_string(story + 1), story * 3.2, 3.2));
    }
    const auto roof_level_id = document.create_level(
        "Level " + std::to_string(story_count + 1) + " (Roof)",
        story_count * 3.2,
        3.2
    );

    constexpr double width = 12.0;
    constexpr double depth = 8.0;
    constexpr double building_pitch_x = 18.0;
    constexpr double building_pitch_y = 15.0;
    for (int building = 0; building < building_count; ++building) {
        const auto origin_x = static_cast<double>(building % 3) * building_pitch_x;
        const auto origin_y = static_cast<double>(building / 3) * building_pitch_y;
        // Deliberately use an orthogonal L-shaped residential footprint in
        // the bundled engine template. This exercises wall-loop ordering,
        // rooms, layered floors/ceilings and the automatic footprint roof on
        // the first screen instead of hiding those paths behind a rectangle.
        const std::vector<Point2> footprint{
            {.x = origin_x, .y = origin_y},
            {.x = origin_x + width, .y = origin_y},
            {.x = origin_x + width, .y = origin_y + depth * 0.5},
            {.x = origin_x + width * 0.58, .y = origin_y + depth * 0.5},
            {.x = origin_x + width * 0.58, .y = origin_y + depth},
            {.x = origin_x, .y = origin_y + depth},
        };
        // One foundation belongs to the building, not to every storey. Its
        // top is aligned with Level 1; ordinary storeys get their own floor
        // slab below.
        document.create_slab(
            levels.front(),
            footprint,
            0.33,
            concrete,
            foundation_assembly,
            -0.33
        );
        std::vector<ElementId> top_perimeter;
        for (int story = 0; story < story_count; ++story) {
            const auto level_id = levels[static_cast<std::size_t>(story)];
            std::vector<ElementId> perimeter;
            perimeter.reserve(footprint.size());
            for (std::size_t edge = 0; edge < footprint.size(); ++edge) {
                const auto wall_id = document.create_wall(
                    "Building " + std::to_string(building + 1) + " exterior wall",
                    Line2{.start = footprint[edge], .end = footprint[(edge + 1) % footprint.size()]},
                    0.24,
                    3.2,
                    level_id
                );
                document.set_wall_type(wall_id, exterior_wall_type);
                if (story + 1 < story_count) {
                    document.set_wall_level_constraints(wall_id, level_id, levels[static_cast<std::size_t>(story + 1)], 0.0, 0.0, tbe::core::WallHeightMode::TopLevel);
                }
                perimeter.push_back(wall_id);
            }
            const auto partition_id = document.create_wall(
                "Building " + std::to_string(building + 1) + " apartment partition",
                Line2{.start = {.x = origin_x + width * 0.5, .y = origin_y}, .end = {.x = origin_x + width * 0.5, .y = origin_y + depth}},
                0.16,
                3.2,
                level_id
            );
            document.set_wall_type(partition_id, interior_wall_type);
            if (story + 1 < story_count) {
                document.set_wall_level_constraints(partition_id, level_id, levels[static_cast<std::size_t>(story + 1)], 0.0, 0.0, tbe::core::WallHeightMode::TopLevel);
            }
            // Two real apartment circulation doors keep both wings usable;
            // 0.90 x 2.10 m matches a common residential interior opening.
            document.create_door("Apartment hall door A", partition_id, 2.0, 0.90, 2.10);
            document.create_door("Apartment hall door B", partition_id, 6.0, 0.90, 2.10);
            // A realistic authoring / renderer stress fixture needs more
            // than an empty shell. These repeated apartment cores exercise
            // openings, stairs, columns and beams while retaining level
            // ownership and deterministic geometry.
            for (const auto fraction : {0.25, 0.75}) {
                const auto cross_end_x = fraction > 0.5
                    ? origin_x + width * 0.58
                    : origin_x + width;
                const auto horizontal = document.create_wall(
                    "Building " + std::to_string(building + 1) + " apartment cross partition",
                    Line2{.start = {.x = origin_x, .y = origin_y + depth * fraction}, .end = {.x = cross_end_x, .y = origin_y + depth * fraction}},
                    0.12,
                    3.2,
                    level_id
                );
                document.set_wall_type(horizontal, interior_wall_type);
                if (story + 1 < story_count) {
                    document.set_wall_level_constraints(horizontal, level_id, levels[static_cast<std::size_t>(story + 1)], 0.0, 0.0, tbe::core::WallHeightMode::TopLevel);
                }
                document.create_door("Apartment cross-room door", horizontal, 3.0, 0.82, 2.10);
            }
            for (const auto fraction : {0.25, 0.75}) {
                const auto room_end_y = fraction > 0.58
                    ? origin_y + depth * 0.5
                    : origin_y + depth;
                const auto vertical = document.create_wall(
                    "Building " + std::to_string(building + 1) + " apartment room partition",
                    Line2{.start = {.x = origin_x + width * fraction, .y = origin_y}, .end = {.x = origin_x + width * fraction, .y = room_end_y}},
                    0.12,
                    3.2,
                    level_id
                );
                document.set_wall_type(vertical, interior_wall_type);
                if (story + 1 < story_count) {
                    document.set_wall_level_constraints(vertical, level_id, levels[static_cast<std::size_t>(story + 1)], 0.0, 0.0, tbe::core::WallHeightMode::TopLevel);
                }
                document.create_door("Apartment room door", vertical, 2.0, 0.82, 2.10);
            }
            for (const auto xFraction : {0.25, 0.75}) {
                for (const auto yFraction : {0.25, 0.75}) {
                    document.create_column(level_id, {.x = origin_x + width * xFraction, .y = origin_y + depth * yFraction}, 0.28, 0.28, 3.2, concrete);
                }
            }
            document.create_beam(level_id, {.x = origin_x, .y = origin_y + depth * 0.5}, {.x = origin_x + width, .y = origin_y + depth * 0.5}, 0.24, 0.42, concrete);
            document.create_beam(level_id, {.x = origin_x + width * 0.5, .y = origin_y}, {.x = origin_x + width * 0.5, .y = origin_y + depth}, 0.24, 0.42, concrete);
            if (story + 1 < story_count) {
                document.create_stair(level_id, levels[static_cast<std::size_t>(story + 1)], {.x = origin_x + width * 0.58, .y = origin_y + 0.45}, {.x = 0.0, .y = 1.0}, 1.1, 3.2, 3.9, 18, 17, concrete, stair_assembly);
            }
            document.create_door("Apartment entry A", perimeter.front(), 2.0, 0.9, 2.1);
            document.create_door("Apartment entry B", perimeter[2], 2.0, 0.9, 2.1);
            document.create_window("Living window A", perimeter[1], 1.2, 1.0, 1.2, 0.9);
            document.create_window("Living window B", perimeter[1], 2.8, 1.0, 1.2, 0.9);
            document.create_window("Living window C", perimeter[3], 1.2, 1.0, 1.2, 0.9);
            document.create_window("Living window D", perimeter[3], 2.8, 1.0, 1.2, 0.9);
            document.create_window("Bedroom window A", perimeter[0], 4.0, 1.0, 1.2, 1.0);
            document.create_window("Bedroom window B", perimeter[2], 4.0, 1.0, 1.2, 1.0);
            document.create_slab(
                level_id,
                footprint,
                0.242,
                concrete,
                floor_assembly,
                0.0
            );
            document.create_ceiling_system_from_profile(level_id, footprint, ceiling_assembly, 2.85);
            if (story + 1 == story_count) {
                top_perimeter = perimeter;
            }
        }
        // The starter model demonstrates the same automatic footprint path
        // used by authoring: an L-shaped boundary, slope and overhang are
        // resolved in the C++ engine and remain linked to source walls.
        document.create_roof(roof_level_id, footprint, tbe::core::RoofType::AutoFootprint, 0.20, concrete, roof_assembly, 25.0, 0.50, std::move(top_perimeter));
    }
    // Resolve the template's perimeter and partition intersections once all
    // walls exist.  This gives the starter buildings real mitered/corner
    // joins while avoiding repeated work during creation of each wall.
    document.auto_join_walls();
    document.set_automatic_wall_join_enabled(true);
    document.clear_dirty_room_requests();
    document.regenerate_dirty_geometry(tbe::core::GeometryDetail::Envelope);
    return project;
}

double distance(Point2 left, Point2 right) {
    const auto dx = left.x - right.x;
    const auto dy = left.y - right.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

double clamp(double value, double min_value, double max_value) {
    return std::max(min_value, std::min(value, max_value));
}

double line_length(Line2 line) {
    return distance(line.start, line.end);
}

bool near_zero(double value) {
    return std::abs(value) < 1.0e-9;
}

double distance_point_to_segment(Point2 point, Line2 line, double* out_param = nullptr, Point2* out_projected = nullptr) {
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    const auto length_squared = (dx * dx) + (dy * dy);
    if (length_squared <= 1.0e-12) {
        if (out_param != nullptr) {
            *out_param = 0.0;
        }
        if (out_projected != nullptr) {
            *out_projected = line.start;
        }
        return distance(point, line.start);
    }
    const auto t = clamp((((point.x - line.start.x) * dx) + ((point.y - line.start.y) * dy)) / length_squared, 0.0, 1.0);
    const auto projected = Point2{.x = line.start.x + (dx * t), .y = line.start.y + (dy * t)};
    if (out_param != nullptr) {
        *out_param = t;
    }
    if (out_projected != nullptr) {
        *out_projected = projected;
    }
    return distance(point, projected);
}

bool point_in_polygon(Point2 point, const std::vector<Point2>& polygon) {
    if (polygon.size() < 3) {
        return false;
    }
    auto inside = false;
    for (std::size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
        const auto intersects = ((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
            (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / ((polygon[j].y - polygon[i].y) + 1.0e-12) + polygon[i].x);
        if (intersects) {
            inside = !inside;
        }
    }
    return inside;
}

AABB2D bounds_from_points(const std::vector<Point2>& points) {
    AABB2D bounds{};
    if (points.empty()) {
        return bounds;
    }
    bounds.min_x = bounds.max_x = points.front().x;
    bounds.min_y = bounds.max_y = points.front().y;
    for (const auto& point : points) {
        bounds.min_x = std::min(bounds.min_x, point.x);
        bounds.min_y = std::min(bounds.min_y, point.y);
        bounds.max_x = std::max(bounds.max_x, point.x);
        bounds.max_y = std::max(bounds.max_y, point.y);
    }
    return bounds;
}

std::vector<Point2> wall_body_polygon(Line2 axis, double thickness_meters) {
    const auto length_value = line_length(axis);
    if (length_value <= 1.0e-12) {
        return {};
    }
    const auto direction = Point2{.x = (axis.end.x - axis.start.x) / length_value, .y = (axis.end.y - axis.start.y) / length_value};
    const auto normal = Point2{.x = -direction.y * (thickness_meters / 2.0), .y = direction.x * (thickness_meters / 2.0)};
    return {
        Point2{.x = axis.start.x + normal.x, .y = axis.start.y + normal.y},
        Point2{.x = axis.end.x + normal.x, .y = axis.end.y + normal.y},
        Point2{.x = axis.end.x - normal.x, .y = axis.end.y - normal.y},
        Point2{.x = axis.start.x - normal.x, .y = axis.start.y - normal.y},
    };
}

int hit_priority(HitKind kind) {
    switch (kind) {
    case HitKind::Opening: return 10;
    case HitKind::Column: return 15;
    case HitKind::Stair: return 16;
    case HitKind::WallBody: return 20;
    case HitKind::Beam: return 22;
    case HitKind::WallAxis: return 30;
    case HitKind::FloorSystem: return 40;
    case HitKind::CeilingSystem: return 41;
    case HitKind::Slab: return 42;
    case HitKind::Roof: return 45;
    case HitKind::RoomInterior: return 100;
    case HitKind::None: return 1000;
    }
    return 1000;
}

int snap_priority(SnapType type) {
    switch (type) {
    case SnapType::Endpoint: return 10;
    case SnapType::WallIntersection: return 11;
    case SnapType::RoomCorner: return 12;
    case SnapType::Midpoint: return 20;
    case SnapType::OrthogonalProjection: return 30;
    case SnapType::WallAxis: return 35;
    case SnapType::Grid: return 50;
    case SnapType::None: return 1000;
    }
    return 1000;
}

ApiStatus status_from_exception(const std::exception& error) {
    if (dynamic_cast<const std::invalid_argument*>(&error) != nullptr) {
        return ApiStatus::InvalidArgument;
    }
    return ApiStatus::InternalError;
}

ElementIdDTO to_id(ElementId id) {
    return ElementIdDTO{.value = id};
}

Vec2 to_vec2(Point2 point) {
    return Vec2{.x = point.x, .y = point.y};
}

std::vector<Vec2> to_vec2_list(const std::vector<Point2>& points) {
    std::vector<Vec2> values;
    values.reserve(points.size());
    for (const auto& point : points) {
        values.push_back(to_vec2(point));
    }
    return values;
}

Vec3 to_vec3(Point3 point) {
    return Vec3{.x = point.x, .y = point.y, .z = point.z};
}

AABB3D make_bounds3d(const std::vector<Vec3>& positions) {
    AABB3D bounds{};
    if (positions.empty()) {
        return bounds;
    }
    bounds.min = bounds.max = positions.front();
    for (const auto& point : positions) {
        bounds.min.x = std::min(bounds.min.x, point.x);
        bounds.min.y = std::min(bounds.min.y, point.y);
        bounds.min.z = std::min(bounds.min.z, point.z);
        bounds.max.x = std::max(bounds.max.x, point.x);
        bounds.max.y = std::max(bounds.max.y, point.y);
        bounds.max.z = std::max(bounds.max.z, point.z);
    }
    return bounds;
}

bool is_finite_vec3(Vec3 point) {
    return std::isfinite(point.x) && std::isfinite(point.y) && std::isfinite(point.z);
}

double safe_value(double value) {
    return std::isfinite(value) ? value : 0.0;
}

std::string escape_json(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const auto character : value) {
        switch (character) {
        case '\\': escaped += "\\\\"; break;
        case '"': escaped += "\\\""; break;
        case '\b': escaped += "\\b"; break;
        case '\f': escaped += "\\f"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (static_cast<unsigned char>(character) < 0x20) {
                escaped += "\\u00";
                const auto value_byte = static_cast<unsigned char>(character);
                const char* digits = "0123456789abcdef";
                escaped.push_back(digits[(value_byte >> 4) & 0x0f]);
                escaped.push_back(digits[value_byte & 0x0f]);
            } else {
                escaped.push_back(character);
            }
            break;
        }
    }
    return escaped;
}

std::string api_kind_name(ApiElementKind kind) {
    switch (kind) {
    case ApiElementKind::Level: return "Level";
    case ApiElementKind::Wall: return "Wall";
    case ApiElementKind::Door: return "Door";
    case ApiElementKind::Window: return "Window";
    case ApiElementKind::Room: return "Room";
    case ApiElementKind::Slab: return "Slab";
    case ApiElementKind::FloorSystem: return "FloorSystem";
    case ApiElementKind::CeilingSystem: return "CeilingSystem";
    case ApiElementKind::Roof: return "Roof";
    case ApiElementKind::Column: return "Column";
    case ApiElementKind::Beam: return "Beam";
    case ApiElementKind::Stair: return "Stair";
    case ApiElementKind::Proxy: return "Proxy";
    case ApiElementKind::Unknown: return "Unknown";
    }
    return "Unknown";
}

std::string material_category_name(ApiElementKind kind) {
    switch (kind) {
    case ApiElementKind::Window: return "glass";
    case ApiElementKind::Door: return "generic";
    case ApiElementKind::Wall:
    case ApiElementKind::Slab:
    case ApiElementKind::FloorSystem:
    case ApiElementKind::CeilingSystem:
    case ApiElementKind::Roof:
    case ApiElementKind::Column:
    case ApiElementKind::Beam:
    case ApiElementKind::Stair:
    case ApiElementKind::Proxy:
        return "structural";
    case ApiElementKind::Level:
    case ApiElementKind::Room:
    case ApiElementKind::Unknown:
        return "generic";
    }
    return "generic";
}

std::vector<Vec3> mesh_positions(const tbe::core::MeshBuffer& mesh) {
    std::vector<Vec3> positions;
    positions.reserve(mesh.vertices.size());
    for (const auto& vertex : mesh.vertices) {
        positions.push_back(to_vec3(vertex));
    }
    return positions;
}

enum class RenderSceneDetail {
    Interactive,
    Exact,
};

// The primary stage is intentionally architectural: it contains the objects
// needed to frame and navigate a project immediately. Secondary coordination
// objects are requested by the normal scene query after the first frame is
// already visible. The source Document is never changed by this filter.
enum class RenderSceneStage {
    Primary,
    Full,
};

bool has_exact_ifc_geometry(const Element& element) {
    const auto found = element.metadata().find("ifc_exact_geometry");
    return found != element.metadata().end() && found->second.value == "true";
}

std::string_view ifc_entity_type(const Element& element) {
    const auto found = element.metadata().find("ifc_entity");
    return found == element.metadata().end() ? std::string_view{} : found->second.value;
}

bool is_small_ifc_detail_proxy(const Element& element) {
    if (!element.proxy() || !has_exact_ifc_geometry(element)) return false;

    const auto type = ifc_entity_type(element);
    // These categories are useful for coordination and selection, but their
    // dense source meshes should not determine the architectural viewport
    // budget. The exact meshes remain in the document JSON and IFC export.
    if (type == "IFCFURNISHINGELEMENT" || type == "IFCFURNITURE" ||
        type == "IFCRAILING" || type == "IFCFASTENER" ||
        type == "IFCMECHANICALFASTENER" || type == "IFCDISCRETEACCESSORY" ||
        type == "IFCELECTRICAPPLIANCE" || type == "IFCFLOWSEGMENT" ||
        type == "IFCFLOWFITTING" || type == "IFCFLOWTERMINAL" ||
        type == "IFCOPENINGELEMENT" ||
        type == "IFCFLOWCONTROLLER" || type == "IFCFLOWMOVINGDEVICE" ||
        type == "IFCFLOWSTORAGEDEVICE" || type == "IFCFLOWTREATMENTDEVICE" ||
        type == "IFCFLOWINSTRUMENT" || type == "IFCDISTRIBUTIONELEMENT" ||
        type == "IFCDISTRIBUTIONFLOWELEMENT" || type == "IFCDISTRIBUTIONCONTROLELEMENT" ||
        type == "IFCENERGYCONVERSIONDEVICE" || type == "IFCMOTORCONNECTION" ||
        type == "IFCLIGHTFIXTURE" || type == "IFCSENSOR" ||
        type == "IFCSANITARYTERMINAL" || type == "IFCSPACEHEATER" ||
        type == "IFCUNITARYEQUIPMENT" || type == "IFCVEHICLE") {
        return true;
    }

    // Generic proxies are ambiguous. Only small ones are treated as detail;
    // large structural/architectural proxies stay exact by default.
    if (type != "IFCBUILDINGELEMENTPROXY") return false;
    const auto* proxy = element.proxy();
    const auto largest_dimension = std::max({
        proxy->width_meters,
        proxy->depth_meters,
        proxy->height_meters,
    });
    return largest_dimension > 0.0 && largest_dimension <= 2.5;
}

bool is_runtime_hidden_ifc_proxy(const Element& element, RenderSceneDetail detail) {
    // IFCOPENINGELEMENT describes a void/cutter, not a visible architectural
    // object. IFC spatial containers are likewise coordination metadata: some
    // exporters attach a site/building envelope to them, and drawing that
    // envelope in the interactive viewport produces a giant box around the
    // actual building. Keep all of them in the exact document/IFC round trip,
    // but do not turn their container bounds into viewport geometry.
    if (detail != RenderSceneDetail::Interactive || element.proxy() == nullptr) return false;
    const auto type = ifc_entity_type(element);
    return type == "IFCOPENINGELEMENT" ||
        type == "IFCPROJECT" ||
        type == "IFCSITE" ||
        type == "IFCBUILDING";
}

RenderSceneMeshDTO mesh_dto_from_mesh_buffer(
    const tbe::core::MeshBuffer& mesh,
    double z_offset = 0.0,
    std::size_t triangle_budget = 0
) {
    RenderSceneMeshDTO dto;
    const auto triangle_count = mesh.indices.size() / 3;
    if (triangle_budget == 0 || triangle_count <= triangle_budget) {
        dto.positions = mesh_positions(mesh);
        if (z_offset != 0.0) {
            for (auto& point : dto.positions) {
                point.z += z_offset;
            }
        }
        dto.indices = mesh.indices;
        dto.triangle_material_ids = mesh.triangle_material_ids;
        return dto;
    }

    // Runtime LOD is deliberately deterministic and preserves the six
    // coordinate extremes before uniform sampling. This keeps the object's
    // culling/fit envelope stable while dropping dense IFC tessellation. The
    // source MeshBuffer is never modified, so project save/export remains exact.
    std::array<std::size_t, 6> extreme_vertices{};
    std::array<double, 6> extreme_values{
        std::numeric_limits<double>::max(),
        std::numeric_limits<double>::lowest(),
        std::numeric_limits<double>::max(),
        std::numeric_limits<double>::lowest(),
        std::numeric_limits<double>::max(),
        std::numeric_limits<double>::lowest(),
    };
    for (std::size_t vertex_index = 0; vertex_index < mesh.vertices.size(); ++vertex_index) {
        const auto& vertex = mesh.vertices[vertex_index];
        const std::array<double, 6> values{
            vertex.x, vertex.x, vertex.y, vertex.y, vertex.z, vertex.z,
        };
        for (std::size_t axis = 0; axis < values.size(); ++axis) {
            const bool lower = axis % 2 == 0;
            if ((lower && values[axis] < extreme_values[axis]) ||
                (!lower && values[axis] > extreme_values[axis])) {
                extreme_values[axis] = values[axis];
                extreme_vertices[axis] = vertex_index;
            }
        }
    }

    std::vector<bool> selected_triangles(triangle_count, false);
    const auto select_triangle = [&](std::size_t triangle_index) {
        if (triangle_index < selected_triangles.size()) selected_triangles[triangle_index] = true;
    };
    for (const auto extreme_vertex : extreme_vertices) {
        for (std::size_t triangle_index = 0; triangle_index < triangle_count; ++triangle_index) {
            const auto offset = triangle_index * 3;
            if (mesh.indices[offset] == extreme_vertex ||
                mesh.indices[offset + 1] == extreme_vertex ||
                mesh.indices[offset + 2] == extreme_vertex) {
                select_triangle(triangle_index);
                break;
            }
        }
    }
    const auto stride = std::max<std::size_t>(1, (triangle_count + triangle_budget - 1) / triangle_budget);
    for (std::size_t triangle_index = 0; triangle_index < triangle_count; triangle_index += stride) {
        select_triangle(triangle_index);
    }
    select_triangle(triangle_count - 1);

    const auto invalid_index = std::numeric_limits<std::uint32_t>::max();
    std::vector<std::uint32_t> remap(mesh.vertices.size(), invalid_index);
    const auto append_vertex = [&](std::uint32_t source_index) {
        if (source_index >= mesh.vertices.size()) return invalid_index;
        auto& mapped = remap[source_index];
        if (mapped == invalid_index) {
            mapped = static_cast<std::uint32_t>(dto.positions.size());
            auto point = to_vec3(mesh.vertices[source_index]);
            point.z += z_offset;
            dto.positions.push_back(point);
        }
        return mapped;
    };
    for (std::size_t triangle_index = 0; triangle_index < triangle_count; ++triangle_index) {
        if (!selected_triangles[triangle_index]) continue;
        const auto offset = triangle_index * 3;
        const auto first = append_vertex(mesh.indices[offset]);
        const auto second = append_vertex(mesh.indices[offset + 1]);
        const auto third = append_vertex(mesh.indices[offset + 2]);
        if (first == invalid_index || second == invalid_index || third == invalid_index) continue;
        dto.indices.insert(dto.indices.end(), {first, second, third});
        if (triangle_index < mesh.triangle_material_ids.size()) {
            dto.triangle_material_ids.push_back(mesh.triangle_material_ids[triangle_index]);
        }
    }
    return dto;
}

std::size_t interactive_triangle_budget(
    const Element& element,
    const tbe::core::MeshBuffer& mesh,
    RenderSceneDetail detail
) {
    constexpr std::size_t kDetailTriangleBudget = 128;
    if (detail == RenderSceneDetail::Exact || !is_small_ifc_detail_proxy(element)) return 0;
    const auto budget = kDetailTriangleBudget;
    return mesh.indices.size() / 3 > budget
        ? budget
        : 0;
}

RenderSceneMeshDTO make_flat_polygon_mesh(const std::vector<tbe::core::Point2>& polygon, double z, double thickness = 0.02) {
    RenderSceneMeshDTO dto;
    if (polygon.size() < 3) {
        return dto;
    }
    dto.positions.reserve(polygon.size() * 2);
    for (const auto& point : polygon) {
        dto.positions.push_back(Vec3{.x = point.x, .y = point.y, .z = z});
    }
    for (const auto& point : polygon) {
        dto.positions.push_back(Vec3{.x = point.x, .y = point.y, .z = z + thickness});
    }
    const auto top_triangles = tbe::core::triangulate_simple_polygon(polygon);
    for (std::size_t index = 0; index + 2 < top_triangles.size(); index += 3) {
        const auto first = top_triangles[index];
        const auto second = top_triangles[index + 1];
        const auto third = top_triangles[index + 2];
        dto.indices.push_back(first);
        dto.indices.push_back(second);
        dto.indices.push_back(third);
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size() + third));
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size() + second));
        dto.indices.push_back(static_cast<std::uint32_t>(polygon.size() + first));
    }
    return dto;
}

RenderSceneMeshDTO make_opening_mesh(const tbe::core::Line2& axis, const tbe::core::HostedOpening& opening, double wall_thickness, double z_offset = 0.0) {
    RenderSceneMeshDTO dto;
    const auto dx = axis.end.x - axis.start.x;
    const auto dy = axis.end.y - axis.start.y;
    const auto length = std::sqrt((dx * dx) + (dy * dy));
    if (length <= 1.0e-9 || opening.width_meters <= 0.0 || opening.height_meters <= 0.0 || wall_thickness <= 0.0) {
        return dto;
    }
    const auto ux = dx / length;
    const auto uy = dy / length;
    const auto nx = -uy;
    const auto ny = ux;
    const auto center_x = axis.start.x + (ux * opening.offset_meters);
    const auto center_y = axis.start.y + (uy * opening.offset_meters);
    const auto sill = safe_value(opening.sill_height_meters);
    const auto width = opening.width_meters;
    const auto height = opening.height_meters;
    const auto half_width = width / 2.0;

    // Hosted openings intentionally stay a single selectable render object,
    // but their mesh is no longer a featureless box. Four perimeter bars form
    // a visible frame and the inset centre becomes either a door leaf or a
    // thin window pane. This keeps the existing material/edge pipeline and
    // therefore cannot change the frozen wall Solid/Shaded contract.
    const auto frame = std::clamp(std::min(width, height) * 0.075, 0.045, 0.12);
    // Project the frame a few centimetres beyond each wall face. At 0.90x the
    // wall depth the Filament depth pass could hide the front of the bars,
    // leaving only their edge batch visible in Solid mode.
    const auto frame_depth = std::max(0.06, wall_thickness * 1.08);
    const auto frame_half_depth = frame_depth / 2.0;
    const auto inner_half_width = std::max(0.01, half_width - frame);
    const auto inner_half_height = std::max(0.01, (height / 2.0) - frame);
    const auto centre_z = sill + (height / 2.0);

    const auto append_box = [&](double centre_u,
                                double centre_n,
                                double centre_v,
                                double half_u,
                                double half_n,
                                double half_v) {
        const auto base_index = static_cast<std::uint32_t>(dto.positions.size());
        const auto point = [&](double u, double n, double v) {
            return Vec3{
                .x = center_x + (ux * u) + (nx * n),
                .y = center_y + (uy * u) + (ny * n),
                .z = z_offset + centre_z + v,
            };
        };
        const auto corners = std::array<Vec3, 8>{
            point(centre_u - half_u, centre_n - half_n, centre_v - half_v),
            point(centre_u + half_u, centre_n - half_n, centre_v - half_v),
            point(centre_u + half_u, centre_n + half_n, centre_v - half_v),
            point(centre_u - half_u, centre_n + half_n, centre_v - half_v),
            point(centre_u - half_u, centre_n - half_n, centre_v + half_v),
            point(centre_u + half_u, centre_n - half_n, centre_v + half_v),
            point(centre_u + half_u, centre_n + half_n, centre_v + half_v),
            point(centre_u - half_u, centre_n + half_n, centre_v + half_v),
        };
        dto.positions.insert(dto.positions.end(), corners.begin(), corners.end());
        const auto append_triangle = [&](std::uint32_t first,
                                          std::uint32_t second,
                                          std::uint32_t third) {
            dto.indices.push_back(base_index + first);
            dto.indices.push_back(base_index + second);
            dto.indices.push_back(base_index + third);
        };
        append_triangle(0, 1, 2);
        append_triangle(0, 2, 3);
        append_triangle(4, 6, 5);
        append_triangle(4, 7, 6);
        append_triangle(0, 4, 5);
        append_triangle(0, 5, 1);
        append_triangle(1, 5, 6);
        append_triangle(1, 6, 2);
        append_triangle(2, 6, 7);
        append_triangle(2, 7, 3);
        append_triangle(3, 7, 4);
        append_triangle(3, 4, 0);
    };

    // The frame runs almost through the host wall, so it remains readable
    // from either side and does not disappear behind an opaque wall face.
    append_box(-half_width + (frame / 2.0), 0.0, 0.0, frame / 2.0, frame_half_depth, height / 2.0);
    append_box(half_width - (frame / 2.0), 0.0, 0.0, frame / 2.0, frame_half_depth, height / 2.0);
    append_box(0.0, 0.0, -(height / 2.0) + (frame / 2.0), inner_half_width, frame_half_depth, frame / 2.0);
    append_box(0.0, 0.0, (height / 2.0) - (frame / 2.0), inner_half_width, frame_half_depth, frame / 2.0);

    if (opening.kind == tbe::core::OpeningKind::Window) {
        // A thin pane sits between the perimeter bars. Window material is
        // already transparent in both Solid and Shaded, so the centre reads
        // as glass without introducing a second renderable or a new pipeline.
        const auto glass_half_depth = std::max(0.012, wall_thickness * 0.045);
        append_box(0.0, 0.0, 0.0, inner_half_width, glass_half_depth, inner_half_height);
    } else {
        // Doors remain opaque architectural leaves, with a shallow inset that
        // reads as a panel inside the frame instead of the old plain block.
        const auto panel_half_depth = std::max(0.025, wall_thickness * 0.28);
        append_box(0.0, 0.0, 0.0, inner_half_width, panel_half_depth, inner_half_height);
    }
    return dto;
}

std::map<ElementId, double> level_elevation_map(const Document& document) {
    std::map<ElementId, double> elevations;
    for (const auto& element : document.elements()) {
        if (const auto* level = element.level(); level != nullptr) {
            elevations[element.id()] = safe_value(level->elevation_meters);
        }
    }
    return elevations;
}

double level_elevation(const std::map<ElementId, double>& levels, ElementId level_id, double fallback = 0.0) {
    const auto found = levels.find(level_id);
    return found == levels.end() ? fallback : found->second;
}

double resolved_wall_base_elevation(const tbe::core::WallData& wall, const std::map<ElementId, double>& levels) {
    const auto level_id = wall.base_level_id != 0 ? wall.base_level_id : wall.level_id;
    return level_elevation(levels, level_id, 0.0) + wall.base_offset_meters;
}

double resolved_wall_height(const tbe::core::WallData& wall, const std::map<ElementId, double>& levels) {
    if (wall.height_mode == tbe::core::WallHeightMode::TopLevel && wall.top_level_id != 0) {
        const auto top = level_elevation(levels, wall.top_level_id, 0.0) + wall.top_offset_meters;
        return std::max(0.01, top - resolved_wall_base_elevation(wall, levels));
    }
    return std::max(0.01, wall.height_meters);
}

RenderSceneObjectDTO make_object_dto(
    ElementId element_id,
    ApiElementKind kind,
    ElementId level_id,
    std::uint64_t revision,
    RenderSceneMeshDTO mesh,
    std::string material_category,
    std::map<std::string, std::string> metadata = {},
    bool selectable = true,
    bool visible_by_default = true
) {
    RenderSceneObjectDTO object;
    object.element_id = to_id(element_id);
    object.kind = kind;
    object.level_id = to_id(level_id);
    object.selectable = selectable;
    object.visible_by_default = visible_by_default;
    object.revision = revision;
    object.mesh = std::move(mesh);
    object.material_category = std::move(material_category);
    object.metadata = std::move(metadata);
    object.bounds = make_bounds3d(object.mesh.positions);
    return object;
}

// Layer assemblies are deliberately sent as compact semantic metadata. The
// viewport can draw a plan cut/pattern from this profile without receiving a
// separate mesh for every layer and without duplicating the profile for each
// triangle.
std::string layer_profile(const std::vector<tbe::core::WallAssemblyLayer>& layers) {
    std::ostringstream profile;
    profile << std::setprecision(12);
    for (std::size_t index = 0; index < layers.size(); ++index) {
        if (index != 0) {
            profile << ';';
        }
        const auto& layer = layers[index];
        profile << layer.material_id << ':' << layer.thickness_meters;
    }
    return profile.str();
}

std::string wall_layer_profile(const Document& document, const tbe::core::WallData& wall) {
    if (wall.assembly_id != 0) {
        const auto* assembly = document.get_layered_assembly(wall.assembly_id);
        return assembly == nullptr ? std::string{} : layer_profile(assembly->layers);
    }
    if (wall.wall_type_id != 0) {
        const auto* wall_type = document.get_wall_type(wall.wall_type_id);
        return wall_type == nullptr ? std::string{} : layer_profile(wall_type->layers);
    }
    return {};
}

// GeometryService has already resolved end-to-end mitres and T-junction
// trims by the time a render scene is built. Keep those final plan profile
// corners available to the tablet authoring layer so boundary snapping uses
// the same visible join geometry as the wall mesh.
std::string wall_profile_corners(const tbe::core::WallData& wall) {
    const auto dx = wall.axis.end.x - wall.axis.start.x;
    const auto dy = wall.axis.end.y - wall.axis.start.y;
    const auto length = std::sqrt((dx * dx) + (dy * dy));
    if (length <= 1.0e-9 || wall.geometry.profile.polygon.empty()) {
        return {};
    }

    const auto direction_x = dx / length;
    const auto direction_y = dy / length;
    const auto perpendicular_x = -direction_y;
    const auto perpendicular_y = direction_x;
    std::ostringstream profile;
    profile << std::setprecision(12);
    for (std::size_t index = 0; index < wall.geometry.profile.polygon.size(); ++index) {
        if (index != 0) {
            profile << ';';
        }
        const auto& point = wall.geometry.profile.polygon[index];
        const auto world_x = wall.axis.start.x + (point.x * direction_x) + (point.y * perpendicular_x);
        const auto world_y = wall.axis.start.y + (point.x * direction_y) + (point.y * perpendicular_y);
        profile << world_x << ',' << world_y;
    }
    return profile.str();
}

// The Solid brick pass is a renderer-only overlay, so keep the authoritative
// hosted opening rectangles beside the wall metadata.  Fractions along the
// wall axis make this independent of the Android scene's world transform and
// let the overlay clip the same openings on either long wall face.
std::string wall_opening_profile(const tbe::core::WallData& wall) {
    const auto dx = wall.axis.end.x - wall.axis.start.x;
    const auto dy = wall.axis.end.y - wall.axis.start.y;
    const auto length = std::sqrt((dx * dx) + (dy * dy));
    if (length <= 1.0e-9 || wall.openings.empty()) {
        return {};
    }

    std::ostringstream profile;
    profile << std::setprecision(12);
    bool first = true;
    for (const auto& opening : wall.openings) {
        const auto x_min = std::max(0.0, opening.offset_meters - (opening.width_meters * 0.5));
        const auto x_max = std::min(length, opening.offset_meters + (opening.width_meters * 0.5));
        const auto z_min = opening.vertical_offset_meters + opening.sill_height_meters;
        const auto z_max = z_min + opening.height_meters;
        if (x_max <= x_min || z_max <= z_min) {
            continue;
        }
        if (!first) {
            profile << ';';
        }
        first = false;
        profile << (x_min / length) << ',' << (x_max / length) << ',' << z_min << ',' << z_max;
    }
    return profile.str();
}

std::string wall_type_category_name(tbe::core::WallTypeCategory category) {
    switch (category) {
    case tbe::core::WallTypeCategory::Interior: return "Interior";
    case tbe::core::WallTypeCategory::Exterior: return "Exterior";
    case tbe::core::WallTypeCategory::Generic: return "Generic";
    }
    return "Generic";
}

double section_cross(Point2 left, Point2 right) {
    return left.x * right.y - left.y * right.x;
}

double section_dot(Point2 left, Point2 right) {
    return left.x * right.x + left.y * right.y;
}

RenderSceneMeshDTO make_section_box(double x_min, double x_max, double y_min, double y_max, double z_min, double z_max, std::uint64_t material_id) {
    RenderSceneMeshDTO mesh;
    mesh.positions = {
        {.x = x_min, .y = y_min, .z = z_min}, {.x = x_max, .y = y_min, .z = z_min},
        {.x = x_max, .y = y_max, .z = z_min}, {.x = x_min, .y = y_max, .z = z_min},
        {.x = x_min, .y = y_min, .z = z_max}, {.x = x_max, .y = y_min, .z = z_max},
        {.x = x_max, .y = y_max, .z = z_max}, {.x = x_min, .y = y_max, .z = z_max},
    };
    const std::array<std::uint32_t, 36> indices{
        0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
        2, 6, 7, 2, 7, 3, 4, 0, 3, 4, 3, 7,
    };
    mesh.indices.assign(indices.begin(), indices.end());
    mesh.triangle_material_ids.assign(mesh.indices.size() / 3, material_id);
    return mesh;
}

RenderSceneMeshDTO make_section_ribbon(
    double start_x,
    double start_z,
    double end_x,
    double end_z,
    std::uint64_t material_id,
    double half_width = 0.025,
    double half_depth = 0.03
) {
    const auto dx = end_x - start_x;
    const auto dz = end_z - start_z;
    const auto length = std::sqrt((dx * dx) + (dz * dz));
    if (length <= 1.0e-8) return {};
    const auto normal_x = -dz / length * half_width;
    const auto normal_z = dx / length * half_width;
    const auto first_a = Vec3{.x = start_x + normal_x, .y = -half_depth, .z = start_z + normal_z};
    const auto first_b = Vec3{.x = start_x - normal_x, .y = -half_depth, .z = start_z - normal_z};
    const auto second_a = Vec3{.x = end_x + normal_x, .y = -half_depth, .z = end_z + normal_z};
    const auto second_b = Vec3{.x = end_x - normal_x, .y = -half_depth, .z = end_z - normal_z};
    RenderSceneMeshDTO mesh;
    mesh.positions = {
        first_a, second_a, second_b, first_b,
        Vec3{.x = first_a.x, .y = half_depth, .z = first_a.z},
        Vec3{.x = second_a.x, .y = half_depth, .z = second_a.z},
        Vec3{.x = second_b.x, .y = half_depth, .z = second_b.z},
        Vec3{.x = first_b.x, .y = half_depth, .z = first_b.z},
    };
    const std::array<std::uint32_t, 36> indices{
        0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
        2, 6, 7, 2, 7, 3, 4, 0, 3, 4, 3, 7,
    };
    mesh.indices.assign(indices.begin(), indices.end());
    mesh.triangle_material_ids.assign(mesh.indices.size() / 3, material_id);
    return mesh;
}

void append_section_object(
    RenderSceneDTO& scene,
    ElementId source_id,
    ApiElementKind kind,
    ElementId level_id,
    std::size_t layer_index,
    RenderSceneMeshDTO mesh,
    std::map<std::string, std::string> metadata,
    std::size_t fragment_index = 0
) {
    metadata["section_source_id"] = std::to_string(source_id);
    metadata["section_layer_index"] = std::to_string(layer_index);
    metadata["section_fragment_index"] = std::to_string(fragment_index);
    auto object = make_object_dto(
        9000000000000000ULL + (source_id * 10000ULL) +
            (static_cast<ElementId>(layer_index) * 100ULL) +
            static_cast<ElementId>(fragment_index),
        kind,
        level_id,
        1,
        std::move(mesh),
        kind == ApiElementKind::Wall ? "wall" : "structural",
        std::move(metadata),
        false,
        true
    );
    scene.vertex_count += object.mesh.positions.size();
    scene.index_count += object.mesh.indices.size();
    scene.objects.push_back(std::move(object));
}

bool section_line_intersection(Point2 section_start, Point2 section_direction, Point2 wall_start, Point2 wall_direction, double& section_parameter, double& wall_parameter) {
    const auto denominator = section_cross(section_direction, wall_direction);
    if (std::abs(denominator) <= 1.0e-9) return false;
    const auto delta = Point2{.x = wall_start.x - section_start.x, .y = wall_start.y - section_start.y};
    section_parameter = section_cross(delta, wall_direction) / denominator;
    wall_parameter = section_cross(delta, section_direction) / denominator;
    return true;
}

std::vector<tbe::core::WallAssemblyLayer> section_wall_layers(const Document& document, const tbe::core::WallData& wall) {
    if (wall.assembly_id != 0) {
        if (const auto* assembly = document.get_layered_assembly(wall.assembly_id)) return assembly->layers;
    }
    if (wall.wall_type_id != 0) {
        if (const auto* wall_type = document.get_wall_type(wall.wall_type_id)) return wall_type->layers;
    }
    return {tbe::core::WallAssemblyLayer{.material_id = 0, .thickness_meters = wall.thickness_meters}};
}

RenderSceneDTO build_section_scene(const Document& document, Vec2 start, Vec2 end) {
    const auto section_start = Point2{.x = start.x, .y = start.y};
    const auto section_end = Point2{.x = end.x, .y = end.y};
    const auto direction = Point2{.x = section_end.x - section_start.x, .y = section_end.y - section_start.y};
    const auto section_length = std::sqrt(section_dot(direction, direction));
    if (section_length <= 1.0e-9) throw std::invalid_argument("section line must have positive length");
    const auto unit = Point2{.x = direction.x / section_length, .y = direction.y / section_length};
    const auto levels = level_elevation_map(document);
    RenderSceneDTO scene;
    scene.scene_version = 1;
    scene.units = "meters";
    scene.coordinate_system = "Section distance X, Z elevation";
    // Keep the section definition in the returned scene as well. This lets
    // the Project Browser continue to expose the active section after the
    // viewport has switched from the plan scene to the generated cut scene.
    scene.sections.push_back(RenderSceneSectionDTO{
        .name = "Current Section",
        .start = start,
        .end = end,
    });
    for (const auto& element : document.elements()) {
        if (const auto* level = element.level()) {
            scene.levels.push_back(RenderSceneLevelDTO{.level_id = to_id(element.id()), .name = level->name, .elevation_meters = level->elevation_meters, .default_wall_height_meters = level->default_wall_height_meters});
        }
    }
    for (const auto& [material_id, material] : document.materials()) {
        scene.materials.push_back(RenderSceneMaterialDTO{.id = to_id(material_id), .name = material.name, .category = to_api_material_category(material.category), .display_color = material.display_color});
    }

    // A concave L/U footprint can cross the section line in several disjoint
    // spans. Pair sorted crossings instead of filling from the first to the
    // last one, otherwise a section incorrectly bridges a courtyard/notch.
    const auto polygon_intervals = [&](const std::vector<Point2>& polygon) {
        std::vector<double> intersections;
        for (std::size_t index = 0; index < polygon.size(); ++index) {
            const auto edge_start = polygon[index];
            const auto edge_end = polygon[(index + 1) % polygon.size()];
            double section_parameter = 0.0;
            double edge_parameter = 0.0;
            if (section_line_intersection(section_start, direction, edge_start,
                                          Point2{.x = edge_end.x - edge_start.x,
                                                 .y = edge_end.y - edge_start.y},
                                          section_parameter, edge_parameter) &&
                section_parameter >= -1.0e-6 && section_parameter <= 1.0 + 1.0e-6 &&
                edge_parameter >= -1.0e-6 && edge_parameter <= 1.0 + 1.0e-6) {
                intersections.push_back(section_parameter * section_length);
            }
        }
        std::sort(intersections.begin(), intersections.end());
        intersections.erase(
            std::unique(intersections.begin(), intersections.end(), [](double left, double right) {
                return std::abs(left - right) <= 1.0e-6;
            }),
            intersections.end()
        );
        std::vector<std::pair<double, double>> intervals;
        for (std::size_t index = 0; index + 1 < intersections.size(); index += 2) {
            if (intersections[index + 1] - intersections[index] > 1.0e-6) {
                intervals.emplace_back(intersections[index], intersections[index + 1]);
            }
        }
        return intervals;
    };

    auto append_horizontal_layers = [&](const std::vector<Point2>& polygon,
                                        ElementId source_id,
                                        ApiElementKind kind,
                                        ElementId level_id,
                                        double base_z,
                                        ElementId assembly_id,
                                        ElementId fallback_material_id,
                                        std::string section_kind) {
        const auto intervals = polygon_intervals(polygon);
        if (intervals.empty()) return;

        std::vector<tbe::core::WallAssemblyLayer> layers;
        if (assembly_id != 0) {
            if (const auto* assembly = document.get_layered_assembly(assembly_id)) {
                layers = assembly->layers;
            }
        }
        if (layers.empty()) {
            layers.push_back(tbe::core::WallAssemblyLayer{
                .material_id = fallback_material_id,
                .thickness_meters = 0.02,
            });
        }
        auto z = base_z;
        for (std::size_t index = 0; index < layers.size(); ++index) {
            const auto thickness = std::max(0.005, layers[index].thickness_meters);
            const auto next_z = z + thickness;
            for (std::size_t interval_index = 0;
                 interval_index < intervals.size(); ++interval_index) {
                const auto [section_start_x, section_end_x] = intervals[interval_index];
                append_section_object(
                    scene, source_id, kind, level_id, index,
                    make_section_box(section_start_x, section_end_x, -0.03, 0.03,
                                     z, next_z, layers[index].material_id),
                    {{"section_kind", section_kind},
                     {"layer_thickness_meters", std::to_string(thickness)},
                     {"assembly_id", std::to_string(assembly_id)}},
                    interval_index);
            }
            z = next_z;
        }
    };

    // Sloped roof meshes are already authoritative geometry. Intersect their
    // triangles with the vertical section plane so a section shows the real
    // pitched profile instead of a flat proxy at the roof level.
    const auto append_sloped_roof_cut = [&](const tbe::core::RoofData& roof,
                                            ElementId source_id) {
        if (roof.mesh.indices.empty() || roof.mesh.vertices.empty()) return false;
        const auto base_z = level_elevation(levels, roof.level_id, 0.0);
        auto fallback_material = roof.material_id;
        if (fallback_material == 0 && roof.assembly_id != 0) {
            if (const auto* assembly = document.get_layered_assembly(roof.assembly_id);
                assembly != nullptr && !assembly->layers.empty()) {
                fallback_material = assembly->layers.front().material_id;
            }
        }
        struct Segment {
            double start_x{};
            double start_z{};
            double end_x{};
            double end_z{};
            ElementId material_id{};
        };
        std::vector<Segment> segments;
        const auto add_segment = [&](Point3 first, Point3 second,
                                     ElementId material_id) {
            const auto first_x = section_dot(
                Point2{.x = first.x - section_start.x,
                       .y = first.y - section_start.y}, unit);
            const auto second_x = section_dot(
                Point2{.x = second.x - section_start.x,
                       .y = second.y - section_start.y}, unit);
            if (std::hypot(second_x - first_x, second.z - first.z) <= 1.0e-6) {
                return;
            }
            Segment candidate{
                .start_x = first_x,
                .start_z = first.z,
                .end_x = second_x,
                .end_z = second.z,
                .material_id = material_id,
            };
            if (candidate.end_x < candidate.start_x ||
                (std::abs(candidate.end_x - candidate.start_x) <= 1.0e-6 &&
                 candidate.end_z < candidate.start_z)) {
                std::swap(candidate.start_x, candidate.end_x);
                std::swap(candidate.start_z, candidate.end_z);
            }
            const auto duplicate = std::any_of(
                segments.begin(), segments.end(), [&](const Segment& existing) {
                    return existing.material_id == candidate.material_id &&
                        std::abs(existing.start_x - candidate.start_x) <= 1.0e-5 &&
                        std::abs(existing.start_z - candidate.start_z) <= 1.0e-5 &&
                        std::abs(existing.end_x - candidate.end_x) <= 1.0e-5 &&
                        std::abs(existing.end_z - candidate.end_z) <= 1.0e-5;
                });
            if (!duplicate) segments.push_back(candidate);
        };

        for (std::size_t index = 0; index + 2 < roof.mesh.indices.size(); index += 3) {
            const auto first_index = roof.mesh.indices[index];
            const auto second_index = roof.mesh.indices[index + 1];
            const auto third_index = roof.mesh.indices[index + 2];
            if (first_index >= roof.mesh.vertices.size() ||
                second_index >= roof.mesh.vertices.size() ||
                third_index >= roof.mesh.vertices.size()) {
                continue;
            }
            const std::array<Point3, 3> triangle{
                Point3{.x = roof.mesh.vertices[first_index].x,
                       .y = roof.mesh.vertices[first_index].y,
                       .z = roof.mesh.vertices[first_index].z + base_z},
                Point3{.x = roof.mesh.vertices[second_index].x,
                       .y = roof.mesh.vertices[second_index].y,
                       .z = roof.mesh.vertices[second_index].z + base_z},
                Point3{.x = roof.mesh.vertices[third_index].x,
                       .y = roof.mesh.vertices[third_index].y,
                       .z = roof.mesh.vertices[third_index].z + base_z},
            };
            const auto plane_distance = [&](Point3 point) {
                return section_cross(direction, Point2{
                    .x = point.x - section_start.x,
                    .y = point.y - section_start.y,
                }) / section_length;
            };
            std::array<double, 3> distances{
                plane_distance(triangle[0]), plane_distance(triangle[1]),
                plane_distance(triangle[2]),
            };
            std::vector<Point3> intersections;
            const auto append_unique = [&](Point3 point) {
                const auto already_present = std::any_of(
                    intersections.begin(), intersections.end(),
                    [&](Point3 existing) {
                        return std::abs(existing.x - point.x) <= 1.0e-6 &&
                            std::abs(existing.y - point.y) <= 1.0e-6 &&
                            std::abs(existing.z - point.z) <= 1.0e-6;
                    });
                if (!already_present) intersections.push_back(point);
            };
            for (const auto& [first_edge, second_edge] :
                 std::array<std::pair<std::size_t, std::size_t>, 3>{
                     std::pair{0U, 1U}, std::pair{1U, 2U}, std::pair{2U, 0U}}) {
                const auto first_distance = distances[first_edge];
                const auto second_distance = distances[second_edge];
                if (std::abs(first_distance) <= 1.0e-8) {
                    append_unique(triangle[first_edge]);
                }
                if ((first_distance < -1.0e-8 && second_distance > 1.0e-8) ||
                    (first_distance > 1.0e-8 && second_distance < -1.0e-8)) {
                    const auto t = first_distance / (first_distance - second_distance);
                    const auto& first = triangle[first_edge];
                    const auto& second = triangle[second_edge];
                    append_unique(Point3{
                        .x = first.x + ((second.x - first.x) * t),
                        .y = first.y + ((second.y - first.y) * t),
                        .z = first.z + ((second.z - first.z) * t),
                    });
                }
            }
            if (intersections.size() < 2) continue;
            std::size_t first = 0;
            std::size_t second = 1;
            auto farthest_distance = -1.0;
            for (std::size_t left = 0; left < intersections.size(); ++left) {
                for (std::size_t right = left + 1; right < intersections.size(); ++right) {
                    const auto distance = std::pow(intersections[right].x - intersections[left].x, 2.0) +
                        std::pow(intersections[right].y - intersections[left].y, 2.0) +
                        std::pow(intersections[right].z - intersections[left].z, 2.0);
                    if (distance > farthest_distance) {
                        farthest_distance = distance;
                        first = left;
                        second = right;
                    }
                }
            }
            const auto triangle_material_index = index / 3;
            const auto material_id = triangle_material_index < roof.mesh.triangle_material_ids.size() &&
                    roof.mesh.triangle_material_ids[triangle_material_index] != 0
                ? roof.mesh.triangle_material_ids[triangle_material_index]
                : fallback_material;
            add_segment(intersections[first], intersections[second], material_id);
        }
        for (std::size_t index = 0; index < segments.size(); ++index) {
            const auto& segment = segments[index];
            append_section_object(
                scene, source_id, ApiElementKind::Roof, roof.level_id, 0,
                make_section_ribbon(segment.start_x, segment.start_z,
                                    segment.end_x, segment.end_z,
                                    segment.material_id),
                {{"section_kind", "RoofSlopeCut"},
                 {"assembly_id", std::to_string(roof.assembly_id)}},
                index);
        }
        return !segments.empty();
    };

    for (const auto& [system_id, system] : document.floor_systems()) {
        append_horizontal_layers(system.boundary_polygon, system_id,
                                 ApiElementKind::FloorSystem, system.level_id,
                                 level_elevation(levels, system.level_id, 0.0),
                                 system.assembly_id, 0, "FloorCut");
    }
    for (const auto& [system_id, system] : document.ceiling_systems()) {
        append_horizontal_layers(
            system.boundary_polygon, system_id, ApiElementKind::CeilingSystem,
            system.level_id,
            level_elevation(levels, system.level_id, 0.0) +
                system.height_offset_meters,
            system.assembly_id, 0, "CeilingCut");
    }
    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall()) {
            const auto wall_direction = Point2{.x = wall->axis.end.x - wall->axis.start.x, .y = wall->axis.end.y - wall->axis.start.y};
            double section_parameter = 0.0;
            double wall_parameter = 0.0;
            const auto layers = section_wall_layers(document, *wall);
            const auto base_z = resolved_wall_base_elevation(*wall, levels);
            const auto height = resolved_wall_height(*wall, levels);
            const auto total_thickness = std::accumulate(layers.begin(), layers.end(), 0.0, [](double value, const auto& layer) { return value + layer.thickness_meters; });
            const auto wall_length = std::sqrt(section_dot(wall_direction, wall_direction));
            auto add_wall_layers = [&](double center,
                                       double width,
                                       const tbe::core::HostedOpening* opening) {
                auto cursor = center - width * 0.5;
                for (std::size_t index = 0; index < layers.size(); ++index) {
                    const auto next = cursor + layers[index].thickness_meters / std::max(total_thickness, 1.0e-9) * width;
                    const auto append_piece = [&](double z_min, double z_max, std::size_t fragment_index) {
                        if (z_max - z_min <= 1.0e-6) return;
                        std::map<std::string, std::string> metadata{
                            {"section_kind", "WallCut"},
                            {"layer_profile", wall_layer_profile(document, *wall)},
                            {"wall_type_category", wall->wall_type_id == 0 ? "Generic" : wall_type_category_name(document.get_wall_type(wall->wall_type_id)->category)},
                        };
                        if (opening != nullptr) {
                            metadata["section_opening_id"] = std::to_string(opening->element_id);
                        }
                        append_section_object(
                            scene, element.id(), ApiElementKind::Wall,
                            wall->level_id, index,
                            make_section_box(cursor, next, -0.03, 0.03,
                                             z_min, z_max,
                                             layers[index].material_id),
                            std::move(metadata), fragment_index);
                    };
                    if (opening == nullptr) {
                        append_piece(base_z, base_z + height, 0);
                    } else {
                        const auto opening_bottom = std::clamp(
                            base_z + opening->vertical_offset_meters + opening->sill_height_meters,
                            base_z, base_z + height);
                        const auto opening_top = std::clamp(
                            opening_bottom + opening->height_meters,
                            base_z, base_z + height);
                        append_piece(base_z, opening_bottom, 0);
                        append_piece(opening_top, base_z + height, 1);
                    }
                    cursor = next;
                }
            };
            if (section_line_intersection(section_start, direction, wall->axis.start, wall_direction, section_parameter, wall_parameter) && section_parameter >= -1.0e-6 && section_parameter <= 1.0 + 1.0e-6 && wall_parameter >= -1.0e-6 && wall_parameter <= 1.0 + 1.0e-6) {
                const auto station = wall_parameter * wall_length;
                const tbe::core::HostedOpening* opening_at_cut = nullptr;
                for (const auto& opening : wall->openings) {
                    const auto opening_start = opening.offset_meters - (opening.width_meters * 0.5);
                    const auto opening_end = opening.offset_meters + (opening.width_meters * 0.5);
                    if (station >= opening_start - 1.0e-6 &&
                        station <= opening_end + 1.0e-6) {
                        opening_at_cut = &opening;
                        break;
                    }
                }
                add_wall_layers(section_parameter * section_length,
                                total_thickness, opening_at_cut);
            } else if (std::abs(section_cross(direction, Point2{.x = wall->axis.start.x - section_start.x, .y = wall->axis.start.y - section_start.y})) <= wall->thickness_meters * section_length) {
                const auto a = section_dot(Point2{.x = wall->axis.start.x - section_start.x, .y = wall->axis.start.y - section_start.y}, unit);
                const auto b = section_dot(Point2{.x = wall->axis.end.x - section_start.x, .y = wall->axis.end.y - section_start.y}, unit);
                auto cursor = std::min(a, b);
                const auto end_cursor = std::max(a, b);
                for (std::size_t index = 0; index < layers.size(); ++index) {
                    const auto next = cursor + layers[index].thickness_meters / std::max(total_thickness, 1.0e-9) * (end_cursor - std::min(a, b));
                    append_section_object(scene, element.id(), ApiElementKind::Wall, wall->level_id, index, make_section_box(cursor, next, -0.03, 0.03, base_z, base_z + height, layers[index].material_id), {{"section_kind", "WallAlong"}, {"layer_profile", wall_layer_profile(document, *wall)}});
                    cursor = next;
                }
            }
        } else if (const auto* slab = element.slab()) {
            const auto intervals = polygon_intervals(slab->boundary_polygon);
            if (intervals.empty()) continue;
            std::vector<tbe::core::WallAssemblyLayer> layers;
            if (slab->assembly_id != 0) {
                if (const auto* assembly = document.get_layered_assembly(slab->assembly_id)) layers = assembly->layers;
            }
            if (layers.empty()) layers.push_back(tbe::core::WallAssemblyLayer{.material_id = slab->material_id, .thickness_meters = slab->thickness_meters});
            const auto slab_base = level_elevation(levels, slab->level_id, 0.0) + slab->elevation_offset_meters;
            auto z = slab_base;
            for (std::size_t index = 0; index < layers.size(); ++index) {
                const auto next_z = z + layers[index].thickness_meters;
                for (std::size_t interval_index = 0;
                     interval_index < intervals.size(); ++interval_index) {
                    const auto [slab_area_start, slab_area_end] = intervals[interval_index];
                    append_section_object(scene, element.id(), ApiElementKind::Slab, slab->level_id, index, make_section_box(slab_area_start, slab_area_end, -0.03, 0.03, z, next_z, layers[index].material_id), {{"section_kind", "SlabCut"}, {"layer_thickness_meters", std::to_string(layers[index].thickness_meters)}, {"assembly_id", std::to_string(slab->assembly_id)}}, interval_index);
                }
                z = next_z;
            }
        } else if (const auto* roof = element.roof()) {
            const auto has_sloped_profile =
                roof->roof_type != tbe::core::RoofType::Flat &&
                append_sloped_roof_cut(*roof, element.id());
            if (!has_sloped_profile) {
                append_horizontal_layers(
                    roof->boundary_polygon, element.id(), ApiElementKind::Roof,
                    roof->level_id, level_elevation(levels, roof->level_id, 0.0),
                    roof->assembly_id, roof->material_id, "RoofCut");
            }
        }
    }
    scene.object_count = scene.objects.size();
    return scene;
}

RenderSceneDTO build_render_scene(
    const Document& document,
    const std::set<ElementId>* visible_level_ids = nullptr,
    RenderSceneDetail detail = RenderSceneDetail::Exact,
    RenderSceneStage stage = RenderSceneStage::Full
) {
    RenderSceneDTO scene;
    scene.scene_version = 1;
    scene.units = "meters";
    scene.coordinate_system = "X/Y plan, Z up";

    const auto elevations = level_elevation_map(document);

    const auto mesh_for_render = [&](const tbe::core::MeshBuffer& mesh, double z_offset, const Element& owner) {
        return mesh_dto_from_mesh_buffer(
            mesh,
            z_offset,
            interactive_triangle_budget(owner, mesh, detail));
    };

    auto append_object = [&](RenderSceneObjectDTO object) {
        if (visible_level_ids != nullptr && !visible_level_ids->contains(object.level_id.value)) {
            const auto host_level = object.metadata.find("host_render_level_id");
            if (host_level == object.metadata.end() ||
                !visible_level_ids->contains(static_cast<ElementId>(std::stoull(host_level->second)))) {
                return;
            }
        }
        if (stage == RenderSceneStage::Primary &&
            (object.kind == ApiElementKind::Door ||
             object.kind == ApiElementKind::Window ||
             object.kind == ApiElementKind::Room ||
             object.kind == ApiElementKind::Proxy)) {
            return;
        }
        if (const auto* source = document.find_ptr(object.element_id.value); source != nullptr) {
            for (const auto& [key, value] : source->metadata()) {
                const auto property_key = "property." + key;
                object.metadata[property_key] = value.value;
                object.metadata[property_key + ".type"] = std::to_string(static_cast<int>(value.kind));
                if (!value.unit.empty()) object.metadata[property_key + ".unit"] = value.unit;
            }
        }
        if (object.mesh.positions.empty() || object.mesh.indices.empty()) {
            return;
        }
        for (const auto& point : object.mesh.positions) {
            if (!is_finite_vec3(point)) {
                return;
            }
        }
        scene.vertex_count += object.mesh.positions.size();
        scene.index_count += object.mesh.indices.size();
        scene.objects.push_back(std::move(object));
    };

    for (const auto& element : document.elements()) {
        if (const auto* level = element.level(); level != nullptr) {
            scene.levels.push_back(RenderSceneLevelDTO{
                .level_id = to_id(element.id()),
                .name = level->name,
                .elevation_meters = level->elevation_meters,
                .default_wall_height_meters = level->default_wall_height_meters,
            });
        }
    }

    for (const auto& [material_id, material] : document.materials()) {
        scene.materials.push_back(RenderSceneMaterialDTO{
            .id = to_id(material_id),
            .name = material.name,
            .category = to_api_material_category(material.category),
            .display_color = material.display_color,
        });
    }

    for (const auto& [wall_type_id, wall_type] : document.wall_types()) {
        RenderSceneWallTypeDTO dto{
            .id = to_id(wall_type_id),
            .name = wall_type.name,
            .category = to_api_wall_type_category(wall_type.category),
            .total_thickness_meters = std::accumulate(
                wall_type.layers.begin(),
                wall_type.layers.end(),
                0.0,
                [](double total, const auto& layer) {
                    return total + layer.thickness_meters;
                }),
            .core_start_layer = wall_type.core_start_layer,
            .core_end_layer = wall_type.core_end_layer,
        };
        dto.layers.reserve(wall_type.layers.size());
        for (const auto& layer : wall_type.layers) {
            dto.layers.push_back(RenderSceneWallLayerDTO{
                .material_id = to_id(layer.material_id),
                .thickness_meters = layer.thickness_meters,
                .function = to_api_layer_function(layer.function),
                .priority = layer.priority,
                .structural = layer.structural,
                .side = to_api_layer_side(layer.side),
                .wraps_openings = layer.wraps_openings,
                .wraps_ends = layer.wraps_ends,
            });
        }
        scene.wall_types.push_back(std::move(dto));
    }

    // Default template guidance: two perpendicular cuts through the model
    // center are visible immediately in plan. The actual section scene is
    // generated only when the user requests one.
    double min_x = std::numeric_limits<double>::max();
    double min_y = std::numeric_limits<double>::max();
    double max_x = std::numeric_limits<double>::lowest();
    double max_y = std::numeric_limits<double>::lowest();
    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall()) {
            min_x = std::min({min_x, wall->axis.start.x, wall->axis.end.x});
            min_y = std::min({min_y, wall->axis.start.y, wall->axis.end.y});
            max_x = std::max({max_x, wall->axis.start.x, wall->axis.end.x});
            max_y = std::max({max_y, wall->axis.start.y, wall->axis.end.y});
        }
    }
    if (min_x <= max_x && min_y <= max_y) {
        const auto center_x = (min_x + max_x) * 0.5;
        const auto center_y = (min_y + max_y) * 0.5;
        // Let every default cut overrun the building shell. Besides matching
        // Revit's readable section-marker convention, this keeps exterior
        // wall intersections safely inside the finite section segment.
        const auto span = std::max(max_x - min_x, max_y - min_y);
        const auto margin = std::max(1.0, span * 0.08);
        scene.sections.push_back(RenderSceneSectionDTO{.name = "Section A", .start = {.x = min_x - margin, .y = center_y}, .end = {.x = max_x + margin, .y = center_y}});
        scene.sections.push_back(RenderSceneSectionDTO{.name = "Section B", .start = {.x = center_x, .y = min_y - margin}, .end = {.x = center_x, .y = max_y + margin}});
    }

    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall(); wall != nullptr) {
            const auto base_elevation = resolved_wall_base_elevation(*wall, elevations);
            const auto layer_profile = wall_layer_profile(document, *wall);
            const auto* wall_type = wall->wall_type_id == 0 ? nullptr : document.get_wall_type(wall->wall_type_id);
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Wall,
                wall->level_id,
                element.revision(),
                mesh_for_render(wall->geometry.mesh, base_elevation, element),
                material_category_name(ApiElementKind::Wall),
                {
                    {"start_x", std::to_string(wall->axis.start.x)},
                    {"start_y", std::to_string(wall->axis.start.y)},
                    {"end_x", std::to_string(wall->axis.end.x)},
                    {"end_y", std::to_string(wall->axis.end.y)},
                    {"thickness_meters", std::to_string(wall->thickness_meters)},
                    {"assembly_id", std::to_string(wall->assembly_id)},
                    {"wall_type_id", std::to_string(wall->wall_type_id)},
                    {"wall_type_name", wall_type == nullptr ? "Generic Wall" : wall_type->name},
                    {"wall_type_category", wall_type == nullptr ? "Generic" : wall_type_category_name(wall_type->category)},
                    {"height_meters", std::to_string(resolved_wall_height(*wall, elevations))},
                    {"base_level_id", std::to_string(wall->base_level_id)},
                    {"top_level_id", std::to_string(wall->top_level_id)},
                    {"base_offset_meters", std::to_string(wall->base_offset_meters)},
                    {"top_offset_meters", std::to_string(wall->top_offset_meters)},
                    {"height_mode", wall->height_mode == tbe::core::WallHeightMode::TopLevel ? "TopLevel" : "Unconnected"},
                    {"level_locked", "true"},
                    {"layer_profile", layer_profile},
                    {"profile_corners", wall_profile_corners(*wall)},
                    {"opening_profile", wall_opening_profile(*wall)},
                }
            ));
            for (const auto& opening : wall->openings) {
                // Structural voids cut the host wall geometry but the cutter
                // (column/beam) is rendered once as its own authoritative
                // object. Never emit a duplicate selectable opening object.
                if (opening.kind == tbe::core::OpeningKind::StructuralVoid) continue;
                const auto opening_kind = opening.kind == tbe::core::OpeningKind::Door ? ApiElementKind::Door : ApiElementKind::Window;
                const auto* opening_element = document.find_ptr(opening.element_id);
                const auto opening_level_id =
                    opening_element != nullptr && opening_element->door() != nullptr
                        ? opening_element->door()->level_id
                        : (opening_element != nullptr && opening_element->window() != nullptr
                               ? opening_element->window()->level_id
                               : wall->level_id);
                const auto opening_locked = opening_element != nullptr && opening_element->door() != nullptr
                    ? opening_element->door()->level_locked
                    : (opening_element != nullptr && opening_element->window() != nullptr ? opening_element->window()->level_locked : true);
                const auto opening_level_offset = opening_element != nullptr && opening_element->door() != nullptr
                    ? opening_element->door()->level_offset_meters
                    : (opening_element != nullptr && opening_element->window() != nullptr
                           ? opening_element->window()->level_offset_meters
                           : 0.0);
                auto opening_mesh = make_opening_mesh(wall->axis, opening, wall->thickness_meters, base_elevation);
                if (opening_element != nullptr && opening_element->door() != nullptr &&
                    !opening_element->door()->mesh.vertices.empty() && !opening_element->door()->mesh.indices.empty()) {
                    opening_mesh = mesh_for_render(opening_element->door()->mesh, base_elevation, *opening_element);
                } else if (opening_element != nullptr && opening_element->window() != nullptr &&
                    !opening_element->window()->mesh.vertices.empty() && !opening_element->window()->mesh.indices.empty()) {
                    opening_mesh = mesh_for_render(opening_element->window()->mesh, base_elevation, *opening_element);
                }
                append_object(make_object_dto(
                    opening.element_id,
                    opening_kind,
                    opening_level_id,
                    element.revision(),
                    std::move(opening_mesh),
                    material_category_name(opening_kind),
                    {
                        {"host_wall_id", std::to_string(element.id())},
                        {"host_render_level_id", std::to_string(wall->level_id)},
                        {"offset_meters", std::to_string(opening.offset_meters)},
                        {"width_meters", std::to_string(opening.width_meters)},
                        {"height_meters", std::to_string(opening.height_meters)},
                        {"sill_height_meters", std::to_string(opening.sill_height_meters)},
                        {"vertical_offset_meters", std::to_string(opening.vertical_offset_meters)},
                        {"level_offset_meters", std::to_string(opening_level_offset)},
                        {"level_locked", opening_locked ? "true" : "false"},
                    }
                ));
            }
            continue;
        }
        if (const auto* room = element.room(); room != nullptr) {
            const auto& polygon = room->interior_boundary_polygon.empty()
                ? room->centerline_boundary_polygon
                : room->interior_boundary_polygon;
            if (polygon.size() >= 3) {
                const auto elevation = level_elevation(elevations, room->level_id, 0.0);
                auto boundary_ids = std::string{};
                for (std::size_t index = 0; index < room->boundary_wall_ids.size(); ++index) {
                    if (index != 0) boundary_ids += ',';
                    boundary_ids += std::to_string(room->boundary_wall_ids[index]);
                }
                auto boundary_polygon = std::string{};
                for (std::size_t index = 0; index < polygon.size(); ++index) {
                    if (index != 0) boundary_polygon += ';';
                    boundary_polygon += std::to_string(polygon[index].x) + ',' +
                        std::to_string(polygon[index].y);
                }
                append_object(make_object_dto(
                    element.id(),
                    ApiElementKind::Room,
                    room->level_id,
                    element.revision(),
                    make_flat_polygon_mesh(polygon, elevation + 0.01, 0.01),
                    material_category_name(ApiElementKind::Room),
                    {
                        {"boundary_wall_ids", boundary_ids},
                        {"boundary_polygon", boundary_polygon},
                    }
                ));
            }
            continue;
        }
        if (const auto* slab = element.slab(); slab != nullptr) {
            const auto elevation = level_elevation(elevations, slab->level_id, 0.0) + slab->elevation_offset_meters;
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Slab,
                slab->level_id,
                element.revision(),
                mesh_for_render(slab->mesh, level_elevation(elevations, slab->level_id, 0.0), element),
                material_category_name(ApiElementKind::Slab),
                {
                    {"elevation_offset_meters", std::to_string(slab->elevation_offset_meters)},
                    {"assembly_id", std::to_string(slab->assembly_id)},
                }
            ));
            (void)elevation;
            continue;
        }
        if (const auto* roof = element.roof(); roof != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Roof,
                roof->level_id,
                element.revision(),
                mesh_for_render(roof->mesh, level_elevation(elevations, roof->level_id, 0.0), element),
                material_category_name(ApiElementKind::Roof),
                {
                    {"assembly_id", std::to_string(roof->assembly_id)},
                    {"roof_type", roof->roof_type == tbe::core::RoofType::SimpleGable
                        ? "SimpleGable"
                        : roof->roof_type == tbe::core::RoofType::AutoFootprint ? "AutoFootprint" : "Flat"},
                    {"slope_degrees", roof->slope_degrees.has_value() ? std::to_string(*roof->slope_degrees) : ""},
                    {"overhang_meters", roof->overhang_meters.has_value() ? std::to_string(*roof->overhang_meters) : ""},
                }
            ));
            continue;
        }
        if (const auto* column = element.column(); column != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Column,
                column->level_id,
                element.revision(),
                mesh_for_render(column->mesh, level_elevation(elevations, column->level_id, 0.0), element),
                material_category_name(ApiElementKind::Column)
            ));
            continue;
        }
        if (const auto* beam = element.beam(); beam != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Beam,
                beam->level_id,
                element.revision(),
                mesh_for_render(beam->mesh, level_elevation(elevations, beam->level_id, 0.0), element),
                material_category_name(ApiElementKind::Beam)
            ));
            continue;
        }
        if (const auto* stair = element.stair(); stair != nullptr) {
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Stair,
                stair->base_level_id,
                element.revision(),
                mesh_for_render(stair->mesh, level_elevation(elevations, stair->base_level_id, 0.0), element),
                material_category_name(ApiElementKind::Stair),
                {
                    {"base_level_id", std::to_string(stair->base_level_id)},
                    {"top_level_id", std::to_string(stair->top_level_id)},
                    {"width_meters", std::to_string(stair->width_meters)},
                    {"total_rise_meters", std::to_string(stair->total_rise_meters)},
                    {"total_run_meters", std::to_string(stair->total_run_meters)},
                    {"riser_count", std::to_string(stair->riser_count)},
                    {"tread_count", std::to_string(stair->tread_count)},
                    {"assembly_id", std::to_string(stair->assembly_id)},
                    {"level_locked", "true"},
                }
            ));
            continue;
        }
        if (const auto* proxy = element.proxy(); proxy != nullptr) {
            if (is_runtime_hidden_ifc_proxy(element, detail)) continue;
            const auto elevation = level_elevation(elevations, proxy->level_id, 0.0);
            // Small exact IFC detail stays visually faithful. The interactive
            // mesh_for_render path applies the deterministic triangle budget;
            // replacing it with a generic box was cheap but made furniture and
            // fixtures read as a wireframe cage. Only true fallback proxies
            // (with no source mesh) use the selectable envelope.
            auto proxy_mesh = proxy->mesh.vertices.empty() || proxy->mesh.indices.empty()
                ? make_section_box(
                    proxy->position.x - proxy->width_meters * 0.5,
                    proxy->position.x + proxy->width_meters * 0.5,
                    proxy->position.y - proxy->depth_meters * 0.5,
                    proxy->position.y + proxy->depth_meters * 0.5,
                    elevation,
                    elevation + proxy->height_meters,
                    0)
                : mesh_for_render(proxy->mesh, elevation, element);
            append_object(make_object_dto(
                element.id(),
                ApiElementKind::Proxy,
                proxy->level_id,
                element.revision(),
                std::move(proxy_mesh),
                material_category_name(ApiElementKind::Proxy),
                {
                    {"width_meters", std::to_string(proxy->width_meters)},
                    {"depth_meters", std::to_string(proxy->depth_meters)},
                    {"height_meters", std::to_string(proxy->height_meters)},
                    {"ifc_proxy", "true"},
                    // Keep the source entity at the render/cache boundary.
                    // In particular, a CAD import can be a single
                    // IFCBUILDINGELEMENTPROXY that needs part-level touch
                    // targets even though the source has no Door/Window IDs.
                    {"ifc_entity", std::string(ifc_entity_type(element))},
                }
            ));
        }
    }

    for (const auto& [system_id, system] : document.floor_systems()) {
        const auto elevation = level_elevation(elevations, system.level_id, 0.0);
        auto mesh = make_flat_polygon_mesh(system.boundary_polygon, elevation, 0.02);
        append_object(make_object_dto(
            system_id,
            ApiElementKind::FloorSystem,
            system.level_id,
            system.dirty ? 0 : 1,
            std::move(mesh),
            material_category_name(ApiElementKind::FloorSystem),
            {{"assembly_id", std::to_string(system.assembly_id)},
             {"stair_opening_count", std::to_string(system.stair_opening_ids.size())}}
        ));
    }

    for (const auto& [system_id, system] : document.ceiling_systems()) {
        const auto elevation = level_elevation(elevations, system.level_id, 0.0) + system.height_offset_meters;
        auto mesh = make_flat_polygon_mesh(system.boundary_polygon, elevation, 0.02);
        append_object(make_object_dto(
            system_id,
            ApiElementKind::CeilingSystem,
            system.level_id,
            system.dirty ? 0 : 1,
            std::move(mesh),
            material_category_name(ApiElementKind::CeilingSystem),
            {{"assembly_id", std::to_string(system.assembly_id)},
             {"stair_opening_count", std::to_string(system.stair_opening_ids.size())}}
        ));
    }

    scene.object_count = scene.objects.size();
    return scene;
}

std::string api_kind_json_name(ApiElementKind kind) {
    return api_kind_name(kind);
}

std::string render_scene_to_json(const RenderSceneDTO& scene) {
    std::ostringstream out;
    out << '{';
    out << "\"scene_version\":" << scene.scene_version << ',';
    out << "\"units\":\"" << escape_json(scene.units) << "\",";
    out << "\"coordinate_system\":\"" << escape_json(scene.coordinate_system) << "\",";
    out << "\"object_count\":" << scene.object_count << ',';
    out << "\"vertex_count\":" << scene.vertex_count << ',';
    out << "\"index_count\":" << scene.index_count << ',';
    out << "\"levels\":[";
    for (std::size_t index = 0; index < scene.levels.size(); ++index) {
        if (index != 0) {
            out << ',';
        }
        const auto& level = scene.levels[index];
        out << "{\"level_id\":" << level.level_id.value
            << ",\"name\":\"" << escape_json(level.name) << "\""
            << ",\"elevation_meters\":" << safe_value(level.elevation_meters)
            << ",\"default_wall_height_meters\":" << safe_value(level.default_wall_height_meters)
            << "}";
    }
    out << "],";
    out << "\"materials\":[";
    for (std::size_t index = 0; index < scene.materials.size(); ++index) {
        if (index != 0) out << ',';
        const auto& material = scene.materials[index];
        out << "{\"id\":" << material.id.value
            << ",\"name\":\"" << escape_json(material.name) << "\""
            << ",\"category\":\"" << static_cast<int>(material.category) << "\""
            << ",\"display_color\":\"" << escape_json(material.display_color) << "\"}";
    }
    out << "],\"wall_types\":[";
    for (std::size_t index = 0; index < scene.wall_types.size(); ++index) {
        if (index != 0) out << ',';
        const auto& wall_type = scene.wall_types[index];
        out << "{\"id\":" << wall_type.id.value
            << ",\"name\":\"" << escape_json(wall_type.name) << "\""
            << ",\"category\":\"" << wall_type_category_name(
                wall_type.category == ApiWallTypeCategory::Interior
                    ? tbe::core::WallTypeCategory::Interior
                    : wall_type.category == ApiWallTypeCategory::Exterior
                        ? tbe::core::WallTypeCategory::Exterior
                        : tbe::core::WallTypeCategory::Generic) << "\""
            << ",\"total_thickness_meters\":" << safe_value(wall_type.total_thickness_meters)
            << ",\"core_start_layer\":" << wall_type.core_start_layer
            << ",\"core_end_layer\":" << wall_type.core_end_layer
            << ",\"layers\":[";
        for (std::size_t layer_index = 0; layer_index < wall_type.layers.size(); ++layer_index) {
            if (layer_index != 0) out << ',';
            const auto& layer = wall_type.layers[layer_index];
            out << "{\"material_id\":" << layer.material_id.value
                << ",\"thickness_meters\":" << safe_value(layer.thickness_meters)
                << ",\"function\":" << static_cast<int>(layer.function)
                << ",\"priority\":" << layer.priority
                << ",\"structural\":" << (layer.structural ? "true" : "false")
                << ",\"side\":" << static_cast<int>(layer.side)
                << ",\"wraps_openings\":" << (layer.wraps_openings ? "true" : "false")
                << ",\"wraps_ends\":" << (layer.wraps_ends ? "true" : "false")
                << "}";
        }
        out << "]}";
    }
    out << "],\"sections\":[";
    for (std::size_t index = 0; index < scene.sections.size(); ++index) {
        if (index != 0) out << ',';
        const auto& section = scene.sections[index];
        out << "{\"name\":\"" << escape_json(section.name) << "\",\"start\":{\"x\":" << safe_value(section.start.x) << ",\"y\":" << safe_value(section.start.y) << "},\"end\":{\"x\":" << safe_value(section.end.x) << ",\"y\":" << safe_value(section.end.y) << "}}";
    }
    out << "],";
    out << "\"objects\":[";
    for (std::size_t object_index = 0; object_index < scene.objects.size(); ++object_index) {
        const auto& object = scene.objects[object_index];
        if (object_index != 0) {
            out << ',';
        }
        out << '{';
        out << "\"element_id\":" << object.element_id.value << ',';
        out << "\"kind\":\"" << api_kind_json_name(object.kind) << "\",";
        out << "\"level_id\":" << object.level_id.value << ',';
        out << "\"selectable\":" << (object.selectable ? "true" : "false") << ',';
        out << "\"visible_by_default\":" << (object.visible_by_default ? "true" : "false") << ',';
        out << "\"revision\":" << object.revision << ',';
        out << "\"material_category\":\"" << escape_json(object.material_category) << "\",";
        if (!object.metadata.empty()) {
            out << "\"metadata\":{";
            auto first_metadata = true;
            for (const auto& [key, value] : object.metadata) {
                if (!first_metadata) {
                    out << ',';
                }
                first_metadata = false;
                out << "\"" << escape_json(key) << "\":\"" << escape_json(value) << "\"";
            }
            out << "},";
        }
        out << "\"bounds\":{\"min\":{\"x\":" << safe_value(object.bounds.min.x) << ",\"y\":" << safe_value(object.bounds.min.y) << ",\"z\":" << safe_value(object.bounds.min.z)
            << "},\"max\":{\"x\":" << safe_value(object.bounds.max.x) << ",\"y\":" << safe_value(object.bounds.max.y) << ",\"z\":" << safe_value(object.bounds.max.z) << "}},";
        out << "\"mesh\":{\"positions\":[";
        for (std::size_t index = 0; index < object.mesh.positions.size(); ++index) {
            if (index != 0) {
                out << ',';
            }
            const auto& point = object.mesh.positions[index];
            out << "{\"x\":" << safe_value(point.x) << ",\"y\":" << safe_value(point.y) << ",\"z\":" << safe_value(point.z) << "}";
        }
        out << "],\"indices\":[";
        for (std::size_t index = 0; index < object.mesh.indices.size(); ++index) {
            if (index != 0) {
                out << ',';
            }
            out << object.mesh.indices[index];
        }
        out << ']';
        out << ",\"triangle_material_ids\":[";
        for (std::size_t index = 0; index < object.mesh.triangle_material_ids.size(); ++index) {
            if (index != 0) out << ',';
            out << object.mesh.triangle_material_ids[index];
        }
        out << ']';
        if (object.mesh.normals.has_value()) {
            out << ",\"normals\":[";
            const auto& normals = *object.mesh.normals;
            for (std::size_t index = 0; index < normals.size(); ++index) {
                if (index != 0) {
                    out << ',';
                }
                const auto& normal = normals[index];
                out << "{\"x\":" << safe_value(normal.x) << ",\"y\":" << safe_value(normal.y) << ",\"z\":" << safe_value(normal.z) << "}";
            }
            out << ']';
        }
        out << "}}";
    }
    out << "]}";
    return out.str();
}

ApiElementKind to_api_kind(tbe::core::ElementKind kind) {
    switch (kind) {
    case tbe::core::ElementKind::Level: return ApiElementKind::Level;
    case tbe::core::ElementKind::Wall: return ApiElementKind::Wall;
    case tbe::core::ElementKind::Door: return ApiElementKind::Door;
    case tbe::core::ElementKind::Window: return ApiElementKind::Window;
    case tbe::core::ElementKind::Room: return ApiElementKind::Room;
    case tbe::core::ElementKind::Slab: return ApiElementKind::Slab;
    case tbe::core::ElementKind::Roof: return ApiElementKind::Roof;
    case tbe::core::ElementKind::Column: return ApiElementKind::Column;
    case tbe::core::ElementKind::Beam: return ApiElementKind::Beam;
    case tbe::core::ElementKind::Stair: return ApiElementKind::Stair;
    case tbe::core::ElementKind::Proxy: return ApiElementKind::Proxy;
    }
    return ApiElementKind::Unknown;
}

ApiValidationSeverity to_api_severity(tbe::core::ValidationSeverity severity) {
    return severity == tbe::core::ValidationSeverity::Warning ? ApiValidationSeverity::Warning : ApiValidationSeverity::Error;
}

ApiQuantityType to_api_quantity_type(tbe::core::QuantityType type) {
    switch (type) {
    case tbe::core::QuantityType::Area: return ApiQuantityType::Area;
    case tbe::core::QuantityType::Volume: return ApiQuantityType::Volume;
    case tbe::core::QuantityType::Length: return ApiQuantityType::Length;
    case tbe::core::QuantityType::Count: return ApiQuantityType::Count;
    }
    return ApiQuantityType::Volume;
}

ApiMaterialCategory to_api_material_category(tbe::core::MaterialCategory category) {
    switch (category) {
    case tbe::core::MaterialCategory::Structural: return ApiMaterialCategory::Structural;
    case tbe::core::MaterialCategory::Finish: return ApiMaterialCategory::Finish;
    case tbe::core::MaterialCategory::Insulation: return ApiMaterialCategory::Insulation;
    case tbe::core::MaterialCategory::Glass: return ApiMaterialCategory::Glass;
    case tbe::core::MaterialCategory::Generic: return ApiMaterialCategory::Generic;
    }
    return ApiMaterialCategory::Generic;
}

tbe::core::MaterialCategory to_core_material_category(ApiMaterialCategory category) {
    switch (category) {
    case ApiMaterialCategory::Structural: return tbe::core::MaterialCategory::Structural;
    case ApiMaterialCategory::Finish: return tbe::core::MaterialCategory::Finish;
    case ApiMaterialCategory::Insulation: return tbe::core::MaterialCategory::Insulation;
    case ApiMaterialCategory::Glass: return tbe::core::MaterialCategory::Glass;
    case ApiMaterialCategory::Generic: return tbe::core::MaterialCategory::Generic;
    }
    return tbe::core::MaterialCategory::Generic;
}

ApiWallLayerFunction to_api_layer_function(tbe::core::WallLayerFunction function) {
    switch (function) {
    case tbe::core::WallLayerFunction::Core: return ApiWallLayerFunction::Core;
    case tbe::core::WallLayerFunction::InteriorFinish: return ApiWallLayerFunction::InteriorFinish;
    case tbe::core::WallLayerFunction::ExteriorFinish: return ApiWallLayerFunction::ExteriorFinish;
    case tbe::core::WallLayerFunction::Insulation: return ApiWallLayerFunction::Insulation;
    case tbe::core::WallLayerFunction::AirGap: return ApiWallLayerFunction::AirGap;
    case tbe::core::WallLayerFunction::Generic: return ApiWallLayerFunction::Generic;
    }
    return ApiWallLayerFunction::Generic;
}

tbe::core::WallLayerFunction to_core_layer_function(ApiWallLayerFunction function) {
    switch (function) {
    case ApiWallLayerFunction::Core: return tbe::core::WallLayerFunction::Core;
    case ApiWallLayerFunction::InteriorFinish: return tbe::core::WallLayerFunction::InteriorFinish;
    case ApiWallLayerFunction::ExteriorFinish: return tbe::core::WallLayerFunction::ExteriorFinish;
    case ApiWallLayerFunction::Insulation: return tbe::core::WallLayerFunction::Insulation;
    case ApiWallLayerFunction::AirGap: return tbe::core::WallLayerFunction::AirGap;
    case ApiWallLayerFunction::Generic: return tbe::core::WallLayerFunction::Generic;
    }
    return tbe::core::WallLayerFunction::Generic;
}

ApiWallLayerSide to_api_layer_side(tbe::core::WallLayerSide side) {
    switch (side) {
    case tbe::core::WallLayerSide::Unspecified: return ApiWallLayerSide::Unspecified;
    case tbe::core::WallLayerSide::Exterior: return ApiWallLayerSide::Exterior;
    case tbe::core::WallLayerSide::Interior: return ApiWallLayerSide::Interior;
    }
    return ApiWallLayerSide::Unspecified;
}

tbe::core::WallLayerSide to_core_layer_side(ApiWallLayerSide side) {
    switch (side) {
    case ApiWallLayerSide::Unspecified: return tbe::core::WallLayerSide::Unspecified;
    case ApiWallLayerSide::Exterior: return tbe::core::WallLayerSide::Exterior;
    case ApiWallLayerSide::Interior: return tbe::core::WallLayerSide::Interior;
    }
    return tbe::core::WallLayerSide::Unspecified;
}

ApiWallTypeCategory to_api_wall_type_category(tbe::core::WallTypeCategory category) {
    switch (category) {
    case tbe::core::WallTypeCategory::Interior: return ApiWallTypeCategory::Interior;
    case tbe::core::WallTypeCategory::Exterior: return ApiWallTypeCategory::Exterior;
    case tbe::core::WallTypeCategory::Generic: return ApiWallTypeCategory::Generic;
    }
    return ApiWallTypeCategory::Generic;
}

tbe::core::WallTypeCategory to_core_wall_type_category(ApiWallTypeCategory category) {
    switch (category) {
    case ApiWallTypeCategory::Interior: return tbe::core::WallTypeCategory::Interior;
    case ApiWallTypeCategory::Exterior: return tbe::core::WallTypeCategory::Exterior;
    case ApiWallTypeCategory::Generic: return tbe::core::WallTypeCategory::Generic;
    }
    return tbe::core::WallTypeCategory::Generic;
}

ApiLayeredAssemblyKind to_api_assembly_kind(tbe::core::LayeredAssemblyKind kind) {
    switch (kind) {
    case tbe::core::LayeredAssemblyKind::Wall: return ApiLayeredAssemblyKind::Wall;
    case tbe::core::LayeredAssemblyKind::Floor: return ApiLayeredAssemblyKind::Floor;
    case tbe::core::LayeredAssemblyKind::Ceiling: return ApiLayeredAssemblyKind::Ceiling;
    case tbe::core::LayeredAssemblyKind::Roof: return ApiLayeredAssemblyKind::Roof;
    case tbe::core::LayeredAssemblyKind::Stair: return ApiLayeredAssemblyKind::Stair;
    }
    return ApiLayeredAssemblyKind::Floor;
}

tbe::core::LayeredAssemblyKind to_core_assembly_kind(ApiLayeredAssemblyKind kind) {
    switch (kind) {
    case ApiLayeredAssemblyKind::Wall: return tbe::core::LayeredAssemblyKind::Wall;
    case ApiLayeredAssemblyKind::Floor: return tbe::core::LayeredAssemblyKind::Floor;
    case ApiLayeredAssemblyKind::Ceiling: return tbe::core::LayeredAssemblyKind::Ceiling;
    case ApiLayeredAssemblyKind::Roof: return tbe::core::LayeredAssemblyKind::Roof;
    case ApiLayeredAssemblyKind::Stair: return tbe::core::LayeredAssemblyKind::Stair;
    }
    return tbe::core::LayeredAssemblyKind::Floor;
}

tbe::core::RoofType to_core_roof_type(ApiRoofType type) {
    switch (type) {
    case ApiRoofType::SimpleGable: return tbe::core::RoofType::SimpleGable;
    case ApiRoofType::AutoFootprint: return tbe::core::RoofType::AutoFootprint;
    case ApiRoofType::Flat: return tbe::core::RoofType::Flat;
    }
    return tbe::core::RoofType::Flat;
}

tbe::core::WallHeightMode to_core_wall_height_mode(ApiWallHeightMode mode) {
    return mode == ApiWallHeightMode::TopLevel ? tbe::core::WallHeightMode::TopLevel : tbe::core::WallHeightMode::Unconnected;
}

tbe::core::ProfileDraftMode to_core_profile_mode(ApiProfileDraftMode mode) {
    switch (mode) {
    case ApiProfileDraftMode::Rectangle: return tbe::core::ProfileDraftMode::Rectangle;
    case ApiProfileDraftMode::PickWalls: return tbe::core::ProfileDraftMode::PickWalls;
    case ApiProfileDraftMode::AutoRoom: return tbe::core::ProfileDraftMode::AutoRoom;
    case ApiProfileDraftMode::Polyline:
    default:
        return tbe::core::ProfileDraftMode::Polyline;
    }
}

tbe::core::ProfileTargetKind to_core_profile_target(ApiProfileTargetKind kind) {
    switch (kind) {
    case ApiProfileTargetKind::FloorBoundary: return tbe::core::ProfileTargetKind::FloorBoundary;
    case ApiProfileTargetKind::CeilingBoundary: return tbe::core::ProfileTargetKind::CeilingBoundary;
    case ApiProfileTargetKind::RoofBoundary: return tbe::core::ProfileTargetKind::RoofBoundary;
    case ApiProfileTargetKind::WallPath:
    default:
        return tbe::core::ProfileTargetKind::WallPath;
    }
}

ValidationIssueDTO to_validation_issue(const tbe::core::ValidationIssue& issue) {
    return ValidationIssueDTO{
        .severity = to_api_severity(issue.severity),
        .element_id = to_id(issue.element_id),
        .message = issue.message,
    };
}

ValidationReportDTO to_validation_report(const tbe::core::ValidationReport& report) {
    ValidationReportDTO dto{
        .issue_count = report.issue_count(),
        .warning_count = report.warning_count(),
        .error_count = report.error_count(),
    };
    dto.issues.reserve(report.issues.size());
    for (const auto& issue : report.issues) {
        dto.issues.push_back(to_validation_issue(issue));
    }
    return dto;
}

ElementSummaryDTO to_element_summary(const Element& element) {
    return ElementSummaryDTO{
        .id = to_id(element.id()),
        .kind = to_api_kind(element.kind()),
        .name = std::string(element.name()),
    };
}

RoomDTO to_room_dto(const Element& element) {
    const auto* room = element.room();
    return RoomDTO{
        .id = to_id(element.id()),
        .level_id = to_id(room == nullptr ? 0 : room->level_id),
        .centerline_boundary_polygon = room == nullptr ? std::vector<Vec2>{} : to_vec2_list(room->centerline_boundary_polygon),
        .interior_boundary_polygon = room == nullptr ? std::vector<Vec2>{} : to_vec2_list(room->interior_boundary_polygon),
        .centerline_area_square_meters = room == nullptr ? 0.0 : room->centerline_area_square_meters,
        .interior_area_square_meters = room == nullptr ? 0.0 : room->interior_area_square_meters,
        .centerline_perimeter_meters = room == nullptr ? 0.0 : room->centerline_perimeter_meters,
        .interior_perimeter_meters = room == nullptr ? 0.0 : room->interior_perimeter_meters,
        .baseboard_length_meters = room == nullptr ? 0.0 : room->baseboard_length_meters,
    };
}

Point2 to_point(Vec2 point) {
    return Point2{.x = point.x, .y = point.y};
}

std::vector<Point2> to_point_list(const std::vector<Vec2>& points) {
    std::vector<Point2> values;
    values.reserve(points.size());
    for (const auto& point : points) {
        values.push_back(to_point(point));
    }
    return values;
}

template <typename T>
ApiResult<T> success_result(T value) {
    ApiResult<T> result;
    result.value = std::move(value);
    return result;
}

ApiVoidResult success_void() {
    return ApiVoidResult{};
}

template <typename T>
ApiResult<T> error_result(ApiStatus status, std::string message) {
    ApiResult<T> result;
    result.status = status;
    result.message = std::move(message);
    return result;
}

ApiVoidResult error_void(ApiStatus status, std::string message) {
    ApiVoidResult result;
    result.status = status;
    result.message = std::move(message);
    return result;
}

FreshnessState dirty_or_stale(FreshnessState state) {
    return has_cached_state(state) ? FreshnessState::Stale : FreshnessState::Dirty;
}

int detect_schema_version_value(std::string_view json) {
    const auto key = std::string_view{"\"schema_version\":"};
    const auto pos = json.find(key);
    if (pos == std::string_view::npos) {
        return 0;
    }
    auto begin = pos + key.size();
    while (begin < json.size() && std::isspace(static_cast<unsigned char>(json[begin]))) {
        ++begin;
    }
    auto end = begin;
    while (end < json.size() && std::isdigit(static_cast<unsigned char>(json[end]))) {
        ++end;
    }
    if (end == begin) {
        return 0;
    }
    return std::stoi(std::string(json.substr(begin, end - begin)));
}

JsonPatchResult ensure_project_schema_version(std::string_view json) {
    JsonPatchResult result{.json = std::string(json)};
    if (detect_schema_version_value(result.json) != 0) {
        return result;
    }
    const auto schema_key = std::string_view{"\"schema\":\"tbe.project.v1\","};
    const auto schema_pos = result.json.find(schema_key);
    if (schema_pos != std::string::npos) {
        result.json.insert(schema_pos + schema_key.size(), "\"schema_version\":1,\"engine_version\":\"mvp-level12\",");
        ++result.changes;
        result.messages.push_back("added missing schema_version for legacy project");
    }
    return result;
}

JsonPatchResult patch_missing_opening_level_ids(std::string_view json) {
    JsonPatchResult result{.json = std::string(json)};
    std::size_t search_from = 0;
    while ((search_from = result.json.find("\"door\":{", search_from)) != std::string::npos) {
        const auto object_end = result.json.find('}', search_from);
        if (object_end == std::string::npos) {
            break;
        }
        if (result.json.find("\"level_id\":", search_from) > object_end) {
            result.json.insert(search_from + std::string("\"door\":{").size(), "\"level_id\":0,");
            ++result.changes;
            result.messages.push_back("added missing door level_id placeholder");
            search_from = object_end + std::string("\"level_id\":0,").size();
        } else {
            search_from = object_end;
        }
    }
    search_from = 0;
    while ((search_from = result.json.find("\"window\":{", search_from)) != std::string::npos) {
        const auto object_end = result.json.find('}', search_from);
        if (object_end == std::string::npos) {
            break;
        }
        if (result.json.find("\"level_id\":", search_from) > object_end) {
            result.json.insert(search_from + std::string("\"window\":{").size(), "\"level_id\":0,");
            ++result.changes;
            result.messages.push_back("added missing window level_id placeholder");
            search_from = object_end + std::string("\"level_id\":0,").size();
        } else {
            search_from = object_end;
        }
    }
    return result;
}

MigrationReportDTO migrate_json_to_current(std::string_view input_json, std::string& migrated_json, int from_version, int to_version) {
    migrated_json = std::string(input_json);
    MigrationReportDTO report{
        .from_version = from_version,
        .to_version = to_version,
    };
    if (from_version == to_version) {
        return report;
    }
    if (from_version == 0 && to_version == tbe::core::TBE_SCHEMA_VERSION) {
        auto schema_patch = ensure_project_schema_version(migrated_json);
        migrated_json = std::move(schema_patch.json);
        report.migrated_count += schema_patch.changes;
        report.messages.insert(report.messages.end(), schema_patch.messages.begin(), schema_patch.messages.end());

        auto opening_patch = patch_missing_opening_level_ids(migrated_json);
        migrated_json = std::move(opening_patch.json);
        report.migrated_count += opening_patch.changes;
        report.messages.insert(report.messages.end(), opening_patch.messages.begin(), opening_patch.messages.end());
        return report;
    }
    report.error_count = 1;
    report.messages.push_back("unsupported schema migration path");
    return report;
}

AABB2D expanded_bounds(AABB2D bounds, double amount) {
    return AABB2D{
        .min_x = bounds.min_x - amount,
        .min_y = bounds.min_y - amount,
        .max_x = bounds.max_x + amount,
        .max_y = bounds.max_y + amount,
    };
}

bool bounds_overlap(AABB2D left, AABB2D right) {
    return left.min_x <= right.max_x && left.max_x >= right.min_x &&
        left.min_y <= right.max_y && left.max_y >= right.min_y;
}

double interval_length(double start, double end) {
    return std::max(0.0, end - start);
}

} // namespace

struct EngineSession::Impl {
    explicit Impl(std::string project_name)
        : project(std::move(project_name)) {}

    Project project;
    std::vector<SessionTransaction> undo_stack{};
    std::vector<SessionTransaction> redo_stack{};
    PerformanceProfile performance_profile{PerformanceProfile::Balanced};
    ComputeMode compute_mode{ComputeMode::Normal};
    FreshnessSummaryDTO freshness{};
    std::optional<std::vector<RoomDTO>> cached_rooms{};
    std::optional<std::vector<WallScheduleDTO>> cached_wall_schedule{};
    std::optional<std::vector<OpeningScheduleDTO>> cached_opening_schedule{};
    std::optional<std::vector<RoomScheduleDTO>> cached_room_schedule{};
    std::optional<std::vector<MaterialTakeoffSummaryDTO>> cached_material_takeoff{};
    std::optional<ValidationReportDTO> cached_validation{};
    MigrationReportDTO last_migration_report{};
    RepairReportDTO last_repair_report{};
    std::map<ElementId, LevelSpatialIndex> spatial_index_by_level{};
    std::uint64_t spatial_index_version{0};
    bool spatial_index_dirty{true};
    // Final reports are pure reads after geometry regeneration. The pool
    // scales with the device but preserves one core for UI/OS responsiveness.
    tbe::core::JobSystem final_compute_jobs{recommended_final_compute_workers()};

    [[nodiscard]] Document& document() noexcept {
        return project.active_document();
    }

    [[nodiscard]] const Document& document() const noexcept {
        return project.active_document();
    }

    void clear_caches() {
        cached_rooms.reset();
        cached_wall_schedule.reset();
        cached_opening_schedule.reset();
        cached_room_schedule.reset();
        cached_material_takeoff.reset();
        cached_validation.reset();
    }

    void mark_all_derived_dirty() {
        freshness.room_metrics = dirty_or_stale(freshness.room_metrics);
        freshness.geometry = dirty_or_stale(freshness.geometry);
        freshness.schedules = dirty_or_stale(freshness.schedules);
        freshness.material_takeoff = dirty_or_stale(freshness.material_takeoff);
        freshness.validation_report = dirty_or_stale(freshness.validation_report);
        freshness.exports = dirty_or_stale(freshness.exports);
        spatial_index_dirty = true;
    }
};

EngineSession::EngineSession()
    : EngineSession("API Project") {}

EngineSession::EngineSession(std::string project_name)
    : impl_(std::make_unique<Impl>(std::move(project_name))) {}

EngineSession::~EngineSession() = default;
EngineSession::EngineSession(EngineSession&&) noexcept = default;
EngineSession& EngineSession::operator=(EngineSession&&) noexcept = default;

namespace {

std::vector<RoomDTO> build_room_cache(const Document& document) {
    std::vector<RoomDTO> rooms;
    for (const auto& element : document.elements()) {
        if (element.room() != nullptr) {
            rooms.push_back(to_room_dto(element));
        }
    }
    return rooms;
}

std::vector<WallScheduleDTO> build_wall_schedule_cache(const Document& document) {
    std::vector<WallScheduleDTO> rows;
    for (const auto& row : document.generate_wall_schedule()) {
        rows.push_back(WallScheduleDTO{
            .wall_id = to_id(row.wall_id),
            .level_id = to_id(row.level_id),
            .wall_type_name = row.wall_type_name,
            .length_meters = row.length_meters,
            .thickness_meters = row.thickness_meters,
            .height_meters = row.height_meters,
            .gross_area_square_meters = row.gross_area_square_meters,
            .opening_area_square_meters = row.opening_area_square_meters,
            .net_area_square_meters = row.net_area_square_meters,
            .gross_volume_cubic_meters = row.gross_volume_cubic_meters,
            .net_volume_cubic_meters = row.net_volume_cubic_meters,
            .material_volume_by_id = [&]() {
                std::map<std::uint64_t, double> volumes;
                for (const auto& [material_id, volume] : row.material_volume_by_id) {
                    volumes[material_id] = volume;
                }
                return volumes;
            }(),
            .material_cost_by_id = [&]() {
                std::map<std::uint64_t, double> costs;
                for (const auto& [material_id, cost] : row.material_cost_by_id) {
                    costs[material_id] = cost;
                }
                return costs;
            }(),
        });
    }
    return rows;
}

std::vector<OpeningScheduleDTO> build_opening_schedule_cache(const Document& document) {
    std::vector<OpeningScheduleDTO> rows;
    for (const auto& row : document.generate_opening_schedule()) {
        rows.push_back(OpeningScheduleDTO{
            .element_id = to_id(row.element_id),
            .type = row.type == tbe::core::OpeningKind::Door ? "Door" : "Window",
            .host_wall_id = to_id(row.host_wall_id),
            .width_meters = row.width_meters,
            .height_meters = row.height_meters,
            .area_square_meters = row.area_square_meters,
            .level_id = to_id(row.level_id),
        });
    }
    return rows;
}

std::vector<RoomScheduleDTO> build_room_schedule_cache(const Document& document) {
    std::vector<RoomScheduleDTO> rows;
    for (const auto& row : document.generate_room_schedule()) {
        rows.push_back(RoomScheduleDTO{
            .room_id = to_id(row.room_id),
            .level_id = to_id(row.level_id),
            .centerline_area_square_meters = row.centerline_area_square_meters,
            .interior_area_square_meters = row.interior_area_square_meters,
            .interior_perimeter_meters = row.interior_perimeter_meters,
            .baseboard_length_meters = row.baseboard_length_meters,
            .floor_finish_area_square_meters = row.floor_finish_area_square_meters,
            .ceiling_area_square_meters = row.ceiling_area_square_meters,
            .interior_wall_finish_area_square_meters = row.interior_wall_finish_area_square_meters,
        });
    }
    return rows;
}

std::vector<MaterialTakeoffSummaryDTO> build_material_takeoff_cache(const Document& document) {
    std::vector<MaterialTakeoffSummaryDTO> rows;
    for (const auto& row : document.generate_material_takeoff()) {
        const auto* material = document.get_material(row.material_id);
        rows.push_back(MaterialTakeoffSummaryDTO{
            .material_id = to_id(row.material_id),
            .material_name = row.material_name,
            .quantity_type = to_api_quantity_type(row.quantity_type),
            .quantity = row.quantity,
            .unit = row.unit,
            .unit_cost = material == nullptr ? std::nullopt : material->unit_cost,
            .estimated_cost = row.estimated_cost,
        });
    }
    return rows;
}

DirtySummaryDTO build_dirty_summary(const FreshnessSummaryDTO& freshness) {
    DirtySummaryDTO summary{
        .has_room_metrics_work = is_non_clean(freshness.room_metrics),
        .has_geometry_work = is_non_clean(freshness.geometry),
        .has_schedule_work = is_non_clean(freshness.schedules),
        .has_material_takeoff_work = is_non_clean(freshness.material_takeoff),
        .has_validation_work = is_non_clean(freshness.validation_report),
        .has_export_work = is_non_clean(freshness.exports),
    };
    const auto count_state = [&](FreshnessState state) {
        if (state == FreshnessState::Dirty) {
            ++summary.dirty_categories;
        } else if (state == FreshnessState::Stale) {
            ++summary.stale_categories;
        }
    };
    count_state(freshness.room_metrics);
    count_state(freshness.geometry);
    count_state(freshness.schedules);
    count_state(freshness.material_takeoff);
    count_state(freshness.validation_report);
    count_state(freshness.exports);
    return summary;
}

template <typename SessionImpl>
void rebuild_spatial_index_impl(SessionImpl& impl) {
    impl.spatial_index_by_level.clear();

    const auto append_entry = [&](ElementId level_id, SpatialEntry entry) {
        auto& level_index = impl.spatial_index_by_level[level_id];
        level_index.entries.push_back(std::move(entry));
    };

    for (const auto& element : impl.document().elements()) {
        if (const auto* wall = element.wall()) {
            const auto polygon = wall_body_polygon(wall->axis, wall->thickness_meters);
            append_entry(wall->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = wall->level_id,
                .kind = ApiElementKind::Wall,
                .preferred_hit_kind = HitKind::WallBody,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
                .axis = wall->axis,
                .thickness_meters = wall->thickness_meters,
            });
            const auto length_value = line_length(wall->axis);
            const auto direction = length_value <= 1.0e-12 ? Point2{} : Point2{.x = (wall->axis.end.x - wall->axis.start.x) / length_value, .y = (wall->axis.end.y - wall->axis.start.y) / length_value};
            const auto normal = Point2{.x = -direction.y * (wall->thickness_meters / 2.0), .y = direction.x * (wall->thickness_meters / 2.0)};
            for (const auto& opening : wall->openings) {
                const auto center = Point2{
                    .x = wall->axis.start.x + (direction.x * opening.offset_meters),
                    .y = wall->axis.start.y + (direction.y * opening.offset_meters),
                };
                const auto half_width = opening.width_meters / 2.0;
                std::vector<Point2> opening_polygon{
                    Point2{.x = center.x + (direction.x * half_width) + normal.x, .y = center.y + (direction.y * half_width) + normal.y},
                    Point2{.x = center.x - (direction.x * half_width) + normal.x, .y = center.y - (direction.y * half_width) + normal.y},
                    Point2{.x = center.x - (direction.x * half_width) - normal.x, .y = center.y - (direction.y * half_width) - normal.y},
                    Point2{.x = center.x + (direction.x * half_width) - normal.x, .y = center.y + (direction.y * half_width) - normal.y},
                };
                append_entry(wall->level_id, SpatialEntry{
                    .element_id = opening.element_id,
                    .level_id = wall->level_id,
                    .kind = opening.kind == tbe::core::OpeningKind::Door ? ApiElementKind::Door : ApiElementKind::Window,
                    .preferred_hit_kind = HitKind::Opening,
                    .bounds = bounds_from_points(opening_polygon),
                    .polygon = opening_polygon,
                    .axis = wall->axis,
                    .thickness_meters = wall->thickness_meters,
                });
            }
        } else if (const auto* room = element.room()) {
            append_entry(room->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = room->level_id,
                .kind = ApiElementKind::Room,
                .preferred_hit_kind = HitKind::RoomInterior,
                .bounds = bounds_from_points(room->interior_boundary_polygon.empty() ? room->centerline_boundary_polygon : room->interior_boundary_polygon),
                .polygon = room->interior_boundary_polygon.empty() ? room->centerline_boundary_polygon : room->interior_boundary_polygon,
            });
        } else if (const auto* slab = element.slab()) {
            append_entry(slab->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = slab->level_id,
                .kind = ApiElementKind::Slab,
                .preferred_hit_kind = HitKind::Slab,
                .bounds = bounds_from_points(slab->boundary_polygon),
                .polygon = slab->boundary_polygon,
            });
        } else if (const auto* roof = element.roof()) {
            append_entry(roof->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = roof->level_id,
                .kind = ApiElementKind::Roof,
                .preferred_hit_kind = HitKind::Roof,
                .bounds = bounds_from_points(roof->boundary_polygon),
                .polygon = roof->boundary_polygon,
            });
        } else if (const auto* column = element.column()) {
            const auto polygon = std::vector<Point2>{
                Point2{.x = column->position.x - (column->width_meters / 2.0), .y = column->position.y - (column->depth_meters / 2.0)},
                Point2{.x = column->position.x + (column->width_meters / 2.0), .y = column->position.y - (column->depth_meters / 2.0)},
                Point2{.x = column->position.x + (column->width_meters / 2.0), .y = column->position.y + (column->depth_meters / 2.0)},
                Point2{.x = column->position.x - (column->width_meters / 2.0), .y = column->position.y + (column->depth_meters / 2.0)},
            };
            append_entry(column->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = column->level_id,
                .kind = ApiElementKind::Column,
                .preferred_hit_kind = HitKind::Column,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
            });
        } else if (const auto* beam = element.beam()) {
            const auto polygon = wall_body_polygon(Line2{.start = beam->start, .end = beam->end}, beam->width_meters);
            append_entry(beam->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = beam->level_id,
                .kind = ApiElementKind::Beam,
                .preferred_hit_kind = HitKind::Beam,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
                .axis = Line2{.start = beam->start, .end = beam->end},
                .thickness_meters = beam->width_meters,
            });
        } else if (const auto* stair = element.stair()) {
            const auto direction_length = std::sqrt((stair->direction.x * stair->direction.x) + (stair->direction.y * stair->direction.y));
            if (direction_length > 1.0e-12) {
                const auto unit = Point2{.x = stair->direction.x / direction_length, .y = stair->direction.y / direction_length};
                const auto end = Point2{.x = stair->start.x + (unit.x * stair->total_run_meters), .y = stair->start.y + (unit.y * stair->total_run_meters)};
                const auto polygon = wall_body_polygon(Line2{.start = stair->start, .end = end}, stair->width_meters);
                append_entry(stair->base_level_id, SpatialEntry{
                    .element_id = element.id(),
                    .level_id = stair->base_level_id,
                    .kind = ApiElementKind::Stair,
                    .preferred_hit_kind = HitKind::Stair,
                    .bounds = bounds_from_points(polygon),
                    .polygon = polygon,
                });
            }
        } else if (const auto* proxy = element.proxy()) {
            const auto polygon = std::vector<Point2>{
                Point2{.x = proxy->position.x - (proxy->width_meters / 2.0), .y = proxy->position.y - (proxy->depth_meters / 2.0)},
                Point2{.x = proxy->position.x + (proxy->width_meters / 2.0), .y = proxy->position.y - (proxy->depth_meters / 2.0)},
                Point2{.x = proxy->position.x + (proxy->width_meters / 2.0), .y = proxy->position.y + (proxy->depth_meters / 2.0)},
                Point2{.x = proxy->position.x - (proxy->width_meters / 2.0), .y = proxy->position.y + (proxy->depth_meters / 2.0)},
            };
            append_entry(proxy->level_id, SpatialEntry{
                .element_id = element.id(),
                .level_id = proxy->level_id,
                .kind = ApiElementKind::Proxy,
                .preferred_hit_kind = HitKind::None,
                .bounds = bounds_from_points(polygon),
                .polygon = polygon,
            });
        }
    }

    for (const auto& [system_id, system] : impl.document().floor_systems()) {
        append_entry(system.level_id, SpatialEntry{
            .element_id = system_id,
            .level_id = system.level_id,
            .kind = ApiElementKind::FloorSystem,
            .preferred_hit_kind = HitKind::FloorSystem,
            .bounds = bounds_from_points(system.boundary_polygon),
            .polygon = system.boundary_polygon,
        });
    }
    for (const auto& [system_id, system] : impl.document().ceiling_systems()) {
        append_entry(system.level_id, SpatialEntry{
            .element_id = system_id,
            .level_id = system.level_id,
            .kind = ApiElementKind::CeilingSystem,
            .preferred_hit_kind = HitKind::CeilingSystem,
            .bounds = bounds_from_points(system.boundary_polygon),
            .polygon = system.boundary_polygon,
        });
    }

    for (auto& [_, level_index] : impl.spatial_index_by_level) {
        for (std::size_t index = 0; index < level_index.entries.size(); ++index) {
            const auto& bounds = level_index.entries[index].bounds;
            const auto min_x = static_cast<int>(std::floor(bounds.min_x / level_index.cell_size_meters));
            const auto max_x = static_cast<int>(std::floor(bounds.max_x / level_index.cell_size_meters));
            const auto min_y = static_cast<int>(std::floor(bounds.min_y / level_index.cell_size_meters));
            const auto max_y = static_cast<int>(std::floor(bounds.max_y / level_index.cell_size_meters));
            for (int gx = min_x; gx <= max_x; ++gx) {
                for (int gy = min_y; gy <= max_y; ++gy) {
                    level_index.buckets[{gx, gy}].push_back(index);
                }
            }
        }
    }

    impl.spatial_index_dirty = false;
    ++impl.spatial_index_version;
}

template <typename SessionImpl>
void ensure_spatial_index(SessionImpl& impl) {
    if (impl.spatial_index_dirty) {
        rebuild_spatial_index_impl(impl);
    }
}

template <typename SessionImpl>
const LevelSpatialIndex* find_level_spatial_index(SessionImpl& impl, ElementId level_id) {
    ensure_spatial_index(impl);
    const auto found = impl.spatial_index_by_level.find(level_id);
    if (found == impl.spatial_index_by_level.end()) {
        return nullptr;
    }
    return &found->second;
}

std::vector<std::size_t> query_level_indices(const LevelSpatialIndex& level_index, AABB2D bounds) {
    std::set<std::size_t> unique_indices;
    const auto min_x = static_cast<int>(std::floor(bounds.min_x / level_index.cell_size_meters));
    const auto max_x = static_cast<int>(std::floor(bounds.max_x / level_index.cell_size_meters));
    const auto min_y = static_cast<int>(std::floor(bounds.min_y / level_index.cell_size_meters));
    const auto max_y = static_cast<int>(std::floor(bounds.max_y / level_index.cell_size_meters));
    for (int gx = min_x; gx <= max_x; ++gx) {
        for (int gy = min_y; gy <= max_y; ++gy) {
            const auto found = level_index.buckets.find({gx, gy});
            if (found == level_index.buckets.end()) {
                continue;
            }
            unique_indices.insert(found->second.begin(), found->second.end());
        }
    }

    std::vector<std::size_t> filtered;
    filtered.reserve(unique_indices.size());
    for (const auto index : unique_indices) {
        if (index < level_index.entries.size() && bounds_overlap(level_index.entries[index].bounds, bounds)) {
            filtered.push_back(index);
        }
    }
    return filtered;
}

std::vector<WallFreeIntervalDTO> compute_wall_free_intervals_for_entry(const Element& wall_element, double requested_width_meters, double clearance_meters) {
    const auto* wall = wall_element.wall();
    if (wall == nullptr) {
        throw std::invalid_argument("element is not a wall");
    }

    const auto wall_length = line_length(wall->axis);
    const auto edge_margin = std::max(0.0, (requested_width_meters / 2.0) + clearance_meters);
    if (wall_length <= (2.0 * edge_margin)) {
        return {};
    }

    std::vector<std::pair<double, double>> blocked;
    blocked.push_back({0.0, edge_margin});
    blocked.push_back({wall_length - edge_margin, wall_length});
    for (const auto& opening : wall->openings) {
        const auto half_width = (opening.width_meters / 2.0) + clearance_meters + (requested_width_meters / 2.0);
        blocked.push_back({
            clamp(opening.offset_meters - half_width, 0.0, wall_length),
            clamp(opening.offset_meters + half_width, 0.0, wall_length),
        });
    }

    std::sort(blocked.begin(), blocked.end(), [](const auto& left, const auto& right) {
        if (std::abs(left.first - right.first) > 1.0e-9) {
            return left.first < right.first;
        }
        return left.second < right.second;
    });

    std::vector<std::pair<double, double>> merged;
    for (const auto& interval : blocked) {
        if (merged.empty() || interval.first > merged.back().second + 1.0e-9) {
            merged.push_back(interval);
            continue;
        }
        merged.back().second = std::max(merged.back().second, interval.second);
    }

    std::vector<WallFreeIntervalDTO> free_intervals;
    double cursor = 0.0;
    for (const auto& interval : merged) {
        if (interval.first > cursor + 1.0e-9) {
            free_intervals.push_back(WallFreeIntervalDTO{
                .start_offset_meters = cursor,
                .end_offset_meters = interval.first,
                .length_meters = interval_length(cursor, interval.first),
            });
        }
        cursor = std::max(cursor, interval.second);
    }
    if (cursor < wall_length - 1.0e-9) {
        free_intervals.push_back(WallFreeIntervalDTO{
            .start_offset_meters = cursor,
            .end_offset_meters = wall_length,
            .length_meters = interval_length(cursor, wall_length),
        });
    }

    free_intervals.erase(std::remove_if(free_intervals.begin(), free_intervals.end(), [](const auto& interval) {
        return interval.length_meters <= 1.0e-9;
    }), free_intervals.end());
    return free_intervals;
}

template <typename SessionImpl>
ApiVoidResult recompute_impl(SessionImpl& impl, ComputeMode mode) {
    try {
        if (mode == ComputeMode::FinalExact) {
            impl.freshness = FreshnessSummaryDTO{
                .room_metrics = FreshnessState::Computing,
                .geometry = FreshnessState::Computing,
                .schedules = FreshnessState::Computing,
                .material_takeoff = FreshnessState::Computing,
                .validation_report = FreshnessState::Computing,
                .exports = FreshnessState::Computing,
            };
            impl.document().recompute_all_rooms();
            // Assemblies remain semantic data. Interactive/final reports do
            // not need a separate mesh for every layer; keep the viewport
            // geometry at the single lightweight envelope level.
            impl.document().regenerate_dirty_geometry(tbe::core::GeometryDetail::Envelope);
            (void)impl.document().dependency_graph();
            const auto& document = impl.document();
            auto rooms_job = impl.final_compute_jobs.submit([&document]() {
                return build_room_cache(document);
            });
            auto wall_schedule_job = impl.final_compute_jobs.submit([&document]() {
                return build_wall_schedule_cache(document);
            });
            auto opening_schedule_job = impl.final_compute_jobs.submit([&document]() {
                return build_opening_schedule_cache(document);
            });
            auto room_schedule_job = impl.final_compute_jobs.submit([&document]() {
                return build_room_schedule_cache(document);
            });
            auto takeoff_job = impl.final_compute_jobs.submit([&document]() {
                return build_material_takeoff_cache(document);
            });
            auto validation_job = impl.final_compute_jobs.submit([&document]() {
                return to_validation_report(document.validate_document());
            });
            impl.cached_rooms = rooms_job.get();
            impl.cached_wall_schedule = wall_schedule_job.get();
            impl.cached_opening_schedule = opening_schedule_job.get();
            impl.cached_room_schedule = room_schedule_job.get();
            impl.cached_material_takeoff = takeoff_job.get();
            impl.cached_validation = validation_job.get();
            impl.freshness = FreshnessSummaryDTO{
                .room_metrics = FreshnessState::Clean,
                .geometry = FreshnessState::Clean,
                .schedules = FreshnessState::Clean,
                .material_takeoff = FreshnessState::Clean,
                .validation_report = FreshnessState::Clean,
                .exports = FreshnessState::Clean,
            };
            rebuild_spatial_index_impl(impl);
            return success_void();
        }

        impl.freshness.geometry = FreshnessState::Computing;
        impl.document().regenerate_dirty_geometry(tbe::core::GeometryDetail::Envelope);
        impl.freshness.geometry = FreshnessState::Clean;

        if (mode == ComputeMode::InteractivePreview) {
            // Room boundaries, schedules and cost takeoff are report data,
            // not viewport data. Leave them dirty/stale until an explicit
            // final/documentation request asks for exact calculations.
            impl.freshness.room_metrics = dirty_or_stale(impl.freshness.room_metrics);
            impl.freshness.schedules = dirty_or_stale(impl.freshness.schedules);
            impl.freshness.material_takeoff = dirty_or_stale(impl.freshness.material_takeoff);
            impl.freshness.validation_report = dirty_or_stale(impl.freshness.validation_report);
        } else {
            impl.freshness.room_metrics = FreshnessState::Computing;
            (void)impl.document().recompute_dirty_rooms();
            impl.cached_rooms = build_room_cache(impl.document());
            impl.freshness.room_metrics = FreshnessState::Clean;
        }
        impl.spatial_index_dirty = true;

        return success_void();
    } catch (const std::exception& error) {
        impl.freshness.room_metrics = FreshnessState::Failed;
        impl.freshness.geometry = FreshnessState::Failed;
        return error_void(status_from_exception(error), error.what());
    }
}

template <typename SessionImpl>
RepairReportDTO repair_project_impl(SessionImpl& impl, RepairOptionsDTO options) {
    RepairReportDTO report;
    auto& document = impl.document();

    std::vector<ElementId> elements_to_delete;
    const auto queue_delete = [&](ElementId element_id, std::string message) {
        if (std::find(elements_to_delete.begin(), elements_to_delete.end(), element_id) == elements_to_delete.end()) {
            elements_to_delete.push_back(element_id);
        }
        ++report.repaired_count;
        report.messages.push_back(std::move(message));
    };
    for (const auto& element : document.elements()) {
        if (const auto* door = element.door()) {
            const auto* host = document.find_ptr(door->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                if (options.remove_orphan_openings) {
                    queue_delete(element.id(), "removed orphan door");
                } else {
                    ++report.warning_count;
                    report.messages.push_back("orphan door left in place");
                }
                continue;
            }
            if (options.fix_opening_levels_from_host) {
                auto* mutable_element = document.find_ptr(element.id());
                auto* mutable_door = mutable_element == nullptr ? nullptr : mutable_element->door();
                if (mutable_door != nullptr && mutable_door->level_id != host->wall()->level_id) {
                    mutable_door->level_id = host->wall()->level_id;
                    mutable_element->touch();
                    ++report.repaired_count;
                    report.messages.push_back("fixed door level_id from host wall");
                }
            }
        } else if (const auto* window = element.window()) {
            const auto* host = document.find_ptr(window->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                if (options.remove_orphan_openings) {
                    queue_delete(element.id(), "removed orphan window");
                } else {
                    ++report.warning_count;
                    report.messages.push_back("orphan window left in place");
                }
                continue;
            }
            if (options.fix_opening_levels_from_host) {
                auto* mutable_element = document.find_ptr(element.id());
                auto* mutable_window = mutable_element == nullptr ? nullptr : mutable_element->window();
                if (mutable_window != nullptr && mutable_window->level_id != host->wall()->level_id) {
                    mutable_window->level_id = host->wall()->level_id;
                    mutable_element->touch();
                    ++report.repaired_count;
                    report.messages.push_back("fixed window level_id from host wall");
                }
            }
        } else if (const auto* wall = element.wall()) {
            auto* mutable_element = document.find_ptr(element.id());
            auto* mutable_wall = mutable_element == nullptr ? nullptr : mutable_element->wall();
            if (mutable_wall != nullptr && !mutable_wall->openings.empty()) {
                std::vector<tbe::core::HostedOpening> filtered;
                filtered.reserve(mutable_wall->openings.size());
                bool removed_orphans = false;
                for (const auto& opening : mutable_wall->openings) {
                    const auto* opening_element = document.find_ptr(opening.element_id);
                    const bool opening_matches_type =
                        (opening.kind == tbe::core::OpeningKind::Door && opening_element != nullptr && opening_element->door() != nullptr) ||
                        (opening.kind == tbe::core::OpeningKind::Window && opening_element != nullptr && opening_element->window() != nullptr);
                    if (!opening_matches_type) {
                        removed_orphans = true;
                        if (options.remove_orphan_openings) {
                            ++report.repaired_count;
                            report.messages.push_back("removed orphan wall opening");
                            continue;
                        }
                        ++report.warning_count;
                        report.messages.push_back("orphan wall opening left in place");
                    }
                    filtered.push_back(opening);
                }
                if (removed_orphans && options.remove_orphan_openings) {
                    mutable_wall->openings = std::move(filtered);
                    mutable_element->touch();
                }
            }
        } else if (const auto* room = element.room()) {
            auto invalid_boundary = false;
            for (const auto boundary_id : room->boundary_wall_ids) {
                const auto* boundary = document.find_ptr(boundary_id);
                if (boundary == nullptr || boundary->wall() == nullptr) {
                    invalid_boundary = true;
                    break;
                }
            }
            if (invalid_boundary && options.remove_invalid_rooms) {
                queue_delete(element.id(), "removed room with invalid boundary walls");
            }
        } else if (const auto* slab = element.slab()) {
            const auto missing_material = slab->material_id != 0 && document.get_material(slab->material_id) == nullptr;
            const auto missing_assembly = slab->assembly_id != 0 && document.get_layered_assembly(slab->assembly_id) == nullptr;
            if (slab->thickness_meters <= 0.0 || slab->boundary_polygon.size() < 3 || slab->area_square_meters <= 0.0 || missing_material || missing_assembly) {
                queue_delete(element.id(), "removed invalid slab");
            }
        } else if (const auto* roof = element.roof()) {
            const auto missing_material = roof->material_id != 0 && document.get_material(roof->material_id) == nullptr;
            const auto missing_assembly = roof->assembly_id != 0 && document.get_layered_assembly(roof->assembly_id) == nullptr;
            if (roof->thickness_meters <= 0.0 || roof->boundary_polygon.size() < 3 || roof->area_square_meters <= 0.0 || missing_material || missing_assembly) {
                queue_delete(element.id(), "removed invalid roof");
            }
        } else if (const auto* column = element.column()) {
            const auto missing_material = column->material_id != 0 && document.get_material(column->material_id) == nullptr;
            if (column->width_meters <= 0.0 || column->depth_meters <= 0.0 || column->height_meters <= 0.0 || missing_material) {
                queue_delete(element.id(), "removed invalid column");
            }
        } else if (const auto* beam = element.beam()) {
            const auto missing_material = beam->material_id != 0 && document.get_material(beam->material_id) == nullptr;
            const auto dx = beam->end.x - beam->start.x;
            const auto dy = beam->end.y - beam->start.y;
            if (beam->width_meters <= 0.0 || beam->height_meters <= 0.0 || std::sqrt((dx * dx) + (dy * dy)) <= 1.0e-9 || missing_material) {
                queue_delete(element.id(), "removed invalid beam");
            }
        } else if (const auto* stair = element.stair()) {
            const auto missing_material = stair->material_id != 0 && document.get_material(stair->material_id) == nullptr;
            const auto invalid_levels = document.find_ptr(stair->base_level_id) == nullptr || document.find_ptr(stair->base_level_id)->level() == nullptr ||
                (stair->top_level_id != 0 && (document.find_ptr(stair->top_level_id) == nullptr || document.find_ptr(stair->top_level_id)->level() == nullptr));
            if (stair->width_meters <= 0.0 || stair->total_rise_meters <= 0.0 || stair->total_run_meters <= 0.0 ||
                stair->riser_count <= 0 || stair->tread_count <= 0 || missing_material || invalid_levels) {
                queue_delete(element.id(), "removed invalid stair");
            }
        }
    }

    for (const auto element_id : elements_to_delete) {
        if (document.find_ptr(element_id) != nullptr) {
            document.delete_element(element_id);
        }
    }

    if (options.remove_duplicate_joins) {
        for (const auto& element : document.elements()) {
            const auto* wall = element.wall();
            if (wall == nullptr) {
                continue;
            }
            auto* mutable_element = document.find_ptr(element.id());
            auto* mutable_wall = mutable_element == nullptr ? nullptr : mutable_element->wall();
            if (mutable_wall == nullptr) {
                continue;
            }
            std::set<std::tuple<ElementId, long long, long long>> seen;
            std::vector<tbe::core::WallJoin> filtered;
            filtered.reserve(mutable_wall->joins.size());
            for (const auto& join : mutable_wall->joins) {
                const auto key = std::make_tuple(
                    join.other_wall_id,
                    static_cast<long long>(std::llround(join.point.x * 1000000.0)),
                    static_cast<long long>(std::llround(join.point.y * 1000000.0))
                );
                if (seen.insert(key).second) {
                    filtered.push_back(join);
                }
            }
            if (filtered.size() != mutable_wall->joins.size()) {
                mutable_wall->joins = std::move(filtered);
                mutable_element->touch();
                ++report.repaired_count;
                report.messages.push_back("removed duplicate wall joins");
            }
        }
    }

    if (options.regenerate_room_metrics) {
        document.recompute_all_rooms();
        ++report.repaired_count;
        report.messages.push_back("recomputed room metrics");
    }
    if (options.regenerate_geometry) {
        document.regenerate_dirty_geometry();
        ++report.repaired_count;
        report.messages.push_back("regenerated dirty geometry");
    }

    (void)document.dependency_graph();
    return report;
}

template <typename SessionImpl, typename Fn>
ApiVoidResult apply_mutation(SessionImpl& impl, const std::string& name, Fn&& fn) {
    const auto before = impl.project.to_json();
    try {
        fn(impl.document());
        const auto after = impl.project.to_json();
        if (after != before) {
            impl.undo_stack.push_back(SessionTransaction{
                .name = name,
                .before_json = before,
                .after_json = after,
            });
            impl.redo_stack.clear();
            impl.mark_all_derived_dirty();
            if (impl.performance_profile == PerformanceProfile::Performance && impl.compute_mode != ComputeMode::InteractivePreview) {
                (void)recompute_impl(impl, ComputeMode::Normal);
            }
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

template <typename SessionImpl, typename T, typename Fn>
ApiResult<T> apply_mutation_with_value(SessionImpl& impl, const std::string& name, T& value, Fn&& fn) {
    const auto before = impl.project.to_json();
    try {
        fn(impl.document(), value);
        const auto after = impl.project.to_json();
        if (after != before) {
            impl.undo_stack.push_back(SessionTransaction{
                .name = name,
                .before_json = before,
                .after_json = after,
            });
            impl.redo_stack.clear();
            impl.mark_all_derived_dirty();
            if (impl.performance_profile == PerformanceProfile::Performance && impl.compute_mode != ComputeMode::InteractivePreview) {
                (void)recompute_impl(impl, ComputeMode::Normal);
            }
        }
        return success_result(std::move(value));
    } catch (const std::exception& error) {
        return error_result<T>(status_from_exception(error), error.what());
    }
}

template <typename T, typename Fn>
ApiResult<T> query_result(Fn&& fn) {
    try {
        return success_result(fn());
    } catch (const std::exception& error) {
        return error_result<T>(status_from_exception(error), error.what());
    }
}

ApiVoidResult query_void(const std::function<void()>& fn) {
    try {
        fn();
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

} // namespace

ApiVoidResult EngineSession::new_project(std::string project_name) {
    try {
        impl_->project = Project(std::move(project_name));
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_migration_report = MigrationReportDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::current_project() const {
    return success_result(std::string(impl_->project.name()));
}

ApiVoidResult EngineSession::clear_project() {
    try {
        const auto current_name = std::string(impl_->project.name());
        impl_->project = Project(current_name.empty() ? "API Project" : current_name);
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_migration_report = MigrationReportDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::load_project_json(std::string_view json) {
    return load_project_json_with_mode(json, LoadMode::Strict);
}

ApiVoidResult EngineSession::load_project_json_with_mode(std::string_view json, LoadMode mode) {
    try {
        std::string migrated_json;
        const auto detected_version = detect_schema_version_value(json);
        impl_->last_migration_report = migrate_json_to_current(json, migrated_json, detected_version, tbe::core::TBE_SCHEMA_VERSION);
        if (impl_->last_migration_report.error_count > 0) {
            return error_void(ApiStatus::InvalidArgument, impl_->last_migration_report.messages.front());
        }
        impl_->project = Project::from_json(migrated_json);
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->last_repair_report = RepairReportDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        const auto validation = impl_->document().validate_document();
        if (mode == LoadMode::Repair) {
            impl_->last_repair_report = repair_project_impl(*impl_, RepairOptionsDTO{});
            impl_->clear_caches();
            impl_->mark_all_derived_dirty();
            rebuild_spatial_index_impl(*impl_);
            return success_void();
        }
        if (mode == LoadMode::Strict && validation.error_count() > 0) {
            const auto detail = validation.issues.empty()
                ? std::string{"invalid project data"}
                : validation.issues.front().message;
            return error_void(ApiStatus::ValidationError, "strict load rejected invalid project data: " + detail);
        }
        if (mode == LoadMode::Tolerant && (validation.warning_count() > 0 || validation.error_count() > 0)) {
            ApiVoidResult result = success_void();
            result.message = "project loaded in tolerant mode with validation warnings";
            for (const auto& issue : validation.issues) {
                result.validation_issues.push_back(to_validation_issue(issue));
            }
            return result;
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<int> EngineSession::get_schema_version() const {
    return success_result(tbe::core::TBE_SCHEMA_VERSION);
}

ApiResult<int> EngineSession::detect_schema_version_from_json(std::string_view json) const {
    return success_result(detect_schema_version_value(json));
}

ApiResult<std::string> EngineSession::migrate_project_json(std::string_view json, int from_version, int to_version) const {
    std::string migrated_json;
    auto report = migrate_json_to_current(json, migrated_json, from_version, to_version);
    if (report.error_count > 0) {
        return error_result<std::string>(ApiStatus::InvalidArgument, report.messages.empty() ? "migration failed" : report.messages.front());
    }
    return success_result(std::move(migrated_json));
}

ApiResult<MigrationReportDTO> EngineSession::get_last_migration_report() const {
    return success_result(impl_->last_migration_report);
}

ApiResult<RepairReportDTO> EngineSession::get_last_repair_report() const {
    return success_result(impl_->last_repair_report);
}

ApiResult<RepairReportDTO> EngineSession::repair_current_project(RepairOptionsDTO options) {
    impl_->last_repair_report = repair_project_impl(*impl_, options);
    impl_->clear_caches();
    impl_->mark_all_derived_dirty();
    rebuild_spatial_index_impl(*impl_);
    return success_result(impl_->last_repair_report);
}

ApiVoidResult EngineSession::export_project_package(const std::string& path, PackageExportOptionsDTO options) const {
    namespace fs = std::filesystem;
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return error_void(recompute.status, recompute.message);
        }
        const fs::path root(path);
        fs::create_directories(root / "exports");
        fs::create_directories(root / "debug");
        {
            std::ofstream project_file(root / "project.json");
            project_file << impl_->project.to_json();
        }
        {
            std::ofstream metadata_file(root / "metadata.json");
            metadata_file << "{\"schema_version\":" << tbe::core::TBE_SCHEMA_VERSION
                          << ",\"engine_version\":\"" << tbe::core::TBE_ENGINE_VERSION
                          << "\",\"project_name\":\"" << impl_->project.name() << "\"}";
        }
        if (options.include_floorplan_svg) {
            impl_->document().export_floorplan_svg(root / "exports" / "floorplan.svg");
        }
        if (options.include_walls_obj) {
            impl_->document().export_mesh_obj(root / "exports" / "walls.obj");
        }
        if (options.include_debug_report_json) {
            impl_->document().export_debug_report_json(root / "debug" / "debug_report.json");
        }
        {
            std::ofstream render_scene_file(root / "exports" / "render_scene.json");
            render_scene_file << render_scene_to_json(build_render_scene(impl_->document()));
        }
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::import_project_package(const std::string& path, LoadMode mode) {
    namespace fs = std::filesystem;
    try {
        const fs::path root(path);
        std::ifstream project_file(root / "project.json");
        if (!project_file) {
            return error_void(ApiStatus::NotFound, "project package is missing project.json");
        }
        std::ostringstream buffer;
        buffer << project_file.rdbuf();
        return load_project_json_with_mode(buffer.str(), mode);
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<RenderSceneDTO> EngineSession::get_render_scene() const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return error_result<RenderSceneDTO>(recompute.status, recompute.message);
        }
        return success_result(build_render_scene(impl_->document()));
    } catch (const std::exception& error) {
        return error_result<RenderSceneDTO>(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::get_render_scene_json() const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::InteractivePreview);
        if (!recompute.ok()) {
            return error_result<std::string>(recompute.status, recompute.message);
        }
        return success_result(render_scene_to_json(build_render_scene(
            impl_->document(), nullptr, RenderSceneDetail::Interactive)));
    } catch (const std::exception& error) {
        return error_result<std::string>(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::get_render_scene_json_primary(
    std::uint64_t active_level_id
) const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::InteractivePreview);
        if (!recompute.ok()) {
            return error_result<std::string>(recompute.status, recompute.message);
        }
        const auto& document = impl_->document();
        std::vector<std::pair<double, ElementId>> levels;
        for (const auto& element : document.elements()) {
            if (const auto* level = element.level(); level != nullptr) {
                levels.emplace_back(level->elevation_meters, element.id());
            }
        }
        std::sort(levels.begin(), levels.end());
        const auto active = std::find_if(levels.begin(), levels.end(), [active_level_id](const auto& entry) {
            return entry.second == active_level_id;
        });
        if (active == levels.end()) {
            return error_result<std::string>(ApiStatus::NotFound, "active render level does not exist");
        }
        const auto active_index = static_cast<int>(std::distance(levels.begin(), active));
        std::set<ElementId> visible_levels;
        for (auto index = std::max(0, active_index - 1);
             index <= std::min(static_cast<int>(levels.size()) - 1, active_index + 1);
             ++index) {
            visible_levels.insert(levels[static_cast<std::size_t>(index)].second);
        }
        return success_result(render_scene_to_json(build_render_scene(
            document,
            &visible_levels,
            RenderSceneDetail::Interactive,
            RenderSceneStage::Primary)));
    } catch (const std::exception& error) {
        return error_result<std::string>(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::get_render_scene_json_near_level(
    std::uint64_t active_level_id,
    int adjacent_level_count
) const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::InteractivePreview);
        if (!recompute.ok()) {
            return error_result<std::string>(recompute.status, recompute.message);
        }
        const auto& document = impl_->document();
        std::vector<std::pair<double, ElementId>> levels;
        for (const auto& element : document.elements()) {
            if (const auto* level = element.level(); level != nullptr) {
                levels.emplace_back(level->elevation_meters, element.id());
            }
        }
        std::sort(levels.begin(), levels.end());
        const auto active = std::find_if(levels.begin(), levels.end(), [active_level_id](const auto& entry) {
            return entry.second == active_level_id;
        });
        if (active == levels.end()) {
            return error_result<std::string>(ApiStatus::NotFound, "active render level does not exist");
        }
        const auto radius = std::max(0, adjacent_level_count);
        const auto active_index = static_cast<int>(std::distance(levels.begin(), active));
        std::set<ElementId> visible_levels;
        for (auto index = std::max(0, active_index - radius);
             index <= std::min(static_cast<int>(levels.size()) - 1, active_index + radius);
             ++index) {
            visible_levels.insert(levels[static_cast<std::size_t>(index)].second);
        }
        return success_result(render_scene_to_json(build_render_scene(
            document, &visible_levels, RenderSceneDetail::Interactive)));
    } catch (const std::exception& error) {
        return error_result<std::string>(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::get_section_scene_json(Vec2 start, Vec2 end) const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::InteractivePreview);
        if (!recompute.ok()) {
            return error_result<std::string>(recompute.status, recompute.message);
        }
        return success_result(render_scene_to_json(build_section_scene(impl_->document(), start, end)));
    } catch (const std::exception& error) {
        return error_result<std::string>(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::export_render_scene_json(const std::string& path) const {
    namespace fs = std::filesystem;
    try {
        // A render export is a viewport operation.  Do not block it on
        // schedules, material takeoff, or the full validation report; those
        // expensive derived products are generated by their explicit report
        // APIs.  Normal mode still refreshes room-dependent scene data.
        auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
        if (!recompute.ok()) {
            return error_void(recompute.status, recompute.message);
        }
        const fs::path output(path);
        if (!output.parent_path().empty()) {
            fs::create_directories(output.parent_path());
        }
        std::ofstream file(output);
        if (!file) {
            return error_void(ApiStatus::InternalError, "failed to open render scene export path");
        }
        file << render_scene_to_json(build_render_scene(impl_->document()));
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::string> EngineSession::save_project_json() const {
    // Project JSON is the semantic source of truth. Saving it must not force
    // room discovery, schedules or material-cost takeoff; those are explicit
    // report operations. Geometry is regenerated lazily when a viewport or
    // export asks for it.
    ApiResult<std::string> result = query_result<std::string>([&]() {
        return impl_->project.to_json();
    });
    result.freshness = impl_->freshness.exports;
    if (result.freshness != FreshnessState::Clean) {
        result.message = "project JSON saved; derived report data remains stale";
    }
    return result;
}

ApiResult<std::string> EngineSession::save_project_json_cached(bool allow_stale) const {
    if (!allow_stale) {
        return save_project_json();
    }
    ApiResult<std::string> result = query_result<std::string>([&]() {
        return impl_->project.to_json();
    });
    result.freshness = impl_->freshness.exports;
    if (impl_->freshness.exports != FreshnessState::Clean) {
        result.message = "project JSON may include stale derived metrics";
    }
    return result;
}

ApiResult<std::string> EngineSession::get_engine_version() const {
    return success_result(std::string(kEngineVersion));
}

ApiResult<std::string> EngineSession::get_core_version() const {
    return success_result(std::string(kCoreVersion));
}

ApiResult<std::string> EngineSession::get_api_version() const {
    return success_result(std::string(kApiVersion));
}

ApiVoidResult EngineSession::set_performance_profile(PerformanceProfile profile) {
    impl_->performance_profile = profile;
    return success_void();
}

ApiResult<PerformanceProfile> EngineSession::get_performance_profile() const {
    return success_result(impl_->performance_profile);
}

ApiVoidResult EngineSession::set_compute_mode(ComputeMode mode) {
    impl_->compute_mode = mode;
    return success_void();
}

ApiResult<ComputeMode> EngineSession::get_compute_mode() const {
    return success_result(impl_->compute_mode);
}

ApiResult<ElementIdDTO> EngineSession::create_residential_template(int building_count, int story_count) {
    ElementIdDTO primary_level{};
    try {
        // Build outside the live session first.  A malformed template can
        // therefore never leave the user with a half-created project.
        auto template_project = make_residential_template(building_count, story_count);
        impl_->project = std::move(template_project);
        for (const auto& element : impl_->document().elements()) {
            if (element.level() != nullptr) {
                primary_level.value = element.id();
                break;
            }
        }
        if (primary_level.value == 0) {
            return error_result<ElementIdDTO>(ApiStatus::InternalError, "residential template did not create a level");
        }
        impl_->undo_stack.clear();
        impl_->redo_stack.clear();
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->mark_all_derived_dirty();
        (void)recompute_impl(*impl_, ComputeMode::InteractivePreview);
        rebuild_spatial_index_impl(*impl_);
        return success_result(primary_level);
    } catch (const std::exception& error) {
        return error_result<ElementIdDTO>(status_from_exception(error), error.what());
    }
}

ApiResult<DirtySummaryDTO> EngineSession::get_dirty_summary() const {
    return success_result(build_dirty_summary(impl_->freshness));
}

ApiResult<FreshnessSummaryDTO> EngineSession::get_freshness_summary() const {
    return success_result(impl_->freshness);
}

ApiVoidResult EngineSession::recompute_dirty() {
    return recompute_impl(*impl_, impl_->compute_mode);
}

ApiVoidResult EngineSession::recompute_all_final() {
    return recompute_impl(*impl_, ComputeMode::FinalExact);
}

ApiVoidResult EngineSession::rebuild_spatial_index() {
    return query_void([&]() {
        ensure_spatial_index(*impl_);
    });
}

ApiResult<std::uint64_t> EngineSession::spatial_index_version() const {
    ensure_spatial_index(*impl_);
    return success_result(impl_->spatial_index_version);
}

ApiResult<SpatialIndexStatsDTO> EngineSession::spatial_index_stats() const {
    ensure_spatial_index(*impl_);
    std::size_t total_entries = 0;
    std::size_t total_buckets = 0;
    std::size_t total_bucket_occupancy = 0;
    std::size_t max_bucket_occupancy = 0;
    for (const auto& [_, level_index] : impl_->spatial_index_by_level) {
        total_entries += level_index.entries.size();
        total_buckets += level_index.buckets.size();
        for (const auto& [__, indices] : level_index.buckets) {
            total_bucket_occupancy += indices.size();
            max_bucket_occupancy = std::max(max_bucket_occupancy, indices.size());
        }
    }
    return success_result(SpatialIndexStatsDTO{
        .version = impl_->spatial_index_version,
        .element_bounds_count = total_entries,
        .bucket_count = total_buckets,
        .average_bucket_occupancy = total_buckets == 0 ? 0.0 : static_cast<double>(total_bucket_occupancy) / static_cast<double>(total_buckets),
        .max_bucket_occupancy = max_bucket_occupancy,
        .dirty = impl_->spatial_index_dirty,
    });
}

ApiResult<std::vector<ElementSummaryDTO>> EngineSession::query_rect(ElementIdDTO level_id, AABB2D bounds) const {
    ensure_spatial_index(*impl_);
    const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
    if (level_index == nullptr) {
        return error_result<std::vector<ElementSummaryDTO>>(ApiStatus::NotFound, "level spatial index not found");
    }

    std::vector<ElementSummaryDTO> result;
    for (const auto entry_index : query_level_indices(*level_index, bounds)) {
        const auto& entry = level_index->entries.at(entry_index);
        const auto* element = impl_->document().find_ptr(entry.element_id);
        result.push_back(ElementSummaryDTO{
            .id = to_id(entry.element_id),
            .kind = entry.kind,
            .name = element == nullptr ? std::string{} : std::string(element->name()),
        });
    }
    return success_result(std::move(result));
}

ApiResult<ElementIdDTO> EngineSession::create_level(std::string name, double elevation_meters, double default_wall_height_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_level", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_level(std::move(name), elevation_meters, default_wall_height_meters));
    });
}

ApiVoidResult EngineSession::update_level(
    std::uint64_t level_id,
    std::optional<std::string> name,
    std::optional<double> elevation_meters,
    std::optional<double> default_wall_height_meters
) {
    return apply_mutation(*impl_, "update_level", [&](Document& document) {
        document.update_level(level_id, std::move(name), elevation_meters, default_wall_height_meters);
    });
}

ApiVoidResult EngineSession::move_level_elevation(std::uint64_t level_id, double elevation_meters) {
    return apply_mutation(*impl_, "move_level_elevation", [&](Document& document) {
        document.move_level_elevation(level_id, elevation_meters);
    });
}

ApiResult<ElementIdDTO> EngineSession::create_wall(std::string name, Vec2 start, Vec2 end, double thickness_meters, double height_meters, std::uint64_t level_id) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_wall", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_wall(std::move(name), Line2{.start = to_point(start), .end = to_point(end)}, thickness_meters, height_meters, level_id));
    });
}

ApiVoidResult EngineSession::set_wall_type(std::uint64_t wall_id, std::uint64_t wall_type_id) {
    return apply_mutation(*impl_, "set_wall_type", [&](Document& document) {
        document.set_wall_type(wall_id, wall_type_id);
    });
}

ApiResult<ElementIdDTO> EngineSession::create_wall_type(
    ApiWallTypeCategory category,
    std::string name,
    std::vector<AssemblyLayerDTO> layers,
    int core_start_layer,
    int core_end_layer
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_wall_type", created, [&](Document& document, ElementIdDTO& out) {
        std::vector<tbe::core::WallAssemblyLayer> core_layers;
        core_layers.reserve(layers.size());
        for (const auto& layer : layers) {
            core_layers.push_back(tbe::core::WallAssemblyLayer{
                .material_id = layer.material_id.value,
                .thickness_meters = layer.thickness_meters,
                .function = to_core_layer_function(layer.function),
                .priority = layer.priority,
                .structural = layer.structural,
                .side = to_core_layer_side(layer.side),
                .wraps_openings = layer.wraps_openings,
                .wraps_ends = layer.wraps_ends,
            });
        }
        auto wall_type_id = document.create_wall_type(std::move(name), std::move(core_layers), to_core_wall_type_category(category));
        if (core_start_layer >= 0 || core_end_layer >= 0) {
            auto wall_type = *document.get_wall_type(wall_type_id);
            wall_type.core_start_layer = core_start_layer;
            wall_type.core_end_layer = core_end_layer;
            document.update_wall_type(std::move(wall_type));
        }
        out = to_id(wall_type_id);
    });
}

ApiVoidResult EngineSession::update_wall_type(WallTypeDTO wall_type) {
    return apply_mutation(*impl_, "update_wall_type", [&](Document& document) {
        tbe::core::WallTypeData core_type{
            .wall_type_id = wall_type.id.value,
            .name = std::move(wall_type.name),
            .category = to_core_wall_type_category(wall_type.category),
            .core_start_layer = wall_type.core_start_layer,
            .core_end_layer = wall_type.core_end_layer,
        };
        for (const auto& layer : wall_type.layers) {
            core_type.layers.push_back(tbe::core::WallAssemblyLayer{
                .material_id = layer.material_id.value,
                .thickness_meters = layer.thickness_meters,
                .function = to_core_layer_function(layer.function),
                .priority = layer.priority,
                .structural = layer.structural,
                .side = to_core_layer_side(layer.side),
                .wraps_openings = layer.wraps_openings,
                .wraps_ends = layer.wraps_ends,
            });
        }
        document.update_wall_type(std::move(core_type));
    });
}

ApiResult<std::vector<WallTypeDTO>> EngineSession::list_wall_types() const {
    return query_result<std::vector<WallTypeDTO>>([&]() {
        std::vector<WallTypeDTO> rows;
        for (const auto& [wall_type_id, wall_type] : impl_->document().wall_types()) {
        WallTypeDTO row{
                .id = to_id(wall_type_id),
                .name = wall_type.name,
                .category = to_api_wall_type_category(wall_type.category),
                .total_thickness_meters = std::accumulate(wall_type.layers.begin(), wall_type.layers.end(), 0.0, [](double total, const auto& layer) { return total + layer.thickness_meters; }),
                .core_start_layer = wall_type.core_start_layer,
                .core_end_layer = wall_type.core_end_layer,
            };
            for (const auto& layer : wall_type.layers) {
                row.layers.push_back(AssemblyLayerDTO{
                    .material_id = to_id(layer.material_id),
                    .thickness_meters = layer.thickness_meters,
                    .function = to_api_layer_function(layer.function),
                    .priority = layer.priority,
                    .structural = layer.structural,
                    .side = to_api_layer_side(layer.side),
                    .wraps_openings = layer.wraps_openings,
                    .wraps_ends = layer.wraps_ends,
                });
            }
            rows.push_back(std::move(row));
        }
        return rows;
    });
}

ApiVoidResult EngineSession::set_wall_level_constraints(
    std::uint64_t wall_id,
    std::uint64_t base_level_id,
    std::uint64_t top_level_id,
    double base_offset_meters,
    double top_offset_meters,
    ApiWallHeightMode height_mode
) {
    return apply_mutation(*impl_, "set_wall_level_constraints", [&](Document& document) {
        document.set_wall_level_constraints(
            wall_id,
            base_level_id,
            top_level_id,
            base_offset_meters,
            top_offset_meters,
            to_core_wall_height_mode(height_mode)
        );
    });
}

ApiResult<ElementIdDTO> EngineSession::create_door(std::string name, std::uint64_t host_wall_id, double offset_meters, double width_meters, double height_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_door", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_door(std::move(name), host_wall_id, offset_meters, width_meters, height_meters));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_window(
    std::string name,
    std::uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_window", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_window(std::move(name), host_wall_id, offset_meters, width_meters, height_meters, sill_height_meters));
    });
}

ApiVoidResult EngineSession::set_opening_level_lock(std::uint64_t opening_id, bool locked) {
    return apply_mutation(*impl_, "set_opening_level_lock", [&](Document& document) {
        document.set_opening_level_lock(opening_id, locked);
    });
}

ApiVoidResult EngineSession::set_opening_level(std::uint64_t opening_id, std::uint64_t level_id) {
    return apply_mutation(*impl_, "set_opening_level", [&](Document& document) {
        document.set_opening_level(opening_id, level_id);
    });
}

ApiVoidResult EngineSession::set_opening_level_constraint(
    std::uint64_t opening_id,
    std::uint64_t level_id,
    double level_offset_meters
) {
    return apply_mutation(*impl_, "set_opening_level_constraint", [&](Document& document) {
        document.set_opening_level_constraint(opening_id, level_id, level_offset_meters);
    });
}

ApiResult<std::vector<ElementIdDTO>> EngineSession::create_elements_from_profile(ProfileDraftDTO draft) {
    std::vector<ElementIdDTO> created;
    return apply_mutation_with_value(*impl_, "create_elements_from_profile", created, [&](Document& document, std::vector<ElementIdDTO>& out) {
        tbe::core::ProfileDraft core_draft{
            .mode = to_core_profile_mode(draft.mode),
            .target_kind = to_core_profile_target(draft.target_kind),
            .level_id = draft.level_id.value,
            .closed = draft.closed,
            .thickness_meters = draft.thickness_meters,
            .height_meters = draft.height_meters,
            .vertical_offset_meters = draft.vertical_offset_meters,
            .material_id = draft.material_id.value,
            .assembly_id = draft.assembly_id.value,
            .roof_type = to_core_roof_type(draft.roof_type),
        };
        core_draft.points.reserve(draft.points.size());
        for (const auto& point : draft.points) {
            core_draft.points.push_back(to_point(point));
        }
        core_draft.picked_wall_ids.reserve(draft.picked_wall_ids.size());
        for (const auto& wall_id : draft.picked_wall_ids) {
            core_draft.picked_wall_ids.push_back(wall_id.value);
        }
        for (const auto id : document.create_elements_from_profile(core_draft)) {
            out.push_back(to_id(id));
        }
    });
}

ApiResult<std::vector<RoomDTO>> EngineSession::detect_rooms() {
    std::vector<RoomDTO> rooms;
    auto result = apply_mutation_with_value(*impl_, "detect_rooms", rooms, [&](Document& document, std::vector<RoomDTO>& out) {
        const auto room_ids = document.detect_rooms();
        out.reserve(room_ids.size());
        for (const auto room_id : room_ids) {
            const auto* element = document.find_ptr(room_id);
            if (element != nullptr && element->room() != nullptr) {
                out.push_back(to_room_dto(*element));
            }
        }
    });
    if (result.ok() && result.value.has_value()) {
        impl_->cached_rooms = *result.value;
        impl_->freshness.room_metrics = FreshnessState::Clean;
        impl_->freshness.geometry = dirty_or_stale(impl_->freshness.geometry);
        impl_->freshness.schedules = dirty_or_stale(impl_->freshness.schedules);
        result.freshness = FreshnessState::Clean;
    }
    return result;
}

ApiVoidResult EngineSession::auto_join_walls() {
    return apply_mutation(*impl_, "auto_join_walls", [&](Document& document) {
        document.auto_join_walls();
    });
}

ApiVoidResult EngineSession::set_wall_axis(std::uint64_t wall_id, Vec2 start, Vec2 end) {
    return apply_mutation(*impl_, "set_wall_axis", [&](Document& document) {
        document.set_wall_axis_with_joins(wall_id, Line2{.start = to_point(start), .end = to_point(end)});
    });
}

ApiVoidResult EngineSession::trim_extend_walls(
    std::uint64_t first_wall_id,
    bool first_uses_start,
    std::uint64_t second_wall_id,
    bool second_uses_start
) {
    return apply_mutation(*impl_, "trim_extend_walls", [&](Document& document) {
        document.trim_extend_walls(
            first_wall_id,
            first_uses_start,
            second_wall_id,
            second_uses_start
        );
    });
}

ApiVoidResult EngineSession::update_wall_properties(std::uint64_t wall_id, double thickness_meters, double height_meters, std::uint64_t wall_type_id) {
    return apply_mutation(*impl_, "update_wall_properties", [&](Document& document) {
        document.set_wall_properties(wall_id, thickness_meters, height_meters, wall_type_id);
    });
}

ApiVoidResult EngineSession::set_element_assembly(std::uint64_t element_id, std::uint64_t assembly_id) {
    return apply_mutation(*impl_, "set_element_assembly", [&](Document& document) {
        document.set_element_assembly(element_id, assembly_id);
    });
}

ApiResult<ElementIdDTO> EngineSession::create_material(
    std::string name,
    ApiMaterialCategory category,
    std::optional<double> density_kg_per_m3,
    std::optional<double> unit_cost,
    std::string display_color
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_material", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_material(
            std::move(name),
            to_core_material_category(category),
            density_kg_per_m3,
            unit_cost,
            {},
            std::move(display_color)
        ));
    });
}

ApiVoidResult EngineSession::update_material(MaterialDTO material) {
    return apply_mutation(*impl_, "update_material", [&](Document& document) {
        document.update_material(tbe::core::MaterialDefinition{
            .material_id = material.id.value,
            .name = std::move(material.name),
            .category = to_core_material_category(material.category),
            .density_kg_per_m3 = material.density_kg_per_m3,
            .unit_cost = material.unit_cost,
            .display_color = std::move(material.display_color),
        });
    });
}

ApiResult<std::vector<MaterialDTO>> EngineSession::list_materials() const {
    return query_result<std::vector<MaterialDTO>>([&]() {
        std::vector<MaterialDTO> rows;
        for (const auto& [material_id, material] : impl_->document().materials()) {
            rows.push_back(MaterialDTO{
                .id = to_id(material_id),
                .name = material.name,
                .category = to_api_material_category(material.category),
                .density_kg_per_m3 = material.density_kg_per_m3,
                .unit_cost = material.unit_cost,
                .display_color = material.display_color,
            });
        }
        return rows;
    });
}

ApiResult<ElementIdDTO> EngineSession::create_layered_assembly(
    ApiLayeredAssemblyKind kind,
    std::string name,
    std::vector<AssemblyLayerDTO> layers,
    int core_start_layer,
    int core_end_layer
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_layered_assembly", created, [&](Document& document, ElementIdDTO& out) {
        std::vector<tbe::core::WallAssemblyLayer> core_layers;
        core_layers.reserve(layers.size());
        for (const auto& layer : layers) {
            core_layers.push_back(tbe::core::WallAssemblyLayer{
                .material_id = layer.material_id.value,
                .thickness_meters = layer.thickness_meters,
                .function = to_core_layer_function(layer.function),
                .priority = layer.priority,
                .structural = layer.structural,
                .side = to_core_layer_side(layer.side),
                .wraps_openings = layer.wraps_openings,
                .wraps_ends = layer.wraps_ends,
            });
        }
        auto assembly_id = document.create_layered_assembly(to_core_assembly_kind(kind), std::move(name), std::move(core_layers));
        if (core_start_layer >= 0 || core_end_layer >= 0) {
            auto assembly = *document.get_layered_assembly(assembly_id);
            assembly.core_start_layer = core_start_layer;
            assembly.core_end_layer = core_end_layer;
            document.update_layered_assembly(std::move(assembly));
        }
        out = to_id(assembly_id);
    });
}

ApiVoidResult EngineSession::update_layered_assembly(LayeredAssemblyDTO assembly) {
    return apply_mutation(*impl_, "update_layered_assembly", [&](Document& document) {
        tbe::core::LayeredAssemblyData core_assembly{
            .assembly_id = assembly.id.value,
            .kind = to_core_assembly_kind(assembly.kind),
            .name = std::move(assembly.name),
        };
        core_assembly.layers.reserve(assembly.layers.size());
        for (const auto& layer : assembly.layers) {
            core_assembly.layers.push_back(tbe::core::WallAssemblyLayer{
                .material_id = layer.material_id.value,
                .thickness_meters = layer.thickness_meters,
                .function = to_core_layer_function(layer.function),
                .priority = layer.priority,
                .structural = layer.structural,
                .side = to_core_layer_side(layer.side),
                .wraps_openings = layer.wraps_openings,
                .wraps_ends = layer.wraps_ends,
            });
        }
        core_assembly.core_start_layer = assembly.core_start_layer;
        core_assembly.core_end_layer = assembly.core_end_layer;
        document.update_layered_assembly(std::move(core_assembly));
    });
}

ApiResult<std::vector<LayeredAssemblyDTO>> EngineSession::list_layered_assemblies() const {
    return query_result<std::vector<LayeredAssemblyDTO>>([&]() {
        std::vector<LayeredAssemblyDTO> rows;
        for (const auto& [assembly_id, assembly] : impl_->document().layered_assemblies()) {
            LayeredAssemblyDTO row{
                .id = to_id(assembly_id),
                .kind = to_api_assembly_kind(assembly.kind),
                .name = assembly.name,
                .core_start_layer = assembly.core_start_layer,
                .core_end_layer = assembly.core_end_layer,
            };
            for (const auto& layer : assembly.layers) {
                row.layers.push_back(AssemblyLayerDTO{
                    .material_id = to_id(layer.material_id),
                    .thickness_meters = layer.thickness_meters,
                    .function = to_api_layer_function(layer.function),
                    .priority = layer.priority,
                    .structural = layer.structural,
                    .side = to_api_layer_side(layer.side),
                    .wraps_openings = layer.wraps_openings,
                    .wraps_ends = layer.wraps_ends,
                });
            }
            rows.push_back(std::move(row));
        }
        return rows;
    });
}

ApiVoidResult EngineSession::update_roof_properties(
    std::uint64_t roof_id, ApiRoofType roof_type,
    std::optional<double> slope_degrees, std::optional<double> overhang_meters
) {
    return apply_mutation(*impl_, "update_roof_properties", [&](Document& document) {
        document.update_roof_properties(roof_id, to_core_roof_type(roof_type), slope_degrees, overhang_meters);
    });
}

ApiVoidResult EngineSession::set_structural_wall_cut(std::uint64_t wall_id, std::uint64_t cutter_id, bool enabled, double clearance_meters) {
    return apply_mutation(*impl_, "set_structural_wall_cut", [&](Document& document) {
        document.set_structural_wall_cut(wall_id, cutter_id, enabled, clearance_meters);
    });
}

ApiVoidResult EngineSession::set_beam_column_join(std::uint64_t beam_id, std::uint64_t column_id, bool enabled) {
    return apply_mutation(*impl_, "set_beam_column_join", [&](Document& document) {
        document.set_beam_column_join(beam_id, column_id, enabled);
    });
}

ApiResult<ElementIdDTO> EngineSession::split_wall(std::uint64_t wall_id, double offset_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "split_wall", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.split_wall(wall_id, offset_meters));
    });
}

ApiVoidResult EngineSession::delete_element(std::uint64_t element_id) {
    return apply_mutation(*impl_, "delete_element", [&](Document& document) {
        document.delete_element(element_id);
    });
}

ApiVoidResult EngineSession::move_hosted_opening(std::uint64_t opening_id, double offset_meters) {
    return apply_mutation(*impl_, "move_hosted_opening", [&](Document& document) {
        document.move_hosted_opening(opening_id, offset_meters);
    });
}

ApiVoidResult EngineSession::resize_door(std::uint64_t door_id, double width_meters, double height_meters) {
    return apply_mutation(*impl_, "resize_door", [&](Document& document) {
        document.resize_door(door_id, width_meters, height_meters);
    });
}

ApiVoidResult EngineSession::resize_window(std::uint64_t window_id, double width_meters, double height_meters, double sill_height_meters) {
    return apply_mutation(*impl_, "resize_window", [&](Document& document) {
        document.resize_window(window_id, width_meters, height_meters, sill_height_meters);
    });
}

ApiResult<ElementIdDTO> EngineSession::create_floor_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_floor_system_for_room", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_floor_system_for_room(room_id, assembly_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_ceiling_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id, double height_offset_meters) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_ceiling_system_for_room", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_ceiling_system_for_room(room_id, assembly_id, height_offset_meters));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_roof(
    std::uint64_t level_id,
    std::vector<Vec2> boundary_polygon,
    ApiRoofType roof_type,
    double thickness_meters,
    std::uint64_t material_id,
    std::uint64_t assembly_id,
    std::optional<double> slope_degrees,
    std::optional<double> overhang_meters
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_roof", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_roof(
            level_id,
            to_point_list(boundary_polygon),
            to_core_roof_type(roof_type),
            thickness_meters,
            material_id,
            assembly_id,
            slope_degrees,
            overhang_meters
        ));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_column(
    std::uint64_t level_id,
    Vec2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_column", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_column(level_id, to_point(position), width_meters, depth_meters, height_meters, material_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_beam(
    std::uint64_t level_id,
    Vec2 start,
    Vec2 end,
    double width_meters,
    double height_meters,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_beam", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_beam(level_id, to_point(start), to_point(end), width_meters, height_meters, material_id));
    });
}

ApiResult<ElementIdDTO> EngineSession::create_stair(
    std::uint64_t base_level_id,
    std::uint64_t top_level_id,
    Vec2 start,
    Vec2 direction,
    double width_meters,
    double total_rise_meters,
    double total_run_meters,
    int riser_count,
    int tread_count,
    std::uint64_t material_id
) {
    ElementIdDTO created{};
    return apply_mutation_with_value(*impl_, "create_stair", created, [&](Document& document, ElementIdDTO& out) {
        out = to_id(document.create_stair(
            base_level_id,
            top_level_id,
            to_point(start),
            to_point(direction),
            width_meters,
            total_rise_meters,
            total_run_meters,
            riser_count,
            tread_count,
            material_id
        ));
    });
}

ApiVoidResult EngineSession::undo() {
    if (impl_->undo_stack.empty()) {
        return error_void(ApiStatus::NotFound, "no API undo transaction available");
    }
    try {
        auto transaction = impl_->undo_stack.back();
        impl_->undo_stack.pop_back();
        impl_->project = Project::from_json(transaction.before_json);
        impl_->redo_stack.push_back(std::move(transaction));
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::export_ifc(const std::string& path) const {
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) return error_void(recompute.status, recompute.message);
        tbe::core::IfcExchangeReport report;
        tbe::core::export_ifc(impl_->document(), path, &report);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiVoidResult EngineSession::import_ifc(const std::string& path, LoadMode mode) {
    try {
        tbe::core::IfcExchangeReport report;
        auto imported = tbe::core::import_ifc(path, std::filesystem::path(path).stem().string(), &report);
        if (report.imported_elements == 0 && !report.warnings.empty()) {
            return error_void(ApiStatus::InvalidArgument, report.warnings.front());
        }
        const auto before = impl_->project.to_json();
        impl_->project = Project(std::string(imported.name()));
        impl_->project.active_document() = std::move(imported);
        impl_->clear_caches();
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        if (mode == LoadMode::Repair) {
            (void)repair_project_impl(*impl_, RepairOptionsDTO{});
        }
        impl_->undo_stack.clear();
        impl_->undo_stack.push_back(SessionTransaction{"Import IFC", before, impl_->project.to_json()});
        impl_->redo_stack.clear();
        auto result = success_void();
        for (const auto& warning : report.warnings) result.message += warning + " ";
        return result;
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<BimCacheStatsDTO> EngineSession::compile_bim_cache(
    const std::string& source_ifc_path,
    const std::string& cache_path
) const {
    namespace fs = std::filesystem;
    try {
        auto recompute = recompute_impl(*impl_, ComputeMode::InteractivePreview);
        if (!recompute.ok()) {
            return error_result<BimCacheStatsDTO>(recompute.status, recompute.message);
        }
        // The cache deliberately compiles the interactive runtime scene. Exact
        // authoring geometry remains in the Document/source IFC; this artifact
        // is only the chunked representation used to draw and pick quickly.
        auto compiled = runtime_cache::compile(
            build_render_scene(impl_->document(), nullptr, RenderSceneDetail::Interactive),
            runtime_cache::source_signature(source_ifc_path)
        );
        runtime_cache::write_file(cache_path, compiled);
        return success_result(runtime_cache::stats_for(
            compiled,
            static_cast<std::size_t>(fs::file_size(cache_path)),
            true
        ));
    } catch (const std::exception& error) {
        return error_result<BimCacheStatsDTO>(status_from_exception(error), error.what());
    }
}

ApiResult<BimCacheStatsDTO> EngineSession::inspect_bim_cache(
    const std::string& source_ifc_path,
    const std::string& cache_path
) const {
    namespace fs = std::filesystem;
    try {
        const auto cached = runtime_cache::read_file(cache_path, source_ifc_path);
        return success_result(runtime_cache::stats_for(
            cached,
            static_cast<std::size_t>(fs::file_size(cache_path)),
            true
        ));
    } catch (const std::exception& error) {
        return error_result<BimCacheStatsDTO>(status_from_exception(error), error.what());
    }
}

ApiResult<UnitSettingsDTO> EngineSession::get_unit_settings() const {
    const auto& settings = impl_->document().unit_settings();
    return success_result(UnitSettingsDTO{
        .system = std::string(tbe::core::unit_system_to_string(settings.system)),
        .length = std::string(tbe::core::length_unit_to_string(settings.length)),
        .angle = settings.angle,
    });
}

ApiVoidResult EngineSession::set_unit_settings(UnitSettingsDTO settings) {
    return apply_mutation(*impl_, "Set project units", [&](Document& document) {
        document.set_unit_settings(UnitSettings{
            .system = tbe::core::string_to_unit_system(settings.system),
            .length = tbe::core::string_to_length_unit(settings.length),
            .angle = std::move(settings.angle),
        });
    });
}

ApiResult<HistorySummaryDTO> EngineSession::get_history_summary() const {
    return query_result<HistorySummaryDTO>([&]() {
        return HistorySummaryDTO{
            .undo_count = impl_->undo_stack.size(),
            .redo_count = impl_->redo_stack.size(),
        };
    });
}

ApiVoidResult EngineSession::redo() {
    if (impl_->redo_stack.empty()) {
        return error_void(ApiStatus::NotFound, "no API redo transaction available");
    }
    try {
        auto transaction = impl_->redo_stack.back();
        impl_->redo_stack.pop_back();
        impl_->project = Project::from_json(transaction.after_json);
        impl_->undo_stack.push_back(std::move(transaction));
        impl_->clear_caches();
        impl_->freshness = FreshnessSummaryDTO{};
        impl_->mark_all_derived_dirty();
        rebuild_spatial_index_impl(*impl_);
        return success_void();
    } catch (const std::exception& error) {
        return error_void(status_from_exception(error), error.what());
    }
}

ApiResult<std::vector<ElementSummaryDTO>> EngineSession::list_elements() const {
    return query_result<std::vector<ElementSummaryDTO>>([&]() {
        std::vector<ElementSummaryDTO> rows;
        rows.reserve(impl_->document().elements().size());
        for (const auto& element : impl_->document().elements()) {
            rows.push_back(to_element_summary(element));
        }
        return rows;
    });
}

ApiResult<ElementSummaryDTO> EngineSession::get_element_summary(std::uint64_t element_id) const {
    return query_result<ElementSummaryDTO>([&]() {
        const auto* element = impl_->document().find_ptr(element_id);
        if (element == nullptr) {
            throw std::invalid_argument("element does not exist");
        }
        return to_element_summary(*element);
    });
}

ApiResult<WallDTO> EngineSession::get_wall(std::uint64_t wall_id) const {
    return query_result<WallDTO>([&]() {
        const auto* element = impl_->document().find_ptr(wall_id);
        if (element == nullptr || element->wall() == nullptr) {
            throw std::invalid_argument("wall does not exist");
        }
        const auto* wall = element->wall();
        return WallDTO{
            .id = to_id(element->id()),
            .name = std::string(element->name()),
            .level_id = to_id(wall->level_id),
            .start = to_vec2(wall->axis.start),
            .end = to_vec2(wall->axis.end),
            .thickness_meters = wall->thickness_meters,
            .height_meters = wall->height_meters,
        };
    });
}

ApiResult<std::vector<RoomDTO>> EngineSession::get_rooms() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<RoomDTO>>(recompute.status, recompute.message);
    }
    ApiResult<std::vector<RoomDTO>> result = success_result(impl_->cached_rooms.value_or(build_room_cache(impl_->document())));
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomDTO>> EngineSession::get_cached_rooms() const {
    ApiResult<std::vector<RoomDTO>> result;
    result.freshness = impl_->freshness.room_metrics;
    if (impl_->cached_rooms.has_value()) {
        result.value = *impl_->cached_rooms;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached room data available";
    return result;
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::get_wall_schedule() const {
    return const_cast<EngineSession*>(this)->generate_wall_schedule();
}

ApiResult<std::vector<SlabScheduleDTO>> EngineSession::get_slab_schedule() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<SlabScheduleDTO>>(recompute.status, recompute.message);
    }
    std::vector<SlabScheduleDTO> rows;
    for (const auto& row : impl_->document().generate_slab_schedule()) {
        SlabScheduleDTO dto{
            .slab_id = to_id(row.slab_id),
            .level_id = to_id(row.level_id),
            .area_square_meters = row.area_square_meters,
            .thickness_meters = row.thickness_meters,
            .volume_cubic_meters = row.volume_cubic_meters,
            .material_or_assembly_name = row.material_or_assembly_name,
        };
        for (const auto& [material_id, volume] : row.material_volume_by_id) {
            dto.material_volume_by_id[material_id] = volume;
        }
        for (const auto& [material_id, cost] : row.material_cost_by_id) {
            dto.material_cost_by_id[material_id] = cost;
        }
        rows.push_back(std::move(dto));
    }
    return success_result(std::move(rows));
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::get_cached_wall_schedule() const {
    ApiResult<std::vector<WallScheduleDTO>> result;
    result.freshness = impl_->freshness.schedules;
    if (impl_->cached_wall_schedule.has_value()) {
        result.value = *impl_->cached_wall_schedule;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached wall schedule available";
    return result;
}

ApiResult<std::vector<OpeningScheduleDTO>> EngineSession::get_opening_schedule() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<OpeningScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_opening_schedule = build_opening_schedule_cache(impl_->document());
    ApiResult<std::vector<OpeningScheduleDTO>> result = success_result(*impl_->cached_opening_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::get_room_schedule() const {
    return const_cast<EngineSession*>(this)->generate_room_schedule();
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::get_cached_room_schedule() const {
    ApiResult<std::vector<RoomScheduleDTO>> result;
    result.freshness = impl_->freshness.schedules;
    if (impl_->cached_room_schedule.has_value()) {
        result.value = *impl_->cached_room_schedule;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached room schedule available";
    return result;
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::get_material_takeoff_summary() const {
    return const_cast<EngineSession*>(this)->generate_material_takeoff_summary();
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::get_cached_material_takeoff_summary() const {
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> result;
    result.freshness = impl_->freshness.material_takeoff;
    if (impl_->cached_material_takeoff.has_value()) {
        result.value = *impl_->cached_material_takeoff;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached material takeoff available";
    return result;
}

ApiResult<ValidationReportDTO> EngineSession::get_validation_report() const {
    return const_cast<EngineSession*>(this)->generate_validation_report();
}

ApiResult<ValidationReportDTO> EngineSession::get_cached_validation_report() const {
    ApiResult<ValidationReportDTO> result;
    result.freshness = impl_->freshness.validation_report;
    if (impl_->cached_validation.has_value()) {
        result.value = *impl_->cached_validation;
        return result;
    }
    result.status = ApiStatus::NotFound;
    result.message = "no cached validation report available";
    return result;
}

ApiResult<DependencyGraphSummaryDTO> EngineSession::get_dependency_graph_summary() const {
    return query_result<DependencyGraphSummaryDTO>([&]() {
        const auto& graph = impl_->document().dependency_graph();
        return DependencyGraphSummaryDTO{
            .version = impl_->document().dependency_graph_version(),
            .rooms_by_wall_entries = graph.rooms_by_wall.size(),
            .openings_by_wall_entries = graph.openings_by_wall.size(),
            .connected_walls_entries = graph.connected_walls_by_wall.size(),
            .geometry_dependency_entries = graph.geometry_by_element.size(),
        };
    });
}

ApiResult<ScheduleSummaryDTO> EngineSession::generate_schedules() const {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<ScheduleSummaryDTO>(recompute.status, recompute.message);
    }
    ApiResult<ScheduleSummaryDTO> result = success_result(ScheduleSummaryDTO{
        .wall_rows = impl_->document().generate_wall_schedule().size(),
        .opening_rows = impl_->document().generate_opening_schedule().size(),
        .room_rows = impl_->document().generate_room_schedule().size(),
        .slab_rows = impl_->document().generate_slab_schedule().size(),
        .roof_rows = impl_->document().generate_roof_schedule().size(),
        .column_rows = impl_->document().generate_column_schedule().size(),
        .beam_rows = impl_->document().generate_beam_schedule().size(),
        .stair_rows = impl_->document().generate_stair_schedule().size(),
        .floor_rows = impl_->document().generate_floor_finish_schedule().size(),
        .ceiling_rows = impl_->document().generate_ceiling_schedule().size(),
        .material_takeoff_rows = impl_->document().generate_material_takeoff().size(),
    });
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<HitTestCandidateDTO>> EngineSession::hit_test_point(HitTestPoint query) const {
    ensure_spatial_index(*impl_);
    return query_result<std::vector<HitTestCandidateDTO>>([&]() {
        std::vector<HitTestCandidateDTO> candidates;
        const auto* level_index = find_level_spatial_index(*impl_, query.level_id.value);
        if (level_index == nullptr) {
            return candidates;
        }
        const auto point = to_point(query.point);
        const auto query_bounds = AABB2D{
            .min_x = point.x - query.tolerance_meters,
            .min_y = point.y - query.tolerance_meters,
            .max_x = point.x + query.tolerance_meters,
            .max_y = point.y + query.tolerance_meters,
        };
        for (const auto entry_index : query_level_indices(*level_index, query_bounds)) {
            const auto& entry = level_index->entries[entry_index];

            auto push_candidate = [&](HitKind hit_kind, double distance_meters) {
                candidates.push_back(HitTestCandidateDTO{
                    .element_id = to_id(entry.element_id),
                    .element_kind = entry.kind,
                    .hit_kind = hit_kind,
                    .distance_meters = distance_meters,
                    .priority = hit_priority(hit_kind),
                });
            };

            switch (entry.kind) {
            case ApiElementKind::Wall: {
                const auto axis_distance = distance_point_to_segment(point, entry.axis);
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::WallBody, axis_distance);
                }
                if (axis_distance <= query.tolerance_meters) {
                    push_candidate(HitKind::WallAxis, axis_distance);
                }
                break;
            }
            case ApiElementKind::Door:
            case ApiElementKind::Window:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Opening, 0.0);
                }
                break;
            case ApiElementKind::Room:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::RoomInterior, 0.0);
                }
                break;
            case ApiElementKind::Slab:
            case ApiElementKind::FloorSystem:
            case ApiElementKind::CeilingSystem:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(entry.preferred_hit_kind, 0.0);
                }
                break;
            case ApiElementKind::Roof:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Roof, 0.0);
                }
                break;
            case ApiElementKind::Column:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Column, 0.0);
                }
                break;
            case ApiElementKind::Beam: {
                const auto beam_distance = distance_point_to_segment(point, entry.axis);
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Beam, beam_distance);
                }
                break;
            }
            case ApiElementKind::Stair:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::Stair, 0.0);
                }
                break;
            case ApiElementKind::Proxy:
                if (!entry.polygon.empty() && point_in_polygon(point, entry.polygon)) {
                    push_candidate(HitKind::None, 0.0);
                }
                break;
            default:
                break;
            }
        }

        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
            if (left.priority != right.priority) {
                return left.priority < right.priority;
            }
            if (std::abs(left.distance_meters - right.distance_meters) > 1.0e-9) {
                return left.distance_meters < right.distance_meters;
            }
            return left.element_id.value < right.element_id.value;
        });
        return candidates;
    });
}

ApiResult<std::vector<SnapCandidateDTO>> EngineSession::get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap) const {
    return get_snap_candidates(level_id, point, tolerance_meters, SnapOptionsDTO{.enable_grid = include_grid_snap});
}

ApiResult<std::vector<SnapCandidateDTO>> EngineSession::get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const {
    ensure_spatial_index(*impl_);
    return query_result<std::vector<SnapCandidateDTO>>([&]() {
        std::vector<SnapCandidateDTO> candidates;
        const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
        if (level_index == nullptr) {
            return candidates;
        }
        const auto query_point = to_point(point);
        const auto query_bounds = AABB2D{
            .min_x = query_point.x - tolerance_meters,
            .min_y = query_point.y - tolerance_meters,
            .max_x = query_point.x + tolerance_meters,
            .max_y = query_point.y + tolerance_meters,
        };
        auto push_snap = [&](Point2 candidate_point, SnapType type, std::optional<ElementId> source) {
            const auto dist = distance(query_point, candidate_point);
            if (dist > tolerance_meters && type != SnapType::Grid) {
                return;
            }
            candidates.push_back(SnapCandidateDTO{
                .point = to_vec2(candidate_point),
                .type = type,
                .source_element_id = source.has_value() ? std::optional<ElementIdDTO>{to_id(*source)} : std::nullopt,
                .distance_meters = dist,
                .priority = snap_priority(type),
            });
        };

        for (const auto entry_index : query_level_indices(*level_index, expanded_bounds(query_bounds, tolerance_meters))) {
            const auto& entry = level_index->entries[entry_index];
            if (entry.kind == ApiElementKind::Wall || entry.kind == ApiElementKind::Beam) {
                if (options.enable_endpoints) {
                    push_snap(entry.axis.start, SnapType::Endpoint, entry.element_id);
                    push_snap(entry.axis.end, SnapType::Endpoint, entry.element_id);
                }
                if (options.enable_midpoints) {
                    push_snap(Point2{
                        .x = (entry.axis.start.x + entry.axis.end.x) / 2.0,
                        .y = (entry.axis.start.y + entry.axis.end.y) / 2.0,
                    }, SnapType::Midpoint, entry.element_id);
                }
                Point2 projected{};
                const auto axis_distance = distance_point_to_segment(query_point, entry.axis, nullptr, &projected);
                if (axis_distance <= tolerance_meters) {
                    if (options.enable_orthogonal_projection) {
                        push_snap(projected, SnapType::OrthogonalProjection, entry.element_id);
                    }
                    if (options.enable_wall_axis) {
                        push_snap(projected, SnapType::WallAxis, entry.element_id);
                    }
                }
            }
            if (options.enable_room_corners &&
                (entry.kind == ApiElementKind::Room || entry.kind == ApiElementKind::Slab || entry.kind == ApiElementKind::FloorSystem ||
                    entry.kind == ApiElementKind::CeilingSystem || entry.kind == ApiElementKind::Roof || entry.kind == ApiElementKind::Stair) &&
                !entry.polygon.empty()) {
                for (const auto& polygon_point : entry.polygon) {
                    push_snap(polygon_point, SnapType::RoomCorner, entry.element_id);
                }
            }
        }

        if (options.enable_intersections) {
            for (const auto& first : level_index->entries) {
            if (!(first.kind == ApiElementKind::Wall || first.kind == ApiElementKind::Beam)) {
                continue;
            }
                for (const auto& second : level_index->entries) {
                if (first.element_id >= second.element_id || !(second.kind == ApiElementKind::Wall || second.kind == ApiElementKind::Beam)) {
                    continue;
                }
                const auto denominator = ((first.axis.start.x - first.axis.end.x) * (second.axis.start.y - second.axis.end.y)) -
                    ((first.axis.start.y - first.axis.end.y) * (second.axis.start.x - second.axis.end.x));
                if (near_zero(denominator)) {
                    continue;
                }
                const auto x1 = first.axis.start.x;
                const auto y1 = first.axis.start.y;
                const auto x2 = first.axis.end.x;
                const auto y2 = first.axis.end.y;
                const auto x3 = second.axis.start.x;
                const auto y3 = second.axis.start.y;
                const auto x4 = second.axis.end.x;
                const auto y4 = second.axis.end.y;
                const auto px = (((x1 * y2) - (y1 * x2)) * (x3 - x4) - (x1 - x2) * ((x3 * y4) - (y3 * x4))) / denominator;
                const auto py = (((x1 * y2) - (y1 * x2)) * (y3 - y4) - (y1 - y2) * ((x3 * y4) - (y3 * x4))) / denominator;
                push_snap(Point2{.x = px, .y = py}, SnapType::WallIntersection, first.element_id);
            }
        }
        }

        if (options.enable_grid) {
            const auto grid_size = options.grid_size_meters > 1.0e-9 ? options.grid_size_meters : 1.0;
            push_snap(Point2{
                .x = std::round(query_point.x / grid_size) * grid_size,
                .y = std::round(query_point.y / grid_size) * grid_size,
            }, SnapType::Grid, std::nullopt);
        }

        std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
            if (left.priority != right.priority) {
                return left.priority < right.priority;
            }
            if (std::abs(left.distance_meters - right.distance_meters) > 1.0e-9) {
                return left.distance_meters < right.distance_meters;
            }
            return left.source_element_id.value_or(ElementIdDTO{}).value < right.source_element_id.value_or(ElementIdDTO{}).value;
        });
        return candidates;
    });
}

ApiResult<SnapCandidateDTO> EngineSession::best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap) const {
    return best_snap(level_id, point, tolerance_meters, SnapOptionsDTO{.enable_grid = include_grid_snap});
}

ApiResult<SnapCandidateDTO> EngineSession::best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const {
    const auto candidates = get_snap_candidates(level_id, point, tolerance_meters, options);
    if (!candidates.ok()) {
        return error_result<SnapCandidateDTO>(candidates.status, candidates.message);
    }
    if (!candidates.value.has_value() || candidates.value->empty()) {
        return error_result<SnapCandidateDTO>(ApiStatus::NotFound, "no snap candidate available");
    }
    auto result = success_result(candidates.value->front());
    result.freshness = candidates.freshness;
    return result;
}

ApiResult<std::vector<WallFreeIntervalDTO>> EngineSession::compute_wall_free_intervals(std::uint64_t wall_id, double requested_width_meters, double clearance_meters) const {
    return query_result<std::vector<WallFreeIntervalDTO>>([&]() {
        const auto* wall_element = impl_->document().find_ptr(wall_id);
        if (wall_element == nullptr) {
            throw std::invalid_argument("wall does not exist");
        }
        return compute_wall_free_intervals_for_entry(*wall_element, requested_width_meters, clearance_meters);
    });
}

ApiResult<WallHostPlacementDTO> EngineSession::find_wall_host_at_point(
    ElementIdDTO level_id,
    Vec2 point,
    double tolerance_meters,
    double requested_width_meters,
    double clearance_meters
) const {
    ensure_spatial_index(*impl_);
    return query_result<WallHostPlacementDTO>([&]() {
        const auto query_point = to_point(point);
        const auto* level_index = find_level_spatial_index(*impl_, level_id.value);
        if (level_index == nullptr) {
            throw std::invalid_argument("level has no spatial entries");
        }

        const SpatialEntry* best_wall = nullptr;
        double best_distance = tolerance_meters;
        double best_param = 0.0;
        const auto query_bounds = AABB2D{
            .min_x = query_point.x - tolerance_meters,
            .min_y = query_point.y - tolerance_meters,
            .max_x = query_point.x + tolerance_meters,
            .max_y = query_point.y + tolerance_meters,
        };
        for (const auto entry_index : query_level_indices(*level_index, expanded_bounds(query_bounds, tolerance_meters))) {
            const auto& entry = level_index->entries[entry_index];
            if (entry.kind != ApiElementKind::Wall) {
                continue;
            }
            double param = 0.0;
            const auto axis_distance = distance_point_to_segment(query_point, entry.axis, &param, nullptr);
            if (axis_distance <= best_distance) {
                best_distance = axis_distance;
                best_param = param;
                best_wall = &entry;
            }
        }
        if (best_wall == nullptr) {
            throw std::invalid_argument("no wall host found at point");
        }

        const auto* wall_element = impl_->document().find_ptr(best_wall->element_id);
        const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
        if (wall == nullptr) {
            throw std::invalid_argument("wall host entry is invalid");
        }

        const auto length_value = line_length(best_wall->axis);
        const auto requested_offset = best_param * length_value;
        const auto direction = length_value <= 1.0e-12 ? Point2{} : Point2{.x = (best_wall->axis.end.x - best_wall->axis.start.x) / length_value, .y = (best_wall->axis.end.y - best_wall->axis.start.y) / length_value};
        const auto cross = ((query_point.x - best_wall->axis.start.x) * direction.y) - ((query_point.y - best_wall->axis.start.y) * direction.x);
        const auto free_intervals = compute_wall_free_intervals_for_entry(*wall_element, requested_width_meters, clearance_meters);
        WallHostPlacementDTO result{
            .wall_id = to_id(best_wall->element_id),
            .requested_offset_meters = requested_offset,
            .wall_local_offset_meters = requested_offset,
            .adjusted_valid_offset_meters = requested_offset,
            .side = cross >= 0.0 ? "left" : "right",
            .valid = false,
            .free_intervals = free_intervals,
        };

        for (const auto& interval : free_intervals) {
            if (requested_offset >= interval.start_offset_meters - 1.0e-9 && requested_offset <= interval.end_offset_meters + 1.0e-9) {
                result.valid = true;
                result.adjusted_valid_offset_meters = clamp(requested_offset, interval.start_offset_meters, interval.end_offset_meters);
                break;
            }
        }

        if (!result.valid && !free_intervals.empty()) {
            double best_adjusted = free_intervals.front().start_offset_meters;
            double best_delta = std::abs(best_adjusted - requested_offset);
            for (const auto& interval : free_intervals) {
                const auto candidate = clamp(requested_offset, interval.start_offset_meters, interval.end_offset_meters);
                const auto delta = std::abs(candidate - requested_offset);
                if (delta < best_delta) {
                    best_delta = delta;
                    best_adjusted = candidate;
                }
            }
            result.adjusted_valid_offset_meters = best_adjusted;
            result.warnings.push_back("requested offset adjusted to nearest valid interval");
        }

        for (const auto& opening : wall->openings) {
            if (std::abs(opening.offset_meters - requested_offset) <= std::max(tolerance_meters, clearance_meters)) {
                result.warnings.push_back("near existing opening");
            }
        }
        if (free_intervals.empty()) {
            result.warnings.push_back("no valid wall placement interval available");
        }
        return result;
    });
}

ApiResult<std::vector<WallScheduleDTO>> EngineSession::generate_wall_schedule() {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<WallScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_wall_schedule = build_wall_schedule_cache(impl_->document());
    impl_->freshness.schedules = FreshnessState::Clean;
    ApiResult<std::vector<WallScheduleDTO>> result = success_result(*impl_->cached_wall_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<RoomScheduleDTO>> EngineSession::generate_room_schedule() {
    auto recompute = recompute_impl(*impl_, ComputeMode::Normal);
    if (!recompute.ok()) {
        return error_result<std::vector<RoomScheduleDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_room_schedule = build_room_schedule_cache(impl_->document());
    impl_->freshness.schedules = FreshnessState::Clean;
    ApiResult<std::vector<RoomScheduleDTO>> result = success_result(*impl_->cached_room_schedule);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<std::vector<MaterialTakeoffSummaryDTO>> EngineSession::generate_material_takeoff_summary() {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<std::vector<MaterialTakeoffSummaryDTO>>(recompute.status, recompute.message);
    }
    impl_->cached_material_takeoff = build_material_takeoff_cache(impl_->document());
    impl_->freshness.material_takeoff = FreshnessState::Clean;
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> result = success_result(*impl_->cached_material_takeoff);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiResult<ValidationReportDTO> EngineSession::generate_validation_report() {
    auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
    if (!recompute.ok()) {
        return error_result<ValidationReportDTO>(recompute.status, recompute.message);
    }
    impl_->cached_validation = to_validation_report(impl_->document().validate_document());
    impl_->freshness.validation_report = FreshnessState::Clean;
    ApiResult<ValidationReportDTO> result = success_result(*impl_->cached_validation);
    result.freshness = FreshnessState::Clean;
    return result;
}

ApiVoidResult EngineSession::export_svg(const std::string& path) const {
    return const_cast<EngineSession*>(this)->export_svg_cached(path, false);
}

ApiVoidResult EngineSession::export_svg_cached(const std::string& path, bool allow_stale) const {
    if (!allow_stale) {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return recompute;
        }
    }
    auto result = query_void([&]() {
        impl_->document().export_floorplan_svg(path);
    });
    result.freshness = allow_stale ? impl_->freshness.exports : FreshnessState::Clean;
    if (result.ok()) {
        impl_->freshness.exports = FreshnessState::Clean;
    }
    return result;
}

ApiVoidResult EngineSession::export_obj(const std::string& path) const {
    return const_cast<EngineSession*>(this)->export_obj_cached(path, false);
}

ApiVoidResult EngineSession::export_obj_cached(const std::string& path, bool allow_stale) const {
    if (!allow_stale) {
        auto recompute = recompute_impl(*impl_, ComputeMode::FinalExact);
        if (!recompute.ok()) {
            return recompute;
        }
    }
    auto result = query_void([&]() {
        impl_->document().export_mesh_obj(path);
    });
    result.freshness = allow_stale ? impl_->freshness.exports : FreshnessState::Clean;
    if (result.ok()) {
        impl_->freshness.exports = FreshnessState::Clean;
    }
    return result;
}

ApiResult<std::unique_ptr<EngineSession>> create_session(std::string project_name) {
    try {
        return success_result(std::make_unique<EngineSession>(std::move(project_name)));
    } catch (const std::exception& error) {
        return error_result<std::unique_ptr<EngineSession>>(status_from_exception(error), error.what());
    }
}

} // namespace tbe::api
