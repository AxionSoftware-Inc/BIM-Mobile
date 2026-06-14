#pragma once

#include <cstdint>
#include <map>
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
    Roof,
    Column,
    Beam,
    Stair,
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

enum class RoomBoundaryMode {
    Centerline,
    InteriorFinishFace
};

enum class WallRoomSide {
    Left,
    Right,
    Exterior
};

enum class MaterialCategory {
    Structural,
    Finish,
    Insulation,
    Glass,
    Generic
};

enum class WallLayerFunction {
    Core,
    InteriorFinish,
    ExteriorFinish,
    Insulation,
    AirGap,
    Generic
};

enum class QuantityType {
    Area,
    Volume,
    Length,
    Count
};

enum class LayeredAssemblyKind {
    Floor,
    Ceiling
};

enum class RoofType {
    Flat,
    SimpleGable
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
    ElementId wall_type_id{};
    Line2 axis{};
    double thickness_meters{};
    double height_meters{};
    std::vector<WallJoin> joins{};
    std::vector<HostedOpening> openings{};
    GeneratedGeometry geometry{};
};

struct DoorData {
    ElementId level_id{};
    ElementId host_wall_id{};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
};

struct WindowData {
    ElementId level_id{};
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
    ElementId level_id{};
    RoomBoundaryMode preferred_boundary_mode{RoomBoundaryMode::Centerline};
    std::vector<Point2> centerline_boundary_polygon{};
    std::vector<Point2> interior_boundary_polygon{};
    double centerline_area_square_meters{};
    double interior_area_square_meters{};
    double centerline_perimeter_meters{};
    double interior_perimeter_meters{};
    double floor_finish_area_square_meters{};
    double ceiling_area_square_meters{};
    double baseboard_length_meters{};
    double interior_wall_finish_area_square_meters{};
};

struct SlabData {
    ElementId level_id{};
    std::vector<Point2> boundary_polygon{};
    double thickness_meters{};
    ElementId material_id{};
    ElementId assembly_id{};
    double elevation_offset_meters{};
    bool generated_geometry_dirty{true};
    MeshBuffer mesh{};
    double area_square_meters{};
    double volume_cubic_meters{};
};

struct RoofData {
    ElementId level_id{};
    std::vector<Point2> boundary_polygon{};
    RoofType roof_type{RoofType::Flat};
    double thickness_meters{};
    std::optional<double> slope_degrees{};
    std::optional<double> overhang_meters{};
    ElementId material_id{};
    ElementId assembly_id{};
    bool generated_geometry_dirty{true};
    MeshBuffer mesh{};
    double area_square_meters{};
    double volume_cubic_meters{};
};

struct ColumnData {
    ElementId level_id{};
    Point2 position{};
    double width_meters{};
    double depth_meters{};
    double height_meters{};
    ElementId material_id{};
    bool generated_geometry_dirty{true};
    MeshBuffer mesh{};
    double volume_cubic_meters{};
};

struct BeamData {
    ElementId level_id{};
    Point2 start{};
    Point2 end{};
    double width_meters{};
    double height_meters{};
    ElementId material_id{};
    bool generated_geometry_dirty{true};
    MeshBuffer mesh{};
    double length_meters{};
    double volume_cubic_meters{};
};

struct StairData {
    ElementId base_level_id{};
    ElementId top_level_id{};
    Point2 start{};
    Point2 direction{};
    double width_meters{};
    double total_rise_meters{};
    double total_run_meters{};
    int riser_count{};
    int tread_count{};
    ElementId material_id{};
    bool generated_geometry_dirty{true};
    MeshBuffer mesh{};
    double footprint_area_square_meters{};
    double volume_cubic_meters{};
};

struct FloorSystemData {
    ElementId system_id{};
    ElementId room_id{};
    ElementId level_id{};
    ElementId assembly_id{};
    std::vector<Point2> boundary_polygon{};
    double area_square_meters{};
    bool dirty{true};
};

