package com.example.viewer_flutter

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.view.View
import org.json.JSONArray
import org.json.JSONObject
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.max
import kotlin.math.min

internal data class ScenePoint(val x: Double, val y: Double, val z: Double)
internal data class SceneBounds(val min: ScenePoint, val max: ScenePoint)
internal data class SceneMesh(
  val positions: List<ScenePoint>,
  val indices: List<Int>,
)

internal data class SceneObject(
  val elementId: Long?,
  val kind: String,
  val levelId: Long?,
  val selectable: Boolean,
  val visibleByDefault: Boolean,
  val revision: Int,
  val bounds: SceneBounds,
  val mesh: SceneMesh,
  val materialCategory: String,
)

internal data class SceneState(
  val sceneVersion: Int,
  val units: String,
  val coordinateSystem: String,
  val objectCount: Int,
  val vertexCount: Int,
  val indexCount: Int,
  val objects: List<SceneObject>,
)

internal fun normalizeKind(value: String): String {
  val trimmed = value.trim().lowercase()
  return when (trimmed) {
    "floorsystem" -> "floor"
    "ceilingsystem" -> "ceiling"
    "opening" -> "door"
    else -> if (trimmed.isEmpty()) "unknown" else trimmed
  }
}

internal fun toSceneState(payload: Any?): SceneState? {
  if (payload == null) {
    return null
  }
  val root = normalizeScenePayload(payload) ?: return null
  val warnings = mutableListOf<String>()
  val errors = mutableListOf<String>()
  val objects = mutableListOf<SceneObject>()
  val rawObjects = root["objects"]
  if (rawObjects is List<*>) {
    for (entry in rawObjects) {
      val objectMap = entry as? Map<*, *> ?: continue
      val mesh = parseMesh(objectMap["mesh"], warnings)
      val bounds = parseBounds(objectMap["bounds"]) ?: boundsFromPoints(mesh.positions)
      objects.add(
        SceneObject(
          elementId = toLong(objectMap["element_id"]),
          kind = toStringValue(objectMap["kind"], "Unknown"),
          levelId = toLong(objectMap["level_id"]),
          selectable = objectMap["selectable"] != false,
          visibleByDefault = objectMap["visible_by_default"] != false,
          revision = toInt(objectMap["revision"]) ?: 0,
          bounds = if (isFinite(bounds)) bounds else SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0)),
          mesh = mesh,
          materialCategory = toStringValue(objectMap["material_category"], "generic"),
        )
      )
    }
  } else {
    errors.add("Missing object list.")
  }
  val derivedVertexCount = objects.sumOf { it.mesh.positions.size }
  val derivedIndexCount = objects.sumOf { it.mesh.indices.size }
  val sceneVersion = toInt(root["scene_version"]) ?: toInt(root["sceneVersion"]) ?: 1
  val objectCount = toInt(root["object_count"]) ?: toInt(root["objectCount"]) ?: objects.size
  val vertexCount = toInt(root["vertex_count"]) ?: toInt(root["vertexCount"]) ?: derivedVertexCount
  val indexCount = toInt(root["index_count"]) ?: toInt(root["indexCount"]) ?: derivedIndexCount
  if (warnings.isNotEmpty()) {
    // Intentionally left as a debug hook for the skeleton; Dart side owns user-facing diagnostics.
  }
  if (errors.isNotEmpty()) {
    return null
  }
  return SceneState(
    sceneVersion = sceneVersion,
    units = toStringValue(root["units"], "meters"),
    coordinateSystem = toStringValue(root["coordinate_system"] ?: root["coordinateSystem"], "X/Y plan, Z up"),
    objectCount = objectCount,
    vertexCount = vertexCount,
    indexCount = indexCount,
    objects = objects,
  )
}

private fun normalizeScenePayload(payload: Any?): Map<String, Any?>? {
  return when (payload) {
    is Map<*, *> -> payload.entries.associate { (key, value) ->
      key.toString() to normalizeJsonValue(value)
    }
    is String -> try {
      val parsed = JSONObject(payload)
      parsed.keys().asSequence().associateWith { key -> normalizeJsonValue(parsed.get(key)) }
    } catch (_: Exception) {
      null
    }
    else -> null
  }
}

