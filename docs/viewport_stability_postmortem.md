# Android viewport stability: shimmer/flicker postmortem

This note exists so the same renderer regressions are not reintroduced during future camera, batching, or Android-surface work.

## Symptom that changed the diagnosis

The reported shimmer reproduced in **both 2D and 3D**, and it also reproduced while the camera was not physically close to a wall. That observation rules out camera-wall collision as the common root cause. A collision clamp can hide a close-zoom symptom, but it cannot explain distant 2D and 3D instability.

## What was actually fixed / guarded

### 1. Generated edge geometry must own its real bounds

`RenderSceneEdgeGeometry.kt` generates triangle ribbons, not mathematical screen-space lines. Isometric wall edges are lifted away from faces and some junction construction can move vertices several centimetres outside the source face.

The old implementation used source bounds with a fixed margin. That margin did **not** contain every generated edge vertex. Filament could therefore reject and re-admit the same batch on adjacent frames while the camera moved. Visually this looks like depth-buffer shimmer even when the depth buffer is behaving correctly.

Current invariant:

> The AABB submitted for culling must contain every uploaded generated vertex in the same coordinate space.

The generated-edge bounds are now accumulated from the actual ribbon vertices. The 3D wall ribbon half-width was also reduced from the old broad overlay to 3 mm so the ribbon cannot straddle the wall surface despite its 6–8 mm lift.

### 2. Culling bounds must be transformed exactly once

This project has previously had two related culling bugs:

- Filament `Box` was treated as min/max when it actually expects center + half-extent.
- Render geometry bounds were converted/transformed a second time after the geometry had already entered renderer coordinates.

Both mistakes can make a valid renderable disappear and reappear during orbit/pan.

The current `RenderSceneViewportStabilityGuard` therefore keeps view-level Filament frustum culling disabled until every batch path has a verified AABB invariant. Native cache residency is separate from this guard.

Before re-enabling global culling, verify **every** render path, including:

- individual face renderables;
- combined face batches;
- instance groups;
- clipped/rebuilt geometry;
- edge batches;
- native-cache chunks.

For each path, assert that all uploaded vertices are inside the exact `RenderableManager.Builder.boundingBox` supplied for that renderable after the intended transform, and that no second coordinate conversion is applied.

### 3. Extreme zoom must adapt the near plane, not fake a collision

The normal renderer uses a 0.12 m near-plane floor for good depth precision. At the deepest legal orbit zoom, the eye-to-target distance could also reach 0.12 m, which puts the orbit target itself on the clipping plane.

`RenderSceneViewportStabilityGuard` changes only this extreme-close branch. It uses an adaptive near floor of roughly 8% of eye-to-target distance, with a 5 mm numerical minimum. At ordinary distances the original 0.12 m path remains unchanged.

This is intentionally **not** a camera collision system. The camera is allowed to enter and leave geometry. That keeps inspection predictable and avoids hiding renderer defects behind arbitrary movement limits.

## Experiments that did not fix the root problem

Do not repeat these as a generic shimmer fix without new evidence:

1. **Camera-wall collision / larger minimum orbit distance.** The bug also happened far from walls and in 2D.
2. **TextureView → SurfaceView migration solely to stop shimmer.** The experiment also added aggressive swapchain destruction/recreation and resize render bursts; the user observed no improvement, so it was reverted.
3. **Aggressive swapchain churn.** Recreating a swapchain on normal view updates adds another source of presentation instability. Recreate only when the native surface really changes.
4. **Widening edge ribbons.** Edge ribbons are geometry. A half-width larger than the face lift can create a second competing surface and bring z-fighting back.
5. **Adding arbitrary source-bounds padding.** Padding is not a proof. Generated bounds must be computed from generated geometry.
6. **Transforming AABBs independently from their vertex buffers.** Vertex data and culling bounds must live in the same coordinate system and share one transform authority.

## Stable renderer rules

- Keep Android `TextureView` unless a separately reproduced platform-composition defect proves that the surface type itself is wrong.
- Keep one camera authority during native 3D gestures. Flutter must not replay stale orbit snapshots over the live native camera.
- Keep projection, selection overlay, and picking synchronized from the same corrected camera matrix.
- Prefer continuous mathematical fixes (adaptive near plane, exact generated bounds) over hard clamps that create discontinuities during touch gestures.
- When diagnosing a future shimmer, first isolate **faces / edges / materials / shadows**, then **culling**, then **presentation/compositor**. Do not start by changing camera collision.

## Removal condition for `RenderSceneViewportStabilityGuard`

The guard may be removed only when both of these are implemented directly in the renderer and covered by regression tests:

1. all cullable batches have verified exact AABBs and view-level frustum culling can be enabled without pop/flicker across 2D/3D camera movement;
2. the host's native camera projection itself owns the adaptive extreme-close near plane and overlays/picking consume that same projection.

When those conditions are met, move the logic into `RenderSceneFilamentHostView`, remove the reflection guard, and keep this document as the regression checklist.
