#include "tbe/core/Document.hpp"

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <utility>

namespace tbe::core {

namespace {

constexpr auto epsilon = 1.0e-9;

double line_length(const Line2& line) {
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

bool is_vertical(const Line2& line) {
    return std::abs(line.start.x - line.end.x) < epsilon &&
        std::abs(line.start.y - line.end.y) >= epsilon;
}

double polygon_area(const std::vector<Point2>& polygon) {
    auto signed_area = 0.0;
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto& current = polygon[index];
        const auto& next = polygon[(index + 1) % polygon.size()];
        signed_area += (current.x * next.y) - (next.x * current.y);
    }
    return std::abs(signed_area) / 2.0;
}

double layered_assembly_total_thickness(const LayeredAssemblyData& assembly) {
    auto total = 0.0;
    for (const auto& layer : assembly.layers) {
        total += layer.thickness_meters;
    }
    return total;
}

bool same_point(Point2 first, Point2 second) {
    return std::abs(first.x - second.x) < epsilon &&
        std::abs(first.y - second.y) < epsilon;
}

bool cyclic_polygon_equal(const std::vector<Point2>& first, const std::vector<Point2>& second) {
    if (first.size() != second.size()) {
        return false;
    }
    if (first.empty()) {
        return true;
    }
    for (std::size_t offset = 0; offset < second.size(); ++offset) {
        auto matches_forward = true;
        for (std::size_t index = 0; index < first.size(); ++index) {
            if (!same_point(first[index], second[(index + offset) % second.size()])) {
                matches_forward = false;
                break;
            }
        }
        if (matches_forward) {
            return true;
        }
        auto matches_reverse = true;
        for (std::size_t index = 0; index < first.size(); ++index) {
            const auto reverse_index = (offset + second.size() - index) % second.size();
            if (!same_point(first[index], second[reverse_index])) {
                matches_reverse = false;
                break;
            }
        }
        if (matches_reverse) {
            return true;
        }
    }
    return false;
}

} // namespace

std::vector<WallRoomAdjacency> Document::wall_room_adjacencies() const {
    std::vector<WallRoomAdjacency> rows;
    std::map<ElementId, std::vector<WallRoomAdjacency>> by_wall;
    for (const auto& element : elements_) {
        const auto* room = element.room();
        if (room == nullptr) {
            continue;
        }

        for (const auto wall_id : room->boundary_wall_ids) {
            const auto* wall_element = find_ptr(wall_id);
            const auto* wall = wall_element == nullptr ? nullptr : wall_element->wall();
            if (wall == nullptr) {
                continue;
            }

            const auto polygon = room->centerline_boundary_polygon;
            auto side = WallRoomSide::Exterior;
            if (polygon.size() >= 2) {
                const auto center = Point2{
                    .x = (wall->axis.start.x + wall->axis.end.x) / 2.0,
                    .y = (wall->axis.start.y + wall->axis.end.y) / 2.0,
                };
                const auto probe = is_vertical(wall->axis)
                    ? Point2{.x = center.x + 0.01, .y = center.y}
                    : Point2{.x = center.x, .y = center.y + 0.01};
                auto inside = false;
                for (std::size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
                    const auto intersect = ((polygon[i].y > probe.y) != (polygon[j].y > probe.y)) &&
                        (probe.x < (polygon[j].x - polygon[i].x) * (probe.y - polygon[i].y) / (polygon[j].y - polygon[i].y + epsilon) + polygon[i].x);
                    if (intersect) {
                        inside = !inside;
                    }
                }
                if (is_vertical(wall->axis)) {
                    side = inside ? WallRoomSide::Right : WallRoomSide::Left;
                } else {
                    side = inside ? WallRoomSide::Left : WallRoomSide::Right;
                }
            }

            by_wall[wall_id].push_back(WallRoomAdjacency{
                .wall_id = wall_id,
                .room_id = element.id(),
                .side = side,
            });
        }
    }
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }
        auto& entries = by_wall[element.id()];
        if (entries.empty()) {
            entries.push_back(WallRoomAdjacency{
                .wall_id = element.id(),
                .room_id = 0,
                .side = WallRoomSide::Exterior,
            });
        } else if (entries.size() == 1) {
            entries.push_back(WallRoomAdjacency{
                .wall_id = element.id(),
                .room_id = 0,
                .side = WallRoomSide::Exterior,
            });
        }
        for (const auto& entry : entries) {
            rows.push_back(entry);
        }
    }
    return rows;
}

