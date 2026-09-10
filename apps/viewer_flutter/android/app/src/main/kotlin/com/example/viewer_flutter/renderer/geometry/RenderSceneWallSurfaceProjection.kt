package com.example.viewer_flutter

import android.util.Log
import android.view.View
import com.google.android.filament.Engine
import com.google.android.filament.Material
import com.google.android.filament.filamat.MaterialBuilder
import com.google.android.filament.filamat.MaterialPackage
import java.util.WeakHashMap

/**
 * Installs orientation-stable wall surface projection without changing BIM
 * geometry or the renderer's streaming policy.
 *
 * The original procedural brick cue used world.x as its horizontal coordinate.
 * That is correct only for one wall orientation; a wall/end-cap whose face
 * tangent is mostly Z receives almost no horizontal variation and the bricks
 * visibly stretch. The shader below derives a local horizontal tangent from
 * the actual face normal and measures the pattern in world metres along that
 * tangent. Front/back/side faces therefore keep the same physical brick size.
 *
 * This is intentionally not texture streaming. The brick cue is procedural and
 * has no bitmap to upload. Geometry/cache revisions remain the batching
 * boundary, while every static frame simply samples an immutable material.
 */
internal object RenderSceneWallSurfaceProjection {
  private const val TAG = "WallSurfaceProjection"
  private val installed = WeakHashMap<View, Boolean>()

  @Synchronized
  fun install(host: View) {
    if (installed[host] == true) return
    try {
      val engine = field(host, "engine") as? Engine ?: return
      val previous = field(host, "wallMaterial") as? Material ?: return
      val replacement = buildWallMaterial(engine) ?: return
      var committed = false
      try {
        setField(host, "wallMaterial", replacement)
        invokeNoArg(host, "rebuildScene")
        invokeNoArg(host, "syncVisibility")
        invokeNoArg(host, "refreshTintState")
        invokeLong(host, "requestRender", 180L)
        host.invalidate()
        installed[host] = true
        committed = true
        engine.destroyMaterial(previous)
        Log.i(TAG, "Installed local-tangent procedural wall projection.")
      } finally {
        if (!committed) {
          try {
            setField(host, "wallMaterial", previous)
          } catch (_: Throwable) {
            // Preserve the original failure below; this is only rollback.
          }
          engine.destroyMaterial(replacement)
        }
      }
    } catch (error: Throwable) {
      Log.w(TAG, "Could not install local-tangent wall projection.", error)
    }
  }

