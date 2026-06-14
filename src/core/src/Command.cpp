#include "tbe/core/Command.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace tbe::core {

namespace {

bool same_point(Point2 left, Point2 right) {
    return std::abs(left.x - right.x) < 1.0e-9 && std::abs(left.y - right.y) < 1.0e-9;
}

std::vector<ElementId> all_element_ids(const Document& document) {
    std::vector<ElementId> ids;
    ids.reserve(document.elements().size());
    for (const auto& element : document.elements()) {
        ids.push_back(element.id());
    }
    return ids;
}

void remove_missing(Document& document, const std::vector<ElementSnapshot>& snapshots) {
    std::vector<ElementId> expected_ids;
    expected_ids.reserve(snapshots.size());
    for (const auto& snapshot : snapshots) {
        expected_ids.push_back(snapshot.element.id());
    }

    std::vector<ElementId> to_remove;
    for (const auto& element : document.elements()) {
        if (std::find(expected_ids.begin(), expected_ids.end(), element.id()) == expected_ids.end()) {
            to_remove.push_back(element.id());
        }
    }

    for (const auto element_id : to_remove) {
        document.remove_element(element_id);
    }
}

void restore_snapshots(Document& document, const std::vector<ElementSnapshot>& snapshots) {
    remove_missing(document, snapshots);
    for (const auto& snapshot : snapshots) {
        document.restore_element(snapshot.element);
    }
}

std::vector<ElementId> delta_ids(const DocumentDelta& delta) {
    std::vector<ElementId> ids;
    for (const auto& snapshot : delta.after.empty() ? delta.before : delta.after) {
        ids.push_back(snapshot.element.id());
    }
    return ids;
}

} // namespace

void ICommand::undo(Document& document) {
    restore_before(document);
}

void ICommand::redo(Document& document) {
    restore_after(document);
}

std::vector<ElementId> ICommand::affected_element_ids() const {
    return delta_ids(delta_);
}

const DocumentDelta& ICommand::delta() const noexcept {
    return delta_;
}

void ICommand::capture_before(Document& document, const std::vector<ElementId>& element_ids) {
    delta_.before.clear();
    delta_.after.clear();
    for (const auto element_id : element_ids) {
        if (const auto element = document.find(element_id)) {
            delta_.before.push_back(ElementSnapshot{.element = *element});
        }
    }
}

void ICommand::capture_after(Document& document, const std::vector<ElementId>& element_ids) {
    delta_.after.clear();
    for (const auto element_id : element_ids) {
        if (const auto element = document.find(element_id)) {
            delta_.after.push_back(ElementSnapshot{.element = *element});
        }
    }
}

void ICommand::restore_before(Document& document) {
    restore_snapshots(document, delta_.before);
    document.auto_join_walls();
    document.detect_rooms();
}

void ICommand::restore_after(Document& document) {
    restore_snapshots(document, delta_.after);
    document.auto_join_walls();
    document.detect_rooms();
}

CreateLevelCommand::CreateLevelCommand(std::string name, double elevation_meters, double default_wall_height_meters)
    : level_name_(std::move(name)),
      elevation_meters_(elevation_meters),
      default_wall_height_meters_(default_wall_height_meters) {}

void CreateLevelCommand::execute(Document& document) {
    const auto before_ids = all_element_ids(document);
    capture_before(document, before_ids);
    created_id_ = document.create_level(level_name_, elevation_meters_, default_wall_height_meters_);
    capture_after(document, all_element_ids(document));
}

std::string_view CreateLevelCommand::name() const noexcept {
    return "CreateLevel";
}

std::vector<ElementId> CreateLevelCommand::affected_element_ids() const {
    return created_id_ == 0 ? std::vector<ElementId>{} : std::vector<ElementId>{created_id_};
}

ElementId CreateLevelCommand::created_id() const noexcept {
    return created_id_;
}

CreateWallCommand::CreateWallCommand(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id)
    : wall_name_(std::move(name)),
      axis_(axis),
      thickness_meters_(thickness_meters),
      height_meters_(height_meters),
      level_id_(level_id) {}

void CreateWallCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    created_id_ = document.create_wall(wall_name_, axis_, thickness_meters_, height_meters_, level_id_);
    capture_after(document, all_element_ids(document));
}

void CreateWallCommand::undo(Document& document) {
    restore_before(document);
}

void CreateWallCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view CreateWallCommand::name() const noexcept {
    return "CreateWall";
}

std::vector<ElementId> CreateWallCommand::affected_element_ids() const {
    return created_id_ == 0 ? std::vector<ElementId>{} : std::vector<ElementId>{created_id_};
}

ElementId CreateWallCommand::created_id() const noexcept {
    return created_id_;
}

