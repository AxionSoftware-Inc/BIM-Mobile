# viewer_flutter

RenderScene-first Flutter viewer skeleton for the TabletBimEngine UI path.

This app is intentionally minimal. It loads `render_scene.json`, shows scene
diagnostics, and hosts a renderer-neutral viewport contract that is ready for a
native Filament implementation.
The older C ABI / FFI hooks stay in the package for future engine/status work,
but they are not the primary 3D source in this pass.

## Scope

- load bundled `assets/render_scene.json`
- open an external RenderScene JSON file
- parse and validate the scene safely
- show object / vertex / triangle diagnostics
- show object counts by kind
- highlight/select elements from the object list
- host a native Android platform-view skeleton
- keep an iOS placeholder structure ready

It does **not** implement BIM editing, cloud sync, schedules, or photorealistic
rendering.

## Why Flutter + Filament

The C++ engine now exports `RenderScene` as the stable 3D scene contract. Flutter
is the future app UI path, and Filament is the native renderer planned for the
mobile/desktop viewport. The current app proves the integration shape without
making the UI depend on debug JSON, OBJ fallback files, or engine internals.

## RenderScene flow

The viewer loads `assets/render_scene.json` or a local file path, parses it in
Dart, and then:

1. shows diagnostics in Flutter,
2. sends the scene payload to the native Android Filament viewport by default,
3. keeps a desktop fallback preview for macOS / Linux / Windows development.

The renderer contract is intentionally neutral:

- `loadRenderScene`
- `clearScene`
- `fitCamera`
- `setVisibleKinds`
- `selectElement`
- `highlightElement`

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
- Android now uses the Filament viewport as the primary renderer path.

The local machine that produced this checkout does **not** have a complete
Android SDK installed, so I could not run `flutter build apk` or launch on a
device here. The code is structured for a normal Android Studio / SDK / NDK /
JDK setup and should be the first native target once that toolchain is present.

### iOS

The iOS runner includes a placeholder platform-view structure with the same
Dart-facing contract, but full native rendering is deferred until the toolchain
is available.

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
- Android Filament rendering is wired in code, but the local SDK/toolchain was
  not available here to run the APK proof
- iOS is placeholder-only for now
- no editing tools are implemented in this app
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

- harden Android Filament rendering and add picking/highlight
- add iOS/Metal rendering
- connect live selection and editing after the renderer is stable
