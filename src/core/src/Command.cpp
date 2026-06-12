#include "tbe/core/Command.hpp"

#include <utility>

namespace tbe::core {

CreateWallCommand::CreateWallCommand(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id)
    : wall_name_(std::move(name)),
      axis_(axis),
      thickness_meters_(thickness_meters),
      height_meters_(height_meters),
      level_id_(level_id) {}

void CreateWallCommand::execute(Document& document) {
    created_id_ = document.create_wall(wall_name_, axis_, thickness_meters_, height_meters_, level_id_);
}

std::string_view CreateWallCommand::name() const noexcept {
    return "CreateWall";
}

ElementId CreateWallCommand::created_id() const noexcept {
    return created_id_;
}

InsertDoorCommand::InsertDoorCommand(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters)
    : door_name_(std::move(name)),
      host_wall_id_(host_wall_id),
      offset_meters_(offset_meters),
      width_meters_(width_meters),
      height_meters_(height_meters) {}

void InsertDoorCommand::execute(Document& document) {
    created_id_ = document.create_door(door_name_, host_wall_id_, offset_meters_, width_meters_, height_meters_);
}

std::string_view InsertDoorCommand::name() const noexcept {
    return "InsertDoor";
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
    created_id_ = document.create_window(window_name_, host_wall_id_, offset_meters_, width_meters_, height_meters_, sill_height_meters_);
}

std::string_view InsertWindowCommand::name() const noexcept {
    return "InsertWindow";
}

ElementId InsertWindowCommand::created_id() const noexcept {
    return created_id_;
}

void AutoJoinWallsCommand::execute(Document& document) {
    document.auto_join_walls();
}

std::string_view AutoJoinWallsCommand::name() const noexcept {
    return "AutoJoinWalls";
}

void DetectRoomsCommand::execute(Document& document) {
    detected_room_ids_ = document.detect_rooms();
}

std::string_view DetectRoomsCommand::name() const noexcept {
    return "DetectRooms";
}

const std::vector<ElementId>& DetectRoomsCommand::detected_room_ids() const noexcept {
    return detected_room_ids_;
}

void CommandProcessor::execute(Document& document, ICommand& command) {
    command.execute(document);
    transaction_log_.emplace_back(command.name());
}

const std::vector<std::string>& CommandProcessor::transaction_log() const noexcept {
    return transaction_log_;
}

} // namespace tbe::core
