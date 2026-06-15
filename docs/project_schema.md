# Project Schema

## Current Version

- `TBE_SCHEMA_VERSION = 1`
- current project JSON writes:
  - `schema`
  - `schema_version`
  - `engine_version`
  - `project_name`
  - `document`

Missing `schema_version` is treated as legacy schema `v0`.

## Migration Policy

- the engine detects schema version before load
- `v0 -> v1` migration is currently supported
- migration is explicit through API calls and also used during load
- unsupported migration paths fail with an error

Current legacy migration behavior:

- add missing `schema_version`
- add current `engine_version`
- add placeholder `level_id` for legacy door/window payloads when absent

Unknown fields are ignored safely by the current loader.

## Repair Policy

Repair is explicit and driven by `RepairOptionsDTO`.

Safe repair actions currently include:

- remove orphan openings when allowed
- remove invalid rooms referencing deleted walls when allowed
- regenerate room metrics
- regenerate dirty geometry
- fix door/window `level_id` from host wall when possible
- remove duplicate joins
- rebuild dependency and spatial caches

Repair reports include:

- repaired count
- warning count
- error count
- message list

## Load Modes

- `Strict`
  - load JSON
  - validate
  - fail if validation reports errors

- `Tolerant`
  - load what can be loaded
  - return warnings or validation issues to caller

- `Repair`
  - load
  - run safe repairs
  - rebuild caches
  - return repair report through API

## Package Layout

Current package export is a directory package, ready to be zipped later if needed.

Example layout:

```text
my_project.tbeproj/
  project.json
  metadata.json
  exports/
    floorplan.svg
    walls.obj
  debug/
    debug_report.json
```

`project.json` is authoritative. Exported SVG/OBJ/debug files are derived artifacts.

## Backward Compatibility Rules

- current engine writes schema `v1`
- legacy `v0` without `schema_version` is supported through migration
- newer unknown schema versions are not accepted automatically
- save after migration normalizes project JSON back to current schema
