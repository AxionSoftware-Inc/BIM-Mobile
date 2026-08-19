# viewer_flutter

RenderScene-first Flutter viewer for the TabletBimEngine UI path.

The default path loads `assets/sample_project.json` through the C API on a
worker isolate, obtains the engine-generated RenderScene in memory, shows scene
diagnostics, and hosts a renderer-neutral viewport contract.

## Scope

- load bundled `assets/sample_project.json` through the engine
- open an external RenderScene JSON file
- parse and validate the scene safely
- show object / vertex / triangle diagnostics
- show object counts by kind
- highlight/select elements from the object list
- host the native Android Filament platform view
- use the verified Flutter fallback viewport on non-Android platforms

It does **not** implement BIM editing, cloud sync, schedules, or photorealistic
rendering.

## Why Flutter + Filament

The C++ engine now exports `RenderScene` as the stable 3D scene contract. Flutter
is the future app UI path, and Filament is the native renderer planned for the
mobile/desktop viewport. The current app proves the integration shape without
making the UI depend on debug JSON, OBJ fallback files, or engine internals.

## RenderScene flow

The viewer loads a project through the engine worker or accepts a renderer-only
JSON source for tests and tooling, then:

1. shows diagnostics in Flutter,
2. sends the scene payload to the mounted native Android viewport,
3. keeps a desktop fallback preview for macOS / Linux / Windows development.

The renderer contract is intentionally neutral:

- `loadRenderScene`
- `clearScene`
- `fitCamera`
- `setVisibleKinds`
- `selectElement`
- `highlightElement`
- `setProjectionMode`
- `setOrbitProjectionStyle`
- `setDisplayStyle`

## Native renderer status

### Android

The Android host contains a platform-view registered under
`tbe/render_scene_view`. The current pass wires that view into a real Filament
scene path:

- `RenderScene` JSON is sent from Flutter to Android as JSON text.
- Android builds a runtime unlit material with Filamat.
- Each `RenderScene` object becomes a Filament renderable with its own mesh,
  bounds, kind metadata, and color.
- Engine coordinates are mapped to Filament so the model stands upright with
  Z-up from the engine becoming Y-up in Filament.
- Native logs include renderer creation, surface attach/detach, scene load
  counts, and any material-build failures.

The Android app now builds the engine C API through `android/app/CMakeLists.txt`
so `libtbe_capi.so` is packaged with the APK. APK/device validation still
requires a local Android SDK, NDK and JDK 17.

### iOS

The iOS runner no longer registers a fake native placeholder. It uses the same
Flutter fallback renderer, while the engine source falls back to the validated
RenderScene asset if the C API is not linked into the iOS process.

## Setup

Refresh Flutter packages:

```bash
cd apps/viewer_flutter
flutter pub get
```

Analyze the app:

```bash
flutter analyze
```

Run the widget tests:

```bash
flutter test
```

### Android Filament build proof

The Android side now depends on:

- `com.google.android.filament:filament-android:1.71.6`
- `com.google.android.filament:filament-utils-android:1.71.6`
- `com.google.android.filament:filamat-android:1.71.6`

The Filament runtime material is generated on-device from a small unlit source
string, so the app does not depend on a precompiled `.filamat` asset for this
first pass. The material source uses a single `baseColor` parameter and the
scene objects are uploaded as triangle meshes with position-only vertex
buffers.

#### Android runtime validation checklist

Required components:

- Android Studio
- Android SDK
- Android NDK
- CMake
- JDK 17

Useful checks:

```bash
flutter doctor -v
flutter devices
ls "$ANDROID_HOME"
ls "$ANDROID_SDK_ROOT"
./scripts/check_android_toolchain.sh
```

Build and run commands once the SDK is installed:

```bash
flutter build apk --debug
flutter run -d <android-device-or-emulator>
```

If you need to point Flutter at a custom SDK path:

```bash
flutter config --android-sdk /path/to/Android/Sdk
```

Common errors and fixes:

- `Unable to locate Android SDK`
  - install Android Studio and the Android SDK platform/tools
  - verify `ANDROID_HOME` or `ANDROID_SDK_ROOT`
- `Android NDK missing`
  - install the NDK from Android Studio SDK Manager
- `xcodebuild` / `xcrun` errors on macOS
  - switch to full Xcode with `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
- Gradle cannot resolve Filament
  - confirm `google()` and `mavenCentral()` are enabled in `android/settings.gradle.kts`
- app opens but viewport is blank
  - check the logs for `RenderSceneFilament`
  - confirm `render_scene.json` has objects and mesh data

SDK path hints:

- default macOS SDK path is usually `~/Library/Android/sdk`
- the app also respects `ANDROID_HOME` and `ANDROID_SDK_ROOT`

If Android build tooling is missing, run:

```bash
flutter doctor -v
flutter devices
flutter build apk
```

Expected blockers on this machine:

- Android SDK is missing
- Xcode is incomplete
- CocoaPods is not installed

## Engine validation

The Flutter viewer does not own the engine build, but the RenderScene export
path should stay green:

```bash
cmake --build --preset dev
ctest --preset dev --output-on-failure
```

## Sample asset

Bundled sample scene:

- `assets/render_scene.json`

The sample is copied from the engine export output and should contain walls,
doors, windows, and the rest of the RenderScene diagnostics data.

## Known limitations

- the desktop preview is a fallback, not the final renderer
- Android/iOS device builds still need toolchain smoke tests
- editing commands are exposed through the worker/repository layer, but editing
  UI tools are not implemented yet
- selection is still list-driven rather than full viewport picking

## Manual Android checklist

After installing the Android SDK, the first device/emulator smoke test should
show:

- app launches
- RenderScene diagnostics visible
- Filament viewport appears
- model is upright
- object count is greater than zero
- walls, doors, and windows are visible when present
- fit camera works
- visibility toggles do not crash the renderer
- logs mention `RenderSceneFilament` and a scene load count

## Future work

- add viewport-to-engine picking and snap feedback
- add editing panels and save/export actions
- add an iOS native Metal renderer if native GPU parity is required
