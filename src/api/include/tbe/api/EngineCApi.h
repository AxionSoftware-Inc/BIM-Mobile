#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TbeEngineHandle TbeEngineHandle;

typedef enum TbeApiStatusCode {
    TBE_API_OK = 0,
    TBE_API_INVALID_ARGUMENT = 1,
    TBE_API_NOT_FOUND = 2,
    TBE_API_VALIDATION_ERROR = 3,
    TBE_API_INTERNAL_ERROR = 4
} TbeApiStatusCode;

typedef struct TbeVec2 {
    double x;
    double y;
} TbeVec2;

typedef struct TbeScheduleSummary {
    size_t wall_rows;
    size_t opening_rows;
    size_t room_rows;
    size_t slab_rows;
    size_t roof_rows;
    size_t column_rows;
    size_t beam_rows;
    size_t stair_rows;
    size_t floor_rows;
    size_t ceiling_rows;
    size_t material_takeoff_rows;
} TbeScheduleSummary;

typedef struct TbeValidationSummary {
    int issue_count;
    int warning_count;
    int error_count;
} TbeValidationSummary;

typedef struct TbeMigrationSummary {
    int from_version;
    int to_version;
    int migrated_count;
    int warning_count;
    int error_count;
} TbeMigrationSummary;

typedef struct TbeRepairSummary {
    int repaired_count;
    int warning_count;
    int error_count;
} TbeRepairSummary;

typedef struct TbeHitTestResult {
    uint64_t element_id;
    int element_kind;
    int hit_kind;
    double distance_meters;
    int priority;
    uint64_t candidate_count;
} TbeHitTestResult;

typedef struct TbeHitTestCandidate {
    uint64_t element_id;
    int element_kind;
    int hit_kind;
    double distance_meters;
    int priority;
} TbeHitTestCandidate;

typedef struct TbeHitTestCandidatesResult {
    uint64_t candidate_count;
    TbeHitTestCandidate* candidates;
} TbeHitTestCandidatesResult;

typedef struct TbeSnapResult {
    double x;
    double y;
    int snap_type;
    uint64_t source_element_id;
    double distance_meters;
    int priority;
} TbeSnapResult;

typedef struct TbeSpatialIndexStats {
    uint64_t version;
    uint64_t element_count;
    uint64_t bucket_count;
    double average_bucket_occupancy;
    uint64_t max_bucket_occupancy;
    int dirty;
} TbeSpatialIndexStats;

typedef struct TbeWallInterval {
    double start_offset_meters;
    double end_offset_meters;
    double length_meters;
} TbeWallInterval;

typedef struct TbeWallFreeIntervalsResult {
    uint64_t wall_id;
    uint64_t interval_count;
    TbeWallInterval* intervals;
} TbeWallFreeIntervalsResult;

typedef struct TbeWallHostPlacement {
    uint64_t wall_id;
    double requested_offset_meters;
    double wall_local_offset_meters;
    double adjusted_valid_offset_meters;
    int valid;
    uint64_t interval_count;
    TbeWallInterval* intervals;
    int warning_count;
} TbeWallHostPlacement;

TbeEngineHandle* tbe_engine_create(void);
void tbe_engine_destroy(TbeEngineHandle* handle);

