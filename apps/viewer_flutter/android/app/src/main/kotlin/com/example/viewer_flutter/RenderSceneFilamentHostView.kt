package com.example.viewer_flutter

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.opengl.Matrix
import android.view.MotionEvent
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.Gravity
import android.view.Surface
import android.view.ScaleGestureDetector
import android.view.TextureView
import android.widget.FrameLayout
import android.widget.TextView
import com.google.android.filament.Camera
import com.google.android.filament.Colors
import com.google.android.filament.ColorGrading
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.IndexBuffer
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.RenderableManager.PrimitiveType
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.Skybox
import com.google.android.filament.SwapChain
import com.google.android.filament.Texture
import com.google.android.filament.VertexBuffer
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.Box
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper
import com.google.android.filament.filamat.MaterialBuilder
import com.google.android.filament.filamat.MaterialPackage
import com.google.android.filament.utils.KTX1Loader
import com.google.android.filament.utils.Utils
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.IntBuffer
import java.util.ArrayDeque
import kotlin.math.cos
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

private const val DEFAULT_RENDERER_STATUS = "Renderer initializing..."
private const val TAG = "RenderSceneFilament"
// A cache tile can still contain a substantial piece of facade geometry.  Do
// not turn a cache hit into one giant UI-thread GPU upload: show a useful
// first image, then submit the remaining immutable tiles in small pulses.
private const val NATIVE_CACHE_INITIAL_UPLOAD_CHUNKS = 3
private const val NATIVE_CACHE_STEADY_UPLOAD_CHUNKS = 1
private const val NATIVE_CACHE_UPLOAD_DELAY_MS = 8L
private const val NATIVE_CACHE_REPRIORITIZE_DELAY_MS = 56L
private const val NATIVE_CACHE_EDGE_SEGMENT_BUDGET = 60_000

// External mesh formats (FBX and equivalent payloads) do not carry BIM
// semantics that can be used to select a small architectural edge subset.
// Keep a bounded, deterministic edge budget so their linework is visible
// without turning a large imported scene into a second full mesh upload.
private const val IMPORTED_MESH_EDGE_SEGMENT_BUDGET = 48_000
private const val IMPORTED_MESH_EDGE_SEGMENT_LIMIT_SMALL_SCENE = 384
private const val IMPORTED_MESH_EDGE_SEGMENT_LIMIT_LARGE_SCENE = 128
private val EXTERNAL_MESH_KIND_ALIASES = setOf(
  "fbx",
  "fbxmesh",
  "fbxmodel",
  "fbximport",
  "fbx_import",
  "mesh",
  "meshmodel",
  "imported",
  "importedmesh",
  "importedmodel",
  "model3d",
  "external",
  "externalmesh",
  "foreignmesh",
)

// BIM sun preset: a strong directional source with restrained environment
// fill. This keeps the sun-facing facade bright while preserving a readable
// light/shadow boundary on the opposite facade and on the receiver plane.
private const val BIM_SUN_INTENSITY = 65000.0f
// Keep the environment restrained for the lit Shaded view. Solid is unlit and
// therefore independent of scene lighting, matching a clean coordination view.
private const val BIM_IBL_INTENSITY = 6000.0f
private const val BIM_SUN_ANGULAR_RADIUS = 0.018f

private const val FLAT_COLOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float3 normal = normalize(cross(dFdx(world), dFdy(world)));
    material.normal = normal;
    // Solid is intentionally not a wireframe substitute.  Keep the neutral
    // Revit-like surface, but give differently oriented faces a stable,
    // low-frequency value difference so a large imported building reads as a
    // filled model at fit-to-view scale.  This is deterministic (no
    // camera-dependent noise or procedural texture) and therefore does not
    // sparkle while orbiting on mobile GPUs.
    float3 lightDirection = normalize(float3(-0.35, 0.82, 0.42));
    float faceShade = 0.78 + 0.22 * abs(dot(normal, lightDirection));
    float shade = faceShade;
    material.baseColor = float4(materialParams.baseColor.rgb * shade, materialParams.baseColor.a);
}
"""

private const val WALL_BRICK_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float row = floor(world.y / 0.075);
    float jointY = step(fract(world.y / 0.075), 0.018);
    float jointX = step(fract((world.x + mod(row, 2.0) * 0.12) / 0.24), 0.014);
    // Keep this subtle enough for a working BIM view, but distinct on a
    // tablet-sized wall face; the prior 16% contrast disappeared in Solid.
    float mortar = max(jointY, jointX) * 0.58 * materialParams.displayShade;
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(brick * shade, materialParams.baseColor.a);
}
"""

private const val PLASTER_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float variation = 0.035 * sin(world.x * 31.0 + world.y * 17.0 + world.z * 23.0) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + variation) * shade, materialParams.baseColor.a);
}
"""

private const val WOOD_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float grain = 0.10 * sin((world.x + world.z) * 46.0 + sin(world.y * 5.0)) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + grain) * shade, materialParams.baseColor.a);
}
"""

private const val FLOOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float board = step(0.94, fract((world.x + world.z * 0.18) / 0.18)) * materialParams.displayShade;
    float grain = 0.06 * sin(world.x * 58.0 + world.z * 9.0) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + grain - board * 0.20) * shade, materialParams.baseColor.a);
}
"""

private const val ROOF_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float course = step(0.90, fract((world.x + world.z) / 0.28)) * materialParams.displayShade;
    float joint = step(0.94, fract((world.x - world.z) / 0.42)) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 - max(course, joint) * 0.24) * shade, materialParams.baseColor.a);
}
"""

private const val CONCRETE_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float speckle = fract(sin(dot(world.xz, float2(12.9898, 78.233))) * 43758.5453);
    float variation = (speckle - 0.5) * 0.10 * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + variation) * shade, materialParams.baseColor.a);
}
"""

// The model uses Filament's real lit path. The previous unlit workaround
// avoided black faces only because the scene had no environment light; with a
// stable baked IBL, the normal/tangent data can now drive actual sun + ambient
// shading without camera-dependent procedural patterns.
private const val ARCHITECTURAL_LIT_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    material.baseColor = materialParams.baseColor;
    material.metallic = 0.0;
    material.roughness = 0.88;
    material.reflectance = 0.35;
}
"""

