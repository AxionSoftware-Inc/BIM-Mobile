#pragma once

#include "tbe/core/Document.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace tbe::core {

class ICommand {
public:
    virtual ~ICommand() = default;

    virtual void execute(Document& document) = 0;
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
};

class CreateWallCommand final : public ICommand {
public:
    CreateWallCommand(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id);

    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] ElementId created_id() const noexcept;

private:
    std::string wall_name_;
    Line2 axis_{};
    double thickness_meters_{};
    double height_meters_{};
    ElementId level_id_{};
    ElementId created_id_{};
};

class InsertDoorCommand final : public ICommand {
public:
    InsertDoorCommand(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters);

    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] ElementId created_id() const noexcept;

private:
    std::string door_name_;
    ElementId host_wall_id_{};
    double offset_meters_{};
    double width_meters_{};
    double height_meters_{};
    ElementId created_id_{};
};

class InsertWindowCommand final : public ICommand {
public:
    InsertWindowCommand(
        std::string name,
        ElementId host_wall_id,
        double offset_meters,
        double width_meters,
        double height_meters,
        double sill_height_meters
    );

    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] ElementId created_id() const noexcept;

private:
    std::string window_name_;
    ElementId host_wall_id_{};
    double offset_meters_{};
    double width_meters_{};
    double height_meters_{};
    double sill_height_meters_{};
    ElementId created_id_{};
};

class AutoJoinWallsCommand final : public ICommand {
public:
    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
};

class DetectRoomsCommand final : public ICommand {
public:
    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] const std::vector<ElementId>& detected_room_ids() const noexcept;

private:
    std::vector<ElementId> detected_room_ids_;
};

class CommandProcessor {
public:
    void execute(Document& document, ICommand& command);

    [[nodiscard]] const std::vector<std::string>& transaction_log() const noexcept;

private:
    std::vector<std::string> transaction_log_;
};

} // namespace tbe::core
