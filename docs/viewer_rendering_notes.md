# Viewer Rendering Notes

This file tracks rendering-specific issues we hit in the Flutter fallback CAD/3D viewport so future edits do not reintroduce them.

## Confirmed problems

- `render_scene.json` sample objects can arrive without wall/opening `metadata`.
- Hot reload can leave the previous in-memory scene active unless the scene is reloaded explicitly.
- The Flutter fallback painter does not have a real GPU depth buffer or native backface culling.
- Drawing every mesh edge in `solid` mode makes walls look hollow, exposes opening tunnel lines, and shows false seam lines at joins.
- Bounding-box outlines create fake diagonal cage lines that are not real wall edges.

## Fixes already applied

- Reload the scene during `reassemble()` so hot reload reflects current geometry.
- Normalize loaded wall/opening geometry through `RenderSceneEditor.normalizeSceneGeometry(...)`.
- Rebuild walls even when metadata is missing by deriving wall axes and opening host/offset data from bounds/mesh.
- Use mesh-derived outlines instead of bounds-box diagonals.
- Cull backfaces in the Flutter fallback solid painter.

## Current rendering rule

- `wireframe` may show all mesh edges.
- `solid` should behave like a solid viewport:
  - front-facing surfaces only
  - silhouette edges preferred over full hidden/internal edge display
  - no fake bounding-box diagonals
  - walls/doors/windows should not draw default full outlines unless selected or highlighted

## Known sensitive areas

- Door/window tunnel edges can look wrong if we draw all visible crease edges.
- Wall joins can show seams if we render all coplanar/crease edges instead of silhouette-only edges.
- T-junctions depend on fallback wall reconstruction and may need explicit trim logic later.

## Next debugging order

1. Verify loaded scene geometry after normalization.
2. Keep painter edge logic silhouette-first.
3. Only if seams remain, improve wall-join mesh trimming in `RenderSceneEditor`.
