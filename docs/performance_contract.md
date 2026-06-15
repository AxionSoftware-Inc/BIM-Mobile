# Performance Contract

## Freshness States

Derived engine data is tracked with a shared freshness contract:

- `Clean`: cached data is current and safe to treat as final.
- `Dirty`: source model changed and this derived category must be recomputed.
- `Stale`: cached data exists, but a newer model edit made it outdated.
- `Computing`: a recompute is currently running.
- `Failed`: the last recompute attempt failed and callers must not trust the cache.

The public API applies this to:

- room metrics
- generated geometry
- schedules
- material takeoff
- validation report
- export readiness

## Cached vs Fresh APIs

Public API reads are split into two families:

- Cached reads may return stale data together with freshness.
  - examples: `get_cached_room_schedule()`, `get_cached_wall_schedule()`, `get_cached_validation_report()`
- Fresh/generate reads must return clean data or an explicit error.
  - examples: `generate_room_schedule()`, `generate_material_takeoff_summary()`, `generate_validation_report()`

The existing convenience methods such as `get_room_schedule()` and `get_validation_report()` follow the safe path and force fresh results.

## Compute Modes

`ComputeMode` controls how aggressively recomputation runs:

- `InteractivePreview`
  - optimize for drag/stylus responsiveness
  - recompute room metrics and dirty geometry only
  - avoid full validation and heavy downstream work
- `Normal`
  - recompute affected rooms and geometry
  - update schedules and material takeoff unless the active profile defers them
- `FinalExact`
  - full room recompute
  - full geometry regenerate
  - rebuild schedules and takeoff
  - full validation
  - required before safe export/save/report

## Performance Profiles

`PerformanceProfile` tunes background work:

- `BatterySaver`
  - delay non-critical schedule/takeoff/validation updates
  - prefer batched recompute
  - reduce unnecessary final work during interactive edits
- `Balanced`
  - default
  - predictable fresh results without over-eager recompute
- `Performance`
  - recompute more eagerly after edits
  - keep caches warmer for repeated reads

## Safety Rules

- Edits mark affected derived categories as `Dirty` or `Stale`.
- Cached read APIs must surface freshness to the caller.
- Fresh/generate APIs must not silently return stale data.
- `save_project_json()` forces `FinalExact` recompute before returning JSON.
- `export_svg()` and `export_obj()` force `FinalExact` recompute by default.
- `save_project_json_cached(true)` and cached export paths are explicitly opt-in for stale output.
- Loading JSON through the API clears cached derived state and marks derived categories dirty, so the session does not silently trust serialized metrics.
