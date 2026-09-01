#pragma once

#include "tbe/core/Element.hpp"

#include <filesystem>
#include <set>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace tbe::core {

enum class GeometryDetail {
    // Fast analytical envelope used by interactive viewport rendering.
    Envelope,
    // Per-layer mesh used by core-level authoring/tests and explicit detail
    // exports. Quantities never require this mesh: assemblies are semantic.
    Layered,
};

class Document {
public:
    explicit Document(std::string name);

    [[nodiscard]] std::string_view name() const noexcept;
    void rename(std::string name);
    [[nodiscard]] const UnitSettings& unit_settings() const noexcept;
    void set_unit_settings(UnitSettings settings);

    ElementId create_material(
        std::string name,
        MaterialCategory category,
        std::optional<double> density_kg_per_m3 = std::nullopt,
        std::optional<double> unit_cost = std::nullopt,
        std::map<std::string, std::string> metadata = {},
        std::string display_color = "#B0B7C3"
    );
    [[nodiscard]] const MaterialDefinition* get_material(ElementId material_id) const noexcept;
    void update_material(MaterialDefinition material);
    ElementId create_wall_type(std::string name, std::vector<WallAssemblyLayer> layers, WallTypeCategory category = WallTypeCategory::Generic);
    [[nodiscard]] const WallTypeData* get_wall_type(ElementId wall_type_id) const noexcept;
    void update_wall_type(WallTypeData wall_type);
    ElementId create_layered_assembly(LayeredAssemblyKind kind, std::string name, std::vector<WallAssemblyLayer> layers);
    [[nodiscard]] const LayeredAssemblyData* get_layered_assembly(ElementId assembly_id) const noexcept;
    void update_layered_assembly(LayeredAssemblyData assembly);
    ElementId create_level(std::string name, double elevation_meters, double default_wall_height_meters);
    ElementId create_wall(std::string name, Line2 axis, double thickness_meters, double height_meters, ElementId level_id = 0, ElementId assembly_id = 0);
    ElementId create_door(std::string name, ElementId host_wall_id, double offset_meters, double width_meters, double height_meters);
    ElementId create_window(
        std::string name,
        ElementId host_wall_id,
        double offset_meters,
        double width_meters,
        double height_meters,
        double sill_height_meters
    );
    ElementId create_slab(
        ElementId level_id,
        std::vector<Point2> boundary_polygon,
        double thickness_meters,
        ElementId material_id = 0,
        ElementId assembly_id = 0,
        double elevation_offset_meters = 0.0
    );
    ElementId create_roof(
        ElementId level_id,
        std::vector<Point2> boundary_polygon,
        RoofType roof_type,
        double thickness_meters,
        ElementId material_id = 0,
        ElementId assembly_id = 0,
        std::optional<double> slope_degrees = std::nullopt,
        std::optional<double> overhang_meters = std::nullopt,
        std::vector<ElementId> source_wall_ids = {}
    );
    ElementId create_column(
        ElementId level_id,
        Point2 position,
        double width_meters,
        double depth_meters,
        double height_meters,
        ElementId material_id
    );
    ElementId create_beam(
        ElementId level_id,
        Point2 start,
        Point2 end,
        double width_meters,
        double height_meters,
        ElementId material_id
    );
    ElementId create_stair(
        ElementId base_level_id,
        ElementId top_level_id,
        Point2 start,
        Point2 direction,
        double width_meters,
        double total_rise_meters,
        double total_run_meters,
        int riser_count,
        int tread_count,
        ElementId material_id,
        ElementId assembly_id = 0
    );
    /// Adds a lightweight box for a physical IFC product whose exact profile
    /// is not supported by the analytical importer.
    ElementId create_proxy(
        std::string name,
        ElementId level_id,
        Point2 position,
        double width_meters,
        double depth_meters,
        double height_meters
    );
    ElementId create_floor_system_for_room(ElementId room_id, ElementId assembly_id);
    ElementId create_ceiling_system_for_room(ElementId room_id, ElementId assembly_id, double height_offset_meters = 0.0);
    std::vector<ElementId> generate_floor_systems_for_all_rooms(ElementId default_assembly_id);
    std::vector<ElementId> generate_ceiling_systems_for_all_rooms(ElementId default_assembly_id, double height_offset_meters = 0.0);
    ElementId create_floor_system_from_profile(
        ElementId level_id,
        std::vector<Point2> boundary_polygon,
        ElementId assembly_id,
        double thickness_meters = 0.18
    );
    ElementId create_ceiling_system_from_profile(
        ElementId level_id,
        std::vector<Point2> boundary_polygon,
        ElementId assembly_id,
        double height_offset_meters = 0.0
    );
    void update_floor_system_from_room(ElementId room_id);
    void update_ceiling_system_from_room(ElementId room_id);
    void update_level(ElementId level_id, std::optional<std::string> name, std::optional<double> elevation_meters, std::optional<double> default_wall_height_meters);
    void move_level_elevation(ElementId level_id, double elevation_meters);
    void set_wall_level_constraints(
        ElementId wall_id,
        ElementId base_level_id,
        ElementId top_level_id,
        double base_offset_meters,
        double top_offset_meters,
        WallHeightMode height_mode
    );
    void set_opening_level_lock(ElementId opening_id, bool locked);
    void set_opening_level(ElementId opening_id, ElementId level_id);
    void set_opening_level_constraint(ElementId opening_id, ElementId level_id, double level_offset_meters);
    std::vector<ElementId> create_elements_from_profile(const ProfileDraft& draft);
    void set_wall_type(ElementId wall_id, ElementId wall_type_id);
    /// Applies a canonical compound assembly to a supported element. Legacy
    /// wall types remain readable, but new authoring should use this API.
    void set_element_assembly(ElementId element_id, ElementId assembly_id);
    void update_roof_properties(ElementId roof_id, RoofType roof_type, std::optional<double> slope_degrees, std::optional<double> overhang_meters);
    /// Creates/removes an explicit structural void in a wall. No destructive
    /// boolean is performed; the host wall owns the cut profile semantically.
    void set_structural_wall_cut(ElementId wall_id, ElementId cutter_id, bool enabled, double clearance_meters = 0.0);
    /// Stores an explicit analytical beam-to-column join. Geometry remains
    /// separate and cheap to regenerate.
    void set_beam_column_join(ElementId beam_id, ElementId column_id, bool enabled);
    void set_wall_properties(ElementId wall_id, double thickness_meters, double height_meters, ElementId wall_type_id = 0);
    void set_wall_axis(ElementId wall_id, Line2 axis);
    /// Applies an axis edit transactionally. A rigid body move carries only
    /// immediate joined endpoints; an endpoint-handle edit stays local.
    void set_wall_axis_with_joins(ElementId wall_id, Line2 axis);
    /// Atomically trims or extends the explicitly chosen endpoint of two
    /// same-storey wall axes to their infinite-line intersection.
    void trim_extend_walls(
        ElementId first_wall_id,
        bool first_uses_start,
        ElementId second_wall_id,
        bool second_uses_start
    );
    ElementId split_wall(ElementId wall_id, double offset_meters);
    void delete_element(ElementId element_id);
    void move_hosted_opening(ElementId opening_id, double offset_meters);
    void resize_door(ElementId door_id, double width_meters, double height_meters);
    void resize_window(ElementId window_id, double width_meters, double height_meters, double sill_height_meters);
    /// Validates and applies all horizontal/vertical opening edits as one
    /// document mutation. The host wall is updated only after the complete
    /// candidate opening has passed validation.
    void update_hosted_opening(
        ElementId opening_id,
        double offset_meters,
        double width_meters,
        double height_meters,
        double sill_height_meters
    );

