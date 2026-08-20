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
    virtual void undo(Document& document);
    virtual void redo(Document& document);
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
    [[nodiscard]] virtual std::vector<ElementId> affected_element_ids() const;
    [[nodiscard]] const DocumentDelta& delta() const noexcept;

protected:
    void capture_before(Document& document, const std::vector<ElementId>& element_ids);
    void capture_after(Document& document, const std::vector<ElementId>& element_ids);
    void restore_before(Document& document);
    void restore_after(Document& document);

    DocumentDelta delta_{};
};

class CreateLevelCommand final : public ICommand {
public:
    CreateLevelCommand(std::string name, double elevation_meters, double default_wall_height_meters);

    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
    [[nodiscard]] ElementId created_id() const noexcept;

private:
    std::string level_name_;
    double elevation_meters_{};
    double default_wall_height_meters_{};
    ElementId created_id_{};
};

class CreateWallCommand final : public ICommand {
public:
    CreateWallCommand(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
    [[nodiscard]] ElementId created_id() const noexcept;

private:
    std::string wall_name_;
    Line2 axis_{};
    double thickness_meters_{};
    double height_meters_{};
    ElementId level_id_{};
    ElementId created_id_{};
};

class MoveWallCommand final : public ICommand {
public:
    MoveWallCommand(ElementId wall_id, Point2 delta);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId wall_id_{};
    Point2 move_delta_{};
};

class SetWallAxisCommand final : public ICommand {
public:
    SetWallAxisCommand(ElementId wall_id, Line2 axis);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId wall_id_{};
    Line2 axis_{};
};

class SplitWallCommand final : public ICommand {
public:
    SplitWallCommand(ElementId wall_id, double offset_meters);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
    [[nodiscard]] ElementId created_wall_id() const noexcept;

private:
    ElementId wall_id_{};
    double offset_meters_{};
    ElementId created_wall_id_{};
};

class DeleteElementCommand final : public ICommand {
public:
    explicit DeleteElementCommand(ElementId element_id);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId element_id_{};
    std::vector<Element> before_{};
};

class InsertDoorCommand final : public ICommand {
public:
    InsertDoorCommand(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
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
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
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

class MoveHostedOpeningCommand final : public ICommand {
public:
    MoveHostedOpeningCommand(ElementId opening_id, double offset_meters);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId opening_id_{};
    double offset_meters_{};
};

class ResizeDoorCommand final : public ICommand {
public:
    ResizeDoorCommand(ElementId door_id, double width_meters, double height_meters);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId door_id_{};
    double width_meters_{};
    double height_meters_{};
};

class ResizeWindowCommand final : public ICommand {
public:
    ResizeWindowCommand(ElementId window_id, double width_meters, double height_meters, double sill_height_meters);

    void execute(Document& document) override;
    void undo(Document& document) override;
    void redo(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;

private:
    ElementId window_id_{};
    double width_meters_{};
    double height_meters_{};
    double sill_height_meters_{};
};

class AutoJoinWallsCommand final : public ICommand {
public:
    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
};

class DetectRoomsCommand final : public ICommand {
public:
    void execute(Document& document) override;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] std::vector<ElementId> affected_element_ids() const override;
    [[nodiscard]] const std::vector<ElementId>& detected_room_ids() const noexcept;

private:
    std::vector<ElementId> detected_room_ids_;
};

struct TransactionEntry {
    std::string command_name{};
    std::vector<ElementId> affected_element_ids{};
    DocumentDelta delta{};
};

class CommandProcessor {
public:
    void execute(Document& document, ICommand& command);
    bool undo_last(Document& document);
    bool redo_last(Document& document);

    [[nodiscard]] const std::vector<TransactionEntry>& history() const noexcept;
    [[nodiscard]] const std::vector<std::string>& transaction_log() const noexcept;

private:
    // TODO: extend this structure into full undo/redo transactions once commands
    // can capture inverse operations and semantic diffs.
    std::vector<TransactionEntry> history_{};
    std::vector<std::string> transaction_log_;
    std::vector<ICommand*> executed_commands_{};
    std::vector<ICommand*> undone_commands_{};
};

} // namespace tbe::core
