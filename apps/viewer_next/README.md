# viewer_next

Temporary read-only BIM viewer prototype for exported engine artifacts.

## What it shows

- floorplan SVG from engine export
- 3D OBJ preview from engine export
- debug report JSON with element counts and validation summary
- schedules, material takeoff, and selected element details
- optional `walls.obj` and project metadata if present
- SVG hover/click-selection when embedded element ids are available
- kind filters for walls, rooms, openings, slabs, floors, ceilings, roofs, columns, beams, and stairs
- local dev-only wall, door, and window edit bridges that refresh exported artifacts
- local dev-only numeric edit bridges for delete, wall axis, wall properties, door/window properties, and opening moves

## Sample artifacts

The app loads files from `public/sample`:

- `public/sample/project.json`
- `public/sample/debug_report.json`
- `public/sample/floorplan.svg`
- `public/sample/walls.obj`
- `public/sample/metadata.json`

These are copied from the engine export folder. The current sample source is:

- `c_basic_building_package/`

## Copy latest exports

If you export a newer engine package, refresh the viewer sample files with:

```bash
cp c_basic_building_package/exports/floorplan.svg apps/viewer_next/public/sample/floorplan.svg
cp c_basic_building_package/debug/debug_report.json apps/viewer_next/public/sample/debug_report.json
cp c_basic_building_package/exports/walls.obj apps/viewer_next/public/sample/walls.obj
cp c_basic_building_package/project.json apps/viewer_next/public/sample/project.json
cp c_basic_building_package/metadata.json apps/viewer_next/public/sample/metadata.json
```

If your latest export lives elsewhere, copy the matching files from that export folder into `public/sample`.

## Import Flow

The viewer supports two static import paths:

1. `project.json` only.
2. `debug_report.json` plus `floorplan.svg` as a pair, with optional `project.json` and `metadata.json`.

Use the buttons in the left panel to load local files. This still does not call the engine directly; it only reads exported artifacts in the browser.

## SVG Click Selection

Click-selection works only when the SVG export embeds element ids or `data-element-id` attributes.

- If ids are present, the viewer maps them back to exported element ids and highlights the matching SVG group.
- Hovering a marked SVG group shows the kind and element id in a small tooltip.
- If ids are missing, the click falls back to an approximate screen-space marker and the right panel remains panel-driven.
- The current engine SVG export sample now embeds metadata, so wall/room/opening selection should work directly from the SVG.

## 3D View

The 3D tab reads `public/sample/walls.obj` and renders it with `three.js`.

If you update the viewer from a fresh checkout, make sure dependencies are installed:

```bash
npm install
```

The 3D tab includes orbit controls, reset camera, and a solid/wireframe toggle. It is still read-only and does not do per-element selection yet.

## Add Wall Draft

The `Add wall draft` button enables a temporary 2D preview mode:

- first click sets the draft start point
- second click sets the draft end point
- a temporary line and approximate length are shown
- press `Esc` to cancel the preview

This does not mutate `project.json` and is only a visual draft aid.

## Add Door / Add Window

The viewer also has dev-only local edit flows for hosted openings:

- `Add door` inserts a door on the currently selected wall
- `Add window` inserts a window on the currently selected wall
- the offset and size are entered manually for now
- the local helper validates the host wall and rejects overlapping or out-of-range placements

Workflow:

1. Select a wall in the SVG or the element list.
2. Click `Add door` or `Add window`.
3. Adjust offset, width, height, and sill height if needed.
4. Click `Insert door` or `Insert window`.
5. The route calls the local helper, regenerates exported artifacts, and reloads the viewer.

## Edit Selected Element

When a wall, door, or window is selected, the right panel exposes numeric edit controls:

- `Delete selected` removes the element through the local bridge.
- wall selection shows start/end axis fields plus height, thickness, and optional wall type id.
- door selection shows offset, width, and height fields.
- window selection shows offset, width, height, and sill height fields.
- `Apply axis`, `Update wall`, `Update door`, and `Update window` push the changes through the local helper and refresh the exported artifacts.
- the bridge also supports `move_hosted_opening` for direct opening offset moves, which can be wired into the UI later if needed.

Limitations:

- numeric edit only
- no drag editing yet
- local dev only
- no multi-select
- no undo UI yet

## Local Edit Bridge

`Add wall draft` can also submit to a local dev-only bridge that creates a wall, regenerates exports, and reloads the sample artifacts.

Architecture:

1. The browser sends a fixed JSON payload to `POST /api/edit/create-wall`.
2. The Next.js route validates the input and calls the fixed helper executable with `execFile`.
3. The helper loads the current project, creates the wall, recomputes rooms/schedules/validation, and exports a fresh package.
4. The route copies the exported `project.json`, `debug_report.json`, `floorplan.svg`, `walls.obj`, and `metadata.json` back into `public/sample`.
5. The viewer reloads the updated sample artifacts with a cache-busting query string.

Required env vars for the route:

- `TBE_REPO_ROOT`
- `TBE_APPLY_COMMAND`
- `TBE_WORKING_PROJECT`
- `TBE_VIEWER_SAMPLE_DIR`

Build the helper with the normal CMake preset:

```bash
cmake --build --preset dev --target tbe_apply_command
```

Suggested local development values:

- `TBE_REPO_ROOT=/Users/macbookpro/Documents/BIM-Mobile`
- `TBE_APPLY_COMMAND=/Users/macbookpro/Documents/BIM-Mobile/build/dev/apps/tbe_cli/tbe_apply_command`
- `TBE_WORKING_PROJECT=/Users/macbookpro/Documents/BIM-Mobile/apps/viewer_next/public/sample/project.json`
- `TBE_VIEWER_SAMPLE_DIR=/Users/macbookpro/Documents/BIM-Mobile/apps/viewer_next/public/sample`

Limitations:

- local dev only
- create wall only for now
- door/window offsets are manual for now
- delete and property edits use fixed JSON bridge commands
- SVG-to-wall offset mapping is approximate until a true picker is wired in
- no browser-to-C-ABI bridge
- no arbitrary shell execution from the browser
- refreshes exported artifacts, not a live in-memory engine session

## Filters

The left panel includes kind toggles. When a kind is unchecked:

- matching SVG groups are dimmed and not selectable
- the element list and category blocks are filtered to the visible kinds
- the default state is all kinds visible

## Regenerate Sample Exports

When the engine export changes, regenerate the sample files and copy them into `public/sample`:

```bash
build/dev/apps/tbe_cli/tbe_cli
cp <export-folder>/floorplan.svg apps/viewer_next/public/sample/floorplan.svg
cp <export-folder>/debug_report.json apps/viewer_next/public/sample/debug_report.json
cp <export-folder>/project.json apps/viewer_next/public/sample/project.json
cp <export-folder>/walls.obj apps/viewer_next/public/sample/walls.obj
cp <export-folder>/metadata.json apps/viewer_next/public/sample/metadata.json
```

If your export path differs, copy the latest `floorplan.svg`, `debug_report.json`, and `project.json` equivalents from that export folder. The CLI prints the export path it used.

## Run

From `apps/viewer_next`:

```bash
npm install
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000).

## Notes

- This is a temporary viewer and does not talk directly to the C ABI yet.
- SVG zoom and pan are intentionally simple.
- Screen-to-model mapping is approximate for fallback clicks and is not yet a true CAD hit-test.
- SVG selection depends on engine metadata attributes like `data-element-id`, `data-kind`, and `data-hit-kind`.
- 3D OBJ selection is not yet metadata-aware.
- Next step is to replace the static artifact flow with a live engine bridge once the macOS Flutter toolchain is fixed.
