package com.example.viewer_flutter

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** A topology edge consumed by the Filament line-ribbon pass. */
internal data class NativeVisualEdge(
  val first: Int,
  val second: Int,
  val triangleIndices: IntArray,
  val sharp: Boolean,
  val primitiveCenter: ScenePoint? = null,
  /** Optional per-primitive wall axis used by the native-cache edge pass. */
  val wallAxis: WallAxis? = null,
)

internal data class WallAxis(
  val start: ScenePoint,
  val end: ScenePoint,
)

/**
 * Pure mesh-topology operations used by the viewport edge pipeline.
 *
 * This layer deliberately knows nothing about Filament entities, camera state,
 * scene lifecycle or mutable upload budgets. Keeping topology here makes it
 * possible to reason about seams and architectural contours independently of
 * the renderer host.
 */
internal object RenderSceneEdgeTopology {
  fun featureEdges(
    points: List<ScenePoint>,
    triangles: List<IntArray>,
    creaseDotThreshold: Double = 0.90,
    includeBoundaryEdges: Boolean = true,
  ): List<NativeVisualEdge> {
    if (points.isEmpty() || triangles.isEmpty()) return emptyList()

    data class PointKey(val x: Long, val y: Long, val z: Long)
    data class Edge(val first: Int, val second: Int)
    data class EdgeUse(
      val normal: DoubleArray,
      val firstRaw: Int,
      val secondRaw: Int,
      val triangleIndex: Int,
    )

    // Render meshes often duplicate vertices across face boundaries. Weld by
    // position before classifying edges, otherwise every triangle diagonal can
    // become an apparent architectural line.
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
      if (triangle.size != 3 || triangle.any { it !in points.indices }) continue
      val normal = triangleNormal(
        points[triangle[0]],
        points[triangle[1]],
        points[triangle[2]],
      )
      if (normal.all { abs(it) <= 1.0e-9 }) continue
      for ((first, second) in arrayOf(
        triangle[0] to triangle[1],
        triangle[1] to triangle[2],
        triangle[2] to triangle[0],
      )) {
        val canonicalFirst = canonicalIndices[first]
        val canonicalSecond = canonicalIndices[second]
        if (canonicalFirst == canonicalSecond) continue
        val edge = if (canonicalFirst < canonicalSecond) {
          Edge(canonicalFirst, canonicalSecond)
        } else {
          Edge(canonicalSecond, canonicalFirst)
        }
        usesByEdge.getOrPut(edge) { mutableListOf() }
          .add(EdgeUse(normal, first, second, triangleIndex))
      }
    }

