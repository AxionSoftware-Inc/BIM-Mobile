# Viewer Rendering Notes

This file tracks rendering-specific issues we hit in the Flutter fallback CAD/3D viewport and Android Filament renderer so future edits do not reintroduce them.

## Confirmed problems

- `render_scene.json` sample objects can arrive without wall/opening `metadata`.
- Hot reload can leave the previous in-memory scene active unless the scene is reloaded explicitly.
- The Flutter fallback painter does not have a real GPU depth buffer or native backface culling.
- Drawing every mesh edge in `solid` mode makes walls look hollow, exposes opening tunnel lines, and shows false seam lines at joins.
- Bounding-box outlines create fake diagonal cage lines that are not real wall edges.
- Android GLES drivers frequently clamp `PrimitiveType.LINES` to one physical pixel. It cannot provide a usable Revit-like Solid border on tablets.
- A Flutter/Android Canvas overlay has no access to Filament's depth buffer. It therefore cannot reliably decide whether an edge is hidden behind another object.

## Fixes already applied

- Reload the scene during `reassemble()` so hot reload reflects current geometry.
- Normalize loaded wall/opening geometry through `RenderSceneEditor.normalizeSceneGeometry(...)`.
- Rebuild walls even when metadata is missing by deriving wall axes and opening host/offset data from bounds/mesh.
- Use mesh-derived outlines instead of bounds-box diagonals.
- Cull backfaces in the Flutter fallback solid painter.
- **Android Filament Solid border contract:** render sharp semantic edges as a single, thin, depth-tested triangle mesh per BIM element. This is deliberately not `PrimitiveType.LINES` and not a Canvas overlay.
  - The edge mesh is visual-only; it never changes engine geometry, selection, quantities, joins, or persistence.
  - It contains only boundary / sharp architectural edges, not tessellation seams.
  - It is shown only in `solid`; `wireframe` continues to use its full edge representation.
  - The active/selected object may still use the overlay for feedback, but the normal Solid border must remain GPU depth-tested.

## Current rendering rule

- `wireframe` may show all mesh edges.
- `solid` should behave like a solid viewport:
  - front-facing surfaces only
  - depth-tested sharp architectural edges, with no full hidden/internal edge display
  - no fake bounding-box diagonals
  - walls/doors/windows should not draw default full outlines unless selected or highlighted

## Known sensitive areas

- Door/window tunnel edges can look wrong if we draw all visible crease edges.
- Wall joins can show seams if we render all coplanar/crease edges instead of silhouette-only edges.
- T-junctions depend on fallback wall reconstruction and may need explicit trim logic later.

## Do not regress the Android Solid border implementation

`RenderSceneFilamentHostView.kt` has two intentionally separate paths:

- `NativeSelectionOverlay`: rectangle selection, levels, Wire and selection feedback. It is **not** the production Solid-border renderer.
- `edgeGeometry(...)`: batches thin 3D edge prisms and is the production Solid-border renderer. Filament depth testing hides occluded portions correctly.

Do not replace `edgeGeometry(...)` with Canvas drawing or `PrimitiveType.LINES` merely to simplify the code. Both were tried and caused the historical failures: either Solid became full Wire, or borders disappeared / flickered on Android.

## Next debugging order

1. Verify loaded scene geometry after normalization.
2. Keep painter edge logic silhouette-first.
3. Only if seams remain, improve wall-join mesh trimming in `RenderSceneEditor`.