    void auto_join_walls();
    /// Rebuilds deterministic host relations: beam-to-column joins, safe
    /// column-to-wall cuts and stair openings in matching floor/ceiling systems.
    void auto_join_structural_elements();
    [[nodiscard]] const std::vector<HostRelation>& host_relations() const noexcept;
    /// Bulk import/template construction can defer expensive join discovery
    /// until a deliberate authoring operation asks for it.
    void set_automatic_wall_join_enabled(bool enabled) noexcept;
    std::vector<ElementId> detect_rooms();
    void regenerate_dirty_geometry(GeometryDetail detail = GeometryDetail::Layered);
    [[nodiscard]] DependencyGraph build_dependency_graph() const;
    [[nodiscard]] const DependencyGraph& dependency_graph() const;
    [[nodiscard]] Revision dependency_graph_version() const noexcept;
    void mark_rooms_dirty_for_wall(ElementId wall_id);
    std::vector<ElementId> recompute_dirty_rooms();
    std::vector<ElementId> recompute_all_rooms();
    [[nodiscard]] const std::vector<ElementId>& dirty_room_ids() const noexcept;
    /// Drops only deferred room-discovery requests. Existing rooms remain
    /// intact; final compute can still explicitly recompute all rooms.
    void clear_dirty_room_requests() noexcept;
    [[nodiscard]] ValidationReport validate_document() const;
    [[nodiscard]] std::vector<WallRoomAdjacency> wall_room_adjacencies() const;
    [[nodiscard]] std::vector<WallScheduleRow> generate_wall_schedule() const;
    [[nodiscard]] std::vector<OpeningScheduleRow> generate_opening_schedule() const;
    [[nodiscard]] std::vector<RoomScheduleRow> generate_room_schedule() const;
    [[nodiscard]] std::vector<SlabScheduleRow> generate_slab_schedule() const;
    [[nodiscard]] std::vector<RoofScheduleRow> generate_roof_schedule() const;
    [[nodiscard]] std::vector<ColumnScheduleRow> generate_column_schedule() const;
    [[nodiscard]] std::vector<BeamScheduleRow> generate_beam_schedule() const;
    [[nodiscard]] std::vector<StairScheduleRow> generate_stair_schedule() const;
    [[nodiscard]] std::vector<FloorFinishScheduleRow> generate_floor_finish_schedule() const;
    [[nodiscard]] std::vector<CeilingScheduleRow> generate_ceiling_schedule() const;
    [[nodiscard]] std::vector<MaterialTakeoffRow> generate_material_takeoff() const;
    void export_floorplan_svg(const std::filesystem::path& path) const;
    void export_mesh_obj(const std::filesystem::path& path) const;
    void export_debug_report_json(const std::filesystem::path& path) const;

