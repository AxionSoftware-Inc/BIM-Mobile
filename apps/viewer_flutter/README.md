# viewer_flutter

Minimal read-only Flutter viewer skeleton for the hardened `tbe_capi` bridge.

## Scope

This app is intentionally limited to viewer proof-of-integration work:

- load bundled sample project JSON
- load external project JSON
- call the C ABI through Dart FFI
- export SVG/package through the native bridge
- display a 2D SVG floorplan
- show version, schedule, validation, and hit-test data

It does **not** implement editing yet.

## Setup

Generate or refresh the Flutter host runners:

```bash
cd apps/viewer_flutter
flutter create . --platforms=macos,ios,android
flutter pub get
```

## Native Library Build

Build the shared C API library from the repo root:

```bash
cmake --build --preset dev --target tbe_capi_shared
```

Expected macOS output:

```text
build/dev/src/api/libtbe_capi.dylib
```

## Library Discovery

The Dart loader checks:

1. `TBE_CAPI_PATH`
2. `../../build/dev/src/api/libtbe_capi.dylib` relative to `apps/viewer_flutter`
3. nearby `build/dev/src/api/...` debug/release variants while walking up the repo tree
4. `libtbe_capi.dylib` on the dynamic loader path

Recommended launch:

```bash
cd /Users/macbookpro/Documents/BIM-Mobile
cmake --build --preset dev --target tbe_capi_shared
cd apps/viewer_flutter
export TBE_CAPI_PATH=/absolute/path/to/build/dev/src/api/libtbe_capi.dylib
flutter analyze
flutter run -d macos
```

## Sample Data

Bundled sample asset:

- `assets/sample_project.json`

The sample is intended to include:

- two rooms
- door/window
- slab
- floor/ceiling systems
- roof
- columns
- beam
- stair

## Manual Verification Checklist

- app launches
- engine version is shown
- schema version is shown
- bundled sample loads
- validation errors show `0`
- exported SVG is visible
- clicking floorplan triggers hit-test
- hit candidate list shows ordered element id / kind / hit kind / distance
- selected hit marker appears at the tapped screen position
- selected element panel updates
- schedule summary is populated
- app exits without crash

## Troubleshooting dylib Loading

- If the app opens with a native library error card, verify `build/dev/src/api/libtbe_capi.dylib` exists.
- If you launch Flutter outside `apps/viewer_flutter`, set `TBE_CAPI_PATH` explicitly.
- Rebuild the dylib after C API changes:

```bash
cmake --build --preset dev --target tbe_capi_shared
```

- If macOS blocks the library, remove stale copies and relaunch so Flutter loads the latest local build artifact.

## Known Limitations

- screen-to-model coordinate mapping is approximate and based on SVG `viewBox`
- selected hit highlighting is a screen-space marker, not a true geometry overlay
- validation detail display depends on parsing exported debug JSON when available
- no editing, snapping UI, or 3D view is implemented yet
