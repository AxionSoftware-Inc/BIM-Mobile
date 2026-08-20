# API Usage

## C++ API Overview

Primary entry point:

- `tbe::api::create_session()`

Typical flow:

1. create session
2. create or load project
3. add/edit elements
4. recompute or query cached/fresh derived data
5. validate
6. save JSON or export package

Important session calls:

- project: `new_project`, `load_project_json`, `save_project_json`
- persistence: `load_project_json_with_mode`, `migrate_project_json`, `export_project_package`, `import_project_package`
- model edits: `create_wall`, `create_door`, `create_window`, `set_wall_axis`, `delete_element`
- derived data: `detect_rooms`, `generate_schedules`, `get_validation_report`
- interaction: `hit_test_point`, `best_snap`, `compute_wall_free_intervals`

## C ABI Overview

Primary entry point:

- `tbe_engine_create()`
- `tbe_engine_destroy()`

The C ABI uses:

- opaque engine handles
- POD structs
- integer status codes
- explicitly allocated result buffers for strings and interval arrays

## Ownership Rules

Caller-owned outputs returned by allocation:

- strings from `tbe_project_save_json`
- strings from `tbe_migrate_project_json`
- strings from version getter C APIs
- arrays from `tbe_compute_wall_free_intervals`
- arrays inside `tbe_find_wall_host_at_point`

Free them with:

- `tbe_free_string()`
- `tbe_free_memory()`

Passing `NULL` to these free functions is safe.

## Error Handling

All public API calls return structured success/failure:

- C++: `ApiResult<T>` or `ApiVoidResult`
- C: `TbeApiStatusCode`

C ABI callers should check the return code first, then use:

- `tbe_get_last_error()`

`last_error` is updated on failure and typically cleared on successful string/buffer-returning calls.

## Load / Save / Package Flow

Recommended safe flow:

1. `load_project_json_with_mode(..., Repair)` for legacy or uncertain inputs
2. inspect migration and repair reports
3. `get_validation_report()`
4. `save_project_json()` or `export_project_package()`

Package layout currently exports a directory package with:

- `project.json`
- `metadata.json`
- optional exports/debug files

## Cached vs Fresh APIs

Cached reads may return stale freshness state:

- `get_cached_room_schedule`
- `get_cached_validation_report`
- `save_project_json_cached`

Fresh generation APIs recompute as needed:

- `generate_room_schedule`
- `get_validation_report`
- `save_project_json`
- `export_project_package`

## Performance Profile Usage

Available profiles:

- `BatterySaver`
- `Balanced`
- `Performance`

Use `InteractivePreview` compute mode for drag/stylus-like updates and `FinalExact` before export/reporting.

## Hit / Snap Usage

Hit test:

- `hit_test_point()`

Snap:

- `get_snap_candidates()`
- `best_snap()`

Placement:

- `compute_wall_free_intervals()`
- `find_wall_host_at_point()`

Snap options let you enable only the candidate families needed by your tool.

## Minimal C++ Example

```cpp
auto session_result = tbe::api::create_session("Example");
auto session = std::move(*session_result.value);
auto level = session->create_level("Level 1", 0.0, 3.0);
session->create_wall("A", {0, 0}, {4, 0}, 0.2, 3.0, level.value->value);
session->detect_rooms();
auto validation = session->get_validation_report();
```

## Minimal C Example

```c
TbeEngineHandle* handle = tbe_engine_create();
uint64_t wall_id = 0;
tbe_create_wall(handle, "A", 0, (TbeVec2){0, 0}, (TbeVec2){4, 0}, 0.2, 3.0, &wall_id);
tbe_engine_destroy(handle);
```
