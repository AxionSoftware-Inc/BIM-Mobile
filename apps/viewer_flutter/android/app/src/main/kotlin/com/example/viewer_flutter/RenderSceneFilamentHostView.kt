package com.example.viewer_flutter

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.RenderableManager.PrimitiveType
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.Skybox
import com.google.android.filament.SwapChain
import com.google.android.filament.VertexBuffer
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.Box
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper
import com.google.android.filament.filamat.MaterialBuilder
import com.google.android.filament.filamat.MaterialPackage
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.IntBuffer
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

private const val DEFAULT_RENDERER_STATUS = "Renderer initializing..."
private const val TAG = "RenderSceneFilament"

private const val FLAT_COLOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    material.baseColor = materialParams.baseColor;
}
"""

private const val WALL_BRICK_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float row = floor(world.y / 0.075);
    float jointY = step(fract(world.y / 0.075), 0.018);
    float jointX = step(fract((world.x + mod(row, 2.0) * 0.12) / 0.24), 0.014);
    // Keep this subtle enough for a working BIM view, but distinct on a
    // tablet-sized wall face; the prior 16% contrast disappeared in Solid.
    float mortar = max(jointY, jointX) * 0.34;
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);
    material.baseColor = float4(brick, materialParams.baseColor.a);
}
"""

private data class FilamentRenderableEntry(
  val objectData: SceneObject,
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val edgeEntity: Int?,
  val edgeVertexBuffer: VertexBuffer?,
  val edgeIndexBuffer: IndexBuffer?,
  val material: Material,
  val materialInstance: MaterialInstance,
  val edgeMaterialInstance: MaterialInstance?,
  val baseColor: FloatArray,
  val bounds: SceneBounds,
  var attached: Boolean = false,
  var edgeAttached: Boolean = false,
)

private data class FilamentSceneMetrics(
  val bounds: SceneBounds,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
)

private data class NativeVisualObject(
  val elementId: Long?,
  val kind: String,
  val selectable: Boolean,
  val points: List<ScenePoint>,
  val triangles: List<IntArray>,
  val featureEdges: List<NativeVisualEdge>,
)

private data class NativeVisualEdge(
  val first: Int,
  val second: Int,
  val triangleIndices: IntArray,
  // A true architectural corner (roughly 70 degrees or sharper), not a
  // tessellation seam. Solid can retain these after silhouette filtering.
  val sharp: Boolean,
)

