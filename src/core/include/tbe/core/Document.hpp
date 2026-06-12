#pragma once

#include "tbe/core/Element.hpp"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tbe::core {

class Document {
public:
    explicit Document(std::string name);

    [[nodiscard]] std::string_view name() const noexcept;
    void rename(std::string name);

    ElementId create_level(std::string name, double elevation_meters, double default_wall_height_meters);
    ElementId create_wall(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id = 0);
    ElementId create_door(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters);
    ElementId create_window(
        std::string name,
        ElementId host_wall_id,
        double offset_meters,
        double width_meters,
        double height_meters,
        double sill_height_meters
    );

    void auto_join_walls();
    std::vector<ElementId> detect_rooms();
    void regenerate_dirty_geometry();

    [[nodiscard]] std::string to_json() const;
    [[nodiscard]] static Document from_json(std::string_view json);

    [[nodiscard]] const std::vector<Element>& elements() const noexcept;
    [[nodiscard]] std::optional<Element> find(ElementId id) const;
    [[nodiscard]] const Element* find_ptr(ElementId id) const noexcept;
    [[nodiscard]] Element* find_ptr(ElementId id) noexcept;

private:
    [[nodiscard]] ElementId allocate_id() noexcept;
    [[nodiscard]] Element& require_level(ElementId id);
    [[nodiscard]] Element& require_wall(ElementId id);
    [[nodiscard]] const Element& require_wall(ElementId id) const;
    void add_opening_to_wall(ElementId host_wall_id, HostedOpening opening);
    void validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const;
    void mark_wall_dirty(Element& wall) noexcept;
    void replace_state(std::string name, std::vector<Element> elements, ElementId next_id);

    std::string name_;
    std::vector<Element> elements_;
    ElementId next_id_{1};
};

} // namespace tbe::core
