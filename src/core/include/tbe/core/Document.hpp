#pragma once

#include "tbe/core/Element.hpp"

#include <filesystem>
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

    ElementId create_material(
        std::string name,
        MaterialCategory category,
        std::optional<double> density_kg_per_m3 = std::nullopt,
        std::optional<double> unit_cost = std::nullopt,
        std::map<std::string, std::string> metadata = {}
    );
    [[nodiscard]] const MaterialDefinition* get_material(ElementId material_id) const noexcept;
    void update_material(MaterialDefinition material);
    ElementId create_wall_type(std::string name, std::vector<WallAssemblyLayer> layers);
    [[nodiscard]] const WallTypeData* get_wall_type(ElementId wall_type_id) const noexcept;
    void update_wall_type(WallTypeData wall_type);
    ElementId create_layered_assembly(LayeredAssemblyKind kind, std::string name, std::vector<WallAssemblyLayer> layers);
    [[nodiscard]] const LayeredAssemblyData* get_layered_assembly(ElementId assembly_id) const noexcept;
    void update_layered_assembly(LayeredAssemblyData assembly);
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
        std::optional<double> overhang_meters = std::nullopt
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
        ElementId material_id
    );
    ElementId create_floor_system_for_room(ElementId room_id, ElementId assembly_id);
    ElementId create_ceiling_system_for_room(ElementId room_id, ElementId assembly_id, double height_offset_meters = 0.0);
    std::vector<ElementId> generate_floor_systems_for_all_rooms(ElementId default_assembly_id);
    std::vector<ElementId> generate_ceiling_systems_for_all_rooms(ElementId default_assembly_id, double height_offset_meters = 0.0);
    void update_floor_system_from_room(ElementId room_id);
    void update_ceiling_system_from_room(ElementId room_id);
    void set_wall_type(ElementId wall_id, ElementId wall_type_id);
    void set_wall_axis(ElementId wall_id, Line2 axis);
    ElementId split_wall(ElementId wall_id, double offset_meters);
    void delete_element(ElementId element_id);
    void move_hosted_opening(ElementId opening_id, double offset_meters);
    void resize_door(ElementId door_id, double width_meters, double height_meters);
    void resize_window(ElementId window_id, double width_meters, double height_meters, double sill_height_meters);

    void auto_join_walls();
    std::vector<ElementId> detect_rooms();
    void regenerate_dirty_geometry();
    [[nodiscard]] DependencyGraph build_dependency_graph() const;
    [[nodiscard]] const DependencyGraph& dependency_graph() const;
    [[nodiscard]] Revision dependency_graph_version() const noexcept;
    void mark_rooms_dirty_for_wall(ElementId wall_id);
    std::vector<ElementId> recompute_dirty_rooms();
    std::vector<ElementId> recompute_all_rooms();
    [[nodiscard]] const std::vector<ElementId>& dirty_room_ids() const noexcept;
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
    [[nodiscard]] std::string layered_assembly_name(ElementId assembly_id) const;
    void add_opening_to_wall(ElementId host_wall_id, HostedOpening opening);
    void validate_opening(const WallData& wall, double offset_meters, double width_meters, double height_meters) const;
    void validate_wall_axis(Line2 axis, double thickness_meters, double height_meters) const;
    void validate_wall_openings(const WallData& wall, std::optional<ElementId> ignored_opening_id = std::nullopt) const;
    void update_wall_opening(ElementId host_wall_id, const HostedOpening& opening);
    void remove_hosted_opening(ElementId host_wall_id, ElementId opening_id);
    void touch_related_rooms(ElementId wall_id) noexcept;
    void refresh_dependencies_for_wall(ElementId wall_id);
    void add_issue(ValidationReport& report, ValidationSeverity severity, ValidationIssueCode code, ElementId element_id, std::string message) const;
    void invalidate_dependency_graph_cache() noexcept;
    [[nodiscard]] std::vector<ElementId> detect_rooms_for_levels(const std::vector<ElementId>& level_ids);
    void mark_wall_dirty(Element& wall) noexcept;
    void replace_state(std::string name, std::vector<Element> elements, ElementId next_id);

    std::string name_;
    std::vector<Element> elements_;
    ElementId next_id_{1};
    std::map<ElementId, MaterialDefinition> materials_{};
    std::map<ElementId, WallTypeData> wall_types_{};
    std::map<ElementId, LayeredAssemblyData> layered_assemblies_{};
    std::map<ElementId, FloorSystemData> floor_systems_{};
    std::map<ElementId, CeilingSystemData> ceiling_systems_{};
    std::vector<ElementId> dirty_room_ids_{};
    mutable DependencyGraph dependency_graph_cache_{};
    mutable bool dependency_graph_dirty_{true};
    mutable Revision dependency_graph_version_{};
};

} // namespace tbe::core
