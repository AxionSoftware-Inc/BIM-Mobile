# Filament Renderer Plan

`RenderScene` is the bridge between the C++ BIM engine and the future Flutter
UI. The long-term renderer path is:

1. C++ engine exports `render_scene.json`.
2. Flutter parses the scene and owns the app UI.
3. A native renderer consumes the scene data.
4. Filament becomes the Android/mobile 3D backend.

## Why this exists

- keep the UI contract stable even while engine internals evolve
- avoid depending on `debug_report.json`, OBJ fallback files, or ad-hoc scene
  inspection
- keep the renderer swappable without changing the engine or the main app UI

## Current state

- Flutter loads and validates `RenderScene` in Dart.
- Android has a native platform-view bridge that accepts scene data and is
  wired for a Filament-based render path.
- The first Android pass uses a runtime-built unlit Filament material and
  uploads `RenderScene` meshes as real renderables.
- iOS has a placeholder structure and the same Dart-facing contract.

## Coordinate system

- Engine / `RenderScene`: `X/Y` are the plan plane and `Z` is vertical up.
- Flutter UI: same logical scene data, used for diagnostics and selection.
- Native 3D renderer: `X/Z` is the ground plane and `Y` is up. The Android
  renderer remaps engine coordinates into this space so walls stand upright.

## Android proof path

The first Android renderer proof is intentionally simple:

- `RenderScene` JSON is passed from Flutter to Android.
- Android creates a single flat-color Filament material at runtime using
  Filamat.
- Each object is uploaded as a Filament renderable with position-only vertex
  buffers and triangle indices.
- Object kind metadata is preserved separately in native state for future
  selection/highlight work.

This path proves the Flutter app can host a native Filament viewport without
tying the UI to `debug_report.json` or OBJ fallbacks.

## Renderer contract

The Flutter side talks to a renderer-neutral interface:

- `loadRenderScene`
- `clearScene`
- `fitCamera`
- `setVisibleKinds`
- `selectElement`
- `highlightElement`

The final Filament backend should honor the same contract so the UI does not
need renderer-specific code.

## Chunking and level strategy

The first implementation can render the scene as a flat list grouped by kind
and level. A future optimization pass can:

- stream by level
- cull invisible kinds
- chunk large object sets by floor or spatial bucket
- keep selection metadata separate from geometry buffers

## Limitations

- not a full scene graph
- not a final material system
- no shadows or post-processing yet
- no advanced selection/picking in native renderer yet
- no editing workflow is attached to this renderer pass yet
- Android build validation is blocked on local SDK availability on this machine
