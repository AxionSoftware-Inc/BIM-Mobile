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
- Preserve a loaded wall's valid engine mesh during normalization. It is the
  authoritative result of C++ auto-join and opening-cut generation; replacing
  it in Flutter turns mitred joins into overlapping walls and can erase the
  interior edge loop. Rebuild only legacy walls without usable mesh data.
- When a legacy wall truly needs rebuilding, read EngineApi's scalar
  `start_x/start_y/end_x/end_y` axis metadata before falling back to bounds.
  Bounds are not an axis for a joined or diagonal wall.
- Use mesh-derived outlines instead of bounds-box diagonals.
- Cull backfaces in the Flutter fallback solid painter.
- **Android Filament Solid border contract:** render sharp semantic edges as thin, depth-tested triangle prisms. Static prisms are batched by category, level and spatial tile so large projects do not pay one extra draw call per BIM element. This is deliberately not `PrimitiveType.LINES` and not a Canvas overlay.
  - The edge mesh is visual-only; it never changes engine geometry, selection, quantities, joins, or persistence.
  - It contains only boundary / sharp architectural edges, not tessellation seams.
  - It is shown only in `solid`; `wireframe` continues to use its full edge representation.
  - The active/selected object may still use the overlay for feedback, but the normal Solid border must remain GPU depth-tested.
- The edge renderable's culling bounds must include the visual prism radius. Using only the source face bounds can cull a border during a close interior orbit even when its wall face remains visible.
  - Wall top/bottom contacts use a dedicated junction-border subset derived
    from mesh triangles, not only crease classification. Floor/ceiling faces
    can otherwise make those room-defining edges disappear through z-fighting.
  - Do not mistake a wall's top constraint for the ceiling contact. A wall can
    run to the next level while its `CeilingSystem` is lower. The renderer
    must intersect wall faces with the actual floor/ceiling elevations and
    draw those intermediate room-boundary segments as well.
  - An intermediate ceiling-contact border must be shifted a few centimetres
    down from the ceiling plane. A prism centred exactly on that plane is
    hidden by depth testing even though the intersection was calculated.
  - Never make a wall's border conditional on `featureEdges` being non-empty.
    Engine auto-join/welding can leave that cosmetic list incomplete for a
    perfectly valid wall mesh. Solid must derive the wall's top/bottom
    sections and vertical envelope corners from mesh triangles as a fallback;
    otherwise adjacent rooms and levels render with inconsistent borders.
  - Apply floor/ceiling elevations scene-wide, then reject elevations outside
    each wall's own vertical bounds. Do not group the border calculation by
    `levelId`: imported or joined wall metadata can disagree with a correctly
    placed mesh and silently omit the third-storey ceiling line.
  - Surface-system elevation extraction must include `bounds.min.z` and
    `bounds.max.z`, not only mesh vertices. Android can receive a valid
    bounds-only fallback surface; otherwise its face renders while its
    wall/ceiling border is silently omitted.

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
- T-junctions in an engine-rendered scene are handled by the core auto-join
  geometry and must remain untouched by the viewer. Local fallback
  reconstruction is intentionally a legacy repair path and may still need
  explicit trim logic for complex T/cross junctions.

## Do not regress the Android Solid border implementation

`RenderSceneFilamentHostView.kt` has two intentionally separate paths:

- `NativeSelectionOverlay`: rectangle selection, levels, Wire and selection feedback. It is **not** the production Solid-border renderer.
- `edgeGeometry(...)`: creates thin 3D edge prisms; the native renderer then combines them into category/level/spatial batches. This is the production Solid-border renderer and Filament depth testing hides occluded portions correctly.

The visual contract and the batching contract are separate. Do not restore a
per-element edge renderable merely to support selection: normal borders stay
batched, while `NativeSelectionOverlay` owns selected/highlight feedback. Edge
geometry is cached by element revision outside clipping mode, and a static
viewport must be event-driven rather than continuously rendering at 30 FPS.
Each square prism uploads only its four visible side quads; microscopic end
caps are omitted, preserving thickness/depth behavior while reducing border
triangles and indices by one third.
An unchanged RenderScene replay is fingerprinted from element IDs, revisions,
mesh cardinality, bounds and metadata and reuses the existing GPU batches.