MoveWallCommand::MoveWallCommand(ElementId wall_id, Point2 delta)
    : wall_id_(wall_id),
      move_delta_(delta) {}

void MoveWallCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    const auto original_axis = document.find_ptr(wall_id_)->wall()->axis;
    const auto moved_axis = Line2{
        .start = Point2{.x = original_axis.start.x + move_delta_.x, .y = original_axis.start.y + move_delta_.y},
        .end = Point2{.x = original_axis.end.x + move_delta_.x, .y = original_axis.end.y + move_delta_.y},
    };
    document.set_wall_axis(wall_id_, moved_axis);

    for (const auto& snapshot : delta_.before) {
        const auto* wall = snapshot.element.wall();
        if (wall == nullptr || snapshot.element.id() == wall_id_) {
            continue;
        }

        auto axis = wall->axis;
        auto touched = false;
        if (same_point(axis.start, original_axis.start) || same_point(axis.start, original_axis.end)) {
            axis.start = Point2{.x = axis.start.x + move_delta_.x, .y = axis.start.y + move_delta_.y};
            touched = true;
        }
        if (same_point(axis.end, original_axis.start) || same_point(axis.end, original_axis.end)) {
            axis.end = Point2{.x = axis.end.x + move_delta_.x, .y = axis.end.y + move_delta_.y};
            touched = true;
        }
        if (touched) {
            document.set_wall_axis(snapshot.element.id(), axis);
        }
    }

    capture_after(document, all_element_ids(document));
}

void MoveWallCommand::undo(Document& document) {
    restore_before(document);
}

void MoveWallCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view MoveWallCommand::name() const noexcept {
    return "MoveWall";
}

std::vector<ElementId> MoveWallCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

SetWallAxisCommand::SetWallAxisCommand(ElementId wall_id, Line2 axis)
    : wall_id_(wall_id),
      axis_(axis) {}

void SetWallAxisCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.set_wall_axis(wall_id_, axis_);
    capture_after(document, all_element_ids(document));
}

void SetWallAxisCommand::undo(Document& document) {
    restore_before(document);
}

void SetWallAxisCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view SetWallAxisCommand::name() const noexcept {
    return "SetWallAxis";
}

std::vector<ElementId> SetWallAxisCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

SplitWallCommand::SplitWallCommand(ElementId wall_id, double offset_meters)
    : wall_id_(wall_id),
      offset_meters_(offset_meters) {}

void SplitWallCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    created_wall_id_ = document.split_wall(wall_id_, offset_meters_);
    capture_after(document, all_element_ids(document));
}

void SplitWallCommand::undo(Document& document) {
    restore_before(document);
}

void SplitWallCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view SplitWallCommand::name() const noexcept {
    return "SplitWall";
}

std::vector<ElementId> SplitWallCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

ElementId SplitWallCommand::created_wall_id() const noexcept {
    return created_wall_id_;
}

DeleteElementCommand::DeleteElementCommand(ElementId element_id)
    : element_id_(element_id) {}

void DeleteElementCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.delete_element(element_id_);
    capture_after(document, all_element_ids(document));
}

void DeleteElementCommand::undo(Document& document) {
    restore_before(document);
}

void DeleteElementCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view DeleteElementCommand::name() const noexcept {
    return "DeleteElement";
}

std::vector<ElementId> DeleteElementCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

InsertDoorCommand::InsertDoorCommand(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters)
    : door_name_(std::move(name)),
      host_wall_id_(host_wall_id),
      offset_meters_(offset_meters),
      width_meters_(width_meters),
      height_meters_(height_meters) {}

void InsertDoorCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    created_id_ = document.create_door(door_name_, host_wall_id_, offset_meters_, width_meters_, height_meters_);
    capture_after(document, all_element_ids(document));
}

void InsertDoorCommand::undo(Document& document) {
    restore_before(document);
}

void InsertDoorCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view InsertDoorCommand::name() const noexcept {
    return "InsertDoor";
}

std::vector<ElementId> InsertDoorCommand::affected_element_ids() const {
    return created_id_ == 0 ? std::vector<ElementId>{} : std::vector<ElementId>{host_wall_id_, created_id_};
}

ElementId InsertDoorCommand::created_id() const noexcept {
    return created_id_;
}

InsertWindowCommand::InsertWindowCommand(
    std::string name,
    ElementId host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
)
    : window_name_(std::move(name)),
      host_wall_id_(host_wall_id),
      offset_meters_(offset_meters),
      width_meters_(width_meters),
      height_meters_(height_meters),
      sill_height_meters_(sill_height_meters) {}

void InsertWindowCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    created_id_ = document.create_window(window_name_, host_wall_id_, offset_meters_, width_meters_, height_meters_, sill_height_meters_);
    capture_after(document, all_element_ids(document));
}

