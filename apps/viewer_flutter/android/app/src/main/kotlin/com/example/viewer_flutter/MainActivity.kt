package com.example.viewer_flutter

import java.io.File
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // The C++ authoring engine is packaged by Gradle as libtbe_capi.so. Load
    // it through Android's namespace-aware loader before Dart FFI opens it;
    // relying on a bare dlopen name is device/loader-version dependent.
    System.loadLibrary("tbe_capi")
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val registry: PlatformViewRegistry = flutterEngine.platformViewsController.registry
    registry.registerViewFactory(
      RenderScenePlatformViewFactory.BRIDGE_VIEW_TYPE,
      RenderScenePlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
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
  }
}
