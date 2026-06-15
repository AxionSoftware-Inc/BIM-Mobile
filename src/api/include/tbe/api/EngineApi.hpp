#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tbe::api {

enum class ApiStatus {
    Ok,
    InvalidArgument,
    NotFound,
    ValidationError,
    InternalError
};

enum class ApiElementKind {
    Unknown,
    Level,
    Wall,
    Door,
    Window,
    Room,
    Slab,
    FloorSystem,
    CeilingSystem,
    Roof,
    Column,
    Beam,
    Stair
};

enum class ApiValidationSeverity {
    Warning,
    Error
};

enum class ApiMaterialCategory {
    Structural,
    Finish,
    Insulation,
    Glass,
    Generic
};

enum class ApiQuantityType {
    Area,
    Volume,
    Length,
    Count
};

enum class ApiRoofType {
    Flat,
    SimpleGable
};

enum class FreshnessState {
    Clean,
    Dirty,
    Stale,
    Computing,
    Failed
};

enum class ComputeMode {
    InteractivePreview,
    Normal,
    FinalExact
};

enum class PerformanceProfile {
    BatterySaver,
    Balanced,
    Performance
};

enum class LoadMode {
    Strict,
    Tolerant,
    Repair
};

enum class HitKind {
    None,
    WallAxis,
    WallBody,
    Opening,
    RoomInterior,
    Slab,
    FloorSystem,
    CeilingSystem,
    Roof,
    Column,
    Beam,
    Stair
};

enum class SnapType {
    None,
    Endpoint,
    Midpoint,
    WallAxis,
    WallIntersection,
    Grid,
    OrthogonalProjection,
    RoomCorner
};

struct Vec2 {
    double x{};
    double y{};
};

struct Vec3 {
    double x{};
    double y{};
    double z{};
};

struct AABB3D {
    Vec3 min{};
    Vec3 max{};
};

struct AABB2D {
    double min_x{};
    double min_y{};
    double max_x{};
    double max_y{};
};

struct ElementIdDTO {
    std::uint64_t value{};
};

struct HitTestPoint {
    ElementIdDTO level_id{};
    Vec2 point{};
    double tolerance_meters{};
};

struct ElementSummaryDTO {
    ElementIdDTO id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    std::string name{};
};

struct WallDTO {
    ElementIdDTO id{};
    std::string name{};
    ElementIdDTO level_id{};
    Vec2 start{};
    Vec2 end{};
    double thickness_meters{};
    double height_meters{};
};

struct DoorDTO {
    ElementIdDTO id{};
    std::string name{};
    ElementIdDTO level_id{};
    ElementIdDTO host_wall_id{};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
};

struct WindowDTO {
    ElementIdDTO id{};
    std::string name{};
    ElementIdDTO level_id{};
    ElementIdDTO host_wall_id{};
    double offset_meters{};
    double width_meters{};
    double height_meters{};
    double sill_height_meters{};
};

struct RenderSceneMeshDTO {
    std::vector<Vec3> positions{};
    std::vector<std::uint32_t> indices{};
    std::optional<std::vector<Vec3>> normals{};
};

struct RenderSceneObjectDTO {
    ElementIdDTO element_id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    ElementIdDTO level_id{};
    bool selectable{true};
    bool visible_by_default{true};
    std::uint64_t revision{};
    AABB3D bounds{};
    RenderSceneMeshDTO mesh{};
    std::string material_category{};
};

struct RenderSceneDTO {
    int scene_version{1};
    std::string units{"meters"};
    std::string coordinate_system{"X/Y plan, Z up"};
    std::vector<RenderSceneObjectDTO> objects{};
    std::size_t object_count{};
    std::size_t vertex_count{};
    std::size_t index_count{};
};

struct RoomDTO {
    ElementIdDTO id{};
    ElementIdDTO level_id{};
    std::vector<Vec2> centerline_boundary_polygon{};
    std::vector<Vec2> interior_boundary_polygon{};
    double centerline_area_square_meters{};
    double interior_area_square_meters{};
    double centerline_perimeter_meters{};
    double interior_perimeter_meters{};
    double baseboard_length_meters{};
};

struct MaterialDTO {
    ElementIdDTO id{};
    std::string name{};
    ApiMaterialCategory category{ApiMaterialCategory::Generic};
    std::optional<double> density_kg_per_m3{};
    std::optional<double> unit_cost{};
};

struct WallTypeDTO {
    ElementIdDTO id{};
    std::string name{};
    double total_thickness_meters{};
};

struct WallScheduleDTO {
    ElementIdDTO wall_id{};
    ElementIdDTO level_id{};
    std::string wall_type_name{};
    double length_meters{};
    double thickness_meters{};
    double height_meters{};
    double gross_area_square_meters{};
    double opening_area_square_meters{};
    double net_area_square_meters{};
    double gross_volume_cubic_meters{};
    double net_volume_cubic_meters{};
};