std::vector<WallScheduleRow> Document::generate_wall_schedule() const {
    std::vector<WallScheduleRow> rows;
    const auto adjacencies = wall_room_adjacencies();
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }

        const auto length_meters = line_length(wall->axis);
        const auto resolved_height = resolved_wall_height(*wall);
        const auto gross_area = length_meters * resolved_height;
        auto opening_area = 0.0;
        for (const auto& opening : wall->openings) {
            opening_area += opening.width_meters * opening.height_meters;
        }
        const auto net_area = std::max(0.0, gross_area - opening_area);
        std::map<ElementId, double> material_volumes;
        if (const auto* wall_type = get_wall_type(wall->wall_type_id)) {
            for (const auto& layer : wall_type->layers) {
                material_volumes[layer.material_id] += net_area * layer.thickness_meters;
            }
        } else if (const auto* assembly = get_layered_assembly(wall->assembly_id);
                   assembly != nullptr && assembly->kind == LayeredAssemblyKind::Wall) {
            for (const auto& layer : assembly->layers) {
                material_volumes[layer.material_id] += net_area * layer.thickness_meters;
            }
        }
        std::map<ElementId, double> material_costs;
        for (const auto& [material_id, volume] : material_volumes) {
            const auto* material = get_material(material_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                material_costs[material_id] = volume * *material->unit_cost;
            }
        }
        const auto room_count = std::count_if(adjacencies.begin(), adjacencies.end(), [&](const WallRoomAdjacency& adjacency) {
            return adjacency.wall_id == element.id() && adjacency.room_id != 0;
        });
        rows.push_back(WallScheduleRow{
            .wall_id = element.id(),
            .level_id = wall->level_id,
            .wall_type_id = wall->wall_type_id,
            .wall_type_name = wall->wall_type_id != 0
                ? wall_type_name(wall->wall_type_id)
                : layered_assembly_name(wall->assembly_id),
            .length_meters = length_meters,
            .thickness_meters = wall_thickness(*wall),
            .height_meters = resolved_height,
            .gross_area_square_meters = gross_area,
            .opening_area_square_meters = opening_area,
            .net_area_square_meters = net_area,
            .gross_volume_cubic_meters = gross_area * wall_thickness(*wall),
            .net_volume_cubic_meters = net_area * wall_thickness(*wall),
            .interior_finish_area_square_meters = room_count == 0 ? 0.0 : net_area * static_cast<double>(std::min<std::size_t>(room_count, 2)),
            .exterior_finish_area_square_meters = room_count < 2 ? net_area : 0.0,
            .material_volume_by_id = std::move(material_volumes),
            .material_cost_by_id = std::move(material_costs),
        });
    }
    return rows;
}

std::vector<OpeningScheduleRow> Document::generate_opening_schedule() const {
    std::vector<OpeningScheduleRow> rows;
    for (const auto& element : elements_) {
        if (const auto* door = element.door()) {
            rows.push_back(OpeningScheduleRow{
                .element_id = element.id(),
                .type = OpeningKind::Door,
                .host_wall_id = door->host_wall_id,
                .width_meters = door->width_meters,
                .height_meters = door->height_meters,
                .area_square_meters = door->width_meters * door->height_meters,
                .level_id = door->level_id,
            });
        } else if (const auto* window = element.window()) {
            rows.push_back(OpeningScheduleRow{
                .element_id = element.id(),
                .type = OpeningKind::Window,
                .host_wall_id = window->host_wall_id,
                .width_meters = window->width_meters,
                .height_meters = window->height_meters,
                .area_square_meters = window->width_meters * window->height_meters,
                .level_id = window->level_id,
            });
        }
    }
    return rows;
}

std::vector<RoomScheduleRow> Document::generate_room_schedule() const {
    std::vector<RoomScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* room = element.room();
        if (room == nullptr) {
            continue;
        }
        rows.push_back(RoomScheduleRow{
            .room_id = element.id(),
            .level_id = room->level_id,
            .centerline_area_square_meters = room->centerline_area_square_meters,
            .interior_area_square_meters = room->interior_area_square_meters,
            .interior_perimeter_meters = room->interior_perimeter_meters,
            .baseboard_length_meters = room->baseboard_length_meters,
            .floor_finish_area_square_meters = room->floor_finish_area_square_meters,
            .ceiling_area_square_meters = room->ceiling_area_square_meters,
            .interior_wall_finish_area_square_meters = room->interior_wall_finish_area_square_meters,
        });
    }
    return rows;
}