void InsertWindowCommand::undo(Document& document) {
    restore_before(document);
}

void InsertWindowCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view InsertWindowCommand::name() const noexcept {
    return "InsertWindow";
}

std::vector<ElementId> InsertWindowCommand::affected_element_ids() const {
    return created_id_ == 0 ? std::vector<ElementId>{} : std::vector<ElementId>{host_wall_id_, created_id_};
}

ElementId InsertWindowCommand::created_id() const noexcept {
    return created_id_;
}

MoveHostedOpeningCommand::MoveHostedOpeningCommand(ElementId opening_id, double offset_meters)
    : opening_id_(opening_id),
      offset_meters_(offset_meters) {}

void MoveHostedOpeningCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.move_hosted_opening(opening_id_, offset_meters_);
    capture_after(document, all_element_ids(document));
}

void MoveHostedOpeningCommand::undo(Document& document) {
    restore_before(document);
}

void MoveHostedOpeningCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view MoveHostedOpeningCommand::name() const noexcept {
    return "MoveHostedOpening";
}

std::vector<ElementId> MoveHostedOpeningCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

ResizeDoorCommand::ResizeDoorCommand(ElementId door_id, double width_meters, double height_meters)
    : door_id_(door_id),
      width_meters_(width_meters),
      height_meters_(height_meters) {}

void ResizeDoorCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.resize_door(door_id_, width_meters_, height_meters_);
    capture_after(document, all_element_ids(document));
}

void ResizeDoorCommand::undo(Document& document) {
    restore_before(document);
}

void ResizeDoorCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view ResizeDoorCommand::name() const noexcept {
    return "ResizeDoor";
}

std::vector<ElementId> ResizeDoorCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

ResizeWindowCommand::ResizeWindowCommand(ElementId window_id, double width_meters, double height_meters, double sill_height_meters)
    : window_id_(window_id),
      width_meters_(width_meters),
      height_meters_(height_meters),
      sill_height_meters_(sill_height_meters) {}

void ResizeWindowCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.resize_window(window_id_, width_meters_, height_meters_, sill_height_meters_);
    capture_after(document, all_element_ids(document));
}

void ResizeWindowCommand::undo(Document& document) {
    restore_before(document);
}

void ResizeWindowCommand::redo(Document& document) {
    restore_after(document);
}

std::string_view ResizeWindowCommand::name() const noexcept {
    return "ResizeWindow";
}

std::vector<ElementId> ResizeWindowCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

void AutoJoinWallsCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    document.auto_join_walls();
    capture_after(document, all_element_ids(document));
}

std::string_view AutoJoinWallsCommand::name() const noexcept {
    return "AutoJoinWalls";
}

std::vector<ElementId> AutoJoinWallsCommand::affected_element_ids() const {
    return delta_ids(delta_);
}

void DetectRoomsCommand::execute(Document& document) {
    capture_before(document, all_element_ids(document));
    detected_room_ids_ = document.detect_rooms();
    capture_after(document, all_element_ids(document));
}

std::string_view DetectRoomsCommand::name() const noexcept {
    return "DetectRooms";
}

std::vector<ElementId> DetectRoomsCommand::affected_element_ids() const {
    return detected_room_ids_;
}

const std::vector<ElementId>& DetectRoomsCommand::detected_room_ids() const noexcept {
    return detected_room_ids_;
}

void CommandProcessor::execute(Document& document, ICommand& command) {
    command.execute(document);
    executed_commands_.push_back(&command);
    undone_commands_.clear();
    history_.push_back(TransactionEntry{
        .command_name = std::string(command.name()),
        .affected_element_ids = command.affected_element_ids(),
        .delta = command.delta(),
    });
    transaction_log_.emplace_back(command.name());
}

bool CommandProcessor::undo_last(Document& document) {
    if (executed_commands_.empty()) {
        return false;
    }

    auto* command = executed_commands_.back();
    executed_commands_.pop_back();
    command->undo(document);
    undone_commands_.push_back(command);
    transaction_log_.emplace_back(std::string("Undo") + std::string(command->name()));
    return true;
}

bool CommandProcessor::redo_last(Document& document) {
    if (undone_commands_.empty()) {
        return false;
    }

    auto* command = undone_commands_.back();
    undone_commands_.pop_back();
    command->redo(document);
    executed_commands_.push_back(command);
    transaction_log_.emplace_back(std::string("Redo") + std::string(command->name()));
    return true;
}

const std::vector<TransactionEntry>& CommandProcessor::history() const noexcept {
    return history_;
}

const std::vector<std::string>& CommandProcessor::transaction_log() const noexcept {
    return transaction_log_;
}

} // namespace tbe::core
