package com.example.viewer_flutter

import android.content.Context
import android.util.Log
import android.view.MotionEvent
import android.view.View
import com.google.android.filament.Camera
import com.google.android.filament.View as FilamentView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Tablet viewport stability policy.
 *
 * Two independent renderer failures are isolated here while the batching
 * implementation is being hardened:
 *
 *  1. A stale/generated AABB can make Filament's view-level frustum culling
 *     drop an otherwise valid face batch. Disabling that top-level cull keeps
 *     the viewport deterministic; native cache streaming still performs its
 *     own spatial residency policy.
 *
 *  2. The renderer normally keeps a 12 cm near plane for strong depth
 *     precision. At the deepest allowed inspection the orbit eye can also be
 *     12 cm from its target, placing the target itself on the near plane. A
 *     wall crossed at that point is then clipped on alternating gesture
 *     samples. Only while the regular near-plane floor is active, shrink that
 *     floor smoothly with the orbit distance. This is not a camera collision
 *     limit: the camera may still enter geometry and leave it again.
 *
 * Historical false leads — DO NOT reintroduce these as generic flicker fixes:
 *
 *  - Camera-vs-wall collision/minimum-distance clamps. The reproduced bug also
 *    happened in 2D and while the camera was far from walls, so physical wall
 *    contact cannot be the common cause. A clamp can only hide one close view.
 *  - TextureView -> SurfaceView plus aggressive swap-chain recreation. That
 *    experiment was tested on-device and did not improve the shimmer; it also
 *    adds presentation churn. Recreate a swap chain only when the native
 *    surface itself actually changes.
 *  - Arbitrary AABB padding. Generated geometry must report the bounds of the
 *    vertices it really uploads. Padding is not a substitute for a correct
 *    coordinate-space invariant.
 *  - Wider edge ribbons. These ribbons are triangle geometry; widening them
 *    until they straddle the lifted source face recreates a competing surface
 *    and can bring z-fighting back.
 *
 * The normal camera range is left untouched, so the depth precision that made
 * ordinary 2D/3D navigation stable is preserved. See
 * docs/viewport_stability_postmortem.md before changing this policy.
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
    applyStabilityPolicy(delegate.getView())
    return delegate
  }

  private data class Point3(val x: Double, val y: Double, val z: Double)

  private data class Bounds3(val min: Point3, val max: Point3)

  private fun applyStabilityPolicy(host: View) {
    applyNoCullingGuard(host)
    RenderSceneWallSurfaceProjection.install(host)
    wrapNativeCameraTouch(host)

    // Renderer construction is synchronous today, but repeat after attach so
    // the policy remains deterministic across Android/Flutter lifecycle paths.
    host.post {
      applyNoCullingGuard(host)
      RenderSceneWallSurfaceProjection.install(host)
      stabilizeCloseProjection(host)
    }
    host.postDelayed({
      applyNoCullingGuard(host)
      RenderSceneWallSurfaceProjection.install(host)
      stabilizeCloseProjection(host)
    }, 250L)
  }

  private fun applyNoCullingGuard(host: View) {
    try {
      val filamentView = field(host, "filamentView") as? FilamentView ?: return
      filamentView.isFrustumCullingEnabled = false
    } catch (error: Throwable) {
      Log.w(
        TAG,
        "Could not disable Filament frustum culling for viewport stability.",
        error,
      )
    }
  }

  /**
   * Keep the host's existing native gesture path, then correct only the close
   * projection before Filament submits the frame. This avoids a frame-loop
   * polling workaround and has zero idle cost.
   */
  private fun wrapNativeCameraTouch(host: View) {
    try {
      val renderSurface = field(host, "renderSurface") as? View ?: return
      val handleTouch = host.javaClass
        .getDeclaredMethod("handleTouchEvent", MotionEvent::class.java)
        .apply { isAccessible = true }

      renderSurface.setOnTouchListener { _, event ->
        val handled = (handleTouch.invoke(host, event) as? Boolean) ?: false
        stabilizeCloseProjection(host)
        handled
      }
    } catch (error: Throwable) {
      Log.w(TAG, "Could not install close-camera projection guard.", error)
    }
  }

  /**
   * Mirrors RenderSceneFilamentHostView.cameraDepthRange, but changes only the
   * branch where its 0.12 m near-plane floor is active.
   *
   * At orbitDistance=0.12 m the old near plane was also 0.12 m, so the orbit
   * target sat exactly on the clipping plane. The adaptive floor below is
   * continuous: 8% of eye-to-target distance, with a 5 mm numerical floor.
   * At 1.5 m it naturally becomes the original 0.12 m value and therefore has
   * no effect on ordinary navigation.
   */
  private fun stabilizeCloseProjection(host: View) {
    try {
      val projectionMode = field(host, "projectionMode") as? String ?: return
      if (projectionMode != "isometric") return

      val distance = (field(host, "orbitDistance") as? Number)?.toDouble() ?: return
      if (!distance.isFinite() || distance <= 0.0 || distance >= CLOSE_RANGE_METERS) return

      val center = point(field(host, "orbitCenter")) ?: return
      val yaw = (field(host, "orbitYawRadians") as? Number)?.toDouble() ?: return
      val pitch = (field(host, "orbitPitchRadians") as? Number)?.toDouble() ?: return
      val bounds = sceneBounds(host) ?: return
      val camera = field(host, "camera") as? Camera ?: return
      val style = field(host, "orbitProjectionStyle") as? String ?: return

      val span = max(
        bounds.max.x - bounds.min.x,
        max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
      ).coerceAtLeast(0.001)

      val cosPitch = cos(pitch)
      val eye = Point3(
        center.x + distance * cosPitch * cos(yaw),
        center.y + distance * sin(pitch),
        center.z + distance * cosPitch * sin(yaw),
      )
      val forward = normalize(
        Point3(center.x - eye.x, center.y - eye.y, center.z - eye.z),
      ) ?: return

      val depths = corners(bounds).map { corner ->
        dot(
          Point3(corner.x - eye.x, corner.y - eye.y, corner.z - eye.z),
          forward,
        )
      }
      val minDepth = depths.minOrNull() ?: return
      val maxDepth = depths.maxOrNull() ?: return
      val safetyMargin = max(span * 0.04, 0.10)
      val rawNear = minDepth - safetyMargin

      // If the scene itself provides a safe positive near distance, preserve
      // the renderer's normal depth-precision path exactly. We intervene only
      // when the fixed 12 cm floor would have been selected.
      if (rawNear > NORMAL_NEAR_METERS) return

      val adaptiveFloor = max(MIN_NEAR_METERS, distance * CLOSE_NEAR_RATIO)
      val near = max(adaptiveFloor, rawNear)
      val sceneFar = max(
        near + max(span * 1.25, 4.0),
        maxDepth + safetyMargin,
      )
      val far = max(sceneFar, distance + max(span * 1.75, 10.0))
      if (!near.isFinite() || !far.isFinite() || far <= near) return

      val aspect = host.width.coerceAtLeast(1).toDouble() /
        host.height.coerceAtLeast(1).toDouble()
      if (style == "orthographic") {
        val halfHeight = max(distance * 0.6, 2.0)
        val halfWidth = halfHeight * aspect
        camera.setProjection(
          Camera.Projection.ORTHO,
          -halfWidth,
          halfWidth,
          -halfHeight,
          halfHeight,
          near,
          far,
        )
      } else {
        camera.setProjection(45.0, aspect, near, far, Camera.Fov.VERTICAL)
      }

      // Selection/section overlays consume Filament's exact projection matrix.
      // Refresh them after the corrected camera projection so the visual and
      // hit-test camera remain a single authority even at extreme zoom.
      host.javaClass.getDeclaredMethod("syncVisualOverlay")
        .apply { isAccessible = true }
        .invoke(host)
    } catch (error: Throwable) {
      Log.w(TAG, "Close-camera projection stabilization failed.", error)
    }
  }

  private fun sceneBounds(host: View): Bounds3? {
    val metrics = field(host, "sceneMetrics") ?: return null
    val bounds = field(metrics, "bounds") ?: return null
    val minPoint = point(field(bounds, "min")) ?: return null
    val maxPoint = point(field(bounds, "max")) ?: return null
    return Bounds3(minPoint, maxPoint)
  }

  private fun point(value: Any?): Point3? {
    value ?: return null
    val x = (field(value, "x") as? Number)?.toDouble() ?: return null
    val y = (field(value, "y") as? Number)?.toDouble() ?: return null
    val z = (field(value, "z") as? Number)?.toDouble() ?: return null
    if (!x.isFinite() || !y.isFinite() || !z.isFinite()) return null
    return Point3(x, y, z)
  }

  private fun field(target: Any, name: String): Any? {
    val declared = target.javaClass.getDeclaredField(name)
    declared.isAccessible = true
    return declared.get(target)
  }

  private fun corners(bounds: Bounds3): List<Point3> = listOf(
    Point3(bounds.min.x, bounds.min.y, bounds.min.z),
    Point3(bounds.max.x, bounds.min.y, bounds.min.z),
    Point3(bounds.max.x, bounds.max.y, bounds.min.z),
    Point3(bounds.min.x, bounds.max.y, bounds.min.z),
    Point3(bounds.min.x, bounds.min.y, bounds.max.z),
    Point3(bounds.max.x, bounds.min.y, bounds.max.z),
    Point3(bounds.max.x, bounds.max.y, bounds.max.z),
    Point3(bounds.min.x, bounds.max.y, bounds.max.z),
  )

  private fun dot(first: Point3, second: Point3): Double =
    first.x * second.x + first.y * second.y + first.z * second.z

  private fun normalize(value: Point3): Point3? {
    val length = kotlin.math.sqrt(dot(value, value))
    if (!length.isFinite() || length <= 1.0e-9) return null
    return Point3(value.x / length, value.y / length, value.z / length)
  }

  private companion object {
    const val TAG = "RenderSceneStability"
    const val NORMAL_NEAR_METERS = 0.12
    const val MIN_NEAR_METERS = 0.005
    const val CLOSE_NEAR_RATIO = 0.08
    const val CLOSE_RANGE_METERS = NORMAL_NEAR_METERS / CLOSE_NEAR_RATIO
  }
}