    return usesByEdge.values.mapNotNull { uses ->
      val feature = (includeBoundaryEdges && uses.size == 1) || uses.zipWithNext().any { (first, second) ->
        // Imported/generated faces can have opposite winding while remaining
        // coplanar. The sign of a normal is not a geometric crease.
        kotlin.math.abs(normalDot(first.normal, second.normal)) < creaseDotThreshold
      }
      if (!feature) return@mapNotNull null
      val sharp = (includeBoundaryEdges && uses.size == 1) || uses.zipWithNext().any { (first, second) ->
        kotlin.math.abs(normalDot(first.normal, second.normal)) < 0.35
      }
      NativeVisualEdge(
        first = uses.first().firstRaw,
        second = uses.first().secondRaw,
        triangleIndices = uses.map { it.triangleIndex }.distinct().toIntArray(),
        sharp = sharp,
      )
    }
  }

  /**
   * Keep only edges that live on a wall-facing surface.
   *
   * Layered wall meshes also contain real edges running through the wall
   * thickness (the sill/jamb return and end-cap edges). Those are useful in a
   * section, but in an oblique 3D view they project as stray diagonal strokes
   * over the facade. A wall-facing edge is vertical or is a declared opening
   * contour that follows the wall axis in plan. Object-local top/bottom
   * boundaries are omitted because multi-storey walls are split into one
   * object per level.
   */
  fun wallFaceEdges(
    points: List<ScenePoint>,
    edges: List<NativeVisualEdge>,
    axisStart: ScenePoint,
    axisEnd: ScenePoint,
  ): List<NativeVisualEdge> {
    val axisX = axisEnd.x - axisStart.x
    val axisZ = axisEnd.z - axisStart.z
    val axisLength = sqrt(axisX * axisX + axisZ * axisZ)
    if (!axisLength.isFinite() || axisLength <= 1.0e-9) return edges
    val directionX = axisX / axisLength
    val directionZ = axisZ / axisLength
    val boundaryTolerance = 0.03
    fun pointKey(point: ScenePoint): String =
      "${kotlin.math.round(point.x * 10000.0)}:${kotlin.math.round(point.y * 10000.0)}:${kotlin.math.round(point.z * 10000.0)}"
    val verticalEdgePoints = edges.asSequence()
      .filter { edge ->
        val first = points.getOrNull(edge.first) ?: return@filter false
        val second = points.getOrNull(edge.second) ?: return@filter false
        val horizontalLength = sqrt(
          (second.x - first.x) * (second.x - first.x) +
            (second.z - first.z) * (second.z - first.z),
        )
        val verticalLength = abs(second.y - first.y)
        verticalLength > 0.05 && verticalLength >= horizontalLength * 3.0
      }
      .flatMap { edge -> sequenceOf(edge.first, edge.second) }
      .mapNotNull { points.getOrNull(it)?.let(::pointKey) }
      .toSet()
    val fallbackOpeningEdgeLength = min(2.5, axisLength * 0.45)
    return edges.filter { edge ->
      val first = points.getOrNull(edge.first) ?: return@filter false
      val second = points.getOrNull(edge.second) ?: return@filter false
      val deltaX = second.x - first.x
      val deltaY = second.y - first.y
      val deltaZ = second.z - first.z
      val horizontalLength = sqrt(deltaX * deltaX + deltaZ * deltaZ)
      val verticalLength = abs(deltaY)
      val vertical = verticalLength > 0.05 &&
        verticalLength >= horizontalLength * 3.0
      val followsWall = horizontalLength > 0.05 &&
        verticalLength <= horizontalLength * 0.20 &&
        abs((deltaX * directionX + deltaZ * directionZ) / horizontalLength) >= 0.96
      if (vertical) return@filter true
      if (!followsWall) return@filter false

      // A layered wall can expose a horizontal side edge at every material
      // or storey break. Those are real mesh edges, but not architectural
      // facade contours. Without an external opening-profile hint, retain a
      // sill/head only when both endpoints are attached to real vertical
      // jambs from the same mesh.
      val inferredOpeningBoundary =
        horizontalLength <= fallbackOpeningEdgeLength + boundaryTolerance &&
        pointKey(first) in verticalEdgePoints &&
        pointKey(second) in verticalEdgePoints
      inferredOpeningBoundary
    }
  }

  /** Remove small external-mesh tessellation seams from the edge stream. */
  fun cleanImportedEdges(
    points: List<ScenePoint>,
    edges: List<NativeVisualEdge>,
  ): List<NativeVisualEdge> {
    if (points.isEmpty() || edges.isEmpty()) return edges
    val bounds = boundsForPoints(points)
    val span = max(
      max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y),
      bounds.max.z - bounds.min.z,
    ).coerceAtLeast(0.1)
    val minimumLength = max(0.01, min(0.10, span * 0.001))
    val minimumBoundaryLength = max(
      minimumLength * 2.5,
      min(0.75, span * 0.015),
    )
    return edges.filter { edge ->
      // Synthetic envelope edges have no source triangle association and are
      // intentionally retained when a smooth imported mesh has no topology.
      if (edge.triangleIndices.isEmpty()) return@filter edge.sharp
      val first = points.getOrNull(edge.first) ?: return@filter false
      val second = points.getOrNull(edge.second) ?: return@filter false
      val dx = second.x - first.x
      val dy = second.y - first.y
      val dz = second.z - first.z
      val length = sqrt(dx * dx + dy * dy + dz * dz)
      if (!length.isFinite() || length < minimumLength) return@filter false
      if (edge.triangleIndices.size == 1) {
        length >= minimumBoundaryLength
      } else {
        edge.sharp
      }
    }
  }

  /** Keep sharp edges first while applying a caller-owned segment budget. */
  fun capEdges(edges: List<NativeVisualEdge>, limit: Int): List<NativeVisualEdge> {
    if (limit <= 0) return emptyList()
    if (edges.size <= limit) return edges
    return (edges.filter { it.sharp } + edges.filterNot { it.sharp }).take(limit)
  }

  private fun triangleNormal(a: ScenePoint, b: ScenePoint, c: ScenePoint): DoubleArray {
    val abX = b.x - a.x
    val abY = b.y - a.y
    val abZ = b.z - a.z
    val acX = c.x - a.x
    val acY = c.y - a.y
    val acZ = c.z - a.z
    val x = abY * acZ - abZ * acY
    val y = abZ * acX - abX * acZ
    val z = abX * acY - abY * acX
    val length = sqrt(x * x + y * y + z * z)
    return if (length <= 1.0e-9) {
      doubleArrayOf(0.0, 0.0, 0.0)
    } else {
      doubleArrayOf(x / length, y / length, z / length)
    }
  }

  private fun normalDot(first: DoubleArray, second: DoubleArray): Double =
    first[0] * second[0] + first[1] * second[1] + first[2] * second[2]

  private fun boundsForPoints(points: List<ScenePoint>): SceneBounds {
    if (points.isEmpty()) {
      return SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
    }
    var minX = points.first().x
    var minY = points.first().y
    var minZ = points.first().z
    var maxX = minX
    var maxY = minY
    var maxZ = minZ
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
}
