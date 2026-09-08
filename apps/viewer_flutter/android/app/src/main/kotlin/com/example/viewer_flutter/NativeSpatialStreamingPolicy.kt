package com.example.viewer_flutter

import kotlin.math.sqrt

/**
 * Google-Earth-style residency policy for very large BIM projects.
 *
 * The renderer may know about every building/floor/chunk, but only a bounded
 * camera-relevant working set should be resident on the GPU. This policy is
 * deliberately independent from Filament resources so it can be tested and
 * later shared by Android/desktop render backends.
 */
internal class NativeSpatialStreamingPolicy(
  private val config: Config = Config(),
) {
  data class Config(
    val maxResidentChunks: Int = 96,
    val maxResidentBytes: Long = 384L * 1024L * 1024L,
    val alwaysResidentDistanceMeters: Double = 55.0,
    val streamDistanceMeters: Double = 260.0,
    val residentHysteresisMultiplier: Double = 1.28,
    val rearHemisphereDotThreshold: Double = -0.12,
  )

  data class Camera(
    val position: ScenePoint,
    val forward: ScenePoint,
  )

  data class Chunk(
    val index: Int,
    val bounds: SceneBounds,
    val estimatedGpuBytes: Long,
  )

  data class Decision(
    val loadOrder: List<Int>,
    val keepResident: Set<Int>,
    val evict: Set<Int>,
    val targetResidentBytes: Long,
  )

  fun decide(
    camera: Camera,
    chunks: List<Chunk>,
    currentResident: Set<Int>,
  ): Decision {
    if (chunks.isEmpty()) {
      return Decision(
        loadOrder = emptyList(),
        keepResident = emptySet(),
        evict = currentResident,
        targetResidentBytes = 0L,
      )
    }

    val forward = normalize(camera.forward)
    val ranked = chunks.map { chunk ->
      val center = center(chunk.bounds)
      val dx = center.x - camera.position.x
      val dy = center.y - camera.position.y
      val dz = center.z - camera.position.z
      val distanceSquared = dx * dx + dy * dy + dz * dz
      val distance = sqrt(distanceSquared).coerceAtLeast(1e-9)
      val viewDot = (dx * forward.x + dy * forward.y + dz * forward.z) / distance
      val wasResident = currentResident.contains(chunk.index)
      val distanceLimit = config.streamDistanceMeters *
        if (wasResident) config.residentHysteresisMultiplier else 1.0
      val near = distance <= config.alwaysResidentDistanceMeters
      val cameraRelevant = near ||
        (distance <= distanceLimit && viewDot >= config.rearHemisphereDotThreshold)

      RankedChunk(
        chunk = chunk,
        distance = distance,
        viewDot = viewDot,
        cameraRelevant = cameraRelevant,
        wasResident = wasResident,
      )
    }.filter { it.cameraRelevant }
      .sortedWith(
        compareByDescending<RankedChunk> { it.distance <= config.alwaysResidentDistanceMeters }
          .thenByDescending { it.viewDot }
          .thenBy { it.distance }
          .thenBy { it.chunk.index },
      )

    val target = linkedSetOf<Int>()
    var targetBytes = 0L
    for (rankedChunk in ranked) {
      if (target.size >= config.maxResidentChunks) break
      val bytes = rankedChunk.chunk.estimatedGpuBytes.coerceAtLeast(0L)
      if (target.isNotEmpty() && targetBytes + bytes > config.maxResidentBytes) {
        continue
      }
      target.add(rankedChunk.chunk.index)
      targetBytes += bytes
    }

    val loadOrder = ranked.asSequence()
      .map { it.chunk.index }
      .filter { target.contains(it) && !currentResident.contains(it) }
      .toList()
    val keep = currentResident.intersect(target)
    val evict = currentResident - target

    return Decision(
      loadOrder = loadOrder,
      keepResident = keep,
      evict = evict,
      targetResidentBytes = targetBytes,
    )
  }

  fun chunksFromCache(chunks: List<NativeBimCacheChunk>): List<Chunk> =
    chunks.mapIndexed { index, chunk ->
      // Vertex payload is xyz float32; indices are uint32. A small fixed
      // allowance covers Filament object/material bookkeeping without trying
      // to pretend this is an exact driver allocation counter.
      val vertexBytes = chunk.positions.capacity().toLong()
      val indexBytes = chunk.indices.capacity().toLong() * Int.SIZE_BYTES
      Chunk(
        index = index,
        bounds = chunk.sourceBounds,
        estimatedGpuBytes = vertexBytes + indexBytes + 4096L,
      )
    }

  private data class RankedChunk(
    val chunk: Chunk,
    val distance: Double,
    val viewDot: Double,
    val cameraRelevant: Boolean,
    val wasResident: Boolean,
  )

  private fun center(bounds: SceneBounds): ScenePoint = ScenePoint(
    (bounds.min.x + bounds.max.x) * 0.5,
    (bounds.min.y + bounds.max.y) * 0.5,
    (bounds.min.z + bounds.max.z) * 0.5,
  )

  private fun normalize(value: ScenePoint): ScenePoint {
    val length = sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    if (length <= 1e-9) return ScenePoint(0.0, 0.0, -1.0)
    return ScenePoint(value.x / length, value.y / length, value.z / length)
  }
}