    [[nodiscard]] std::string to_json() const;
    [[nodiscard]] static Document from_json(std::string_view json);

    [[nodiscard]] const std::vector<Element>& elements() const noexcept;
    [[nodiscard]] const std::map<ElementId, MaterialDefinition>& materials() const noexcept;
    [[nodiscard]] const std::map<ElementId, WallTypeData>& wall_types() const noexcept;
    [[nodiscard]] const std::map<ElementId, LayeredAssemblyData>& layered_assemblies() const noexcept;
    [[nodiscard]] const std::map<ElementId, FloorSystemData>& floor_systems() const noexcept;
    [[nodiscard]] const std::map<ElementId, CeilingSystemData>& ceiling_systems() const noexcept;
    [[nodiscard]] std::optional<Element> find(ElementId id) const;
    [[nodiscard]] const Element* find_ptr(ElementId id) const noexcept;
    [[nodiscard]] Element* find_ptr(ElementId id) noexcept;
    void restore_element(Element element);
    void remove_element(ElementId id);

private:
    [[nodiscard]] ElementId allocate_id() noexcept;
    [[nodiscard]] Element& require_level(ElementId id);
    [[nodiscard]] Element& require_wall(ElementId id);
    [[nodiscard]] const Element& require_wall(ElementId id) const;
    [[nodiscard]] Element& require_door(ElementId id);
    [[nodiscard]] Element& require_window(ElementId id);
    [[nodiscard]] const Element* find_host_wall_for_opening(ElementId opening_id) const noexcept;
    [[nodiscard]] const Element& require_room(ElementId id) const;
    [[nodiscard]] Element& require_room(ElementId id);
    [[nodiscard]] double wall_thickness(const WallData& wall) const;
    [[nodiscard]] std::string wall_type_name(ElementId wall_type_id) const;
    [[nodiscard]] double total_wall_type_thickness(const WallTypeData& wall_type) const;
    [[nodiscard]] bool wall_type_uses_glass(const WallTypeData& wall_type) const;
    [[nodiscard]] bool layered_assembly_uses_glass(const LayeredAssemblyData& assembly) const;
    [[nodiscard]] bool wall_uses_glass(const WallData& wall) const;
    [[nodiscard]] std::string layered_assembly_name(ElementId assembly_id) const;
    [[nodiscard]] double level_elevation(ElementId level_id) const;
    [[nodiscard]] double resolved_wall_base_elevation(const WallData& wall) const;
    [[nodiscard]] double resolved_wall_height(const WallData& wall) const;
    [[nodiscard]] double resolved_roof_surface_area(const RoofData& roof) const;
    [[nodiscard]] std::vector<Point2> normalized_profile_polygon(const ProfileDraft& draft) const;
    void add_opening_to_wall(ElementId host_wall_id, HostedOpening opening);
    void validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const;
    void validate_wall_axis(Line2 axis, double thickness_meters, double height_meters) const;
    void validate_wall_openings(const WallData& wall, std::optional<ElementId> ignored_opening_id = std::nullopt) const;
    void update_wall_opening(ElementId host_wall_id, const HostedOpening& opening);
    void sync_opening_level_constraint(ElementId opening_id);
    void remove_hosted_opening(ElementId host_wall_id, ElementId opening_id);
    void touch_related_rooms(ElementId wall_id) noexcept;
    void refresh_dependencies_for_wall(ElementId wall_id);
    void add_issue(ValidationReport& report, ValidationSeverity severity, ValidationIssueCode code, ElementId element_id, std::string message) const;
    void invalidate_dependency_graph_cache() noexcept;
    [[nodiscard]] std::vector<ElementId> detect_rooms_for_levels(const std::vector<ElementId>& level_ids);
    void mark_wall_dirty(Element& wall) noexcept;
    void replace_state(std::string name, std::vector<Element> elements, ElementId next_id);