  private fun buildWallMaterial(engine: Engine): Material? {
    // Deliberately mirror RenderSceneFilamentHostView.buildMaterial() instead
    // of depending on fluent return values for the source/depth setters. This
    // keeps the guard on the same proven Filament API path as every built-in
    // viewport material.
    val builder = MaterialBuilder()
      .name("RenderSceneWallLocalProjection")
      .shading(MaterialBuilder.Shading.UNLIT)
      .culling(MaterialBuilder.CullingMode.NONE)
      .doubleSided(true)
      .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "baseColor")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT, "displayShade")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT, "surfaceKind")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT, "floorKind")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT, "sectionBoxEnabled")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "sectionBoxMin")
      .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "sectionBoxMax")
      .targetApi(MaterialBuilder.TargetApi.OPENGL)
      .platform(MaterialBuilder.Platform.MOBILE)
      .optimization(MaterialBuilder.Optimization.NONE)
    builder.material(WALL_LOCAL_PROJECTION_MAT)
    builder.depthCulling(true).depthWrite(true)

    val packageData: MaterialPackage = builder.build(engine)
    if (!packageData.isValid) return null
    val packageBuffer = packageData.buffer.duplicate().apply { rewind() }
    return Material.Builder()
      .payload(packageBuffer, packageBuffer.remaining())
      .build(engine)
  }

  private fun field(target: Any, name: String): Any? {
    val declared = target.javaClass.getDeclaredField(name)
    declared.isAccessible = true
    return declared.get(target)
  }

  private fun setField(target: Any, name: String, value: Any?) {
    val declared = target.javaClass.getDeclaredField(name)
    declared.isAccessible = true
    declared.set(target, value)
  }

  private fun invokeNoArg(target: Any, name: String) {
    target.javaClass.getDeclaredMethod(name).apply {
      isAccessible = true
      invoke(target)
    }
  }

  private fun invokeLong(target: Any, name: String, value: Long) {
    target.javaClass.getDeclaredMethod(name, java.lang.Long.TYPE).apply {
      isAccessible = true
      invoke(target, value)
    }
  }

  private const val WALL_LOCAL_PROJECTION_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float3 surfaceNormal = normalize(cross(dFdx(world), dFdy(world)));
    material.normal = surfaceNormal;

    // For a vertical wall face the XZ projection of its normal points across
    // the wall thickness. A perpendicular vector is therefore the local wall
    // tangent. dot(world.xz, tangent) is a stable metre-based U coordinate for
    // every wall rotation, including end caps. Horizontal faces use world.x as
    // a deterministic fallback because their XZ normal projection vanishes.
    float2 horizontalNormal = surfaceNormal.xz;
    float horizontalNormalLength = length(horizontalNormal);
    float surfaceU = world.x;
    if (horizontalNormalLength > 0.0001) {
        float2 localTangent = float2(-horizontalNormal.y, horizontalNormal.x) / horizontalNormalLength;
        surfaceU = dot(world.xz, localTangent);
    }

    float variant = materialParams.surfaceKind;
    float brickMask = 1.0 - step(0.5, variant);
    float plasterMask = step(0.5, variant) * (1.0 - step(1.5, variant));
    float concreteMask = step(1.5, variant) * (1.0 - step(2.5, variant));
    float glassMask = step(2.5, variant);

    float brickRowSpacing = mix(0.18, 0.075, materialParams.displayShade);
    float brickWidth = mix(0.48, 0.24, materialParams.displayShade);
    float rowCoord = world.y / brickRowSpacing;
    float row = floor(rowCoord);
    float rowCell = fract(rowCoord);
    float rowDistance = min(rowCell, 1.0 - rowCell);
    float rowAa = max(fwidth(rowCoord) * 1.25, 0.0005);
    float jointY = 1.0 - smoothstep(0.022 - rowAa, 0.022 + rowAa, rowDistance);
    float brickCoord = (surfaceU + mod(row, 2.0) * brickWidth * 0.5) / brickWidth;
    float brickCell = fract(brickCoord);
    float brickDistance = min(brickCell, 1.0 - brickCell);
    float brickAa = max(fwidth(brickCoord) * 1.25, 0.0005);
    float jointX = 1.0 - smoothstep(0.018 - brickAa, 0.018 + brickAa, brickDistance);
    float mortar = max(jointY, jointX) * mix(0.66, 0.52, materialParams.displayShade);
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);

    float plasterVariation = 0.026 * sin(world.x * 31.0 + world.y * 17.0 + world.z * 23.0);
    float3 plaster = materialParams.baseColor.rgb * (1.0 + plasterVariation);

    float speckle = fract(sin(dot(world.xz, float2(12.9898, 78.233))) * 43758.5453);
    float3 concrete = materialParams.baseColor.rgb * (1.0 + (speckle - 0.5) * 0.08);

    float glassLine = step(0.965, fract((surfaceU + world.y) * 0.42));
    float3 glassTint = mix(float3(0.84, 0.84, 0.84), float3(0.38, 0.68, 0.76), materialParams.displayShade);
    float3 glass = mix(materialParams.baseColor.rgb, glassTint, 0.28);
    glass *= 1.0 - glassLine * 0.18;

    float3 surface = brick * brickMask + plaster * plasterMask + concrete * concreteMask + glass * glassMask;
    float directionalShade = mix(1.0, 0.84 + 0.16 * sin(surfaceU * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(surface * directionalShade, materialParams.baseColor.a);
}
"""
}
