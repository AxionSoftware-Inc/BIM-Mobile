#include "tbe/api/EngineCApi.h"

#include "tbe/api/EngineApi.hpp"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

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
