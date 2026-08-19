#include "tbe/core/DependencyGraphService.hpp"

#include "tbe/core/Document.hpp"

#include <algorithm>

namespace tbe::core {

namespace {

void append_unique(std::vector<ElementId>& values, ElementId value) {
    if (std::find(values.begin(), values.end(), value) == values.end()) {
        values.push_back(value);
    }
}

} // namespace

DependencyGraph DependencyGraphService::build(const Document& document) const {
    DependencyGraph graph;

    for (const auto& element : document.elements()) {
        if (const auto* wall = element.wall()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            for (const auto& join : wall->joins) {
                append_unique(graph.connected_walls_by_wall[element.id()], join.other_wall_id);
            }
            for (const auto& opening : wall->openings) {
                append_unique(graph.openings_by_wall[element.id()], opening.element_id);
                append_unique(graph.geometry_by_element[opening.element_id], element.id());
            }
        } else if (const auto* slab = element.slab()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[slab->level_id], element.id());
        } else if (const auto* roof = element.roof()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[roof->level_id], element.id());
        } else if (const auto* column = element.column()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[column->level_id], element.id());
        } else if (const auto* beam = element.beam()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[beam->level_id], element.id());
        } else if (const auto* stair = element.stair()) {
            auto& geometry = graph.geometry_by_element[element.id()];
            append_unique(geometry, element.id());
            append_unique(graph.geometry_by_element[stair->base_level_id], element.id());
            if (stair->top_level_id != 0) {
                append_unique(graph.geometry_by_element[stair->top_level_id], element.id());
            }
        } else if (const auto* room = element.room()) {
            for (const auto boundary_id : room->boundary_wall_ids) {
                append_unique(graph.rooms_by_wall[boundary_id], element.id());
                append_unique(graph.geometry_by_element[boundary_id], element.id());
            }
            for (const auto& [system_id, system] : document.floor_systems()) {
                if (system.room_id == element.id()) {
                    append_unique(graph.geometry_by_element[element.id()], system_id);
                }
            }
            for (const auto& [system_id, system] : document.ceiling_systems()) {
                if (system.room_id == element.id()) {
                    append_unique(graph.geometry_by_element[element.id()], system_id);
                }
            }
        }
    }

    return graph;
}

const DependencyGraph& DependencyGraphService::get(const Document& document) const {
    if (dirty_) {
        cache_ = build(document);
        dirty_ = false;
        ++version_;
    }
    return cache_;
}

void DependencyGraphService::invalidate() noexcept {
    dirty_ = true;
}

Revision DependencyGraphService::version() const noexcept {
    return version_;
}

} // namespace tbe::core