struct OpeningScheduleDTO {
    ElementIdDTO element_id{};
    std::string type{};
    ElementIdDTO host_wall_id{};
    double width_meters{};
    double height_meters{};
    double area_square_meters{};
    ElementIdDTO level_id{};
};

struct RoomScheduleDTO {
    ElementIdDTO room_id{};
    ElementIdDTO level_id{};
    double centerline_area_square_meters{};
    double interior_area_square_meters{};
    double interior_perimeter_meters{};
    double baseboard_length_meters{};
    double floor_finish_area_square_meters{};
    double ceiling_area_square_meters{};
    double interior_wall_finish_area_square_meters{};
};

struct MaterialTakeoffSummaryDTO {
    ElementIdDTO material_id{};
    std::string material_name{};
    ApiQuantityType quantity_type{ApiQuantityType::Volume};
    double quantity{};
    std::string unit{};
};

struct ValidationIssueDTO {
    ApiValidationSeverity severity{ApiValidationSeverity::Error};
    ElementIdDTO element_id{};
    std::string message{};
};

struct ValidationReportDTO {
    int issue_count{};
    int warning_count{};
    int error_count{};
    std::vector<ValidationIssueDTO> issues{};
};

struct MigrationReportDTO {
    int from_version{};
    int to_version{};
    int migrated_count{};
    int warning_count{};
    int error_count{};
    std::vector<std::string> messages{};
};

struct RepairOptionsDTO {
    bool remove_orphan_openings{true};
    bool remove_invalid_rooms{true};
    bool regenerate_room_metrics{true};
    bool regenerate_geometry{true};
    bool fix_opening_levels_from_host{true};
    bool remove_duplicate_joins{true};
};

struct RepairReportDTO {
    int repaired_count{};
    int warning_count{};
    int error_count{};
    std::vector<std::string> messages{};
};

struct PackageExportOptionsDTO {
    bool include_floorplan_svg{true};
    bool include_walls_obj{true};
    bool include_debug_report_json{true};
};

struct DependencyGraphSummaryDTO {
    std::uint64_t version{};
    std::size_t rooms_by_wall_entries{};
    std::size_t openings_by_wall_entries{};
    std::size_t connected_walls_entries{};
    std::size_t geometry_dependency_entries{};
};

struct ScheduleSummaryDTO {
    std::size_t wall_rows{};
    std::size_t opening_rows{};
    std::size_t room_rows{};
    std::size_t slab_rows{};
    std::size_t roof_rows{};
    std::size_t column_rows{};
    std::size_t beam_rows{};
    std::size_t stair_rows{};
    std::size_t floor_rows{};
    std::size_t ceiling_rows{};
    std::size_t material_takeoff_rows{};
};

struct FreshnessSummaryDTO {
    FreshnessState room_metrics{FreshnessState::Dirty};
    FreshnessState geometry{FreshnessState::Dirty};
    FreshnessState schedules{FreshnessState::Dirty};
    FreshnessState material_takeoff{FreshnessState::Dirty};
    FreshnessState validation_report{FreshnessState::Dirty};
    FreshnessState exports{FreshnessState::Dirty};
};

struct DirtySummaryDTO {
    int dirty_categories{};
    int stale_categories{};
    bool has_room_metrics_work{};
    bool has_geometry_work{};
    bool has_schedule_work{};
    bool has_material_takeoff_work{};
    bool has_validation_work{};
    bool has_export_work{};
};

struct HitTestCandidateDTO {
    ElementIdDTO element_id{};
    ApiElementKind element_kind{ApiElementKind::Unknown};
    HitKind hit_kind{HitKind::None};
    double distance_meters{};
    int priority{};
};

struct SnapOptionsDTO {
    bool enable_grid{true};
    bool enable_endpoints{true};
    bool enable_midpoints{true};
    bool enable_intersections{true};
    bool enable_wall_axis{true};
    bool enable_orthogonal_projection{true};
    bool enable_room_corners{true};
    double grid_size_meters{1.0};
};

struct SnapCandidateDTO {
    Vec2 point{};
    SnapType type{SnapType::None};
    std::optional<ElementIdDTO> source_element_id{};
    double distance_meters{};
    int priority{};
};

struct SpatialIndexStatsDTO {
    std::uint64_t version{};
    std::size_t element_bounds_count{};
    std::size_t bucket_count{};
    double average_bucket_occupancy{};
    std::size_t max_bucket_occupancy{};
    bool dirty{};
};

struct WallFreeIntervalDTO {
    double start_offset_meters{};
    double end_offset_meters{};
    double length_meters{};
};