    std::string name_;
    UnitSettings unit_settings_{};
    std::vector<Element> elements_;
    ElementId next_id_{1};
    std::map<ElementId, MaterialDefinition> materials_{};
    std::map<ElementId, WallTypeData> wall_types_{};
    std::map<ElementId, LayeredAssemblyData> layered_assemblies_{};
    std::map<ElementId, FloorSystemData> floor_systems_{};
    std::map<ElementId, CeilingSystemData> ceiling_systems_{};
    std::vector<std::pair<ElementId, ElementId>> beam_column_joins_{};
    std::vector<HostRelation> host_relations_{};
    // An explicit "remove wall cut" is a user decision, not an invitation
    // for the automatic resolver to recreate the same void on the next edit.
    std::set<std::pair<ElementId, ElementId>> disabled_auto_structural_cuts_{};
    std::vector<ElementId> dirty_room_ids_{};
    // Levels whose room topology changed. This lets interactive snapshots
    // recompute only the edited storey instead of scanning the whole model.
    std::vector<ElementId> dirty_room_level_ids_{};
    bool automatic_wall_join_enabled_{true};
    // Structural resolution can create semantic wall cuts. Those cuts mark a
    // wall dirty, but must never recursively start a second resolver pass.
    bool resolving_structural_relations_{false};
    mutable DependencyGraph dependency_graph_cache_{};
    mutable bool dependency_graph_dirty_{true};
    mutable Revision dependency_graph_version_{};
};

} // namespace tbe::core