struct CeilingSystemData {
    ElementId system_id{};
    ElementId room_id{};
    ElementId level_id{};
    ElementId assembly_id{};
    std::vector<Point2> boundary_polygon{};
    double area_square_meters{};
    double height_offset_meters{};
    bool dirty{true};
};

struct MaterialDefinition {
    ElementId material_id{};
    std::string name{};
    MaterialCategory category{MaterialCategory::Generic};
    std::optional<double> density_kg_per_m3{};
    std::optional<double> unit_cost{};
    std::map<std::string, std::string> metadata{};
};

struct WallAssemblyLayer {
    ElementId material_id{};
    double thickness_meters{};
    WallLayerFunction function{WallLayerFunction::Generic};
};

struct LayeredAssemblyData {
    ElementId assembly_id{};
    LayeredAssemblyKind kind{LayeredAssemblyKind::Floor};
    std::string name{};
    std::vector<WallAssemblyLayer> layers{};
};

struct WallTypeData {
    ElementId wall_type_id{};
    std::string name{};
    std::vector<WallAssemblyLayer> layers{};
};

struct WallRoomAdjacency {
    ElementId wall_id{};
    ElementId room_id{};
    WallRoomSide side{WallRoomSide::Exterior};
};

struct DependencyGraph {
    std::map<ElementId, std::vector<ElementId>> rooms_by_wall{};
    std::map<ElementId, std::vector<ElementId>> openings_by_wall{};
    std::map<ElementId, std::vector<ElementId>> connected_walls_by_wall{};
    std::map<ElementId, std::vector<ElementId>> geometry_by_element{};

    [[nodiscard]] std::vector<ElementId> dependent_rooms(ElementId wall_id) const;
    [[nodiscard]] std::vector<ElementId> dependent_openings(ElementId wall_id) const;
    [[nodiscard]] std::vector<ElementId> connected_walls(ElementId wall_id) const;
    [[nodiscard]] std::vector<ElementId> dependent_geometry(ElementId element_id) const;
};

enum class ValidationSeverity {
    Warning,
    Error
};

enum class ValidationIssueCode {
    OrphanOpening,
    LevelMismatch,
    OpeningOutsideWall,
    OverlappingOpenings,
    MissingRoomBoundaryWall,
    NonPositiveRoomArea,
    WallTooShort,
    InvalidJoin,
    DuplicateJoin
};

struct ValidationIssue {
    ValidationSeverity severity{ValidationSeverity::Error};
    ValidationIssueCode code{ValidationIssueCode::InvalidJoin};
    ElementId element_id{};
    std::string message{};
};

struct ValidationReport {
    std::vector<ValidationIssue> issues{};

    [[nodiscard]] int issue_count() const noexcept;
    [[nodiscard]] int warning_count() const noexcept;
    [[nodiscard]] int error_count() const noexcept;
};

struct WallScheduleRow {
    ElementId wall_id{};
    ElementId level_id{};
    ElementId wall_type_id{};
    std::string wall_type_name{};
    double length_meters{};
    double thickness_meters{};
    double height_meters{};
    double gross_area_square_meters{};
    double opening_area_square_meters{};
    double net_area_square_meters{};
    double gross_volume_cubic_meters{};
    double net_volume_cubic_meters{};
    double interior_finish_area_square_meters{};
    double exterior_finish_area_square_meters{};
    std::map<ElementId, double> material_volume_by_id{};
};

struct SlabScheduleRow {
    ElementId slab_id{};
    ElementId level_id{};
    double area_square_meters{};
    double thickness_meters{};
    double volume_cubic_meters{};
    std::string material_or_assembly_name{};
};

struct FloorFinishScheduleRow {
    ElementId floor_system_id{};
    ElementId room_id{};
    double area_square_meters{};
    std::string assembly_name{};
    std::map<ElementId, double> layer_quantities{};
};

struct CeilingScheduleRow {
    ElementId ceiling_system_id{};
    ElementId room_id{};
    double area_square_meters{};
    std::string assembly_name{};
    std::map<ElementId, double> layer_quantities{};
};