struct WallHostPlacementDTO {
    ElementIdDTO wall_id{};
    double requested_offset_meters{};
    double wall_local_offset_meters{};
    double adjusted_valid_offset_meters{};
    std::string side{};
    bool valid{};
    std::vector<WallFreeIntervalDTO> free_intervals{};
    std::vector<std::string> warnings{};
};

struct ApiVoidResult {
    ApiStatus status{ApiStatus::Ok};
    std::string message{};
    std::vector<ValidationIssueDTO> validation_issues{};
    FreshnessState freshness{FreshnessState::Clean};

    [[nodiscard]] bool ok() const noexcept {
        return status == ApiStatus::Ok;
    }
};

template <typename T>
struct ApiResult {
    ApiStatus status{ApiStatus::Ok};
    std::string message{};
    std::optional<T> value{};
    std::vector<ValidationIssueDTO> validation_issues{};
    FreshnessState freshness{FreshnessState::Clean};

    [[nodiscard]] bool ok() const noexcept {
        return status == ApiStatus::Ok;
    }
};

class EngineSession {
public:
    EngineSession();
    explicit EngineSession(std::string project_name);
    ~EngineSession();

    EngineSession(const EngineSession&) = delete;
    EngineSession& operator=(const EngineSession&) = delete;
    EngineSession(EngineSession&&) noexcept;
    EngineSession& operator=(EngineSession&&) noexcept;

    ApiVoidResult new_project(std::string project_name);
    ApiResult<std::string> current_project() const;
    ApiVoidResult clear_project();
    ApiVoidResult load_project_json(std::string_view json);
    ApiVoidResult load_project_json_with_mode(std::string_view json, LoadMode mode);
    ApiResult<std::string> save_project_json() const;
    ApiResult<std::string> save_project_json_cached(bool allow_stale) const;
    ApiResult<std::string> get_engine_version() const;
    ApiResult<std::string> get_core_version() const;
    ApiResult<std::string> get_api_version() const;
    ApiResult<int> get_schema_version() const;
    ApiResult<int> detect_schema_version_from_json(std::string_view json) const;
    ApiResult<std::string> migrate_project_json(std::string_view json, int from_version, int to_version) const;
    ApiResult<MigrationReportDTO> get_last_migration_report() const;
    ApiResult<RepairReportDTO> get_last_repair_report() const;
    ApiResult<RepairReportDTO> repair_current_project(RepairOptionsDTO options = {});
    ApiVoidResult export_project_package(const std::string& path, PackageExportOptionsDTO options = {}) const;
    ApiVoidResult import_project_package(const std::string& path, LoadMode mode = LoadMode::Strict);
    ApiResult<RenderSceneDTO> get_render_scene() const;
    ApiVoidResult export_render_scene_json(const std::string& path) const;
    ApiVoidResult set_performance_profile(PerformanceProfile profile);
    ApiResult<PerformanceProfile> get_performance_profile() const;
    ApiVoidResult set_compute_mode(ComputeMode mode);
    ApiResult<ComputeMode> get_compute_mode() const;
    ApiResult<DirtySummaryDTO> get_dirty_summary() const;
    ApiResult<FreshnessSummaryDTO> get_freshness_summary() const;
    ApiVoidResult recompute_dirty();
    ApiVoidResult recompute_all_final();
    ApiVoidResult rebuild_spatial_index();
    ApiResult<std::uint64_t> spatial_index_version() const;
    ApiResult<SpatialIndexStatsDTO> spatial_index_stats() const;
    ApiResult<std::vector<ElementSummaryDTO>> query_rect(ElementIdDTO level_id, AABB2D bounds) const;

