#include "tbe/core/Document.hpp"

#include "tbe/core/GeometryService.hpp"

#include <algorithm>
#include <cmath>
#include <set>
#include <stdexcept>
#include <utility>

namespace tbe::core {

namespace {

constexpr auto epsilon = 1.0e-9;

double length(const Line2& line) {
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

bool between(double value, double first, double second) {
    return value >= (std::min(first, second) - epsilon) && value <= (std::max(first, second) + epsilon);
}

bool same_point(Point2 first, Point2 second) {
    return std::abs(first.x - second.x) < epsilon && std::abs(first.y - second.y) < epsilon;
}

std::optional<Point2> segment_intersection(Line2 first, Line2 second) {
    const auto x1 = first.start.x;
    const auto y1 = first.start.y;
    const auto x2 = first.end.x;
    const auto y2 = first.end.y;
    const auto x3 = second.start.x;
    const auto y3 = second.start.y;
    const auto x4 = second.end.x;
    const auto y4 = second.end.y;

    const auto denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4));
    if (std::abs(denominator) < epsilon) {
        return std::nullopt;
    }

    const auto px = (((x1 * y2) - (y1 * x2)) * (x3 - x4) - (x1 - x2) * ((x3 * y4) - (y3 * x4))) / denominator;
    const auto py = (((x1 * y2) - (y1 * x2)) * (y3 - y4) - (y1 - y2) * ((x3 * y4) - (y3 * x4))) / denominator;

    if (!between(px, x1, x2) || !between(py, y1, y2) || !between(px, x3, x4) || !between(py, y3, y4)) {
        return std::nullopt;
    }

    return Point2{.x = px, .y = py};
}

bool is_endpoint(Point2 point, Line2 line) {
    return same_point(point, line.start) || same_point(point, line.end);
}

WallJoinKind join_kind(Point2 point, Line2 first, Line2 second) {
    const auto first_endpoint = is_endpoint(point, first);
    const auto second_endpoint = is_endpoint(point, second);

    if (first_endpoint && second_endpoint) {
        return WallJoinKind::End;
    }
    if (first_endpoint || second_endpoint) {
        return WallJoinKind::Tee;
    }
    return WallJoinKind::Cross;
}

bool openings_overlap(double first_offset, double first_width, double second_offset, double second_width) {
    const auto first_start = first_offset - (first_width / 2.0);
    const auto first_end = first_offset + (first_width / 2.0);
    const auto second_start = second_offset - (second_width / 2.0);
    const auto second_end = second_offset + (second_width / 2.0);
    return first_start < second_end && second_start < first_end;
}

bool near(double first, double second) {
    return std::abs(first - second) < 1.0e-9;
}

bool is_horizontal(const Line2& line) {
    return near(line.start.y, line.end.y) && !near(line.start.x, line.end.x);
}

bool is_vertical(const Line2& line) {
    return near(line.start.x, line.end.x) && !near(line.start.y, line.end.y);
}

double min_x(const Line2& line) {
    return std::min(line.start.x, line.end.x);
}

double max_x(const Line2& line) {
    return std::max(line.start.x, line.end.x);
}

double min_y(const Line2& line) {
    return std::min(line.start.y, line.end.y);
}

double max_y(const Line2& line) {
    return std::max(line.start.y, line.end.y);
}

} // namespace

Document::Document(std::string name)
    : name_(std::move(name)) {
    if (name_.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }
}

std::string_view Document::name() const noexcept {
    return name_;
}

void Document::rename(std::string name) {
    if (name.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }

    name_ = std::move(name);
}

ElementId Document::create_level(std::string name, double elevation_meters, double default_wall_height_meters) {
    if (name.empty()) {
        throw std::invalid_argument("level name must not be empty");
    }
    if (default_wall_height_meters <= 0.0) {
        throw std::invalid_argument("default wall height must be positive");
    }

    const auto id = allocate_id();
    const auto level_name = name;
    elements_.emplace_back(id, ElementKind::Level, std::move(name), LevelData{
        .name = level_name,
        .elevation_meters = elevation_meters,
        .default_wall_height_meters = default_wall_height_meters,
    });
    return id;
}

ElementId Document::create_wall(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id) {
    if (name.empty()) {
        throw std::invalid_argument("wall name must not be empty");
    }
    if (length(axis) <= epsilon || height_meters <= 0.0 || thickness_meters <= 0.0) {
        throw std::invalid_argument("wall dimensions must be positive");
    }
    if (level_id != 0) {
        (void)require_level(level_id);
    }

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Wall, std::move(name), WallData{
        .level_id = level_id,
        .axis = axis,
        .thickness_meters = thickness_meters,
        .height_meters = height_meters,
    });
    auto_join_walls();
    return id;
}