private fun normalizeJsonValue(value: Any?): Any? {
  return when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> value.keys().asSequence().associateWith { key -> normalizeJsonValue(value.get(key)) }
    is JSONArray -> List(value.length()) { index -> normalizeJsonValue(value.get(index)) }
    is Map<*, *> -> value.entries.associate { (key, entryValue) -> key.toString() to normalizeJsonValue(entryValue) }
    is List<*> -> value.map { normalizeJsonValue(it) }
    else -> value
  }
}

internal fun parseMesh(payload: Any?, warnings: MutableList<String>): SceneMesh {
  if (payload !is Map<*, *>) {
    warnings.add("Missing mesh payload.")
    return SceneMesh(emptyList(), emptyList())
  }
  val positions = mutableListOf<ScenePoint>()
  val rawPositions = payload["positions"]
  if (rawPositions is List<*>) {
    for (entry in rawPositions) {
      val point = parsePoint(entry)
      if (point != null) {
        positions.add(point)
      }
    }
  }
  val indices = mutableListOf<Int>()
  val rawIndices = payload["indices"]
  if (rawIndices is List<*>) {
    for (entry in rawIndices) {
      val number = toDouble(entry)
      if (number != null) {
        indices.add(number.toInt())
      }
    }
  }
  return SceneMesh(positions = positions, indices = indices)
}

internal fun parsePoint(payload: Any?): ScenePoint? {
  val map = payload as? Map<*, *> ?: return null
  val x = toDouble(map["x"]) ?: return null
  val y = toDouble(map["y"]) ?: return null
  val z = toDouble(map["z"]) ?: return null
  return ScenePoint(x, y, z)
}

internal fun parseBounds(payload: Any?): SceneBounds? {
  val map = payload as? Map<*, *> ?: return null
  val min = parsePoint(map["min"]) ?: return null
  val max = parsePoint(map["max"]) ?: return null
  return SceneBounds(min, max)
}

internal fun boundsFromPoints(points: List<ScenePoint>): SceneBounds {
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
  return SceneBounds(ScenePoint(minX, minY, minZ), ScenePoint(maxX, maxY, maxZ))
}

internal fun isFinite(bounds: SceneBounds): Boolean {
  return listOf(
    bounds.min.x, bounds.min.y, bounds.min.z, bounds.max.x, bounds.max.y, bounds.max.z
  ).all { it.isFinite() }
}

internal fun toDouble(payload: Any?): Double? {
  return when (payload) {
    is Int -> payload.toDouble()
    is Long -> payload.toDouble()
    is Double -> if (payload.isFinite()) payload else null
    is Float -> if (payload.isFinite()) payload.toDouble() else null
    is String -> payload.toDoubleOrNull()
    else -> null
  }
}

internal fun toInt(payload: Any?): Int? {
  return when (payload) {
    is Int -> payload
    is Long -> payload.toInt()
    is Double -> if (payload.isFinite()) payload.toInt() else null
    is String -> payload.toIntOrNull()
    else -> null
  }
}

internal fun toLong(payload: Any?): Long? {
  return when (payload) {
    is Int -> payload.toLong()
    is Long -> payload
    is Double -> if (payload.isFinite()) payload.toLong() else null
    is String -> payload.toLongOrNull()
    else -> null
  }
}

internal fun toStringValue(payload: Any?, fallback: String): String {
  return when (payload) {
    is String -> if (payload.isNotEmpty()) payload else fallback
    else -> fallback
  }
}

internal class RenderScenePlatformViewFactory(
  private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val initialScene = toSceneState(args)
    return RenderScenePlatformView(context, messenger, viewId, initialScene)
  }

  companion object {
    const val BRIDGE_VIEW_TYPE = "tbe/render_scene_view"
  }
}