Large native scenes (currently 256 objects and above) also batch face geometry
by material variant, category, level and 24 m spatial tile. CPU ray-picking and
the selection overlay retain element identity, while the GPU avoids one face
draw call per BIM element. Small scenes keep per-element faces for the most
direct editing path. A disabled section/section-box replay is a no-op and must
not trigger a full scene rebuild.

Repeated doors, windows and columns additionally use translation-invariant
shared face meshes. The renderer hashes normalized geometry and topology, then
places matching objects with Filament transforms and a shared material
instance. A changed size or topology naturally changes the hash and moves the
object to another group; a one-off shape falls back to the ordinary face path.
Do not group only by BIM category or nominal type: two instances may share a
type name while their generated mesh differs.

Filament automatic instancing and per-view frustum culling are explicitly
enabled. Frustum culling is a render decision for the current native View; it
must never delete or filter central RenderScene data. Section and Section Box
cuts need physically clipped meshes and cap edges, so shared instance groups
temporarily fall back to the existing clipped face batches while a clip volume
is active. Clearing the clip must recreate the instance groups and restore the
complete model.

Connected-tablet production gate (Adreno 810, debug APK): the six-building,
nine-storey template contains 1,842 BIM objects. Normal 3D mode places 972
repeated objects in 9 shared groups and resolves to 144 estimated face draws
plus 216 edge batches (360 estimated draw calls instead of roughly 3,684
per-element face/edge calls). Section Box mode intentionally returns to 234
clipped face batches plus 216 edge batches; clearing it restores the 9 instance
groups and 360-draw layout. The 103-object tower places 54 objects in 9 groups
and resolves to 58 face draws plus 33 edge batches (91 estimated draws, down
from 136 before instancing). After interaction settles, a four-second
`gfxinfo` sample must report zero newly rendered frames. Solid, Shaded,
selection overlay, orbit, Section Box cut and full-model restore were verified
on these fixtures.

Do not replace `edgeGeometry(...)` with Canvas drawing or `PrimitiveType.LINES` merely to simplify the code. Both were tried and caused the historical failures: either Solid became full Wire, or borders disappeared / flickered on Android.

## Next debugging order

1. Verify loaded scene geometry after normalization.
2. Keep painter edge logic silhouette-first.
3. Only if seams remain, improve wall-join mesh trimming in `RenderSceneEditor`.

## Native interaction and shaded materials

- Android Filament owns its live orbit camera, therefore a 3D tap is normalized in Flutter and sent to Filament over the platform channel. The native side maps that normalized point to its actual SurfaceView dimensions, ray-picks it, and sends the resulting ID back to Flutter's single selection controller. A fallback-camera hit-test can be stale after native navigation and must not overwrite the native result.
- **Critical empty-filter invariant:** an empty `visibleKinds` set means **all categories are visible and selectable**. Native pick code must check `visibleKinds.isNotEmpty()` before rejecting an object. Treating an empty set as “no categories” made every 3D ray return `null` on the connected tablet, while 2D continued to work.
- Do not depend solely on generic camera-matrix unprojection for Android hit testing. Some GLES devices expose backend-specific depth transforms. The picker uses the same eye/forward/right/up and perspective/orthographic formula as the renderer's live camera.
- The simplified wall surface can overlap its inset door/window mesh. A 3D
  ray therefore gives a same-surface opening precedence over its host wall;
  it must not select an opening that is materially farther behind the first
  hit. A live-ray miss is a real empty-space click and must clear selection.
  Do not revive the asynchronous GPU-pick fallback on the tested MIUI tablet:
  it returned stale nearby walls and prevented unselecting empty space.
- Shaded may use a separate transparent window material and a low-contrast wall material pattern. These are visual-only materials; they must not add mesh edges, affect selection, or change the Solid/Wire border contract.
