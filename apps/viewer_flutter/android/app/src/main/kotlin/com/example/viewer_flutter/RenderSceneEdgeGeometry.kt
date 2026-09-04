package com.example.viewer_flutter

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.IntBuffer

/**
 * Pure edge-mesh generation for the native viewport.
 *
 * The Filament host owns scene entities and GPU lifetime. This module owns
 * topology classification, offsets, deduplication and ribbon serialization.
 */
internal data class GeometryData(
  val vertexCount: Int,
  val indexCount: Int,
  val vertexData: ByteBuffer,
  val indexData: IntBuffer,
  val bounds: SceneBounds,
  val points: List<ScenePoint> = emptyList(),
  val triangles: List<IntArray> = emptyList(),
)

internal object RenderSceneEdgeGeometry {
  private fun stableWallEdgeOffset(
    first: ScenePoint,
    second: ScenePoint,
    axisStart: ScenePoint,
    axisEnd: ScenePoint,
  ): ScenePoint {
    val axisX = axisEnd.x - axisStart.x
    val axisZ = axisEnd.z - axisStart.z
    val axisLength = kotlin.math.sqrt(axisX * axisX + axisZ * axisZ)
    if (!axisLength.isFinite() || axisLength <= 1.0e-9) return ScenePoint(0.0, 0.0, 0.0)

    // The offset must be the wall-face normal. Using the edge tangent made a
    // vertical edge return a zero horizontal normal and put the ribbon exactly
    // on the wall surface, where mobile depth precision makes it shimmer.
    val normalX = -axisZ / axisLength
    val normalZ = axisX / axisLength
    val axisCenterX = (axisStart.x + axisEnd.x) * 0.5
    val axisCenterZ = (axisStart.z + axisEnd.z) * 0.5
    val edgeCenterX = (first.x + second.x) * 0.5
    val edgeCenterZ = (first.z + second.z) * 0.5
    val side = (edgeCenterX - axisCenterX) * normalX +
      (edgeCenterZ - axisCenterZ) * normalZ
    val sideSign = if (side < 0.0) -1.0 else 1.0
    val offset = 0.006 * sideSign
    return ScenePoint(normalX * offset, 0.0, normalZ * offset)
  }

  private fun stableCurvedWallEdgeOffset(
    first: ScenePoint,
    second: ScenePoint,
    arcCenter: ScenePoint,
    arcRadius: Double,
  ): ScenePoint {
    if (!arcRadius.isFinite() || arcRadius <= 1.0e-9) {
      return ScenePoint(0.0, 0.0, 0.0)
    }
    val midpointX = (first.x + second.x) * 0.5
    val midpointZ = (first.z + second.z) * 0.5
    val radialX = midpointX - arcCenter.x
    val radialZ = midpointZ - arcCenter.z
    val radialLength = kotlin.math.sqrt(radialX * radialX + radialZ * radialZ)
    if (!radialLength.isFinite() || radialLength <= 1.0e-9) {
      return ScenePoint(0.0, 0.0, 0.0)
    }

    // Arc edges cannot use the endpoint chord as a wall normal.  Offset them
    // along the true radial direction instead: the outer boundary moves out,
    // the inner boundary moves in, and both remain depth-tested.  This keeps
    // the architectural line attached to the same curved face without the
    // mobile depth-buffer shimmer caused by coplanar ribbons.
    val side = if (radialLength >= arcRadius) 1.0 else -1.0
    val offset = 0.008 * side
    return ScenePoint(
      radialX / radialLength * offset,
      0.0,
      radialZ / radialLength * offset,
    )
  }