TbeApiStatusCode tbe_project_new(TbeEngineHandle* handle, const char* project_name);
TbeApiStatusCode tbe_project_load_json(TbeEngineHandle* handle, const char* json);
TbeApiStatusCode tbe_project_load_json_with_mode(TbeEngineHandle* handle, const char* json, int load_mode);
TbeApiStatusCode tbe_project_save_json(TbeEngineHandle* handle, char** out_json);
TbeApiStatusCode tbe_get_engine_version(TbeEngineHandle* handle, char** out_version);
TbeApiStatusCode tbe_get_core_version(TbeEngineHandle* handle, char** out_version);
TbeApiStatusCode tbe_get_api_version(TbeEngineHandle* handle, char** out_version);
TbeApiStatusCode tbe_get_schema_version(TbeEngineHandle* handle, int* out_version);
TbeApiStatusCode tbe_detect_schema_version_from_json(TbeEngineHandle* handle, const char* json, int* out_version);
TbeApiStatusCode tbe_migrate_project_json(TbeEngineHandle* handle, const char* json, int from_version, int to_version, char** out_json);
TbeApiStatusCode tbe_get_last_migration_report(TbeEngineHandle* handle, TbeMigrationSummary* out_summary);
TbeApiStatusCode tbe_get_last_repair_report(TbeEngineHandle* handle, TbeRepairSummary* out_summary);
TbeApiStatusCode tbe_repair_current_project(TbeEngineHandle* handle, TbeRepairSummary* out_summary);
TbeApiStatusCode tbe_export_project_package(TbeEngineHandle* handle, const char* path);
TbeApiStatusCode tbe_import_project_package(TbeEngineHandle* handle, const char* path, int load_mode);
TbeApiStatusCode tbe_export_render_scene_json(TbeEngineHandle* handle, const char* path);

TbeApiStatusCode tbe_create_wall(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t level_id,
    TbeVec2 start,
    TbeVec2 end,
    double thickness_meters,
    double height_meters,
    uint64_t* out_wall_id
);
TbeApiStatusCode tbe_move_wall(TbeEngineHandle* handle, uint64_t wall_id, double dx_meters, double dy_meters);
TbeApiStatusCode tbe_create_door(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    uint64_t* out_door_id
);
TbeApiStatusCode tbe_create_window(
    TbeEngineHandle* handle,
    const char* name,
    uint64_t host_wall_id,
    double offset_meters,
    double width_meters,
    double height_meters,
    double sill_height_meters,
    uint64_t* out_window_id
);
TbeApiStatusCode tbe_detect_rooms(TbeEngineHandle* handle, uint64_t* out_room_count);
TbeApiStatusCode tbe_generate_schedules(TbeEngineHandle* handle, TbeScheduleSummary* out_summary);
TbeApiStatusCode tbe_validate(TbeEngineHandle* handle, TbeValidationSummary* out_summary);
TbeApiStatusCode tbe_rebuild_spatial_index(TbeEngineHandle* handle);
TbeApiStatusCode tbe_spatial_index_stats(TbeEngineHandle* handle, TbeSpatialIndexStats* out_stats);
TbeApiStatusCode tbe_hit_test_point(TbeEngineHandle* handle, uint64_t level_id, TbeVec2 point, double tolerance_meters, TbeHitTestResult* out_result);
TbeApiStatusCode tbe_hit_test_candidates(TbeEngineHandle* handle, uint64_t level_id, TbeVec2 point, double tolerance_meters, TbeHitTestCandidatesResult* out_result);
TbeApiStatusCode tbe_best_snap(TbeEngineHandle* handle, uint64_t level_id, TbeVec2 point, double tolerance_meters, TbeSnapResult* out_result);
TbeApiStatusCode tbe_compute_wall_free_intervals(TbeEngineHandle* handle, uint64_t wall_id, double requested_width_meters, double clearance_meters, TbeWallFreeIntervalsResult* out_result);
TbeApiStatusCode tbe_find_wall_host_at_point(TbeEngineHandle* handle, uint64_t level_id, TbeVec2 point, double tolerance_meters, double requested_width_meters, double clearance_meters, TbeWallHostPlacement* out_result);
TbeApiStatusCode tbe_undo(TbeEngineHandle* handle);
TbeApiStatusCode tbe_redo(TbeEngineHandle* handle);
TbeApiStatusCode tbe_export_svg(TbeEngineHandle* handle, const char* path);
TbeApiStatusCode tbe_export_obj(TbeEngineHandle* handle, const char* path);

const char* tbe_get_last_error(const TbeEngineHandle* handle);
void tbe_free_string(char* value);
void tbe_free_memory(void* value);

#ifdef __cplusplus
}
#endif
