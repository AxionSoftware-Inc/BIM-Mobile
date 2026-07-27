package com.example.viewer_flutter

import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {
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