internal class RenderSceneFilamentHostView(
  context: Context,
  initialScene: SceneState? = null,
  private val onObjectTapped: (Long?) -> Unit = {},
) : FrameLayout(context), UiHelper.RendererCallback, Choreographer.FrameCallback {
  companion object {
    init {
      Filament.init()
      MaterialBuilder.init()
    }
  }

  private val renderSurface = TextureView(context)
  private val selectionOverlay = NativeSelectionOverlay(context)
  private val statusView = TextView(context)
  private val choreographer = Choreographer.getInstance()
  private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
  private val displayHelper = DisplayHelper(context, Handler(Looper.getMainLooper()))
  private val scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
    override fun onScale(detector: ScaleGestureDetector): Boolean {
      if (projectionMode == "topDown") {
        topDownZoom = (topDownZoom / detector.scaleFactor.toDouble()).coerceIn(0.5, 200.0)
        configureCameraProjection()
      } else {
        val nextDistance = orbitDistance / detector.scaleFactor.toDouble()
        orbitDistance = nextDistance.coerceIn(minimumOrbitDistance(), 250.0)
        configureCameraProjection()
      }
      updateOrbitCamera()
      updateStatus(
        if (projectionMode == "topDown") {
          "Plan zoom ${topDownZoom.format(2)}m"
        } else {
          "Orbit zoom ${orbitDistance.format(2)}m"
        }
      )
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
      )
    )
  }

  private var engine: Engine? = null
  private var renderer: Renderer? = null
  private var scene: Scene? = null
  private var filamentView: View? = null
  private var camera: Camera? = null
  private var colorGrading: ColorGrading? = null
  private var swapChain: SwapChain? = null
  private var sceneMetrics = FilamentSceneMetrics(
    bounds = SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0)),
    objectCount = 0,
    vertexCount = 0,
    indexCount = 0,
  )
  private var currentScene: SceneState? = initialScene
  private var selectedElementId: Long? = null
  private var selectedElementIds = emptySet<Long>()
  private var highlightedElementId: Long? = null
  private var framePosted = false
  private var renderedFrameCount = 0L
  private var lastRenderedFrameNanos = 0L
  private var interactiveUntilMs = 0L
  private var telemetrySampleMs = 0L
  private var telemetryCpuMs = 0L
  private var telemetryFrameCount = 0L
  private var cpuPercent = 0.0
  private var framesPerSecond = 0.0
  private var residentMemoryMb = 0.0
  private var nativeThreadCount = 0
  private var surfaceReady = false
  private var materialBuilderReady = false
  private var material: Material? = null
  private var wallMaterial: Material? = null
  private var windowMaterial: Material? = null
  private val renderables = linkedMapOf<Long, FilamentRenderableEntry>()
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
  private var lastTouchX = 0f
  private var lastTouchY = 0f
  private var touchDownX = 0f
  private var touchDownY = 0f
  private var touchMoved = false
  private var touching = false

  init {
    setBackgroundColor(Color.rgb(243, 247, 244))
    addView(
      renderSurface,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
    addView(
      selectionOverlay,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
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

    uiHelper.renderCallback = this
    uiHelper.attachTo(renderSurface)
    // Flutter owns Android touch dispatch. In 3D it forwards a normalized
    // viewport point through the channel, which we map back to this actual
    // SurfaceView before ray-picking with Filament's live camera.
    renderSurface.isClickable = false

    try {
      val filamentEngine = Engine.create(Engine.Backend.OPENGL)
      engine = filamentEngine
      renderer = filamentEngine.createRenderer()
      scene = filamentEngine.createScene()
      filamentView = filamentEngine.createView()
      // Windows use a transparent shaded material; include them in GPU picks
      // so tapping glass selects the window rather than the wall behind it.
      filamentView?.isTransparentPickingEnabled = true
      camera = filamentEngine.createCamera(EntityManager.get().create())
      filamentView?.scene = scene
      filamentView?.camera = camera
      colorGrading = ColorGrading.Builder()
        .toneMapping(ColorGrading.ToneMapping.LINEAR)
        .build(filamentEngine)
      filamentView?.colorGrading = colorGrading
      filamentView?.viewport = Viewport(0, 0, 1, 1)
      // Light paper canvas preserves true-white Solid geometry without the
      // old overall grey cast.
      scene?.skybox = Skybox.Builder().color(0.91f, 0.92f, 0.91f, 1.0f).build(filamentEngine)
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

  fun loadScene(newScene: SceneState?) {
    if (newScene == null) {
      clearScene("RenderScene load failed or scene cleared.")
      return
    }
    currentScene = newScene
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

  fun clearScene() {
    clearScene("Scene cleared.")
  }

  private fun clearScene(message: String) {
    currentScene = null
    selectedElementId = null
    selectedElementIds = emptySet()
    highlightedElementId = null
    selectionOverlay.clear()
    selectionOverlay.clearVisualScene()
    destroyRenderables()
    updateMetrics()
    updateStatus(message)
    Log.i(TAG, message)
    invalidate()
  }

  fun fitCamera() {
    val camera = camera ?: return
    val metrics = sceneMetrics
    // sceneMetrics already comes from Filament-space renderable bounds.
    // Transforming it again moves the fitted camera away from the mesh.
    val bounds = metrics.bounds
    val width = max(bounds.max.x - bounds.min.x, 0.001)
    val depth = max(bounds.max.y - bounds.min.y, 0.001)
    val height = max(bounds.max.z - bounds.min.z, 0.001)
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerY = (bounds.min.y + bounds.max.y) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    val radius = max(width, max(depth, height)) * 0.75 + 1.0
    orbitCenter = ScenePoint(centerX, centerY, centerZ)
    orbitDistance = max(radius * 2.0, 3.0)
    orbitYawRadians = Math.toRadians(45.0)
    orbitPitchRadians = Math.toRadians(24.0)
    topDownZoom = max(radius * 1.2, 2.0)
    configureCameraProjection()
    updateOrbitCamera()
    interactiveUntilMs = SystemClock.uptimeMillis() + 500L
    syncVisualOverlay()
    updateStatus("Camera fitted to ${metrics.objectCount} objects.")
    invalidate()
  }

  fun setProjectionMode(mode: String) {
    projectionMode = mode
    when (mode) {
      "northElevation" -> { orbitYawRadians = Math.PI / 2.0; orbitPitchRadians = 0.0 }
      "southElevation" -> { orbitYawRadians = -Math.PI / 2.0; orbitPitchRadians = 0.0 }
      "eastElevation" -> { orbitYawRadians = Math.PI; orbitPitchRadians = 0.0 }
      "westElevation" -> { orbitYawRadians = 0.0; orbitPitchRadians = 0.0 }
    }
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    updateStatus()
    invalidate()
  }

  fun setOrbitProjectionStyle(style: String) {
    orbitProjectionStyle = style
    configureCameraProjection()
    updateOrbitCamera()
    syncVisualOverlay()
    updateStatus()
    invalidate()
  }

  /// Camera state is owned by Flutter so Filament and fallback receive the
  /// same tablet interaction policy. Coordinates are converted once here.
  fun setCamera(payload: Map<*, *>?) {
    val orbitCenterPayload = parsePoint(payload?.get("orbitCenter"))
    val planCenterPayload = parsePoint(payload?.get("planCenter"))
    if (projectionMode == "topDown" && planCenterPayload != null) {
      orbitCenter = toFilamentPoint(planCenterPayload)
      val planZoom = toDouble(payload?.get("planZoom"))
      val planViewportHeight = toDouble(payload?.get("planViewportHeight"))
      if (planZoom != null && planZoom > 0.0 && planViewportHeight != null && planViewportHeight > 0.0) {
        // Flutter owns the plan camera in logical pixels/metre.  Convert that
        // directly to Filament's orthographic half-height in metres; using a
        // fixed pixel reference made the native plan camera differ by device.
        topDownZoom = (planViewportHeight / (2.0 * planZoom)).coerceIn(0.5, 200.0)
      }
    } else if (orbitCenterPayload != null) {
      orbitCenter = toFilamentPoint(orbitCenterPayload)
    }
    // Flutter uses X/Y plan with Z up; Filament receives X/Z/-Y. Mirror yaw
    // at this single conversion point so a two-finger side-pan follows the
    // same camera-right vector in both renderers.
    if (projectionMode == "isometric") {
      orbitYawRadians = toDouble(payload?.get("orbitYawRadians"))?.unaryMinus()
        ?: orbitYawRadians
      orbitPitchRadians = toDouble(payload?.get("orbitPitchRadians")) ?: orbitPitchRadians
    }
    val distance = toDouble(payload?.get("orbitDistance"))
    val zoom = toDouble(payload?.get("orbitZoomScale"))
    if (distance != null) {
      orbitDistance = (distance / (zoom ?: 1.0)).coerceIn(minimumOrbitDistance(), 250.0)
    }
    configureCameraProjection()
    updateOrbitCamera()
    interactiveUntilMs = SystemClock.uptimeMillis() + 500L
    syncVisualOverlay()
    invalidate()
  }

  fun setDisplayStyle(style: String) {
    displayStyle = style
    selectionOverlay.setDisplayStyle(style)
    syncVisibility()
    refreshTintState()
    updateStatus(if (style == "wireframe") "Wireframe: faces hidden, mesh edges shown." else null)
    invalidate()
  }

  fun setVisibleKinds(kinds: Set<String>) {
    visibleKinds.clear()
    visibleKinds.addAll(kinds.map { normalizeKind(it) })
    syncVisibility()
    updateStatus()
    invalidate()
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
    scheduleFrame()
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
    fitCamera()
    syncVisualOverlay()
  }

  override fun doFrame(frameTimeNanos: Long) {
    framePosted = false
    val renderer = renderer
    val view = filamentView
    val swapChain = swapChain
    // BIM editing needs instant feedback while navigating, not a permanent
    // 120 Hz render loop while the model is idle. Cap idle redraw to 30 FPS;
    // pointer gestures still render at the display cadence.
    val idleFrameIntervalNanos = 33_000_000L
    val shouldRender = touching || SystemClock.uptimeMillis() < interactiveUntilMs ||
      frameTimeNanos - lastRenderedFrameNanos >= idleFrameIntervalNanos
    if (shouldRender && renderer != null && view != null && swapChain != null && renderer.beginFrame(swapChain, frameTimeNanos)) {
      renderer.render(view)
      renderer.endFrame()
      renderedFrameCount += 1
      lastRenderedFrameNanos = frameTimeNanos
      sampleTelemetry()
    }
    scheduleFrame()
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
    cancelFrame()
    uiHelper.detach()
    displayHelper.detach()
    swapChain?.let { chain ->
      engine?.destroySwapChain(chain)
    }
    clearScene()
    scene?.let { scene ->
      engine?.destroyScene(scene)
    }
    filamentView?.let { view ->
      engine?.destroyView(view)
    }
    colorGrading?.let { grading ->
      engine?.destroyColorGrading(grading)
    }
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
    engine?.destroy()
    swapChain = null
    renderer = null
    scene = null
    filamentView = null
    camera = null
    colorGrading = null
    engine = null
    material = null
    wallMaterial = null
    windowMaterial = null
    materialBuilderReady = false
  }

  private fun buildRuntimeMaterial(): Boolean {
    val engine = engine ?: return false
    return try {
      material = buildMaterial(engine, "RenderSceneFlatColor", FLAT_COLOR_MAT)
      wallMaterial = buildMaterial(engine, "RenderSceneWallBrick", WALL_BRICK_MAT)
      windowMaterial = buildMaterial(engine, "RenderSceneWindowGlass", FLAT_COLOR_MAT, transparent = true)
      if (material == null || wallMaterial == null || windowMaterial == null) {
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
  ): Material? {
      val builder = MaterialBuilder()
        .name(name)
        .shading(MaterialBuilder.Shading.UNLIT)
        .culling(MaterialBuilder.CullingMode.NONE)
        .doubleSided(true)
        .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "baseColor")
        .material(source)
        .targetApi(MaterialBuilder.TargetApi.OPENGL)
        .platform(MaterialBuilder.Platform.MOBILE)
        .optimization(MaterialBuilder.Optimization.NONE)
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

  private fun rebuildScene() {
    destroyRenderables()
    val scene = scene ?: return
    val sceneState = currentScene ?: return
    if ((material == null || wallMaterial == null || windowMaterial == null) && materialBuilderReady) {
      buildRuntimeMaterial()
    }
    val engine = engine ?: return
    val material = material ?: run {
      statusMessage = "Filament material unavailable."
      Log.w(TAG, statusMessage)
      updateStatus()
      return
    }
    val wallMaterial = wallMaterial ?: material
    val windowMaterial = windowMaterial ?: material
    val filteredObjects = sceneState.objects
      .filter { visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(it.kind)) }
    val objects = if (filteredObjects.isNotEmpty()) filteredObjects else sceneState.objects
    if (filteredObjects.isEmpty() && sceneState.objects.isNotEmpty()) {
      Log.w(TAG, "All RenderScene objects were filtered out by kind visibility; rendering fallback set.")
    }
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
    for (objectData in objects) {
      try {
        val objectMaterial = when (normalizeKind(objectData.kind)) {
          "wall" -> wallMaterial
          "window" -> windowMaterial
          else -> material
        }
        val entry = createRenderable(
          engine,
          objectMaterial,
          objectData,
          wallJunctionElevations,
        ) ?: continue
        renderables[objectData.elementId ?: renderables.size.toLong() + 1L] = entry
        scene.addEntity(entry.entity)
        entry.attached = true
        attachedEntities.add(entry.entity)
      } catch (error: Throwable) {
        failedObjects += 1
        Log.e(TAG, "Failed to create Filament renderable for ${objectData.kind}", error)
      }
    }
    updateMetrics()
    if (failedObjects > 0) {
      statusMessage = "Filament skipped $failedObjects invalid renderables; loaded ${renderables.size}."
      Log.w(TAG, statusMessage)
    }
  }

  private fun createRenderable(
    engine: Engine,
    sharedMaterial: Material,
    objectData: SceneObject,
    wallJunctionElevations: List<Double>,
  ): FilamentRenderableEntry? {
    val geometry = objectGeometry(objectData) ?: return null
    val vertexBuffer = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(geometry.vertexCount)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
      .build(engine)
    vertexBuffer.setBufferAt(engine, 0, geometry.vertexData)

    val indexBuffer = IndexBuffer.Builder()
      .indexCount(geometry.indexCount)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
    indexBuffer.setBuffer(engine, geometry.indexData)

    val entity = EntityManager.get().create()
    val materialInstance = sharedMaterial.createInstance()
    val baseColor = kindColor(normalizeKind(objectData.kind))
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
      .geometry(0, PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer, 0, geometry.indexCount)
      .material(0, materialInstance)
      .build(engine, entity)

    val visual = toVisualObject(objectData)
    // GPU depth-tested architectural border pass. Keep semantic feature
    // edges (open boundaries and face creases), not every mesh triangle edge:
    // this preserves room corners after an exterior wall is removed without
    // turning the solid view into Wire.
    val edgeGeometry = edgeGeometry(
      visual.points,
      visual.featureEdges,
      visual.triangles,
      wallJunctionEdges = normalizeKind(objectData.kind) == "wall",
      wallJunctionElevations = wallJunctionElevations,
    )
    val edgeVertexBuffer = edgeGeometry?.let { edge ->
      VertexBuffer.Builder()
        .bufferCount(1)
        .vertexCount(edge.vertexCount)
        .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
        .build(engine).also { it.setBufferAt(engine, 0, edge.vertexData) }
    }
    val edgeIndexBuffer = edgeGeometry?.let { edge ->
      IndexBuffer.Builder().indexCount(edge.indexCount).bufferType(IndexBuffer.Builder.IndexType.UINT)
        .build(engine).also { it.setBuffer(engine, edge.indexData) }
    }
    val edgeEntity = if (edgeVertexBuffer != null && edgeIndexBuffer != null) EntityManager.get().create() else null
    // Edges must remain a neutral, high-contrast pass. Reusing the wall
    // brick shader makes a thin interior edge inherit the face pattern and
    // disappear at grazing angles.
    val edgeSharedMaterial = material ?: sharedMaterial
    val edgeMaterialInstance = edgeEntity?.let {
      edgeSharedMaterial.createInstance().also { instance ->
        instance.setParameter("baseColor", Colors.RgbaType.LINEAR, 0.015f, 0.025f, 0.040f, 1.0f)
      }
    }
    if (edgeEntity != null && edgeVertexBuffer != null && edgeIndexBuffer != null && edgeGeometry != null && edgeMaterialInstance != null) {
      RenderableManager.Builder(1)
        // Edge prisms extend past the face mesh. Use their own bounds so a
        // close interior orbit cannot cull an otherwise visible room edge.
        .boundingBox(filamentBox(edgeGeometry.bounds))
        .priority(7)
        .geometry(0, PrimitiveType.TRIANGLES, edgeVertexBuffer, edgeIndexBuffer, 0, edgeGeometry.indexCount)
        .material(0, edgeMaterialInstance)
        .build(engine, edgeEntity)
    }

    return FilamentRenderableEntry(
      objectData = objectData,
      entity = entity,
      vertexBuffer = vertexBuffer,
      indexBuffer = indexBuffer,
      edgeEntity = edgeEntity,
      edgeVertexBuffer = edgeVertexBuffer,
      edgeIndexBuffer = edgeIndexBuffer,
      material = sharedMaterial,
      materialInstance = materialInstance,
      edgeMaterialInstance = edgeMaterialInstance,
      baseColor = baseColor,
      bounds = bounds,
    )
  }

  private fun objectGeometry(objectData: SceneObject): GeometryData? {
    val meshPoints = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      objectData.mesh.positions.map(::toFilamentPoint)
    } else {
      boxCorners(objectData.bounds).map(::toFilamentPoint)
    }
    if (meshPoints.isEmpty()) {
      return null
    }
    val triangles = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      objectData.mesh.indices.chunked(3).mapNotNull { group ->
        if (group.size == 3) {
          intArrayOf(group[0], group[1], group[2])
        } else {
          null
        }
      }
    } else {
      listOf(
        intArrayOf(0, 1, 2), intArrayOf(0, 2, 3),
        intArrayOf(4, 6, 5), intArrayOf(4, 7, 6),
        intArrayOf(0, 4, 5), intArrayOf(0, 5, 1),
        intArrayOf(1, 5, 6), intArrayOf(1, 6, 2),
        intArrayOf(2, 6, 7), intArrayOf(2, 7, 3),
        intArrayOf(3, 7, 4), intArrayOf(3, 4, 0),
      )
    }
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
    )
  }

  private fun edgeGeometry(
    points: List<ScenePoint>,
    edges: List<NativeVisualEdge>,
    triangles: List<IntArray>,
    wallJunctionEdges: Boolean = false,
    wallJunctionElevations: List<Double> = emptyList(),
  ): GeometryData? {
    val validEdges = edges.filter { it.first in points.indices && it.second in points.indices }
    // 28 mm is intentionally visual-only: it is thick enough for a tablet
    // Solid view, but does not change the semantic BIM geometry or picking.
    val normalRadius = 0.014
    // Junction borders deliberately get a stronger visual treatment than
    // ordinary silhouette edges. They are the only reliable room boundary
    // after an exterior wall has been removed and an adjacent floor/ceiling
    // occupies the same depth range.
    val junctionRadius = 0.032
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
            junctionKeys.add(edgeKey(firstIndex, secondIndex))
          }
        }
      }
    }
    data class RenderEdge(
      val first: ScenePoint,
      val second: ScenePoint,
      val junction: Boolean = false,
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
      )
    }.toMutableList()
    if (wallJunctionEdges) {
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
    val indexData = ByteBuffer.allocateDirect(renderEdges.size * 36 * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer()
    val cubeIndices = intArrayOf(
      0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
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
      val faceOffset = if (isHorizontalJunction) {
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
      val first = sourceFirst.copy(
        x = sourceFirst.x + faceOffset.x,
        y = sourceFirst.y + junctionOffset,
        z = sourceFirst.z + faceOffset.z,
      )
      val second = sourceSecond.copy(
        x = sourceSecond.x + faceOffset.x,
        y = sourceSecond.y + junctionOffset,
        z = sourceSecond.z + faceOffset.z,
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
    return GeometryData(vertexOffset, (vertexOffset / 8) * 36, vertexData, indexData, bounds)
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
      val visible = displayStyle != "wireframe" &&
        (visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(entry.objectData.kind)))
      if (visible && !entry.attached) {
        scene.addEntity(entry.entity)
        entry.attached = true
      } else if (!visible && entry.attached) {
        scene.removeEntity(entry.entity)
        entry.attached = false
      }
      // Shaded uses the same depth-tested architectural border pass as Solid;
      // only its face tint differs. Without this it reads as flat category
      // colour blocks and loses BIM form readability.
      val edgeVisible = (displayStyle == "solid" || displayStyle == "shaded") &&
        (visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(entry.objectData.kind)))
      val edgeEntity = entry.edgeEntity
      if (edgeEntity != null && edgeVisible && !entry.edgeAttached) {
        scene.addEntity(edgeEntity)
        entry.edgeAttached = true
      } else if (edgeEntity != null && !edgeVisible && entry.edgeAttached) {
        scene.removeEntity(edgeEntity)
        entry.edgeAttached = false
      }
    }
  }

  private fun refreshTintState() {
    for (entry in renderables.values) {
      val selected = entry.objectData.elementId != null && selectedElementIds.contains(entry.objectData.elementId)
      val active = entry.objectData.elementId != null && entry.objectData.elementId == selectedElementId
      val highlighted = entry.objectData.elementId != null && entry.objectData.elementId == highlightedElementId
      val solidColor = if (displayStyle == "solid") {
        // Revit-like working view: neutral paper-white surfaces with graphite
        // edges. Material/category colors remain available in Shaded.
        floatArrayOf(
          1.0f,
          1.0f,
          1.0f,
          1.0f,
        )
      } else {
        entry.baseColor
      }
      val color = when {
        active -> floatArrayOf(0.08f, 0.28f, 0.82f, 1f)
        selected -> floatArrayOf(0.18f, 0.45f, 0.95f, 1f)
        highlighted -> floatArrayOf(0.92f, 0.34f, 0.16f, 1f)
        else -> solidColor
      }
      entry.materialInstance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        color[0],
        color[1],
        color[2],
        color[3],
      )
      entry.edgeMaterialInstance?.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        if (active || selected) 0.08f else 0.035f,
        if (active || selected) 0.32f else 0.045f,
        if (active || selected) 0.95f else 0.055f,
        1.0f,
      )
    }
  }

  private fun destroyRenderables() {
    val engine = engine ?: run {
      renderables.clear()
      attachedEntities.clear()
      return
    }
    val scene = scene
    for (entry in renderables.values) {
      if (entry.attached) {
        scene?.removeEntity(entry.entity)
      }
      if (entry.edgeAttached) {
        entry.edgeEntity?.let { scene?.removeEntity(it) }
      }
      engine.destroyEntity(entry.entity)
      engine.destroyMaterialInstance(entry.materialInstance)
      entry.edgeEntity?.let { engine.destroyEntity(it) }
      entry.edgeMaterialInstance?.let { engine.destroyMaterialInstance(it) }
      engine.destroyVertexBuffer(entry.vertexBuffer)
      engine.destroyIndexBuffer(entry.indexBuffer)
      entry.edgeVertexBuffer?.let { engine.destroyVertexBuffer(it) }
      entry.edgeIndexBuffer?.let { engine.destroyIndexBuffer(it) }
      EntityManager.get().destroy(entry.entity)
      entry.edgeEntity?.let { EntityManager.get().destroy(it) }
    }
    renderables.clear()
    attachedEntities.clear()
  }

  private fun updateMetrics() {
    val entries = renderables.values.toList()
    val bounds = if (entries.isEmpty()) {
      SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
    } else {
      val allBounds = entries.map { it.bounds }
      allBounds.reduce { acc, sceneBounds ->
        SceneBounds(
          min = ScenePoint(
            min(acc.min.x, sceneBounds.min.x),
            min(acc.min.y, sceneBounds.min.y),
            min(acc.min.z, sceneBounds.min.z),
          ),
          max = ScenePoint(
            max(acc.max.x, sceneBounds.max.x),
            max(acc.max.y, sceneBounds.max.y),
            max(acc.max.z, sceneBounds.max.z),
          ),
        )
      }
    }
    sceneMetrics = FilamentSceneMetrics(
      bounds = bounds,
      objectCount = entries.size,
      vertexCount = entries.sumOf { it.vertexBuffer.vertexCount },
      indexCount = entries.sumOf { it.indexBuffer.indexCount },
    )
    val centerX = (bounds.min.x + bounds.max.x) * 0.5
    val centerY = (bounds.min.y + bounds.max.y) * 0.5
    val centerZ = (bounds.min.z + bounds.max.z) * 0.5
    orbitCenter = ScenePoint(centerX, centerY, centerZ)
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
    "renderables" to renderables.size,
    "vertices" to sceneMetrics.vertexCount,
    "indices" to sceneMetrics.indexCount,
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

  private fun Double.format(digits: Int): String = "%.${digits}f".format(this)

  private fun handleTouchEvent(event: MotionEvent): Boolean {
    scaleGestureDetector.onTouchEvent(event)
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        lastTouchX = event.x
        lastTouchY = event.y
        touchDownX = event.x
        touchDownY = event.y
        touchMoved = false
        touching = true
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        if (scaleGestureDetector.isInProgress) {
          touchMoved = true
          return true
        }
        if (touching) {
          val dx = event.x - lastTouchX
          val dy = event.y - lastTouchY
          if (kotlin.math.hypot(event.x - touchDownX, event.y - touchDownY) >
            resources.displayMetrics.density * 8f) {
            touchMoved = true
          }
          lastTouchX = event.x
          lastTouchY = event.y
          if (projectionMode == "topDown") {
            val metersPerPixel = (topDownZoom * 2.0) / max(renderSurface.height.toDouble(), 1.0)
            orbitCenter = orbitCenter.copy(
              x = orbitCenter.x - dx * metersPerPixel,
              z = orbitCenter.z + dy * metersPerPixel,
            )
          } else {
            orbitYawRadians -= dx * 0.01
            orbitPitchRadians = (orbitPitchRadians + dy * 0.01).coerceIn(Math.toRadians(0.1), Math.toRadians(88.0))
          }
          updateOrbitCamera()
          syncVisualOverlay()
          invalidate()
        }
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        if (event.actionMasked == MotionEvent.ACTION_UP && !touchMoved) {
          pickVisibleObject(event.x, event.y)
        }
        touching = false
        return true
      }
      else -> return true
    }
  }

  private fun pickVisibleObject(x: Float, y: Float) {
    val view = filamentView
    if (view == null) {
      onObjectTapped(selectionOverlay.pickElementAt(x, y, visibleKinds))
      return
    }
    // The ray is evaluated against Filament's live view/projection matrices,
    // therefore it remains correct after a native orbit. On the connected
    // MIUI tablet View.pick occasionally reported an unrelated renderable
    // after rotation; only use it when the ray has no geometric hit.
    val rayElementId = selectionOverlay.pickByLiveCameraRay(x, y, visibleKinds)
    if (rayElementId != null) {
      onObjectTapped(rayElementId)
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
    )
  }

  private fun configureCameraProjection() {
    val camera = camera ?: return
    val aspect = aspectRatio()
    // A fixed 10 cm near plane clips whole storeys as an orbit camera gets
    // close to a model. Keep it extremely close but scale it with distance;
    // the far plane remains bounded for depth precision on a campus.
    val near = (orbitDistance * 0.0015).coerceIn(0.002, 0.025)
    val bounds = sceneMetrics.bounds
    val sceneSpan = max(
      bounds.max.x - bounds.min.x,
      max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
    )
    val far = max(orbitDistance * 7.0 + sceneSpan * 2.5, 160.0)
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

  private fun minimumOrbitDistance(): Double {
    val bounds = sceneMetrics.bounds
    val span = max(
      bounds.max.x - bounds.min.x,
      max(bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z),
    )
    // Keep an orbit camera outside dense multi-storey geometry. This avoids
    // near-plane crossings and depth flicker while direct selection remains
    // available for close inspection.
    return max(span * 0.30, 1.75)
  }

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
      "wall" -> floatArrayOf(0.62f, 0.38f, 0.25f, 1f)
      "door" -> floatArrayOf(0.64f, 0.47f, 0.37f, 1f)
      "window" -> floatArrayOf(0.34f, 0.72f, 0.96f, 0.38f)
      "slab" -> floatArrayOf(0.57f, 0.63f, 0.71f, 1f)
      "floor" -> floatArrayOf(0.47f, 0.66f, 0.55f, 1f)
      "ceiling" -> floatArrayOf(0.78f, 0.82f, 0.87f, 1f)
      "roof" -> floatArrayOf(0.72f, 0.38f, 0.13f, 1f)
      "column" -> floatArrayOf(0.41f, 0.45f, 0.52f, 1f)
      "beam" -> floatArrayOf(0.30f, 0.36f, 0.42f, 1f)
      "stair" -> floatArrayOf(0.50f, 0.34f, 0.76f, 1f)
      "room" -> floatArrayOf(0.13f, 0.74f, 0.53f, 1f)
      else -> floatArrayOf(0.42f, 0.47f, 0.56f, 1f)
    }
  }

  private fun toVisualObject(objectData: SceneObject): NativeVisualObject {
    val points = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      objectData.mesh.positions.map(::toFilamentPoint)
    } else {
      boxCorners(objectData.bounds).map(::toFilamentPoint)
    }
    val triangles = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      objectData.mesh.indices.chunked(3).mapNotNull { group ->
        if (group.size == 3 && group.all { it in points.indices }) intArrayOf(group[0], group[1], group[2]) else null
      }
    } else {
      listOf(
        intArrayOf(0, 1, 2), intArrayOf(0, 2, 3), intArrayOf(4, 6, 5), intArrayOf(4, 7, 6),
        intArrayOf(0, 4, 5), intArrayOf(0, 5, 1), intArrayOf(1, 5, 6), intArrayOf(1, 6, 2),
        intArrayOf(2, 6, 7), intArrayOf(2, 7, 4), intArrayOf(3, 7, 4), intArrayOf(3, 4, 0),
      )
    }
    return NativeVisualObject(
      elementId = objectData.elementId,
      kind = normalizeKind(objectData.kind),
      selectable = objectData.selectable,
      points = points,
      triangles = triangles,
      featureEdges = meshFeatureEdges(points, triangles),
    )
  }

  private fun meshFeatureEdges(points: List<ScenePoint>, triangles: List<IntArray>): List<NativeVisualEdge> {
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
      val feature = uses.size == 1 || uses.zipWithNext().any { (first, second) ->
        normalDot(first.normal, second.normal) < 0.90
      }
      if (!feature) return@mapNotNull null
      val sharp = uses.size == 1 || uses.zipWithNext().any { (first, second) ->
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
  private var levels = emptyList<Pair<String, Double>>()
  private var sceneBounds = SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
  private var center = ScenePoint(0.0, 0.0, 0.0)
  private var yawRadians = 0.0
  private var pitchRadians = 0.0
  private var distance = 12.0
  private var topDownZoom = 8.0
  private var topDown = true
  private var perspective = false
  private var wireframe = false
  private var showObjectEdges = true
  private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    style = Paint.Style.STROKE
    color = Color.argb(155, 24, 39, 52)
    strokeWidth = context.resources.displayMetrics.density * 0.85f
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

  fun setVisualScene(
    value: List<NativeVisualObject>,
    levelValues: List<Pair<String, Double>>,
    bounds: SceneBounds,
  ) {
    // Keep coverage across every building at city scale. Sampling avoids line
    // soup but never makes a campus fall back to an unannotated old view.
    val stride = max(1, (value.size + 649) / 650)
    allObjects = value
    objects = value.filterIndexed { index, _ -> index % stride == 0 }
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
  fun pickByLiveCameraRay(x: Float, y: Float, visibleKinds: Set<String>): Long? {
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
    return nearestTriangleHit(origin, direction, visibleKinds)
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
    showObjectEdges = style == "wireframe"
    outline.color = when (style) {
      "wireframe" -> Color.argb(225, 18, 30, 42)
      "solid" -> Color.argb(170, 37, 51, 65)
      else -> Color.TRANSPARENT
    }
    outline.strokeWidth = resources.displayMetrics.density * if (wireframe) 1.45f else 1.6f
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
  ) {
    this.center = center
    this.yawRadians = yawRadians
    this.pitchRadians = pitchRadians
    this.distance = distance
    this.topDownZoom = topDownZoom
    this.topDown = topDown
    this.perspective = perspective
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    drawAuthoringEdges(canvas)
    val rect = rectangle ?: return
    val color = if (crossing) Color.rgb(245, 158, 11) else Color.rgb(37, 99, 235)
    fill.color = Color.argb(40, Color.red(color), Color.green(color), Color.blue(color))
    stroke.color = color
    canvas.drawRect(rect, fill)
    canvas.drawRect(rect, stroke)
  }

  private fun drawAuthoringEdges(canvas: Canvas) {
    if (width <= 1 || height <= 1) return
    for (objectData in objects) {
      val projected = objectData.points.map(::project)
      val selected = objectData.elementId != null && selectedIds.contains(objectData.elementId)
      if (!showObjectEdges && !selected) continue
      val edgePaint = if (selected) selectedOutline else outline
      for (edge in objectData.featureEdges) {
        if (!wireframe && !selected && !isVisibleSolidEdge(objectData, edge)) continue
        val first = projected.getOrNull(edge.first)
        val second = projected.getOrNull(edge.second)
        if (first != null && second != null) {
          canvas.drawLine(first.x, first.y, second.x, second.y, edgePaint)
        }
      }
    }
    if (!topDown) {
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
