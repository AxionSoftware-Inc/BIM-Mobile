#include "tbe/core/Element.hpp"

#include <algorithm>
#include <utility>

namespace tbe::core {

namespace {

std::vector<ElementId> lookup_ids(const std::map<ElementId, std::vector<ElementId>>& values, ElementId key) {
    const auto found = values.find(key);
    if (found == values.end()) {
        return {};
    }
    return found->second;
}

} // namespace

std::vector<ElementId> DependencyGraph::dependent_rooms(ElementId wall_id) const {
    return lookup_ids(rooms_by_wall, wall_id);
}

std::vector<ElementId> DependencyGraph::dependent_openings(ElementId wall_id) const {
    return lookup_ids(openings_by_wall, wall_id);
}

std::vector<ElementId> DependencyGraph::connected_walls(ElementId wall_id) const {
    return lookup_ids(connected_walls_by_wall, wall_id);
}

std::vector<ElementId> DependencyGraph::dependent_geometry(ElementId element_id) const {
    return lookup_ids(geometry_by_element, element_id);
}

int ValidationReport::issue_count() const noexcept {
    return static_cast<int>(issues.size());
}

int ValidationReport::warning_count() const noexcept {
    return static_cast<int>(std::count_if(issues.begin(), issues.end(), [](const ValidationIssue& issue) {
        return issue.severity == ValidationSeverity::Warning;
    }));
}

int ValidationReport::error_count() const noexcept {
    return static_cast<int>(std::count_if(issues.begin(), issues.end(), [](const ValidationIssue& issue) {
        return issue.severity == ValidationSeverity::Error;
    }));
}

Element::Element(ElementId id, ElementKind kind, std::string name, Payload payload, Revision revision)
    : id_(id),
      kind_(kind),
      name_(std::move(name)),
      revision_(revision),
      payload_(std::move(payload)) {}

ElementId Element::id() const noexcept {
    return id_;
}

ElementKind Element::kind() const noexcept {
    return kind_;
}

std::string_view Element::name() const noexcept {
    return name_;
}

Revision Element::revision() const noexcept {
    return revision_;
}

const WallData* Element::wall() const noexcept {
    return std::get_if<WallData>(&payload_);
}

WallData* Element::wall() noexcept {
    return std::get_if<WallData>(&payload_);
}

const DoorData* Element::door() const noexcept {
    return std::get_if<DoorData>(&payload_);
}

DoorData* Element::door() noexcept {
    return std::get_if<DoorData>(&payload_);
}

const WindowData* Element::window() const noexcept {
    return std::get_if<WindowData>(&payload_);
}

WindowData* Element::window() noexcept {
    return std::get_if<WindowData>(&payload_);
}

const LevelData* Element::level() const noexcept {
    return std::get_if<LevelData>(&payload_);
}

const RoomData* Element::room() const noexcept {
    return std::get_if<RoomData>(&payload_);
}

RoomData* Element::room() noexcept {
    return std::get_if<RoomData>(&payload_);
}

const SlabData* Element::slab() const noexcept {
    return std::get_if<SlabData>(&payload_);
}

SlabData* Element::slab() noexcept {
    return std::get_if<SlabData>(&payload_);
}

const RoofData* Element::roof() const noexcept {
    return std::get_if<RoofData>(&payload_);
}

RoofData* Element::roof() noexcept {
    return std::get_if<RoofData>(&payload_);
}

const ColumnData* Element::column() const noexcept {
    return std::get_if<ColumnData>(&payload_);
}

ColumnData* Element::column() noexcept {
    return std::get_if<ColumnData>(&payload_);
}

const BeamData* Element::beam() const noexcept {
    return std::get_if<BeamData>(&payload_);
}

BeamData* Element::beam() noexcept {
    return std::get_if<BeamData>(&payload_);
}

const StairData* Element::stair() const noexcept {
    return std::get_if<StairData>(&payload_);
}

StairData* Element::stair() noexcept {
    return std::get_if<StairData>(&payload_);
}

void Element::touch() noexcept {
    ++revision_;
}

} // namespace tbe::core