    ApiResult<ElementIdDTO> create_level(std::string name, double elevation_meters, double default_wall_height_meters);
    ApiResult<ElementIdDTO> create_wall(std::string name, Vec2 start, Vec2 end, double thickness_meters, double height_meters, std::uint64_t level_id = 0);
    ApiResult<ElementIdDTO> create_door(std::string name, std::uint64_t host_wall_id, double offset_meters, double width_meters, double height_meters);
    ApiResult<ElementIdDTO> create_window(
        std::string name,
        std::uint64_t host_wall_id,
        double offset_meters,
        double width_meters,
        double height_meters,
        double sill_height_meters
    );
    ApiResult<std::vector<RoomDTO>> detect_rooms();
    ApiVoidResult auto_join_walls();
    ApiVoidResult set_wall_axis(std::uint64_t wall_id, Vec2 start, Vec2 end);
    ApiVoidResult update_wall_properties(std::uint64_t wall_id, double thickness_meters, double height_meters, std::uint64_t wall_type_id = 0);
    ApiResult<ElementIdDTO> split_wall(std::uint64_t wall_id, double offset_meters);
    ApiVoidResult delete_element(std::uint64_t element_id);
    ApiVoidResult move_hosted_opening(std::uint64_t opening_id, double offset_meters);
    ApiVoidResult resize_door(std::uint64_t door_id, double width_meters, double height_meters);
    ApiVoidResult resize_window(std::uint64_t window_id, double width_meters, double height_meters, double sill_height_meters);
    ApiResult<ElementIdDTO> create_floor_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id);
    ApiResult<ElementIdDTO> create_ceiling_system_for_room(std::uint64_t room_id, std::uint64_t assembly_id, double height_offset_meters = 0.0);
    ApiResult<ElementIdDTO> create_roof(
        std::uint64_t level_id,
        std::vector<Vec2> boundary_polygon,
        ApiRoofType roof_type,
        double thickness_meters,
        std::uint64_t material_id = 0,
        std::uint64_t assembly_id = 0,
        std::optional<double> slope_degrees = std::nullopt,
        std::optional<double> overhang_meters = std::nullopt
    );
    ApiResult<ElementIdDTO> create_column(
        std::uint64_t level_id,
        Vec2 position,
        double width_meters,
        double depth_meters,
        double height_meters,
        std::uint64_t material_id
    );
    ApiResult<ElementIdDTO> create_beam(
        std::uint64_t level_id,
        Vec2 start,
        Vec2 end,
        double width_meters,
        double height_meters,
        std::uint64_t material_id
    );
    ApiResult<ElementIdDTO> create_stair(
        std::uint64_t base_level_id,
        std::uint64_t top_level_id,
        Vec2 start,
        Vec2 direction,
        double width_meters,
        double total_rise_meters,
        double total_run_meters,
        int riser_count,
        int tread_count,
        std::uint64_t material_id
    );
    ApiVoidResult undo();
    ApiVoidResult redo();

    ApiResult<std::vector<ElementSummaryDTO>> list_elements() const;
    ApiResult<ElementSummaryDTO> get_element_summary(std::uint64_t element_id) const;
    ApiResult<WallDTO> get_wall(std::uint64_t wall_id) const;
    ApiResult<std::vector<RoomDTO>> get_rooms() const;
    ApiResult<std::vector<RoomDTO>> get_cached_rooms() const;
    ApiResult<std::vector<WallScheduleDTO>> get_wall_schedule() const;
    ApiResult<std::vector<WallScheduleDTO>> get_cached_wall_schedule() const;
    ApiResult<std::vector<OpeningScheduleDTO>> get_opening_schedule() const;
    ApiResult<std::vector<RoomScheduleDTO>> get_room_schedule() const;
    ApiResult<std::vector<RoomScheduleDTO>> get_cached_room_schedule() const;
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> get_material_takeoff_summary() const;
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> get_cached_material_takeoff_summary() const;
    ApiResult<ValidationReportDTO> get_validation_report() const;
    ApiResult<ValidationReportDTO> get_cached_validation_report() const;
    ApiResult<DependencyGraphSummaryDTO> get_dependency_graph_summary() const;
    ApiResult<ScheduleSummaryDTO> generate_schedules() const;
    ApiResult<std::vector<HitTestCandidateDTO>> hit_test_point(HitTestPoint query) const;
    ApiResult<std::vector<SnapCandidateDTO>> get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap = true) const;
    ApiResult<std::vector<SnapCandidateDTO>> get_snap_candidates(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const;
    ApiResult<SnapCandidateDTO> best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, bool include_grid_snap = true) const;
    ApiResult<SnapCandidateDTO> best_snap(ElementIdDTO level_id, Vec2 point, double tolerance_meters, SnapOptionsDTO options) const;
    ApiResult<std::vector<WallFreeIntervalDTO>> compute_wall_free_intervals(std::uint64_t wall_id, double requested_width_meters, double clearance_meters) const;
    ApiResult<WallHostPlacementDTO> find_wall_host_at_point(
        ElementIdDTO level_id,
        Vec2 point,
        double tolerance_meters,
        double requested_width_meters = 0.0,
        double clearance_meters = 0.0
    ) const;

    ApiResult<std::vector<WallScheduleDTO>> generate_wall_schedule();
    ApiResult<std::vector<RoomScheduleDTO>> generate_room_schedule();
    ApiResult<std::vector<MaterialTakeoffSummaryDTO>> generate_material_takeoff_summary();
    ApiResult<ValidationReportDTO> generate_validation_report();

    ApiVoidResult export_svg(const std::string& path) const;
    ApiVoidResult export_svg_cached(const std::string& path, bool allow_stale) const;
    ApiVoidResult export_obj(const std::string& path) const;
    ApiVoidResult export_obj_cached(const std::string& path, bool allow_stale) const;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

ApiResult<std::unique_ptr<EngineSession>> create_session(std::string project_name = "API Project");

} // namespace tbe::api
