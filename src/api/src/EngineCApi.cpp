#include "tbe/api/EngineCApi.h"

#include "tbe/api/EngineApi.hpp"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

struct TbeEngineHandle {
    std::unique_ptr<tbe::api::EngineSession> session{};
    std::string last_error{};
};

namespace {

TbeApiStatusCode to_c_status(tbe::api::ApiStatus status) {
    switch (status) {
    case tbe::api::ApiStatus::Ok: return TBE_API_OK;
    case tbe::api::ApiStatus::InvalidArgument: return TBE_API_INVALID_ARGUMENT;
    case tbe::api::ApiStatus::NotFound: return TBE_API_NOT_FOUND;
    case tbe::api::ApiStatus::ValidationError: return TBE_API_VALIDATION_ERROR;
    case tbe::api::ApiStatus::InternalError: return TBE_API_INTERNAL_ERROR;
    }
    return TBE_API_INTERNAL_ERROR;
}

template <typename Result>
TbeApiStatusCode apply_result(TbeEngineHandle* handle, const Result& result) {
    if (handle == nullptr) {
        return TBE_API_INVALID_ARGUMENT;
    }
    handle->last_error = result.message;
    return to_c_status(result.status);
}

TbeApiStatusCode null_handle_error(TbeEngineHandle* handle) {
    if (handle != nullptr) {
        handle->last_error = "engine handle is null";
    }
    return TBE_API_INVALID_ARGUMENT;
}

TbeApiStatusCode invalid_argument_error(TbeEngineHandle* handle, const char* message) {
    if (handle != nullptr) {
        handle->last_error = message == nullptr ? "invalid argument" : message;
    }
    return TBE_API_INVALID_ARGUMENT;
}

bool is_valid_performance_profile(int value) {
    return value >= static_cast<int>(tbe::api::PerformanceProfile::BatterySaver) &&
        value <= static_cast<int>(tbe::api::PerformanceProfile::Performance);
}

bool is_valid_compute_mode(int value) {
    return value >= static_cast<int>(tbe::api::ComputeMode::InteractivePreview) &&
        value <= static_cast<int>(tbe::api::ComputeMode::FinalExact);
}

TbeApiStatusCode copy_string_result(TbeEngineHandle* handle, const tbe::api::ApiResult<std::string>& result, char** out_value) {
    if (!result.ok() || !result.value.has_value()) {
        return apply_result(handle, result);
    }
    auto* buffer = static_cast<char*>(std::malloc(result.value->size() + 1));
    if (buffer == nullptr) {
        handle->last_error = "failed to allocate string buffer";
        return TBE_API_INTERNAL_ERROR;
    }
    std::memcpy(buffer, result.value->c_str(), result.value->size() + 1);
    *out_value = buffer;
    handle->last_error.clear();
    return TBE_API_OK;
}

void copy_bim_cache_stats(
    const tbe::api::BimCacheStatsDTO& source,
    TbeBimCacheStats* target
) {
    target->format_version = source.format_version;
    target->source_valid = source.source_valid ? 1 : 0;
    target->source_object_count = static_cast<uint64_t>(source.source_object_count);
    target->source_triangle_count = static_cast<uint64_t>(source.source_triangle_count);
    target->chunk_count = static_cast<uint64_t>(source.chunk_count);
    target->primitive_count = static_cast<uint64_t>(source.primitive_count);
    target->bvh_node_count = static_cast<uint64_t>(source.bvh_node_count);
    target->byte_size = static_cast<uint64_t>(source.byte_size);
}

} // namespace

extern "C" {

TbeEngineHandle* tbe_engine_create(void) {
    auto created = tbe::api::create_session("C API Project");
    if (!created.ok() || !created.value.has_value()) {
        return nullptr;
    }
    auto* handle = new TbeEngineHandle{};
    handle->session = std::move(*created.value);
    return handle;
}

void tbe_engine_destroy(TbeEngineHandle* handle) {
    delete handle;
}

TbeApiStatusCode tbe_project_new(TbeEngineHandle* handle, const char* project_name) {
    if (handle == nullptr || handle->session == nullptr || project_name == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->new_project(project_name));
}

TbeApiStatusCode tbe_project_load_json(TbeEngineHandle* handle, const char* json) {
    if (handle == nullptr || handle->session == nullptr || json == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->load_project_json(json));
}

TbeApiStatusCode tbe_project_load_json_with_mode(TbeEngineHandle* handle, const char* json, int load_mode) {
    if (handle == nullptr || handle->session == nullptr || json == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->load_project_json_with_mode(json, static_cast<tbe::api::LoadMode>(load_mode)));
}

TbeApiStatusCode tbe_project_save_json(TbeEngineHandle* handle, char** out_json) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->save_project_json();
    if (!result.ok() || !result.value.has_value()) {
        return apply_result(handle, result);
    }
    const auto& json = *result.value;
    auto* buffer = static_cast<char*>(std::malloc(json.size() + 1));
    if (buffer == nullptr) {
        handle->last_error = "failed to allocate JSON buffer";
        return TBE_API_INTERNAL_ERROR;
    }
    std::memcpy(buffer, json.c_str(), json.size() + 1);
    *out_json = buffer;
    handle->last_error.clear();
    return TBE_API_OK;
}

