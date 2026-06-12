#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace tbe::core {

using ElementId = std::uint64_t;
using Revision = std::uint64_t;

enum class ElementKind {
    Level,
    Wall,
    Door,
    Window,
    Room,
    Column,
    Slab
};

struct Point2 {
    double x{};
    double y{};
};

struct Point3 {
    double x{};
    double y{};
    double z{};
};

struct Line2 {
    Point2 start{};
    Point2 end{};
};

enum class WallJoinKind {
    End,
    Tee,
    Cross
};

enum class OpeningKind {
    Door,
    Window
};

struct WallJoin {
    ElementId other_wall_id{};
    Point2 point{};
    Line2 other_axis{};
    WallJoinKind kind{WallJoinKind::End};
};

struct HostedOpening {
    ElementId element_id{};
    OpeningKind kind{OpeningKind::Door};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
    double sill_height_meters{};
};

struct OpeningRectangle {
    ElementId element_id{};
    OpeningKind kind{OpeningKind::Door};
    double x_min{};
    double x_max{};
    double y_min{};
    double y_max{};
    double z_min{};
    double z_max{};
};

struct WallProfile2D {
    std::vector<Point2> polygon{};
    std::vector<OpeningRectangle> openings{};
    bool has_miter_join{};
    int t_junction_placeholders{};
};

struct MeshBuffer {
    std::vector<Point3> vertices{};
    std::vector<std::uint32_t> indices{};
};

struct GeneratedGeometry {
    bool dirty{true};
    Revision source_revision{};
    int vertices{};
    int triangles{};
    int openings_cut{};
    double solid_volume_cubic_meters{};
    WallProfile2D profile{};
    MeshBuffer mesh{};
};

struct WallData {
    ElementId level_id{};
    Line2 axis{};
    double thickness_meters{};
    double height_meters{};
    std::vector<WallJoin> joins{};
    std::vector<HostedOpening> openings{};
    GeneratedGeometry geometry{};
};

struct DoorData {
    ElementId host_wall_id{};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
};

struct WindowData {
    ElementId host_wall_id{};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
    double sill_height_meters{};
};

struct LevelData {
    std::string name{};
    double elevation_meters{};
    double default_wall_height_meters{};
};

struct RoomData {
    std::vector<ElementId> boundary_wall_ids{};
    double area_square_meters{};
    double perimeter_meters{};
    ElementId level_id{};
    std::vector<Point2> boundary_polygon{};
};

class Element {
public:
    using Payload = std::variant<LevelData, WallData, DoorData, WindowData, RoomData>;

    Element(ElementId id, ElementKind kind, std::string name, Payload payload, Revision revision = 1);

    [[nodiscard]] ElementId id() const noexcept;
    [[nodiscard]] ElementKind kind() const noexcept;
    [[nodiscard]] std::string_view name() const noexcept;
    [[nodiscard]] Revision revision() const noexcept;

    [[nodiscard]] const WallData* wall() const noexcept;
    [[nodiscard]] WallData* wall() noexcept;
    [[nodiscard]] const DoorData* door() const noexcept;
    [[nodiscard]] const WindowData* window() const noexcept;
    [[nodiscard]] const LevelData* level() const noexcept;
    [[nodiscard]] const RoomData* room() const noexcept;

    void touch() noexcept;

private:
    ElementId id_{};
    ElementKind kind_{ElementKind::Wall};
    std::string name_;
    Revision revision_{};
    Payload payload_;
};

} // namespace tbe::core
