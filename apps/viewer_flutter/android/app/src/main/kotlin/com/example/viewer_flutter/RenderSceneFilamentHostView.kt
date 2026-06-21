package com.example.viewer_flutter

import android.content.Context
import android.graphics.Color
import android.view.MotionEvent
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
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
material {
    name : RenderSceneFlatColor,
    shadingModel : unlit,
    culling : none,
    doubleSided : true,
    featureLevel : 0
}

fragment {
    void material(inout MaterialInputs material) {
        prepareMaterial(material);
        material.baseColor = materialParams.baseColor;
    }
}
"""

private data class FilamentRenderableEntry(
  val objectData: SceneObject,
  val entity: Int,
  val vertexBuffer: VertexBuffer,
  val indexBuffer: IndexBuffer,
  val material: Material,
  val materialInstance: MaterialInstance,
  val baseColor: FloatArray,
  val bounds: SceneBounds,
  var attached: Boolean = false,
)

private data class FilamentSceneMetrics(
  val bounds: SceneBounds,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
)

internal class RenderSceneFilamentHostView(
  context: Context,
  initialScene: SceneState? = null,
) : FrameLayout(context), UiHelper.RendererCallback, Choreographer.FrameCallback {
  companion object {
    init {
      Filament.init()
      MaterialBuilder.init()
    }
  }

  private val renderSurface = TextureView(context)
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
        orbitDistance = nextDistance.coerceIn(2.0, 250.0)
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
  private var swapChain: SwapChain? = null
  private var sceneMetrics = FilamentSceneMetrics(
    bounds = SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0)),
    objectCount = 0,
    vertexCount = 0,
    indexCount = 0,
  )
  private var currentScene: SceneState? = initialScene
  private var selectedElementId: Long? = null
  private var highlightedElementId: Long? = null
  private var framePosted = false
  private var surfaceReady = false
  private var materialBuilderReady = false
  private var material: Material? = null
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
  private var touching = false

  init {
    setBackgroundColor(Color.rgb(243, 247, 244))
    addView(
      renderSurface,
      LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
    )
    addView(
      statusView,
      LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.START or Gravity.BOTTOM),
    )
    statusView.setPadding(24, 16, 24, 16)
    statusView.setTextColor(Color.rgb(17, 24, 39))
    statusView.setBackgroundColor(Color.argb(180, 255, 255, 255))
    statusView.typeface = Typeface.MONOSPACE
    statusView.textSize = 12f
    statusView.text = DEFAULT_RENDERER_STATUS

    uiHelper.renderCallback = this
    uiHelper.attachTo(renderSurface)
    renderSurface.isClickable = true
    renderSurface.setOnTouchListener { _, event -> handleTouchEvent(event) }

    try {
      val filamentEngine = Engine.create(Engine.Backend.OPENGL)
      engine = filamentEngine
      renderer = filamentEngine.createRenderer()
      scene = filamentEngine.createScene()
      filamentView = filamentEngine.createView()
      camera = filamentEngine.createCamera(EntityManager.get().create())
      filamentView?.scene = scene
      filamentView?.camera = camera
      filamentView?.viewport = Viewport(0, 0, 1, 1)
      scene?.skybox = Skybox.Builder().color(0.96f, 0.97f, 0.98f, 1.0f).build(filamentEngine)
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
    highlightedElementId = null
    destroyRenderables()
    updateMetrics()
    updateStatus(message)
    Log.i(TAG, message)
    invalidate()
  }

  fun fitCamera() {
    val camera = camera ?: return
    val metrics = sceneMetrics
    val bounds = transformBounds(metrics.bounds)
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
    updateStatus("Camera fitted to ${metrics.objectCount} objects.")
    invalidate()
  }

  fun setProjectionMode(mode: String) {
    projectionMode = mode
    configureCameraProjection()
    updateOrbitCamera()
    updateStatus()
    invalidate()
  }

  fun setOrbitProjectionStyle(style: String) {
    orbitProjectionStyle = style
    configureCameraProjection()
    updateOrbitCamera()
    updateStatus()
    invalidate()
  }

  fun setDisplayStyle(style: String) {
    displayStyle = style
    updateStatus(if (style == "wireframe") "Filament wireframe not yet enabled. Showing solid." else null)
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
    refreshTintState()
    updateStatus()
    invalidate()
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
    fitCamera()
  }

  override fun doFrame(frameTimeNanos: Long) {
    framePosted = false
    val renderer = renderer
    val view = filamentView
    val swapChain = swapChain
    if (renderer != null && view != null && swapChain != null && renderer.beginFrame(swapChain, frameTimeNanos)) {
      renderer.render(view)
      renderer.endFrame()
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
    engine?.destroy()
    swapChain = null
    renderer = null
    scene = null
    filamentView = null
    camera = null
    engine = null
    material = null
    materialBuilderReady = false
  }

  private fun buildRuntimeMaterial(): Boolean {
    val engine = engine ?: return false
    return try {
      val packageData: MaterialPackage = MaterialBuilder()
        .name("RenderSceneFlatColor")
        .shading(MaterialBuilder.Shading.UNLIT)
        .culling(MaterialBuilder.CullingMode.NONE)
        .doubleSided(true)
        .uniformParameter(MaterialBuilder.UniformType.FLOAT4, "baseColor")
        .material(FLAT_COLOR_MAT)
        .targetApi(MaterialBuilder.TargetApi.OPENGL)
        .platform(MaterialBuilder.Platform.MOBILE)
        .optimization(MaterialBuilder.Optimization.NONE)
        .build(engine)

      if (!packageData.isValid) {
        statusMessage = "Filament material build returned an invalid package."
        updateStatus()
        return false
      }

      val packageBuffer = packageData.buffer.duplicate()
      packageBuffer.rewind()
      material = Material.Builder()
        .payload(packageBuffer, packageBuffer.remaining())
        .build(engine)
      true
    } catch (error: Throwable) {
      statusMessage = "Filament material build failed: ${error.message ?: error::class.java.simpleName}"
      Log.e(TAG, statusMessage, error)
      updateStatus()
      false
    }
  }

  private fun rebuildScene() {
    destroyRenderables()
    val scene = scene ?: return
    val sceneState = currentScene ?: return
    if (material == null && materialBuilderReady) {
      buildRuntimeMaterial()
    }
    val engine = engine ?: return
    val material = material ?: run {
      statusMessage = "Filament material unavailable."
      Log.w(TAG, statusMessage)
      updateStatus()
      return
    }
    val filteredObjects = sceneState.objects
      .filter { visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(it.kind)) }
    val objects = if (filteredObjects.isNotEmpty()) filteredObjects else sceneState.objects
    if (filteredObjects.isEmpty() && sceneState.objects.isNotEmpty()) {
      Log.w(TAG, "All RenderScene objects were filtered out by kind visibility; rendering fallback set.")
    }

    for (objectData in objects) {
      val entry = createRenderable(engine, material, objectData) ?: continue
      renderables[objectData.elementId ?: renderables.size.toLong() + 1L] = entry
      scene.addEntity(entry.entity)
      entry.attached = true
      attachedEntities.add(entry.entity)
    }
    updateMetrics()
  }

  private fun createRenderable(
    engine: Engine,
    sharedMaterial: Material,
    objectData: SceneObject,
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
    val bounds = transformBounds(geometry.bounds)
    RenderableManager.Builder(1)
      .boundingBox(
        Box(
          bounds.min.x.toFloat(),
          bounds.min.y.toFloat(),
          bounds.min.z.toFloat(),
          bounds.max.x.toFloat(),
          bounds.max.y.toFloat(),
          bounds.max.z.toFloat(),
        )
      )
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

    val indexData = IntBuffer.allocate(triangles.size * 3)
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

  private fun syncVisibility() {
    val scene = scene ?: return
    for (entry in renderables.values) {
      val visible = visibleKinds.isEmpty() || visibleKinds.contains(normalizeKind(entry.objectData.kind))
      if (visible && !entry.attached) {
        scene.addEntity(entry.entity)
        entry.attached = true
      } else if (!visible && entry.attached) {
        scene.removeEntity(entry.entity)
        entry.attached = false
      }
    }
  }

  private fun refreshTintState() {
    for (entry in renderables.values) {
      val selected = entry.objectData.elementId != null && entry.objectData.elementId == selectedElementId
      val highlighted = entry.objectData.elementId != null && entry.objectData.elementId == highlightedElementId
      val color = when {
        selected -> floatArrayOf(0.18f, 0.45f, 0.95f, 1f)
        highlighted -> floatArrayOf(0.92f, 0.34f, 0.16f, 1f)
        else -> entry.baseColor
      }
      entry.materialInstance.setParameter(
        "baseColor",
        Colors.RgbaType.LINEAR,
        color[0],
        color[1],
        color[2],
        color[3],
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
      engine.destroyEntity(entry.entity)
      engine.destroyMaterialInstance(entry.materialInstance)
      engine.destroyVertexBuffer(entry.vertexBuffer)
      engine.destroyIndexBuffer(entry.indexBuffer)
      EntityManager.get().destroy(entry.entity)
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
    }
    statusMessage = status
    statusView.text = status
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
        touching = true
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        if (scaleGestureDetector.isInProgress) {
          return true
        }
        if (touching) {
          val dx = event.x - lastTouchX
          val dy = event.y - lastTouchY
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
          invalidate()
        }
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        touching = false
        return true
      }
      else -> return true
    }
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
  }

  private fun configureCameraProjection() {
    val camera = camera ?: return
    val aspect = aspectRatio()
    val far = max(orbitDistance * 60.0, 500.0)
    if (projectionMode == "topDown" || orbitProjectionStyle == "orthographic") {
      val halfHeight = if (projectionMode == "topDown") topDownZoom else max(orbitDistance * 0.6, 2.0)
      val halfWidth = halfHeight * aspect
      camera.setProjection(
        Camera.Projection.ORTHO,
        -halfWidth,
        halfWidth,
        -halfHeight,
        halfHeight,
        0.1,
        far,
      )
      return
    }

    camera.setProjection(45.0, aspect, 0.1, far, Camera.Fov.VERTICAL)
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
      "wall" -> floatArrayOf(0.52f, 0.63f, 0.56f, 1f)
      "door" -> floatArrayOf(0.64f, 0.47f, 0.37f, 1f)
      "window" -> floatArrayOf(0.31f, 0.56f, 0.94f, 1f)
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

  private data class GeometryData(
    val vertexCount: Int,
    val indexCount: Int,
    val vertexData: ByteBuffer,
    val indexData: IntBuffer,
    val bounds: SceneBounds,
  )
}