  internal fun edgeSurfaceOffset(
    projectionMode: String,
    first: ScenePoint,
    second: ScenePoint,
    triangleIndices: IntArray,
    points: List<ScenePoint>,
    triangles: List<IntArray>,
    primitiveCenter: ScenePoint,
    offsetMeters: Double? = null,
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
    // Imported meshes are not guaranteed to have consistent winding. Orient
    // the offset away from the local primitive centre so a front-face edge is
    // lifted out of the source surface instead of being pushed into it and
    // depth-fighting on mobile GPUs.
    val midpoint = ScenePoint(
      (first.x + second.x) * 0.5,
      (first.y + second.y) * 0.5,
      (first.z + second.z) * 0.5,
    )
    val fromCenterX = midpoint.x - primitiveCenter.x
    val fromCenterY = midpoint.y - primitiveCenter.y
    val fromCenterZ = midpoint.z - primitiveCenter.z
    if (normalX * fromCenterX + normalY * fromCenterY + normalZ * fromCenterZ < 0.0) {
      normalX = -normalX
      normalY = -normalY
      normalZ = -normalZ
    }
    val offset = offsetMeters ?: when {
      projectionMode == "topDown" -> 0.006
      projectionMode == "isometric" -> 0.040
      else -> 0.018
    }
    return ScenePoint(
      normalX / length * offset,
      normalY / length * offset,
      normalZ / length * offset,
    )
  }
  fun build(
    projectionMode: String,
    points: List<ScenePoint>,
    edges: List<NativeVisualEdge>,
    triangles: List<IntArray>,
    wallEdgePass: Boolean = false,
    wallJunctionEdges: Boolean = false,
    wallJunctionElevations: List<Double> = emptyList(),
    wallAxisStart: ScenePoint? = null,
    wallAxisEnd: ScenePoint? = null,
    wallArcCenter: ScenePoint? = null,
    wallArcRadius: Double? = null,
    radiusScale: Double = 1.0,
  ): GeometryData? {
    val validEdges = edges.filter { it.first in points.indices && it.second in points.indices }
    val isFloorPlan = projectionMode == "topDown"
    // Ribbon width is selected below. Keeping it independent of the source
    // wall thickness prevents close-up wall edges from turning into bars.
    val sourceBounds = boundsForPoints(points)
    val sourceCenter = ScenePoint(
      (sourceBounds.min.x + sourceBounds.max.x) * 0.5,
      (sourceBounds.min.y + sourceBounds.max.y) * 0.5,
      (sourceBounds.min.z + sourceBounds.max.z) * 0.5,
    )
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
      val primitiveCenter: ScenePoint? = null,
      val wallAxis: WallAxis? = null,
    )
    val edgeTriangleIndices = validEdges.associateBy(
      keySelector = { edgeKey(it.first, it.second) },
      valueTransform = { it.triangleIndices },
    )
    val allEdges = validEdges.toMutableList()
    for (key in junctionKeys) {
      if (allEdges.none { edgeKey(it.first, it.second) == key }) {
        allEdges.add(
          NativeVisualEdge(
            first = key.first,
            second = key.second,
            triangleIndices = intArrayOf(),
            sharp = true,
          ),
        )
      }
    }
    val rawRenderEdges = allEdges.map { edge ->
      RenderEdge(
        points[edge.first],
        points[edge.second],
        wallJunctionEdges && junctionKeys.contains(edgeKey(edge.first, edge.second)),
        edgeTriangleIndices[edgeKey(edge.first, edge.second)] ?: IntArray(0),
        edge.primitiveCenter,
        edge.wallAxis,
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
    // A thin planar ribbon is one physical line. A square prism creates two
    // visible side contours at corners and can cross the near plane while
    // zooming, which is the source of the doubled lines and large artifacts
    // seen on the tablet.
    val verticesPerEdge = 4
    val indicesPerEdge = 6
    val vertexData = ByteBuffer.allocateDirect(renderEdges.size * verticesPerEdge * 12)
      .order(ByteOrder.nativeOrder())
    val indexData = ByteBuffer.allocateDirect(renderEdges.size * indicesPerEdge * Int.SIZE_BYTES)
      .order(ByteOrder.nativeOrder()).asIntBuffer()
    var vertexOffset = 0
    for (edge in renderEdges.values) {
      val sourceFirst = edge.first
      val sourceSecond = edge.second
      // At a wall/floor or wall/ceiling contact the border ribbon can be
      // coplanar with the adjacent system and lose the depth test. Move only
      // those horizontal wall edges 18 mm onto the visible wall face: it
      // preserves hidden-edge behavior while making an interior room read as
      // bounded after an exterior wall is removed.
      val averageY = (sourceFirst.y + sourceSecond.y) * 0.5
      val isHorizontalWallBoundary = edge.junction
      val junctionOffset = if (isHorizontalWallBoundary && !isFloorPlan) {
        // Adjacent storeys can contribute the same boundary once from the
        // lower wall top and once from the upper wall bottom. Use one shared
        // offset so batch-level centerline deduplication sees one segment.
        // The wall-face offset still keeps it out of the coplanar wall face.
        -0.035
      } else {
        when {
          isHorizontalWallBoundary && kotlin.math.abs(averageY - sourceBounds.min.y) <= 1e-5 -> 0.05
          isHorizontalWallBoundary && kotlin.math.abs(averageY - sourceBounds.max.y) <= 1e-5 -> -0.05
          isHorizontalWallBoundary -> -0.035
          else -> 0.0
        }
      }
      val isHorizontalJunction = isHorizontalWallBoundary &&
        kotlin.math.abs(sourceFirst.y - sourceSecond.y) <= 1e-5
      // The generated ribbon has no thickness, but on mobile depth precision
      // can still place its centre behind the wall face. Push a horizontal wall
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
      // The edge ribbon otherwise sits exactly on the imported face. That is
      // enough to trigger depth-buffer fighting on tablet GPUs, which appears
      // as disappearing/dotted lines while orbiting.  Move it a tiny amount
      // along the average adjacent face normal; it remains depth-tested and
      // is still hidden by genuinely occluding geometry.
      // A curved wall's chord is only its authored endpoint reference. It is
      // never a valid face normal for edge lifting; use the radial arc offset
      // below and deliberately ignore any chord axis attached to the edge.
      val edgeWallAxis = if (wallArcCenter != null) {
        null
      } else edge.wallAxis ?: if (wallAxisStart != null && wallAxisEnd != null) {
        WallAxis(wallAxisStart, wallAxisEnd)
      } else {
        null
      }
      val surfaceOffset = if (wallEdgePass && projectionMode != "section" &&
        wallArcCenter != null && wallArcRadius != null
      ) {
        stableCurvedWallEdgeOffset(
          sourceFirst,
          sourceSecond,
          wallArcCenter,
          wallArcRadius,
        )
      } else if (wallEdgePass && projectionMode != "section" && edgeWallAxis != null) {
        stableWallEdgeOffset(sourceFirst, sourceSecond, edgeWallAxis.start, edgeWallAxis.end)
      } else {
        edgeSurfaceOffset(
          projectionMode,
          edge.first,
          edge.second,
          edge.triangleIndices,
          points,
          triangles,
          edge.primitiveCenter ?: sourceCenter,
        )
      }
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
      val tangent = ScenePoint(dx / length, dy / length, dz / length)
      val offsetNormal = ScenePoint(
        faceOffset.x + surfaceOffset.x,
        junctionOffset + faceOffset.y + surfaceOffset.y,
        faceOffset.z + surfaceOffset.z,
      )
      val normalLength = kotlin.math.sqrt(
        offsetNormal.x * offsetNormal.x +
          offsetNormal.y * offsetNormal.y +
          offsetNormal.z * offsetNormal.z,
      )
      val normal = if (normalLength > 1e-8) {
        ScenePoint(
          offsetNormal.x / normalLength,
          offsetNormal.y / normalLength,
          offsetNormal.z / normalLength,
        )
      } else {
        // Synthetic wall boundary edges do not have triangle normals. Choose
        // a world axis that is not parallel to the edge.
        if (kotlin.math.abs(tangent.y) < 0.80) {
          ScenePoint(0.0, 1.0, 0.0)
        } else {
          ScenePoint(1.0, 0.0, 0.0)
        }
      }
      var width = ScenePoint(
        tangent.y * normal.z - tangent.z * normal.y,
        tangent.z * normal.x - tangent.x * normal.z,
        tangent.x * normal.y - tangent.y * normal.x,
      )
      var widthLength = kotlin.math.sqrt(width.x * width.x + width.y * width.y + width.z * width.z)
      if (widthLength <= 1e-8) {
        width = ScenePoint(tangent.y, -tangent.x, 0.0)
        widthLength = kotlin.math.sqrt(width.x * width.x + width.y * width.y + width.z * width.z)
      }
      if (widthLength <= 1e-8) continue
      val halfWidth = when {
        isFloorPlan -> 0.006
        wallEdgePass && projectionMode == "isometric" -> 0.014
        else -> 0.010
      } * radiusScale
      val widthVector = ScenePoint(
        width.x / widthLength * halfWidth,
        width.y / widthLength * halfWidth,
        width.z / widthLength * halfWidth,
      )
      val ribbonPoints = listOf(
        ScenePoint(first.x + widthVector.x, first.y + widthVector.y, first.z + widthVector.z),
        ScenePoint(first.x - widthVector.x, first.y - widthVector.y, first.z - widthVector.z),
        ScenePoint(second.x + widthVector.x, second.y + widthVector.y, second.z + widthVector.z),
        ScenePoint(second.x - widthVector.x, second.y - widthVector.y, second.z - widthVector.z),
      )
      for (point in ribbonPoints) {
        vertexData.putFloat(point.x.toFloat())
        vertexData.putFloat(point.y.toFloat())
        vertexData.putFloat(point.z.toFloat())
      }
      indexData.put(vertexOffset)
      indexData.put(vertexOffset + 1)
      indexData.put(vertexOffset + 2)
      indexData.put(vertexOffset + 2)
      indexData.put(vertexOffset + 1)
      indexData.put(vertexOffset + 3)
      vertexOffset += 4
    }
    if (vertexOffset == 0) return null
    vertexData.flip(); indexData.flip()
    // The ribbon has no volumetric thickness, so only a small bound margin is
    // needed and it cannot form an oversized near-plane culling volume.
    val bounds = SceneBounds(
      ScenePoint(sourceBounds.min.x - 0.02, sourceBounds.min.y - 0.02, sourceBounds.min.z - 0.02),
      ScenePoint(sourceBounds.max.x + 0.02, sourceBounds.max.y + 0.02, sourceBounds.max.z + 0.02),
    )
    return GeometryData(vertexOffset, (vertexOffset / 4) * indicesPerEdge, vertexData, indexData, bounds)
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
    val length = kotlin.math.sqrt(x * x + y * y + z * z)
    return if (length <= 1.0e-9) {
      doubleArrayOf(0.0, 0.0, 0.0)
    } else {
      doubleArrayOf(x / length, y / length, z / length)
    }
  }

  private fun normalDot(first: DoubleArray, second: DoubleArray): Double =
    first[0] * second[0] + first[1] * second[1] + first[2] * second[2]

  private fun boundsForPoints(points: List<ScenePoint>): SceneBounds =
    boundsFromPoints(points)
}
