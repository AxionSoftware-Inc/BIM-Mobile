# Render Scene Bridge

`RenderScene` is the stable export format between the C++ BIM engine and future Flutter + Filament UI layers.
It exists so the viewer can consume a predictable scene payload without depending on `debug_report.json`, ad-hoc OBJ files, or internal engine classes.

## Why this exists

- Provide one scene contract for 2D/3D viewers.
- Keep the engine-side geometry export explicit and versioned.
- Make it easy for mobile/desktop UIs to load the same semantic model.
- Separate renderable scene data from debug and validation data.

## Coordinate system

- Engine / BIM coordinates:
  - `X` and `Y` are the plan plane.
  - `Z` is vertical up.
- Render scene export:
  - Units are meters.
  - `scene_version` starts at `1`.
  - `coordinate_system` is `X/Y plan, Z up`.
- Flutter / Filament mapping:
  - Plan geometry can be treated as `X/Z` ground plane in the 3D viewport.
  - Engine `Z` maps to vertical up in the renderer.

## RenderScene contents

Each exported object carries:

- `element_id`
- `kind`
- `level_id`
- `selectable`
- `visible_by_default`
- `revision`
- `bounds`
- mesh positions and indices
- optional normals
- a simple material/category label

The scene currently includes:

- walls
- doors
- windows
- slabs
- floors / ceilings when geometry exists
- roof
- columns
- beams
- stairs

## Chunking and levels

The engine exports a flat scene list for now.
Viewers can:

- group by `level_id`
- filter by `kind`
- render only visible-by-default objects first
- lazily load or toggle object subsets later

This keeps the engine output simple while leaving room for later chunked streaming.

## Limitations

- This is not a full scene graph or rendering engine.
- Meshes are fallback-quality geometry, not production-grade visualization meshes.
- Some elements may export simple placeholder geometry until their final renderer is implemented.
- The scene is intended for visualization and selection, not structural analysis.
- Advanced materials, UVs, and per-face rendering rules are intentionally minimal for now.

## Export files

`render_scene.json` is included in project package exports alongside:

- `project.json`
- `metadata.json`
- `debug/debug_report.json`
- `exports/floorplan.svg`
- `exports/walls.obj`

The render scene also exposes basic object, vertex, and index counts for quick diagnostics.
