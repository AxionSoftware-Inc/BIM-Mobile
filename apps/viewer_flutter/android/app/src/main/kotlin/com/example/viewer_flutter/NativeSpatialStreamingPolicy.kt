package com.example.viewer_flutter

import kotlin.math.sqrt

/**
 * Google-Earth-style residency policy for very large BIM projects.
 *
 * The renderer may know about every building/floor/chunk, but only a bounded
 * camera-relevant working set should be resident on the GPU. This policy is
 * deliberately independent from Filament resources so it can be tested and
 * later shared by Android/desktop render backends.
 *
 * IMPORTANT: policy evaluation must be metadata-only. Reading a chunk's
 * positions/indices here would materialize cold native geometry merely to
 * decide whether that geometry should be loaded, defeating CPU lazy loading.
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
    val ranked = ArrayList<RankedChunk>(minOf(chunks.size, config.maxResidentChunks * 4))
    for (chunk in chunks) {
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
      if (!near && (distance > distanceLimit || viewDot < config.rearHemisphereDotThreshold)) {
        continue
      }
      ranked.add(
        RankedChunk(
          chunk = chunk,
          distance = distance,
          viewDot = viewDot,
        ),
      )
    }
    ranked.sortWith(
      compareByDescending<RankedChunk> { it.distance <= config.alwaysResidentDistanceMeters }
        .thenByDescending { it.viewDot }
        .thenBy { it.distance }
        .thenBy { it.chunk.index },
    )

    val target = LinkedHashSet<Int>(minOf(config.maxResidentChunks, ranked.size))
    var targetBytes = 0L
    for (rankedChunk in ranked) {
      if (target.size >= config.maxResidentChunks) break
      val bytes = rankedChunk.chunk.estimatedGpuBytes.coerceAtLeast(0L)
      if (target.isNotEmpty() && targetBytes + bytes > config.maxResidentBytes) continue
      target.add(rankedChunk.chunk.index)
      targetBytes += bytes
    }

    val loadOrder = ArrayList<Int>(target.size)
    for (rankedChunk in ranked) {
      val index = rankedChunk.chunk.index
      if (target.contains(index) && !currentResident.contains(index)) loadOrder.add(index)
    }
    val keep = currentResident.filterTo(linkedSetOf()) { target.contains(it) }
    val evict = currentResident.filterTo(linkedSetOf()) { !target.contains(it) }

    return Decision(
      loadOrder = loadOrder,
      keepResident = keep,
      evict = evict,
      targetResidentBytes = targetBytes,
    )
  }

  fun chunksFromCache(chunks: List<NativeBimCacheChunk>): List<Chunk> =
    chunks.mapIndexed { index, chunk ->
      Chunk(
        index = index,
        bounds = chunk.sourceBounds,
        // Metadata-only estimate: do not touch chunk.positions/indices here.
        estimatedGpuBytes = chunk.estimatedGpuBytes,
      )
    }

  private data class RankedChunk(
    val chunk: Chunk,
    val distance: Double,
    val viewDot: Double,
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
