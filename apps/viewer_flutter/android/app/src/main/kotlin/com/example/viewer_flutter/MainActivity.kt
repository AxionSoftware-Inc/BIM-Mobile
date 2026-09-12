package com.example.viewer_flutter

import java.io.File
import java.io.OutputStreamWriter
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {
  private data class PendingTextExport(
    val result: MethodChannel.Result,
    val contents: String,
  )

  companion object {
    private const val FILE_EXPORT_REQUEST_CODE = 4801
  }

  private var nativeEngineError: String? = null
  private var pendingTextExport: PendingTextExport? = null

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
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tbe/file_export")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "saveTextFile" -> beginTextFileExport(call.arguments, result)
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

  private fun beginTextFileExport(arguments: Any?, result: MethodChannel.Result) {
    if (pendingTextExport != null) {
      result.error("export_busy", "Another file export is already in progress", null)
      return
    }
    val values = arguments as? Map<*, *>
    val fileName = values?.get("fileName") as? String
    val mimeType = values?.get("mimeType") as? String ?: "text/plain"
    val contents = values?.get("contents") as? String
    if (fileName.isNullOrBlank() || contents == null) {
      result.error("invalid_export", "A file name and text contents are required", null)
      return
    }

    pendingTextExport = PendingTextExport(result, contents)
    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
      addCategory(Intent.CATEGORY_OPENABLE)
      type = mimeType
      putExtra(Intent.EXTRA_TITLE, fileName)
    }
    try {
      startActivityForResult(intent, FILE_EXPORT_REQUEST_CODE)
    } catch (error: Exception) {
      pendingTextExport = null
      result.error("export_unavailable", error.message, null)
    }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode == FILE_EXPORT_REQUEST_CODE) {
      val pending = pendingTextExport
      pendingTextExport = null
      if (pending != null) {
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
          pending.result.success(null)
        } else {
          try {
            val uri = data.data!!
            contentResolver.openOutputStream(uri)?.use { output ->
              OutputStreamWriter(output, Charsets.UTF_8).use { writer ->
                writer.write(pending.contents)
              }
            } ?: throw IllegalStateException("Could not open the selected file")
            pending.result.success(uri.toString())
          } catch (error: Exception) {
            pending.result.error("export_failed", error.message, null)
          }
        }
      }
    }
    super.onActivityResult(requestCode, resultCode, data)
  }
}