std::vector<SlabScheduleRow> Document::generate_slab_schedule() const {
    std::vector<SlabScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* slab = element.slab();
        if (slab == nullptr) {
            continue;
        }
        std::string label;
        if (slab->assembly_id != 0) {
            label = layered_assembly_name(slab->assembly_id);
        } else if (slab->material_id != 0) {
            const auto* material = get_material(slab->material_id);
            label = material == nullptr ? std::string{} : material->name;
        }
        auto material_volumes = slab->assembly_id == 0 || get_layered_assembly(slab->assembly_id) == nullptr
            ? (slab->material_id == 0
                ? std::map<ElementId, double>{}
                : std::map<ElementId, double>{{slab->material_id, slab->area_square_meters * slab->thickness_meters}})
            : [&]() {
                std::map<ElementId, double> quantities;
                for (const auto& layer : get_layered_assembly(slab->assembly_id)->layers) {
                    quantities[layer.material_id] += slab->area_square_meters * layer.thickness_meters;
                }
                return quantities;
            }();
        std::map<ElementId, double> material_costs;
        for (const auto& [material_id, volume] : material_volumes) {
            const auto* material = get_material(material_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                material_costs[material_id] = volume * *material->unit_cost;
            }
        }
        rows.push_back(SlabScheduleRow{
            .slab_id = element.id(),
            .level_id = slab->level_id,
            .area_square_meters = slab->area_square_meters > 0.0 ? slab->area_square_meters : polygon_area(slab->boundary_polygon),
            .thickness_meters = slab->thickness_meters,
            .volume_cubic_meters = slab->volume_cubic_meters > 0.0 ? slab->volume_cubic_meters : polygon_area(slab->boundary_polygon) * slab->thickness_meters,
            .material_or_assembly_name = std::move(label),
            .material_volume_by_id = std::move(material_volumes),
            .material_cost_by_id = std::move(material_costs),
        });
    }
    return rows;
}

