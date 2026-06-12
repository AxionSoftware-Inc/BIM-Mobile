#include "tbe/core/Element.hpp"

#include <utility>

namespace tbe::core {

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

const WindowData* Element::window() const noexcept {
    return std::get_if<WindowData>(&payload_);
}

const LevelData* Element::level() const noexcept {
    return std::get_if<LevelData>(&payload_);
}

const RoomData* Element::room() const noexcept {
    return std::get_if<RoomData>(&payload_);
}

void Element::touch() noexcept {
    ++revision_;
}

} // namespace tbe::core
