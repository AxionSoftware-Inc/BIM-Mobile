package com.example.viewer_flutter

import android.content.Context
import android.util.Log
import android.view.View
import com.google.android.filament.View as FilamentView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Temporary renderer isolation guard for the tablet viewport.
 *
 * The project has historically had geometry pop in/out when a renderable AABB
 * no longer matched its generated/batched geometry. The current renderer has
 * several independent face/instance/cache batching paths, so one stale AABB
 * can affect both plan and 3D navigation regardless of camera distance.
 *
 * Disable Filament's view-level frustum culling for this diagnostic build. If
 * the device becomes stable, the permanent fix is to correct the offending
 * batch bounds and remove this guard. Keeping this policy outside the renderer
 * makes the experiment completely reversible and does not change geometry,
 * camera math, materials, picking, or project data.
 */
internal class RenderSceneViewportStabilityGuardFactory(
  private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val delegate = RenderScenePlatformView(
      context,
      messenger,
      viewId,
      toSceneState(args),
    )
    applyNoCullingGuard(delegate.getView())
    return delegate
  }

  private fun applyNoCullingGuard(host: View) {
    fun applyNow() {
      try {
        val field = host.javaClass.getDeclaredField("filamentView")
        field.isAccessible = true
        val filamentView = field.get(host) as? FilamentView ?: return
        filamentView.isFrustumCullingEnabled = false
      } catch (error: Throwable) {
        Log.w(
          "RenderSceneStability",
          "Could not disable Filament frustum culling for viewport isolation.",
          error,
        )
      }
    }

    // Renderer construction is normally synchronous, but repeat after the
    // PlatformView is attached so this remains deterministic across devices.
    applyNow()
    host.post { applyNow() }
    host.postDelayed({ applyNow() }, 250L)
  }
}