private const val GRID_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float2 relative = world.xz - materialParams.gridCenter.xz;
    float distanceFromCenter = length(relative);
    float fade = 1.0 - smoothstep(materialParams.gridFadeStart, materialParams.gridRadius, distanceFromCenter);
    float majorX = 1.0 - smoothstep(0.0, 0.06, abs(fract(relative.x / 5.0 + 0.5) - 0.5));
    float majorZ = 1.0 - smoothstep(0.0, 0.06, abs(fract(relative.y / 5.0 + 0.5) - 0.5));
    float major = max(majorX, majorZ);
    float strength = mix(0.68, 1.0, major);
    material.baseColor = float4(materialParams.baseColor.rgb, materialParams.baseColor.a * fade * strength);
}
"""

private data class FilamentRenderableEntry(
  val objectData: SceneObject,
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  var material: Material,
  var materialInstance: MaterialInstance,
  val baseColor: FloatArray,
  val bounds: SceneBounds,
  var attached: Boolean = false,
)

private data class EdgeBatchKey(
  val kind: String,
  val levelId: Long?,
  val tileX: Int,
  val tileZ: Int,
  val nativeKindMask: Long? = null,
)

private data class FaceBatchKey(
  val kind: String,
  val materialVariant: String,
  val levelId: Long?,
  val tileX: Int,
  val tileZ: Int,
)

private data class FaceBatchEntry(
  val key: FaceBatchKey,
  val representative: SceneObject,
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  var material: Material,
  var materialInstance: MaterialInstance,
  val baseColor: FloatArray,
  val bounds: SceneBounds,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
  val nativeKindMask: Long? = null,
  var attached: Boolean = false,
)

/**
 * One translation-invariant mesh shared by repeated BIM instances.
 *
 * Every entity keeps its own TransformManager component and culling bounds,
 * while Filament's automatic instancing combines entities that reference the
 * same buffers and MaterialInstance into one GPU submission.
 */
private data class InstanceFaceGroupEntry(
  val kind: String,
  val representative: SceneObject,
  val entities: List<Int>,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  var material: Material,
  var materialInstance: MaterialInstance,
  val baseColor: FloatArray,
  val bounds: SceneBounds,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
  var attached: Boolean = false,
)

private data class InstanceFaceKey(
  val kind: String,
  val materialVariant: String,
  val colorHash: Int,
  val vertexCount: Int,
  val indexCount: Int,
  val shapeHash: Long,
)

private data class EdgeBatchEntry(
  val key: EdgeBatchKey,
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val materialInstance: MaterialInstance,
  val vertexCount: Int,
  val indexCount: Int,
  var attached: Boolean = false,
)

/**
 * A precomputed, low-cost architectural shadow silhouette.
 *
 * This is deliberately a mesh, not a Filament light/shadow-map pass. It is
 * rebuilt only with the authoritative scene geometry and then merely toggled
 * with projection/display visibility while the camera moves.
 */
private data class StaticShadowBatchEntry(
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val materialInstance: MaterialInstance,
  val vertexCount: Int,
  val indexCount: Int,
  var attached: Boolean = false,
)

private data class GroundReceiverEntry(
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val materialInstance: MaterialInstance,
  var attached: Boolean = false,
)

private data class GridBatchEntry(
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val materialInstance: MaterialInstance,
  var attached: Boolean = false,
)

private data class FilamentSceneMetrics(
  val bounds: SceneBounds,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
  val edgeBatchCount: Int,
  val edgeVertexCount: Int,
  val edgeIndexCount: Int,
  val instanceGroupCount: Int,
  val instancedObjectCount: Int,
  val sharedFaceVertexCount: Int,
)

private data class NativeVisualObject(
  val elementId: Long?,
  val kind: String,
  val selectable: Boolean,
  val metadata: Map<String, String>,
  val points: List<ScenePoint>,
  val triangles: List<IntArray>,
  val featureEdges: List<NativeVisualEdge>,
)

private data class NativeCameraRay(
  val origin: ScenePoint,
  val direction: ScenePoint,
)

private data class NativeVisualEdge(
  val first: Int,
  val second: Int,
  val triangleIndices: IntArray,
  // A true architectural corner (roughly 70 degrees or sharper), not a
  // tessellation seam. Solid can retain these after silhouette filtering.
  val sharp: Boolean,
)

/** A convex clipping volume shared by the interactive box and section views. */
private data class ClipPlane(
  val normal: ScenePoint,
  val offset: Double,
) {
  fun distance(point: ScenePoint): Double =
    normal.x * point.x + normal.y * point.y + normal.z * point.z + offset
}

private enum class ClipVolumeMode { NONE, SECTION_BOX, SECTION_VIEW }

/** Single authority for every clipping consumer: faces, borders and views. */
private data class ClipVolumeState(
  val mode: ClipVolumeMode = ClipVolumeMode.NONE,
  val planes: List<ClipPlane> = emptyList(),
  val boxMin: ScenePoint = ScenePoint(-100000.0, -100000.0, -100000.0),
  val boxMax: ScenePoint = ScenePoint(100000.0, 100000.0, 100000.0),
  val sectionDirection: ScenePoint? = null,
  val sectionCenter: ScenePoint = ScenePoint(0.0, 0.0, 0.0),
  val sectionLength: Double = 1.0,
) {
  val active: Boolean get() = mode != ClipVolumeMode.NONE
  val isSectionBox: Boolean get() = mode == ClipVolumeMode.SECTION_BOX

  companion object {
    fun none() = ClipVolumeState()
  }
}

internal class RenderSceneFilamentHostView(
  context: Context,
  initialScene: SceneState? = null,
  private val onObjectTapped: (Long?) -> Unit = {},
) : FrameLayout(context), UiHelper.RendererCallback, Choreographer.FrameCallback {
  private class RendererBenchmarkRun(
    val mode: String,
    val startedNanos: Long,
    val sourceIfcPath: String?,
    val cachePath: String?,
    val cacheCompileStats: NativeBimCacheCompileStats?,
  ) {
    var cacheAppliedNanos = 0L
    var firstVisibleNanos = 0L
    var fullReadyNanos = 0L
    var phase = "waiting"
    var phaseStartedNanos = 0L
    var previousFrameNanos = 0L
    var gcCountAtStart: Long? = null
    val frameIntervalsMs = linkedMapOf<String, MutableList<Double>>()
    val cpuSubmitMs = linkedMapOf<String, MutableList<Double>>()

    fun samples(target: MutableMap<String, MutableList<Double>>, phase: String): MutableList<Double> =
      target.getOrPut(phase) { mutableListOf() }
  }

  private data class CachedEdgeGeometry(
    val revision: Int,
    val junctionSignature: Int,
    val geometry: GeometryData,
  )

  private data class NormalizedInstanceGeometry(
    val key: InstanceFaceKey,
    val geometry: GeometryData,
    val translation: ScenePoint,
  )

  companion object {
    init {
      Filament.init()
      MaterialBuilder.init()
      Utils.init()
    }
  }

  private val renderSurface = TextureView(context)
  private val selectionOverlay = NativeSelectionOverlay(context)
  private val statusView = TextView(context)
  private val choreographer = Choreographer.getInstance()
  private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
  private val displayHelper = DisplayHelper(context, Handler(Looper.getMainLooper()))
  private val sectionBoxHandler = Handler(Looper.getMainLooper())
  private val shadowResume = Runnable {
    if (!touching && realShadowVisible()) {
      filamentView?.setShadowingEnabled(true)
      requestRender()
    }
  }
  private var fitSectionBoxOnNextRebuild = false
  private var fitSectionViewOnNextRebuild = false
  private val sectionBoxRebuild = Runnable {
    rebuildScene()
    syncVisibility()
    refreshTintState()
    if (fitSectionBoxOnNextRebuild) {
      fitSectionBoxOnNextRebuild = false
      fitCameraToSectionBox()
    }
    if (fitSectionViewOnNextRebuild) {
      fitSectionViewOnNextRebuild = false
      fitCameraToSectionView()
    }
    invalidate()
  }
  private val scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
    override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
      cancelOrbitInertia()
      orbitYawVelocity = 0.0
      orbitPitchVelocity = 0.0
      return true
    }

    override fun onScale(detector: ScaleGestureDetector): Boolean {
      if (isPlanarProjection()) {
        if (projectionMode == "topDown") {
          topDownZoom = (topDownZoom / detector.scaleFactor.toDouble()).coerceIn(0.5, 200.0)
        } else {
          orbitDistance = (orbitDistance / detector.scaleFactor.toDouble())
            .coerceIn(minimumPlanarOrbitDistance(), 250.0)
        }
      } else {
        val nextDistance = orbitDistance / detector.scaleFactor.toDouble()
        orbitDistance = nextDistance.coerceIn(minimumOrbitDistance(), 250.0)
      }
      configureCameraProjection()
      updateOrbitCamera()
      updateStatus(
        if (projectionMode == "topDown") {
          "Plan zoom ${topDownZoom.format(2)}m"
        } else if (isPlanarProjection()) {
          "Elevation zoom ${orbitDistance.format(2)}m"
        } else {
          "Orbit zoom ${orbitDistance.format(2)}m"
        }
      )
      requestRender(250L)
      invalidate()
      return true
    }
  })
  private val visibleKinds = linkedSetOf<String>().apply {
    addAll(
      setOf(
        "wall",
        "door",
        "window",
        "slab",
        "floor",
        "ceiling",
        "roof",
        "column",
        "beam",
        "stair",
        "room",
        "proxy",
      )
    )
  }

  private var engine: Engine? = null
  private var renderer: Renderer? = null
  private var scene: Scene? = null
  private var filamentView: View? = null
  private var camera: Camera? = null
  private var skybox: Skybox? = null
  private var colorSkybox: Skybox? = null
  private var hdriSkybox: Skybox? = null
  private var hdriSkyboxTexture: Texture? = null
  private var indirectLight: IndirectLight? = null
  private var indirectLightTexture: Texture? = null
  private var sunLightEntity: Int? = null
  private var fillLightEntity: Int? = null
  private var colorGrading: ColorGrading? = null
  private var swapChain: SwapChain? = null
  private var sceneMetrics = FilamentSceneMetrics(
    bounds = SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0)),
    objectCount = 0,
    vertexCount = 0,
    indexCount = 0,
    edgeBatchCount = 0,
    edgeVertexCount = 0,
    edgeIndexCount = 0,
    instanceGroupCount = 0,
    instancedObjectCount = 0,
    sharedFaceVertexCount = 0,
  )
  private var currentScene: SceneState? = initialScene
  // The authoritative compatibility scene remains available while a native
  // cache is displayed. Edits still return here during the migration, and the
  // A/B harness can restore the identical JSON renderer without reparsing IFC.
  private var compatibilityScene: SceneState? = initialScene
  private var nativeBimCache: NativeBimCacheBridge.NativeBimCache? = null
  private var nativeCacheLoadRevision = 0L
  private var nativeCacheUploadRevision = 0L
  private var nativeCacheUploadPosted = false
  private var nativeCacheReprioritizePosted = false
  private val nativeCachePendingChunks = ArrayDeque<Int>()
  private val nativeCacheResidentChunks = linkedSetOf<Int>()
  private var nativeCacheFullBounds: SceneBounds? = null
  private var currentSceneFingerprint: Long? = null
  private var selectedElementId: Long? = null
  private var selectedElementIds = emptySet<Long>()
  private var highlightedElementId: Long? = null
  private var framePosted = false
  private var renderDirty = true
  private var renderedFrameCount = 0L
  private var lastRenderedFrameNanos = 0L
  private var interactiveUntilMs = 0L
  private var telemetrySampleMs = 0L
  private var telemetryCpuMs = 0L
  private var telemetryFrameCount = 0L
  private var cpuPercent = 0.0
  // A static viewport intentionally stops requesting VSYNC. Benchmarks use a
  // small UI-thread heartbeat so their timed phases keep advancing after the
  // final native chunk upload has made the normal renderer idle.
  private val benchmarkTick = object : Runnable {
    override fun run() {
      val benchmark = rendererBenchmark ?: return
      if (benchmark.phase == "complete") return
      driveAutomatedBenchmark(SystemClock.elapsedRealtimeNanos())
      if (rendererBenchmark != null) {
        requestRender()
        renderSurface.postInvalidateOnAnimation()
        postDelayed(this, 16L)
      }
    }
  }
  private var framesPerSecond = 0.0
  private var residentMemoryMb = 0.0
  private var nativeThreadCount = 0
  private var rendererBenchmark: RendererBenchmarkRun? = null
  private var surfaceReady = false
  private var materialBuilderReady = false
  private var material: Material? = null
  private var wallMaterial: Material? = null
  private var windowMaterial: Material? = null
  private var plasterMaterial: Material? = null
  private var woodMaterial: Material? = null
  private var floorMaterial: Material? = null
  private var roofMaterial: Material? = null
  private var concreteMaterial: Material? = null
  private var solidMaterial: Material? = null
  private var solidWindowMaterial: Material? = null
  private var edgeMaterial: Material? = null
  private var gridMaterial: Material? = null
  private var groundMaterial: Material? = null
  private var shadowMaterial: Material? = null
  private val renderables = linkedMapOf<Long, FilamentRenderableEntry>()
  private val faceBatches = mutableListOf<FaceBatchEntry>()
  private val instanceFaceGroups = mutableListOf<InstanceFaceGroupEntry>()
  private val edgeBatches = mutableListOf<EdgeBatchEntry>()
  private var staticShadowBatch: StaticShadowBatchEntry? = null
  private var gridBatch: GridBatchEntry? = null
  private var groundReceiver: GroundReceiverEntry? = null
  private val edgeGeometryCache = linkedMapOf<Long, CachedEdgeGeometry>()
  private var importedMeshEdgeBudgetRemaining = IMPORTED_MESH_EDGE_SEGMENT_BUDGET
  private var nativeCacheEdgeBudgetRemaining = NATIVE_CACHE_EDGE_SEGMENT_BUDGET
  private val attachedEntities = linkedSetOf<Int>()
  private var statusMessage = DEFAULT_RENDERER_STATUS
  private var disposed = false
  private var orbitCenter = ScenePoint(0.0, 0.0, 0.0)
  private var orbitYawRadians = Math.toRadians(45.0)
  private var orbitPitchRadians = Math.toRadians(22.0)
  private var orbitDistance = 12.0
  private var topDownZoom = 1.0
  private var projectionMode = "topDown"
  private var orbitProjectionStyle = "orthographic"
  private var displayStyle = "solid"
  private var viewportTheme = "light"
  private var shadowsEnabled = false
  private var hdriVisible = false
  private var clipVolume = ClipVolumeState.none()
  private val sectionBoxEnabled get() = clipVolume.isSectionBox
  private val sectionBoxMin get() = clipVolume.boxMin
  private val sectionBoxMax get() = clipVolume.boxMax
  private val clipPlanes get() = clipVolume.planes
  private var sectionSceneMin = ScenePoint(-100000.0, -100000.0, -100000.0)
  private var sectionSceneMax = ScenePoint(100000.0, 100000.0, 100000.0)
  private var activeSectionHandle: String? = null
  private var lastTouchX = 0f
  private var lastTouchY = 0f
  private var touchDownX = 0f
  private var touchDownY = 0f
  private var touchMoved = false
  private var touching = false
  // A pinch must never fall through to the one-finger orbit path when one
  // pointer is released. Keeping this state also lets us reset the orbit
  // baseline to the pointer that remains on the surface.
  private var multiTouching = false
  private var multiTouchFocusX = 0f
  private var multiTouchFocusY = 0f
  private var multiTouchFocusValid = false
  private var orbitYawVelocity = 0.0
  private var orbitPitchVelocity = 0.0
  private var lastOrbitMotionTimeMs = 0L
  private var orbitInertiaActive = false
  private var lastInertiaFrameNanos = 0L

  init {
    setBackgroundColor(Color.rgb(243, 247, 244))
    addView(
      renderSurface,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
    // TextureView may otherwise expose an uninitialised tile while the
    // SurfaceTexture is handing a new frame to Flutter's compositor.  The
    // Filament clear pass is opaque, so make that contract explicit to the
    // Android compositor as well.
    renderSurface.isOpaque = true
    renderSurface.setOnTouchListener { _, event -> handleTouchEvent(event) }
    addView(
      selectionOverlay,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
    selectionOverlay.setOnTouchListener { _, event -> handleSectionOverlayTouch(event) }
    addView(
      statusView,
      LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.START or Gravity.TOP),
    )
    statusView.setPadding(24, 16, 24, 16)
    statusView.setTextColor(Color.rgb(17, 24, 39))
    statusView.setBackgroundColor(Color.argb(180, 255, 255, 255))
    statusView.typeface = Typeface.MONOSPACE
    statusView.textSize = 12f
    statusView.maxLines = 2
    statusView.text = DEFAULT_RENDERER_STATUS
    // Native telemetry remains available through the diagnostics channel, but
    // it is never an on-canvas BIM workspace overlay. The visible UI belongs
    // to Flutter's intentionally scoped debug tools instead.
    statusView.visibility = android.view.View.GONE

    uiHelper.renderCallback = this
    uiHelper.attachTo(renderSurface)
    // Flutter owns Android touch dispatch. In 3D it forwards a normalized
    // viewport point through the channel, which we map back to this actual
    // SurfaceView before ray-picking with Filament's live camera.
    renderSurface.isClickable = false

    try {
      // Keep the known-good OpenGL backend for the connected tablet. Vulkan
      // was tested here but the device terminated the app while opening the
      // large KIT scene, so it is not a safe runtime fallback yet.
      val filamentEngine = Engine.create(Engine.Backend.OPENGL)
      // Repeated BIM types share one geometry and MaterialInstance below.
      // Filament can then collapse their independent entities/transforms into
      // hardware-instanced submissions automatically.
      filamentEngine.isAutomaticInstancingEnabled = true
      engine = filamentEngine
      renderer = filamentEngine.createRenderer()
      renderer?.setClearOptions(Renderer.ClearOptions().apply {
        // Explicitly clear every submitted frame. This matters when the
        // shadow receiver is removed: otherwise a TextureView can retain the
        // previous black shadow pixels until an unrelated redraw.
        clear = true
        clearColor = doubleArrayOf(0.95, 0.96, 0.95, 1.0)
      })
      scene = filamentEngine.createScene()
      filamentView = filamentEngine.createView()
      filamentView?.isFrustumCullingEnabled = true
      // Windows use a transparent shaded material; include them in GPU picks
      // so tapping glass selects the window rather than the wall behind it.
      filamentView?.isTransparentPickingEnabled = true
      camera = filamentEngine.createCamera(EntityManager.get().create())
      filamentView?.scene = scene
      filamentView?.camera = camera
      createSunLight(filamentEngine)
      filamentView?.setShadowingEnabled(false)
      filamentView?.setShadowType(View.ShadowType.PCF)
      colorGrading = ColorGrading.Builder()
        // Keep Solid on the same linear presentation curve as the proven
        // tablet renderer. ACES compresses the near-white unlit BIM faces
        // into the light background and makes them look transparent.
        .toneMapping(ColorGrading.ToneMapping.LINEAR)
        .build(filamentEngine)
      filamentView?.colorGrading = colorGrading
      filamentView?.viewport = Viewport(0, 0, 1, 1)
      // Light paper canvas preserves true-white Solid geometry without the
      // old overall grey cast. The selected viewport theme can replace both
      // the clear color and skybox later without rebuilding model geometry.
      colorSkybox = Skybox.Builder().color(0.91f, 0.92f, 0.91f, 1.0f).build(filamentEngine)
      skybox = colorSkybox
      scene?.skybox = colorSkybox
      loadHdriEnvironment(filamentEngine)
      applyViewportTheme()
      statusMessage = "Filament renderer created."
      Log.i(TAG, statusMessage)
      updateStatus()
      materialBuilderReady = buildRuntimeMaterial()
      currentScene?.let { loadScene(it) }
    } catch (error: Throwable) {
      statusMessage = "Filament init failed: ${error.message ?: error::class.java.simpleName}"
      Log.e(TAG, statusMessage, error)
      updateStatus()
    }
  }

  private fun createSunLight(engine: Engine) {
    val entity = EntityManager.get().create()
    val shadowOptions = LightManager.ShadowOptions().apply {
      // A single stable cascade is enough for this BIM viewport and avoids
      // the cost of a continuously refreshed high-resolution shadow atlas.
      mapSize = 1024
      shadowCascades = 1
      constantBias = 0.001f
      normalBias = 0.015f
      shadowNearHint = 0.5f
      shadowFarHint = 120.0f
      shadowFar = 120.0f
      maxShadowDistance = 120.0f
      stable = true
      screenSpaceContactShadows = false
    }
    try {
      LightManager.Builder(LightManager.Type.SUN)
        .color(1.0f, 0.96f, 0.90f)
        // A stable sun supplies the directional part and the actual cast
        // shadow. HDRI/IBL supplies the soft ambient part below.
        .intensity(BIM_SUN_INTENSITY)
        // Filament stores the direction of the incoming light rays. The
        // Keep the source on the camera-facing/right side, but offset it in Z
        // so the cast shadow travels into the visible ground plane instead of
        // disappearing directly behind the building.
        .direction(-0.68f, -0.92f, 0.36f)
        .sunAngularRadius(BIM_SUN_ANGULAR_RADIUS)
        .castShadows(true)
        .shadowOptions(shadowOptions)
        .build(engine, entity)
      scene?.addEntity(entity)
      sunLightEntity = entity
      Log.i(TAG, "Fixed sun light enabled with cached 1-cascade shadow map.")
    } catch (error: Throwable) {
      EntityManager.get().destroy(entity)
      Log.e(TAG, "Failed to create fixed sun light", error)
    }
  }

  private fun realShadowVisible(mode: String = projectionMode): Boolean =
    shadowsEnabled && sunLightEntity != null &&
      mode == "isometric" && displayStyle == "shaded"

  private fun loadHdriEnvironment(engine: Engine): Boolean {
    return try {
      val iblBundle = KTX1Loader.createIndirectLight(
        engine,
        readAssetBuffer("envs/default/default_env_ibl.ktx"),
        KTX1Loader.Options(),
      )
      val skyboxBundle = KTX1Loader.createSkybox(
        engine,
        readAssetBuffer("envs/default/default_env_skybox.ktx"),
        KTX1Loader.Options(),
      )
      indirectLight = iblBundle.indirectLight
      indirectLightTexture = iblBundle.cubemap
      // Keep ambient fill below the direct sun so facade orientation remains
      // visible instead of flattening the model to white on tablet displays.
      applyDisplayLightingPreset()
      hdriSkybox = skyboxBundle.skybox
      hdriSkyboxTexture = skyboxBundle.cubemap
      scene?.indirectLight = indirectLight
      statusMessage = "HDRI environment loaded; stable IBL lighting enabled."
      Log.i(TAG, statusMessage)
      true
    } catch (error: Throwable) {
      statusMessage = "HDRI environment unavailable; using neutral skybox."
      Log.w(TAG, "$statusMessage ${error.message ?: error::class.java.simpleName}", error)
      false
    }
  }

  private fun readAssetBuffer(path: String): ByteBuffer {
    val bytes = context.assets.open(path).use { input -> input.readBytes() }
    return ByteBuffer.allocateDirect(bytes.size)
      .order(ByteOrder.nativeOrder())
      .apply {
        put(bytes)
        flip()
      }
  }

  private fun applyDisplayLightingPreset() {
    indirectLight?.intensity = BIM_IBL_INTENSITY
  }

  private fun createFillLight(engine: Engine) {
    val entity = EntityManager.get().create()
    try {
      // This light has no shadow map. It only lifts fully occluded faces so
      // the fixed sun produces readable BIM shading instead of crushed black
      // surfaces on tablet GPUs.
      LightManager.Builder(LightManager.Type.SUN)
        .color(0.82f, 0.86f, 0.94f)
        .intensity(45000.0f)
        .direction(-0.40f, -0.70f, -0.65f)
        .sunAngularRadius(0.045f)
        .castLight(true)
        .castShadows(false)
        .build(engine, entity)
      scene?.addEntity(entity)
      fillLightEntity = entity
    } catch (error: Throwable) {
      EntityManager.get().destroy(entity)
      Log.e(TAG, "Failed to create fill light", error)
    }
  }

  fun loadScene(newScene: SceneState?) {
    nativeCacheLoadRevision += 1L
    closeNativeBimCache()
    if (newScene == null) {
      clearScene("RenderScene load failed or scene cleared.")
      return
    }
    val fingerprint = sceneFingerprint(newScene)
    if (currentSceneFingerprint == fingerprint && clipVolume.mode == ClipVolumeMode.NONE) {
      // Flutter may replay an unchanged authoritative snapshot while its
      // surrounding widgets settle. Reuse native GPU batches when every
      // element revision and geometry cardinality is identical.
      currentScene = newScene
      compatibilityScene = newScene
      syncVisibility()
      refreshTintState()
      requestRender()
      return
    }
    // A RenderScene snapshot is always authoritative and uncut. The Flutter
    // controller reapplies its current ClipVolume after loading; clearing it
    // here prevents a stale box/section from deleting a differently-bounded
    // building during the intermediate rebuild.
    resetClipVolumeState()
    currentScene = newScene
    compatibilityScene = newScene
    currentSceneFingerprint = fingerprint
    val liveElementIds = newScene.objects.mapNotNull { it.elementId }.toSet()
    edgeGeometryCache.keys.retainAll(liveElementIds)
    rebuildScene()
    selectionOverlay.setVisualScene(
      newScene.objects.map(::toVisualObject),
      newScene.levels.map { level -> level.name to level.elevationMeters },
      sceneMetrics.bounds,
    )
    selectionOverlay.setDisplayStyle(displayStyle)
    syncVisibility()
    refreshTintState()
    fitCamera()
    statusMessage = "Loaded ${sceneMetrics.objectCount} renderables from RenderScene."
    Log.i(TAG, statusMessage)
    updateStatus()
    invalidate()
  }

  /**
   * Opens a validated engine cache away from the Android UI thread, then uses
   * its direct native vertex/index buffers for Filament. This follows the
   * compatibility scene load so a stale or unavailable cache never prevents a
   * model from opening.
   */
  fun loadNativeBimCache(cachePath: String, sourceIfcPath: String) {
    val requestRevision = nativeCacheLoadRevision + 1L
    nativeCacheLoadRevision = requestRevision
    Thread {
      val loaded = NativeBimCacheBridge.open(cachePath, sourceIfcPath)
      post {
        if (disposed || requestRevision != nativeCacheLoadRevision) {
          loaded?.close()
          return@post
        }
        if (loaded == null || loaded.chunks.isEmpty()) {
          statusMessage = "Native BIM cache unavailable; using compatibility scene."
          updateStatus()
          return@post
        }
        closeNativeBimCache()
        nativeBimCache = loaded
        nativeCacheFullBounds = nativeCacheBounds(loaded)
        resetClipVolumeState()
        currentScene = nativeCacheSceneState(loaded)
        currentSceneFingerprint = null
        rendererBenchmark?.takeIf { it.mode == "NEW_BIMCACHE" }?.let { benchmark ->
          benchmark.cacheAppliedNanos = SystemClock.elapsedRealtimeNanos()
        }
        // Fit against the complete cached model before submitting its first
        // GPU tile.  Otherwise a near-first stream would fit to a façade
        // fragment and make the camera jump as later chunks arrive.
        updateMetrics()
        fitCamera()
        rebuildScene()
        selectionOverlay.setVisualScene(
          loaded.primitives.map(::nativeCacheVisualObject).also { visualObjects ->
            val importedCount = visualObjects.count { it.metadata["external_mesh"] == "true" }
            val edgeCount = visualObjects.sumOf { it.featureEdges.size }
            Log.i(TAG, "Native cache overlay: primitives=${visualObjects.size}, imported=$importedCount, boundsEdges=$edgeCount")
          },
          currentScene?.levels?.map { level -> level.name to level.elevationMeters } ?: emptyList(),
          sceneMetrics.bounds,
        )
        selectionOverlay.setDisplayStyle(displayStyle)
        syncVisibility()
        refreshTintState()
        statusMessage = "Streaming ${loaded.chunks.size} native BIM chunks."
        Log.i(TAG, statusMessage)
        updateStatus()
        invalidate()
      }
    }.apply {
      name = "tbe-bim-cache-open"
      isDaemon = true
      start()
    }
  }

  private fun closeNativeBimCache() {
    nativeCacheUploadRevision += 1L
    nativeCacheUploadPosted = false
    nativeCacheReprioritizePosted = false
    nativeCachePendingChunks.clear()
    nativeCacheResidentChunks.clear()
    nativeCacheFullBounds = null
    nativeBimCache?.close()
    nativeBimCache = null
  }

  /**
   * Runs a repeatable renderer-only tablet benchmark. The JSON path uses the
   * same already-decoded compatibility scene; the cache path opens the same
   * IFC-derived binary cache. This isolates renderer/open/submission costs
   * from human gesture variability and never edits the IFC or BIM session.
   */
  fun runAutomatedRendererBenchmark(
    mode: String,
    sourceIfcPath: String? = null,
    cachePath: String? = null,
    cacheCompileStats: NativeBimCacheCompileStats? = null,
  ) {
    val benchmark = RendererBenchmarkRun(
      mode = mode,
      startedNanos = SystemClock.elapsedRealtimeNanos(),
      sourceIfcPath = sourceIfcPath,
      cachePath = cachePath,
      cacheCompileStats = cacheCompileStats,
    ).also {
      it.gcCountAtStart = android.os.Debug.getRuntimeStat("art.gc.gc-count")?.toLongOrNull()
    }
    rendererBenchmark = benchmark
    removeCallbacks(benchmarkTick)
    post(benchmarkTick)
    Log.i("TbeBenchmark", "START mode=$mode source=${sourceIfcPath ?: "compatibility_scene"}")

    if (mode == "OLD_JSON") {
      val fallback = compatibilityScene
      if (fallback == null) {
        Log.e("TbeBenchmark", "BENCHMARK_ERROR no compatibility JSON scene is loaded")
        rendererBenchmark = null
        return
      }
      nativeCacheLoadRevision += 1L
      closeNativeBimCache()
      resetClipVolumeState()
      currentScene = fallback
      currentSceneFingerprint = sceneFingerprint(fallback)
      rebuildScene()
      selectionOverlay.setVisualScene(
        fallback.objects.map(::toVisualObject),
        fallback.levels.map { level -> level.name to level.elevationMeters },
        sceneMetrics.bounds,
      )
      syncVisibility()
      refreshTintState()
      fitCamera()
      markBenchmarkFullSceneReady(benchmark)
    } else if (mode == "NEW_BIMCACHE") {
      if (sourceIfcPath.isNullOrBlank() || cachePath.isNullOrBlank()) {
        Log.e("TbeBenchmark", "BENCHMARK_ERROR cache benchmark requires sourceIfcPath and cachePath")
        rendererBenchmark = null
        return
      }
      loadNativeBimCache(cachePath, sourceIfcPath)
    } else {
      Log.e("TbeBenchmark", "BENCHMARK_ERROR unsupported mode=$mode")
      rendererBenchmark = null
    }
  }

  private fun markBenchmarkFullSceneReady(benchmark: RendererBenchmarkRun) {
    if (rendererBenchmark !== benchmark || benchmark.fullReadyNanos != 0L) return
    benchmark.fullReadyNanos = SystemClock.elapsedRealtimeNanos()
    // Start standardized idle/orbit/zoom-pan sampling only after the complete
    // representation is ready. Native streaming can still record first visible
    // time earlier, but does not pollute steady-state measurements.
    benchmark.phase = "idle"
    benchmark.phaseStartedNanos = benchmark.fullReadyNanos
    // Streaming may have submitted its final dirty frame before the last
    // chunk marks the scene complete. Keep the Choreographer alive for the
    // standardized idle/orbit/zoom-pan samples instead of leaving the
    // benchmark stranded in an otherwise intentionally idle viewport.
    requestRender()
  }

  private fun markBenchmarkFirstSceneVisible(benchmark: RendererBenchmarkRun) {
    if (rendererBenchmark !== benchmark || benchmark.firstVisibleNanos != 0L) return
    // GPU buffers for at least one cache chunk now exist. A render is queued
    // immediately afterwards, so this is the native-path equivalent of the
    // first scene that can become visible without waiting for far chunks.
    benchmark.firstVisibleNanos = SystemClock.elapsedRealtimeNanos()
  }

  private fun nativeCacheBounds(cache: NativeBimCacheBridge.NativeBimCache): SceneBounds {
    val bounds = cache.chunks.map { chunk -> transformBounds(chunk.sourceBounds) }
    return bounds.reduceOrNull(::unionBounds)
      ?: SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
  }

  private fun nativeCacheSceneState(cache: NativeBimCacheBridge.NativeBimCache): SceneState {
    val objects = cache.chunks.mapIndexed { index, chunk ->
      SceneObject(
        elementId = -(index.toLong() + 1L),
        kind = chunk.kind,
        levelId = chunk.levelId,
        selectable = false,
        visibleByDefault = true,
        revision = 1,
        bounds = chunk.sourceBounds,
        mesh = SceneMesh(emptyList(), emptyList()),
        materialCategory = chunk.materialCategory,
        metadata = emptyMap(),
      )
    }
    val levels = objects
      .mapNotNull { entry -> entry.levelId }
      .distinct()
      .sorted()
      .map { levelId -> SceneLevel(levelId, "Level $levelId", 0.0) }
    return SceneState(
      sceneVersion = 1,
      units = "meters",
      coordinateSystem = "X/Y plan, Z up",
      objectCount = cache.primitives.size,
      vertexCount = cache.chunks.sumOf { it.positions.capacity() / 12 },
      indexCount = cache.chunks.sumOf { it.indices.capacity() },
      levels = levels,
      objects = objects,
    )
  }

  private fun nativeCacheVisualObject(primitive: NativeBimCachePrimitive): NativeVisualObject {
    val sourceElementId = NativeBimCacheBridge.virtualIfcPartSourceId(primitive.elementId)
    // The cache compiler preserves IFCBUILDINGELEMENTPROXY as `proxy` when
    // the source exporter did not provide virtual part ids. Those objects are
    // still imported mesh payloads from the viewport's point of view and must
    // receive the same stable outline fallback as FBX/OBJ imports.
    val importedPart = sourceElementId != null || normalizeKind(primitive.kind) == "proxy"
    val points = boxCorners(primitive.sourceBounds).map(::toFilamentPoint)
    val triangles = listOf(
      intArrayOf(0, 1, 2), intArrayOf(0, 2, 3),
      intArrayOf(4, 6, 5), intArrayOf(4, 7, 6),
      intArrayOf(0, 4, 5), intArrayOf(0, 5, 1),
      intArrayOf(1, 5, 6), intArrayOf(1, 6, 2),
      intArrayOf(2, 6, 7), intArrayOf(2, 7, 4),
      intArrayOf(3, 7, 4), intArrayOf(3, 4, 0),
    )
    // Cache meshes stay in native DirectByteBuffers, so the overlay never
    // receives their full edges.  Keep just the twelve bounds edges as a
    // selection-only affordance: it makes a picked IFC element visibly blue
    // without reintroducing per-triangle Dart/Kotlin work for large models.
    val selectionBoundsEdges = listOf(
      0 to 1, 1 to 2, 2 to 3, 3 to 0,
      4 to 5, 5 to 6, 6 to 7, 7 to 4,
      0 to 4, 1 to 5, 2 to 6, 3 to 7,
    ).map { (first, second) ->
      NativeVisualEdge(
        first = first,
        second = second,
        triangleIndices = intArrayOf(),
        sharp = true,
      )
    }
    return NativeVisualObject(
      elementId = primitive.elementId,
      kind = primitive.kind,
      selectable = true,
      metadata = buildMap {
        put("native_cache", "true")
        put("level_id", primitive.levelId.toString())
        if (importedPart) {
          // Native cache primitives for collapsed IFC/CAD payloads are the
          // same semantic class as an imported FBX part. Their mesh stays in
          // native memory, so the Android overlay needs this small marker to
          // draw a stable bounds outline when the GPU edge pass is occluded
          // or temporarily absent on a mobile OpenGL driver.
          put("external_mesh", "true")
        }
        sourceElementId?.let { sourceId ->
          put("source_element_id", sourceId.toString())
          put("selection_scope", "imported_mesh_part")
        }
      },
      points = points,
      triangles = triangles,
      featureEdges = selectionBoundsEdges,
    )
  }

  fun clearScene() {
    clearScene("Scene cleared.")
  }

  private fun clearScene(message: String) {
    removeCallbacks(benchmarkTick)
    rendererBenchmark = null
    nativeCacheLoadRevision += 1L
    closeNativeBimCache()
    resetClipVolumeState()
    currentScene = null
    currentSceneFingerprint = null
    selectedElementId = null
    selectedElementIds = emptySet()
    highlightedElementId = null
    selectionOverlay.clear()
    selectionOverlay.clearVisualScene()
    destroyRenderables()
    edgeGeometryCache.clear()
    updateMetrics()
    updateStatus(message)
    Log.i(TAG, message)
    invalidate()
  }

  private fun sceneFingerprint(scene: SceneState): Long {
    var hash = 1125899906842597L
    hash = hash * 31L + scene.sceneVersion
    hash = hash * 31L + scene.objects.size
    hash = hash * 31L + scene.vertexCount
    hash = hash * 31L + scene.indexCount
    for (objectData in scene.objects) {
      hash = hash * 31L + (objectData.elementId ?: 0L)
      hash = hash * 31L + objectData.revision
      hash = hash * 31L + objectData.mesh.positions.size
      hash = hash * 31L + objectData.mesh.indices.size
      hash = hash * 31L + objectData.bounds.hashCode()
      hash = hash * 31L + objectData.metadata.hashCode()
    }
    return hash
  }

  private fun resetClipVolumeState() {
    clipVolume = ClipVolumeState.none()
    sectionSceneMin = ScenePoint(-100000.0, -100000.0, -100000.0)
    sectionSceneMax = ScenePoint(100000.0, 100000.0, 100000.0)
    fitSectionBoxOnNextRebuild = false
    fitSectionViewOnNextRebuild = false
    selectionOverlay.setSectionBox(false, clipVolume.boxMin, clipVolume.boxMax)
  }

  fun fitCamera() {
    val camera = camera ?: return
    val metrics = sceneMetrics
    // sceneMetrics already comes from Filament-space renderable bounds.
    // Transforming it again moves the fitted camera away from the mesh.
    val bounds = metrics.bounds
    val width = max(bounds.max.x - bounds.min.x, 0.001)
    // Filament uses Y as vertical.  Section scenes are intentionally very
    // shallow in Z, so treating Z as elevation here fitted a 9-storey cut to
    // its 6 cm section depth and clipped its first/last storeys.
    val height = max(bounds.max.y - bounds.min.y, 0.001)
    val depth = max(bounds.max.z - bounds.min.z, 0.001)
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerY = (bounds.min.y + bounds.max.y) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    val radius = max(width, max(depth, height)) * 0.75 + 1.0
    orbitCenter = ScenePoint(centerX, centerY, centerZ)
    orbitDistance = if (isElevationProjection()) {
      val horizontalExtent = when (projectionMode) {
        "northElevation", "southElevation" -> width
        "eastElevation", "westElevation" -> depth
        else -> width
      }
      // `configureCameraProjection` derives orthographic half-height from
      // orbitDistance. Size that value from the actual elevation axes, not
      // the largest 3D extent, so a whole building fills the view naturally.
      val halfHeight = max(
        height * 0.5,
        horizontalExtent / (2.0 * max(aspectRatio(), 0.1)),
      ) * 1.12
      max(halfHeight / 0.6, 3.0)
    } else {
      max(radius * 2.0, 3.0)
    }
    resetCameraOrientationForProjection()
    topDownZoom = max(radius * 1.2, 2.0)
    configureCameraProjection()
    updateOrbitCamera()
    interactiveUntilMs = SystemClock.uptimeMillis() + 500L
    syncVisualOverlay()
    requestRender(500L)
    updateStatus("Camera fitted to ${metrics.objectCount} objects.")
    invalidate()
  }

  fun setProjectionMode(mode: String) {
    val edgeGeometryNeedsRefresh =
      (projectionMode == "topDown") != (mode == "topDown")
    projectionMode = mode
    filamentView?.setShadowingEnabled(realShadowVisible(mode))
    if (mode == "isometric" && shadowsEnabled && groundReceiver == null && currentScene != null && materialBuilderReady) {
      createGroundReceiver(engine ?: return, scene ?: return, currentScene!!)
    }
    if (edgeGeometryNeedsRefresh && currentScene != null && materialBuilderReady) {
      // Edge prisms are projection-aware: top-down uses a light line weight
      // and omits section-only reconstruction segments that become diagonal
      // seams in a floor plan. Rebuild only the native edge batches when
      // crossing the plan/3D boundary; keep the scene and GPU materials.
      rebuildEdgeBatchesForProjection()
      syncVisibility()
      refreshTintState()
    }
    if (mode == "isometric" && gridBatch == null && currentScene != null && materialBuilderReady) {
      createGridBatch(engine ?: return, scene ?: return, currentScene!!)
    } else if (mode != "isometric" && gridBatch != null) {
      destroyGridBatch(engine, scene)
    }
    // Static shadow visibility follows the view mode, but its geometry is not
    // rebuilt when the camera or projection changes.
    syncVisibility()
    resetCameraOrientationForProjection()
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    requestRender(250L)
    updateStatus()
    invalidate()
  }

  fun setOrbitProjectionStyle(style: String) {
    orbitProjectionStyle = style
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    requestRender(250L)
    updateStatus()
    invalidate()
  }

  /// Camera state is owned by Flutter so Filament and fallback receive the
  /// same tablet interaction policy. Coordinates are converted once here.
  fun setCamera(payload: Map<*, *>?) {
    val orbitCenterPayload = parsePoint(payload?.get("orbitCenter"))
    val planCenterPayload = parsePoint(payload?.get("planCenter"))
    if (isPlanarProjection() && planCenterPayload != null) {
      orbitCenter = toFilamentPoint(planCenterPayload)
      val planZoom = toDouble(payload?.get("planZoom"))
      val planViewportHeight = toDouble(payload?.get("planViewportHeight"))
      if (planZoom != null && planZoom > 0.0 && planViewportHeight != null && planViewportHeight > 0.0) {
        // Flutter owns the planar camera in logical pixels/metre. Convert it
        // directly to Filament's orthographic half-height in metres. Elevation
        // uses the same camera scale as plan; previously it silently fell back
        // to the stale orbit distance and ignored every Flutter pan/zoom.
        val halfHeight = (planViewportHeight / (2.0 * planZoom)).coerceIn(0.3, 200.0)
        if (projectionMode == "topDown") {
          topDownZoom = halfHeight
        } else {
          orbitDistance = (halfHeight / 0.6).coerceIn(minimumPlanarOrbitDistance(), 250.0)
        }
      }
    } else if (orbitCenterPayload != null) {
      orbitCenter = toFilamentPoint(orbitCenterPayload)
    }
    // Flutter and Filament now use the same orbit yaw convention.  Do not
    // mirror it here: doing so made a horizontal drag rotate the model in the
    // opposite direction in the native 3D viewport.
    if (projectionMode == "isometric") {
      orbitYawRadians = toDouble(payload?.get("orbitYawRadians"))
        ?: orbitYawRadians
      orbitPitchRadians = toDouble(payload?.get("orbitPitchRadians")) ?: orbitPitchRadians
    }
    val distance = toDouble(payload?.get("orbitDistance"))
    val zoom = toDouble(payload?.get("orbitZoomScale"))
    if (distance != null && !isPlanarProjection()) {
      orbitDistance = (distance / (zoom ?: 1.0)).coerceIn(minimumOrbitDistance(), 250.0)
    }
    configureCameraProjection()
    updateOrbitCamera()
    // The Flutter controller coalesces planar camera updates to one call per
    // frame. Render the new state once instead of extending a native 500 ms
    // animation window for every pointer event.
    requestRender()
    invalidate()
  }

  fun setDisplayStyle(style: String) {
    if (displayStyle == style) return
    displayStyle = style
    // Solid is a clean, unlit coordination view; Shaded owns scene lighting
    // and the optional real shadow path.
    applyDisplayLightingPreset()
    filamentView?.setShadowingEnabled(realShadowVisible())
    selectionOverlay.setDisplayStyle(style)
    if (nativeBimCache != null) {
      rebuildNativeBimCacheEdgeBatches()
    }
    // Wire hides Filament faces entirely; do not churn thousands of material
    // instances for a pass that is not visible. The desired face material is
    // applied only when Solid or Shaded becomes active again.
    if (style != "wireframe") refreshFaceMaterials()
    if (style != "wireframe" && shadowsEnabled && projectionMode == "isometric" &&
      groundReceiver == null && currentScene != null && materialBuilderReady
    ) {
      createGroundReceiver(engine ?: return, scene ?: return, currentScene!!)
    }
    syncVisibility()
    refreshTintState()
    updateStatus(if (style == "wireframe") "Wireframe: faces hidden, mesh edges shown." else null)
    requestRender(250L)
    invalidate()
  }

  private fun rebuildNativeBimCacheEdgeBatches() {
    val engine = engine ?: return
    val scene = scene ?: return
    val cache = nativeBimCache ?: return
    destroyEdgeBatches(engine, scene)
    // Native cache edges are also needed in Solid/Shaded.  They are generated
    // from the complete chunk topology below, so this is an architectural
    // contour pass rather than a second wireframe representation.
    val edgeChunks = linkedMapOf<EdgeBatchKey, MutableList<GeometryData>>()
    nativeCacheResidentChunks.forEach { index ->
      val chunk = cache.chunks.getOrNull(index) ?: return@forEach
      nativeCacheEdgeGeometry(chunk)?.let { geometry ->
        val key = EdgeBatchKey(
          kind = normalizeKind(chunk.kind),
          levelId = chunk.levelId,
          tileX = kotlin.math.floor((geometry.bounds.min.x + geometry.bounds.max.x) * 0.5 / 24.0).toInt(),
          tileZ = kotlin.math.floor((geometry.bounds.min.z + geometry.bounds.max.z) * 0.5 / 24.0).toInt(),
          nativeKindMask = chunk.kindMask,
        )
        edgeChunks.getOrPut(key) { mutableListOf() }.add(geometry)
      }
    }
    createEdgeBatches(engine, scene, edgeChunks)
    updateMetrics()
    renderDirty = true
  }

  fun setViewportTheme(theme: String) {
    val normalized = when (theme) {
      "standardDark", "amoledBlack" -> theme
      else -> "light"
    }
    if (viewportTheme == normalized) return
    viewportTheme = normalized
    applyViewportTheme()
    if (materialBuilderReady) refreshTintState()
    syncVisibility()
    requestRender(120L)
    invalidate()
  }

  fun setHdriVisible(visible: Boolean) {
    val available = hdriSkybox != null
    hdriVisible = visible && available
    applyViewportTheme()
    syncVisibility()
    requestRender(180L)
    invalidate()
    updateStatus(
      when {
        hdriVisible -> "HDRI background visible."
        visible && !available -> "HDRI background is unavailable; neutral background kept."
        else -> "HDRI background hidden; IBL lighting remains active."
      },
    )
  }

  private fun applyViewportTheme() {
    val background = when (viewportTheme) {
      "standardDark" -> intArrayOf(32, 36, 39)
      "amoledBlack" -> intArrayOf(0, 0, 0)
      else -> intArrayOf(243, 247, 244)
    }
    val clear = when (viewportTheme) {
      "standardDark" -> doubleArrayOf(0.125, 0.141, 0.153, 1.0)
      "amoledBlack" -> doubleArrayOf(0.0, 0.0, 0.0, 1.0)
      else -> doubleArrayOf(0.985, 0.99, 0.985, 1.0)
    }
    val sky = when (viewportTheme) {
      "standardDark" -> floatArrayOf(0.018f, 0.021f, 0.024f, 1.0f)
      "amoledBlack" -> floatArrayOf(0.0f, 0.0f, 0.0f, 1.0f)
      else -> floatArrayOf(0.985f, 0.99f, 0.985f, 1.0f)
    }
    setBackgroundColor(Color.rgb(background[0], background[1], background[2]))
    renderer?.setClearOptions(Renderer.ClearOptions().apply {
      this.clear = true
      clearColor = clear
    })
    selectionOverlay.setViewportTheme(viewportTheme)
    val engine = engine ?: return
    val nativeScene = scene ?: return
    if (hdriVisible && hdriSkybox != null) {
      skybox = hdriSkybox
      nativeScene.skybox = hdriSkybox
    } else {
      val previousColorSkybox = colorSkybox
      val nextColorSkybox = Skybox.Builder()
        .color(sky[0], sky[1], sky[2], sky[3])
        .build(engine)
      colorSkybox = nextColorSkybox
      skybox = nextColorSkybox
      nativeScene.skybox = nextColorSkybox
      previousColorSkybox?.let { old ->
        if (old !== hdriSkybox && old !== nextColorSkybox) engine.destroySkybox(old)
      }
    }
  }

  private fun viewportEdgeColor(): FloatArray {
    // Shaded keeps readable silhouette/feature edges, but they should recede
    // behind the lit surfaces instead of looking like a black cartoon outline.
    if (displayStyle == "shaded") {
      return if (viewportTheme == "light") {
        floatArrayOf(0.30f, 0.34f, 0.38f, 1.0f)
      } else {
        floatArrayOf(0.47f, 0.51f, 0.55f, 1.0f)
      }
    }
    return if (viewportTheme == "light") {
      floatArrayOf(0.0f, 0.0f, 0.0f, 1.0f)
    } else {
      floatArrayOf(0.72f, 0.77f, 0.80f, 1.0f)
    }
  }

  private fun viewportGridColor(): FloatArray = if (viewportTheme == "light") {
    floatArrayOf(0.30f, 0.36f, 0.37f, 0.08f)
  } else {
    floatArrayOf(0.78f, 0.82f, 0.84f, 0.045f)
  }

  private fun viewportGroundColor(): FloatArray = if (viewportTheme == "light") {
    floatArrayOf(0.88f, 0.89f, 0.90f, 1.0f)
  } else if (viewportTheme == "amoledBlack") {
    floatArrayOf(0.0f, 0.0f, 0.0f, 1.0f)
  } else {
    floatArrayOf(0.0f, 0.0f, 0.0f, 1.0f)
  }

  fun setShadowsEnabled(enabled: Boolean) {
    if (shadowsEnabled == enabled) return
    shadowsEnabled = enabled
    sectionBoxHandler.removeCallbacks(shadowResume)
    val nativeEngine = engine
    val nativeScene = scene
    sunLightEntity?.let { entity ->
      nativeEngine?.let { runtimeEngine ->
        val lightInstance = runtimeEngine.lightManager.getInstance(entity)
        if (lightInstance != 0) {
          runtimeEngine.lightManager.setShadowCaster(lightInstance, enabled)
        }
      }
      if (enabled) nativeScene?.addEntity(entity) else nativeScene?.removeEntity(entity)
    }
    // Rebuild once on an explicit toggle so the receiver and shadow state are
    // removed from the current frame immediately. Camera movement never
    // enters this path.
    if (nativeEngine != null && nativeScene != null && materialBuilderReady) {
      rebuildScene()
    }
    Log.i(TAG, "Shadow toggle: enabled=$enabled, receiver=${groundReceiver != null}, static=${staticShadowBatch != null}")
    filamentView?.setShadowingEnabled(realShadowVisible())
    syncVisibility()
    // TextureView can retain the previous shadow-receiver frame after the
    // receiver entity is removed. Submit a short burst of clean frames so the
    // cleared background is actually presented. This is only for an explicit
    // toggle; camera movement still uses the event-driven shadow pause path.
    requestRender(300L)
    renderSurface.invalidate()
    sectionBoxHandler.postDelayed({
      if (!disposed) {
        renderDirty = true
        renderSurface.invalidate()
        requestRender()
      }
    }, 120L)
    updateStatus(if (enabled) "Real shadows enabled." else "Real shadows disabled.")
    invalidate()
  }

  private fun refreshFaceMaterials() {
    val engine = engine ?: return
    val fallback = material ?: return
    val manager = engine.renderableManager
    for (entry in renderables.values) {
      val target = materialForObject(entry.objectData, fallback)
      if (entry.material === target) continue
      val replacement = target.createInstance()
      applySectionBoxState(replacement)
      applyDisplayStyle(replacement)
      val instance = manager.getInstance(entry.entity)
      if (instance != 0) manager.setMaterialInstanceAt(instance, 0, replacement)
      engine.destroyMaterialInstance(entry.materialInstance)
      entry.material = target
      entry.materialInstance = replacement
    }
    for (batch in faceBatches) {
      val target = materialForObject(batch.representative, fallback)
      if (batch.material === target) continue
      val replacement = target.createInstance()
      applySectionBoxState(replacement)
      applyDisplayStyle(replacement)
      val instance = manager.getInstance(batch.entity)
      if (instance != 0) manager.setMaterialInstanceAt(instance, 0, replacement)
      engine.destroyMaterialInstance(batch.materialInstance)
      batch.material = target
      batch.materialInstance = replacement
    }
    for (group in instanceFaceGroups) {
      val target = materialForObject(group.representative, fallback)
      if (group.material === target) continue
      val replacement = target.createInstance().also { instance ->
        applySectionBoxState(instance)
        applyDisplayStyle(instance)
        instance.setParameter(
          "baseColor", Colors.RgbaType.LINEAR,
          group.baseColor[0], group.baseColor[1], group.baseColor[2], group.baseColor[3],
        )
      }
      for (entity in group.entities) {
        val instance = manager.getInstance(entity)
        if (instance != 0) manager.setMaterialInstanceAt(instance, 0, replacement)
      }
      engine.destroyMaterialInstance(group.materialInstance)
      group.material = target
      group.materialInstance = replacement
    }
  }

  fun setVisibleKinds(kinds: Set<String>) {
    visibleKinds.clear()
    visibleKinds.addAll(kinds.map { normalizeKind(it) })
    selectionOverlay.setVisibleKinds(visibleKinds)
    Log.i(
      TAG,
      "Visibility kinds=${visibleKinds.sorted().joinToString(",")} " +
        "faceAttached=${faceBatches.count { it.attached }} " +
        "edgeAttached=${edgeBatches.count { it.attached }} " +
        "cache=${nativeBimCache != null}",
    )
    syncVisibility()
    updateStatus()
    invalidate()
  }

  /** One universal ClipVolume drives the native box and triangle clipping. */
  fun setSectionBox(payload: Map<*, *>?) {
    val enabled = payload?.get("enabled") as? Boolean ?: false
    val minPoint = parsePoint(payload?.get("min"))
    val maxPoint = parsePoint(payload?.get("max"))
    // Flutter replays the disabled state while a view is initializing. It is
    // a no-op when no clip volume is active; rebuilding thousands of face and
    // edge batches here previously dominated large-template startup time.
    if (!enabled && clipVolume.mode == ClipVolumeMode.NONE) {
      selectionOverlay.setSectionBox(false, sectionBoxMin, sectionBoxMax)
      return
    }
    // Flutter may replay its last bridge snapshot after a native gesture.
    // Once active, the native ClipVolume owns the six live planes; accepting
    // that stale replay would snap both the border and camera back to their
    // initial bounds in the middle of a drag.
    if (enabled && sectionBoxEnabled && minPoint != null && maxPoint != null) {
      return
    }
    if (enabled && minPoint != null && maxPoint != null) {
      sectionSceneMin = minPoint
      sectionSceneMax = maxPoint
      val corners = listOf(
        ScenePoint(minPoint.x, minPoint.y, minPoint.z), ScenePoint(minPoint.x, minPoint.y, maxPoint.z),
        ScenePoint(minPoint.x, maxPoint.y, minPoint.z), ScenePoint(minPoint.x, maxPoint.y, maxPoint.z),
        ScenePoint(maxPoint.x, minPoint.y, minPoint.z), ScenePoint(maxPoint.x, minPoint.y, maxPoint.z),
        ScenePoint(maxPoint.x, maxPoint.y, minPoint.z), ScenePoint(maxPoint.x, maxPoint.y, maxPoint.z),
      ).map(::toFilamentPoint)
      val bounds = boundsForPoints(corners)
      // Scene bounds are derived from doubles while Filament stores float
      // vertices. Keep a small outward tolerance so an untouched box never
      // discards a face solely because of float rounding at its boundary.
      val tolerance = 0.05
      val boxMin = ScenePoint(bounds.min.x - tolerance, bounds.min.y - tolerance, bounds.min.z - tolerance)
      val boxMax = ScenePoint(bounds.max.x + tolerance, bounds.max.y + tolerance, bounds.max.z + tolerance)
      clipVolume = ClipVolumeState(
        mode = ClipVolumeMode.SECTION_BOX,
        planes = boxClipPlanes(boxMin, boxMax),
        boxMin = boxMin,
        boxMax = boxMax,
      )
      fitSectionBoxOnNextRebuild = true
    } else {
      resetClipVolumeState()
    }
    applySectionBoxState()
    selectionOverlay.setSectionBox(sectionBoxEnabled, sectionBoxMin, sectionBoxMax)
    sectionBoxHandler.removeCallbacks(sectionBoxRebuild)
    sectionBoxHandler.post(sectionBoxRebuild)
    invalidate()
  }

  /**
   * Uses the same ClipVolume as Section Box, but presents it as an
   * architectural section: the cut line is the near plane and the camera
   * looks into the retained half of the real, full RenderScene.
   */
  fun setSectionView(payload: Map<*, *>?) {
    val enabled = payload?.get("enabled") as? Boolean ?: false
    val start = parsePoint(payload?.get("start"))
    val end = parsePoint(payload?.get("end"))
    if (!enabled || start == null || end == null) {
      if (clipVolume.mode != ClipVolumeMode.SECTION_VIEW) return
      resetClipVolumeState()
      sectionBoxHandler.removeCallbacks(sectionBoxRebuild)
      sectionBoxHandler.post(sectionBoxRebuild)
      return
    }
    selectionOverlay.setSectionBox(false, sectionBoxMin, sectionBoxMax)
    val first = toFilamentPoint(start.copy(z = 0.0))
    val second = toFilamentPoint(end.copy(z = 0.0))
    val length = kotlin.math.hypot(second.x - first.x, second.z - first.z)
    if (length <= 1.0e-6) return
    val along = ScenePoint((second.x - first.x) / length, 0.0, (second.z - first.z) / length)
    // Left side of the authored line is retained. The camera sits on the
    // removed side and looks through the exact same plane used for clipping.
    val inward = ScenePoint(-along.z, 0.0, along.x)
    val lineMargin = 0.05
    clipVolume = ClipVolumeState(
      mode = ClipVolumeMode.SECTION_VIEW,
      planes = listOf(
        planeThrough(first, along, lineMargin),
        planeThrough(second, ScenePoint(-along.x, 0.0, -along.z), lineMargin),
        planeThrough(first, inward, 0.001),
      ),
      sectionDirection = inward,
      sectionCenter = ScenePoint(
        (first.x + second.x) * 0.5,
        (sceneMetrics.bounds.min.y + sceneMetrics.bounds.max.y) * 0.5,
        (first.z + second.z) * 0.5,
      ),
      sectionLength = length,
    )
    projectionMode = "section"
    // Flutter has already supplied the authoritative planar center and scale
    // immediately before this clip state arrives. Preserve them instead of
    // fitting a second native camera, otherwise the model drifts away from
    // Flutter's level overlay on the first section frame.
    // Keep the camera on the removed side of the authored cut line so the
    // newly generated cut faces are visible instead of the opposite facade.
    orbitYawRadians = kotlin.math.atan2(-inward.z, -inward.x)
    orbitPitchRadians = 0.0
    fitSectionViewOnNextRebuild = false
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    sectionBoxHandler.removeCallbacks(sectionBoxRebuild)
    sectionBoxHandler.post(sectionBoxRebuild)
    invalidate()
  }

  private fun planeThrough(point: ScenePoint, normal: ScenePoint, allowance: Double = 0.0): ClipPlane =
    ClipPlane(normal, -(normal.x * point.x + normal.y * point.y + normal.z * point.z) + allowance)

  private fun boxClipPlanes(minPoint: ScenePoint, maxPoint: ScenePoint): List<ClipPlane> = listOf(
    ClipPlane(ScenePoint(1.0, 0.0, 0.0), -minPoint.x),
    ClipPlane(ScenePoint(-1.0, 0.0, 0.0), maxPoint.x),
    ClipPlane(ScenePoint(0.0, 1.0, 0.0), -minPoint.y),
    ClipPlane(ScenePoint(0.0, -1.0, 0.0), maxPoint.y),
    ClipPlane(ScenePoint(0.0, 0.0, 1.0), -minPoint.z),
    ClipPlane(ScenePoint(0.0, 0.0, -1.0), maxPoint.z),
  )

  private fun fitCameraToSectionBox() {
    if (!sectionBoxEnabled || projectionMode != "isometric") return
    val width = sectionBoxMax.x - sectionBoxMin.x
    val height = sectionBoxMax.y - sectionBoxMin.y
    val depth = sectionBoxMax.z - sectionBoxMin.z
    val span = max(width, max(height, depth))
    orbitCenter = ScenePoint(
      (sectionBoxMin.x + sectionBoxMax.x) * 0.5,
      (sectionBoxMin.y + sectionBoxMax.y) * 0.5,
      (sectionBoxMin.z + sectionBoxMax.z) * 0.5,
    )
    orbitDistance = max(span * 2.00, 8.0)
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
  }

  private fun fitCameraToSectionView() {
    val inward = clipVolume.sectionDirection ?: return
    val bounds = sceneMetrics.bounds
    val height = max(bounds.max.y - bounds.min.y, 0.001)
    val halfHeight = max(
      height * 0.5,
      clipVolume.sectionLength / (2.0 * max(aspectRatio(), 0.1)),
    ) * 1.10
    orbitCenter = clipVolume.sectionCenter.copy(
      y = (bounds.min.y + bounds.max.y) * 0.5,
    )
    orbitDistance = max(halfHeight / 0.6, 3.0)
    orbitYawRadians = kotlin.math.atan2(-inward.z, -inward.x)
    orbitPitchRadians = 0.0
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
  }

  private fun applySectionBoxState() {
    for (entry in renderables.values) {
      applySectionBoxState(entry.materialInstance)
    }
    for (batch in faceBatches) applySectionBoxState(batch.materialInstance)
    for (group in instanceFaceGroups) applySectionBoxState(group.materialInstance)
    for (batch in edgeBatches) applySectionBoxState(batch.materialInstance)
    gridBatch?.let { batch -> applySectionBoxState(batch.materialInstance) }
    requestRender()
  }

  private fun applySectionBoxState(instance: MaterialInstance) {
    instance.setParameter("sectionBoxEnabled", if (sectionBoxEnabled) 1.0f else 0.0f)
    instance.setParameter("sectionBoxMin", sectionBoxMin.x.toFloat(), sectionBoxMin.y.toFloat(), sectionBoxMin.z.toFloat(), 0.0f)
    instance.setParameter("sectionBoxMax", sectionBoxMax.x.toFloat(), sectionBoxMax.y.toFloat(), sectionBoxMax.z.toFloat(), 0.0f)
  }

  fun selectElement(elementId: Any?) {
    selectedElementId = toLong(elementId)
    selectedElementIds = selectedElementId?.let { setOf(it) } ?: emptySet()
    selectionOverlay.setSelection(selectedElementIds, selectedElementId)
    refreshTintState()
    updateStatus()
    invalidate()
  }

  fun setSelection(selection: Map<*, *>?) {
    val ids = (selection?.get("ids") as? List<*>)
      ?.mapNotNull { toLong(it) }
      ?.toSet()
      ?: emptySet()
    selectedElementIds = ids
    selectedElementId = toLong(selection?.get("activeId"))?.takeIf { ids.contains(it) }
    selectionOverlay.setSelection(selectedElementIds, selectedElementId)
    refreshTintState()
    updateStatus()
    invalidate()
  }

  fun setSelectionRectangle(payload: Map<*, *>?) {
    val left = toDouble(payload?.get("left"))
    val top = toDouble(payload?.get("top"))
    val right = toDouble(payload?.get("right"))
    val bottom = toDouble(payload?.get("bottom"))
    if (left == null || top == null || right == null || bottom == null) {
      selectionOverlay.clear()
      return
    }
    val density = resources.displayMetrics.density
    selectionOverlay.setRectangle(
      RectF(
        (left * density).toFloat(),
        (top * density).toFloat(),
        (right * density).toFloat(),
        (bottom * density).toFloat(),
      ),
      payload?.get("crossing") as? Boolean ?: false,
    )
  }

  fun highlightElement(elementId: Any?) {
    highlightedElementId = toLong(elementId)
    refreshTintState()
    updateStatus()
    invalidate()
  }

  override fun onNativeWindowChanged(surface: Surface) {
    val engine = engine ?: return
    swapChain = engine.createSwapChain(surface)
    surfaceReady = true
    statusMessage = "Surface attached."
    Log.i(TAG, statusMessage)
    updateStatus()
    renderSurface.display?.let { display ->
      renderer?.let { displayHelper.attach(it, display) }
    }
    requestRender()
  }

  override fun onDetachedFromSurface() {
    surfaceReady = false
    displayHelper.detach()
    swapChain?.let { chain ->
      engine?.destroySwapChain(chain)
    }
    swapChain = null
    statusMessage = "Surface detached."
    Log.i(TAG, statusMessage)
    updateStatus()
    cancelFrame()
  }

  override fun onResized(width: Int, height: Int) {
    filamentView?.viewport = Viewport(0, 0, width.coerceAtLeast(1), height.coerceAtLeast(1))
    // Reserve the upper-right quadrant for Flutter's compact model card.
    // Telemetry wraps here instead of disappearing behind that card.
    statusView.maxWidth = (width * 0.60f).toInt().coerceAtLeast(220)
    // Flutter owns every planar camera's scale and center. A TextureView
    // resize must only update the projection matrix; fitting here uses the
    // native 3D bounds and makes a floor plan open zoomed too far out until
    // the next Flutter gesture restores its authoritative camera.
    if (isPlanarProjection()) {
      configureCameraProjection()
      updateOrbitCamera()
    } else {
      fitCamera()
    }
    syncVisualOverlay()
    requestRender()
  }

  override fun doFrame(frameTimeNanos: Long) {
    framePosted = false
    updateOrbitInertia(frameTimeNanos)
    driveAutomatedBenchmark(frameTimeNanos)
    val renderer = renderer
    val view = filamentView
    val swapChain = swapChain
    // A static BIM viewport is event-driven. Rendering forever at an idle
    // 30 FPS made every face and border draw call a permanent battery cost.
    // Gestures retain display-cadence feedback; after interaction one final
    // dirty frame is submitted and the Choreographer loop goes completely idle.
    val benchmarking = rendererBenchmark != null
    val interactive = touching || orbitInertiaActive || benchmarking || SystemClock.uptimeMillis() < interactiveUntilMs
    val shouldRender = renderDirty || interactive
    if (shouldRender && renderer != null && view != null && swapChain != null && renderer.beginFrame(swapChain, frameTimeNanos)) {
      val submitStartedNanos = SystemClock.elapsedRealtimeNanos()
      renderer.render(view)
      renderer.endFrame()
      val submitMs = (SystemClock.elapsedRealtimeNanos() - submitStartedNanos).toDouble() / 1_000_000.0
      renderedFrameCount += 1
      lastRenderedFrameNanos = frameTimeNanos
      renderDirty = false
      recordAutomatedBenchmarkFrame(frameTimeNanos, submitMs)
      sampleTelemetry()
    }
    if (interactive || (renderDirty && surfaceReady)) scheduleFrame()
  }

  private fun driveAutomatedBenchmark(frameTimeNanos: Long) {
    val benchmark = rendererBenchmark ?: return
    if (benchmark.phase == "waiting" || benchmark.phase == "complete") return
    val elapsedMs = (frameTimeNanos - benchmark.phaseStartedNanos).toDouble() / 1_000_000.0
    when (benchmark.phase) {
      "idle" -> if (elapsedMs >= 1800.0) {
        benchmark.phase = "orbit"
        benchmark.phaseStartedNanos = frameTimeNanos
      }
      "orbit" -> {
        orbitYawRadians += 0.010
        orbitPitchRadians = (orbitPitchRadians + 0.0015).coerceIn(Math.toRadians(8.0), Math.toRadians(72.0))
        configureCameraProjection()
        updateOrbitCamera()
        renderDirty = true
        if (elapsedMs >= 3200.0) {
          benchmark.phase = "zoomPan"
          benchmark.phaseStartedNanos = frameTimeNanos
        }
      }
      "zoomPan" -> {
        orbitDistance = max(3.0, orbitDistance * 0.997)
        val scale = max(orbitDistance, 3.0) * 0.0012
        orbitCenter = orbitCenter.copy(x = orbitCenter.x + scale, z = orbitCenter.z - scale * 0.55)
        configureCameraProjection()
        updateOrbitCamera()
        renderDirty = true
        if (elapsedMs >= 3200.0) {
          benchmark.phase = "complete"
          finishAutomatedBenchmark(benchmark)
        }
      }
    }
  }

  private fun recordAutomatedBenchmarkFrame(frameTimeNanos: Long, submitMs: Double) {
    val benchmark = rendererBenchmark ?: return
    if (benchmark.mode == "NEW_BIMCACHE" && benchmark.cacheAppliedNanos == 0L) return
    if (benchmark.firstVisibleNanos == 0L) {
      benchmark.firstVisibleNanos = SystemClock.elapsedRealtimeNanos()
      if (benchmark.fullReadyNanos != 0L) {
        benchmark.phase = "idle"
        benchmark.phaseStartedNanos = frameTimeNanos
      }
    }
    val phase = benchmark.phase
    if (phase == "waiting" || phase == "complete") return
    if (benchmark.previousFrameNanos != 0L) {
      val intervalMs = (frameTimeNanos - benchmark.previousFrameNanos).toDouble() / 1_000_000.0
      if (intervalMs in 0.1..1000.0) benchmark.samples(benchmark.frameIntervalsMs, phase).add(intervalMs)
    }
    benchmark.samples(benchmark.cpuSubmitMs, phase).add(submitMs)
    benchmark.previousFrameNanos = frameTimeNanos
  }

  private fun benchmarkAverage(values: List<Double>): Double =
    if (values.isEmpty()) 0.0 else values.average()

  private fun benchmarkPercentile(values: List<Double>, percentile: Double): Double {
    if (values.isEmpty()) return 0.0
    val sorted = values.sorted()
    val index = ((sorted.size - 1) * percentile).toInt().coerceIn(0, sorted.lastIndex)
    return sorted[index]
  }

  private fun benchmarkFps(values: List<Double>): Double {
    val average = benchmarkAverage(values)
    return if (average <= 0.0) 0.0 else 1000.0 / average
  }

  private fun finishAutomatedBenchmark(benchmark: RendererBenchmarkRun) {
    if (rendererBenchmark !== benchmark) return
    removeCallbacks(benchmarkTick)
    val allFrameIntervals = benchmark.frameIntervalsMs.values.flatten()
    val allCpuSubmit = benchmark.cpuSubmitMs.values.flatten()
    val processMemory = (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()).toDouble() / (1024.0 * 1024.0)
    val nativeHeapMb = android.os.Debug.getNativeHeapAllocatedSize().toDouble() / (1024.0 * 1024.0)
    val gcNow = android.os.Debug.getRuntimeStat("art.gc.gc-count")?.toLongOrNull()
    val gcDelta = if (benchmark.gcCountAtStart != null && gcNow != null) gcNow - benchmark.gcCountAtStart!! else -1L
    val materialCount = (
      renderables.values.map { System.identityHashCode(it.material) } +
        faceBatches.map { System.identityHashCode(it.material) } +
        instanceFaceGroups.map { System.identityHashCode(it.material) }
      ).distinct().size
    val estimatedGpuBufferBytes =
      faceBatches.sumOf { it.vertexCount.toLong() * 12L + it.indexCount.toLong() * 4L } +
        renderables.values.sumOf { it.vertexBuffer.vertexCount.toLong() * 28L + it.indexBuffer.indexCount.toLong() * 4L } +
        instanceFaceGroups.sumOf { it.vertexCount.toLong() * 28L + it.indexCount.toLong() * 4L }
    val sourceCacheBytes = benchmark.cachePath?.let { path -> java.io.File(path).takeIf { it.isFile }?.length() } ?: 0L
    val sourceObjectCount = nativeBimCache?.primitives?.size ?: sceneMetrics.objectCount
    fun phaseFps(name: String) = benchmarkFps(benchmark.frameIntervalsMs[name] ?: emptyList())
    val readyMs = if (benchmark.fullReadyNanos == 0L) -1L else (benchmark.fullReadyNanos - benchmark.startedNanos) / 1_000_000L
    val visibleMs = if (benchmark.firstVisibleNanos == 0L) -1L else (benchmark.firstVisibleNanos - benchmark.startedNanos) / 1_000_000L
    val applyMs = if (benchmark.cacheAppliedNanos == 0L) -1L else (benchmark.cacheAppliedNanos - benchmark.startedNanos) / 1_000_000L
    val compileMs = benchmark.cacheCompileStats?.elapsedMs ?: -1L
    Log.i(
      "TbeBenchmark",
      "RESULT mode=${benchmark.mode} firstVisibleMs=$visibleMs fullReadyMs=$readyMs cacheAppliedMs=$applyMs " +
        "cacheCompileMs=$compileMs cacheBytes=$sourceCacheBytes fpsIdle=${benchmarkFps(benchmark.frameIntervalsMs["idle"] ?: emptyList()).format(2)} " +
        "fpsOrbit=${phaseFps("orbit").format(2)} fpsZoomPan=${phaseFps("zoomPan").format(2)} " +
        "frameAvgMs=${benchmarkAverage(allFrameIntervals).format(2)} frameP95Ms=${benchmarkPercentile(allFrameIntervals, 0.95).format(2)} " +
        "frameP99Ms=${benchmarkPercentile(allFrameIntervals, 0.99).format(2)} cpuSubmitAvgMs=${benchmarkAverage(allCpuSubmit).format(2)} " +
        "cpuSubmitP95Ms=${benchmarkPercentile(allCpuSubmit, 0.95).format(2)} objects=$sourceObjectCount triangles=${sceneMetrics.indexCount / 3} " +
        "vertices=${sceneMetrics.vertexCount} renderables=${renderables.size + faceBatches.size + instanceFaceGroups.size} " +
        "drawCalls=${renderables.size + faceBatches.size + instanceFaceGroups.size + edgeBatches.size} materials=$materialCount " +
        "loadedChunks=${if (nativeBimCache != null) nativeCacheResidentChunks.size else faceBatches.size} " +
        "visibleChunks=${faceBatches.count { it.attached }} estimatedGpuBufferBytes=$estimatedGpuBufferBytes " +
        "javaHeapMb=${processMemory.format(1)} nativeHeapMb=${nativeHeapMb.format(1)} gcDelta=$gcDelta",
    )
    rendererBenchmark = null
  }

  private fun updateOrbitInertia(frameTimeNanos: Long) {
    if (!orbitInertiaActive || projectionMode != "isometric") return
    if (lastInertiaFrameNanos == 0L) {
      lastInertiaFrameNanos = frameTimeNanos
      return
    }
    val deltaSeconds = ((frameTimeNanos - lastInertiaFrameNanos).toDouble() / 1_000_000_000.0)
      .coerceIn(0.0, 0.05)
    lastInertiaFrameNanos = frameTimeNanos
    if (deltaSeconds <= 0.0) return

    orbitYawRadians += orbitYawVelocity * deltaSeconds
    orbitPitchRadians = (orbitPitchRadians + orbitPitchVelocity * deltaSeconds)
      .coerceIn(Math.toRadians(0.1), Math.toRadians(88.0))
    val friction = Math.exp(-6.5 * deltaSeconds)
    orbitYawVelocity *= friction
    orbitPitchVelocity *= friction
    if (max(kotlin.math.abs(orbitYawVelocity), kotlin.math.abs(orbitPitchVelocity)) < 0.015) {
      cancelOrbitInertia()
      return
    }
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    renderDirty = true
  }

  private fun cancelOrbitInertia() {
    orbitInertiaActive = false
    lastInertiaFrameNanos = 0L
    orbitYawVelocity = 0.0
    orbitPitchVelocity = 0.0
  }

  private fun startOrbitInertia() {
    if (projectionMode != "isometric") return
    val speed = max(kotlin.math.abs(orbitYawVelocity), kotlin.math.abs(orbitPitchVelocity))
    if (speed < 0.10) {
      cancelOrbitInertia()
      return
    }
    orbitYawVelocity = orbitYawVelocity.coerceIn(-3.2, 3.2)
    orbitPitchVelocity = orbitPitchVelocity.coerceIn(-2.4, 2.4)
    orbitInertiaActive = true
    lastInertiaFrameNanos = 0L
    requestRender()
  }

  override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
    disposeResources()
  }

  fun disposeResources() {
    if (disposed) {
      return
    }
    disposed = true
    sectionBoxHandler.removeCallbacks(sectionBoxRebuild)
    sectionBoxHandler.removeCallbacks(shadowResume)
    cancelFrame()
    uiHelper.detach()
    displayHelper.detach()
    swapChain?.let { chain ->
      engine?.destroySwapChain(chain)
    }
    clearScene()
    sunLightEntity?.let { entity ->
      scene?.removeEntity(entity)
      engine?.destroyEntity(entity)
      EntityManager.get().destroy(entity)
    }
    sunLightEntity = null
    fillLightEntity?.let { entity ->
      scene?.removeEntity(entity)
      engine?.destroyEntity(entity)
      EntityManager.get().destroy(entity)
    }
    fillLightEntity = null
    scene?.let { scene ->
      engine?.destroyScene(scene)
    }
    filamentView?.let { view ->
      engine?.destroyView(view)
    }
    colorGrading?.let { grading ->
      engine?.destroyColorGrading(grading)
    }
    colorSkybox?.let { box ->
      engine?.destroySkybox(box)
    }
    hdriSkybox?.let { box ->
      if (box !== colorSkybox) engine?.destroySkybox(box)
    }
    indirectLight?.let { light -> engine?.destroyIndirectLight(light) }
    indirectLightTexture?.let { texture -> engine?.destroyTexture(texture) }
    hdriSkyboxTexture?.let { texture -> engine?.destroyTexture(texture) }
    renderer?.let { renderer ->
      engine?.destroyRenderer(renderer)
    }
    camera?.let { camera ->
      engine?.destroyCameraComponent(camera.entity)
      EntityManager.get().destroy(camera.entity)
    }
    material?.let { material ->
      engine?.destroyMaterial(material)
    }
    wallMaterial?.let { material -> engine?.destroyMaterial(material) }
    windowMaterial?.let { material -> engine?.destroyMaterial(material) }
    plasterMaterial?.let { material -> engine?.destroyMaterial(material) }
    woodMaterial?.let { material -> engine?.destroyMaterial(material) }
    floorMaterial?.let { material -> engine?.destroyMaterial(material) }
    roofMaterial?.let { material -> engine?.destroyMaterial(material) }
    concreteMaterial?.let { material -> engine?.destroyMaterial(material) }
    solidMaterial?.let { material -> engine?.destroyMaterial(material) }
    solidWindowMaterial?.let { material -> engine?.destroyMaterial(material) }
    edgeMaterial?.let { material -> engine?.destroyMaterial(material) }
    gridMaterial?.let { material -> engine?.destroyMaterial(material) }
    groundMaterial?.let { material -> engine?.destroyMaterial(material) }
    shadowMaterial?.let { material -> engine?.destroyMaterial(material) }
    engine?.destroy()
    swapChain = null
    renderer = null
    scene = null
    filamentView = null
    camera = null
    skybox = null
    colorSkybox = null
    hdriSkybox = null
    hdriSkyboxTexture = null
    indirectLight = null
    indirectLightTexture = null
    colorGrading = null
    engine = null
    material = null
    wallMaterial = null
    windowMaterial = null
    plasterMaterial = null
    woodMaterial = null
    floorMaterial = null
    roofMaterial = null
    concreteMaterial = null
    solidMaterial = null
    solidWindowMaterial = null
    edgeMaterial = null
    gridMaterial = null
    groundMaterial = null
    shadowMaterial = null
    materialBuilderReady = false
  }

  private fun buildRuntimeMaterial(): Boolean {
    val engine = engine ?: return false
    return try {
      material = buildMaterial(engine, "RenderSceneArchitectural", ARCHITECTURAL_LIT_MAT, lit = true)
      wallMaterial = buildMaterial(engine, "RenderSceneWall", ARCHITECTURAL_LIT_MAT, lit = true)
      windowMaterial = buildMaterial(engine, "RenderSceneWindowGlass", ARCHITECTURAL_LIT_MAT, transparent = true, lit = true)
      plasterMaterial = buildMaterial(engine, "RenderScenePlaster", ARCHITECTURAL_LIT_MAT, lit = true)
      woodMaterial = buildMaterial(engine, "RenderSceneWood", ARCHITECTURAL_LIT_MAT, lit = true)
      floorMaterial = buildMaterial(engine, "RenderSceneFloor", ARCHITECTURAL_LIT_MAT, lit = true)
      roofMaterial = buildMaterial(engine, "RenderSceneRoof", ARCHITECTURAL_LIT_MAT, lit = true)
      concreteMaterial = buildMaterial(engine, "RenderSceneConcrete", ARCHITECTURAL_LIT_MAT, lit = true)
      // Solid is deliberately unlit: it stays clean white and does not inherit
      // HDRI/Sun changes. Real lighting belongs to Shaded, where it can be
      // inspected without compromising the primary BIM coordination view.
      solidMaterial = buildMaterial(engine, "RenderSceneSolid", FLAT_COLOR_MAT, lit = false)
      solidWindowMaterial = buildMaterial(
        engine,
        "RenderSceneSolidWindow",
        FLAT_COLOR_MAT,
        transparent = true,
        lit = false,
      )
      edgeMaterial = buildMaterial(engine, "RenderSceneEdges", FLAT_COLOR_MAT, lit = false)
      gridMaterial = buildMaterial(
        engine,
        "RenderSceneGrid",
        GRID_MAT,
        transparent = true,
        lit = false,
        grid = true,
      )
      groundMaterial = buildMaterial(engine, "RenderSceneShadowReceiver", FLAT_COLOR_MAT, lit = true)
      shadowMaterial = buildMaterial(
        engine,
        "RenderSceneBakedShadow",
        FLAT_COLOR_MAT,
        transparent = true,
        lit = false,
      )
      if (listOf(material, wallMaterial, windowMaterial, plasterMaterial,
          woodMaterial, floorMaterial, roofMaterial, concreteMaterial,
           solidMaterial, solidWindowMaterial, edgeMaterial, gridMaterial,
           groundMaterial, shadowMaterial).any { it == null }) {
        statusMessage = "Filament material build returned an invalid package."
        updateStatus()
        return false
      }
      true
    } catch (error: Throwable) {
      statusMessage = "Filament material build failed: ${error.message ?: error::class.java.simpleName}"
      Log.e(TAG, statusMessage, error)
      updateStatus()
      false
    }
  }

  private fun buildMaterial(
    engine: Engine,
    name: String,
    source: String,
    transparent: Boolean = false,
    lit: Boolean = false,
    grid: Boolean = false,
  ): Material? {
      val builder = MaterialBuilder()
        .name(name)
        .shading(if (lit) MaterialBuilder.Shading.LIT else MaterialBuilder.Shading.UNLIT)
        .culling(MaterialBuilder.CullingMode.NONE)
        .doubleSided(true)
      .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "baseColor")
        .uniformParameter(MaterialBuilder.UniformType.FLOAT, "displayShade")
        .uniformParameter(MaterialBuilder.UniformType.FLOAT, "sectionBoxEnabled")
        .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "sectionBoxMin")
        .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "sectionBoxMax")
        .targetApi(MaterialBuilder.TargetApi.OPENGL)
        .platform(MaterialBuilder.Platform.MOBILE)
        .optimization(MaterialBuilder.Optimization.NONE)
      if (grid) {
        builder
          .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "gridCenter")
          .uniformParameter(MaterialBuilder.UniformType.FLOAT, "gridRadius")
          .uniformParameter(MaterialBuilder.UniformType.FLOAT, "gridFadeStart")
          .uniformParameter(MaterialBuilder.UniformType.FLOAT, "gridMinorStep")
          .uniformParameter(MaterialBuilder.UniformType.FLOAT, "gridMajorStep")
      }
      builder.material(source)
      if (transparent) {
        builder
          .blending(MaterialBuilder.BlendingMode.TRANSPARENT)
          .transparencyMode(MaterialBuilder.TransparencyMode.TWO_PASSES_TWO_SIDES)
          .depthWrite(false)
      }
      val packageData: MaterialPackage = builder.build(engine)
      if (!packageData.isValid) return null
      val packageBuffer = packageData.buffer.duplicate().apply { rewind() }
      return Material.Builder()
        .payload(packageBuffer, packageBuffer.remaining())
        .build(engine)
  }

  private fun rebuildNativeBimCacheScene(
    engine: Engine,
    scene: Scene,
    cache: NativeBimCacheBridge.NativeBimCache,
    fallbackMaterial: Material,
  ) {
    // Cache chunks are ordered by distance to the fitted camera target.  The
    // first few render immediately; the rest are posted in tiny GPU upload
    // slices so panning and gesture dispatch remain responsive on tablets.
    nativeCacheUploadRevision += 1L
    nativeCacheUploadPosted = false
    nativeCachePendingChunks.clear()
    nativeCacheResidentChunks.clear()
    nativeCacheEdgeBudgetRemaining = NATIVE_CACHE_EDGE_SEGMENT_BUDGET
    val revision = nativeCacheUploadRevision
    cache.chunks.indices
      .sortedBy { index -> nativeCacheChunkDistanceSquared(cache, index) }
      .forEach(nativeCachePendingChunks::addLast)
    uploadNativeBimCacheChunks(
      engine = engine,
      scene = scene,
      cache = cache,
      fallbackMaterial = fallbackMaterial,
      revision = revision,
      maxChunks = NATIVE_CACHE_INITIAL_UPLOAD_CHUNKS,
    )
    // Native cache rebuilds destroy auxiliary renderables as well. Recreate
    // the navigation grid here so a section-box toggle cannot leave the
    // viewport in a different visual state from a normal 3D load.
    if (projectionMode == "isometric") {
      currentScene?.let { createGridBatch(engine, scene, it) }
    }
    updateMetrics()
    renderDirty = true
  }

  private fun nativeCacheChunkDistanceSquared(
    cache: NativeBimCacheBridge.NativeBimCache,
    index: Int,
  ): Double {
    val bounds = transformBounds(cache.chunks[index].sourceBounds)
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerY = (bounds.min.y + bounds.max.y) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    val dx = centerX - orbitCenter.x
    val dy = centerY - orbitCenter.y
    val dz = centerZ - orbitCenter.z
    return dx * dx + dy * dy + dz * dz
  }

  private fun uploadNativeBimCacheChunks(
    engine: Engine,
    scene: Scene,
    cache: NativeBimCacheBridge.NativeBimCache,
    fallbackMaterial: Material,
    revision: Long,
    maxChunks: Int,
  ) {
    if (disposed || revision != nativeCacheUploadRevision || cache !== nativeBimCache) return
    val edgeChunks = linkedMapOf<EdgeBatchKey, MutableList<GeometryData>>()
    repeat(maxChunks) {
      val index = nativeCachePendingChunks.pollFirst() ?: return@repeat
      if (createNativeBimCacheChunk(engine, scene, cache, fallbackMaterial, index)) {
        nativeCacheResidentChunks.add(index)
        val chunk = cache.chunks.getOrNull(index)
        // Keep the architectural contour batch beside each streamed face
        // chunk so Solid/Shaded is correct even before the stream completes.
        if (chunk != null) {
          nativeCacheEdgeGeometry(chunk)?.let { geometry ->
            val key = EdgeBatchKey(
              kind = normalizeKind(chunk.kind),
              levelId = chunk.levelId,
              tileX = kotlin.math.floor((geometry.bounds.min.x + geometry.bounds.max.x) * 0.5 / 24.0).toInt(),
              tileZ = kotlin.math.floor((geometry.bounds.min.z + geometry.bounds.max.z) * 0.5 / 24.0).toInt(),
              nativeKindMask = chunk.kindMask,
            )
            edgeChunks.getOrPut(key) { mutableListOf() }.add(geometry)
          }
        }
      }
    }
    createEdgeBatches(engine, scene, edgeChunks)
    rendererBenchmark?.takeIf {
      it.mode == "NEW_BIMCACHE" && nativeCacheResidentChunks.isNotEmpty()
    }?.let(::markBenchmarkFirstSceneVisible)
    updateMetrics()
    syncVisibility()
    renderDirty = true
    requestRender(250L)

    if (nativeCachePendingChunks.isEmpty()) {
      statusMessage = "Loaded ${nativeCacheResidentChunks.size}/${cache.chunks.size} native BIM chunks."
      Log.i(TAG, statusMessage)
      rendererBenchmark?.takeIf { it.mode == "NEW_BIMCACHE" }?.let(::markBenchmarkFullSceneReady)
      updateStatus()
      return
    }
    scheduleNativeBimCacheUpload(engine, scene, cache, fallbackMaterial, revision)
  }

  private fun scheduleNativeBimCacheUpload(
    engine: Engine,
    scene: Scene,
    cache: NativeBimCacheBridge.NativeBimCache,
    fallbackMaterial: Material,
    revision: Long,
  ) {
    if (nativeCacheUploadPosted) return
    nativeCacheUploadPosted = true
    postDelayed({
      nativeCacheUploadPosted = false
      if (disposed || revision != nativeCacheUploadRevision || cache !== nativeBimCache) return@postDelayed
      uploadNativeBimCacheChunks(
        engine = engine,
        scene = scene,
        cache = cache,
        fallbackMaterial = fallbackMaterial,
        revision = revision,
        maxChunks = NATIVE_CACHE_STEADY_UPLOAD_CHUNKS,
      )
    }, NATIVE_CACHE_UPLOAD_DELAY_MS)
  }

  private fun scheduleNativeBimCacheReprioritization() {
    val cache = nativeBimCache ?: return
    if (nativeCachePendingChunks.size < 2 || nativeCacheReprioritizePosted) return
    val revision = nativeCacheUploadRevision
    nativeCacheReprioritizePosted = true
    // Sorting on every MotionEvent can itself make a large model feel heavy.
    // Coalesce a gesture into one short delayed reorder instead; uploads that
    // already reached Filament remain valid LOD0 geometry and are never
    // touched.
    postDelayed({
      nativeCacheReprioritizePosted = false
      if (disposed || revision != nativeCacheUploadRevision || cache !== nativeBimCache) return@postDelayed
      val nearestFirst = nativeCachePendingChunks
        .toList()
        .sortedBy { index -> nativeCacheChunkDistanceSquared(cache, index) }
      nativeCachePendingChunks.clear()
      nearestFirst.forEach(nativeCachePendingChunks::addLast)
    }, NATIVE_CACHE_REPRIORITIZE_DELAY_MS)
  }

  private fun createNativeBimCacheChunk(
    engine: Engine,
    scene: Scene,
    cache: NativeBimCacheBridge.NativeBimCache,
    fallbackMaterial: Material,
    index: Int,
  ): Boolean {
    val sceneState = currentScene ?: return false
    val chunk = cache.chunks.getOrNull(index) ?: return false
    val representative = sceneState.objects.getOrNull(index) ?: return false
    // Keep the cache's native memory ownership, but upload the small axis-remap
    // staging buffer in Filament coordinates.  Relying on a per-entity matrix
    // for this conversion made the Adreno/OpenGL driver validate the face AABB
    // in source coordinates; the result was a completely invisible solid pass
    // while the Canvas bounds overlay still showed its edges.  The conversion
    // happens once per streamed chunk (not per frame), so orbiting remains
    // native/GPU-only and the source `.bimcache` stays untouched.
    val filamentPositions = nativeCacheFilamentPositions(chunk)
    val vertexCount = filamentPositions.capacity() / 12
    val indexCount = chunk.indices.capacity()
    if (vertexCount <= 0 || indexCount < 3) return false
    if (index < 8) {
      Log.i(
        TAG,
        "Cache face chunk=$index kind=${chunk.kind} mask=${chunk.kindMask} " +
          "vertices=$vertexCount indices=$indexCount bounds=${chunk.sourceBounds} " +
          "representative=${representative.kind}",
      )
    }
    return try {
      // Cache coordinates stay in the engine's X/Y-plan/Z-up convention.
      // One entity transform maps that buffer to Filament X/Z/-Y without
      // ever copying its vertices through Kotlin or Dart.
      val vertexBuffer = VertexBuffer.Builder()
        .bufferCount(1)
        .vertexCount(vertexCount)
        .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
        .build(engine)
        .also { buffer ->
          buffer.setBufferAt(engine, 0, filamentPositions)
        }
      val indexBuffer = IndexBuffer.Builder()
        .indexCount(indexCount)
        .bufferType(IndexBuffer.Builder.IndexType.UINT)
        .build(engine)
        .also { buffer ->
          buffer.setBuffer(engine, chunk.indices.duplicate().apply { rewind() })
        }
      // A native cache chunk contains several IFC elements and can therefore
      // carry more than one material category.  Applying the first element's
      // procedural wall/wood/floor shader to the whole chunk made its
      // high-frequency pattern alias while orbiting on the tablet, which was
      // perceived as white/black flicker.  Keep the complete cached geometry
      // and use the low-frequency neutral material for the streamed path;
      // material detail remains available in the compatibility renderer.
      val sharedMaterial = if (displayStyle == "solid") {
        solidMaterial ?: fallbackMaterial
      } else {
        fallbackMaterial
      }
      val baseColor = displayBaseColor(representative)
      val materialInstance = sharedMaterial.createInstance().also { instance ->
        applySectionBoxState(instance)
        applyDisplayStyle(instance)
        instance.setParameter(
          "baseColor",
          Colors.RgbaType.LINEAR,
          baseColor[0], baseColor[1], baseColor[2], baseColor[3],
        )
      }
      val entity = EntityManager.get().create()
      RenderableManager.Builder(1)
        .boundingBox(filamentBox(transformBounds(chunk.sourceBounds)))
        // The cache mesh is authored in the source (X/Y plan, Z up) space and
        // receives the axis remap in TransformManager below.  On the tablet's
        // Adreno/OpenGL path the renderer can evaluate the local AABB before
        // that remap and cull the complete face pass, while the separate edge
        // overlay remains visible.  Cache chunks are already spatially
        // streamed (only a handful of entities), so keep their face pass
        // visible and leave fine-grained culling to the native chunk loader.
        .culling(false)
        .castShadows(false)
        .receiveShadows(false)
        .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, indexCount)
        .material(0, materialInstance)
        .build(engine, entity)
      val visible = nativeCacheChunkVisible(chunk)
      if (visible) scene.addEntity(entity)
      faceBatches.add(
        FaceBatchEntry(
          key = FaceBatchKey(
            kind = normalizeKind(representative.kind),
            materialVariant = representative.materialCategory,
            levelId = representative.levelId,
            tileX = 0,
            tileZ = 0,
          ),
          representative = representative,
          entity = entity,
          vertexBuffer = vertexBuffer,
          indexBuffer = indexBuffer,
          material = sharedMaterial,
          materialInstance = materialInstance,
          baseColor = baseColor,
          bounds = transformBounds(chunk.sourceBounds),
          objectCount = 1,
          vertexCount = vertexCount,
          indexCount = indexCount,
          nativeKindMask = chunk.kindMask,
          attached = visible,
        ),
      )
      true
    } catch (error: Throwable) {
      Log.e(TAG, "Failed to create native BIM cache chunk $index", error)
      false
    }
  }

  private fun nativeCacheChunkVisible(chunk: NativeBimCacheChunk): Boolean =
    nativeCacheKindMaskVisible(chunk.kindMask)

  private fun nativeCacheFilamentPositions(chunk: NativeBimCacheChunk): ByteBuffer {
    val source = chunk.positions.duplicate()
      .order(ByteOrder.nativeOrder())
      .apply { rewind() }
    val vertexCount = source.capacity() / 12
    val converted = ByteBuffer.allocateDirect(vertexCount * 12)
      .order(ByteOrder.nativeOrder())
    for (vertexIndex in 0 until vertexCount) {
      val offset = vertexIndex * 12
      val sourceX = source.getFloat(offset)
      val sourceY = source.getFloat(offset + 4)
      val sourceZ = source.getFloat(offset + 8)
      converted.putFloat(sourceX)
      converted.putFloat(sourceZ)
      converted.putFloat(-sourceY)
    }
    converted.flip()
    return converted
  }

  private fun nativeCacheKindMaskVisible(mask: Long): Boolean {
    if (visibleKinds.isEmpty() || mask == 0L) return true
    return visibleKinds.any { kind ->
      val ordinal = when (normalizeKind(kind)) {
        "wall" -> 2
        "door" -> 3
        "window" -> 4
        "room" -> 5
        "slab" -> 6
        "floor" -> 7
        "ceiling" -> 8
        "roof" -> 9
        "column" -> 10
        "beam" -> 11
        "stair" -> 12
        "proxy" -> 13
        else -> -1
      }
      ordinal >= 0 && (mask and (1L shl ordinal)) != 0L
    }
  }

  private fun applyCacheCoordinateTransform(engine: Engine, entity: Int) {
    var transformInstance = engine.transformManager.getInstance(entity)
    if (transformInstance == 0) transformInstance = engine.transformManager.create(entity)
    // Engine: (X, Y plan, Z up). Filament: (X, Y up, -Z plan).
    engine.transformManager.setTransform(
      transformInstance,
      floatArrayOf(
        1f, 0f, 0f, 0f,
        0f, 0f, -1f, 0f,
        0f, 1f, 0f, 0f,
        0f, 0f, 0f, 1f,
      ),
    )
  }

  private fun resetImportedMeshEdgeBudget() {
    importedMeshEdgeBudgetRemaining = IMPORTED_MESH_EDGE_SEGMENT_BUDGET
  }

  private fun rebuildScene() {
    destroyRenderables()
    val scene = scene ?: return
    val sceneState = currentScene ?: return
    if ((material == null || wallMaterial == null || windowMaterial == null ||
        plasterMaterial == null || woodMaterial == null || floorMaterial == null ||
         roofMaterial == null || concreteMaterial == null || edgeMaterial == null ||
         gridMaterial == null ||
         groundMaterial == null || shadowMaterial == null) &&
      materialBuilderReady) {
      buildRuntimeMaterial()
    }
    val engine = engine ?: return
    val material = material ?: run {
      statusMessage = "Filament material unavailable."
      Log.w(TAG, statusMessage)
      updateStatus()
      return
    }
    nativeBimCache?.let { cache ->
      rebuildNativeBimCacheScene(engine, scene, cache, material)
      return
    }
    val objects = sceneState.objects
    // A ceiling normally sits below the wall's top constraint (for example
    // 2.85 m below a 3.20 m level). Keep its actual elevation so walls can
    // render the physical wall/ceiling junction, not merely their own top.
    // Do not key these elevations by level ID. Imported/joined walls may have
    // a missing or differently-normalized level reference even though their
    // mesh is correctly positioned. The wall's own vertical bounds below
    // select the relevant elevation, so the scene-wide set is both safer and
    // just as precise.
    val wallJunctionElevations = objects
      .filter { normalizeKind(it.kind) == "ceiling" || normalizeKind(it.kind) == "floor" }
      .flatMap { system ->
        // Some valid surface systems are transported as bounds-only fallback
        // geometry. Their faces still render, but relying on mesh positions
        // alone loses their elevation and makes nearby wall borders random.
        system.mesh.positions.map { it.z } + listOf(system.bounds.min.z, system.bounds.max.z)
      }
      .distinct()

    var failedObjects = 0
    val batchFaces = objects.size >= 256
    val faceChunks = linkedMapOf<FaceBatchKey, MutableList<Pair<SceneObject, GeometryData>>>()
    val instanceChunks = linkedMapOf<InstanceFaceKey, MutableList<Triple<SceneObject, GeometryData, NormalizedInstanceGeometry>>>()
    val edgeChunks = linkedMapOf<EdgeBatchKey, MutableList<GeometryData>>()
    resetImportedMeshEdgeBudget()
    for (objectData in objects) {
      try {
        val geometry = objectGeometry(objectData) ?: continue
        val normalizedInstance = if (isInstanceCandidate(objectData)) {
          normalizedInstanceGeometry(objectData, geometry)
        } else {
          null
        }
        if (normalizedInstance != null) {
          instanceChunks.getOrPut(normalizedInstance.key) { mutableListOf() }
            .add(Triple(objectData, geometry, normalizedInstance))
        } else if (batchFaces) {
          faceChunks.getOrPut(faceBatchKey(objectData, geometry.bounds)) { mutableListOf() }
            .add(objectData to geometry)
        } else {
          val objectMaterial = materialForObject(objectData, material)
          val entry = createRenderable(
            engine,
            objectMaterial,
            objectData,
            geometry,
          ) ?: continue
          renderables[objectData.elementId ?: renderables.size.toLong() + 1L] = entry
          scene.addEntity(entry.entity)
          entry.attached = true
          attachedEntities.add(entry.entity)
        }
        edgeGeometryFor(objectData, geometry, wallJunctionElevations)?.let { edge ->
          edgeChunks.getOrPut(edgeBatchKey(objectData, geometry.bounds)) { mutableListOf() }.add(edge)
        }
      } catch (error: Throwable) {
        failedObjects += 1
        Log.e(TAG, "Failed to create Filament renderable for ${objectData.kind}", error)
      }
    }
    for ((_, sources) in instanceChunks) {
      if (sources.size >= 2) {
        createInstanceFaceGroup(engine, scene, sources)
      } else {
        val (objectData, geometry, _) = sources.first()
        if (batchFaces) {
          faceChunks.getOrPut(faceBatchKey(objectData, geometry.bounds)) { mutableListOf() }
            .add(objectData to geometry)
        } else {
          val objectMaterial = materialForObject(objectData, material)
          val entry = createRenderable(engine, objectMaterial, objectData, geometry) ?: continue
          renderables[objectData.elementId ?: renderables.size.toLong() + 1L] = entry
          scene.addEntity(entry.entity)
          entry.attached = true
          attachedEntities.add(entry.entity)
        }
      }
    }
    if (batchFaces) createFaceBatches(engine, scene, faceChunks)
    createEdgeBatches(engine, scene, edgeChunks)
    if (projectionMode == "isometric") {
      createGridBatch(engine, scene, sceneState)
    }
    if (projectionMode == "isometric" && shadowsEnabled) {
      createGroundReceiver(engine, scene, sceneState)
    }
    updateMetrics()
    renderDirty = true
    Log.i(
      TAG,
      "GPU layout: objects=${sceneMetrics.objectCount}, faceDraws=${renderables.size + faceBatches.size + instanceFaceGroups.size}, " +
        "instanceGroups=${instanceFaceGroups.size}, instancedObjects=${sceneMetrics.instancedObjectCount}, " +
        "edgeBatches=${edgeBatches.size}, draws=${renderables.size + faceBatches.size + instanceFaceGroups.size + edgeBatches.size}, " +
        "edgeTriangles=${sceneMetrics.edgeIndexCount / 3}, cache=${edgeGeometryCache.size}",
    )
    if (failedObjects > 0) {
      statusMessage = "Filament skipped $failedObjects invalid renderables; loaded ${renderables.size}."
      Log.w(TAG, statusMessage)
    }
  }

  private fun rebuildEdgeBatchesForProjection() {
    val engine = engine ?: return
    val scene = scene ?: return
    val sceneState = currentScene ?: return
    destroyEdgeBatches(engine, scene)
    // The cache key includes revisions, but not projection mode. Clear it
    // when switching between plan and 3D so the lighter top-down geometry is
    // actually regenerated.
    edgeGeometryCache.clear()
    resetImportedMeshEdgeBudget()

    val wallJunctionElevations = sceneState.objects
      .filter { normalizeKind(it.kind) == "ceiling" || normalizeKind(it.kind) == "floor" }
      .flatMap { system ->
        system.mesh.positions.map { it.z } + listOf(system.bounds.min.z, system.bounds.max.z)
      }
      .distinct()
    val edgeChunks = linkedMapOf<EdgeBatchKey, MutableList<GeometryData>>()
    for (objectData in sceneState.objects) {
      try {
        val geometry = objectGeometry(objectData) ?: continue
        edgeGeometryFor(objectData, geometry, wallJunctionElevations)?.let { edge ->
          edgeChunks.getOrPut(edgeBatchKey(objectData, geometry.bounds)) { mutableListOf() }
            .add(edge)
        }
      } catch (error: Throwable) {
        Log.w(TAG, "Failed to refresh edge geometry for ${objectData.kind}", error)
      }
    }
    createEdgeBatches(engine, scene, edgeChunks)
    updateMetrics()
    renderDirty = true
  }

  private fun materialForObject(objectData: SceneObject, fallback: Material): Material {
    val kind = normalizeKind(objectData.kind)
    if (displayStyle == "solid") {
      return if (kind == "window") {
        solidWindowMaterial ?: fallback
      } else {
        solidMaterial ?: fallback
      }
    }
    if (kind == "window") return windowMaterial ?: fallback
    return when (kind) {
      "wall" -> if (objectData.metadata["wall_type_category"] == "Interior") {
        plasterMaterial ?: fallback
      } else {
        wallMaterial ?: fallback
      }
      "door" -> woodMaterial ?: fallback
      // IFC categories use the same small set of real Filament materials so
      // the view stays consistent across imported and native scene objects.
      "floor" -> floorMaterial ?: fallback
      "roof" -> roofMaterial ?: fallback
      "slab", "column", "beam", "stair", "proxy" -> concreteMaterial ?: fallback
      "ceiling" -> plasterMaterial ?: fallback
      else -> if (displayStyle == "solid") fallback else fallback
    }
  }

  private fun applyDisplayStyle(instance: MaterialInstance) {
    instance.setParameter("displayShade", if (displayStyle == "shaded") 1.0f else 0.0f)
  }

  private fun displayBaseColor(objectData: SceneObject): FloatArray {
    val kind = normalizeKind(objectData.kind)
    val isWindow = kind == "window"
    return if (displayStyle == "solid") {
      val surface = when (viewportTheme) {
        "standardDark" -> 0.34f
        "amoledBlack" -> 0.24f
        // Keep the light Revit-like solid appearance, but leave enough
        // neutral contrast against the paper background for filled faces to
        // remain obvious on a tablet.  Pure white made a valid surface pass
        // look empty and was easily mistaken for wireframe.
        else -> 0.82f
      }
      floatArrayOf(surface, surface, surface, if (isWindow) 0.30f else 1.0f)
    } else {
      // Revit-like Lighting/Shaded view: neutral architectural surfaces let
      // the sun establish the form, instead of dark category colors masking
      // the light/shadow boundary. Dark viewport themes keep the same palette
      // but scale it down so the model remains comfortable to read.
      revitShadedColor(kind)
    }
  }

  private fun revitShadedColor(kind: String): FloatArray {
    val base = when (kind) {
      "wall" -> floatArrayOf(0.72f, 0.74f, 0.77f, 1.0f)
      "door" -> floatArrayOf(0.34f, 0.36f, 0.39f, 1.0f)
      "window" -> floatArrayOf(0.36f, 0.50f, 0.60f, 0.42f)
      "slab" -> floatArrayOf(0.66f, 0.68f, 0.71f, 1.0f)
      "floor" -> floatArrayOf(0.67f, 0.69f, 0.72f, 1.0f)
      "ceiling" -> floatArrayOf(0.84f, 0.85f, 0.86f, 1.0f)
      "roof" -> floatArrayOf(0.78f, 0.79f, 0.81f, 1.0f)
      "column" -> floatArrayOf(0.62f, 0.65f, 0.69f, 1.0f)
      "beam" -> floatArrayOf(0.58f, 0.61f, 0.65f, 1.0f)
      "stair" -> floatArrayOf(0.70f, 0.72f, 0.75f, 1.0f)
      "proxy" -> floatArrayOf(0.64f, 0.60f, 0.55f, 1.0f)
      else -> floatArrayOf(0.68f, 0.70f, 0.73f, 1.0f)
    }
    val themeScale = when (viewportTheme) {
      "standardDark" -> 0.62f
      "amoledBlack" -> 0.52f
      else -> 1.0f
    }
    return floatArrayOf(
      base[0] * themeScale,
      base[1] * themeScale,
      base[2] * themeScale,
      base[3],
    )
  }

  private fun openingVisibleInPlan(kind: String): Boolean =
    projectionMode != "topDown" || (kind != "door" && kind != "window")

  private fun faceVisible(objectData: SceneObject): Boolean =
    displayStyle != "wireframe" && kindVisible(normalizeKind(objectData.kind)) &&
      openingVisibleInPlan(normalizeKind(objectData.kind))

  private fun edgeVisible(kind: String): Boolean =
    (displayStyle == "solid" || displayStyle == "shaded") &&
      kindVisible(kind) && openingVisibleInPlan(kind)

  private fun edgeVisible(key: EdgeBatchKey): Boolean =
    (displayStyle == "wireframe" || displayStyle == "solid" || displayStyle == "shaded") &&
      (key.nativeKindMask?.let(::nativeCacheKindMaskVisible)
        ?: kindVisible(key.kind)) &&
      openingVisibleInPlan(key.kind)

  private fun baseColorForObject(objectData: SceneObject): FloatArray =
    kindColor(normalizeKind(objectData.kind))

  private fun isImportedMeshObject(objectData: SceneObject): Boolean {
    val rawKind = objectData.kind.trim().lowercase()
    if (rawKind in EXTERNAL_MESH_KIND_ALIASES ||
      rawKind.contains("fbx") ||
      rawKind.contains("external") ||
      rawKind.contains("mesh")
    ) return true
    if (objectData.metadata.any { (key, value) ->
      val normalizedKey = key.trim().lowercase()
      if (normalizedKey !in setOf(
          "format",
          "file_format",
          "fileformat",
          "source_format",
          "sourceformat",
          "import_format",
          "importformat",
          "source_type",
          "sourcetype",
        )) {
        false
      } else {
        val normalizedValue = value.trim().lowercase()
        normalizedValue.contains("fbx") || normalizedValue in setOf(
          "obj",
          "gltf",
          "glb",
          "mesh",
          "external",
        )
      }
    }) return true
    // Some import adapters only preserve a source filename/URI and do not
    // copy it into a canonical format field. Recognize that contract too,
    // without treating ordinary BIM names as external meshes.
    return objectData.metadata.values.any { value ->
      val normalizedValue = value.trim().lowercase()
      normalizedValue.contains(".fbx") ||
        normalizedValue.contains("/fbx/") ||
        normalizedValue.contains("\\fbx\\")
    }
  }

  private fun importedMeshTriangleBudget(objectData: SceneObject): Int? {
    val sourceTriangleCount = objectData.mesh.indices.size / 3
    if (!isImportedMeshObject(objectData) || sourceTriangleCount <= 0) {
      return if ((currentScene?.objects?.size ?: 0) > 600) 16 else null
    }
    // Preserve all topology for ordinary-sized meshes. Only large external
    // meshes use deterministic sampling for the edge overlay; the Filament
    // face render still receives the original geometry unchanged.
    return when {
      sourceTriangleCount <= 4_096 -> null
      sourceTriangleCount > 200_000 -> 256
      sourceTriangleCount > 50_000 -> 512
      else -> 1_024
    }
  }

  private fun capGenericMeshEdges(
    objectData: SceneObject,
    edges: List<NativeVisualEdge>,
  ): List<NativeVisualEdge> {
    if (normalizeKind(objectData.kind) != "proxy") return edges
    val sceneObjectCount = currentScene?.objects?.size ?: 0
    val perObjectLimit = if (sceneObjectCount > 600) {
      IMPORTED_MESH_EDGE_SEGMENT_LIMIT_LARGE_SCENE
    } else {
      IMPORTED_MESH_EDGE_SEGMENT_LIMIT_SMALL_SCENE
    }
    val allowed = min(perObjectLimit, importedMeshEdgeBudgetRemaining)
    if (allowed <= 0) return emptyList()
    val capped = if (edges.size <= allowed) {
      edges
    } else {
      // Sharp edges are the useful architectural/model contours. Keep them
      // first, then fill the remainder with boundary edges in source order.
      (edges.filter { it.sharp } + edges.filterNot { it.sharp })
        .take(allowed)
    }
    importedMeshEdgeBudgetRemaining -= capped.size
    return capped
  }

  private fun capNativeCacheEdges(edges: List<NativeVisualEdge>): List<NativeVisualEdge> {
    // A cache chunk can contain hundreds of imported detail triangles. Keep a
    // bounded contour subset per chunk so the filled model stays readable at
    // fit-to-view scale; close-up detail remains available through selection
    // and the source mesh itself.
    val allowed = min(192, nativeCacheEdgeBudgetRemaining)
    if (allowed <= 0) return emptyList()
    val capped = if (edges.size <= allowed) {
      edges
    } else {
      (edges.filter { it.sharp } + edges.filterNot { it.sharp }).take(allowed)
    }
    nativeCacheEdgeBudgetRemaining -= capped.size
    return capped
  }

  /**
   * Builds a small edge-only view of a streamed cache chunk. The face chunk
   * keeps its direct native buffers and its cache transform; this temporary
   * CPU view only decodes the triangles needed for linework and uploads a
   * separate, already-transformed edge mesh.
   */
  private fun nativeCacheEdgeGeometry(chunk: NativeBimCacheChunk): GeometryData? {
    if (nativeCacheEdgeBudgetRemaining <= 0) return null
    val vertexCount = chunk.positions.capacity() / 12
    val indexCount = chunk.indices.capacity()
    if (vertexCount <= 0 || indexCount < 3) return null

    val positionBuffer = chunk.positions.duplicate()
      .order(ByteOrder.nativeOrder())
      .apply { rewind() }
    val indexBuffer = chunk.indices.duplicate().apply { rewind() }
    val sourceTriangleCount = indexCount / 3
    val points = mutableListOf<ScenePoint>()
    val localBySourceIndex = hashMapOf<Int, Int>()

    fun readPoint(sourceIndex: Int): ScenePoint? {
      if (sourceIndex !in 0 until vertexCount) return null
      val existing = localBySourceIndex[sourceIndex]
      if (existing != null) return points[existing]
      val byteOffset = sourceIndex * 12
      val point = ScenePoint(
        positionBuffer.getFloat(byteOffset).toDouble(),
        positionBuffer.getFloat(byteOffset + 4).toDouble(),
        positionBuffer.getFloat(byteOffset + 8).toDouble(),
      )
      if (!point.x.isFinite() || !point.y.isFinite() || !point.z.isFinite()) return null
      val transformed = toFilamentPoint(point)
      val localIndex = points.size
      points.add(transformed)
      localBySourceIndex[sourceIndex] = localIndex
      return transformed
    }

    val triangles = mutableListOf<IntArray>()
    for (triangleIndex in 0 until sourceTriangleCount) {
      val offset = triangleIndex * 3
      val firstSource = indexBuffer.get(offset)
      val secondSource = indexBuffer.get(offset + 1)
      val thirdSource = indexBuffer.get(offset + 2)
      val first = readPoint(firstSource) ?: continue
      val second = readPoint(secondSource) ?: continue
      val third = readPoint(thirdSource) ?: continue
      val abX = second.x - first.x
      val abY = second.y - first.y
      val abZ = second.z - first.z
      val acX = third.x - first.x
      val acY = third.y - first.y
      val acZ = third.z - first.z
      val crossX = abY * acZ - abZ * acY
      val crossY = abZ * acX - abX * acZ
      val crossZ = abX * acY - abY * acX
      if (crossX * crossX + crossY * crossY + crossZ * crossZ <= 1.0e-16) continue
      triangles.add(
        intArrayOf(
          localBySourceIndex[firstSource] ?: continue,
          localBySourceIndex[secondSource] ?: continue,
          localBySourceIndex[thirdSource] ?: continue,
        ),
      )
    }
    if (points.isEmpty() || triangles.isEmpty()) return null

    val edgePoints: List<ScenePoint> = points
    val edgeTriangles: List<IntArray> = triangles
    // Build adjacency from the complete chunk before applying the line budget.
    // Sampling triangles first breaks shared-edge continuity and was the cause
    // of the dotted/tessellated look seen in the historical builds.
    val minimumLength = when (normalizeKind(chunk.kind)) {
      "wall" -> 0.18
      "window", "door" -> 0.06
      "column" -> 0.10
      "stair" -> 0.08
      else -> 0.12
    }
    // A one-use edge can be either a triangulation seam or a real outer
    // contour. Keep creases at any useful scale, and keep only *long* one-use
    // boundaries. This restores the silhouette of a flat facade without
    // promoting every tiny imported tessellation fragment into a line.
    val edges = meshFeatureEdges(
      points,
      triangles,
      creaseDotThreshold = 0.55,
      includeBoundaryEdges = true,
    )
      .filter { edge ->
        val first = points.getOrNull(edge.first) ?: return@filter false
        val second = points.getOrNull(edge.second) ?: return@filter false
        val dx = second.x - first.x
        val dy = second.y - first.y
        val dz = second.z - first.z
        val lengthSquared = dx * dx + dy * dy + dz * dz
        if (lengthSquared < minimumLength * minimumLength) return@filter false
        val boundary = edge.triangleIndices.size == 1
        val longBoundary = boundary && lengthSquared >=
          max(minimumLength * minimumLength * 6.25, 0.45 * 0.45)
        (!boundary && edge.sharp) || longBoundary
      }
    if (edges.isEmpty()) return null
    val boundedEdges = capNativeCacheEdges(edges)
    return edgeGeometry(edgePoints, boundedEdges, edgeTriangles, radiusScale = 2.2)
  }

  private fun edgeSurfaceOffset(
    triangleIndices: IntArray,
    points: List<ScenePoint>,
    triangles: List<IntArray>,
  ): ScenePoint {
    if (triangleIndices.isEmpty()) return ScenePoint(0.0, 0.0, 0.0)
    var reference: DoubleArray? = null
    var normalX = 0.0
    var normalY = 0.0
    var normalZ = 0.0
    var count = 0
    for (triangleIndex in triangleIndices) {
      val triangle = triangles.getOrNull(triangleIndex) ?: continue
      if (triangle.size != 3 || triangle.any { it !in points.indices }) continue
      val normal = triangleNormal(points[triangle[0]], points[triangle[1]], points[triangle[2]])
      if (normal.all { kotlin.math.abs(it) <= 1.0e-9 }) continue
      if (reference == null) reference = normal
      val currentReference: DoubleArray? = reference
      val direction = currentReference ?: continue
      val sign = if (normalDot(normal, direction) < 0.0) -1.0 else 1.0
      normalX += normal[0] * sign
      normalY += normal[1] * sign
      normalZ += normal[2] * sign
      count += 1
    }
    if (count == 0) return ScenePoint(0.0, 0.0, 0.0)
    val length = kotlin.math.sqrt(normalX * normalX + normalY * normalY + normalZ * normalZ)
    if (length <= 1.0e-9) return ScenePoint(0.0, 0.0, 0.0)
    val offset = when {
      projectionMode == "topDown" -> 0.006
      projectionMode == "isometric" -> 0.025
      else -> 0.012
    }
    return ScenePoint(
      normalX / length * offset,
      normalY / length * offset,
      normalZ / length * offset,
    )
  }

  private fun edgeGeometryFor(
    objectData: SceneObject,
    geometry: GeometryData,
    wallJunctionElevations: List<Double>,
  ): GeometryData? {
    val kind = normalizeKind(objectData.kind)
    // In orbit view floors/ceilings are surfaces, not architectural linework.
    // Their coplanar borders were being depth-tested as repeated heavy storey
    // bands and could flicker while orbiting. Columns keep only their vertical
    // edges below; those are readable without reintroducing the horizontal
    // edges that overlap beams and slabs. Sections still get their section
    // edges from the clipped wall geometry.
    if ((projectionMode == "isometric" || projectionMode == "section") &&
      kind in setOf("floor", "ceiling", "slab")
    ) {
      return null
    }
    val wallEdges = kind == "wall"
    val isSectionLike = projectionMode != "topDown" && projectionMode != "isometric"
    val relevantJunctions = if (wallEdges) {
      wallJunctionElevations.filter { elevation ->
        elevation >= geometry.bounds.min.y - 1.0e-5 &&
          elevation <= geometry.bounds.max.y + 1.0e-5
      }
    } else {
      emptyList()
    }
    val junctionSignature = (relevantJunctions.hashCode() * 31) + if (isSectionLike) 1 else 0
    val elementId = objectData.elementId
    if (!clipVolume.active && elementId != null) {
      val cached = edgeGeometryCache[elementId]
      if (cached != null && cached.revision == objectData.revision &&
        cached.junctionSignature == junctionSignature) {
        return cached.geometry
      }
    }
    val visual = toVisualObject(objectData)
    val points = if (clipVolume.active) geometry.points else visual.points
    val triangles = if (clipVolume.active) geometry.triangles else visual.triangles
    val edges = if (clipVolume.active) clippedFeatureEdges(points, triangles) else visual.featureEdges
    // A clipped triangle soup contains many one-triangle seams. They are
    // valid topology boundaries, but not architectural linework; at section
    // zoom they sit almost coplanar with the faces and shimmer during motion.
    val stableSectionEdges = if (projectionMode == "section" && clipVolume.active) {
      edges.filter { it.sharp }
    } else {
      edges
    }
    val stableColumnEdges = if (projectionMode == "isometric" && kind == "column") {
      stableSectionEdges.filter { edge ->
        val first = points.getOrNull(edge.first) ?: return@filter false
        val second = points.getOrNull(edge.second) ?: return@filter false
        val dx = kotlin.math.abs(second.x - first.x)
        val dy = kotlin.math.abs(second.y - first.y)
        val dz = kotlin.math.abs(second.z - first.z)
        // A box column's vertical edges are the useful 3D linework. Horizontal
        // top/bottom edges are exactly the coplanar borders that used to flicker.
        dy > 0.05 && dy > max(dx, dz) * 3.0
      }
    } else {
      stableSectionEdges
    }
    val boundedEdges = capGenericMeshEdges(objectData, stableColumnEdges)
    val generated = edgeGeometry(
      points,
      boundedEdges,
      triangles,
      wallJunctionEdges = wallEdges && isSectionLike,
      wallJunctionElevations = relevantJunctions,
    ) ?: return null
    if (!clipVolume.active && elementId != null) {
      edgeGeometryCache[elementId] = CachedEdgeGeometry(
        revision = objectData.revision,
        junctionSignature = junctionSignature,
        geometry = generated,
      )
    }
    return generated
  }

  private fun edgeBatchKey(objectData: SceneObject, bounds: SceneBounds): EdgeBatchKey {
    val tileSizeMeters = 24.0
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    return EdgeBatchKey(
      kind = normalizeKind(objectData.kind),
      levelId = objectData.levelId,
      tileX = kotlin.math.floor(centerX / tileSizeMeters).toInt(),
      tileZ = kotlin.math.floor(centerZ / tileSizeMeters).toInt(),
    )
  }

  private fun faceBatchKey(objectData: SceneObject, bounds: SceneBounds): FaceBatchKey {
    val kind = normalizeKind(objectData.kind)
    val tileSizeMeters = 24.0
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    val materialVariant = faceMaterialVariant(objectData)
    return FaceBatchKey(
      kind = kind,
      materialVariant = materialVariant,
      levelId = objectData.levelId,
      tileX = kotlin.math.floor(centerX / tileSizeMeters).toInt(),
      tileZ = kotlin.math.floor(centerZ / tileSizeMeters).toInt(),
    )
  }

  private fun faceMaterialVariant(objectData: SceneObject): String {
    val kind = normalizeKind(objectData.kind)
    return if (kind == "wall") {
      objectData.metadata["wall_type_category"] ?: "Generic"
    } else {
      objectData.materialCategory
    }
  }

  private fun isInstanceCandidate(objectData: SceneObject): Boolean {
    if (clipVolume.active) return false
    return normalizeKind(objectData.kind) in setOf("door", "window", "column")
  }

  /**
   * Removes translation but preserves the exact transported mesh topology and
   * orientation. Equal family geometry therefore shares GPU buffers safely;
   * resized or unique instances naturally receive a different signature.
   */
  private fun normalizedInstanceGeometry(
    objectData: SceneObject,
    geometry: GeometryData,
  ): NormalizedInstanceGeometry? {
    if (geometry.vertexCount <= 0 || geometry.indexCount <= 0) return null
    val translation = ScenePoint(
      (geometry.bounds.min.x + geometry.bounds.max.x) * 0.5,
      (geometry.bounds.min.y + geometry.bounds.max.y) * 0.5,
      (geometry.bounds.min.z + geometry.bounds.max.z) * 0.5,
    )
    val sourceVertices = geometry.vertexData.duplicate().order(ByteOrder.nativeOrder()).apply { rewind() }.asFloatBuffer()
    val localVertexData = ByteBuffer.allocateDirect(geometry.vertexCount * 12).order(ByteOrder.nativeOrder())
    var shapeHash = -0x340d631b7bdddcdbL
    fun mix(value: Long) {
      shapeHash = (shapeHash xor value) * 0x100000001b3L
    }
    repeat(geometry.vertexCount) {
      val x = sourceVertices.get().toDouble() - translation.x
      val y = sourceVertices.get().toDouble() - translation.y
      val z = sourceVertices.get().toDouble() - translation.z
      localVertexData.putFloat(x.toFloat())
      localVertexData.putFloat(y.toFloat())
      localVertexData.putFloat(z.toFloat())
      mix(kotlin.math.round(x * 10000.0).toLong())
      mix(kotlin.math.round(y * 10000.0).toLong())
      mix(kotlin.math.round(z * 10000.0).toLong())
    }
    localVertexData.flip()
    val sourceIndices = geometry.indexData.duplicate().apply { rewind() }
    val localIndexData = ByteBuffer.allocateDirect(geometry.indexCount * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer()
    while (sourceIndices.hasRemaining()) {
      val index = sourceIndices.get()
      localIndexData.put(index)
      mix(index.toLong())
    }
    localIndexData.flip()
    val localBounds = SceneBounds(
      min = ScenePoint(
        geometry.bounds.min.x - translation.x,
        geometry.bounds.min.y - translation.y,
        geometry.bounds.min.z - translation.z,
      ),
      max = ScenePoint(
        geometry.bounds.max.x - translation.x,
        geometry.bounds.max.y - translation.y,
        geometry.bounds.max.z - translation.z,
      ),
    )
    val key = InstanceFaceKey(
      kind = normalizeKind(objectData.kind),
      materialVariant = faceMaterialVariant(objectData),
      colorHash = baseColorForObject(objectData).contentHashCode(),
      vertexCount = geometry.vertexCount,
      indexCount = geometry.indexCount,
      shapeHash = shapeHash,
    )
    return NormalizedInstanceGeometry(
      key = key,
      geometry = GeometryData(
        vertexCount = geometry.vertexCount,
        indexCount = geometry.indexCount,
        vertexData = localVertexData,
        indexData = localIndexData,
        bounds = localBounds,
      ),
      translation = translation,
    )
  }

  private fun createInstanceFaceGroup(
    engine: Engine,
    scene: Scene,
    sources: List<Triple<SceneObject, GeometryData, NormalizedInstanceGeometry>>,
  ) {
    val fallback = material ?: return
    val first = sources.firstOrNull() ?: return
    val representative = first.first
    val local = first.third.geometry
    val sharedMaterial = materialForObject(representative, fallback)
    val baseColor = displayBaseColor(representative)
    val vertexData = vertexDataWithTangents(local)
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(local.vertexCount)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 28)
      .attribute(VertexBuffer.VertexAttribute.TANGENTS, 0, VertexBuffer.AttributeType.FLOAT4, 12, 28)
      .build(engine).also { it.setBufferAt(engine, 0, vertexData) }
    val indexBuffer = IndexBuffer.Builder()
      .indexCount(local.indexCount)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine).also { it.setBuffer(engine, local.indexData) }
    val materialInstance = sharedMaterial.createInstance().also { instance ->
      applySectionBoxState(instance)
      applyDisplayStyle(instance)
      instance.setParameter(
        "baseColor", Colors.RgbaType.LINEAR,
        baseColor[0], baseColor[1], baseColor[2], baseColor[3],
      )
    }
    val visible = faceVisible(representative)
    val transformManager = engine.transformManager
    val entities = ArrayList<Int>(sources.size)
    for ((_, _, normalized) in sources) {
      val entity = EntityManager.get().create()
      RenderableManager.Builder(1)
        .boundingBox(filamentBox(local.bounds))
        .culling(true)
        .castShadows(shadowsEnabled)
        .receiveShadows(shadowsEnabled)
        .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, local.indexCount)
        .material(0, materialInstance)
        .build(engine, entity)
      var transformInstance = transformManager.getInstance(entity)
      if (transformInstance == 0) transformInstance = transformManager.create(entity)
      val transform = FloatArray(16)
      Matrix.setIdentityM(transform, 0)
      Matrix.translateM(
        transform,
        0,
        normalized.translation.x.toFloat(),
        normalized.translation.y.toFloat(),
        normalized.translation.z.toFloat(),
      )
      transformManager.setTransform(transformInstance, transform)
      if (visible) scene.addEntity(entity)
      entities.add(entity)
    }
    val worldBounds = sources.map { it.second.bounds }.reduce(::unionBounds)
    instanceFaceGroups.add(
      InstanceFaceGroupEntry(
        kind = normalizeKind(representative.kind),
        representative = representative,
        entities = entities,
        vertexBuffer = vertexBuffer,
        indexBuffer = indexBuffer,
        material = sharedMaterial,
        materialInstance = materialInstance,
        baseColor = baseColor,
        bounds = worldBounds,
        objectCount = sources.size,
        vertexCount = local.vertexCount,
        indexCount = local.indexCount,
        attached = visible,
      )
    )
  }

  private fun createFaceBatches(
    engine: Engine,
    scene: Scene,
    chunks: Map<FaceBatchKey, List<Pair<SceneObject, GeometryData>>>,
  ) {
    val fallback = material ?: return
    for ((key, sources) in chunks) {
      val representative = sources.firstOrNull()?.first ?: continue
      val geometry = combineGeometry(sources.map { it.second }) ?: continue
      val sharedMaterial = materialForObject(representative, fallback)
      val baseColor = displayBaseColor(representative)
      val vertexData = vertexDataWithTangents(geometry)
      val vertexBuffer = VertexBuffer.Builder()
        .bufferCount(1)
        .vertexCount(geometry.vertexCount)
        .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 28)
        .attribute(VertexBuffer.VertexAttribute.TANGENTS, 0, VertexBuffer.AttributeType.FLOAT4, 12, 28)
        .build(engine).also { it.setBufferAt(engine, 0, vertexData) }
      val indexBuffer = IndexBuffer.Builder()
        .indexCount(geometry.indexCount)
        .bufferType(IndexBuffer.Builder.IndexType.UINT)
        .build(engine).also { it.setBuffer(engine, geometry.indexData) }
      val entity = EntityManager.get().create()
      val materialInstance = sharedMaterial.createInstance().also { instance ->
        applySectionBoxState(instance)
        applyDisplayStyle(instance)
        instance.setParameter(
          "baseColor", Colors.RgbaType.LINEAR,
          baseColor[0], baseColor[1], baseColor[2], baseColor[3],
        )
      }
      RenderableManager.Builder(1)
        .boundingBox(filamentBox(geometry.bounds))
        .culling(true)
        .castShadows(shadowsEnabled)
        .receiveShadows(shadowsEnabled)
        .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, geometry.indexCount)
        .material(0, materialInstance)
        .build(engine, entity)
      val visible = faceVisible(representative)
      if (visible) scene.addEntity(entity)
      faceBatches.add(
        FaceBatchEntry(
          key = key,
          representative = representative,
          entity = entity,
          vertexBuffer = vertexBuffer,
          indexBuffer = indexBuffer,
          material = sharedMaterial,
          materialInstance = materialInstance,
          baseColor = baseColor,
          bounds = geometry.bounds,
          objectCount = sources.size,
          vertexCount = geometry.vertexCount,
          indexCount = geometry.indexCount,
          attached = visible,
        )
      )
    }
  }

  private fun createEdgeBatches(
    engine: Engine,
    scene: Scene,
    chunks: Map<EdgeBatchKey, List<GeometryData>>,
  ) {
    val edgeMaterial = edgeMaterial ?: material ?: return
    for ((key, geometries) in chunks) {
      val geometry = combineGeometry(geometries) ?: continue
      val vertexBuffer = VertexBuffer.Builder()
        .bufferCount(1)
        .vertexCount(geometry.vertexCount)
        .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
        .build(engine).also { it.setBufferAt(engine, 0, geometry.vertexData) }
      val indexBuffer = IndexBuffer.Builder()
        .indexCount(geometry.indexCount)
        .bufferType(IndexBuffer.Builder.IndexType.UINT)
        .build(engine).also { it.setBuffer(engine, geometry.indexData) }
      val entity = EntityManager.get().create()
      val materialInstance = edgeMaterial.createInstance().also { instance ->
        applyDisplayStyle(instance)
        val edgeColor = viewportEdgeColor()
        instance.setParameter(
          "baseColor",
          Colors.RgbaType.LINEAR,
          edgeColor[0], edgeColor[1], edgeColor[2], edgeColor[3],
        )
        applySectionBoxState(instance)
      }
      RenderableManager.Builder(1)
        .boundingBox(filamentBox(geometry.bounds))
        .culling(true)
        .priority(7)
        .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, geometry.indexCount)
        .material(0, materialInstance)
        .build(engine, entity)
      val visible = edgeVisible(key)
      if (visible) scene.addEntity(entity)
      edgeBatches.add(
        EdgeBatchEntry(
          key = key,
          entity = entity,
          vertexBuffer = vertexBuffer,
          indexBuffer = indexBuffer,
          materialInstance = materialInstance,
          vertexCount = geometry.vertexCount,
          indexCount = geometry.indexCount,
          attached = visible,
        )
      )
    }
  }

  private fun createGroundReceiver(
    engine: Engine,
    scene: Scene,
    sceneState: SceneState,
  ) {
    destroyGroundReceiver(engine, scene)
    val receiverMaterial = this.groundMaterial ?: return
    if (sceneState.objects.isEmpty()) return
    val allBounds = sceneState.objects
      .map { transformBounds(it.bounds) }
      .reduce(::unionBounds)
    val buildingHeight = allBounds.max.y - allBounds.min.y
    val horizontalMargin = max(4.0, buildingHeight * 0.70 + 2.0)
    val y = allBounds.min.y + 0.012
    val minX = allBounds.min.x - horizontalMargin
    val maxX = allBounds.max.x + horizontalMargin
    val minZ = allBounds.min.z - horizontalMargin
    val maxZ = allBounds.max.z + horizontalMargin
    val positionData = ByteBuffer.allocateDirect(4 * 12).order(ByteOrder.nativeOrder()).apply {
      putFloat(minX.toFloat()); putFloat(y.toFloat()); putFloat(minZ.toFloat())
      putFloat(maxX.toFloat()); putFloat(y.toFloat()); putFloat(minZ.toFloat())
      putFloat(maxX.toFloat()); putFloat(y.toFloat()); putFloat(maxZ.toFloat())
      putFloat(minX.toFloat()); putFloat(y.toFloat()); putFloat(maxZ.toFloat())
      flip()
    }
    val indexData = ByteBuffer.allocateDirect(6 * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer().apply {
        // Counter-clockwise when viewed from above, so the receiver normal is
        // +Y and the sun can shade it from the front-facing side.
        put(0); put(2); put(1); put(0); put(3); put(2)
        flip()
      }
    val geometry = GeometryData(
      vertexCount = 4,
      indexCount = 6,
      vertexData = positionData,
      indexData = indexData,
      bounds = SceneBounds(
        ScenePoint(minX, y, minZ),
        ScenePoint(maxX, y, maxZ),
      ),
    )
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(geometry.vertexCount)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 28)
      .attribute(VertexBuffer.VertexAttribute.TANGENTS, 0, VertexBuffer.AttributeType.FLOAT4, 12, 28)
      .build(engine)
      .also { it.setBufferAt(engine, 0, vertexDataWithTangents(geometry)) }
    val indexBuffer = IndexBuffer.Builder()
      .indexCount(geometry.indexCount)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
      .also { it.setBuffer(engine, geometry.indexData) }
    val materialInstance = receiverMaterial.createInstance().also { instance ->
      applySectionBoxState(instance)
      instance.setParameter("displayShade", 0.0f)
      val groundColor = viewportGroundColor()
      instance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        groundColor[0], groundColor[1], groundColor[2], groundColor[3],
      )
    }
    val entity = EntityManager.get().create()
    RenderableManager.Builder(1)
      .boundingBox(filamentBox(geometry.bounds))
      .culling(false)
      .castShadows(false)
      .receiveShadows(true)
      .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, geometry.indexCount)
      .material(0, materialInstance)
      .build(engine, entity)
    val attached = realShadowVisible()
    if (attached) scene.addEntity(entity)
    groundReceiver = GroundReceiverEntry(
      entity = entity,
      vertexBuffer = vertexBuffer,
      indexBuffer = indexBuffer,
      materialInstance = materialInstance,
      attached = attached,
    )
    Log.i(TAG, "Real shadow receiver: ${horizontalMargin.format(2)}m perimeter plane")
  }

  private fun createGridBatch(
    engine: Engine,
    scene: Scene,
    sceneState: SceneState,
  ) {
    destroyGridBatch(engine, scene)
    // Native IFC caches already contain the complete building/site payload.
    // A 50 m helper grid is useful for authoring primitives, but around a
    // streamed imported model its projected outer lines read like a second
    // wireframe/bounding cage at fit-to-view scale. Keep the cache view clean;
    // the grid remains available for the lightweight authoring scene.
    if (nativeBimCache != null) return
    val gridMaterial = gridMaterial ?: return
    if (sceneState.objects.isEmpty()) return
    val allBounds = sceneState.objects
      .map { transformBounds(it.bounds) }
      .reduce(::unionBounds)
    val centerX = (allBounds.min.x + allBounds.max.x) * 0.5
    val centerZ = (allBounds.min.z + allBounds.max.z) * 0.5
    val groundY = allBounds.min.y + 0.025
    val radius = 50.0
    val minX = centerX - radius
    val maxX = centerX + radius
    val minZ = centerZ - radius
    val maxZ = centerZ + radius
    val lineVertices = mutableListOf<Float>()
    val lineIndices = mutableListOf<Int>()
    val lineHalfWidth = 0.012

    fun addVerticalLine(x: Double, halfSpan: Double) {
      val base = lineVertices.size / 3
      lineVertices += (x - lineHalfWidth).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (centerZ - halfSpan).toFloat()
      lineVertices += (x + lineHalfWidth).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (centerZ - halfSpan).toFloat()
      lineVertices += (x + lineHalfWidth).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (centerZ + halfSpan).toFloat()
      lineVertices += (x - lineHalfWidth).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (centerZ + halfSpan).toFloat()
      lineIndices += base; lineIndices += base + 2; lineIndices += base + 1
      lineIndices += base; lineIndices += base + 3; lineIndices += base + 2
    }

    fun addHorizontalLine(z: Double, halfSpan: Double) {
      val base = lineVertices.size / 3
      lineVertices += (centerX - halfSpan).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (z - lineHalfWidth).toFloat()
      lineVertices += (centerX + halfSpan).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (z - lineHalfWidth).toFloat()
      lineVertices += (centerX + halfSpan).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (z + lineHalfWidth).toFloat()
      lineVertices += (centerX - halfSpan).toFloat(); lineVertices += groundY.toFloat(); lineVertices += (z + lineHalfWidth).toFloat()
      lineIndices += base; lineIndices += base + 2; lineIndices += base + 1
      lineIndices += base; lineIndices += base + 3; lineIndices += base + 2
    }

    // The grid is a navigation aid, not a bounding box. Clip every line to a
    // circular 50 m working area; a square line extent creates four apparent
    // walls around the model at fit-to-view scale and looks like wireframe.
    var offset = -radius + 1.0
    while (offset <= radius - 1.0 + 0.001) {
      val halfSpan = kotlin.math.sqrt((radius * radius - offset * offset).coerceAtLeast(0.0))
      if (halfSpan >= 0.25) {
        addVerticalLine(centerX + offset, halfSpan)
        addHorizontalLine(centerZ + offset, halfSpan)
      }
      offset += 1.0
    }
    val vertexData = ByteBuffer.allocateDirect(lineVertices.size * Float.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).apply {
        lineVertices.forEach { putFloat(it) }
        flip()
      }
    val indexData = ByteBuffer.allocateDirect(lineIndices.size * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer().apply {
        lineIndices.forEach { put(it) }
        flip()
      }
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(lineVertices.size / 3)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
      .build(engine)
      .also { it.setBufferAt(engine, 0, vertexData) }
    val indexBuffer = IndexBuffer.Builder()
      .indexCount(lineIndices.size)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
      .also { it.setBuffer(engine, indexData) }
    val materialInstance = gridMaterial.createInstance().also { instance ->
      applySectionBoxState(instance)
      applyDisplayStyle(instance)
      val gridColor = viewportGridColor()
      instance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        gridColor[0], gridColor[1], gridColor[2], gridColor[3],
      )
      instance.setParameter("gridCenter", centerX.toFloat(), groundY.toFloat(), centerZ.toFloat(), 0.0f)
      instance.setParameter("gridRadius", radius.toFloat())
      instance.setParameter("gridFadeStart", 34.0f)
      instance.setParameter("gridMinorStep", 1.0f)
      instance.setParameter("gridMajorStep", 5.0f)
    }
    val entity = EntityManager.get().create()
    RenderableManager.Builder(1)
      .boundingBox(
        filamentBox(
          SceneBounds(
            ScenePoint(minX, groundY, minZ),
            ScenePoint(maxX, groundY, maxZ),
          ),
        ),
      )
      .culling(false)
      .castShadows(false)
      .receiveShadows(false)
      .priority(0)
      .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, lineIndices.size)
      .material(0, materialInstance)
      .build(engine, entity)
    // Solid is the primary coordination view. Keep its background clean so
    // the model's filled surfaces are never mistaken for a wireframe. The
    // optional working grid remains available in Shaded, where it reads as a
    // navigation aid rather than an architectural edge pass.
    val attached = projectionMode == "isometric" && displayStyle != "solid"
    if (attached) scene.addEntity(entity)
    gridBatch = GridBatchEntry(
      entity = entity,
      vertexBuffer = vertexBuffer,
      indexBuffer = indexBuffer,
      materialInstance = materialInstance,
      attached = attached,
    )
    Log.i(TAG, "3D grid enabled: ${radius.format(0)}m radius, fade=${34.0.format(0)}-${radius.format(0)}m")
  }

  private fun destroyGridBatch(engine: Engine?, scene: Scene?) {
    val batch = gridBatch ?: return
    if (batch.attached) scene?.removeEntity(batch.entity)
    engine?.destroyEntity(batch.entity)
    engine?.destroyMaterialInstance(batch.materialInstance)
    engine?.destroyVertexBuffer(batch.vertexBuffer)
    engine?.destroyIndexBuffer(batch.indexBuffer)
    EntityManager.get().destroy(batch.entity)
    gridBatch = null
  }

  private fun createStaticShadowBatch(
    engine: Engine,
    scene: Scene,
    sceneState: SceneState,
  ) {
    destroyStaticShadowBatch(engine, scene)
    val shadowMaterial = shadowMaterial ?: return
    if (sceneState.objects.isEmpty()) return

    val allBounds = sceneState.objects
      .map { transformBounds(it.bounds) }
      .reduce(::unionBounds)
    val groundY = allBounds.min.y + 0.018
    val lightX = 0.58
    val lightY = -1.0
    val lightZ = 0.36

    data class ShadowPoint(val x: Double, val z: Double)
    fun cross(origin: ShadowPoint, first: ShadowPoint, second: ShadowPoint): Double =
      (first.x - origin.x) * (second.z - origin.z) -
        (first.z - origin.z) * (second.x - origin.x)

    fun convexHull(points: List<ShadowPoint>): List<ShadowPoint> {
      val sorted = points
        .distinctBy { "${kotlin.math.round(it.x * 10000.0)}:${kotlin.math.round(it.z * 10000.0)}" }
        .sortedWith(compareBy<ShadowPoint> { it.x }.thenBy { it.z })
      if (sorted.size <= 2) return sorted
      val lower = mutableListOf<ShadowPoint>()
      for (point in sorted) {
        while (lower.size >= 2 && cross(lower[lower.size - 2], lower.last(), point) <= 0.0) {
          lower.removeAt(lower.lastIndex)
        }
        lower.add(point)
      }
      val upper = mutableListOf<ShadowPoint>()
      for (point in sorted.asReversed()) {
        while (upper.size >= 2 && cross(upper[upper.size - 2], upper.last(), point) <= 0.0) {
          upper.removeAt(upper.lastIndex)
        }
        upper.add(point)
      }
      return (lower.dropLast(1) + upper.dropLast(1))
    }

    fun projectToGround(point: ScenePoint): ShadowPoint? {
      val distance = (groundY - point.y) / lightY
      if (distance < 0.0) return null
      return ShadowPoint(point.x + lightX * distance, point.z + lightZ * distance)
    }

    // Prefer roofs as the baked silhouette. If a model has no roof, its
    // highest walls provide a stable fallback. This keeps campus shadows
    // separated per building instead of making one huge scene-wide polygon.
    val roofs = sceneState.objects.filter { normalizeKind(it.kind) == "roof" }
    val candidates = if (roofs.isNotEmpty()) {
      roofs
    } else {
      val highestY = sceneState.objects.maxOf { transformBounds(it.bounds).max.y }
      sceneState.objects.filter { objectData ->
        normalizeKind(objectData.kind) == "wall" &&
          transformBounds(objectData.bounds).max.y >= highestY - 0.20
      }
    }
    val polygons = candidates.mapNotNull { objectData ->
      val points = boxCorners(objectData.bounds)
        .map(::toFilamentPoint)
        .mapNotNull(::projectToGround)
      val hull = convexHull(points)
      hull.takeIf { it.size >= 3 }
    }
    if (polygons.isEmpty()) return

    val vertices = mutableListOf<ScenePoint>()
    val indices = mutableListOf<Int>()
    for (polygon in polygons) {
      val base = vertices.size
      vertices += polygon.map { point -> ScenePoint(point.x, groundY, point.z) }
      for (index in 1 until polygon.size - 1) {
        indices += base
        indices += base + index
        indices += base + index + 1
      }
    }
    if (vertices.isEmpty() || indices.isEmpty()) return

    val vertexData = ByteBuffer.allocateDirect(vertices.size * 12).order(ByteOrder.nativeOrder())
    for (point in vertices) {
      vertexData.putFloat(point.x.toFloat())
      vertexData.putFloat(point.y.toFloat())
      vertexData.putFloat(point.z.toFloat())
    }
    vertexData.flip()
    val indexData = ByteBuffer
      .allocateDirect(indices.size * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder())
      .asIntBuffer()
    indices.forEach(indexData::put)
    indexData.flip()
    val entity = EntityManager.get().create()
    val materialInstance = shadowMaterial.createInstance().also { instance ->
      applySectionBoxState(instance)
      instance.setParameter("displayShade", 0.0f)
      instance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        0.08f,
        0.10f,
        0.12f,
        0.20f,
      )
    }
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(vertices.size)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
      .build(engine)
      .also { it.setBufferAt(engine, 0, vertexData) }
    val indexBuffer = IndexBuffer.Builder()
      .indexCount(indices.size)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
      .also { it.setBuffer(engine, indexData) }
    RenderableManager.Builder(1)
      .boundingBox(filamentBox(boundsForPoints(vertices)))
      .culling(true)
      .priority(1)
      .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, indices.size)
      .material(0, materialInstance)
      .build(engine, entity)
    val attached = staticShadowVisible()
    if (attached) scene.addEntity(entity)
    staticShadowBatch = StaticShadowBatchEntry(
      entity = entity,
      vertexBuffer = vertexBuffer,
      indexBuffer = indexBuffer,
      materialInstance = materialInstance,
      vertexCount = vertices.size,
      indexCount = indices.size,
      attached = attached,
    )
    Log.i(TAG, "Baked shadow mesh: polygons=${polygons.size}, vertices=${vertices.size}, triangles=${indices.size / 3}")
  }

  // Never show the old baked silhouette. It was a visual approximation and
  // looked like a shadow sticker when the camera moved. Real shadows come
  // only from the Filament sun and the receiving ground plane now.
  private fun staticShadowVisible(): Boolean = false

  private fun combineGeometry(geometries: List<GeometryData>): GeometryData? {
    if (geometries.isEmpty()) return null
    val vertexCount = geometries.sumOf { it.vertexCount }
    val indexCount = geometries.sumOf { it.indexCount }
    if (vertexCount == 0 || indexCount == 0) return null
    val vertexData = ByteBuffer.allocateDirect(vertexCount * 12).order(ByteOrder.nativeOrder())
    val indexData = ByteBuffer.allocateDirect(indexCount * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer()
    var vertexOffset = 0
    for (geometry in geometries) {
      val vertices = geometry.vertexData.duplicate().apply { rewind() }
      vertexData.put(vertices)
      val indices = geometry.indexData.duplicate().apply { rewind() }
      while (indices.hasRemaining()) indexData.put(indices.get() + vertexOffset)
      vertexOffset += geometry.vertexCount
    }
    vertexData.flip()
    indexData.flip()
    val bounds = geometries.map { it.bounds }.reduce(::unionBounds)
    return GeometryData(vertexCount, indexCount, vertexData, indexData, bounds)
  }

  /**
   * Filament's lit materials consume a tangent-frame quaternion rather than a
   * standalone normal attribute. The imported BIM meshes carry positions and
   * indices, so derive an area-weighted normal per vertex once while building
   * the GPU batch. This gives the fixed sun real facade orientation without
   * adding a CPU update to every rendered frame.
   */
  private fun vertexDataWithTangents(geometry: GeometryData): ByteBuffer {
    val positions = FloatArray(geometry.vertexCount * 3)
    val source = geometry.vertexData.duplicate().order(ByteOrder.nativeOrder()).apply { rewind() }
      .asFloatBuffer()
    source.get(positions)
    val normals = DoubleArray(geometry.vertexCount * 3)
    val indices = geometry.indexData.duplicate().apply { rewind() }
    while (indices.remaining() >= 3) {
      val first = indices.get()
      val second = indices.get()
      val third = indices.get()
      if (first !in 0 until geometry.vertexCount ||
        second !in 0 until geometry.vertexCount ||
        third !in 0 until geometry.vertexCount
      ) continue
      val ax = positions[second * 3] - positions[first * 3]
      val ay = positions[second * 3 + 1] - positions[first * 3 + 1]
      val az = positions[second * 3 + 2] - positions[first * 3 + 2]
      val bx = positions[third * 3] - positions[first * 3]
      val by = positions[third * 3 + 1] - positions[first * 3 + 1]
      val bz = positions[third * 3 + 2] - positions[first * 3 + 2]
      val nx = ay * bz - az * by
      val ny = az * bx - ax * bz
      val nz = ax * by - ay * bx
      for (index in intArrayOf(first, second, third)) {
        normals[index * 3] += nx
        normals[index * 3 + 1] += ny
        normals[index * 3 + 2] += nz
      }
    }
    val result = ByteBuffer.allocateDirect(geometry.vertexCount * 28).order(ByteOrder.nativeOrder())
    repeat(geometry.vertexCount) { index ->
      result.putFloat(positions[index * 3])
      result.putFloat(positions[index * 3 + 1])
      result.putFloat(positions[index * 3 + 2])
      var nx = normals[index * 3]
      var ny = normals[index * 3 + 1]
      var nz = normals[index * 3 + 2]
      val length = kotlin.math.sqrt(nx * nx + ny * ny + nz * nz)
      if (length <= 1.0e-12) {
        nx = 0.0
        ny = 1.0
        nz = 0.0
      } else {
        nx /= length
        ny /= length
        nz /= length
      }
      // Quaternion rotating Filament's canonical +Z normal into this normal.
      // This is the compact format expected by VertexAttribute.TANGENTS.
      val dot = nz.coerceIn(-1.0, 1.0)
      if (dot < -0.9999) {
        result.putFloat(0.0f)
        result.putFloat(1.0f)
        result.putFloat(0.0f)
        result.putFloat(0.0f)
      } else {
        val denominator = kotlin.math.sqrt(2.0 * (1.0 + dot)).coerceAtLeast(1.0e-8)
        result.putFloat((-ny / denominator).toFloat())
        result.putFloat((nx / denominator).toFloat())
        result.putFloat(0.0f)
        result.putFloat(kotlin.math.sqrt((1.0 + dot) * 0.5).toFloat())
      }
    }
    result.flip()
    return result
  }

  private fun unionBounds(first: SceneBounds, second: SceneBounds): SceneBounds = SceneBounds(
    min = ScenePoint(
      min(first.min.x, second.min.x),
      min(first.min.y, second.min.y),
      min(first.min.z, second.min.z),
    ),
    max = ScenePoint(
      max(first.max.x, second.max.x),
      max(first.max.y, second.max.y),
      max(first.max.z, second.max.z),
    ),
  )

  private fun kindVisible(kind: String): Boolean =
    visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(kind))

  private fun createRenderable(
    engine: Engine,
    sharedMaterial: Material,
    objectData: SceneObject,
    geometry: GeometryData,
  ): FilamentRenderableEntry? {
    val vertexData = vertexDataWithTangents(geometry)
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(geometry.vertexCount)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 28)
      .attribute(VertexBuffer.VertexAttribute.TANGENTS, 0, VertexBuffer.AttributeType.FLOAT4, 12, 28)
      .build(engine)
    vertexBuffer.setBufferAt(engine, 0, vertexData)

    val indexBuffer = IndexBuffer.Builder()
      .indexCount(geometry.indexCount)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
    indexBuffer.setBuffer(engine, geometry.indexData)

    val entity = EntityManager.get().create()
    val materialInstance = sharedMaterial.createInstance()
    applySectionBoxState(materialInstance)
    applyDisplayStyle(materialInstance)
    val baseColor = displayBaseColor(objectData)
    materialInstance.setParameter(
      "baseColor",
      Colors.RgbaType.LINEAR,
      baseColor[0],
      baseColor[1],
      baseColor[2],
      baseColor[3],
    )
    // objectGeometry already converts RenderScene coordinates to Filament.
    // A second conversion corrupts the culling box and makes geometry pop
    // in/out while orbiting.
    val bounds = geometry.bounds
    RenderableManager.Builder(1)
      // Filament Box is center + half extent, not min + max. Passing raw
      // min/max makes transformed BIM meshes appear to have zero depth and
      // lets frustum culling discard the entire scene.
      .boundingBox(filamentBox(bounds))
      .culling(true)
      .castShadows(shadowsEnabled)
      .receiveShadows(shadowsEnabled)
      .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, geometry.indexCount)
      .material(0, materialInstance)
      .build(engine, entity)

    return FilamentRenderableEntry(
      objectData = objectData,
      entity = entity,
      vertexBuffer = vertexBuffer,
      indexBuffer = indexBuffer,
      material = sharedMaterial,
      materialInstance = materialInstance,
      baseColor = baseColor,
      bounds = bounds,
    )
  }

  private fun objectGeometry(objectData: SceneObject): GeometryData? {
    val meshGeometry = meshGeometryFor(objectData)
    val sourcePoints = meshGeometry?.first ?: boxCorners(objectData.bounds).map(::toFilamentPoint)
    if (sourcePoints.isEmpty()) {
      return null
    }
    // Broad-phase clipping keeps large projects cheap: objects fully outside
    // are rejected before triangle work, while objects fully inside reuse the
    // ordinary mesh path. Only geometry touching a cut plane is polygon-clipped.
    var fullyInsideClipVolume = clipPlanes.isEmpty()
    if (clipPlanes.isNotEmpty()) {
      fullyInsideClipVolume = true
      for (plane in clipPlanes) {
        var maximumDistance = Double.NEGATIVE_INFINITY
        var minimumDistance = Double.POSITIVE_INFINITY
        for (point in sourcePoints) {
          val distance = plane.distance(point)
          maximumDistance = max(maximumDistance, distance)
          minimumDistance = min(minimumDistance, distance)
        }
        if (maximumDistance < -1.0e-6) return null
        if (minimumDistance < -1.0e-6) fullyInsideClipVolume = false
      }
    }
    val sourceTriangles = meshGeometry?.second ?: run {
      listOf(
        intArrayOf(0, 1, 2), intArrayOf(0, 2, 3),
        intArrayOf(4, 6, 5), intArrayOf(4, 7, 6),
        intArrayOf(0, 4, 5), intArrayOf(0, 5, 1),
        intArrayOf(1, 5, 6), intArrayOf(1, 6, 2),
        intArrayOf(2, 6, 7), intArrayOf(2, 7, 3),
        intArrayOf(3, 7, 4), intArrayOf(3, 4, 0),
      )
    }
    val meshPoints = mutableListOf<ScenePoint>()
    val triangles = mutableListOf<IntArray>()
    if (fullyInsideClipVolume) {
      meshPoints.addAll(sourcePoints)
      triangles.addAll(sourceTriangles)
    } else {
      for (triangle in sourceTriangles) {
        if (triangle.any { it !in sourcePoints.indices }) continue
        var polygon = listOf(sourcePoints[triangle[0]], sourcePoints[triangle[1]], sourcePoints[triangle[2]])
        for (plane in clipPlanes) {
          if (polygon.isEmpty()) break
          val clipped = mutableListOf<ScenePoint>()
          for (index in polygon.indices) {
            val first = polygon[index]
            val second = polygon[(index + 1) % polygon.size]
            val firstDistance = plane.distance(first)
            val secondDistance = plane.distance(second)
            val firstInside = firstDistance >= -1.0e-6
            val secondInside = secondDistance >= -1.0e-6
            if (firstInside != secondInside) {
              val denominator = firstDistance - secondDistance
              val ratio = if (kotlin.math.abs(denominator) <= 1.0e-12) 0.0 else firstDistance / denominator
              clipped.add(ScenePoint(
                first.x + (second.x - first.x) * ratio,
                first.y + (second.y - first.y) * ratio,
                first.z + (second.z - first.z) * ratio,
              ))
            }
            if (secondInside) clipped.add(second)
          }
          polygon = clipped
        }
        if (polygon.size >= 3) {
          val base = meshPoints.size
          meshPoints.addAll(polygon)
          for (index in 1 until polygon.size - 1) {
            triangles.add(intArrayOf(base, base + index, base + index + 1))
          }
        }
      }
    }
    if (meshPoints.isEmpty() || triangles.isEmpty()) return null
    val vertexData = ByteBuffer.allocateDirect(meshPoints.size * 12).order(ByteOrder.nativeOrder())
    for (point in meshPoints) {
      vertexData.putFloat(point.x.toFloat())
      vertexData.putFloat(point.y.toFloat())
      vertexData.putFloat(point.z.toFloat())
    }
    vertexData.flip()
    val indexData = ByteBuffer
      .allocateDirect(triangles.size * 3 * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder())
      .asIntBuffer()
    for (triangle in triangles) {
      indexData.put(triangle[0])
      indexData.put(triangle[1])
      indexData.put(triangle[2])
    }
    indexData.flip()
    return GeometryData(
      vertexCount = meshPoints.size,
      indexCount = triangles.size * 3,
      vertexData = vertexData,
      indexData = indexData,
      bounds = boundsForPoints(meshPoints),
      points = meshPoints,
      triangles = triangles,
    )
  }

  /**
   * Validate imported triangle data before it reaches an Android GPU index
   * buffer. A single out-of-range index is undefined behaviour on GLES and
   * can present as intermittent red/black tiles while the camera exposes a
   * different part of a large IFC mesh. Invalid or zero-area faces are safe
   * to skip; supported IFC geometry remains exact and unsupported elements
   * still use the bounds box fallback.
   */
  private fun meshGeometryFor(
    objectData: SceneObject,
    triangleBudget: Int? = null,
  ): Pair<List<ScenePoint>, List<IntArray>>? {
    val mesh = objectData.mesh
    if (mesh.positions.isEmpty() || mesh.indices.size < 3) return null
    val points = mesh.positions.map(::toFilamentPoint)
    if (points.isEmpty() || points.any { point ->
        !point.x.isFinite() || !point.y.isFinite() || !point.z.isFinite()
      }) {
      return null
    }
    var rejectedFaces = 0
    val sourceTriangleCount = mesh.indices.size / 3
    val stride = triangleBudget
      ?.takeIf { it > 0 && sourceTriangleCount > it }
      ?.let { max(1, (sourceTriangleCount + it - 1) / it) }
      ?: 1
    val triangles = (0 until sourceTriangleCount).mapNotNull { triangleIndex ->
      if (stride > 1 && triangleIndex % stride != 0 && triangleIndex != sourceTriangleCount - 1) {
        return@mapNotNull null
      }
      val offset = triangleIndex * 3
      val group = mesh.indices.subList(offset, offset + 3)
      if (group.size != 3 || group.any { it !in points.indices }) {
        rejectedFaces += 1
        return@mapNotNull null
      }
      val first = points[group[0]]
      val second = points[group[1]]
      val third = points[group[2]]
      val abX = second.x - first.x
      val abY = second.y - first.y
      val abZ = second.z - first.z
      val acX = third.x - first.x
      val acY = third.y - first.y
      val acZ = third.z - first.z
      val crossX = abY * acZ - abZ * acY
      val crossY = abZ * acX - abX * acZ
      val crossZ = abX * acY - abY * acX
      val areaSquared = crossX * crossX + crossY * crossY + crossZ * crossZ
      if (!areaSquared.isFinite() || areaSquared <= 1.0e-16) {
        rejectedFaces += 1
        null
      } else {
        intArrayOf(group[0], group[1], group[2])
      }
    }
    if (rejectedFaces > 0) {
      Log.w(
        TAG,
        "Skipped $rejectedFaces invalid IFC faces for ${objectData.elementId ?: "unassigned"}.",
      )
    }
    return triangles.takeIf { it.isNotEmpty() }?.let { points to it }
  }

  /**
   * Reconstructs only physical outlines from the already-clipped triangle
   * soup. Cut-plane contours are included, while coplanar triangulation seams
   * remain hidden.
   */
  private fun clippedFeatureEdges(
    points: List<ScenePoint>,
    triangles: List<IntArray>,
  ): List<NativeVisualEdge> {
    data class PointKey(val x: Long, val y: Long, val z: Long)
    data class EdgeUse(
      val first: Int,
      val second: Int,
      val triangleIndices: MutableList<Int> = mutableListOf(),
      val normals: MutableList<DoubleArray> = mutableListOf(),
    )
    fun pointKey(point: ScenePoint) = PointKey(
      kotlin.math.round(point.x * 100000.0).toLong(),
      kotlin.math.round(point.y * 100000.0).toLong(),
      kotlin.math.round(point.z * 100000.0).toLong(),
    )
    fun orderedKey(first: PointKey, second: PointKey): String {
      val a = "${first.x}:${first.y}:${first.z}"
      val b = "${second.x}:${second.y}:${second.z}"
      return if (a <= b) "$a|$b" else "$b|$a"
    }
    val uses = linkedMapOf<String, EdgeUse>()
    for ((triangleIndex, triangle) in triangles.withIndex()) {
      if (triangle.size != 3 || triangle.any { it !in points.indices }) continue
      val normal = triangleNormal(
        points[triangle[0]], points[triangle[1]], points[triangle[2]],
      )
      for ((first, second) in arrayOf(
        triangle[0] to triangle[1],
        triangle[1] to triangle[2],
        triangle[2] to triangle[0],
      )) {
        val key = orderedKey(pointKey(points[first]), pointKey(points[second]))
        val use = uses.getOrPut(key) { EdgeUse(first, second) }
        use.triangleIndices.add(triangleIndex)
        use.normals.add(normal)
      }
    }
    return uses.values.mapNotNull { use ->
      val first = points[use.first]
      val second = points[use.second]
      val onCutPlane = clipPlanes.any { plane ->
        kotlin.math.abs(plane.distance(first)) <= 1.0e-5 &&
          kotlin.math.abs(plane.distance(second)) <= 1.0e-5
      }
      val sharp = use.normals.indices.any { left ->
        (left + 1 until use.normals.size).any { right ->
          normalDot(use.normals[left], use.normals[right]) < 0.82
        }
      }
      if (use.triangleIndices.size == 1 || onCutPlane || sharp) {
        NativeVisualEdge(
          first = use.first,
          second = use.second,
          triangleIndices = use.triangleIndices.toIntArray(),
          sharp = sharp || onCutPlane,
        )
      } else {
        null
      }
    }
  }

  private fun edgeGeometry(
    points: List<ScenePoint>,
    edges: List<NativeVisualEdge>,
    triangles: List<IntArray>,
    wallJunctionEdges: Boolean = false,
    wallJunctionElevations: List<Double> = emptyList(),
    radiusScale: Double = 1.0,
  ): GeometryData? {
    val validEdges = edges.filter { it.first in points.indices && it.second in points.indices }
    val isFloorPlan = projectionMode == "topDown"
    // Floor plan uses a lighter line weight. Section/elevation keeps the
    // existing GPU-safe border sizes; only the noisy top-down presentation is
    // narrowed here.
    // 3D borders remain visible, but the previous 28 mm prisms read as
    // oversized black bars in the orbit view. Keep the lighter plan weight
    // and use a separate, still-readable 3D weight. At fit-to-model zoom a
    // 6 mm radius becomes sub-pixel on a tablet, so the edge can alternate
    // between covered and visible fragments as the camera moves.
    val normalRadius = when {
      isFloorPlan -> 0.004
      projectionMode != "isometric" -> 0.009
      else -> 0.010
    } * radiusScale
    // Junction borders deliberately get a stronger visual treatment than
    // ordinary silhouette edges. They are the only reliable room boundary
    // after an exterior wall has been removed and an adjacent floor/ceiling
    // occupies the same depth range.
    val junctionRadius = when {
      isFloorPlan -> 0.008
      projectionMode == "isometric" -> 0.012
      else -> 0.006
    } * radiusScale
    val sourceBounds = boundsForPoints(points)
    data class EdgeKey(val first: Int, val second: Int)
    fun edgeKey(first: Int, second: Int) = if (first < second) {
      EdgeKey(first, second)
    } else {
      EdgeKey(second, first)
    }
    val junctionKeys = linkedSetOf<EdgeKey>()
    if (wallJunctionEdges) {
      // Do not depend solely on normal/crease classification here. A ceiling
      // or floor can make an otherwise valid wall edge look coplanar after
      // mesh welding. Extract the top/bottom triangle boundary segments
      // directly, then draw them in the dedicated junction pass below.
      val minimumY = sourceBounds.min.y
      val maximumY = sourceBounds.max.y
      val planEdgeUseCounts = linkedMapOf<String, Int>()
      val planEdgeCandidates = mutableListOf<Pair<Int, Int>>()
      fun geometricEdgeKey(first: ScenePoint, second: ScenePoint): String {
        fun pointKey(point: ScenePoint) =
          "${kotlin.math.round(point.x * 100000.0)}:${kotlin.math.round(point.y * 100000.0)}:${kotlin.math.round(point.z * 100000.0)}"
        val firstKey = pointKey(first)
        val secondKey = pointKey(second)
        return if (firstKey <= secondKey) "$firstKey|$secondKey" else "$secondKey|$firstKey"
      }
      fun isJunctionPoint(point: ScenePoint) =
        kotlin.math.abs(point.y - minimumY) <= 1e-5 ||
          kotlin.math.abs(point.y - maximumY) <= 1e-5
      for (triangle in triangles) {
        if (triangle.size != 3 || triangle.any { it !in points.indices }) continue
        for ((firstIndex, secondIndex) in arrayOf(
          triangle[0] to triangle[1],
          triangle[1] to triangle[2],
          triangle[2] to triangle[0],
        )) {
          val first = points[firstIndex]
          val second = points[secondIndex]
          if (kotlin.math.abs(first.y - second.y) <= 1e-6 &&
            isJunctionPoint(first) && isJunctionPoint(second)) {
            if (isFloorPlan) {
              planEdgeCandidates.add(firstIndex to secondIndex)
              val key = geometricEdgeKey(first, second)
              planEdgeUseCounts[key] = (planEdgeUseCounts[key] ?: 0) + 1
            } else {
              junctionKeys.add(edgeKey(firstIndex, secondIndex))
            }
          }
        }
      }
      if (isFloorPlan) {
        // A diagonal shared by the two triangles of one coplanar face is an
        // internal tessellation seam, not a wall boundary. Keep only physical
        // perimeter edges in top-down view.
        for ((firstIndex, secondIndex) in planEdgeCandidates) {
          val key = geometricEdgeKey(points[firstIndex], points[secondIndex])
          if (planEdgeUseCounts[key] == 1) {
            junctionKeys.add(edgeKey(firstIndex, secondIndex))
          }
        }
      }
    }
    data class RenderEdge(
      val first: ScenePoint,
      val second: ScenePoint,
      val junction: Boolean = false,
      val triangleIndices: IntArray = IntArray(0),
    )
    val edgeTriangleIndices = validEdges.associateBy(
      keySelector = { edgeKey(it.first, it.second) },
      valueTransform = { it.triangleIndices },
    )
    val allEdges = validEdges.map { it.first to it.second }.toMutableList()
    for (key in junctionKeys) {
      if (allEdges.none { edgeKey(it.first, it.second) == key }) {
        allEdges.add(key.first to key.second)
      }
    }
    val rawRenderEdges = allEdges.map { edge ->
      RenderEdge(
        points[edge.first],
        points[edge.second],
        wallJunctionEdges && junctionKeys.contains(edgeKey(edge.first, edge.second)),
        edgeTriangleIndices[edgeKey(edge.first, edge.second)] ?: IntArray(0),
      )
    }.toMutableList()
    if (wallJunctionEdges && !isFloorPlan) {
      // A joined wall can legitimately have no (or incomplete) feature-edge
      // list after vertex welding. Its physical outline must not disappear
      // from Solid in that case: reconstruct the bottom/top sections and
      // every vertical envelope corner directly from the engine mesh.
      rawRenderEdges.addAll(
        wallIntersectionSegments(
          points,
          triangles,
          wallJunctionElevations + listOf(sourceBounds.min.y, sourceBounds.max.y),
          sourceBounds,
        )
          .map { (first, second) -> RenderEdge(first, second, junction = true) },
      )
      rawRenderEdges.addAll(wallVerticalEnvelopeSegments(points, sourceBounds)
        .map { (first, second) -> RenderEdge(first, second, junction = true) })
    }
    data class PointKey(val x: Long, val y: Long, val z: Long)
    data class RenderEdgeKey(val first: PointKey, val second: PointKey)
    fun pointKey(point: ScenePoint) = PointKey(
      kotlin.math.round(point.x * 100000.0).toLong(),
      kotlin.math.round(point.y * 100000.0).toLong(),
      kotlin.math.round(point.z * 100000.0).toLong(),
    )
    fun renderEdgeKey(edge: RenderEdge): RenderEdgeKey {
      val first = pointKey(edge.first)
      val second = pointKey(edge.second)
      return if (first.toString() <= second.toString()) RenderEdgeKey(first, second) else RenderEdgeKey(second, first)
    }
    // A plane can cross both triangles of one face. Draw one physical border,
    // not two coincident dark prisms.
    val renderEdges = linkedMapOf<RenderEdgeKey, RenderEdge>()
    for (edge in rawRenderEdges) {
      val key = renderEdgeKey(edge)
      val previous = renderEdges[key]
      renderEdges[key] = if (previous == null || edge.junction) edge else previous
    }
    if (renderEdges.isEmpty()) return null
    val vertexData = ByteBuffer.allocateDirect(renderEdges.size * 8 * 12).order(ByteOrder.nativeOrder())
    // Four side quads preserve the exact square-prism silhouette and depth
    // behavior. The two microscopic end caps are never useful at BIM view
    // distances and mostly overlap the next connected segment, so omitting
    // them removes one third of border triangles without changing thickness.
    val indicesPerPrism = 24
    val indexData = ByteBuffer.allocateDirect(renderEdges.size * indicesPerPrism * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer()
    val cubeIndices = intArrayOf(
      0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
      2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0,
    )
    var vertexOffset = 0
    for (edge in renderEdges.values) {
      val sourceFirst = edge.first
      val sourceSecond = edge.second
      // At a wall/floor or wall/ceiling contact the border prism can be
      // coplanar with the adjacent system and lose the depth test. Move only
      // those horizontal wall edges 18 mm onto the visible wall face: it
      // preserves hidden-edge behavior while making an interior room read as
      // bounded after an exterior wall is removed.
      val averageY = (sourceFirst.y + sourceSecond.y) * 0.5
      val isHorizontalWallBoundary = edge.junction
      val radius = if (isHorizontalWallBoundary) junctionRadius else normalRadius
      val junctionOffset = when {
        isHorizontalWallBoundary && kotlin.math.abs(averageY - sourceBounds.min.y) <= 1e-5 -> 0.05
        isHorizontalWallBoundary && kotlin.math.abs(averageY - sourceBounds.max.y) <= 1e-5 -> -0.05
        // A ceiling intersection is intentionally just below the ceiling
        // plane. Leaving the prism centred on that plane makes it coplanar
        // with the ceiling surface, so depth testing hides it when looking
        // into a room through a removed exterior wall.
        isHorizontalWallBoundary -> -0.035
        else -> 0.0
      }
      val isHorizontalJunction = isHorizontalWallBoundary &&
        kotlin.math.abs(sourceFirst.y - sourceSecond.y) <= 1e-5
      // The generated prism has thickness, but on mobile depth precision can
      // still place its centre behind the wall face. Push a horizontal wall
      // junction just outside its nearest face. Depth testing remains on, so
      // an actually occluding wall still hides the border (unlike Wire).
      val faceOffset = if (isHorizontalJunction && !isFloorPlan) {
        wallFaceOffset(
          ScenePoint(
            (sourceFirst.x + sourceSecond.x) * 0.5,
            averageY,
            (sourceFirst.z + sourceSecond.z) * 0.5,
          ),
          sourceBounds,
        )
      } else {
        ScenePoint(0.0, 0.0, 0.0)
      }
      // The edge prism otherwise sits exactly on the imported face.  That is
      // enough to trigger depth-buffer fighting on tablet GPUs, which appears
      // as disappearing/dotted lines while orbiting.  Move it a tiny amount
      // along the average adjacent face normal; it remains depth-tested and
      // is still hidden by genuinely occluding geometry.
      val surfaceOffset = edgeSurfaceOffset(edge.triangleIndices, points, triangles)
      val first = sourceFirst.copy(
        x = sourceFirst.x + faceOffset.x + surfaceOffset.x,
        y = sourceFirst.y + junctionOffset + surfaceOffset.y,
        z = sourceFirst.z + faceOffset.z + surfaceOffset.z,
      )
      val second = sourceSecond.copy(
        x = sourceSecond.x + faceOffset.x + surfaceOffset.x,
        y = sourceSecond.y + junctionOffset + surfaceOffset.y,
        z = sourceSecond.z + faceOffset.z + surfaceOffset.z,
      )
      val dx = second.x - first.x; val dy = second.y - first.y; val dz = second.z - first.z
      val length = kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)
      if (length <= 1e-8) continue
      val axisX = dx / length; val axisY = dy / length; val axisZ = dz / length
      val refX = if (kotlin.math.abs(axisY) < 0.85) 0.0 else 1.0
      val refY = if (kotlin.math.abs(axisY) < 0.85) 1.0 else 0.0
      val ux0 = axisY * 0.0 - axisZ * refY
      val uy0 = axisZ * refX - axisX * 0.0
      val uz0 = axisX * refY - axisY * refX
      val uLength = kotlin.math.sqrt(ux0 * ux0 + uy0 * uy0 + uz0 * uz0).coerceAtLeast(1e-9)
      val ux = ux0 / uLength * radius; val uy = uy0 / uLength * radius; val uz = uz0 / uLength * radius
      val vx = axisY * uz - axisZ * uy
      val vy = axisZ * ux - axisX * uz
      val vz = axisX * uy - axisY * ux
      val corners = arrayOf(
        doubleArrayOf(first.x - ux - vx, first.y - uy - vy, first.z - uz - vz),
        doubleArrayOf(first.x + ux - vx, first.y + uy - vy, first.z + uz - vz),
        doubleArrayOf(first.x + ux + vx, first.y + uy + vy, first.z + uz + vz),
        doubleArrayOf(first.x - ux + vx, first.y - uy + vy, first.z - uz + vz),
        doubleArrayOf(second.x - ux - vx, second.y - uy - vy, second.z - uz - vz),
        doubleArrayOf(second.x + ux - vx, second.y + uy - vy, second.z + uz - vz),
        doubleArrayOf(second.x + ux + vx, second.y + uy + vy, second.z + uz + vz),
        doubleArrayOf(second.x - ux + vx, second.y - uy + vy, second.z - uz + vz),
      )
      for (corner in corners) {
        vertexData.putFloat(corner[0].toFloat()); vertexData.putFloat(corner[1].toFloat()); vertexData.putFloat(corner[2].toFloat())
      }
      for (index in cubeIndices) indexData.put(vertexOffset + index)
      vertexOffset += 8
    }
    if (vertexOffset == 0) return null
    vertexData.flip(); indexData.flip()
    // The visual prisms intentionally extend beyond the source face. Include
    // that thickness in the culling bounds, especially for interior views.
    val bounds = SceneBounds(
      ScenePoint(sourceBounds.min.x - 0.09, sourceBounds.min.y - 0.09, sourceBounds.min.z - 0.09),
      ScenePoint(sourceBounds.max.x + 0.09, sourceBounds.max.y + 0.09, sourceBounds.max.z + 0.09),
    )
    return GeometryData(vertexOffset, (vertexOffset / 8) * indicesPerPrism, vertexData, indexData, bounds)
  }

  private fun wallFaceOffset(point: ScenePoint, bounds: SceneBounds): ScenePoint {
    val offset = 0.05
    val candidates = listOf(
      kotlin.math.abs(point.x - bounds.min.x) to ScenePoint(-offset, 0.0, 0.0),
      kotlin.math.abs(point.x - bounds.max.x) to ScenePoint(offset, 0.0, 0.0),
      kotlin.math.abs(point.z - bounds.min.z) to ScenePoint(0.0, 0.0, -offset),
      kotlin.math.abs(point.z - bounds.max.z) to ScenePoint(0.0, 0.0, offset),
    )
    return candidates.minByOrNull { it.first }?.second ?: ScenePoint(0.0, 0.0, 0.0)
  }

  private fun wallVerticalEnvelopeSegments(
    points: List<ScenePoint>,
    bounds: SceneBounds,
  ): List<Pair<ScenePoint, ScenePoint>> {
    val epsilon = 1e-5
    data class HorizontalKey(val x: Long, val z: Long)
    fun key(point: ScenePoint) = HorizontalKey(
      kotlin.math.round(point.x * 100000.0).toLong(),
      kotlin.math.round(point.z * 100000.0).toLong(),
    )
    val lower = linkedMapOf<HorizontalKey, ScenePoint>()
    val upper = linkedMapOf<HorizontalKey, ScenePoint>()
    for (point in points) {
      if (kotlin.math.abs(point.y - bounds.min.y) <= epsilon) lower.putIfAbsent(key(point), point)
      if (kotlin.math.abs(point.y - bounds.max.y) <= epsilon) upper.putIfAbsent(key(point), point)
    }
    return lower.mapNotNull { (horizontal, first) ->
      upper[horizontal]?.let { second -> first to second }
    }
  }

  private fun wallIntersectionSegments(
    points: List<ScenePoint>,
    triangles: List<IntArray>,
    elevations: List<Double>,
    bounds: SceneBounds,
  ): List<Pair<ScenePoint, ScenePoint>> {
    val result = linkedMapOf<String, Pair<ScenePoint, ScenePoint>>()
    val epsilon = 1e-5
    for (elevation in elevations.distinct()) {
      if (elevation < bounds.min.y - epsilon || elevation > bounds.max.y + epsilon) continue
      for (triangle in triangles) {
        if (triangle.size != 3 || triangle.any { it !in points.indices }) continue
        val trianglePoints = triangle.map { points[it] }
        val hits = mutableListOf<ScenePoint>()
        for ((first, second) in arrayOf(
          trianglePoints[0] to trianglePoints[1],
          trianglePoints[1] to trianglePoints[2],
          trianglePoints[2] to trianglePoints[0],
        )) {
          val firstDelta = first.y - elevation
          val secondDelta = second.y - elevation
          if (kotlin.math.abs(firstDelta) <= epsilon && kotlin.math.abs(secondDelta) <= epsilon) continue
          if ((firstDelta < -epsilon && secondDelta < -epsilon) ||
            (firstDelta > epsilon && secondDelta > epsilon)) continue
          val denominator = second.y - first.y
          if (kotlin.math.abs(denominator) <= epsilon) continue
          val t = ((elevation - first.y) / denominator).coerceIn(0.0, 1.0)
          val hit = ScenePoint(
            first.x + (second.x - first.x) * t,
            elevation,
            first.z + (second.z - first.z) * t,
          )
          if (hits.none { kotlin.math.abs(it.x - hit.x) <= epsilon && kotlin.math.abs(it.z - hit.z) <= epsilon }) {
            hits.add(hit)
          }
        }
        if (hits.size >= 2 && kotlin.math.abs(hits[0].x - hits[1].x) + kotlin.math.abs(hits[0].z - hits[1].z) > epsilon) {
          val first = hits[0]
          val second = hits[1]
          fun key(point: ScenePoint) = "${kotlin.math.round(point.x * 100000.0)}:${kotlin.math.round(point.y * 100000.0)}:${kotlin.math.round(point.z * 100000.0)}"
          val firstKey = key(first)
          val secondKey = key(second)
          val segmentKey = if (firstKey <= secondKey) "$firstKey|$secondKey" else "$secondKey|$firstKey"
          result.putIfAbsent(segmentKey, first to second)
        }
      }
    }
    return result.values.toList()
  }

  private fun syncVisibility() {
    val scene = scene ?: return
    for (entry in renderables.values) {
      val visible = faceVisible(entry.objectData)
      if (visible && !entry.attached) {
        scene.addEntity(entry.entity)
        entry.attached = true
      } else if (!visible && entry.attached) {
        scene.removeEntity(entry.entity)
        entry.attached = false
      }
    }
    for (batch in faceBatches) {
      val visible = batch.nativeKindMask?.let(::nativeCacheKindMaskVisible)
        ?: faceVisible(batch.representative)
      if (visible && !batch.attached) {
        scene.addEntity(batch.entity)
        batch.attached = true
      } else if (!visible && batch.attached) {
        scene.removeEntity(batch.entity)
        batch.attached = false
      }
    }
    for (group in instanceFaceGroups) {
      val visible = faceVisible(group.representative)
      if (visible && !group.attached) {
        for (entity in group.entities) scene.addEntity(entity)
        group.attached = true
      } else if (!visible && group.attached) {
        for (entity in group.entities) scene.removeEntity(entity)
        group.attached = false
      }
    }
    // Normal borders are chunked by category/level/spatial tile. Selection
    // feedback remains in NativeSelectionOverlay, so one border batch can
    // safely represent many BIM elements without losing per-object picking.
    for (batch in edgeBatches) {
      val visible = edgeVisible(batch.key)
      if (visible && !batch.attached) {
        scene.addEntity(batch.entity)
        batch.attached = true
      } else if (!visible && batch.attached) {
        scene.removeEntity(batch.entity)
        batch.attached = false
      }
    }
    gridBatch?.let { batch ->
      val visible = projectionMode == "isometric" && displayStyle != "solid"
      if (visible && !batch.attached) {
        scene.addEntity(batch.entity)
        batch.attached = true
      } else if (!visible && batch.attached) {
        scene.removeEntity(batch.entity)
        batch.attached = false
      }
    }
    staticShadowBatch?.let { batch ->
      val visible = staticShadowVisible()
      if (visible && !batch.attached) {
        scene.addEntity(batch.entity)
        batch.attached = true
      } else if (!visible && batch.attached) {
        scene.removeEntity(batch.entity)
        batch.attached = false
      }
    }
    groundReceiver?.let { receiver ->
      val visible = realShadowVisible()
      if (visible && !receiver.attached) {
        scene.addEntity(receiver.entity)
        receiver.attached = true
      } else if (!visible && receiver.attached) {
        scene.removeEntity(receiver.entity)
        receiver.attached = false
      }
    }
    requestRender()
  }

  private fun refreshTintState() {
    for (entry in renderables.values) {
      val selected = entry.objectData.elementId != null && selectedElementIds.contains(entry.objectData.elementId)
      val active = entry.objectData.elementId != null && entry.objectData.elementId == selectedElementId
      val highlighted = entry.objectData.elementId != null && entry.objectData.elementId == highlightedElementId
      val isWindow = normalizeKind(entry.objectData.kind) == "window"
      // Keep the requested architectural colors in both Shaded and Solid.
      // Windows use alpha 0.30, which is 70% transparent.
      val solidColor = displayBaseColor(entry.objectData)
      val color = when {
        active -> floatArrayOf(0.08f, 0.28f, 0.82f, if (isWindow) 0.30f else 1f)
        selected -> floatArrayOf(0.18f, 0.45f, 0.95f, if (isWindow) 0.30f else 1f)
        highlighted -> floatArrayOf(0.92f, 0.34f, 0.16f, if (isWindow) 0.30f else 1f)
        else -> solidColor
      }
      applyDisplayStyle(entry.materialInstance)
      entry.materialInstance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        color[0],
        color[1],
        color[2],
        color[3],
      )
    }
    for (group in instanceFaceGroups) {
      val color = displayBaseColor(group.representative)
      applyDisplayStyle(group.materialInstance)
      group.materialInstance.setParameter(
        "baseColor", Colors.RgbaType.LINEAR,
        color[0], color[1], color[2], color[3],
      )
    }
    for (batch in faceBatches) {
      val color = displayBaseColor(batch.representative)
      applyDisplayStyle(batch.materialInstance)
      batch.materialInstance.setParameter(
        "baseColor", Colors.RgbaType.LINEAR,
        color[0], color[1], color[2], color[3],
      )
    }
    for (batch in edgeBatches) {
      applyDisplayStyle(batch.materialInstance)
      val edgeColor = viewportEdgeColor()
      batch.materialInstance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        edgeColor[0], edgeColor[1], edgeColor[2], edgeColor[3],
      )
    }
    gridBatch?.materialInstance?.let { instance ->
      val gridColor = viewportGridColor()
      instance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        gridColor[0], gridColor[1], gridColor[2], gridColor[3],
      )
    }
    groundReceiver?.materialInstance?.let { instance ->
      val groundColor = viewportGroundColor()
      instance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        groundColor[0], groundColor[1], groundColor[2], groundColor[3],
      )
    }
    requestRender()
  }

  private fun destroyRenderables() {
    val engine = engine ?: run {
      renderables.clear()
      faceBatches.clear()
      instanceFaceGroups.clear()
      edgeBatches.clear()
      gridBatch = null
      attachedEntities.clear()
      return
    }
    val scene = scene
    destroyFaceBatches(engine, scene)
    destroyInstanceFaceGroups(engine, scene)
    destroyEdgeBatches(engine, scene)
    destroyGridBatch(engine, scene)
    destroyGroundReceiver(engine, scene)
    destroyStaticShadowBatch(engine, scene)
    for (entry in renderables.values) {
      if (entry.attached) {
        scene?.removeEntity(entry.entity)
      }
      engine.destroyEntity(entry.entity)
      engine.destroyMaterialInstance(entry.materialInstance)
      engine.destroyVertexBuffer(entry.vertexBuffer)
      engine.destroyIndexBuffer(entry.indexBuffer)
      EntityManager.get().destroy(entry.entity)
    }
    renderables.clear()
    attachedEntities.clear()
  }

  private fun destroyFaceBatches(engine: Engine, scene: Scene?) {
    for (batch in faceBatches) {
      if (batch.attached) scene?.removeEntity(batch.entity)
      engine.destroyEntity(batch.entity)
      engine.destroyMaterialInstance(batch.materialInstance)
      engine.destroyVertexBuffer(batch.vertexBuffer)
      engine.destroyIndexBuffer(batch.indexBuffer)
      EntityManager.get().destroy(batch.entity)
    }
    faceBatches.clear()
  }

  private fun destroyInstanceFaceGroups(engine: Engine, scene: Scene?) {
    for (group in instanceFaceGroups) {
      for (entity in group.entities) {
        if (group.attached) scene?.removeEntity(entity)
        engine.destroyEntity(entity)
        EntityManager.get().destroy(entity)
      }
      engine.destroyMaterialInstance(group.materialInstance)
      engine.destroyVertexBuffer(group.vertexBuffer)
      engine.destroyIndexBuffer(group.indexBuffer)
    }
    instanceFaceGroups.clear()
  }

  private fun destroyEdgeBatches(engine: Engine, scene: Scene?) {
    for (batch in edgeBatches) {
      if (batch.attached) scene?.removeEntity(batch.entity)
      engine.destroyEntity(batch.entity)
      engine.destroyMaterialInstance(batch.materialInstance)
      engine.destroyVertexBuffer(batch.vertexBuffer)
      engine.destroyIndexBuffer(batch.indexBuffer)
      EntityManager.get().destroy(batch.entity)
    }
    edgeBatches.clear()
  }

  private fun destroyStaticShadowBatch(engine: Engine, scene: Scene?) {
    val batch = staticShadowBatch ?: return
    scene?.removeEntity(batch.entity)
    engine.destroyEntity(batch.entity)
    engine.destroyMaterialInstance(batch.materialInstance)
    engine.destroyVertexBuffer(batch.vertexBuffer)
    engine.destroyIndexBuffer(batch.indexBuffer)
    EntityManager.get().destroy(batch.entity)
    staticShadowBatch = null
  }

  private fun destroyGroundReceiver(engine: Engine, scene: Scene?) {
    val receiver = groundReceiver ?: return
    Log.i(TAG, "Destroying real shadow receiver entity=${receiver.entity}")
    scene?.removeEntity(receiver.entity)
    engine.destroyEntity(receiver.entity)
    engine.destroyMaterialInstance(receiver.materialInstance)
    engine.destroyVertexBuffer(receiver.vertexBuffer)
    engine.destroyIndexBuffer(receiver.indexBuffer)
    EntityManager.get().destroy(receiver.entity)
    groundReceiver = null
  }

  private fun updateMetrics() {
    val entries = renderables.values.toList()
    val allBounds = entries.map { it.bounds } + faceBatches.map { it.bounds } + instanceFaceGroups.map { it.bounds }
    val uploadedBounds = if (allBounds.isEmpty()) {
      SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
    } else {
      allBounds.reduce(::unionBounds)
    }
    // A progressive cache renderer may have only its nearest tiles resident.
    // Camera fitting and section/elevation extents must nevertheless describe
    // the complete immutable model, otherwise every background upload shifts
    // the user’s camera target.  The counters below intentionally remain the
    // full cache totals as well: they describe the opened BIM asset, not a
    // transient GPU upload slice.
    val cache = nativeBimCache
    val bounds = nativeCacheFullBounds ?: uploadedBounds
    sceneMetrics = FilamentSceneMetrics(
      bounds = bounds,
      objectCount = cache?.primitives?.size
        ?: (entries.size + faceBatches.sumOf { it.objectCount } + instanceFaceGroups.sumOf { it.objectCount }),
      vertexCount = cache?.chunks?.sumOf { it.positions.capacity() / 12 }
        ?: (entries.sumOf { it.vertexBuffer.vertexCount } + faceBatches.sumOf { it.vertexCount } +
          instanceFaceGroups.sumOf { it.vertexCount * it.objectCount }),
      indexCount = cache?.chunks?.sumOf { it.indices.capacity() }
        ?: (entries.sumOf { it.indexBuffer.indexCount } + faceBatches.sumOf { it.indexCount } +
          instanceFaceGroups.sumOf { it.indexCount * it.objectCount }),
      edgeBatchCount = edgeBatches.size,
      edgeVertexCount = edgeBatches.sumOf { it.vertexCount },
      edgeIndexCount = edgeBatches.sumOf { it.indexCount },
      instanceGroupCount = instanceFaceGroups.size,
      instancedObjectCount = instanceFaceGroups.sumOf { it.objectCount },
      sharedFaceVertexCount = instanceFaceGroups.sumOf { it.vertexCount },
    )
    // `fitCamera` initializes a cache scene from its full bounds.  Never
    // overwrite a user pan while later cache chunks become resident.
    if (cache == null || nativeCacheFullBounds == null) {
      val centerX = (bounds.min.x + bounds.max.x) * 0.5
      val centerY = (bounds.min.y + bounds.max.y) * 0.5
      val centerZ = (bounds.min.z + bounds.max.z) * 0.5
      orbitCenter = ScenePoint(centerX, centerY, centerZ)
    }
  }

  private fun updateStatus(customMessage: String? = null) {
    val scene = currentScene
    val objectCount = sceneMetrics.objectCount
    val triangleCount = sceneMetrics.indexCount / 3
    val selectedLabel = selectedElementId?.let { "selected=$it" } ?: "selected=none"
    val highlightLabel = highlightedElementId?.let { "highlighted=$it" } ?: "highlighted=none"
    val status = customMessage ?: buildString {
      append(if (scene != null) "Loaded" else "Idle")
      append(" · ")
      append(objectCount)
      append(" objects · ")
      append(sceneMetrics.vertexCount)
      append(" vertices · ")
      append(triangleCount)
      append(" triangles · ")
      append(selectedLabel)
      append(" · ")
      append(highlightLabel)
      if (surfaceReady) {
        append(" · CPU ")
        append(cpuPercent.format(0))
        append("% · ")
        append(framesPerSecond.format(0))
        append(" fps · ")
        append(residentMemoryMb.format(0))
        append(" MB · ")
        append(nativeThreadCount)
        append(" threads/")
        append(Runtime.getRuntime().availableProcessors())
        append(" cores")
      }
    }
    statusMessage = status
    statusView.text = status
  }

  fun diagnostics(): Map<String, Any> = mapOf(
    "status" to statusMessage,
    "inputObjects" to (currentScene?.objects?.size ?: 0),
    "renderables" to sceneMetrics.objectCount,
    "nativeCacheChunks" to (nativeBimCache?.chunks?.size ?: 0),
    "nativeCacheResidentChunks" to nativeCacheResidentChunks.size,
    "nativeCachePendingChunks" to nativeCachePendingChunks.size,
    "faceBatches" to faceBatches.size,
    "instanceGroups" to sceneMetrics.instanceGroupCount,
    "instancedObjects" to sceneMetrics.instancedObjectCount,
    "sharedFaceVertices" to sceneMetrics.sharedFaceVertexCount,
    "vertices" to sceneMetrics.vertexCount,
    "indices" to sceneMetrics.indexCount,
    "edgeBatches" to sceneMetrics.edgeBatchCount,
    "edgeVertices" to sceneMetrics.edgeVertexCount,
    "edgeIndices" to sceneMetrics.edgeIndexCount,
    "estimatedDrawCalls" to (renderables.size + faceBatches.size + instanceFaceGroups.size + edgeBatches.size),
    "automaticInstancing" to (engine?.isAutomaticInstancingEnabled ?: false),
    "frustumCulling" to (filamentView?.isFrustumCullingEnabled ?: false),
    "edgeCacheEntries" to edgeGeometryCache.size,
    "materialReady" to (material != null),
    "surfaceReady" to surfaceReady,
    "swapChainReady" to (swapChain != null),
    "renderedFrames" to renderedFrameCount,
    "cpuPercent" to cpuPercent,
    "fps" to framesPerSecond,
    "residentMemoryMb" to residentMemoryMb,
    "threadCount" to nativeThreadCount,
    "cpuCores" to Runtime.getRuntime().availableProcessors(),
  )

  private fun sampleTelemetry() {
    val nowMs = SystemClock.elapsedRealtime()
    if (telemetrySampleMs == 0L) {
      telemetrySampleMs = nowMs
      telemetryCpuMs = Process.getElapsedCpuTime()
      telemetryFrameCount = renderedFrameCount
      return
    }
    val elapsedMs = nowMs - telemetrySampleMs
    if (elapsedMs < 1000L) return
    val processCpuMs = Process.getElapsedCpuTime()
    cpuPercent = ((processCpuMs - telemetryCpuMs).toDouble() / elapsedMs.toDouble() * 100.0).coerceAtLeast(0.0)
    framesPerSecond = (renderedFrameCount - telemetryFrameCount).toDouble() * 1000.0 / elapsedMs.toDouble()
    residentMemoryMb = (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()).toDouble() / (1024.0 * 1024.0)
    nativeThreadCount = java.io.File("/proc/self/task").list()?.size ?: Thread.activeCount()
    telemetrySampleMs = nowMs
    telemetryCpuMs = processCpuMs
    telemetryFrameCount = renderedFrameCount
    updateStatus()
  }

  private fun scheduleFrame() {
    if (!framePosted) {
      framePosted = true
      choreographer.postFrameCallback(this)
    }
  }

  private fun requestRender(interactiveForMs: Long = 0L) {
    renderDirty = true
    if (interactiveForMs > 0L) {
      interactiveUntilMs = max(interactiveUntilMs, SystemClock.uptimeMillis() + interactiveForMs)
      if (realShadowVisible()) {
        filamentView?.setShadowingEnabled(false)
        sectionBoxHandler.removeCallbacks(shadowResume)
        sectionBoxHandler.postDelayed(shadowResume, interactiveForMs + 80L)
      }
    } else if (!touching && realShadowVisible()) {
      sectionBoxHandler.removeCallbacks(shadowResume)
      sectionBoxHandler.postDelayed(shadowResume, 80L)
    }
    if (surfaceReady) scheduleFrame()
  }

  private fun cancelFrame() {
    if (framePosted) {
      choreographer.removeFrameCallback(this)
      framePosted = false
    }
  }

  private fun aspectRatio(): Double {
    val width = max(renderSurface.width, 1)
    val height = max(renderSurface.height, 1)
    return width.toDouble() / height.toDouble()
  }

  private fun pointerFocusX(event: MotionEvent, ignoredIndex: Int = -1): Float {
    var total = 0f
    var count = 0
    for (index in 0 until event.pointerCount) {
      if (index == ignoredIndex) continue
      total += event.getX(index)
      count += 1
    }
    return if (count == 0) event.x else total / count
  }

  private fun pointerFocusY(event: MotionEvent, ignoredIndex: Int = -1): Float {
    var total = 0f
    var count = 0
    for (index in 0 until event.pointerCount) {
      if (index == ignoredIndex) continue
      total += event.getY(index)
      count += 1
    }
    return if (count == 0) event.y else total / count
  }

  private fun Double.format(digits: Int): String = "%.${digits}f".format(this)

  private fun handleTouchEvent(event: MotionEvent): Boolean {
    scaleGestureDetector.onTouchEvent(event)
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        cancelOrbitInertia()
        multiTouching = false
        multiTouchFocusValid = false
        lastOrbitMotionTimeMs = SystemClock.uptimeMillis()
        lastTouchX = event.x
        lastTouchY = event.y
        touchDownX = event.x
        touchDownY = event.y
        touchMoved = false
        touching = true
        requestRender(250L)
        activeSectionHandle = selectionOverlay.hitSectionHandle(event.x, event.y)
        return true
      }
      MotionEvent.ACTION_POINTER_DOWN -> {
        // Keep a native focus baseline for two-finger pan. ScaleGestureDetector
        // is still responsible for pinch distance, but on some tablet builds
        // it does not emit onScale for a pure focus translation.
        cancelOrbitInertia()
        multiTouching = true
        multiTouchFocusX = pointerFocusX(event)
        multiTouchFocusY = pointerFocusY(event)
        multiTouchFocusValid = true
        lastOrbitMotionTimeMs = 0L
        touchMoved = true
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        if (event.pointerCount > 1 || multiTouching || scaleGestureDetector.isInProgress) {
          if (event.pointerCount > 1) {
            val focusX = pointerFocusX(event)
            val focusY = pointerFocusY(event)
            if (!multiTouchFocusValid) {
              multiTouchFocusX = focusX
              multiTouchFocusY = focusY
              multiTouchFocusValid = true
            } else {
              val focusDx = focusX - multiTouchFocusX
              val focusDy = focusY - multiTouchFocusY
              if (focusDx != 0f || focusDy != 0f) {
                if (projectionMode == "isometric") {
                  panOrbitCamera(focusDx, focusDy)
                  updateOrbitCamera()
                  requestRender(250L)
                  invalidate()
                }
              }
              multiTouchFocusX = focusX
              multiTouchFocusY = focusY
            }
          }
          touchMoved = true
          return true
        }
        if (touching) {
          val dx = event.x - lastTouchX
          val dy = event.y - lastTouchY
          val nowMs = SystemClock.uptimeMillis()
          if (projectionMode == "isometric" && activeSectionHandle == null && lastOrbitMotionTimeMs > 0L) {
            val deltaSeconds = ((nowMs - lastOrbitMotionTimeMs).coerceIn(1L, 50L)).toDouble() / 1000.0
            val instantYawVelocity = dx.toDouble() * 0.01 / deltaSeconds
            val instantPitchVelocity = dy.toDouble() * 0.01 / deltaSeconds
            orbitYawVelocity = orbitYawVelocity * 0.65 + instantYawVelocity * 0.35
            orbitPitchVelocity = orbitPitchVelocity * 0.65 + instantPitchVelocity * 0.35
          }
          lastOrbitMotionTimeMs = nowMs
          if (kotlin.math.hypot(event.x - touchDownX, event.y - touchDownY) >
            resources.displayMetrics.density * 8f) {
            touchMoved = true
          }
          lastTouchX = event.x
          lastTouchY = event.y
          val sectionHandle = activeSectionHandle
          if (sectionHandle != null) {
            moveSectionHandle(sectionHandle, selectionOverlay.sectionAxisDelta(sectionHandle, dx, dy))
          } else if (isPlanarProjection()) {
            panPlanarCamera(dx, dy)
          } else {
            orbitYawRadians += dx * 0.01
            orbitPitchRadians = (orbitPitchRadians + dy * 0.01).coerceIn(Math.toRadians(0.1), Math.toRadians(88.0))
          }
          updateOrbitCamera()
          syncVisualOverlay()
          requestRender(250L)
          invalidate()
        }
        return true
      }
      MotionEvent.ACTION_POINTER_UP -> {
        touchMoved = true
        orbitYawVelocity = 0.0
        orbitPitchVelocity = 0.0
        lastOrbitMotionTimeMs = 0L
        val releasedIndex = event.actionIndex
        val remainingCount = event.pointerCount - 1
        if (remainingCount > 1) {
          multiTouchFocusX = pointerFocusX(event, releasedIndex)
          multiTouchFocusY = pointerFocusY(event, releasedIndex)
          multiTouchFocusValid = true
        } else {
          multiTouchFocusValid = false
        }
        val remainingIndex = (0 until event.pointerCount)
          .firstOrNull { index -> index != releasedIndex }
        if (remainingIndex != null) {
          lastTouchX = event.getX(remainingIndex)
          lastTouchY = event.getY(remainingIndex)
          multiTouching = event.pointerCount - 1 > 1
        } else {
          multiTouching = false
        }
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        // Flutter's viewport wrapper forwards a stationary 3D tap through
        // pickNormalized. Keeping selection on that one path prevents the
        // native TextureView and Flutter overlay from racing with different
        // results for the same pointer-up event.
        if (event.actionMasked == MotionEvent.ACTION_UP && touchMoved && activeSectionHandle == null) {
          startOrbitInertia()
        } else {
          cancelOrbitInertia()
        }
        activeSectionHandle = null
        multiTouching = false
        multiTouchFocusValid = false
        lastOrbitMotionTimeMs = 0L
        touching = false
        requestRender()
        return true
      }
      else -> return true
    }
  }

  private fun handleSectionOverlayTouch(event: MotionEvent): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        val handle = selectionOverlay.hitSectionHandle(event.x, event.y) ?: return false
        activeSectionHandle = handle
        lastTouchX = event.x
        lastTouchY = event.y
        parent?.requestDisallowInterceptTouchEvent(true)
        touching = true
        requestRender(250L)
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        val handle = activeSectionHandle ?: return false
        val dx = event.x - lastTouchX
        val dy = event.y - lastTouchY
        lastTouchX = event.x
        lastTouchY = event.y
        moveSectionHandle(handle, selectionOverlay.sectionAxisDelta(handle, dx, dy))
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        if (activeSectionHandle == null) return false
        activeSectionHandle = null
        touching = false
        parent?.requestDisallowInterceptTouchEvent(false)
        requestRender()
        return true
      }
      else -> return activeSectionHandle != null
    }
  }

  private fun moveSectionHandle(handle: String, delta: Double) {
    if (!sectionBoxEnabled || !delta.isFinite()) return
    val minimumSpan = 0.02
    var minPoint = sectionBoxMin
    var maxPoint = sectionBoxMax
    when (handle) {
      "xMin" -> minPoint = minPoint.copy(x = (minPoint.x + delta).coerceAtMost(maxPoint.x - minimumSpan))
      "xMax" -> maxPoint = maxPoint.copy(x = (maxPoint.x + delta).coerceAtLeast(minPoint.x + minimumSpan))
      "yMin" -> minPoint = minPoint.copy(y = (minPoint.y + delta).coerceAtMost(maxPoint.y - minimumSpan))
      "yMax" -> maxPoint = maxPoint.copy(y = (maxPoint.y + delta).coerceAtLeast(minPoint.y + minimumSpan))
      "zMin" -> minPoint = minPoint.copy(z = (minPoint.z + delta).coerceAtMost(maxPoint.z - minimumSpan))
      "zMax" -> maxPoint = maxPoint.copy(z = (maxPoint.z + delta).coerceAtLeast(minPoint.z + minimumSpan))
    }
    // Border, handles and clipping triangles must consume the same bounds.
    // Rebuilding these planes here removes the former one-gesture lag where
    // the wire box moved but geometry still used its initial six planes.
    clipVolume = clipVolume.copy(
      planes = boxClipPlanes(minPoint, maxPoint),
      boxMin = minPoint,
      boxMax = maxPoint,
    )
    val sceneBounds = boundsForPoints(boxCorners(SceneBounds(minPoint, maxPoint)).map(::fromFilamentPoint))
    sectionSceneMin = sceneBounds.min
    sectionSceneMax = sceneBounds.max
    applySectionBoxState()
    selectionOverlay.setSectionBox(true, minPoint, maxPoint)
    sectionBoxHandler.removeCallbacks(sectionBoxRebuild)
    sectionBoxHandler.postDelayed(sectionBoxRebuild, 55L)
    interactiveUntilMs = SystemClock.uptimeMillis() + 500L
    requestRender(500L)
    invalidate()
  }

  private fun pickVisibleObject(x: Float, y: Float) {
    val view = filamentView
    if (view == null) {
      val result = selectionOverlay.pickElementAt(x, y, visibleKinds)
      onObjectTapped(result)
      return
    }
    // The ray is evaluated against Filament's live view/projection matrices,
    // therefore it remains correct after a native orbit. On the connected
    // MIUI tablet View.pick occasionally reported an unrelated renderable
    // after rotation; only use it when the ray has no geometric hit.
    val activeCache = nativeBimCache
    val rayElementId = if (activeCache != null) {
      // The cache owns exact triangle data and a chunk BVH. Using it here
      // avoids projecting every primitive AABB in Kotlin for a large IFC.
      selectionOverlay.liveCameraRay(x, y)?.let { ray ->
        activeCache.pick(ray.origin, ray.direction, visibleKinds)
      }
    } else {
      selectionOverlay.pickByLiveCameraRay(x, y, visibleKinds)
    }
    if (rayElementId != null) {
      onObjectTapped(rayElementId)
      return
    }
    // Native cache picking is exact, but older cache files and a few Android
    // GLES drivers can still reject a valid ray at a chunk boundary.  The
    // overlay keeps lightweight bounds for every primitive, so use it as a
    // deterministic screen-space fallback instead of silently clearing a tap.
    selectionOverlay.pickElementAt(x, y, visibleKinds)?.let {
      onObjectTapped(it)
      return
    }
    // Do not fall back to Filament's asynchronous GPU pick here. On this
    // MIUI device it can return a stale/nearby renderable after an orbit, so
    // tapping empty space kept a wall selected instead of clearing it. The
    // live-camera ray above is the single 3D selection authority; a miss is
    // deliberately reported as null and clears the Flutter Inspector too.
    onObjectTapped(null)
  }

  fun pickNormalized(normalizedX: Double, normalizedY: Double) {
    val width = selectionOverlay.width
    val height = selectionOverlay.height
    if (width <= 1 || height <= 1) return
    val x = (normalizedX.coerceIn(0.0, 1.0) * width).toFloat()
    val y = (normalizedY.coerceIn(0.0, 1.0) * height).toFloat()
    pickVisibleObject(x, y)
  }

  private fun updateOrbitCamera() {
    val camera = camera ?: return
    val center = orbitCenter
    if (projectionMode == "topDown") {
      val eyeY = center.y + max(orbitDistance, topDownZoom * 2.5)
      camera.lookAt(
        center.x,
        eyeY,
        center.z,
        center.x,
        center.y,
        center.z,
        0.0,
        0.0,
        -1.0,
      )
      syncVisualOverlay()
      scheduleNativeBimCacheReprioritization()
      return
    }
    val cosPitch = cos(orbitPitchRadians)
    val eyeX = center.x + orbitDistance * cosPitch * cos(orbitYawRadians)
    val eyeZ = center.z + orbitDistance * cosPitch * sin(orbitYawRadians)
    val eyeY = center.y + orbitDistance * sin(orbitPitchRadians)
    camera.lookAt(
      eyeX,
      eyeY,
      eyeZ,
      center.x,
      center.y,
      center.z,
      0.0,
      1.0,
      0.0,
    )
    syncVisualOverlay()
    scheduleNativeBimCacheReprioritization()
  }

  /// Every non-isometric view is an architectural planar view. A Fit must
  /// preserve that camera direction instead of restoring the 3D default.
  private fun isPlanarProjection(): Boolean = projectionMode != "isometric"

  private fun isElevationProjection(): Boolean =
    projectionMode == "northElevation" || projectionMode == "southElevation" ||
      projectionMode == "eastElevation" || projectionMode == "westElevation"

  private fun resetCameraOrientationForProjection() {
    when (projectionMode) {
      "northElevation" -> {
        orbitYawRadians = Math.PI / 2.0
        orbitPitchRadians = 0.0
      }
      "southElevation" -> {
        orbitYawRadians = -Math.PI / 2.0
        orbitPitchRadians = 0.0
      }
      "eastElevation" -> {
        orbitYawRadians = Math.PI
        orbitPitchRadians = 0.0
      }
      "westElevation" -> {
        orbitYawRadians = 0.0
        orbitPitchRadians = 0.0
      }
      "section" -> {
        val inward = clipVolume.sectionDirection
        if (inward != null) {
          // The camera is on the removed side and looks into the retained
          // half, matching the planar descriptor selected by Flutter.
          orbitYawRadians = kotlin.math.atan2(-inward.z, -inward.x)
          orbitPitchRadians = 0.0
        }
      }
      else -> {
        orbitYawRadians = Math.toRadians(45.0)
        orbitPitchRadians = Math.toRadians(24.0)
      }
    }
  }

  private fun panPlanarCamera(dx: Float, dy: Float) {
    val halfHeight = if (projectionMode == "topDown") topDownZoom else max(orbitDistance * 0.6, 2.0)
    val metersPerPixel = (halfHeight * 2.0) / max(renderSurface.height.toDouble(), 1.0)
    orbitCenter = when (projectionMode) {
      "topDown" -> orbitCenter.copy(
        x = orbitCenter.x - dx * metersPerPixel,
        z = orbitCenter.z + dy * metersPerPixel,
      )
      "northElevation", "southElevation" -> orbitCenter.copy(
        x = orbitCenter.x - dx * metersPerPixel,
        y = orbitCenter.y + dy * metersPerPixel,
      )
      "section" -> orbitCenter.copy(
        x = orbitCenter.x - dx * metersPerPixel,
        y = orbitCenter.y + dy * metersPerPixel,
      )
      "eastElevation", "westElevation" -> orbitCenter.copy(
        z = orbitCenter.z + dx * metersPerPixel,
        y = orbitCenter.y + dy * metersPerPixel,
      )
      else -> orbitCenter
    }
  }

  private fun panOrbitCamera(dx: Float, dy: Float) {
    if (renderSurface.width <= 1 || renderSurface.height <= 1) return
    fun crossVector(first: ScenePoint, second: ScenePoint) = ScenePoint(
      first.y * second.z - first.z * second.y,
      first.z * second.x - first.x * second.z,
      first.x * second.y - first.y * second.x,
    )
    fun normalizeVector(value: ScenePoint): ScenePoint {
      val length = kotlin.math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
        .coerceAtLeast(1.0e-9)
      return ScenePoint(value.x / length, value.y / length, value.z / length)
    }
    val cosPitch = cos(orbitPitchRadians)
    val forward = normalizeVector(
      ScenePoint(
        -cosPitch * kotlin.math.cos(orbitYawRadians),
        -sin(orbitPitchRadians),
        -cosPitch * kotlin.math.sin(orbitYawRadians),
      ),
    )
    val right = normalizeVector(crossVector(forward, ScenePoint(0.0, 1.0, 0.0)))
    val up = normalizeVector(crossVector(right, forward))
    val visibleHalfHeight = if (orbitProjectionStyle == "perspective") {
      orbitDistance * tan(Math.toRadians(45.0) * 0.5)
    } else {
      max(orbitDistance * 0.6, 2.0)
    }
    val metersPerPixel = (visibleHalfHeight * 2.0) / renderSurface.height.toDouble()
    orbitCenter = orbitCenter.copy(
      x = orbitCenter.x - right.x * dx * metersPerPixel + up.x * dy * metersPerPixel,
      y = orbitCenter.y - right.y * dx * metersPerPixel + up.y * dy * metersPerPixel,
      z = orbitCenter.z - right.z * dx * metersPerPixel + up.z * dy * metersPerPixel,
    )
  }

  private fun syncVisualOverlay() {
    selectionOverlay.setVisualCamera(
      center = orbitCenter,
      yawRadians = orbitYawRadians,
      pitchRadians = orbitPitchRadians,
      distance = orbitDistance,
      topDownZoom = topDownZoom,
      topDown = projectionMode == "topDown",
      perspective = orbitProjectionStyle == "perspective",
      showNativeLevels = !isElevationProjection() && projectionMode != "section",
    )
  }

  private fun configureCameraProjection() {
    val camera = camera ?: return
    val aspect = aspectRatio()
    val bounds = sceneMetrics.bounds
    val sceneSpan = max(
      bounds.max.x - bounds.min.x,
      max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
    )
    // Derive the clip range from the actual camera-facing scene depths. The
    // old fixed 2 mm..160 m range wasted almost all depth precision on empty
    // space; edge prisms could then alternate with the coplanar model faces
    // while orbiting or pinching. A small safety margin keeps the model and
    // the 50 m navigation grid inside the frustum without reopening that
    // precision gap in elevation/section orthographic views.
    val (near, sceneFar) = cameraDepthRange(bounds, sceneSpan)
    val far = if (projectionMode == "isometric") {
      max(sceneFar, orbitDistance + max(sceneSpan, 50.0) * 1.15)
    } else {
      sceneFar
    }
    if (projectionMode != "isometric" || orbitProjectionStyle == "orthographic") {
      val halfHeight = if (projectionMode == "topDown") topDownZoom else max(orbitDistance * 0.6, 2.0)
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
      return
    }

    camera.setProjection(45.0, aspect, near, far, Camera.Fov.VERTICAL)
  }

  private fun cameraDepthRange(bounds: SceneBounds, sceneSpan: Double): Pair<Double, Double> {
    val center = orbitCenter
    val eye = if (projectionMode == "topDown") {
      val eyeY = center.y + max(orbitDistance, topDownZoom * 2.5)
      ScenePoint(center.x, eyeY, center.z)
    } else {
      val cosPitch = cos(orbitPitchRadians)
      ScenePoint(
        center.x + orbitDistance * cosPitch * cos(orbitYawRadians),
        center.y + orbitDistance * sin(orbitPitchRadians),
        center.z + orbitDistance * cosPitch * sin(orbitYawRadians),
      )
    }
    val forward = normalizeScenePoint(ScenePoint(center.x - eye.x, center.y - eye.y, center.z - eye.z))
    val depths = boxCorners(bounds).map { point ->
      dotScenePoints(ScenePoint(point.x - eye.x, point.y - eye.y, point.z - eye.z), forward)
    }
    // Keep the near plane out of the millimetre range for building-scale
    // scenes.  A near plane of 0.01 m combined with a distant orbit consumes
    // almost all mobile depth precision and makes coplanar IFC triangles
    // sparkle during a pinch.  The margin is still proportional, so small
    // architectural details remain selectable and visible.
    val safetyMargin = max(sceneSpan * 0.04, 0.10)
    val near = max(0.05, (depths.minOrNull() ?: 0.0) - safetyMargin)
    val far = max(near + max(sceneSpan * 1.25, 4.0), (depths.maxOrNull() ?: 1.0) + safetyMargin)
    return near to far
  }

  private fun dotScenePoints(first: ScenePoint, second: ScenePoint): Double =
    first.x * second.x + first.y * second.y + first.z * second.z

  private fun normalizeScenePoint(value: ScenePoint): ScenePoint {
    val length = kotlin.math.sqrt(dotScenePoints(value, value))
    return if (length <= 1.0e-9) ScenePoint(0.0, 0.0, 0.0) else {
      ScenePoint(value.x / length, value.y / length, value.z / length)
    }
  }

  private fun minimumOrbitDistance(): Double {
    val bounds = sceneMetrics.bounds
    val span = max(
      bounds.max.x - bounds.min.x,
      max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
    )
    // Keep an orbit camera outside dense multi-storey geometry. This avoids
    // near-plane crossings and depth flicker while direct selection remains
    // available for close inspection.
    return max(span * 0.50, 1.75)
  }

  private fun minimumPlanarOrbitDistance(): Double = 0.5

  private fun boxCorners(bounds: SceneBounds): List<ScenePoint> {
    return listOf(
      ScenePoint(bounds.min.x, bounds.min.y, bounds.min.z),
      ScenePoint(bounds.max.x, bounds.min.y, bounds.min.z),
      ScenePoint(bounds.max.x, bounds.max.y, bounds.min.z),
      ScenePoint(bounds.min.x, bounds.max.y, bounds.min.z),
      ScenePoint(bounds.min.x, bounds.min.y, bounds.max.z),
      ScenePoint(bounds.max.x, bounds.min.y, bounds.max.z),
      ScenePoint(bounds.max.x, bounds.max.y, bounds.max.z),
      ScenePoint(bounds.min.x, bounds.max.y, bounds.max.z),
    )
  }

  private fun transformBounds(bounds: SceneBounds): SceneBounds {
    return boundsForPoints(boxCorners(bounds).map(::toFilamentPoint))
  }

  private fun filamentBox(bounds: SceneBounds): Box {
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerY = (bounds.min.y + bounds.max.y) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    val halfX = max((bounds.max.x - bounds.min.x) * 0.5, 0.001)
    val halfY = max((bounds.max.y - bounds.min.y) * 0.5, 0.001)
    val halfZ = max((bounds.max.z - bounds.min.z) * 0.5, 0.001)
    return Box(
      centerX.toFloat(), centerY.toFloat(), centerZ.toFloat(),
      halfX.toFloat(), halfY.toFloat(), halfZ.toFloat(),
    )
  }

  private fun toFilamentPoint(point: ScenePoint): ScenePoint {
    return ScenePoint(point.x, point.z, -point.y)
  }

  private fun fromFilamentPoint(point: ScenePoint): ScenePoint {
    return ScenePoint(point.x, -point.z, point.y)
  }

  private fun boundsForPoints(points: List<ScenePoint>): SceneBounds {
    if (points.isEmpty()) {
      return SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
    }
    var minX = points.first().x
    var minY = points.first().y
    var minZ = points.first().z
    var maxX = points.first().x
    var maxY = points.first().y
    var maxZ = points.first().z
    for (point in points.drop(1)) {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      minZ = min(minZ, point.z)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
      maxZ = max(maxZ, point.z)
    }
    return SceneBounds(
      min = ScenePoint(minX, minY, minZ),
      max = ScenePoint(maxX, maxY, maxZ),
    )
  }

  private fun kindColor(kind: String): FloatArray {
    return when (kind) {
      // Muted architectural palette: the categories remain distinguishable
      // without saturated blue/purple/green faces overwhelming the model.
      "wall" -> floatArrayOf(0.50f, 0.53f, 0.57f, 1f)
      "door" -> floatArrayOf(0.30f, 0.18f, 0.10f, 1f)
      "window" -> floatArrayOf(0.16f, 0.40f, 0.54f, 0.38f)
      "slab" -> floatArrayOf(0.44f, 0.48f, 0.53f, 1f)
      "floor" -> floatArrayOf(0.46f, 0.32f, 0.20f, 1f)
      "ceiling" -> floatArrayOf(0.68f, 0.68f, 0.64f, 1f)
      "roof" -> floatArrayOf(0.28f, 0.14f, 0.11f, 1f)
      "column" -> floatArrayOf(0.40f, 0.44f, 0.49f, 1f)
      "beam" -> floatArrayOf(0.32f, 0.37f, 0.42f, 1f)
      "stair" -> floatArrayOf(0.46f, 0.48f, 0.53f, 1f)
      "room" -> floatArrayOf(0.26f, 0.43f, 0.35f, 0.18f)
      "proxy" -> floatArrayOf(0.42f, 0.32f, 0.20f, 1f)
      else -> floatArrayOf(0.40f, 0.45f, 0.50f, 1f)
    }
  }

  private fun toVisualObject(objectData: SceneObject): NativeVisualObject {
    // Selection/edge overlays do not need the full render mesh. On large IFC
    // scenes, retaining a tiny deterministic sample here avoids rebuilding a
    // second triangle soup on the UI thread while Filament keeps its separate
    // runtime LOD geometry for rendering.
    val overlayBudget = importedMeshTriangleBudget(objectData)
    // Legacy IFC detail proxies are intentionally represented by their bounds
    // at city/campus scale. This keeps their newly restored outline path cheap;
    // FBX/generic mesh objects still use the sampled source topology above.
    val largeIfcProxy = normalizeKind(objectData.kind) == "proxy" &&
      !isImportedMeshObject(objectData) &&
      (currentScene?.objects?.size ?: 0) >= 256
    val meshGeometry = if (largeIfcProxy) null else meshGeometryFor(objectData, overlayBudget)
    val sourcePoints = meshGeometry?.first ?: boxCorners(objectData.bounds).map(::toFilamentPoint)
    val sourceTriangles = meshGeometry?.second ?: run {
      listOf(
        intArrayOf(0, 1, 2), intArrayOf(0, 2, 3), intArrayOf(4, 6, 5), intArrayOf(4, 7, 6),
        intArrayOf(0, 4, 5), intArrayOf(0, 5, 1), intArrayOf(1, 5, 6), intArrayOf(1, 6, 2),
        intArrayOf(2, 6, 7), intArrayOf(2, 7, 4), intArrayOf(3, 7, 4), intArrayOf(3, 4, 0),
      )
    }
    var points = sourcePoints
    val triangles = sourceTriangles
    var featureEdges = meshFeatureEdges(
      sourcePoints,
      sourceTriangles,
      creaseDotThreshold = if (normalizeKind(objectData.kind) == "roof") 0.995 else 0.90,
    )
    // Some FBX exporters mark every surface smooth, leaving no boundary or
    // crease in the geometric topology even though the model is valid. Keep
    // a lightweight envelope outline as a readable fallback instead of
    // making the imported model look like a flat, edge-less solid.
    if (isImportedMeshObject(objectData) && featureEdges.isEmpty() && meshGeometry != null) {
      val envelopePoints = boxCorners(objectData.bounds).map(::toFilamentPoint)
      val offset = points.size
      points = points + envelopePoints
      val envelopeEdges = listOf(
        0 to 1, 1 to 2, 2 to 3, 3 to 0,
        4 to 5, 5 to 6, 6 to 7, 7 to 4,
        0 to 4, 1 to 5, 2 to 6, 3 to 7,
      ).map { (first, second) ->
        NativeVisualEdge(
          first = offset + first,
          second = offset + second,
          triangleIndices = intArrayOf(),
          sharp = true,
        )
      }
      featureEdges = envelopeEdges
    }
    val overlayEdges = if (isImportedMeshObject(objectData)) {
      // The Filament edge prism remains the primary path. This bounded copy
      // is only for external meshes whose internal edges are hidden by the
      // face depth pass on some mobile GPUs. It keeps the overlay cheap even
      // when an FBX contains a large amount of tessellation.
      (featureEdges.filter { it.sharp } + featureEdges.filterNot { it.sharp })
        .take(IMPORTED_MESH_EDGE_SEGMENT_LIMIT_SMALL_SCENE)
    } else {
      featureEdges
    }
    return NativeVisualObject(
      elementId = objectData.elementId,
      kind = normalizeKind(objectData.kind),
      selectable = objectData.selectable,
      metadata = buildMap {
        putAll(objectData.metadata)
        if (isImportedMeshObject(objectData)) put("external_mesh", "true")
      },
      points = points,
      triangles = triangles,
      featureEdges = overlayEdges,
    )
  }

  private fun meshFeatureEdges(
    points: List<ScenePoint>,
    triangles: List<IntArray>,
    creaseDotThreshold: Double = 0.90,
    includeBoundaryEdges: Boolean = true,
  ): List<NativeVisualEdge> {
    data class PointKey(val x: Long, val y: Long, val z: Long)
    data class Edge(val first: Int, val second: Int)
    data class EdgeUse(
      val normal: DoubleArray,
      val firstRaw: Int,
      val secondRaw: Int,
      val triangleIndex: Int,
    )
    // Engine meshes intentionally duplicate vertices across face boundaries
    // for simple, robust generation. For visual topology those duplicates are
    // one vertex; without this weld every triangle diagonal becomes an edge
    // and Solid degenerates into Wire.
    fun key(point: ScenePoint) = PointKey(
      kotlin.math.round(point.x * 100000.0).toLong(),
      kotlin.math.round(point.y * 100000.0).toLong(),
      kotlin.math.round(point.z * 100000.0).toLong(),
    )
    val canonicalByPoint = linkedMapOf<PointKey, Int>()
    val canonicalIndices = IntArray(points.size)
    points.forEachIndexed { index, point ->
      canonicalIndices[index] = canonicalByPoint.getOrPut(key(point)) { canonicalByPoint.size }
    }
    val usesByEdge = linkedMapOf<Edge, MutableList<EdgeUse>>()
    for ((triangleIndex, triangle) in triangles.withIndex()) {
      val normal = triangleNormal(points[triangle[0]], points[triangle[1]], points[triangle[2]])
      for ((first, second) in arrayOf(triangle[0] to triangle[1], triangle[1] to triangle[2], triangle[2] to triangle[0])) {
        val canonicalFirst = canonicalIndices[first]
        val canonicalSecond = canonicalIndices[second]
        if (canonicalFirst == canonicalSecond) continue
        val edge = if (canonicalFirst < canonicalSecond) Edge(canonicalFirst, canonicalSecond) else Edge(canonicalSecond, canonicalFirst)
        usesByEdge.getOrPut(edge) { mutableListOf() }.add(EdgeUse(normal, first, second, triangleIndex))
      }
    }
    return usesByEdge.values.mapNotNull { uses ->
      // A crease must be visually meaningful. This suppresses triangulation
      // seams and tiny tessellation changes while retaining real BIM corners.
      val feature = (includeBoundaryEdges && uses.size == 1) || uses.zipWithNext().any { (first, second) ->
        normalDot(first.normal, second.normal) < creaseDotThreshold
      }
      if (!feature) return@mapNotNull null
      val sharp = (includeBoundaryEdges && uses.size == 1) || uses.zipWithNext().any { (first, second) ->
        normalDot(first.normal, second.normal) < 0.35
      }
      NativeVisualEdge(
        first = uses.first().firstRaw,
        second = uses.first().secondRaw,
        triangleIndices = uses.map { it.triangleIndex }.distinct().toIntArray(),
        sharp = sharp,
      )
    }
  }

  private fun triangleNormal(a: ScenePoint, b: ScenePoint, c: ScenePoint): DoubleArray {
    val abX = b.x - a.x; val abY = b.y - a.y; val abZ = b.z - a.z
    val acX = c.x - a.x; val acY = c.y - a.y; val acZ = c.z - a.z
    val x = abY * acZ - abZ * acY
    val y = abZ * acX - abX * acZ
    val z = abX * acY - abY * acX
    val length = kotlin.math.sqrt(x * x + y * y + z * z)
    return if (length <= 1e-9) doubleArrayOf(0.0, 0.0, 0.0) else doubleArrayOf(x / length, y / length, z / length)
  }

  private fun normalDot(first: DoubleArray, second: DoubleArray): Double =
    first[0] * second[0] + first[1] * second[1] + first[2] * second[2]

  private data class GeometryData(
    val vertexCount: Int,
    val indexCount: Int,
    val vertexData: ByteBuffer,
    val indexData: IntBuffer,
    val bounds: SceneBounds,
    val points: List<ScenePoint> = emptyList(),
    val triangles: List<IntArray> = emptyList(),
  )
}

private class NativeSelectionOverlay(context: Context) : android.view.View(context) {
  private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    strokeWidth = context.resources.displayMetrics.density * 2f
  }
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.FILL
  }
  private var rectangle: RectF? = null
  private var crossing = false
  private var objects = emptyList<NativeVisualObject>()
  private var allObjects = emptyList<NativeVisualObject>()
  private var selectedIds = emptySet<Long>()
  private var activeId: Long? = null
  private var visibleKinds = emptySet<String>()
  private var levels = emptyList<Pair<String, Double>>()
  private val openingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.rgb(17, 24, 39)
    strokeWidth = context.resources.displayMetrics.density * 1.05f
    strokeCap = Paint.Cap.SQUARE
    strokeJoin = Paint.Join.MITER
  }
  private val windowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.rgb(17, 24, 39)
    strokeWidth = context.resources.displayMetrics.density * 1.35f
    strokeCap = Paint.Cap.SQUARE
    strokeJoin = Paint.Join.MITER
  }
  private val openingCutPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.FILL
    color = Color.rgb(244, 247, 245)
  }
  private var planOpeningSpecs = emptyList<PlanOpeningSpec>()
  private var sceneBounds = SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
  private var center = ScenePoint(0.0, 0.0, 0.0)
  private var yawRadians = 0.0
  private var pitchRadians = 0.0
  private var distance = 12.0
  private var topDownZoom = 8.0
  private var topDown = true
  private var perspective = false
  private var showNativeLevels = true
  private var wireframe = false
  private var viewportTheme = "light"
  // Filament owns the normal architectural edge batches. Painting the same
  // sampled edges again in the Android overlay made every 2D pan/zoom walk
  // hundreds of projected vertices (and, in elevation/section, recompute
  // face-facing tests) on the UI thread. Keep this overlay path reserved for
  // wireframe and explicit selection feedback.
  private var showObjectEdges = false
  private var hasExternalMeshEdges = false
  private var sectionBoxEnabled = false
  private var sectionBoxMin = ScenePoint(0.0, 0.0, 0.0)
  private var sectionBoxMax = ScenePoint(0.0, 0.0, 0.0)
  private val sectionFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.FILL
    color = Color.argb(5, 0, 137, 123)
  }
  private val sectionStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.rgb(0, 121, 107)
    strokeWidth = context.resources.displayMetrics.density * 1.6f
  }
  private val sectionHandle = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.FILL
    color = Color.rgb(0, 121, 107)
  }
  private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.argb(155, 24, 39, 52)
    strokeWidth = context.resources.displayMetrics.density * 0.85f
  }
  private val externalOutline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.argb(232, 28, 45, 55)
    strokeWidth = context.resources.displayMetrics.density * 1.35f
    strokeCap = Paint.Cap.SQUARE
    strokeJoin = Paint.Join.MITER
  }
  private val selectedOutline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.rgb(37, 99, 235)
    strokeWidth = context.resources.displayMetrics.density * 2.8f
  }
  private val levelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.argb(195, 8, 119, 139)
    strokeWidth = context.resources.displayMetrics.density * 1.2f
  }
  private val levelText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.rgb(8, 119, 139)
    textSize = context.resources.displayMetrics.scaledDensity * 11f
    typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
  }

  init {
    isClickable = false
  }

  fun setRectangle(value: RectF, isCrossing: Boolean) {
    rectangle = RectF(value)
    crossing = isCrossing
    invalidate()
  }

  fun clear() {
    if (rectangle == null) return
    rectangle = null
    invalidate()
  }

  fun setSectionBox(enabled: Boolean, minPoint: ScenePoint, maxPoint: ScenePoint) {
    sectionBoxEnabled = enabled
    sectionBoxMin = minPoint
    sectionBoxMax = maxPoint
    invalidate()
  }

  fun hitSectionHandle(x: Float, y: Float): String? {
    if (!sectionBoxEnabled || topDown) return null
    val touch = PointF(x, y)
    val radius = resources.displayMetrics.density * 48f
    return sectionFaceCenters().mapNotNull { (name, point) ->
      val projected = project(point) ?: return@mapNotNull null
      name to kotlin.math.hypot((projected.x - touch.x).toDouble(), (projected.y - touch.y).toDouble())
    }.filter { it.second <= radius }.minByOrNull { it.second }?.first
  }

  fun sectionAxisDelta(handle: String, dx: Float, dy: Float): Double {
    val centerPoint = sectionFaceCenters()[handle] ?: return 0.0
    val axis = when (handle.firstOrNull()) {
      'x' -> ScenePoint(1.0, 0.0, 0.0)
      'y' -> ScenePoint(0.0, 1.0, 0.0)
      else -> ScenePoint(0.0, 0.0, 1.0)
    }
    val first = project(centerPoint) ?: return 0.0
    val second = project(ScenePoint(centerPoint.x + axis.x, centerPoint.y + axis.y, centerPoint.z + axis.z)) ?: return 0.0
    val sx = (second.x - first.x).toDouble()
    val sy = (second.y - first.y).toDouble()
    val lengthSquared = sx * sx + sy * sy
    if (lengthSquared < 1.0e-6) return 0.0
    return (dx * sx + dy * sy) / lengthSquared
  }

  private fun sectionFaceCenters(): Map<String, ScenePoint> {
    val midX = (sectionBoxMin.x + sectionBoxMax.x) * 0.5
    val midY = (sectionBoxMin.y + sectionBoxMax.y) * 0.5
    val midZ = (sectionBoxMin.z + sectionBoxMax.z) * 0.5
    return mapOf(
      "xMin" to ScenePoint(sectionBoxMin.x, midY, midZ),
      "xMax" to ScenePoint(sectionBoxMax.x, midY, midZ),
      "yMin" to ScenePoint(midX, sectionBoxMin.y, midZ),
      "yMax" to ScenePoint(midX, sectionBoxMax.y, midZ),
      "zMin" to ScenePoint(midX, midY, sectionBoxMin.z),
      "zMax" to ScenePoint(midX, midY, sectionBoxMax.z),
    )
  }

  fun setVisualScene(
    value: List<NativeVisualObject>,
    levelValues: List<Pair<String, Double>>,
    bounds: SceneBounds,
  ) {
    // Keep coverage across every building at city scale. Sampling avoids line
    // soup but never makes a campus fall back to an unannotated old view.
    val stride = max(1, (value.size + 649) / 650)
    hasExternalMeshEdges = value.any {
      it.metadata["external_mesh"] == "true" && it.metadata["native_cache"] != "true"
    }
    allObjects = value
    val sampledObjects = value.filterIndexed { index, _ -> index % stride == 0 }
    val externalObjects = value.filter { it.metadata["external_mesh"] == "true" }
    // A large scene may be sampled for the lightweight Canvas overlay. Never
    // let that sampling omit the imported mesh that the user is inspecting.
    objects = (sampledObjects + externalObjects).distinctBy { it.elementId ?: it.hashCode().toLong() }
    planOpeningSpecs = buildPlanOpeningSpecs(value)
    levels = levelValues
    sceneBounds = bounds
    invalidate()
  }

  /// Native navigation changes the Filament camera without a Flutter frame.
  /// Pick in this same projection space so a single tap always targets the
  /// visible object rather than a stale fallback-camera approximation.
  fun pickElementAt(x: Float, y: Float, visibleKinds: Set<String>): Long? {
    var bestId: Long? = null
    var bestScore = Double.POSITIVE_INFINITY
    val point = PointF(x, y)
    val tolerance = resources.displayMetrics.density * 12f
    for (objectData in allObjects) {
      val id = objectData.elementId ?: continue
      if (!objectData.selectable || (visibleKinds.isNotEmpty() && !visibleKinds.contains(objectData.kind))) continue
      val projected = objectData.points.map(::project)
      val validPoints = projected.filterNotNull()
      if (validPoints.isEmpty()) continue
      val left = validPoints.minOf { it.x } - tolerance
      val top = validPoints.minOf { it.y } - tolerance
      val right = validPoints.maxOf { it.x } + tolerance
      val bottom = validPoints.maxOf { it.y } + tolerance
      if (point.x !in left..right || point.y !in top..bottom) continue
      var triangleHit = false
      for (triangle in objectData.triangles) {
        val a = projected.getOrNull(triangle[0]) ?: continue
        val b = projected.getOrNull(triangle[1]) ?: continue
        val c = projected.getOrNull(triangle[2]) ?: continue
        if (pointInTriangle(point, a, b, c)) {
          triangleHit = true
          break
        }
      }
      val centerX = (left + right) * 0.5f
      val centerY = (top + bottom) * 0.5f
      val area = (right - left) * (bottom - top)
      val score = if (triangleHit) {
        area.toDouble() * 0.001
      } else {
        kotlin.math.hypot(point.x - centerX, point.y - centerY).toDouble() + area * 0.00001
      }
      if (score < bestScore) {
        bestScore = score
        bestId = id
      }
    }
    return bestId
  }

  fun pickByCameraRay(
    camera: Camera?,
    x: Float,
    y: Float,
    visibleKinds: Set<String>,
  ): Long? {
    if (camera == null || width <= 1 || height <= 1) return null
    val projection = camera.getProjectionMatrix(DoubleArray(16)).map { it.toFloat() }.toFloatArray()
    val view = camera.getViewMatrix(DoubleArray(16)).map { it.toFloat() }.toFloatArray()
    val viewProjection = FloatArray(16)
    val inverse = FloatArray(16)
    Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)
    if (!Matrix.invertM(inverse, 0, viewProjection, 0)) return null
    val clipX = x / width.toFloat() * 2f - 1f
    val clipY = 1f - y / height.toFloat() * 2f
    fun unproject(clipZ: Float): ScenePoint? {
      val point = FloatArray(4)
      Matrix.multiplyMV(point, 0, inverse, 0, floatArrayOf(clipX, clipY, clipZ, 1f), 0)
      if (kotlin.math.abs(point[3]) < 1e-7f) return null
      return ScenePoint(
        (point[0] / point[3]).toDouble(),
        (point[1] / point[3]).toDouble(),
        (point[2] / point[3]).toDouble(),
      )
    }
    // Filament camera matrices use the 0…1 device-depth convention on both
    // mobile backends. Using OpenGL's legacy -1 near depth creates a ray
    // behind the near plane on several Android drivers, so every real 3D
    // touch misses even when its screen coordinate is correct.
    val near = unproject(0f) ?: return null
    val far = unproject(1f) ?: return null
    val direction = normalize(ScenePoint(far.x - near.x, far.y - near.y, far.z - near.z))
    var nearestDistance = Double.POSITIVE_INFINITY
    var nearestId: Long? = null
    var nearestOpeningDistance = Double.POSITIVE_INFINITY
    var nearestOpeningId: Long? = null
    for (objectData in allObjects) {
      val id = objectData.elementId ?: continue
      if (!objectData.selectable || (visibleKinds.isNotEmpty() && !visibleKinds.contains(objectData.kind))) continue
      for (triangle in objectData.triangles) {
        val first = objectData.points.getOrNull(triangle[0]) ?: continue
        val second = objectData.points.getOrNull(triangle[1]) ?: continue
        val third = objectData.points.getOrNull(triangle[2]) ?: continue
        val distance = rayTriangleDistance(near, direction, first, second, third) ?: continue
        if (objectData.kind == "door" || objectData.kind == "window") {
          if (distance < nearestOpeningDistance) {
            nearestOpeningDistance = distance
            nearestOpeningId = id
          }
        } else if (distance < nearestDistance) {
          nearestDistance = distance
          nearestId = id
        }
      }
    }
    return preferredOpeningHit(
      nearestId,
      nearestDistance,
      nearestOpeningId,
      nearestOpeningDistance,
    )
  }

  /// Builds the same ray as [RenderSceneFilamentHostView.updateOrbitCamera]
  /// directly from the renderer's live orbit state. Some Android GLES drivers
  /// expose camera matrices with a backend-specific depth transform, making
  /// generic matrix unprojection miss every triangle despite a valid touch.
  fun liveCameraRay(x: Float, y: Float): NativeCameraRay? {
    if (width <= 1 || height <= 1) return null
    val cosPitch = kotlin.math.cos(pitchRadians)
    val eye = ScenePoint(
      center.x + distance * cosPitch * kotlin.math.cos(yawRadians),
      center.y + distance * kotlin.math.sin(pitchRadians),
      center.z + distance * cosPitch * kotlin.math.sin(yawRadians),
    )
    val forward = normalize(ScenePoint(center.x - eye.x, center.y - eye.y, center.z - eye.z))
    val worldUp = ScenePoint(0.0, 1.0, 0.0)
    val right = normalize(cross(forward, worldUp))
    val up = normalize(cross(right, forward))
    val normalizedX = (x / width.toFloat()).toDouble() * 2.0 - 1.0
    val normalizedY = 1.0 - (y / height.toFloat()).toDouble() * 2.0
    val aspect = width.toDouble() / height.toDouble()

    val origin: ScenePoint
    val direction: ScenePoint
    if (perspective) {
      val tangent = kotlin.math.tan(Math.toRadians(45.0) * 0.5)
      origin = eye
      direction = normalize(ScenePoint(
        forward.x + right.x * normalizedX * tangent * aspect + up.x * normalizedY * tangent,
        forward.y + right.y * normalizedX * tangent * aspect + up.y * normalizedY * tangent,
        forward.z + right.z * normalizedX * tangent * aspect + up.z * normalizedY * tangent,
      ))
    } else {
      val halfHeight = if (topDown) topDownZoom else kotlin.math.max(distance * 0.6, 2.0)
      val halfWidth = halfHeight * aspect
      origin = ScenePoint(
        eye.x + right.x * normalizedX * halfWidth + up.x * normalizedY * halfHeight,
        eye.y + right.y * normalizedX * halfWidth + up.y * normalizedY * halfHeight,
        eye.z + right.z * normalizedX * halfWidth + up.z * normalizedY * halfHeight,
      )
      direction = forward
    }
    return NativeCameraRay(origin, direction)
  }

  fun pickByLiveCameraRay(x: Float, y: Float, visibleKinds: Set<String>): Long? {
    val ray = liveCameraRay(x, y) ?: return null
    return nearestTriangleHit(ray.origin, ray.direction, visibleKinds)
  }

  private fun nearestTriangleHit(
    origin: ScenePoint,
    direction: ScenePoint,
    visibleKinds: Set<String>,
  ): Long? {
    var nearestDistance = Double.POSITIVE_INFINITY
    var nearestId: Long? = null
    var nearestOpeningDistance = Double.POSITIVE_INFINITY
    var nearestOpeningId: Long? = null
    for (objectData in allObjects) {
      val id = objectData.elementId ?: continue
      if (!objectData.selectable || (visibleKinds.isNotEmpty() && !visibleKinds.contains(objectData.kind))) continue
      for (triangle in objectData.triangles) {
        val first = objectData.points.getOrNull(triangle[0]) ?: continue
        val second = objectData.points.getOrNull(triangle[1]) ?: continue
        val third = objectData.points.getOrNull(triangle[2]) ?: continue
        val hitDistance = rayTriangleDistance(origin, direction, first, second, third) ?: continue
        if (objectData.kind == "door" || objectData.kind == "window") {
          if (hitDistance < nearestOpeningDistance) {
            nearestOpeningDistance = hitDistance
            nearestOpeningId = id
          }
        } else if (hitDistance < nearestDistance) {
          nearestDistance = hitDistance
          nearestId = id
        }
      }
    }
    return preferredOpeningHit(
      nearestId,
      nearestDistance,
      nearestOpeningId,
      nearestOpeningDistance,
    )
  }

  private fun preferredOpeningHit(
    nearestId: Long?,
    nearestDistance: Double,
    openingId: Long?,
    openingDistance: Double,
  ): Long? {
    // Opening panels are intentionally slightly inset in their host wall.
    // The simplified wall mesh retains its face for rendering robustness, so
    // a literal nearest-triangle test would always return the wall. Prefer a
    // door/window when it is on the same touched surface (within 35 cm along
    // the ray), but never select an unrelated opening deep behind a wall.
    if (openingId != null && openingDistance <= nearestDistance + 0.35) {
      return openingId
    }
    return nearestId
  }

  private fun rayTriangleDistance(
    origin: ScenePoint,
    direction: ScenePoint,
    first: ScenePoint,
    second: ScenePoint,
    third: ScenePoint,
  ): Double? {
    val edgeOne = ScenePoint(second.x - first.x, second.y - first.y, second.z - first.z)
    val edgeTwo = ScenePoint(third.x - first.x, third.y - first.y, third.z - first.z)
    val p = cross(direction, edgeTwo)
    val determinant = dot(edgeOne, p)
    if (kotlin.math.abs(determinant) < 1e-9) return null
    val inverse = 1.0 / determinant
    val originToFirst = ScenePoint(origin.x - first.x, origin.y - first.y, origin.z - first.z)
    val u = dot(originToFirst, p) * inverse
    if (u < -1e-7 || u > 1.0000001) return null
    val q = cross(originToFirst, edgeOne)
    val v = dot(direction, q) * inverse
    if (v < -1e-7 || u + v > 1.0000001) return null
    val distance = dot(edgeTwo, q) * inverse
    return distance.takeIf { it > 1e-6 }
  }

  private fun pointInTriangle(point: PointF, a: PointF, b: PointF, c: PointF): Boolean {
    fun sign(first: PointF, second: PointF, third: PointF): Float =
      (first.x - third.x) * (second.y - third.y) - (second.x - third.x) * (first.y - third.y)
    val first = sign(point, a, b)
    val second = sign(point, b, c)
    val third = sign(point, c, a)
    return !((first < 0f || second < 0f || third < 0f) &&
      (first > 0f || second > 0f || third > 0f))
  }

  fun clearVisualScene() {
    objects = emptyList()
    allObjects = emptyList()
    hasExternalMeshEdges = false
    visibleKinds = emptySet()
    planOpeningSpecs = emptyList()
    levels = emptyList()
    invalidate()
  }

  fun setSelection(ids: Set<Long>, active: Long?) {
    selectedIds = ids
    activeId = active
    val selected = allObjects.filter { it.elementId != null && ids.contains(it.elementId) }
    objects = (objects + selected).distinctBy { it.elementId ?: it.hashCode().toLong() }
    invalidate()
  }

  fun setDisplayStyle(style: String) {
    wireframe = style == "wireframe"
    // Solid uses only canonical, front-facing crease/silhouette lines. Canvas
    // line width is density-aware, unlike GPU line primitives on Android.
    // Solid borders are a depth-tested Filament mesh. The overlay is retained
    // for Wire and selected-object feedback only.
    // External mesh imports need a small screen-space fallback because their
    // Filament edge prisms can be depth-occluded by coplanar FBX faces on
    // mobile drivers. Architectural BIM edges stay GPU-only for performance.
    showObjectEdges = style == "wireframe" || hasExternalMeshEdges
    outline.color = when (style) {
      "wireframe" -> Color.argb(225, 18, 30, 42)
      "solid" -> Color.argb(170, 37, 51, 65)
      else -> Color.TRANSPARENT
    }
    outline.strokeWidth = resources.displayMetrics.density * if (wireframe) 1.45f else 1.6f
    invalidate()
  }

  fun setVisibleKinds(kinds: Set<String>) {
    visibleKinds = kinds.map(::normalizeKind).toSet()
    invalidate()
  }

  fun setViewportTheme(theme: String) {
    viewportTheme = when (theme) {
      "standardDark", "amoledBlack" -> theme
      else -> "light"
    }
    val dark = viewportTheme != "light"
    outline.color = if (dark) Color.argb(210, 218, 226, 231) else Color.argb(155, 24, 39, 52)
    externalOutline.color = if (dark) Color.argb(235, 226, 235, 238) else Color.argb(232, 28, 45, 55)
    openingPaint.color = if (dark) Color.rgb(220, 228, 232) else Color.rgb(17, 24, 39)
    windowPaint.color = if (dark) Color.rgb(190, 211, 219) else Color.rgb(17, 24, 39)
    openingCutPaint.color = if (dark) {
      if (viewportTheme == "amoledBlack") Color.BLACK else Color.rgb(32, 36, 39)
    } else {
      Color.rgb(244, 247, 245)
    }
    invalidate()
  }

  fun setVisualCamera(
    center: ScenePoint,
    yawRadians: Double,
    pitchRadians: Double,
    distance: Double,
    topDownZoom: Double,
    topDown: Boolean,
    perspective: Boolean,
    showNativeLevels: Boolean,
  ) {
    this.center = center
    this.yawRadians = yawRadians
    this.pitchRadians = pitchRadians
    this.distance = distance
    this.topDownZoom = topDownZoom
    this.topDown = topDown
    this.perspective = perspective
    this.showNativeLevels = showNativeLevels
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    drawAuthoringEdges(canvas)
    // NativeSelectionOverlay is the single owner of committed 2D opening
    // symbols on Android. Flutter keeps only draft/selection overlays, so
    // doors and windows are not painted twice on every plan frame.
    drawPlanOpeningSymbols(canvas)
    drawSectionBox(canvas)
    val rect = rectangle ?: return
    val color = if (crossing) Color.rgb(245, 158, 11) else Color.rgb(37, 99, 235)
    fill.color = Color.argb(40, Color.red(color), Color.green(color), Color.blue(color))
    stroke.color = color
    canvas.drawRect(rect, fill)
    canvas.drawRect(rect, stroke)
  }

  private fun drawSectionBox(canvas: Canvas) {
    if (!sectionBoxEnabled || topDown) return
    val corners = listOf(
      ScenePoint(sectionBoxMin.x, sectionBoxMin.y, sectionBoxMin.z),
      ScenePoint(sectionBoxMax.x, sectionBoxMin.y, sectionBoxMin.z),
      ScenePoint(sectionBoxMax.x, sectionBoxMax.y, sectionBoxMin.z),
      ScenePoint(sectionBoxMin.x, sectionBoxMax.y, sectionBoxMin.z),
      ScenePoint(sectionBoxMin.x, sectionBoxMin.y, sectionBoxMax.z),
      ScenePoint(sectionBoxMax.x, sectionBoxMin.y, sectionBoxMax.z),
      ScenePoint(sectionBoxMax.x, sectionBoxMax.y, sectionBoxMax.z),
      ScenePoint(sectionBoxMin.x, sectionBoxMax.y, sectionBoxMax.z),
    ).map(::project)
    if (corners.any { it == null }) return
    val points = corners.filterNotNull()
    val faces = listOf(
      intArrayOf(0, 1, 2, 3), intArrayOf(4, 5, 6, 7),
      intArrayOf(0, 1, 5, 4), intArrayOf(1, 2, 6, 5),
      intArrayOf(2, 3, 7, 6), intArrayOf(3, 0, 4, 7),
    )
    for (face in faces) {
      val path = android.graphics.Path()
      path.moveTo(points[face[0]].x, points[face[0]].y)
      for (index in 1 until face.size) path.lineTo(points[face[index]].x, points[face[index]].y)
      path.close()
      canvas.drawPath(path, sectionFill)
    }
    val edges = listOf(
      0 to 1, 1 to 2, 2 to 3, 3 to 0, 4 to 5, 5 to 6, 6 to 7, 7 to 4,
      0 to 4, 1 to 5, 2 to 6, 3 to 7,
    )
    for ((first, second) in edges) {
      canvas.drawLine(points[first].x, points[first].y, points[second].x, points[second].y, sectionStroke)
    }
    val radius = resources.displayMetrics.density * 6.5f
    for (point in sectionFaceCenters().values.mapNotNull(::project)) {
      canvas.drawCircle(point.x, point.y, radius, sectionHandle)
    }
  }

  private fun drawAuthoringEdges(canvas: Canvas) {
    if (width <= 1 || height <= 1) return
    for (objectData in objects) {
      if (visibleKinds.isNotEmpty() &&
        !visibleKinds.contains(normalizeKind(objectData.kind))
      ) continue
      val selected = objectData.elementId != null && selectedIds.contains(objectData.elementId)
      val externalMesh = objectData.metadata["external_mesh"] == "true"
      // The Android overlay is a semantic interaction layer, not a second
      // renderer. In Solid/Shaded it must never paint native-cache bounds:
      // those envelopes are not architectural edges and make filled IFC
      // models look like wireframe. External mesh imports are different: an
      // FBX/OBJ/GLB often has smooth or split topology, so its bounded,
      // deterministic feature-edge fallback is the only lightweight way to
      // preserve a readable model outline on tablet GPUs. Keep that fallback
      // enabled only for explicitly identified external meshes.
      if (!wireframe && !selected && (!externalMesh || !showObjectEdges)) continue
      // Do not project sampled geometry for the normal path. Filament already
      // owns the batched architectural edges; this Android overlay is only
      // needed for wireframe or selected-object feedback.
      val projected = objectData.points.map(::project)
      val edgePaint = when {
        selected -> selectedOutline
        externalMesh -> externalOutline
        else -> outline
      }
      for (edge in objectData.featureEdges) {
        if (!wireframe && !selected && !externalMesh && !isVisibleSolidEdge(objectData, edge)) continue
        val first = projected.getOrNull(edge.first)
        val second = projected.getOrNull(edge.second)
        if (first != null && second != null) {
          canvas.drawLine(first.x, first.y, second.x, second.y, edgePaint)
        }
      }
    }
    if (showNativeLevels && !topDown) {
      val widthSpan = max(sceneBounds.max.x - sceneBounds.min.x, 1.0)
      val backZ = sceneBounds.max.z
      for ((name, elevation) in levels) {
        // Level annotation is documentation, not geometry. Keep it in a
        // dedicated exterior gutter instead of drawing through the model;
        // Canvas has no Filament depth buffer and otherwise appears on the
        // far side of a building while orbiting.
        val first = project(ScenePoint(sceneBounds.min.x - widthSpan * 0.30, elevation, backZ))
        val second = project(ScenePoint(sceneBounds.min.x - widthSpan * 0.06, elevation, backZ))
        if (first != null && second != null) {
          canvas.drawLine(first.x, first.y, second.x, second.y, levelPaint)
          canvas.drawText(name, first.x + 6f, first.y - 5f, levelText)
        }
      }
    }
  }

  private fun drawPlanOpeningSymbols(canvas: Canvas) {
    if (!topDown) return
    for (opening in planOpeningSpecs) {
      val startX = opening.startX
      val startY = opening.startY
      val endX = opening.endX
      val endY = opening.endY
      val offset = opening.offset
      val widthMeters = opening.widthMeters

      val dx = endX - startX
      val dy = endY - startY
      val axisLength = kotlin.math.sqrt(dx * dx + dy * dy)
      if (axisLength <= 1.0e-8) continue
      val ux = dx / axisLength
      val uy = dy / axisLength
      val nx = -uy
      val ny = ux
      val centerX = startX + ux * offset
      val centerY = startY + uy * offset
      val halfWidth = widthMeters * 0.5
      val start = sourcePlanPoint(centerX - ux * halfWidth, centerY - uy * halfWidth)
      val end = sourcePlanPoint(centerX + ux * halfWidth, centerY + uy * halfWidth)
      val halfThickness = opening.halfThickness
      val cutStart = project(
        sourcePlanPoint(
          centerX - ux * halfWidth + nx * halfThickness,
          centerY - uy * halfWidth + ny * halfThickness,
        ),
      ) ?: continue
      val cutEnd = project(
        sourcePlanPoint(
          centerX + ux * halfWidth + nx * halfThickness,
          centerY + uy * halfWidth + ny * halfThickness,
        ),
      ) ?: continue
      val cutEndBack = project(
        sourcePlanPoint(
          centerX + ux * halfWidth - nx * halfThickness,
          centerY + uy * halfWidth - ny * halfThickness,
        ),
      ) ?: continue
      val cutStartBack = project(
        sourcePlanPoint(
          centerX - ux * halfWidth - nx * halfThickness,
          centerY - uy * halfWidth - ny * halfThickness,
        ),
      ) ?: continue
      // The opening objects are hidden as full prisms in top-down mode. Clear
      // their host wall footprint here before drawing the familiar symbol so
      // the wall itself visibly contains the opening.
      val cutPath = Path().apply {
        moveTo(cutStart.x, cutStart.y)
        lineTo(cutEnd.x, cutEnd.y)
        lineTo(cutEndBack.x, cutEndBack.y)
        lineTo(cutStartBack.x, cutStartBack.y)
        close()
      }
      canvas.drawPath(cutPath, openingCutPaint)
      val openEnd = sourcePlanPoint(
        centerX - ux * halfWidth + nx * widthMeters,
        centerY - uy * halfWidth + ny * widthMeters,
      )
      val first = project(start) ?: continue
      val second = project(end) ?: continue
      val open = project(openEnd) ?: continue
      openingPaint.color = if (opening.elementId != null && selectedIds.contains(opening.elementId)) {
        Color.rgb(37, 99, 235)
      } else {
        Color.rgb(17, 24, 39)
      }
      if (opening.kind == "window") {
        // Windows use the compact architectural plan symbol: two glazing
        // lines parallel to the host wall. Swing arcs belong to doors and
        // make small windows noisy and visually ambiguous.
        val glassOffset = opening.halfThickness * 0.70
        val glassFirst = project(
          sourcePlanPoint(
            centerX - ux * halfWidth + nx * glassOffset,
            centerY - uy * halfWidth + ny * glassOffset,
          ),
        ) ?: continue
        val glassSecond = project(
          sourcePlanPoint(
            centerX + ux * halfWidth + nx * glassOffset,
            centerY + uy * halfWidth + ny * glassOffset,
          ),
        ) ?: continue
        val glassFirstBack = project(
          sourcePlanPoint(
            centerX - ux * halfWidth - nx * glassOffset,
            centerY - uy * halfWidth - ny * glassOffset,
          ),
        ) ?: continue
        val glassSecondBack = project(
          sourcePlanPoint(
            centerX + ux * halfWidth - nx * glassOffset,
            centerY + uy * halfWidth - ny * glassOffset,
          ),
        ) ?: continue
        windowPaint.color = openingPaint.color
        canvas.drawLine(glassFirst.x, glassFirst.y, glassSecond.x, glassSecond.y, windowPaint)
        canvas.drawLine(glassFirstBack.x, glassFirstBack.y, glassSecondBack.x, glassSecondBack.y, windowPaint)
        continue
      }

      // Revit-like plan door: the leaf is shown open and the swing is a
      // quarter-circle arc from the closed wall direction to the open leaf.
      canvas.drawLine(first.x, first.y, open.x, open.y, openingPaint)
      val radius = kotlin.math.hypot((second.x - first.x).toDouble(), (second.y - first.y).toDouble()).toFloat()
      if (radius <= 1.0f) continue
      val startAngle = Math.toDegrees(atan2((second.y - first.y).toDouble(), (second.x - first.x).toDouble())).toFloat()
      val endAngle = Math.toDegrees(atan2((open.y - first.y).toDouble(), (open.x - first.x).toDouble())).toFloat()
      var sweep = endAngle - startAngle
      while (sweep > 180f) sweep -= 360f
      while (sweep < -180f) sweep += 360f
      if (kotlin.math.abs(sweep) < 5f) sweep = if (sweep < 0f) -90f else 90f
      canvas.drawArc(
        RectF(first.x - radius, first.y - radius, first.x + radius, first.y + radius),
        startAngle,
        sweep,
        false,
        openingPaint,
      )
    }
  }

  private fun buildPlanOpeningSpecs(value: List<NativeVisualObject>): List<PlanOpeningSpec> {
    val wallsById = value.asSequence()
      .filter { it.kind == "wall" }
      .mapNotNull { wall -> wall.elementId?.let { it to wall } }
      .toMap()
    return value.asSequence()
      .filter { it.kind == "door" || it.kind == "window" }
      .mapNotNull { opening ->
        val hostId = opening.metadata["host_wall_id"]?.toLongOrNull() ?: return@mapNotNull null
        val host = wallsById[hostId] ?: return@mapNotNull null
        val startX = host.metadata["start_x"]?.toDoubleOrNull() ?: return@mapNotNull null
        val startY = host.metadata["start_y"]?.toDoubleOrNull() ?: return@mapNotNull null
        val endX = host.metadata["end_x"]?.toDoubleOrNull() ?: return@mapNotNull null
        val endY = host.metadata["end_y"]?.toDoubleOrNull() ?: return@mapNotNull null
        val offset = opening.metadata["offset_meters"]?.toDoubleOrNull() ?: return@mapNotNull null
        val widthMeters = opening.metadata["width_meters"]?.toDoubleOrNull() ?: return@mapNotNull null
        if (widthMeters <= 1.0e-6) return@mapNotNull null
        val thickness = host.metadata["thickness_meters"]?.toDoubleOrNull() ?: 0.20
        PlanOpeningSpec(
          kind = opening.kind,
          elementId = opening.elementId,
          startX = startX,
          startY = startY,
          endX = endX,
          endY = endY,
          offset = offset,
          widthMeters = widthMeters,
          halfThickness = thickness * 0.5,
        )
      }
      .toList()
  }

  private data class PlanOpeningSpec(
    val kind: String,
    val elementId: Long?,
    val startX: Double,
    val startY: Double,
    val endX: Double,
    val endY: Double,
    val offset: Double,
    val widthMeters: Double,
    val halfThickness: Double,
  )

  private fun sourcePlanPoint(x: Double, y: Double): ScenePoint =
    ScenePoint(x, 0.0, -y)

  private fun isVisibleSolidEdge(
    objectData: NativeVisualObject,
    edge: NativeVisualEdge,
  ): Boolean {
    if (topDown) return true
    val cosPitch = cos(pitchRadians)
    val eye = ScenePoint(
      center.x + distance * cosPitch * cos(yawRadians),
      center.y + distance * sin(pitchRadians),
      center.z + distance * cosPitch * sin(yawRadians),
    )
    val facing = mutableListOf<Boolean>()
    for (triangleIndex in edge.triangleIndices) {
      val triangle = objectData.triangles.getOrNull(triangleIndex) ?: continue
      val a = objectData.points[triangle[0]]
      val b = objectData.points[triangle[1]]
      val c = objectData.points[triangle[2]]
      val normal = overlayTriangleNormal(a, b, c)
      val centroidX = (a.x + b.x + c.x) / 3.0
      val centroidY = (a.y + b.y + c.y) / 3.0
      val centroidZ = (a.z + b.z + c.z) / 3.0
      facing += normal[0] * (eye.x - centroidX) +
        normal[1] * (eye.y - centroidY) +
        normal[2] * (eye.z - centroidZ) > 1e-5
    }
    if (facing.isEmpty()) return false
    // An open boundary is visible only when its face faces the camera. An
    // edge between front/back faces is a real silhouette. Keep only very
    // sharp front-facing corners as architectural creases.
    if (facing.size == 1) return facing.first()
    if (facing.any() && facing.any { !it }) return true
    return edge.sharp && facing.all { it }
  }

  private fun overlayTriangleNormal(
    a: ScenePoint,
    b: ScenePoint,
    c: ScenePoint,
  ): DoubleArray {
    val abX = b.x - a.x; val abY = b.y - a.y; val abZ = b.z - a.z
    val acX = c.x - a.x; val acY = c.y - a.y; val acZ = c.z - a.z
    val x = abY * acZ - abZ * acY
    val y = abZ * acX - abX * acZ
    val z = abX * acY - abY * acX
    val length = kotlin.math.sqrt(x * x + y * y + z * z)
    return if (length <= 1e-9) {
      doubleArrayOf(0.0, 0.0, 0.0)
    } else {
      doubleArrayOf(x / length, y / length, z / length)
    }
  }

  private fun project(point: ScenePoint): android.graphics.PointF? {
    val aspect = width.toDouble() / max(height, 1).toDouble()
    if (topDown) {
      val halfHeight = max(topDownZoom, 0.001)
      val halfWidth = halfHeight * aspect
      return android.graphics.PointF(
        ((point.x - center.x) / halfWidth * 0.5 + 0.5).times(width).toFloat(),
        ((point.z - center.z) / halfHeight * 0.5 + 0.5).times(height).toFloat(),
      )
    }
    val cosPitch = cos(pitchRadians)
    val eye = ScenePoint(
      center.x + distance * cosPitch * cos(yawRadians),
      center.y + distance * sin(pitchRadians),
      center.z + distance * cosPitch * sin(yawRadians),
    )
    val forward = normalize(ScenePoint(center.x - eye.x, center.y - eye.y, center.z - eye.z))
    val right = normalize(cross(forward, ScenePoint(0.0, 1.0, 0.0)))
    val up = cross(right, forward)
    val relative = ScenePoint(point.x - eye.x, point.y - eye.y, point.z - eye.z)
    val x = dot(relative, right)
    val y = dot(relative, up)
    val depth = dot(relative, forward)
    if (depth <= 0.01) return null
    val (screenX, screenY) = if (perspective) {
      val tangent = tan(Math.toRadians(45.0) * 0.5)
      (x / (depth * tangent * aspect)) to (y / (depth * tangent))
    } else {
      val halfHeight = max(distance * 0.6, 2.0)
      (x / (halfHeight * aspect)) to (y / halfHeight)
    }
    return android.graphics.PointF(
      ((screenX * 0.5 + 0.5) * width).toFloat(),
      ((0.5 - screenY * 0.5) * height).toFloat(),
    )
  }

  private fun dot(first: ScenePoint, second: ScenePoint): Double =
    first.x * second.x + first.y * second.y + first.z * second.z

  private fun cross(first: ScenePoint, second: ScenePoint): ScenePoint = ScenePoint(
    first.y * second.z - first.z * second.y,
    first.z * second.x - first.x * second.z,
    first.x * second.y - first.y * second.x,
  )

  private fun normalize(value: ScenePoint): ScenePoint {
    val length = kotlin.math.sqrt(dot(value, value))
    return if (length <= 1e-9) ScenePoint(0.0, 0.0, 0.0) else ScenePoint(value.x / length, value.y / length, value.z / length)
  }
}
