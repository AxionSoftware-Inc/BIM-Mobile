package com.example.viewer_flutter

import java.io.File
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {
  private var nativeEngineError: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    // A BIM session is an active authoring session. Keep the tablet awake
    // while this activity is visible so long IFC loads and inspections do
    // not get interrupted by the system's screen timeout.
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    // The C++ authoring engine is packaged by Gradle as libtbe_capi.so. Load
    // it through Android's namespace-aware loader before Dart FFI opens it;
    // relying on a bare dlopen name is device/loader-version dependent.
    try {
      System.loadLibrary("tbe_capi")
    } catch (error: UnsatisfiedLinkError) {
      nativeEngineError = error.message ?: error.javaClass.simpleName
    }
    super.onCreate(savedInstanceState)
    NativeRendererBenchmarkHarness.handleIntent(this, intent)
  }

  override fun onNewIntent(intent: android.content.Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    NativeRendererBenchmarkHarness.handleIntent(this, intent)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val registry: PlatformViewRegistry = flutterEngine.platformViewsController.registry

    // IMPORTANT — viewport stability ownership.
    //
    // Keep the stability factory here until its two invariants have been moved
    // into RenderSceneFilamentHostView itself:
    //   1) every cullable renderable/batch AABB contains every uploaded vertex
    //      in the SAME coordinate space and is transformed exactly once;
    //   2) extreme orbit zoom adapts the near plane instead of putting the
    //      orbit target on the fixed 0.12 m near plane.
    //
    // Do NOT replace this with RenderScenePlatformViewFactory merely because a
    // camera-collision or SurfaceView experiment appears to help one model.
    // The real shimmer reproduced in both 2D and 3D and even at distance, so
    // camera-vs-wall contact was not the root cause. The SurfaceView/swapchain
    // churn experiment was also reverted after it produced no improvement.
    // See docs/viewport_stability_postmortem.md before changing this boundary.
    registry.registerViewFactory(
      RenderScenePlatformViewFactory.BRIDGE_VIEW_TYPE,
      RenderSceneViewportStabilityGuardFactory(flutterEngine.dartExecutor.binaryMessenger)
    )
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tbe/app_storage")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getProjectDirectory" -> {
            val directory = File(filesDir, "projects")
            if (!directory.exists() && !directory.mkdirs()) {
              result.error("storage_unavailable", "Could not create project storage", null)
            } else {
              result.success(directory.absolutePath)
            }
          }
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tbe/native_engine")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getLibraryInfo" -> result.success(
            mapOf(
              "path" to File(applicationInfo.nativeLibraryDir, "libtbe_capi.so").absolutePath,
              "loaded" to (nativeEngineError == null),
              "error" to nativeEngineError,
            )
          )
          else -> result.notImplemented()
        }
      }
  }
}
