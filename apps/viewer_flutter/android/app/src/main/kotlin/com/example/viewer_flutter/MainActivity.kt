package com.example.viewer_flutter

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val registry: PlatformViewRegistry = flutterEngine.platformViewsController.registry
    registry.registerViewFactory(
      RenderScenePlatformViewFactory.BRIDGE_VIEW_TYPE,
      RenderScenePlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
    )
  }
}