std::vector<ColumnScheduleRow> Document::generate_column_schedule() const {
    std::vector<ColumnScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* column = element.column();
        if (column == nullptr) {
            continue;
        }
        const auto* material = get_material(column->material_id);
        rows.push_back(ColumnScheduleRow{
            .column_id = element.id(),
            .level_id = column->level_id,
            .width_meters = column->width_meters,
            .depth_meters = column->depth_meters,
            .height_meters = column->height_meters,
            .volume_cubic_meters = column->volume_cubic_meters > 0.0 ? column->volume_cubic_meters : column->width_meters * column->depth_meters * column->height_meters,
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<BeamScheduleRow> Document::generate_beam_schedule() const {
    std::vector<BeamScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* beam = element.beam();
        if (beam == nullptr) {
            continue;
        }
        const auto* material = get_material(beam->material_id);
        const auto beam_length = beam->length_meters > 0.0 ? beam->length_meters : line_length(Line2{.start = beam->start, .end = beam->end});
        rows.push_back(BeamScheduleRow{
            .beam_id = element.id(),
            .level_id = beam->level_id,
            .length_meters = beam_length,
            .width_meters = beam->width_meters,
            .height_meters = beam->height_meters,
            .volume_cubic_meters = beam->volume_cubic_meters > 0.0 ? beam->volume_cubic_meters : beam_length * beam->width_meters * beam->height_meters,
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<StairScheduleRow> Document::generate_stair_schedule() const {
    std::vector<StairScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* stair = element.stair();
        if (stair == nullptr) {
            continue;
        }
        const auto* material = get_material(stair->material_id);
        rows.push_back(StairScheduleRow{
            .stair_id = element.id(),
            .base_level_id = stair->base_level_id,
            .top_level_id = stair->top_level_id,
            .width_meters = stair->width_meters,
            .total_rise_meters = stair->total_rise_meters,
            .total_run_meters = stair->total_run_meters,
            .riser_count = stair->riser_count,
            .tread_count = stair->tread_count,
            .footprint_area_square_meters = stair->footprint_area_square_meters > 0.0 ? stair->footprint_area_square_meters : stair->width_meters * stair->total_run_meters,
            .volume_cubic_meters = stair->volume_cubic_meters > 0.0 ? stair->volume_cubic_meters : (stair->width_meters * stair->total_run_meters * stair->total_rise_meters / 2.0),
            .material_name = material == nullptr ? std::string{} : material->name,
        });
    }
    return rows;
}

std::vector<FloorFinishScheduleRow> Document::generate_floor_finish_schedule() const {
    std::vector<FloorFinishScheduleRow> rows;
    for (const auto& [system_id, system] : floor_systems_) {
        FloorFinishScheduleRow row{
            .floor_system_id = system_id,
            .room_id = system.room_id,
            .area_square_meters = system.area_square_meters,
            .assembly_name = layered_assembly_name(system.assembly_id),
        };
        if (const auto* assembly = get_layered_assembly(system.assembly_id)) {
            for (const auto& layer : assembly->layers) {
                row.layer_quantities[layer.material_id] += system.area_square_meters * layer.thickness_meters;
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}

std::vector<CeilingScheduleRow> Document::generate_ceiling_schedule() const {
    std::vector<CeilingScheduleRow> rows;
    for (const auto& [system_id, system] : ceiling_systems_) {
        CeilingScheduleRow row{
            .ceiling_system_id = system_id,
            .room_id = system.room_id,
            .area_square_meters = system.area_square_meters,
            .assembly_name = layered_assembly_name(system.assembly_id),
        };
        if (const auto* assembly = get_layered_assembly(system.assembly_id)) {
            for (const auto& layer : assembly->layers) {
                row.layer_quantities[layer.material_id] += system.area_square_meters * layer.thickness_meters;
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}

std::vector<RoofScheduleRow> Document::generate_roof_schedule() const {
    std::vector<RoofScheduleRow> rows;
    for (const auto& element : elements_) {
        const auto* roof = element.roof();
        if (roof == nullptr) {
            continue;
        }
        std::string label;
        if (roof->assembly_id != 0) {
            label = layered_assembly_name(roof->assembly_id);
        } else if (roof->material_id != 0) {
            const auto* material = get_material(roof->material_id);
            label = material == nullptr ? std::string{} : material->name;
        }
        rows.push_back(RoofScheduleRow{
            .roof_id = element.id(),
            .level_id = roof->level_id,
            .roof_type = roof->roof_type,
            .area_square_meters = roof->area_square_meters > 0.0 ? roof->area_square_meters : resolved_roof_surface_area(*roof),
            .thickness_meters = roof->thickness_meters,
            .volume_cubic_meters = roof->volume_cubic_meters > 0.0 ? roof->volume_cubic_meters : resolved_roof_surface_area(*roof) * roof->thickness_meters,
            .material_or_assembly_name = std::move(label),
        });
    }
    return rows;
}

std::vector<MaterialTakeoffRow> Document::generate_material_takeoff() const {
    std::map<std::pair<ElementId, QuantityType>, MaterialTakeoffRow> aggregated;

    for (const auto& row : generate_wall_schedule()) {
        for (const auto& [material_id, volume] : row.material_volume_by_id) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.wall_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& row : generate_opening_schedule()) {
        if (row.type != OpeningKind::Window) {
            continue;
        }
        ElementId material_id = 0;
        if (const auto material = std::find_if(materials_.begin(), materials_.end(), [](const auto& item) {
                return item.second.category == MaterialCategory::Glass;
            }); material != materials_.end()) {
            material_id = material->first;
        }
        if (material_id == 0) {
            continue;
        }
        auto& takeoff = aggregated[{material_id, QuantityType::Area}];
        takeoff.material_id = material_id;
        takeoff.material_name = materials_.at(material_id).name;
        takeoff.quantity_type = QuantityType::Area;
        takeoff.unit = "m2";
        takeoff.quantity += row.area_square_meters;
        takeoff.source_element_ids.push_back(row.element_id);
    }

    for (const auto& row : generate_floor_finish_schedule()) {
        for (const auto& [material_id, volume] : row.layer_quantities) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.floor_system_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& row : generate_ceiling_schedule()) {
        for (const auto& [material_id, volume] : row.layer_quantities) {
            const auto* material = get_material(material_id);
            auto& takeoff = aggregated[{material_id, QuantityType::Volume}];
            takeoff.material_id = material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(row.ceiling_system_id);
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    for (const auto& element : elements_) {
        const auto* slab = element.slab();
        if (slab == nullptr) {
            if (const auto* roof = element.roof()) {
                const auto area = roof->area_square_meters > 0.0 ? roof->area_square_meters : resolved_roof_surface_area(*roof);
                const auto thickness = roof->assembly_id != 0
                    ? (get_layered_assembly(roof->assembly_id) == nullptr ? roof->thickness_meters : layered_assembly_total_thickness(*get_layered_assembly(roof->assembly_id)))
                    : roof->thickness_meters;
                if (roof->assembly_id != 0) {
                    if (const auto* assembly = get_layered_assembly(roof->assembly_id)) {
                        for (const auto& layer : assembly->layers) {
                            const auto volume = area * layer.thickness_meters;
                            const auto* material = get_material(layer.material_id);
                            auto& takeoff = aggregated[{layer.material_id, QuantityType::Volume}];
                            takeoff.material_id = layer.material_id;
                            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                            takeoff.quantity_type = QuantityType::Volume;
                            takeoff.unit = "m3";
                            takeoff.quantity += volume;
                            takeoff.source_element_ids.push_back(element.id());
                            if (material != nullptr && material->unit_cost.has_value()) {
                                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
                            }
                        }
                    }
                } else if (roof->material_id != 0) {
                    const auto* material = get_material(roof->material_id);
                    auto& takeoff = aggregated[{roof->material_id, QuantityType::Volume}];
                    takeoff.material_id = roof->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += area * thickness;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (area * thickness * *material->unit_cost);
                    }
                }
            } else if (const auto* column = element.column()) {
                if (column->material_id != 0) {
                    const auto* material = get_material(column->material_id);
                    auto& takeoff = aggregated[{column->material_id, QuantityType::Volume}];
                    takeoff.material_id = column->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += column->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (column->volume_cubic_meters * *material->unit_cost);
                    }
                }
            } else if (const auto* beam = element.beam()) {
                if (beam->material_id != 0) {
                    const auto* material = get_material(beam->material_id);
                    auto& takeoff = aggregated[{beam->material_id, QuantityType::Volume}];
                    takeoff.material_id = beam->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += beam->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (beam->volume_cubic_meters * *material->unit_cost);
                    }
                }
            } else if (const auto* stair = element.stair()) {
                if (stair->material_id != 0) {
                    const auto* material = get_material(stair->material_id);
                    auto& takeoff = aggregated[{stair->material_id, QuantityType::Volume}];
                    takeoff.material_id = stair->material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += stair->volume_cubic_meters;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (stair->volume_cubic_meters * *material->unit_cost);
                    }
                }
            }
            continue;
        }
        const auto slab_area = slab->area_square_meters > 0.0 ? slab->area_square_meters : polygon_area(slab->boundary_polygon);
        if (slab->assembly_id != 0) {
            if (const auto* assembly = get_layered_assembly(slab->assembly_id)) {
                for (const auto& layer : assembly->layers) {
                    const auto volume = slab_area * layer.thickness_meters;
                    const auto* material = get_material(layer.material_id);
                    auto& takeoff = aggregated[{layer.material_id, QuantityType::Volume}];
                    takeoff.material_id = layer.material_id;
                    takeoff.material_name = material == nullptr ? "Unknown" : material->name;
                    takeoff.quantity_type = QuantityType::Volume;
                    takeoff.unit = "m3";
                    takeoff.quantity += volume;
                    takeoff.source_element_ids.push_back(element.id());
                    if (material != nullptr && material->unit_cost.has_value()) {
                        takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
                    }
                }
            }
        } else if (slab->material_id != 0) {
            const auto volume = slab_area * slab->thickness_meters;
            const auto* material = get_material(slab->material_id);
            auto& takeoff = aggregated[{slab->material_id, QuantityType::Volume}];
            takeoff.material_id = slab->material_id;
            takeoff.material_name = material == nullptr ? "Unknown" : material->name;
            takeoff.quantity_type = QuantityType::Volume;
            takeoff.unit = "m3";
            takeoff.quantity += volume;
            takeoff.source_element_ids.push_back(element.id());
            if (material != nullptr && material->unit_cost.has_value()) {
                takeoff.estimated_cost = takeoff.estimated_cost.value_or(0.0) + (volume * *material->unit_cost);
            }
        }
    }

    std::vector<MaterialTakeoffRow> rows;
    for (auto& [_, row] : aggregated) {
        std::sort(row.source_element_ids.begin(), row.source_element_ids.end());
        row.source_element_ids.erase(std::unique(row.source_element_ids.begin(), row.source_element_ids.end()), row.source_element_ids.end());
        rows.push_back(std::move(row));
    }
    return rows;
}

ValidationReport Document::validate_document() const {
    ValidationReport report;
    (void)dependency_graph();

    std::vector<std::pair<ElementId, double>> level_elevations;
    for (const auto& element : elements_) {
        const auto* level = element.level();
        if (level == nullptr) continue;
        if (!std::isfinite(level->elevation_meters)) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch,
                element.id(), "level elevation must be finite");
        }
        if (!std::isfinite(level->default_wall_height_meters) ||
            level->default_wall_height_meters <= 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort,
                element.id(), "level default wall height must be positive and finite");
        }
        for (const auto& [other_id, other_elevation] : level_elevations) {
            if (std::isfinite(level->elevation_meters) &&
                std::abs(other_elevation - level->elevation_meters) <= epsilon) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch,
                    element.id(), "level elevations must be unique");
                break;
            }
            (void)other_id;
        }
        level_elevations.emplace_back(element.id(), level->elevation_meters);
    }

    for (const auto& [wall_type_id, wall_type] : wall_types_) {
        if (total_wall_type_thickness(wall_type) <= 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, wall_type_id, "wall type total thickness must be positive");
        }
        if (wall_type.core_start_layer < -1 || wall_type.core_end_layer < -1 ||
            (wall_type.core_start_layer < 0) != (wall_type.core_end_layer < 0) ||
            (wall_type.core_start_layer >= 0 &&
             (wall_type.core_start_layer > wall_type.core_end_layer ||
              wall_type.core_end_layer >= static_cast<int>(wall_type.layers.size())))) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "wall type core layer range is invalid");
        }
        for (std::size_t index = 0; index < wall_type.layers.size(); ++index) {
            const auto& layer = wall_type.layers[index];
            if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, wall_type_id, "wall type layer thickness must be positive");
            }
            if (layer.material_id == 0 || get_material(layer.material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "wall type references missing material");
            }
            if (layer.function == WallLayerFunction::ExteriorFinish && layer.side == WallLayerSide::Interior) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "exterior finish layer is marked as interior");
            }
            if (layer.function == WallLayerFunction::InteriorFinish && layer.side == WallLayerSide::Exterior) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "interior finish layer is marked as exterior");
            }
            if (wall_type.core_start_layer >= 0 &&
                index >= static_cast<std::size_t>(wall_type.core_start_layer) &&
                index <= static_cast<std::size_t>(wall_type.core_end_layer) &&
                layer.function != WallLayerFunction::Core) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, wall_type_id, "wall type core range contains a non-core layer");
            }
        }
    }
    for (const auto& [assembly_id, assembly] : layered_assemblies_) {
        if (layered_assembly_total_thickness(assembly) <= 0.0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, assembly_id, "assembly total thickness must be positive");
        }
        if (assembly.core_start_layer < -1 || assembly.core_end_layer < -1 ||
            (assembly.core_start_layer < 0) != (assembly.core_end_layer < 0) ||
            (assembly.core_start_layer >= 0 &&
             (assembly.core_start_layer > assembly.core_end_layer ||
              assembly.core_end_layer >= static_cast<int>(assembly.layers.size())))) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "assembly core layer range is invalid");
        }
        for (std::size_t index = 0; index < assembly.layers.size(); ++index) {
            const auto& layer = assembly.layers[index];
            if (!std::isfinite(layer.thickness_meters) || layer.thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, assembly_id, "assembly layer thickness must be positive");
            }
            if (layer.material_id == 0 || get_material(layer.material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "assembly references missing material");
            }
            if (assembly.core_start_layer >= 0 &&
                index >= static_cast<std::size_t>(assembly.core_start_layer) &&
                index <= static_cast<std::size_t>(assembly.core_end_layer) &&
                layer.function != WallLayerFunction::Core) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "assembly core range contains a non-core layer");
            }
            if (layer.function == WallLayerFunction::ExteriorFinish && layer.side == WallLayerSide::Interior) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "exterior finish layer is marked as interior");
            }
            if (layer.function == WallLayerFunction::InteriorFinish && layer.side == WallLayerSide::Exterior) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, assembly_id, "interior finish layer is marked as exterior");
            }
        }
    }

    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            if (line_length(wall->axis) <= epsilon) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "wall length must be positive");
            }
            const auto wall_base_level_id = wall->base_level_id != 0 ? wall->base_level_id : wall->level_id;
            if (wall_base_level_id != 0 && (find_ptr(wall_base_level_id) == nullptr || find_ptr(wall_base_level_id)->level() == nullptr)) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "wall base level does not exist");
            }
            if (wall->height_mode == WallHeightMode::TopLevel) {
                if (wall->top_level_id == 0 || find_ptr(wall->top_level_id) == nullptr || find_ptr(wall->top_level_id)->level() == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "wall top level does not exist");
                } else if (wall_base_level_id != 0 &&
                    find_ptr(wall_base_level_id) != nullptr && find_ptr(wall_base_level_id)->level() != nullptr) {
                    const auto base = level_elevation(wall_base_level_id) + wall->base_offset_meters;
                    const auto top = level_elevation(wall->top_level_id) + wall->top_offset_meters;
                    if (!std::isfinite(base) || !std::isfinite(top) || top <= base + epsilon) {
                        add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "wall constrained top level must be above base level");
                    }
                }
            }
            if (wall->wall_type_id != 0 && get_wall_type(wall->wall_type_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "wall references missing wall type");
            }
            if (wall->assembly_id != 0) {
                const auto* assembly = get_layered_assembly(wall->assembly_id);
                if (assembly == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "wall references missing assembly");
                } else if (assembly->kind != LayeredAssemblyKind::Wall) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "wall assembly must have Wall kind");
                }
            }

            std::set<std::pair<ElementId, std::string>> seen_joins;
            for (const auto& join : wall->joins) {
                if (find_ptr(join.other_wall_id) == nullptr || find_ptr(join.other_wall_id)->wall() == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "join references missing wall");
                    continue;
                }

                std::ostringstream key;
                key << join.other_wall_id << ':' << join.point.x << ':' << join.point.y;
                if (!seen_joins.insert({join.other_wall_id, key.str()}).second) {
                    add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::DuplicateJoin, element.id(), "duplicate join detected");
                }
            }

            for (std::size_t index = 0; index < wall->openings.size(); ++index) {
                const auto& opening = wall->openings[index];
                const auto* opening_element = find_ptr(opening.element_id);
                const auto structural_void = opening.kind == OpeningKind::StructuralVoid;
                const auto valid_structural_cutter = opening_element != nullptr &&
                    (opening_element->column() != nullptr || opening_element->beam() != nullptr);
                if (opening_element == nullptr ||
                    (!structural_void && opening_element->door() == nullptr && opening_element->window() == nullptr) ||
                    (structural_void && !valid_structural_cutter)) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "wall references missing opening");
                    continue;
                }

                // Structural voids are owned by the wall but cut by a column
                // or beam. They have no hosted-opening level contract.
                if (structural_void) {
                    continue;
                }

                const auto opening_level_id = opening_element->door() != nullptr ? opening_element->door()->level_id : opening_element->window()->level_id;
                if (opening_level_id != wall->level_id) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, opening.element_id, "opening level does not match host wall");
                }

                try {
                    validate_wall_openings(*wall);
                } catch (const std::invalid_argument& error) {
                    const auto message = std::string(error.what());
                    const auto code = message.find("overlaps") != std::string::npos
                        ? ValidationIssueCode::OverlappingOpenings
                        : ValidationIssueCode::OpeningOutsideWall;
                    add_issue(report, ValidationSeverity::Error, code, opening.element_id, message);
                    break;
                }
            }
        } else if (const auto* door = element.door()) {
            const auto* host = find_ptr(door->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "door host wall does not exist");
            } else if (host->wall()->level_id != door->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "door level does not match host wall");
            }
        } else if (const auto* window = element.window()) {
            const auto* host = find_ptr(window->host_wall_id);
            if (host == nullptr || host->wall() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OrphanOpening, element.id(), "window host wall does not exist");
            } else if (host->wall()->level_id != window->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "window level does not match host wall");
            }
        } else if (const auto* room = element.room()) {
            if (room->centerline_area_square_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room area must be positive");
            }
            if (room->interior_area_square_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room interior area must be positive");
            }
            if (std::abs(room->floor_finish_area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room floor area should match interior area");
            }
            if (std::abs(room->ceiling_area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, element.id(), "room ceiling area should match interior area");
            }
            for (const auto boundary_id : room->boundary_wall_ids) {
                const auto* boundary = find_ptr(boundary_id);
                if (boundary == nullptr || boundary->wall() == nullptr) {
                    add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, element.id(), "room boundary references missing wall");
                }
            }
        } else if (const auto* slab = element.slab()) {
            if (find_ptr(slab->level_id) == nullptr || find_ptr(slab->level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "slab level does not exist");
            }
            if (slab->thickness_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "slab thickness must be positive");
            }
            if (polygon_area(slab->boundary_polygon) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, element.id(), "slab boundary area must be positive");
            }
            if (slab->material_id != 0 && get_material(slab->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "slab references missing material");
            }
            if (slab->assembly_id != 0 && get_layered_assembly(slab->assembly_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "slab references missing assembly");
            }
        } else if (const auto* roof = element.roof()) {
            if (find_ptr(roof->level_id) == nullptr || find_ptr(roof->level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "roof level does not exist");
            }
            if (roof->thickness_meters <= 0.0 || polygon_area(roof->boundary_polygon) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "roof dimensions must be positive");
            }
            if (roof->material_id != 0 && get_material(roof->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "roof references missing material");
            }
            if (roof->assembly_id != 0 && get_layered_assembly(roof->assembly_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "roof references missing assembly");
            }
        } else if (const auto* column = element.column()) {
            if (find_ptr(column->level_id) == nullptr || find_ptr(column->level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "column level does not exist");
            }
            if (column->width_meters <= 0.0 || column->depth_meters <= 0.0 || column->height_meters <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "column dimensions must be positive");
            }
            if (column->material_id != 0 && get_material(column->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "column references missing material");
            }
        } else if (const auto* beam = element.beam()) {
            if (find_ptr(beam->level_id) == nullptr || find_ptr(beam->level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "beam level does not exist");
            }
            if (beam->width_meters <= 0.0 || beam->height_meters <= 0.0 || line_length(Line2{.start = beam->start, .end = beam->end}) <= 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "beam dimensions must be positive");
            }
            if (beam->material_id != 0 && get_material(beam->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "beam references missing material");
            }
        } else if (const auto* stair = element.stair()) {
            if (stair->width_meters <= 0.0 || stair->total_rise_meters <= 0.0 || stair->total_run_meters <= 0.0 || stair->riser_count <= 0 || stair->tread_count <= 0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::WallTooShort, element.id(), "stair dimensions and counts must be positive");
            }
            if (find_ptr(stair->base_level_id) == nullptr || find_ptr(stair->base_level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "stair base level does not exist");
            }
            if (stair->top_level_id != 0 && (find_ptr(stair->top_level_id) == nullptr || find_ptr(stair->top_level_id)->level() == nullptr)) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "stair top level does not exist");
            } else if (stair->top_level_id != 0 && stair->top_level_id != stair->base_level_id &&
                find_ptr(stair->base_level_id) != nullptr && find_ptr(stair->base_level_id)->level() != nullptr &&
                level_elevation(stair->top_level_id) <= level_elevation(stair->base_level_id) + epsilon) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "stair top level must be above base level");
            }
            if (stair->material_id != 0 && get_material(stair->material_id) == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, element.id(), "stair references missing material");
            }
        } else if (const auto* proxy = element.proxy()) {
            if (find_ptr(proxy->level_id) == nullptr || find_ptr(proxy->level_id)->level() == nullptr) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, element.id(), "proxy level does not exist");
            }
        }
    }

    for (const auto& [system_id, system] : floor_systems_) {
        if (system.level_id != 0 &&
            (find_ptr(system.level_id) == nullptr || find_ptr(system.level_id)->level() == nullptr)) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "floor system level does not exist");
        }
        const auto* room_element = find_ptr(system.room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room == nullptr && system.room_id != 0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "floor system references missing room");
        } else if (room != nullptr) {
            if (system.area_square_meters < 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "floor system area cannot be negative");
            }
            if (!cyclic_polygon_equal(system.boundary_polygon, room->interior_boundary_polygon)) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "floor system boundary should match room interior boundary");
            }
            if (std::abs(system.area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, system_id, "floor system area should match room interior area");
            }
            if (system.level_id != room->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "floor system level does not match room");
            }
        } else if (system.area_square_meters <= 0.0 || polygon_area(system.boundary_polygon) <= epsilon) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "manual floor system profile must have positive area");
        }
        const auto* assembly = get_layered_assembly(system.assembly_id);
        if (assembly == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "floor system references missing assembly");
        } else if (assembly->kind != LayeredAssemblyKind::Floor) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "floor system assembly must be floor kind");
        }
    }

    for (const auto& [system_id, system] : ceiling_systems_) {
        if (system.level_id != 0 &&
            (find_ptr(system.level_id) == nullptr || find_ptr(system.level_id)->level() == nullptr)) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "ceiling system level does not exist");
        }
        const auto* room_element = find_ptr(system.room_id);
        const auto* room = room_element == nullptr ? nullptr : room_element->room();
        if (room == nullptr && system.room_id != 0) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "ceiling system references missing room");
        } else if (room != nullptr) {
            if (system.area_square_meters < 0.0) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "ceiling system area cannot be negative");
            }
            if (!cyclic_polygon_equal(system.boundary_polygon, room->interior_boundary_polygon)) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::MissingRoomBoundaryWall, system_id, "ceiling system boundary should match room interior boundary");
            }
            if (std::abs(system.area_square_meters - room->interior_area_square_meters) > 1.0e-6) {
                add_issue(report, ValidationSeverity::Warning, ValidationIssueCode::NonPositiveRoomArea, system_id, "ceiling system area should match room interior area");
            }
            if (system.level_id != room->level_id) {
                add_issue(report, ValidationSeverity::Error, ValidationIssueCode::LevelMismatch, system_id, "ceiling system level does not match room");
            }
        } else if (system.area_square_meters <= 0.0 || polygon_area(system.boundary_polygon) <= epsilon) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::NonPositiveRoomArea, system_id, "manual ceiling system profile must have positive area");
        }
        const auto* assembly = get_layered_assembly(system.assembly_id);
        if (assembly == nullptr) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "ceiling system references missing assembly");
        } else if (assembly->kind != LayeredAssemblyKind::Ceiling) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::InvalidJoin, system_id, "ceiling system assembly must be ceiling kind");
        }
    }

    // Validation must stay lightweight.  Detailed layer quantities and
    // material takeoff are explicit report operations, not a side effect of
    // merely validating the document.
    for (const auto& element : elements_) {
        const auto* wall = element.wall();
        if (wall == nullptr) {
            continue;
        }
        const auto gross_area = line_length(wall->axis) * resolved_wall_height(*wall);
        auto opening_area = 0.0;
        for (const auto& opening : wall->openings) {
            opening_area += opening.width_meters * opening.height_meters;
        }
        if (opening_area > gross_area + epsilon) {
            add_issue(report, ValidationSeverity::Error, ValidationIssueCode::OpeningOutsideWall, element.id(), "opening area exceeds wall gross area");
        }
    }
    return report;
}

} // namespace tbe::core