internal class RenderScenePlatformView(
  context: Context,
  messenger: BinaryMessenger,
  viewId: Int,
  initialScene: SceneState?,
) : PlatformView, MethodChannel.MethodCallHandler {
  private val channel = MethodChannel(messenger, "tbe/render_scene_view_$viewId")
  private val view = RenderSceneFilamentHostView(context, initialScene)

  init {
    channel.setMethodCallHandler(this)
  }

  override fun getView(): View = view

  override fun dispose() {
    channel.setMethodCallHandler(null)
    view.disposeResources()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "loadRenderSceneJson", "loadRenderScene" -> {
        view.loadScene(toSceneState(call.arguments))
        result.success(null)
      }

      "clearScene" -> {
        view.clearScene()
        result.success(null)
      }

      "fitCamera" -> {
        view.fitCamera()
        result.success(null)
      }

      "setVisibleKinds" -> {
        val kinds = (call.arguments as? List<*>)?.mapNotNull { it as? String }?.map { normalizeKind(it) }?.toSet()
        if (kinds != null) {
          view.setVisibleKinds(kinds)
        }
        result.success(null)
      }

      "setProjectionMode" -> {
        view.setProjectionMode(call.arguments as? String ?: "topDown")
        result.success(null)
      }

      "setOrbitProjectionStyle" -> {
        view.setOrbitProjectionStyle(call.arguments as? String ?: "orthographic")
        result.success(null)
      }

      "setDisplayStyle" -> {
        view.setDisplayStyle(call.arguments as? String ?: "solid")
        result.success(null)
      }

      "selectElement" -> {
        view.selectElement(call.arguments)
        result.success(null)
      }

      "highlightElement" -> {
        view.highlightElement(call.arguments)
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }
}

private class RenderSceneCanvasView(context: Context) : View(context) {
  private var scene: SceneState? = null
  private var visibleKinds: Set<String> = setOf(
    "wall", "door", "window", "slab", "floor", "ceiling", "roof", "column", "beam", "stair", "room"
  )
  private var selectedElementId: Long? = null
  private var highlightedElementId: Long? = null

  fun loadScene(newScene: SceneState?) {
    scene = newScene
    fitCamera()
  }

  fun clearScene() {
    scene = null
    invalidate()
  }

  fun fitCamera() {
    invalidate()
  }

  fun setVisibleKinds(kinds: Set<String>) {
    visibleKinds = kinds
    invalidate()
  }

  fun selectElement(elementId: Any?) {
    selectedElementId = toLong(elementId)
    invalidate()
  }

  fun highlightElement(elementId: Any?) {
    highlightedElementId = toLong(elementId)
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    canvas.drawColor(Color.rgb(243, 247, 244))
    val currentScene = scene
    if (currentScene == null) {
      drawMessage(canvas, "Load a RenderScene to preview the native viewport skeleton.")
      return
    }

    val filteredObjects = currentScene.objects.filter { visibleKinds.contains(normalizeKind(it.kind)) }
    if (filteredObjects.isEmpty()) {
      drawMessage(canvas, "No visible objects after filtering.")
      return
    }

    val fit = computeFit(filteredObjects, width.toFloat(), height.toFloat())
    drawGrid(canvas, fit)
    drawAxes(canvas, fit)

    for (sceneObject in filteredObjects) {
      val isSelected = sceneObject.elementId != null && sceneObject.elementId == selectedElementId
      val isHighlighted = sceneObject.elementId != null && sceneObject.elementId == highlightedElementId
      drawObject(canvas, sceneObject, fit, isSelected, isHighlighted)
    }
  }

  private fun drawMessage(canvas: Canvas, message: String) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.DKGRAY
      textSize = 32f
    }
    canvas.drawText(message, 32f, (height / 2f).coerceAtLeast(48f), paint)
  }

  private fun drawAxes(canvas: Canvas, fit: FitTransform) {
    val origin = fit.project(ScenePoint(0.0, 0.0, 0.0))
    val xAxis = fit.project(ScenePoint(1.0, 0.0, 0.0))
    val yAxis = fit.project(ScenePoint(0.0, 1.0, 0.0))
    val zAxis = fit.project(ScenePoint(0.0, 0.0, 1.0))
    val xPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.RED; strokeWidth = 3f }
    val yPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.GREEN; strokeWidth = 3f }
    val zPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLUE; strokeWidth = 3f }
    canvas.drawLine(origin.x, origin.y, xAxis.x, xAxis.y, xPaint)
    canvas.drawLine(origin.x, origin.y, yAxis.x, yAxis.y, yPaint)
    canvas.drawLine(origin.x, origin.y, zAxis.x, zAxis.y, zPaint)
  }

  private fun drawGrid(canvas: Canvas, fit: FitTransform) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.argb(60, 148, 163, 184)
      strokeWidth = 1f
    }
    val bounds = fit.sceneBounds
    var x = kotlin.math.floor(bounds.min.x)
    while (x <= kotlin.math.ceil(bounds.max.x)) {
      val start = fit.project(ScenePoint(x, bounds.min.y, 0.0))
      val end = fit.project(ScenePoint(x, bounds.max.y, 0.0))
      canvas.drawLine(start.x, start.y, end.x, end.y, paint)
      x += 1.0
    }
    var y = kotlin.math.floor(bounds.min.y)
    while (y <= kotlin.math.ceil(bounds.max.y)) {
      val start = fit.project(ScenePoint(bounds.min.x, y, 0.0))
      val end = fit.project(ScenePoint(bounds.max.x, y, 0.0))
      canvas.drawLine(start.x, start.y, end.x, end.y, paint)
      y += 1.0
    }
  }

  private fun drawObject(
    canvas: Canvas,
    objectData: SceneObject,
    fit: FitTransform,
    selected: Boolean,
    highlighted: Boolean,
  ) {
    val color = colorForKind(normalizeKind(objectData.kind))
    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      strokeWidth = if (selected || highlighted) 4f else 2f
      this.color = when {
        selected -> Color.rgb(29, 78, 216)
        highlighted -> Color.rgb(180, 35, 24)
        else -> color
      }
    }
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.FILL
      this.color = adjustAlpha(color, if (selected || highlighted) 70 else 36)
    }

    val paths = buildWireframePaths(objectData, fit)
    for (path in paths) {
      canvas.drawPath(path, fill)
      canvas.drawPath(path, stroke)
    }

    val label = "${prettyLabel(objectData.kind)} ${objectData.elementId ?: ""}".trim()
    val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      this.color = Color.DKGRAY
      textSize = 26f
      typeface = android.graphics.Typeface.DEFAULT_BOLD
    }
    val textPoint = fit.project(objectData.bounds.max)
    canvas.drawText(label, textPoint.x + 8f, textPoint.y - 8f, labelPaint)
  }

  private fun buildWireframePaths(objectData: SceneObject, fit: FitTransform): List<Path> {
    val points = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      objectData.mesh.positions
    } else {
      boundsCorners(objectData.bounds)
    }
    val projected = points.map { fit.project(it) }
    val edges = if (objectData.mesh.positions.isNotEmpty() && objectData.mesh.indices.size >= 3) {
      triangleEdges(objectData.mesh.indices)
    } else {
      listOf(
        0 to 1, 1 to 2, 2 to 3, 3 to 0,
        4 to 5, 5 to 6, 6 to 7, 7 to 4,
        0 to 4, 1 to 5, 2 to 6, 3 to 7
      )
    }
    val path = Path()
    for ((start, end) in edges) {
      if (start >= projected.size || end >= projected.size) {
        continue
      }
      val a = projected[start]
      val b = projected[end]
      path.moveTo(a.x, a.y)
      path.lineTo(b.x, b.y)
    }
    return listOf(path)
  }

  private fun triangleEdges(indices: List<Int>): List<Pair<Int, Int>> {
    val edges = linkedSetOf<Pair<Int, Int>>()
    var index = 0
    while (index + 2 < indices.size) {
      val a = indices[index]
      val b = indices[index + 1]
      val c = indices[index + 2]
      edges.add(normalizeEdge(a, b))
      edges.add(normalizeEdge(b, c))
      edges.add(normalizeEdge(c, a))
      index += 3
    }
    return edges.toList()
  }

  private fun normalizeEdge(a: Int, b: Int): Pair<Int, Int> {
    return if (a < b) a to b else b to a
  }

  private fun boundsCorners(bounds: SceneBounds): List<ScenePoint> {
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

  private fun computeFit(objects: List<SceneObject>, width: Float, height: Float): FitTransform {
    var projectedBounds = RectF()
    var first = true
    val points = mutableListOf<PointF>()
    for (objectData in objects) {
      val corners = if (objectData.mesh.positions.isNotEmpty()) objectData.mesh.positions else boundsCorners(objectData.bounds)
      for (point in corners) {
        val projected = project(point)
        points.add(projected)
        if (first) {
          projectedBounds = RectF(projected.x, projected.y, projected.x, projected.y)
          first = false
        } else {
          projectedBounds.left = min(projectedBounds.left, projected.x)
          projectedBounds.top = min(projectedBounds.top, projected.y)
          projectedBounds.right = max(projectedBounds.right, projected.x)
          projectedBounds.bottom = max(projectedBounds.bottom, projected.y)
        }
      }
    }
    if (first) {
      projectedBounds = RectF(0f, 0f, 1f, 1f)
    }
    val padding = 48f
    val sceneWidth = max(projectedBounds.width(), 1f)
    val sceneHeight = max(projectedBounds.height(), 1f)
    val scale = min(
      (width - padding * 2f) / sceneWidth,
      (height - padding * 2f) / sceneHeight,
    ).coerceAtLeast(0.05f)
    return FitTransform(
      sceneBounds = boundsFromPoints(objects.flatMap {
        listOf(
          it.bounds.min, it.bounds.max
        )
      }),
      sourceBounds = projectedBounds,
      width = width,
      height = height,
      padding = padding,
      scale = scale,
    )
  }

  private fun project(point: ScenePoint): PointF {
    val x = (point.x - point.y).toFloat()
    val y = (((point.x + point.y) * 0.5) - point.z).toFloat()
    return PointF(x, y)
  }

  private fun colorForKind(kind: String): Int {
    return when (kind) {
      "wall" -> Color.rgb(124, 152, 133)
      "door" -> Color.rgb(141, 110, 99)
      "window" -> Color.rgb(76, 139, 245)
      "slab" -> Color.rgb(148, 163, 184)
      "roof" -> Color.rgb(180, 83, 9)
      "column" -> Color.rgb(107, 114, 128)
      "beam" -> Color.rgb(75, 85, 99)
      "stair" -> Color.rgb(126, 87, 194)
      "room" -> Color.rgb(16, 185, 129)
      else -> Color.rgb(100, 116, 139)
    }
  }

  private fun prettyLabel(kind: String): String {
    return when (normalizeKind(kind)) {
      "wall" -> "Wall"
      "door" -> "Door"
      "window" -> "Window"
      "slab" -> "Slab"
      "floor" -> "Floor"
      "ceiling" -> "Ceiling"
      "roof" -> "Roof"
      "column" -> "Column"
      "beam" -> "Beam"
      "stair" -> "Stair"
      "room" -> "Room"
      else -> kind
    }
  }

  private fun adjustAlpha(color: Int, alpha: Int): Int {
    return (alpha.coerceIn(0, 255) shl 24) or (color and 0x00FFFFFF)
  }
}

private data class FitTransform(
  val sceneBounds: SceneBounds,
  val sourceBounds: RectF,
  val width: Float,
  val height: Float,
  val padding: Float,
  val scale: Float,
) {
  fun project(point: ScenePoint): PointF {
    val projected = PointF((point.x - point.y).toFloat(), (((point.x + point.y) * 0.5) - point.z).toFloat())
    val x = padding + (projected.x - sourceBounds.left) * scale
    val y = padding + (projected.y - sourceBounds.top) * scale
    return PointF(x, y)
  }
}
