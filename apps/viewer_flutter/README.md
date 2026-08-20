# viewer_flutter

Flutter BIM authoring application for TabletBimEngine. Android uses the
native Filament viewport; macOS, Linux and Windows keep a renderer-neutral
Flutter fallback for development and tests.

## Current capabilities

- engine-backed project templates, save/reload and RenderScene snapshots;
- 3D, floor-plan, elevation and section views with view tabs and Project
  Browser;
- touch-first wall drawing with grid/endpoint/orthogonal snapping, chaining,
  wall move and Trim / Extend;
- door, window, floor, ceiling, roof, stair and level authoring tools;
- Pick Walls, Boundary, Rectangle and Auto Room surface workflows;
- level elevation and wall/opening constraints through engine transactions;
- Inspector, material/assembly editing, quantity estimates and selection;
- documentation sheets, view placement and PDF export.

The Android path is engine-first: Flutter collects and previews a gesture,
tool controllers validate transient geometry, the native repositories submit a
semantic transaction, and the engine returns the authoritative RenderScene
snapshot. The fallback editor is retained only for platforms without the
native library and for deterministic unit/widget tests.

## Layer boundaries

- `tools/` and `plan_sketch_geometry.dart` — reusable authoring geometry,
  snapping, orthogonal rules and tool draft state;
- `render_scene_viewport*` and `viewer_viewport_*` — projection, gestures,
  hit testing, painting and touch interaction;
- `tbe_authoring_mutation_repository.dart` — semantic engine mutations;
- `tbe_scene_query_repository.dart` — read-only scene queries and spatial
  picking;
- `tbe_project_persistence_repository.dart` — project save/load;
- `tbe_ffi_api_methods.dart`, `tbe_ffi_bindings.dart` and `tbe_ffi.dart` —
  native C API composition;
- `src/core` and `src/api` — semantic model, validation, geometry, joins,
  constraints and authoritative snapshots.

Run the architecture guard from the repository root:

```bash
bash tools/check_architecture.sh
```

## Local setup

```bash
cd apps/viewer_flutter
flutter pub get
flutter analyze
flutter test
```

Validate the native engine from the repository root:

```bash
cmake --preset dev
cmake --build --preset dev
ctest --preset dev --output-on-failure
```

Build and run Android:

```bash
cd apps/viewer_flutter
flutter build apk --debug
flutter run -d <android-device-or-emulator>
```

Android requires Android SDK/NDK, CMake and JDK 17. Filament dependencies are
resolved from Google Maven and Maven Central. The native host uses Filament
1.71.6 and packages `libtbe_capi` from the engine CMake build.

## Native renderer

`RenderSceneFilamentHostView.kt` receives the engine snapshot through the
platform-view contract and uploads meshes, metadata, visibility filters,
selection/highlight state and cached lighting to Filament. Engine coordinates
are mapped to Filament with the engine's Z-up convention preserved visually.

iOS currently contains the same platform-view boundary with a placeholder
renderer; Metal implementation is still future work.

## Known limitations

- the fallback geometry backend is deterministic mesh geometry, not a full CAD
  solid/boolean kernel;
- native Android scene loading can skip frames for very large first snapshots,
  so streaming and warm-up performance still need tuning;
- the fallback editor and native engine must remain behaviorally aligned until
  all supported desktop targets have a native engine package;
- iOS native rendering and cloud collaboration are not implemented yet.
