# Arvela release hardening. Dart code is obfuscated separately with Flutter's
# --obfuscate/--split-debug-info flags; these rules protect the Android/Kotlin
# bridge while leaving R8 free to shrink and rename the rest of the app.

# Android entry points and the platform-view factory are reached by Android or
# Flutter through framework callbacks rather than ordinary Java call sites.
-keep class com.example.viewer_flutter.MainActivity { *; }
-keep class com.example.viewer_flutter.RenderScenePlatformViewFactory { *; }
-keep class com.example.viewer_flutter.RenderSceneViewportStabilityGuardFactory { *; }

# The release stability policy deliberately reaches a few private renderer
# members through a narrow reflection boundary. Keep only those names so the
# policy still works after R8 while the rest of the host remains obfuscated.
-keepclassmembers class com.example.viewer_flutter.RenderSceneFilamentHostView {
    <fields>;
    *** handleTouchEvent(android.view.MotionEvent);
    *** syncVisualOverlay();
    *** rebuildScene();
    *** syncVisibility();
    *** refreshTintState();
    *** requestRender(long);
}
-keepclassmembers class com.example.viewer_flutter.FilamentSceneMetrics {
    <fields>;
}
-keepclassmembers class com.example.viewer_flutter.SceneBounds {
    <fields>;
}
-keepclassmembers class com.example.viewer_flutter.ScenePoint {
    <fields>;
}

# NativeBimCacheBridge uses the legacy JNI name-based lookup contract. Keeping
# this exact class and its external methods is required for release builds.
-keep class com.example.viewer_flutter.NativeBimCacheBridge { *; }
-keepnames class com.example.viewer_flutter.NativeBimCacheBridge

# Filament has native-backed entry points and reflective material/platform
# bindings. Its AAR supplies additional rules; this narrow keep prevents R8
# from stripping the public bridge classes used by the renderer.
-keep class com.google.android.filament.Engine { *; }
-keep class com.google.android.filament.EntityManager { *; }
-keep class com.google.android.filament.Material { *; }
-keep class com.google.android.filament.MaterialInstance { *; }
-keep class com.google.android.filament.RenderableManager { *; }
-keep class com.google.android.filament.TransformManager { *; }
-keep class com.google.android.filament.View { *; }
-keep class com.google.android.filament.Scene { *; }
-keep class com.google.android.filament.SwapChain { *; }

# Preserve annotated Android/Flutter callback members without disabling
# obfuscation for unrelated application code.
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}

-dontwarn javax.annotation.**
