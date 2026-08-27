package com.example.viewer_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import java.io.File
import java.lang.ref.WeakReference

/**
 * Tablet-only A/B harness for the renderer migration.
 *
 * It deliberately lives below Flutter so an ADB intent can run identical JSON
 * and BIM-cache passes even while the production UI is being migrated. It is
 * not a product feature and does not alter source IFC data.
 */
internal object NativeRendererBenchmarkHarness {
  const val action = "com.example.viewer_flutter.BENCHMARK"
  private const val tag = "TbeBenchmark"

  private data class Request(
    val mode: String,
    val sourceIfcPath: String,
    val cachePath: String,
    val forceCompile: Boolean,
  )

  private var hostReference = WeakReference<RenderSceneFilamentHostView>(null)
  private var pendingRequest: Request? = null

  fun attach(host: RenderSceneFilamentHostView) {
    hostReference = WeakReference(host)
    dispatchPending()
  }

  fun detach(host: RenderSceneFilamentHostView) {
    if (hostReference.get() === host) hostReference = WeakReference(null)
  }

  fun handleIntent(context: Context, intent: Intent?) {
    if (intent?.action != action) return
    val mode = intent.getStringExtra("mode")?.trim()?.lowercase() ?: "json"
    val projects = File(context.filesDir, "projects")
    val source = intent.getStringExtra("sourceIfcPath")
      ?: File(projects, "templates/openifc-energy-tower.ifc").absolutePath
    val cache = intent.getStringExtra("cachePath")
      ?: File(projects, "ifc-cache/benchmark-openifc-energy-tower.bimcache").absolutePath
    pendingRequest = Request(
      mode = mode,
      sourceIfcPath = source,
      cachePath = cache,
      forceCompile = intent.getBooleanExtra("forceCompile", false),
    )
    if (mode == "probe") {
      runCacheProbe(pendingRequest!!)
      pendingRequest = null
      return
    }
    if (mode == "cache") {
      mountBenchmarkHost(context)
    } else {
      dispatchPending()
    }
  }

  /** Mounts the renderer directly for ADB runs; no human touch is required. */
  private fun mountBenchmarkHost(context: Context) {
    val activity = context as? Activity
    if (activity == null) {
      Log.e(tag, "BENCHMARK_ERROR cache benchmark requires an Activity")
      pendingRequest = null
      return
    }
    activity.runOnUiThread {
      val root = activity.findViewById<ViewGroup>(android.R.id.content)
      val host = RenderSceneFilamentHostView(activity, null)
      root.addView(
        host,
        FrameLayout.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.MATCH_PARENT,
        ),
      )
      attach(host)
    }
  }

  /**
   * Runs without a PlatformView so a real device can validate cache format,
   * source fingerprint and object mapping before Flutter has mounted a scene.
   * Renderer FPS measurements still use the regular [cache] benchmark mode.
   */
  private fun runCacheProbe(request: Request) {
    Thread {
      try {
        val source = File(request.sourceIfcPath)
        val cache = File(request.cachePath)
        if (!source.isFile || source.length() <= 0L) {
          Log.e(tag, "CACHE_PROBE_ERROR missing_source path=${source.absolutePath}")
          return@Thread
        }
        if (request.forceCompile && cache.exists()) cache.delete()
        var compileStats: NativeBimCacheCompileStats? = null
        if (!cache.isFile || cache.length() <= 0L) {
          cache.parentFile?.mkdirs()
          compileStats = NativeBimCacheBridge.compileFromIfc(source.absolutePath, cache.absolutePath)
          if (compileStats == null) {
            Log.e(tag, "CACHE_PROBE_ERROR cache_compile ${NativeBimCacheBridge.lastError()}")
            return@Thread
          }
        }
        val scene = NativeBimCacheBridge.describe(cache.absolutePath, source.absolutePath)
        if (scene == null) {
          Log.e(tag, "CACHE_PROBE_ERROR cache_open ${NativeBimCacheBridge.lastError()}")
          return@Thread
        }
        val objectCount = scene["object_count"] ?: 0
        val vertexCount = scene["vertex_count"] ?: 0
        val indexCount = scene["index_count"] ?: 0
        val levels = (scene["levels"] as? List<*>)?.size ?: 0
        Log.i(
          tag,
          "CACHE_PROBE valid=true compiled=${compileStats != null} " +
            "compileMs=${compileStats?.elapsedMs ?: -1L} bytes=${cache.length()} " +
            "objects=$objectCount vertices=$vertexCount indices=$indexCount levels=$levels",
        )
      } catch (error: Throwable) {
        Log.e(tag, "CACHE_PROBE_ERROR ${error.message ?: error::class.java.simpleName}", error)
      }
    }.apply {
      name = "tbe-bim-cache-probe"
      isDaemon = true
      start()
    }
  }

  private fun dispatchPending() {
    val host = hostReference.get() ?: return
    val request = pendingRequest ?: return
    pendingRequest = null
    host.post {
      when (request.mode) {
        "json" -> host.runAutomatedRendererBenchmark(mode = "OLD_JSON")
        "cache" -> compileAndRunCache(host, request)
        else -> Log.e(tag, "Unknown benchmark mode=${request.mode}; use json or cache")
      }
    }
  }

  private fun compileAndRunCache(host: RenderSceneFilamentHostView, request: Request) {
    Thread {
      try {
        val source = File(request.sourceIfcPath)
        val cache = File(request.cachePath)
        if (!source.isFile || source.length() <= 0L) {
          Log.e(tag, "BENCHMARK_ERROR missing_source path=${source.absolutePath}")
          return@Thread
        }
        if (request.forceCompile && cache.exists()) cache.delete()
        val compileStats = if (cache.isFile && cache.length() > 0L) {
          null
        } else {
          cache.parentFile?.mkdirs()
          val stats = NativeBimCacheBridge.compileFromIfc(source.absolutePath, cache.absolutePath)
          if (stats == null) {
            Log.e(tag, "BENCHMARK_ERROR cache_compile ${NativeBimCacheBridge.lastError()}")
            return@Thread
          }
          Log.i(
            tag,
            "CACHE_COMPILE elapsedMs=${stats.elapsedMs} bytes=${stats.byteSize} objects=${stats.objectCount} " +
              "triangles=${stats.triangleCount} chunks=${stats.chunkCount} primitives=${stats.primitiveCount} bvh=${stats.bvhNodeCount}",
          )
          stats
        }
        host.post {
          host.runAutomatedRendererBenchmark(
            mode = "NEW_BIMCACHE",
            sourceIfcPath = source.absolutePath,
            cachePath = cache.absolutePath,
            cacheCompileStats = compileStats,
          )
        }
      } catch (error: Throwable) {
        Log.e(tag, "BENCHMARK_ERROR ${error.message ?: error::class.java.simpleName}", error)
      }
    }.apply {
      name = "tbe-benchmark-cache-compile"
      isDaemon = true
      start()
    }
  }
}