ElementId Document::create_door(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters) {
    if (name.empty()) {
        throw std::invalid_argument("door name must not be empty");
    }
    auto& wall_element = require_wall(host_wall_id);
    const auto* wall = wall_element.wall();
    validate_opening(*wall, offset_meters, width_meters, height_meters);

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Door, std::move(name), DoorData{
        .host_wall_id = host_wall_id,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Door,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = 0.0,
    });

    return id;
}

ElementId Document::create_window(
    std::string name,
    ElementId host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    if (name.empty()) {
        throw std::invalid_argument("window name must not be empty");
    }
    if (sill_height_meters < 0.0) {
        throw std::invalid_argument("window sill height must not be negative");
    }

    auto& wall_element = require_wall(host_wall_id);
    const auto* wall = wall_element.wall();
    validate_opening(*wall, offset_meters, width_meters, height_meters + sill_height_meters);

    const auto id = allocate_id();
    elements_.emplace_back(id, ElementKind::Window, std::move(name), WindowData{
        .host_wall_id = host_wall_id,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
    });

    add_opening_to_wall(host_wall_id, HostedOpening{
        .element_id = id,
        .kind = OpeningKind::Window,
        .offset_meters = offset_meters,
        .width_meters = width_meters,
        .height_meters = height_meters,
        .sill_height_meters = sill_height_meters,
    });

    return id;
}

void Document::auto_join_walls() {
    for (auto& element : elements_) {
        if (auto* wall = element.wall()) {
            if (!wall->joins.empty()) {
                wall->joins.clear();
                mark_wall_dirty(element);
            }
        }
    }

    for (auto first = elements_.begin(); first != elements_.end(); ++first) {
        auto* first_wall = first->wall();
        if (first_wall == nullptr) {
            continue;
        }

        for (auto second = std::next(first); second != elements_.end(); ++second) {
            auto* second_wall = second->wall();
            if (second_wall == nullptr) {
                continue;
            }

            const auto intersection = segment_intersection(first_wall->axis, second_wall->axis);
            if (!intersection.has_value()) {
                continue;
            }

            const auto kind = join_kind(*intersection, first_wall->axis, second_wall->axis);
            first_wall->joins.push_back(WallJoin{
                .other_wall_id = second->id(),
                .point = *intersection,
                .other_axis = second_wall->axis,
                .kind = kind,
            });
            second_wall->joins.push_back(WallJoin{
                .other_wall_id = first->id(),
                .point = *intersection,
                .other_axis = first_wall->axis,
                .kind = kind,
            });
            mark_wall_dirty(*first);
            mark_wall_dirty(*second);
        }
    }
}

std::vector<ElementId> Document::detect_rooms() {
    elements_.erase(std::remove_if(elements_.begin(), elements_.end(), [](const Element& element) {
        return element.kind() == ElementKind::Room;
    }), elements_.end());

    struct WallRef {
        ElementId id{};
        const WallData* wall{};
    };

    std::vector<WallRef> walls;
    for (const auto& element : elements_) {
        if (const auto* wall = element.wall()) {
            walls.push_back(WallRef{.id = element.id(), .wall = wall});
        }
    }

    std::vector<ElementId> room_ids;
    std::set<std::vector<ElementId>> seen_boundaries;

    for (const auto& bottom : walls) {
        if (!is_horizontal(bottom.wall->axis)) {
            continue;
        }

        for (const auto& top : walls) {
            if (bottom.id == top.id || !is_horizontal(top.wall->axis)) {
                continue;
            }
            if (bottom.wall->level_id != top.wall->level_id) {
                continue;
            }
            if (!near(min_x(bottom.wall->axis), min_x(top.wall->axis)) || !near(max_x(bottom.wall->axis), max_x(top.wall->axis))) {
                continue;
            }

            const auto low_y = std::min(bottom.wall->axis.start.y, top.wall->axis.start.y);
            const auto high_y = std::max(bottom.wall->axis.start.y, top.wall->axis.start.y);
            if (near(low_y, high_y)) {
                continue;
            }

            const auto left_x = min_x(bottom.wall->axis);
            const auto right_x = max_x(bottom.wall->axis);
            if (near(left_x, right_x)) {
                continue;
            }

            for (const auto& left : walls) {
                if (!is_vertical(left.wall->axis) || left.wall->level_id != bottom.wall->level_id || !near(left.wall->axis.start.x, left_x)) {
                    continue;
                }

                for (const auto& right : walls) {
                    if (right.id == left.id || !is_vertical(right.wall->axis) || right.wall->level_id != bottom.wall->level_id) {
                        continue;
                    }
                    if (!near(right.wall->axis.start.x, right_x)) {
                        continue;
                    }
                    if (!near(min_y(left.wall->axis), low_y) || !near(max_y(left.wall->axis), high_y)) {
                        continue;
                    }
                    if (!near(min_y(right.wall->axis), low_y) || !near(max_y(right.wall->axis), high_y)) {
                        continue;
                    }

                    auto boundary_ids = std::vector<ElementId>{bottom.id, top.id, left.id, right.id};
                    std::sort(boundary_ids.begin(), boundary_ids.end());
                    if (!seen_boundaries.insert(boundary_ids).second) {
                        continue;
                    }

                    const auto width = right_x - left_x;
                    const auto depth = high_y - low_y;
                    const auto id = allocate_id();
                    elements_.emplace_back(id, ElementKind::Room, "Room", RoomData{
                        .boundary_wall_ids = boundary_ids,
                        .area_square_meters = width * depth,
                        .perimeter_meters = 2.0 * (width + depth),
                        .level_id = bottom.wall->level_id,
                        .boundary_polygon = {
                            Point2{.x = left_x, .y = low_y},
                            Point2{.x = right_x, .y = low_y},
                            Point2{.x = right_x, .y = high_y},
                            Point2{.x = left_x, .y = high_y},
                        },
                    });
                    room_ids.push_back(id);
                }
            }
        }
    }

    return room_ids;
}