struct RoofScheduleRow {
    ElementId roof_id{};
    ElementId level_id{};
    RoofType roof_type{RoofType::Flat};
    double area_square_meters{};
    double thickness_meters{};
    double volume_cubic_meters{};
    std::string material_or_assembly_name{};
};

struct ColumnScheduleRow {
    ElementId column_id{};
    ElementId level_id{};
    double width_meters{};
    double depth_meters{};
    double height_meters{};
    double volume_cubic_meters{};
    std::string material_name{};
};

struct BeamScheduleRow {
    ElementId beam_id{};
    ElementId level_id{};
    double length_meters{};
    double width_meters{};
    double height_meters{};
    double volume_cubic_meters{};
    std::string material_name{};
};

struct StairScheduleRow {
    ElementId stair_id{};
    ElementId base_level_id{};
    ElementId top_level_id{};
    double width_meters{};
    double total_rise_meters{};
    double total_run_meters{};
    int riser_count{};
    int tread_count{};
    double footprint_area_square_meters{};
    double volume_cubic_meters{};
    std::string material_name{};
};

struct OpeningScheduleRow {
    ElementId element_id{};
    OpeningKind type{OpeningKind::Door};
    ElementId host_wall_id{};
    double width_meters{};
    double height_meters{};
    double area_square_meters{};
    ElementId level_id{};
};

struct RoomScheduleRow {
    ElementId room_id{};
    ElementId level_id{};
    double centerline_area_square_meters{};
    double interior_area_square_meters{};
    double interior_perimeter_meters{};
    double floor_finish_area_square_meters{};
    double ceiling_area_square_meters{};
    double interior_wall_finish_area_square_meters{};
};

struct MaterialTakeoffRow {
    ElementId material_id{};
    std::string material_name{};
    QuantityType quantity_type{QuantityType::Volume};
    double quantity{};
    std::string unit{};
    std::vector<ElementId> source_element_ids{};
    std::optional<double> estimated_cost{};
};

class Element {
public:
    using Payload = std::variant<LevelData, WallData, DoorData, WindowData, RoomData, SlabData, RoofData, ColumnData, BeamData, StairData>;

    Element(ElementId id, ElementKind kind, std::string name, Payload payload, Revision revision = 1);

    [[nodiscard]] ElementId id() const noexcept;
    [[nodiscard]] ElementKind kind() const noexcept;
    [[nodiscard]] std::string_view name() const noexcept;
    [[nodiscard]] Revision revision() const noexcept;

    [[nodiscard]] const WallData* wall() const noexcept;
    [[nodiscard]] WallData* wall() noexcept;
    [[nodiscard]] const DoorData* door() const noexcept;
    [[nodiscard]] DoorData* door() noexcept;
    [[nodiscard]] const WindowData* window() const noexcept;
    [[nodiscard]] WindowData* window() noexcept;
    [[nodiscard]] const LevelData* level() const noexcept;
    [[nodiscard]] const RoomData* room() const noexcept;
    [[nodiscard]] RoomData* room() noexcept;
    [[nodiscard]] const SlabData* slab() const noexcept;
    [[nodiscard]] SlabData* slab() noexcept;
    [[nodiscard]] const RoofData* roof() const noexcept;
    [[nodiscard]] RoofData* roof() noexcept;
    [[nodiscard]] const ColumnData* column() const noexcept;
    [[nodiscard]] ColumnData* column() noexcept;
    [[nodiscard]] const BeamData* beam() const noexcept;
    [[nodiscard]] BeamData* beam() noexcept;
    [[nodiscard]] const StairData* stair() const noexcept;
    [[nodiscard]] StairData* stair() noexcept;

    void touch() noexcept;

private:
    ElementId id_{};
    ElementKind kind_{ElementKind::Wall};
    std::string name_;
    Revision revision_{};
    Payload payload_;
};

struct ElementSnapshot {
    Element element;
};

struct DocumentDelta {
    std::vector<ElementSnapshot> before{};
    std::vector<ElementSnapshot> after{};
};

} // namespace tbe::core