TbeApiStatusCode tbe_get_engine_version(TbeEngineHandle* handle, char** out_version) {
    if (handle == nullptr || handle->session == nullptr || out_version == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(handle, handle->session->get_engine_version(), out_version);
}

TbeApiStatusCode tbe_get_core_version(TbeEngineHandle* handle, char** out_version) {
    if (handle == nullptr || handle->session == nullptr || out_version == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(handle, handle->session->get_core_version(), out_version);
}

TbeApiStatusCode tbe_get_api_version(TbeEngineHandle* handle, char** out_version) {
    if (handle == nullptr || handle->session == nullptr || out_version == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(handle, handle->session->get_api_version(), out_version);
}

TbeApiStatusCode tbe_get_schema_version(TbeEngineHandle* handle, int* out_version) {
    if (handle == nullptr || handle->session == nullptr || out_version == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->get_schema_version();
    if (result.ok() && result.value.has_value()) {
        *out_version = *result.value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_detect_schema_version_from_json(TbeEngineHandle* handle, const char* json, int* out_version) {
    if (handle == nullptr || handle->session == nullptr || json == nullptr || out_version == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->detect_schema_version_from_json(json);
    if (result.ok() && result.value.has_value()) {
        *out_version = *result.value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_migrate_project_json(TbeEngineHandle* handle, const char* json, int from_version, int to_version, char** out_json) {
    if (handle == nullptr || handle->session == nullptr || json == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->migrate_project_json(json, from_version, to_version);
    if (!result.ok() || !result.value.has_value()) {
        return apply_result(handle, result);
    }
    auto* buffer = static_cast<char*>(std::malloc(result.value->size() + 1));
    if (buffer == nullptr) {
        handle->last_error = "failed to allocate migrated JSON buffer";
        return TBE_API_INTERNAL_ERROR;
    }
    std::memcpy(buffer, result.value->c_str(), result.value->size() + 1);
    *out_json = buffer;
    handle->last_error.clear();
    return TBE_API_OK;
}

TbeApiStatusCode tbe_get_last_migration_report(TbeEngineHandle* handle, TbeMigrationSummary* out_summary) {
    if (handle == nullptr || handle->session == nullptr || out_summary == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->get_last_migration_report();
    if (result.ok() && result.value.has_value()) {
        out_summary->from_version = result.value->from_version;
        out_summary->to_version = result.value->to_version;
        out_summary->migrated_count = result.value->migrated_count;
        out_summary->warning_count = result.value->warning_count;
        out_summary->error_count = result.value->error_count;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_get_last_repair_report(TbeEngineHandle* handle, TbeRepairSummary* out_summary) {
    if (handle == nullptr || handle->session == nullptr || out_summary == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->get_last_repair_report();
    if (result.ok() && result.value.has_value()) {
        out_summary->repaired_count = result.value->repaired_count;
        out_summary->warning_count = result.value->warning_count;
        out_summary->error_count = result.value->error_count;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_repair_current_project(TbeEngineHandle* handle, TbeRepairSummary* out_summary) {
    if (handle == nullptr || handle->session == nullptr || out_summary == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->repair_current_project();
    if (result.ok() && result.value.has_value()) {
        out_summary->repaired_count = result.value->repaired_count;
        out_summary->warning_count = result.value->warning_count;
        out_summary->error_count = result.value->error_count;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_export_project_package(TbeEngineHandle* handle, const char* path) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->export_project_package(path));
}

TbeApiStatusCode tbe_import_project_package(TbeEngineHandle* handle, const char* path, int load_mode) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->import_project_package(path, static_cast<tbe::api::LoadMode>(load_mode)));
}

TbeApiStatusCode tbe_export_render_scene_json(TbeEngineHandle* handle, const char* path) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->export_render_scene_json(path));
}

TbeApiStatusCode tbe_create_level(
    TbeEngineHandle* handle,
    const char* name,
    double elevation_meters,
    double default_wall_height_meters,
    uint64_t* out_level_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_level_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_level(name, elevation_meters, default_wall_height_meters);
    if (result.ok() && result.value.has_value()) {
        *out_level_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_update_level(
    TbeEngineHandle* handle,
    uint64_t level_id,
    const char* name,
    double elevation_meters,
    double default_wall_height_meters,
    int update_elevation,
    int update_default_wall_height
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->update_level(
        level_id,
        name == nullptr ? std::nullopt : std::optional<std::string>(name),
        update_elevation != 0 ? std::optional<double>(elevation_meters) : std::nullopt,
        update_default_wall_height != 0 ? std::optional<double>(default_wall_height_meters) : std::nullopt
    ));
}

TbeApiStatusCode tbe_move_level_elevation(TbeEngineHandle* handle, uint64_t level_id, double elevation_meters) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->move_level_elevation(level_id, elevation_meters));
}

TbeApiStatusCode tbe_create_wall(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t level_id,
    TbeVec2 start,
    TbeVec2 end,
    double thickness_meters,
    double height_meters,
    uint64_t* out_wall_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_wall_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_wall(
        name,
        tbe::api::Vec2{.x = start.x, .y = start.y},
        tbe::api::Vec2{.x = end.x, .y = end.y},
        thickness_meters,
        height_meters,
        level_id
    );
    if (result.ok() && result.value.has_value()) {
        *out_wall_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_curved_wall(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t level_id,
    TbeVec2 start,
    TbeVec2 end,
    TbeVec2 center,
    double radius_meters,
    double start_angle_radians,
    double sweep_radians,
    double thickness_meters,
    double height_meters,
    uint64_t* out_wall_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_wall_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_curved_wall(
        name,
        tbe::api::Vec2{.x = start.x, .y = start.y},
        tbe::api::Vec2{.x = end.x, .y = end.y},
        tbe::api::Vec2{.x = center.x, .y = center.y},
        radius_meters,
        start_angle_radians,
        sweep_radians,
        thickness_meters,
        height_meters,
        level_id
    );
    if (result.ok() && result.value.has_value()) {
        *out_wall_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_set_wall_type(
    TbeEngineHandle* handle,
    uint64_t wall_id,
    uint64_t wall_type_id
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_wall_type(wall_id, wall_type_id));
}

TbeApiStatusCode tbe_create_wall_type(
    TbeEngineHandle* handle,
    int category,
    const char* name,
    const uint64_t* material_ids,
    const double* thickness_meters,
    const int* functions,
    const int* priorities,
    const int* structural,
    const int* sides,
    const int* wraps_openings,
    const int* wraps_ends,
    size_t layer_count,
    int core_start_layer,
    int core_end_layer,
    uint64_t* out_wall_type_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr ||
        out_wall_type_id == nullptr || layer_count == 0 ||
        material_ids == nullptr || thickness_meters == nullptr ||
        functions == nullptr || priorities == nullptr || structural == nullptr ||
        sides == nullptr || wraps_openings == nullptr || wraps_ends == nullptr) {
        return null_handle_error(handle);
    }
    if (category < 0 || category > 2) {
        handle->last_error = "wall type category is invalid";
        return TBE_API_INVALID_ARGUMENT;
    }

    std::vector<tbe::api::AssemblyLayerDTO> layers;
    layers.reserve(layer_count);
    for (size_t index = 0; index < layer_count; ++index) {
        layers.push_back(tbe::api::AssemblyLayerDTO{
            .material_id = tbe::api::ElementIdDTO{material_ids[index]},
            .thickness_meters = thickness_meters[index],
            .function = static_cast<tbe::api::ApiWallLayerFunction>(functions[index]),
            .priority = priorities[index],
            .structural = structural[index] != 0,
            .side = static_cast<tbe::api::ApiWallLayerSide>(sides[index]),
            .wraps_openings = wraps_openings[index] != 0,
            .wraps_ends = wraps_ends[index] != 0,
        });
    }
    const auto result = handle->session->create_wall_type(
        static_cast<tbe::api::ApiWallTypeCategory>(category),
        name,
        std::move(layers),
        core_start_layer,
        core_end_layer
    );
    if (result.ok() && result.value.has_value()) {
        *out_wall_type_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_upsert_wall_type_for_wall(
    TbeEngineHandle* handle,
    uint64_t wall_id,
    int category,
    const char* name,
    const uint64_t* material_ids,
    const double* thickness_meters,
    const int* functions,
    const int* priorities,
    const int* structural,
    const int* sides,
    const int* wraps_openings,
    const int* wraps_ends,
    size_t layer_count,
    int core_start_layer,
    int core_end_layer,
    uint64_t* out_wall_type_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr ||
        out_wall_type_id == nullptr || layer_count == 0 ||
        material_ids == nullptr || thickness_meters == nullptr ||
        functions == nullptr || priorities == nullptr || structural == nullptr ||
        sides == nullptr || wraps_openings == nullptr || wraps_ends == nullptr) {
        return null_handle_error(handle);
    }
    if (category < 0 || category > 2) {
        handle->last_error = "wall type category is invalid";
        return TBE_API_INVALID_ARGUMENT;
    }

    std::vector<tbe::api::AssemblyLayerDTO> layers;
    layers.reserve(layer_count);
    for (size_t index = 0; index < layer_count; ++index) {
        layers.push_back(tbe::api::AssemblyLayerDTO{
            .material_id = tbe::api::ElementIdDTO{material_ids[index]},
            .thickness_meters = thickness_meters[index],
            .function = static_cast<tbe::api::ApiWallLayerFunction>(functions[index]),
            .priority = priorities[index],
            .structural = structural[index] != 0,
            .side = static_cast<tbe::api::ApiWallLayerSide>(sides[index]),
            .wraps_openings = wraps_openings[index] != 0,
            .wraps_ends = wraps_ends[index] != 0,
        });
    }
    const auto result = handle->session->upsert_wall_type_for_wall(
        wall_id,
        static_cast<tbe::api::ApiWallTypeCategory>(category),
        name,
        std::move(layers),
        core_start_layer,
        core_end_layer);
    if (result.ok() && result.value.has_value()) {
        *out_wall_type_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_set_wall_level_constraints(
    TbeEngineHandle* handle,
    uint64_t wall_id,
    uint64_t base_level_id,
    uint64_t top_level_id,
    double base_offset_meters,
    double top_offset_meters,
    int height_mode
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_wall_level_constraints(
        wall_id,
        base_level_id,
        top_level_id,
        base_offset_meters,
        top_offset_meters,
        static_cast<tbe::api::ApiWallHeightMode>(height_mode)
    ));
}

TbeApiStatusCode tbe_set_wall_axis(
    TbeEngineHandle* handle,
    uint64_t wall_id,
    TbeVec2 start,
    TbeVec2 end
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_wall_axis(
        wall_id,
        tbe::api::Vec2{.x = start.x, .y = start.y},
        tbe::api::Vec2{.x = end.x, .y = end.y}
    ));
}

TbeApiStatusCode tbe_auto_join_walls(TbeEngineHandle* handle) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->auto_join_walls());
}

TbeApiStatusCode tbe_trim_extend_walls(
    TbeEngineHandle* handle,
    uint64_t first_wall_id,
    int first_uses_start,
    uint64_t second_wall_id,
    int second_uses_start
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->trim_extend_walls(
        first_wall_id,
        first_uses_start != 0,
        second_wall_id,
        second_uses_start != 0
    ));
}

TbeApiStatusCode tbe_set_element_assembly(TbeEngineHandle* handle, uint64_t element_id, uint64_t assembly_id) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->set_element_assembly(element_id, assembly_id));
}

TbeApiStatusCode tbe_set_element_family_reference(
    TbeEngineHandle* handle,
    uint64_t element_id,
    const char* family_asset_id,
    const char* family_name,
    const char* family_type_id,
    const char* family_type_name,
    const char* family_category,
    const char* family_asset_path,
    const char* family_parameter_definitions_json,
    const char* family_parameter_values_json,
    const char* family_plan_svg
) {
    if (handle == nullptr || handle->session == nullptr || family_asset_id == nullptr ||
        family_name == nullptr || family_type_id == nullptr || family_type_name == nullptr ||
        family_category == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_element_family_reference(
        element_id,
        family_asset_id,
        family_name,
        family_type_id,
        family_type_name,
        family_category,
        family_asset_path == nullptr ? std::string{} : std::string{family_asset_path},
        family_parameter_definitions_json == nullptr ? std::string{} : std::string{family_parameter_definitions_json},
        family_parameter_values_json == nullptr ? std::string{} : std::string{family_parameter_values_json},
        family_plan_svg == nullptr ? std::string{} : std::string{family_plan_svg}
    ));
}

TbeApiStatusCode tbe_move_element(TbeEngineHandle* handle, uint64_t element_id, double delta_x_meters, double delta_y_meters) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->move_element(element_id, delta_x_meters, delta_y_meters));
}

TbeApiStatusCode tbe_update_family_instance(
    TbeEngineHandle* handle,
    uint64_t element_id,
    TbeVec2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    const TbeVec3* vertices,
    size_t vertex_count,
    const uint32_t* indices,
    size_t index_count
) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    if ((vertex_count > 0 && vertices == nullptr) || (index_count > 0 && indices == nullptr)) {
        return TBE_API_INVALID_ARGUMENT;
    }
    std::vector<tbe::api::Vec3> mesh_vertices;
    mesh_vertices.reserve(vertex_count);
    for (size_t index = 0; index < vertex_count; ++index) {
        mesh_vertices.push_back(tbe::api::Vec3{.x = vertices[index].x, .y = vertices[index].y, .z = vertices[index].z});
    }
    std::vector<uint32_t> mesh_indices;
    mesh_indices.reserve(index_count);
    for (size_t index = 0; index < index_count; ++index) mesh_indices.push_back(indices[index]);
    return apply_result(handle, handle->session->update_family_instance(
        element_id,
        tbe::api::Vec2{.x = position.x, .y = position.y},
        width_meters,
        depth_meters,
        height_meters,
        std::move(mesh_vertices),
        std::move(mesh_indices)
    ));
}

TbeApiStatusCode tbe_update_roof_properties(
    TbeEngineHandle* handle, uint64_t roof_id, int roof_type,
    int has_slope, double slope_degrees, int has_overhang, double overhang_meters
) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->update_roof_properties(
        roof_id, static_cast<tbe::api::ApiRoofType>(roof_type),
        has_slope != 0 ? std::optional<double>{slope_degrees} : std::nullopt,
        has_overhang != 0 ? std::optional<double>{overhang_meters} : std::nullopt));
}

TbeApiStatusCode tbe_set_structural_wall_cut(
    TbeEngineHandle* handle, uint64_t wall_id, uint64_t cutter_id, int enabled, double clearance_meters
) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->set_structural_wall_cut(wall_id, cutter_id, enabled != 0, clearance_meters));
}

TbeApiStatusCode tbe_set_beam_column_join(TbeEngineHandle* handle, uint64_t beam_id, uint64_t column_id, int enabled) {
    if (handle == nullptr || handle->session == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->set_beam_column_join(beam_id, column_id, enabled != 0));
}

TbeApiStatusCode tbe_move_wall(TbeEngineHandle* handle, uint64_t wall_id, double dx_meters, double dy_meters) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    const auto wall = handle->session->get_wall(wall_id);
    if (!wall.ok() || !wall.value.has_value()) {
        return apply_result(handle, wall);
    }
    const auto current = *wall.value;
    return apply_result(handle, handle->session->set_wall_axis(
        wall_id,
        tbe::api::Vec2{.x = current.start.x + dx_meters, .y = current.start.y + dy_meters},
        tbe::api::Vec2{.x = current.end.x + dx_meters, .y = current.end.y + dy_meters}
    ));
}

TbeApiStatusCode tbe_create_door(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    uint64_t* out_door_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_door_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_door(name, host_wall_id, offset_meters, width_meters, height_meters);
    if (result.ok() && result.value.has_value()) {
        *out_door_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_window(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters,
    uint64_t* out_window_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_window_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_window(name, host_wall_id, offset_meters, width_meters, height_meters, sill_height_meters);
    if (result.ok() && result.value.has_value()) {
        *out_window_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_column(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeVec2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    uint64_t material_id,
    uint64_t* out_column_id
) {
    if (handle == nullptr || handle->session == nullptr || out_column_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_column(
        level_id,
        tbe::api::Vec2{.x = position.x, .y = position.y},
        width_meters,
        depth_meters,
        height_meters,
        material_id
    );
    if (result.ok() && result.value.has_value()) {
        *out_column_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_proxy(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t level_id,
    TbeVec2 position,
    double width_meters,
    double depth_meters,
    double height_meters,
    const TbeVec3* vertices,
    size_t vertex_count,
    const uint32_t* indices,
    size_t index_count,
    uint64_t* out_proxy_id
) {
    if (handle == nullptr || handle->session == nullptr || name == nullptr || out_proxy_id == nullptr) {
        return null_handle_error(handle);
    }
    if ((vertex_count > 0 && vertices == nullptr) || (index_count > 0 && indices == nullptr)) {
        return TBE_API_INVALID_ARGUMENT;
    }
    std::vector<tbe::api::Vec3> mesh_vertices;
    mesh_vertices.reserve(vertex_count);
    for (size_t index = 0; index < vertex_count; ++index) {
        mesh_vertices.push_back(tbe::api::Vec3{
            .x = vertices[index].x,
            .y = vertices[index].y,
            .z = vertices[index].z,
        });
    }
    std::vector<uint32_t> mesh_indices;
    mesh_indices.reserve(index_count);
    for (size_t index = 0; index < index_count; ++index) {
        mesh_indices.push_back(indices[index]);
    }
    const auto result = handle->session->create_proxy(
        name,
        level_id,
        tbe::api::Vec2{.x = position.x, .y = position.y},
        width_meters,
        depth_meters,
        height_meters,
        std::move(mesh_vertices),
        std::move(mesh_indices)
    );
    if (result.ok() && result.value.has_value()) {
        *out_proxy_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_stair(
    TbeEngineHandle* handle, uint64_t base_level_id, uint64_t top_level_id,
    TbeVec2 start, TbeVec2 direction, double width_meters, double total_rise_meters,
    double total_run_meters, int riser_count, int tread_count, uint64_t* out_stair_id
) {
    if (handle == nullptr || handle->session == nullptr || out_stair_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_stair(
        base_level_id, top_level_id,
        tbe::api::Vec2{.x = start.x, .y = start.y},
        tbe::api::Vec2{.x = direction.x, .y = direction.y},
        width_meters, total_rise_meters, total_run_meters, riser_count, tread_count, 0
    );
    if (result.ok() && result.value.has_value()) {
        *out_stair_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_stair_layout(
    TbeEngineHandle* handle,
    uint64_t base_level_id,
    uint64_t top_level_id,
    const TbeVec2* path_points,
    size_t path_count,
    double width_meters,
    double total_rise_meters,
    int riser_count,
    int tread_count,
    double landing_depth_meters,
    int layout_kind,
    int railing_enabled,
    uint64_t* out_stair_id
) {
    if (handle == nullptr || handle->session == nullptr || path_points == nullptr || out_stair_id == nullptr) {
        return null_handle_error(handle);
    }
    std::vector<tbe::api::Vec2> points;
    points.reserve(path_count);
    for (size_t index = 0; index < path_count; ++index) {
        points.push_back(tbe::api::Vec2{.x = path_points[index].x, .y = path_points[index].y});
    }
    const auto result = handle->session->create_stair_layout(
        base_level_id,
        top_level_id,
        points,
        width_meters,
        total_rise_meters,
        riser_count,
        tread_count,
        landing_depth_meters,
        layout_kind,
        railing_enabled != 0,
        0
    );
    if (result.ok() && result.value.has_value()) {
        *out_stair_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_update_stair_layout(
    TbeEngineHandle* handle,
    uint64_t stair_id,
    const TbeVec2* path_points,
    size_t path_count,
    double width_meters,
    double landing_depth_meters,
    int layout_kind,
    int railing_enabled
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    if (path_count > 0 && path_points == nullptr) {
        return invalid_argument_error(handle, "stair path points are missing");
    }
    std::vector<tbe::api::Vec2> points;
    points.reserve(path_count);
    for (size_t index = 0; index < path_count; ++index) {
        points.push_back(tbe::api::Vec2{.x = path_points[index].x, .y = path_points[index].y});
    }
    return apply_result(handle, handle->session->update_stair_layout(
        stair_id,
        points,
        width_meters,
        landing_depth_meters,
        layout_kind,
        railing_enabled != 0
    ));
}

TbeApiStatusCode tbe_set_opening_level_lock(TbeEngineHandle* handle, uint64_t opening_id, int locked) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_opening_level_lock(opening_id, locked != 0));
}

TbeApiStatusCode tbe_set_opening_level(TbeEngineHandle* handle, uint64_t opening_id, uint64_t level_id) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_opening_level(opening_id, level_id));
}

TbeApiStatusCode tbe_set_opening_level_constraint(
    TbeEngineHandle* handle,
    uint64_t opening_id,
    uint64_t level_id,
    double level_offset_meters
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->set_opening_level_constraint(opening_id, level_id, level_offset_meters));
}

TbeApiStatusCode tbe_move_hosted_opening(TbeEngineHandle* handle, uint64_t opening_id, double offset_meters) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->move_hosted_opening(opening_id, offset_meters));
}

TbeApiStatusCode tbe_resize_door(TbeEngineHandle* handle, uint64_t door_id, double width_meters, double height_meters) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->resize_door(door_id, width_meters, height_meters));
}

TbeApiStatusCode tbe_resize_window(TbeEngineHandle* handle, uint64_t window_id, double width_meters, double height_meters, double sill_height_meters) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->resize_window(window_id, width_meters, height_meters, sill_height_meters));
}

TbeApiStatusCode tbe_update_hosted_opening(
    TbeEngineHandle* handle,
    uint64_t opening_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(
        handle,
        handle->session->update_hosted_opening(
            opening_id,
            offset_meters,
            width_meters,
            height_meters,
            sill_height_meters
        )
    );
}

TbeApiStatusCode tbe_create_profile(
    TbeEngineHandle* handle,
    int target_kind,
    int draft_mode,
    uint64_t level_id,
    const TbeVec2* points,
    size_t point_count,
    const uint64_t* wall_ids,
    size_t wall_id_count,
    int closed,
    double thickness_meters,
    double height_meters,
    double vertical_offset_meters,
    uint64_t material_id,
    uint64_t assembly_id,
    int roof_type,
    uint64_t* out_first_id,
    uint64_t* out_created_count
) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    tbe::api::ProfileDraftDTO draft{
        .mode = static_cast<tbe::api::ApiProfileDraftMode>(draft_mode),
        .target_kind = static_cast<tbe::api::ApiProfileTargetKind>(target_kind),
        .level_id = {.value = level_id},
        .closed = closed != 0,
        .thickness_meters = thickness_meters,
        .height_meters = height_meters,
        .vertical_offset_meters = vertical_offset_meters,
        .material_id = {.value = material_id},
        .assembly_id = {.value = assembly_id},
        .roof_type = static_cast<tbe::api::ApiRoofType>(roof_type),
    };
    for (size_t index = 0; index < point_count; ++index) {
        draft.points.push_back(tbe::api::Vec2{.x = points[index].x, .y = points[index].y});
    }
    for (size_t index = 0; index < wall_id_count; ++index) {
        draft.picked_wall_ids.push_back({.value = wall_ids[index]});
    }
    const auto result = handle->session->create_elements_from_profile(std::move(draft));
    if (result.ok() && result.value.has_value()) {
        const auto& ids = *result.value;
        if (out_created_count != nullptr) {
            *out_created_count = static_cast<uint64_t>(ids.size());
        }
        if (out_first_id != nullptr && !ids.empty()) {
            *out_first_id = ids.front().value;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_floor_system_for_room(
    TbeEngineHandle* handle,
    uint64_t room_id,
    uint64_t assembly_id,
    uint64_t* out_floor_id
) {
    if (handle == nullptr || handle->session == nullptr || out_floor_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_floor_system_for_room(room_id, assembly_id);
    if (result.ok() && result.value.has_value()) {
        *out_floor_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_ceiling_system_for_room(
    TbeEngineHandle* handle,
    uint64_t room_id,
    uint64_t assembly_id,
    double height_offset_meters,
    uint64_t* out_ceiling_id
) {
    if (handle == nullptr || handle->session == nullptr || out_ceiling_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_ceiling_system_for_room(room_id, assembly_id, height_offset_meters);
    if (result.ok() && result.value.has_value()) {
        *out_ceiling_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_delete_element(TbeEngineHandle* handle, uint64_t element_id) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->delete_element(element_id));
}

TbeApiStatusCode tbe_detect_rooms(TbeEngineHandle* handle, uint64_t* out_room_count) {
    if (handle == nullptr || handle->session == nullptr || out_room_count == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->detect_rooms();
    if (result.ok() && result.value.has_value()) {
        *out_room_count = static_cast<uint64_t>(result.value->size());
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_generate_schedules(TbeEngineHandle* handle, TbeScheduleSummary* out_summary) {
    if (handle == nullptr || handle->session == nullptr || out_summary == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->generate_schedules();
    if (result.ok() && result.value.has_value()) {
        const auto& summary = *result.value;
        out_summary->wall_rows = summary.wall_rows;
        out_summary->opening_rows = summary.opening_rows;
        out_summary->room_rows = summary.room_rows;
        out_summary->slab_rows = summary.slab_rows;
        out_summary->roof_rows = summary.roof_rows;
        out_summary->column_rows = summary.column_rows;
        out_summary->beam_rows = summary.beam_rows;
        out_summary->stair_rows = summary.stair_rows;
        out_summary->floor_rows = summary.floor_rows;
        out_summary->ceiling_rows = summary.ceiling_rows;
        out_summary->material_takeoff_rows = summary.material_takeoff_rows;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_validate(TbeEngineHandle* handle, TbeValidationSummary* out_summary) {
    if (handle == nullptr || handle->session == nullptr || out_summary == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->get_validation_report();
    if (result.ok() && result.value.has_value()) {
        const auto& summary = *result.value;
        out_summary->issue_count = summary.issue_count;
        out_summary->warning_count = summary.warning_count;
        out_summary->error_count = summary.error_count;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_rebuild_spatial_index(TbeEngineHandle* handle) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->rebuild_spatial_index());
}

TbeApiStatusCode tbe_spatial_index_stats(TbeEngineHandle* handle, TbeSpatialIndexStats* out_stats) {
    if (handle == nullptr || handle->session == nullptr || out_stats == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->spatial_index_stats();
    if (result.ok() && result.value.has_value()) {
        const auto& stats = *result.value;
        out_stats->version = stats.version;
        out_stats->element_count = static_cast<uint64_t>(stats.element_bounds_count);
        out_stats->bucket_count = static_cast<uint64_t>(stats.bucket_count);
        out_stats->average_bucket_occupancy = stats.average_bucket_occupancy;
        out_stats->max_bucket_occupancy = static_cast<uint64_t>(stats.max_bucket_occupancy);
        out_stats->dirty = stats.dirty ? 1 : 0;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_query_rect(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeRect2 bounds,
    TbeElementIdListResult* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    out_result->count = 0;
    out_result->element_ids = nullptr;
    if (!std::isfinite(bounds.min_x) || !std::isfinite(bounds.min_y) ||
        !std::isfinite(bounds.max_x) || !std::isfinite(bounds.max_y) ||
        bounds.min_x > bounds.max_x || bounds.min_y > bounds.max_y) {
        handle->last_error = "query rectangle must be finite and normalized";
        return TBE_API_INVALID_ARGUMENT;
    }
    const auto result = handle->session->query_rect(
        tbe::api::ElementIdDTO{.value = level_id},
        tbe::api::AABB2D{
            .min_x = bounds.min_x,
            .min_y = bounds.min_y,
            .max_x = bounds.max_x,
            .max_y = bounds.max_y,
        }
    );
    if (result.ok() && result.value.has_value()) {
        const auto& elements = *result.value;
        out_result->count = static_cast<uint64_t>(elements.size());
        if (!elements.empty()) {
            auto* ids = static_cast<uint64_t*>(std::malloc(sizeof(uint64_t) * elements.size()));
            if (ids == nullptr) {
                handle->last_error = "failed to allocate rectangle query buffer";
                return TBE_API_INTERNAL_ERROR;
            }
            for (std::size_t index = 0; index < elements.size(); ++index) {
                ids[index] = elements[index].id.value;
            }
            out_result->element_ids = ids;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_hit_test_point(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeVec2 point,
    double tolerance_meters,
    TbeHitTestResult* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->hit_test_point(tbe::api::HitTestPoint{
        .level_id = tbe::api::ElementIdDTO{.value = level_id},
        .point = tbe::api::Vec2{.x = point.x, .y = point.y},
        .tolerance_meters = tolerance_meters,
    });
    if (result.ok() && result.value.has_value()) {
        const auto& candidates = *result.value;
        out_result->candidate_count = static_cast<uint64_t>(candidates.size());
        if (!candidates.empty()) {
            const auto& first = candidates.front();
            out_result->element_id = first.element_id.value;
            out_result->element_kind = static_cast<int>(first.element_kind);
            out_result->hit_kind = static_cast<int>(first.hit_kind);
            out_result->distance_meters = first.distance_meters;
            out_result->priority = first.priority;
        } else {
            out_result->element_id = 0;
            out_result->element_kind = 0;
            out_result->hit_kind = 0;
            out_result->distance_meters = 0.0;
            out_result->priority = 0;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_hit_test_candidates(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeVec2 point,
    double tolerance_meters,
    TbeHitTestCandidatesResult* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->hit_test_point(tbe::api::HitTestPoint{
        .level_id = tbe::api::ElementIdDTO{.value = level_id},
        .point = tbe::api::Vec2{.x = point.x, .y = point.y},
        .tolerance_meters = tolerance_meters,
    });
    out_result->candidate_count = 0;
    out_result->candidates = nullptr;
    if (result.ok() && result.value.has_value()) {
        const auto& candidates = *result.value;
        out_result->candidate_count = static_cast<uint64_t>(candidates.size());
        if (!candidates.empty()) {
            auto* buffer = static_cast<TbeHitTestCandidate*>(std::malloc(sizeof(TbeHitTestCandidate) * candidates.size()));
            if (buffer == nullptr) {
                handle->last_error = "failed to allocate hit candidate buffer";
                return TBE_API_INTERNAL_ERROR;
            }
            for (std::size_t i = 0; i < candidates.size(); ++i) {
                const auto& candidate = candidates[i];
                buffer[i] = TbeHitTestCandidate{
                    .element_id = candidate.element_id.value,
                    .element_kind = static_cast<int>(candidate.element_kind),
                    .hit_kind = static_cast<int>(candidate.hit_kind),
                    .distance_meters = candidate.distance_meters,
                    .priority = candidate.priority,
                };
            }
            out_result->candidates = buffer;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_compute_wall_free_intervals(
    TbeEngineHandle* handle,
    uint64_t wall_id,
    double requested_width_meters,
    double clearance_meters,
    TbeWallFreeIntervalsResult* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->compute_wall_free_intervals(wall_id, requested_width_meters, clearance_meters);
    if (result.ok() && result.value.has_value()) {
        out_result->wall_id = wall_id;
        out_result->interval_count = static_cast<uint64_t>(result.value->size());
        out_result->intervals = nullptr;
        if (!result.value->empty()) {
            auto* intervals = static_cast<TbeWallInterval*>(std::malloc(sizeof(TbeWallInterval) * result.value->size()));
            if (intervals == nullptr) {
                handle->last_error = "failed to allocate intervals buffer";
                return TBE_API_INTERNAL_ERROR;
            }
            for (std::size_t i = 0; i < result.value->size(); ++i) {
                intervals[i] = TbeWallInterval{
                    .start_offset_meters = result.value->at(i).start_offset_meters,
                    .end_offset_meters = result.value->at(i).end_offset_meters,
                    .length_meters = result.value->at(i).length_meters,
                };
            }
            out_result->intervals = intervals;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_best_snap(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeVec2 point,
    double tolerance_meters,
    TbeSnapResult* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->best_snap(
        tbe::api::ElementIdDTO{.value = level_id},
        tbe::api::Vec2{.x = point.x, .y = point.y},
        tolerance_meters
    );
    if (result.ok() && result.value.has_value()) {
        const auto& snap = *result.value;
        out_result->x = snap.point.x;
        out_result->y = snap.point.y;
        out_result->snap_type = static_cast<int>(snap.type);
        out_result->source_element_id = snap.source_element_id.has_value() ? snap.source_element_id->value : 0;
        out_result->distance_meters = snap.distance_meters;
        out_result->priority = snap.priority;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_find_wall_host_at_point(
    TbeEngineHandle* handle,
    uint64_t level_id,
    TbeVec2 point,
    double tolerance_meters,
    double requested_width_meters,
    double clearance_meters,
    TbeWallHostPlacement* out_result
) {
    if (handle == nullptr || handle->session == nullptr || out_result == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->find_wall_host_at_point(
        tbe::api::ElementIdDTO{.value = level_id},
        tbe::api::Vec2{.x = point.x, .y = point.y},
        tolerance_meters,
        requested_width_meters,
        clearance_meters
    );
    if (result.ok() && result.value.has_value()) {
        const auto& placement = *result.value;
        out_result->wall_id = placement.wall_id.value;
        out_result->requested_offset_meters = placement.requested_offset_meters;
        out_result->wall_local_offset_meters = placement.wall_local_offset_meters;
        out_result->adjusted_valid_offset_meters = placement.adjusted_valid_offset_meters;
        out_result->valid = placement.valid ? 1 : 0;
        out_result->warning_count = static_cast<int>(placement.warnings.size());
        out_result->interval_count = static_cast<uint64_t>(placement.free_intervals.size());
        out_result->intervals = nullptr;
        if (!placement.free_intervals.empty()) {
            auto* intervals = static_cast<TbeWallInterval*>(std::malloc(sizeof(TbeWallInterval) * placement.free_intervals.size()));
            if (intervals == nullptr) {
                handle->last_error = "failed to allocate placement intervals buffer";
                return TBE_API_INTERNAL_ERROR;
            }
            for (std::size_t i = 0; i < placement.free_intervals.size(); ++i) {
                intervals[i] = TbeWallInterval{
                    .start_offset_meters = placement.free_intervals[i].start_offset_meters,
                    .end_offset_meters = placement.free_intervals[i].end_offset_meters,
                    .length_meters = placement.free_intervals[i].length_meters,
                };
            }
            out_result->intervals = intervals;
        }
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_undo(TbeEngineHandle* handle) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->undo());
}

TbeApiStatusCode tbe_redo(TbeEngineHandle* handle) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->redo());
}

TbeApiStatusCode tbe_export_ifc(TbeEngineHandle* handle, const char* path) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->export_ifc(path));
}

TbeApiStatusCode tbe_import_ifc(TbeEngineHandle* handle, const char* path, int load_mode) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->import_ifc(path, static_cast<tbe::api::LoadMode>(load_mode)));
}

TbeApiStatusCode tbe_compile_bim_cache(
    TbeEngineHandle* handle,
    const char* source_ifc_path,
    const char* cache_path,
    TbeBimCacheStats* out_stats
) {
    if (handle == nullptr || handle->session == nullptr || source_ifc_path == nullptr ||
        cache_path == nullptr || out_stats == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->compile_bim_cache(source_ifc_path, cache_path);
    if (result.ok() && result.value.has_value()) {
        copy_bim_cache_stats(*result.value, out_stats);
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_inspect_bim_cache(
    TbeEngineHandle* handle,
    const char* source_ifc_path,
    const char* cache_path,
    TbeBimCacheStats* out_stats
) {
    if (handle == nullptr || handle->session == nullptr || source_ifc_path == nullptr ||
        cache_path == nullptr || out_stats == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->inspect_bim_cache(source_ifc_path, cache_path);
    if (result.ok() && result.value.has_value()) {
        copy_bim_cache_stats(*result.value, out_stats);
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_get_unit_settings(TbeEngineHandle* handle, char** out_json) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) return null_handle_error(handle);
    const auto result = handle->session->get_unit_settings();
    if (!result.ok() || !result.value.has_value()) return apply_result(handle, result);
    const auto& settings = *result.value;
    std::ostringstream json;
    json << "{\"system\":\"" << settings.system << "\",\"length\":\"" << settings.length
         << "\",\"angle\":\"" << settings.angle << "\"}";
    const auto value = json.str();
    auto* buffer = static_cast<char*>(std::malloc(value.size() + 1));
    if (buffer == nullptr) {
        handle->last_error = "failed to allocate unit settings buffer";
        return TBE_API_INTERNAL_ERROR;
    }
    std::memcpy(buffer, value.c_str(), value.size() + 1);
    *out_json = buffer;
    handle->last_error.clear();
    return TBE_API_OK;
}

TbeApiStatusCode tbe_set_unit_settings(TbeEngineHandle* handle, const char* system, const char* length, const char* angle) {
    if (handle == nullptr || handle->session == nullptr || system == nullptr || length == nullptr || angle == nullptr) return null_handle_error(handle);
    return apply_result(handle, handle->session->set_unit_settings(tbe::api::UnitSettingsDTO{system, length, angle}));
}

TbeApiStatusCode tbe_get_history_counts(
    TbeEngineHandle* handle,
    uint64_t* out_undo_count,
    uint64_t* out_redo_count
) {
    if (handle == nullptr || handle->session == nullptr || out_undo_count == nullptr || out_redo_count == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->get_history_summary();
    if (result.ok() && result.value.has_value()) {
        *out_undo_count = static_cast<uint64_t>(result.value->undo_count);
        *out_redo_count = static_cast<uint64_t>(result.value->redo_count);
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_export_svg(TbeEngineHandle* handle, const char* path) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->export_svg(path));
}

TbeApiStatusCode tbe_export_obj(TbeEngineHandle* handle, const char* path) {
    if (handle == nullptr || handle->session == nullptr || path == nullptr) {
        return null_handle_error(handle);
    }
    return apply_result(handle, handle->session->export_obj(path));
}

TbeApiStatusCode tbe_get_render_scene_json(TbeEngineHandle* handle, char** out_json) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(handle, handle->session->get_render_scene_json(), out_json);
}

TbeApiStatusCode tbe_get_render_scene_json_primary(
    TbeEngineHandle* handle,
    uint64_t active_level_id,
    char** out_json
) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(
        handle,
        handle->session->get_render_scene_json_primary(active_level_id),
        out_json
    );
}

TbeApiStatusCode tbe_get_render_scene_json_near_level(
    TbeEngineHandle* handle,
    uint64_t active_level_id,
    int adjacent_level_count,
    char** out_json
) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(
        handle,
        handle->session->get_render_scene_json_near_level(active_level_id, adjacent_level_count),
        out_json
    );
}

TbeApiStatusCode tbe_get_section_scene_json(TbeEngineHandle* handle, TbeVec2 start, TbeVec2 end, char** out_json) {
    if (handle == nullptr || handle->session == nullptr || out_json == nullptr) {
        return null_handle_error(handle);
    }
    return copy_string_result(
        handle,
        handle->session->get_section_scene_json(
            tbe::api::Vec2{.x = start.x, .y = start.y},
            tbe::api::Vec2{.x = end.x, .y = end.y}
        ),
        out_json
    );
}

TbeApiStatusCode tbe_set_performance_profile(TbeEngineHandle* handle, int profile) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    if (!is_valid_performance_profile(profile)) {
        handle->last_error = "invalid performance profile";
        return TBE_API_INVALID_ARGUMENT;
    }
    return apply_result(handle, handle->session->set_performance_profile(
        static_cast<tbe::api::PerformanceProfile>(profile)
    ));
}

TbeApiStatusCode tbe_set_compute_mode(TbeEngineHandle* handle, int mode) {
    if (handle == nullptr || handle->session == nullptr) {
        return null_handle_error(handle);
    }
    if (!is_valid_compute_mode(mode)) {
        handle->last_error = "invalid compute mode";
        return TBE_API_INVALID_ARGUMENT;
    }
    return apply_result(handle, handle->session->set_compute_mode(
        static_cast<tbe::api::ComputeMode>(mode)
    ));
}

TbeApiStatusCode tbe_create_residential_template(TbeEngineHandle* handle, int building_count, int story_count, uint64_t* out_primary_level_id) {
    if (handle == nullptr || handle->session == nullptr || out_primary_level_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_residential_template(building_count, story_count);
    if (result.ok() && result.value.has_value()) {
        *out_primary_level_id = result.value->value;
    }
    return apply_result(handle, result);
}

TbeApiStatusCode tbe_create_showcase_template(TbeEngineHandle* handle, int template_kind, uint64_t* out_primary_level_id) {
    if (handle == nullptr || handle->session == nullptr || out_primary_level_id == nullptr) {
        return null_handle_error(handle);
    }
    const auto result = handle->session->create_showcase_template(template_kind);
    if (result.ok() && result.value.has_value()) {
        *out_primary_level_id = result.value->value;
    }
    return apply_result(handle, result);
}

const char* tbe_get_last_error(const TbeEngineHandle* handle) {
    if (handle == nullptr) {
        return "engine handle is null";
    }
    return handle->last_error.c_str();
}

void tbe_free_string(char* value) {
    std::free(value);
}

void tbe_free_memory(void* value) {
    std::free(value);
}

} // extern "C"