void Document::regenerate_dirty_geometry() {
    GeometryService geometry;
    for (auto& element : elements_) {
        auto* wall = element.wall();
        if (wall == nullptr || !wall->geometry.dirty) {
            continue;
        }

        wall->geometry = geometry.build_wall_geometry(*wall, element.revision());
    }
}

const std::vector<Element>& Document::elements() const noexcept {
    return elements_;
}

std::optional<Element> Document::find(ElementId id) const {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return std::nullopt;
    }

    return *found;
}

const Element* Document::find_ptr(ElementId id) const noexcept {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return nullptr;
    }

    return &(*found);
}

Element* Document::find_ptr(ElementId id) noexcept {
    const auto found = std::find_if(elements_.begin(), elements_.end(), [id](const Element& element) {
        return element.id() == id;
    });

    if (found == elements_.end()) {
        return nullptr;
    }

    return &(*found);
}

ElementId Document::allocate_id() noexcept {
    return next_id_++;
}

Element& Document::require_level(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->level() == nullptr) {
        throw std::invalid_argument("level does not exist");
    }

    return *element;
}

Element& Document::require_wall(ElementId id) {
    auto* element = find_ptr(id);
    if (element == nullptr || element->wall() == nullptr) {
        throw std::invalid_argument("host wall does not exist");
    }

    return *element;
}

const Element& Document::require_wall(ElementId id) const {
    const auto* element = find_ptr(id);
    if (element == nullptr || element->wall() == nullptr) {
        throw std::invalid_argument("host wall does not exist");
    }

    return *element;
}

void Document::add_opening_to_wall(ElementId host_wall_id, HostedOpening opening) {
    auto& wall_element = require_wall(host_wall_id);
    auto* wall = wall_element.wall();
    wall->openings.push_back(opening);
    mark_wall_dirty(wall_element);
}

void Document::validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const {
    if (offset_meters < 0.0 || width_meters <= 0.0 || height_meters <= 0.0) {
        throw std::invalid_argument("opening dimensions must be positive");
    }

    if (height_meters > wall.height_meters) {
        throw std::invalid_argument("opening is taller than host wall");
    }

    const auto wall_length = length(wall.axis);
    const auto half_width = width_meters / 2.0;
    if ((offset_meters - half_width) < 0.0 || (offset_meters + half_width) > wall_length) {
        throw std::invalid_argument("opening must stay inside host wall");
    }

    for (const auto& opening : wall.openings) {
        if (openings_overlap(offset_meters, width_meters, opening.offset_meters, opening.width_meters)) {
            throw std::invalid_argument("opening overlaps an existing hosted opening");
        }
    }
}

void Document::mark_wall_dirty(Element& wall) noexcept {
    auto* wall_data = wall.wall();
    if (wall_data == nullptr) {
        return;
    }

    wall_data->geometry.dirty = true;
    wall.touch();
}

void Document::replace_state(std::string name, std::vector<Element> elements, ElementId next_id) {
    if (name.empty()) {
        throw std::invalid_argument("document name must not be empty");
    }
    if (next_id == 0) {
        throw std::invalid_argument("next element id must be positive");
    }

    name_ = std::move(name);
    elements_ = std::move(elements);
    next_id_ = next_id;
}

} // namespace tbe::core
