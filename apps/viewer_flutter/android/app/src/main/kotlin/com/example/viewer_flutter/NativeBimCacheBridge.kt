package com.example.viewer_flutter

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.IntBuffer

/**
 * JNI access to an engine-owned `.bimcache` file.
 *
 * MEMORY/STREAMING CONTRACT:
 * - Dart never receives vertex/index payloads.
 * - Opening a cache builds only a compact chunk/semantic manifest.
 * - A chunk's direct native geometry view is requested lazily when the
 *   renderer actually chooses that chunk for residency.
 *
 * This matters for campus-size projects: progressive GPU upload is not enough
 * if Kotlin eagerly creates direct-buffer views for every floor/building at
 * startup. Lazy geometry lets the CPU and GPU working sets follow the camera.
 */
internal object NativeBimCacheBridge {
  private const val virtualIfcPartTag = 0x4000000000000000L
  private const val virtualIfcPartSourceMask = 0x00003FFFFFFFFFFFL
  private const val virtualIfcPartOrdinalMask = 0xFFFFL

  init {
    System.loadLibrary("tbe_capi")
  }

  private external fun nativeOpen(cachePath: String, sourceIfcPath: String): Long
  private external fun nativeClose(handle: Long)
  private external fun nativeLastError(): String
  private external fun nativeChunkCount(handle: Long): Int
  private external fun nativeChunkLevelId(handle: Long, index: Int): Long
  private external fun nativeChunkMaterial(handle: Long, index: Int): String
  private external fun nativeChunkKindMask(handle: Long, index: Int): Long
  private external fun nativeChunkPrimitiveRanges(handle: Long, index: Int): LongArray?
  private external fun nativeChunkPrimitiveMetadata(handle: Long, index: Int): Array<String>?
  private external fun nativeChunkBounds(handle: Long, index: Int): DoubleArray?
  private external fun nativeChunkPositions(handle: Long, index: Int): ByteBuffer?
  private external fun nativeChunkIndices(handle: Long, index: Int): ByteBuffer?
  private external fun nativePrimitiveData(handle: Long): LongArray?
  private external fun nativePrimitiveBounds(handle: Long): DoubleArray?
  private external fun nativePrimitiveFeatureEdgeCounts(handle: Long): LongArray?
  private external fun nativePrimitiveFeatureEdgeData(handle: Long): DoubleArray?
  private external fun nativePick(
    handle: Long,
    originX: Double,
    originY: Double,
    originZ: Double,
    directionX: Double,
    directionY: Double,
    directionZ: Double,
    visibleKindMask: Long,
  ): Long
  private external fun nativeCompileFromIfc(
    sourceIfcPath: String,
    cachePath: String,
  ): LongArray?

  fun open(cachePath: String, sourceIfcPath: String): NativeBimCache? {
    val handle = nativeOpen(cachePath, sourceIfcPath)
    if (handle == 0L) return null
    return try {
      val primitiveData = nativePrimitiveData(handle) ?: LongArray(0)
      val primitiveBounds = nativePrimitiveBounds(handle) ?: DoubleArray(0)
      val primitiveFeatureEdgeCounts = nativePrimitiveFeatureEdgeCounts(handle) ?: LongArray(0)
      val primitiveFeatureEdgeData = nativePrimitiveFeatureEdgeData(handle) ?: DoubleArray(0)
      val primitiveFeatureEdges = decodePrimitiveFeatureEdges(
        primitiveFeatureEdgeCounts,
        primitiveFeatureEdgeData,
      )
      var primitiveOffset = 0
      val chunks = buildList {
        repeat(nativeChunkCount(handle)) { index ->
          val bounds = nativeChunkBounds(handle, index) ?: return@repeat
          if (bounds.size != 6) return@repeat
          val primitiveRanges = nativeChunkPrimitiveRanges(handle, index)
          val primitiveMetadata = nativeChunkPrimitiveMetadata(handle, index)
            ?.toList()
            ?.chunked(8)
            ?.map { values -> wallMetadata(values) }
            ?: emptyList()
          val ranges = primitiveRanges
            ?.asList()
            ?.chunked(3)
            ?.mapIndexedNotNull { primitiveIndex, values ->
              if (values.size != 3) return@mapIndexedNotNull null
              NativeBimCachePrimitiveRange(
                firstIndex = values[0].toInt(),
                indexCount = values[1].toInt(),
                kind = kindFromNativeValue(values[2]),
                metadata = primitiveMetadata.getOrNull(primitiveIndex) ?: emptyMap(),
                featureEdges = primitiveFeatureEdges.getOrNull(primitiveOffset + primitiveIndex)
                  ?: emptyList(),
              )
            }
            ?: emptyList()
          primitiveOffset += ranges.size
          val kindMask = nativeChunkKindMask(handle, index)
          val estimatedIndexCount = ranges.sumOf { range -> range.indexCount.coerceAtLeast(0) }

          add(
            NativeBimCacheChunk(
              levelId = nativeChunkLevelId(handle, index),
              materialCategory = nativeChunkMaterial(handle, index),
              kindMask = kindMask,
              kind = primaryKindFromMask(kindMask),
              sourceBounds = sceneBounds(bounds),
              estimatedIndexCount = estimatedIndexCount,
              primitiveRanges = ranges,
              geometryLoader = loader@{
                // The cache handle stays open for the lifetime of the viewport.
                // These direct views are therefore safe while the chunk is
                // resident and are not requested for cold/off-screen chunks.
                val positions = nativeChunkPositions(handle, index)
                  ?: return@loader null
                val rawIndices = nativeChunkIndices(handle, index)
                  ?: return@loader null
                if (positions.capacity() < 12 || rawIndices.capacity() < Int.SIZE_BYTES) {
                  return@loader null
                }
                NativeBimCacheGeometry(
                  positions = positions.duplicate()
                    .order(ByteOrder.nativeOrder())
                    .apply { rewind() },
                  indices = rawIndices.duplicate()
                    .order(ByteOrder.nativeOrder())
                    .asIntBuffer()
                    .apply { rewind() },
                )
              },
            ),
          )
        }
      }
      val primitiveMetadata = cachePrimitiveMetadata(chunks)
      NativeBimCache(
        handle = handle,
        chunks = chunks,
        primitives = buildPrimitives(
          primitiveData,
          primitiveBounds,
          primitiveMetadata,
          primitiveFeatureEdges,
        ),
      )
    } catch (_: Throwable) {
      nativeClose(handle)
      null
    }
  }

  fun lastError(): String = nativeLastError()

  /**
   * Debug/profiling-only compiler entry point. It owns an isolated C++
   * session, so cache parsing and compilation can be measured off Android's
   * UI thread without touching the live authoring session.
   */
  fun compileFromIfc(sourceIfcPath: String, cachePath: String): NativeBimCacheCompileStats? {
    val values = nativeCompileFromIfc(sourceIfcPath, cachePath) ?: return null
    if (values.size < 7) return null
    return NativeBimCacheCompileStats(
      elapsedMs = values[0],
      byteSize = values[1],
      objectCount = values[2],
      triangleCount = values[3],
      chunkCount = values[4],
      primitiveCount = values[5],
      bvhNodeCount = values[6],
    )
  }

  /**
   * Reads only the project/chunk envelope required to decide whether a cache is
   * usable and how large it is. Unlike [describe], this deliberately avoids
   * primitive metadata, per-element bounds, feature edges and Java object Maps.
   *
   * The largest temporary allocation is one chunk's primitive-range LongArray;
   * it is discarded before the next chunk. This keeps startup inspection close
   * to O(levels + chunks) retained memory instead of O(elements).
   */
  fun describeManifest(cachePath: String, sourceIfcPath: String): Map<String, Any?>? {
    val handle = nativeOpen(cachePath, sourceIfcPath)
    if (handle == 0L) return null
    return try {
      val chunkCount = nativeChunkCount(handle).coerceAtLeast(0)
      var mergedBounds: SceneBounds? = null
      val levelElevations = sortedMapOf<Long, Double>()
      val primaryKindChunkCounts = linkedMapOf<String, Int>()
      var primitiveCount = 0L
      var estimatedIndexCount = 0L
      var estimatedGpuBytes = 0L

      repeat(chunkCount) { index ->
        val rawBounds = nativeChunkBounds(handle, index)
        if (rawBounds != null && rawBounds.size == 6) {
          val bounds = sceneBounds(rawBounds)
          mergedBounds = mergedBounds?.let { unionSceneBounds(it, bounds) } ?: bounds
          val levelId = nativeChunkLevelId(handle, index)
          val previousElevation = levelElevations[levelId]
          if (previousElevation == null || bounds.min.z < previousElevation) {
            levelElevations[levelId] = bounds.min.z
          }
        }

        val kind = primaryKindFromMask(nativeChunkKindMask(handle, index))
        primaryKindChunkCounts[kind] = (primaryKindChunkCounts[kind] ?: 0) + 1

        val ranges = nativeChunkPrimitiveRanges(handle, index)
        val rangeCount = (ranges?.size ?: 0) / 3
        primitiveCount += rangeCount.toLong()
        var chunkIndexCount = 0L
        if (ranges != null) {
          var offset = 0
          repeat(rangeCount) {
            chunkIndexCount += ranges[offset + 1].coerceAtLeast(0L)
            offset += 3
          }
        }
        estimatedIndexCount += chunkIndexCount
        estimatedGpuBytes += chunkIndexCount * 16L + 4096L
      }

      val bounds = mergedBounds
        ?: SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
      val levels = levelElevations.map { (levelId, elevation) ->
        linkedMapOf<String, Any?>(
          "level_id" to levelId,
          "name" to "Level $levelId",
          "elevation_meters" to elevation,
          "default_wall_height_meters" to 3.2,
        )
      }
      val margin = maxOf(
        2.0,
        (bounds.max.x - bounds.min.x).coerceAtLeast(bounds.max.y - bounds.min.y) * 0.08,
      )

      linkedMapOf<String, Any?>(
        "manifest_version" to 1,
        "scene_version" to 1,
        "units" to "meters",
        "coordinate_system" to "X/Y plan, Z up",
        "object_count" to primitiveCount,
        "chunk_count" to chunkCount,
        "native_cache_estimated_index_count" to estimatedIndexCount,
        "native_cache_estimated_gpu_bytes" to estimatedGpuBytes,
        "primary_kind_chunk_counts" to primaryKindChunkCounts,
        "bounds" to bounds.toMap(),
        "levels" to levels,
        "sections" to listOf(
          sectionMap("Section A", bounds.min.x - margin, centerY(bounds), bounds.max.x + margin, centerY(bounds)),
          sectionMap("Section B", centerX(bounds), bounds.min.y - margin, centerX(bounds), bounds.max.y + margin),
        ),
      )
    } catch (_: Throwable) {
      null
    } finally {
      nativeClose(handle)
    }
  }

  /**
   * Produces the semantic envelope Flutter needs for project chrome,
   * selection and 2D metadata. Meshes never cross this boundary.
   *
   * Do not touch [NativeBimCacheChunk.positions]/indices here. Doing so would
   * defeat lazy CPU streaming during project startup. Geometry counts in this
   * semantic envelope are intentionally zero because the Dart scene contains
   * no mesh; native estimated counts are reported separately for diagnostics.
   */
  fun describe(cachePath: String, sourceIfcPath: String): Map<String, Any?>? {
    val cache = open(cachePath, sourceIfcPath) ?: return null
    return try {
      val bounds = cache.chunks
        .map { it.sourceBounds }
        .reduceOrNull(::unionSceneBounds)
        ?: SceneBounds(ScenePoint(0.0, 0.0, 0.0), ScenePoint(0.0, 0.0, 0.0))
      val levels = cache.chunks
        .groupBy { it.levelId }
        .toSortedMap()
        .map { (levelId, chunks) ->
          linkedMapOf<String, Any?>(
            "level_id" to levelId,
            "name" to "Level $levelId",
            "elevation_meters" to chunks.minOf { it.sourceBounds.min.z },
            "default_wall_height_meters" to 3.2,
          )
        }
      val margin = maxOf(
        2.0,
        (bounds.max.x - bounds.min.x).coerceAtLeast(bounds.max.y - bounds.min.y) * 0.08,
      )
      linkedMapOf<String, Any?>(
        "scene_version" to 1,
        "units" to "meters",
        "coordinate_system" to "X/Y plan, Z up",
        "object_count" to cache.primitives.size,
        "vertex_count" to 0,
        "index_count" to 0,
        "native_cache_estimated_index_count" to cache.chunks.sumOf { it.estimatedIndexCount },
        "native_cache_estimated_gpu_bytes" to cache.chunks.sumOf { it.estimatedGpuBytes },
        "bounds" to bounds.toMap(),
        "levels" to levels,
        "materials" to emptyList<Map<String, Any?>>(),
        "sections" to listOf(
          sectionMap("Section A", bounds.min.x - margin, centerY(bounds), bounds.max.x + margin, centerY(bounds)),
          sectionMap("Section B", centerX(bounds), bounds.min.y - margin, centerX(bounds), bounds.max.y + margin),
        ),
        "objects" to cache.primitives.map { primitive ->
          val sourceElementId = virtualIfcPartSourceId(primitive.elementId)
          val metadata = linkedMapOf<String, Any?>("native_cache" to true)
          metadata.putAll(primitive.metadata)
          if (sourceElementId != null) {
            metadata["source_element_id"] = sourceElementId
            metadata["selection_scope"] = "imported_mesh_part"
          }
          linkedMapOf<String, Any?>(
            "element_id" to primitive.elementId,
            "kind" to primitive.kind,
            "level_id" to primitive.levelId,
            "selectable" to true,
            "visible_by_default" to true,
            "revision" to 0,
            "bounds" to primitive.sourceBounds.toMap(),
            "mesh" to linkedMapOf<String, Any?>(
              "positions" to emptyList<Map<String, Double>>(),
              "indices" to emptyList<Int>(),
            ),
            "material_category" to "generic",
            "metadata" to metadata,
            "feature_edges" to primitive.featureEdges.map { edge ->
              linkedMapOf<String, Any>(
                "role" to edge.role,
                "start" to linkedMapOf("x" to edge.start.x, "y" to edge.start.y, "z" to edge.start.z),
                "end" to linkedMapOf("x" to edge.end.x, "y" to edge.end.y, "z" to edge.end.z),
              )
            },
          ).also { summary ->
            if (sourceElementId != null) {
              summary["name"] =
                "Imported mesh part ${primitive.elementId and virtualIfcPartOrdinalMask}"
            }
          }
        },
      )
    } finally {
      cache.close()
    }
  }

  private fun buildPrimitives(
    data: LongArray,
    bounds: DoubleArray,
    metadata: List<Map<String, String>>,
    featureEdgesByPrimitive: List<List<SceneFeatureEdge>>,
  ): List<NativeBimCachePrimitive> {
    val primitiveCount = minOf(data.size / 4, bounds.size / 6)
    return List(primitiveCount) { index ->
      NativeBimCachePrimitive(
        elementId = data[index * 4],
        kind = kindFromNativeValue(data[index * 4 + 1]),
        levelId = data[index * 4 + 3],
        sourceBounds = sceneBounds(bounds, index * 6),
        metadata = metadata.getOrNull(index) ?: emptyMap(),
        featureEdges = featureEdgesByPrimitive.getOrNull(index) ?: emptyList(),
      )
    }
  }

  private fun decodePrimitiveFeatureEdges(
    counts: LongArray,
    data: DoubleArray,
  ): List<List<SceneFeatureEdge>> {
    var offset = 0
    return counts.map { rawCount ->
      val count = rawCount.toInt().coerceAtLeast(0)
      buildList {
        repeat(count) {
          if (offset + 6 >= data.size) return@repeat
          add(
            SceneFeatureEdge(
              start = ScenePoint(data[offset + 1], data[offset + 2], data[offset + 3]),
              end = ScenePoint(data[offset + 4], data[offset + 5], data[offset + 6]),
              role = if (data[offset].toInt() == 1) "opening_contour" else "silhouette",
            ),
          )
          offset += 7
        }
      }
    }
  }

  private fun cachePrimitiveMetadata(chunks: List<NativeBimCacheChunk>): List<Map<String, String>> =
    chunks.flatMap { chunk -> chunk.primitiveRanges.map { it.metadata } }

  private fun wallMetadata(values: List<String>): Map<String, String> {
    if (values.size != 8 || values.all(String::isEmpty)) return emptyMap()
    val keys = listOf(
      "start_x", "start_y", "end_x", "end_y", "thickness_meters",
      "height_meters", "profile_corners", "layer_profile",
    )
    return keys.zip(values).filter { (_, value) -> value.isNotEmpty() }.toMap()
  }

  internal fun virtualIfcPartSourceId(elementId: Long): Long? {
    if ((elementId and virtualIfcPartTag) != virtualIfcPartTag) return null
    return (elementId ushr 16) and virtualIfcPartSourceMask
  }

  private fun kindFromNativeValue(value: Long): String = when (value.toInt()) {
    2 -> "wall"
    3 -> "door"
    4 -> "window"
    5 -> "room"
    6 -> "slab"
    7 -> "floor"
    8 -> "ceiling"
    9 -> "roof"
    10 -> "column"
    11 -> "beam"
    12 -> "stair"
    13 -> "proxy"
    else -> "proxy"
  }

  private fun primaryKindFromMask(mask: Long): String {
    for (kind in listOf("wall", "door", "window", "room", "slab", "floor", "ceiling", "roof", "column", "beam", "stair", "proxy")) {
      val ordinal = when (kind) {
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
        else -> 13
      }
      if ((mask and (1L shl ordinal)) != 0L) return kind
    }
    return "proxy"
  }

  private fun visibleKindMask(visibleKinds: Set<String>): Long {
    if (visibleKinds.isEmpty()) return -1L
    var mask = 0L
    for (kind in visibleKinds) {
      val ordinal = when (kind) {
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
        else -> continue
      }
      mask = mask or (1L shl ordinal)
    }
    return mask
  }

  private fun sceneBounds(values: DoubleArray, offset: Int = 0): SceneBounds = SceneBounds(
    min = ScenePoint(values[offset], values[offset + 1], values[offset + 2]),
    max = ScenePoint(values[offset + 3], values[offset + 4], values[offset + 5]),
  )

  private fun SceneBounds.toMap(): Map<String, Any> = linkedMapOf(
    "min" to linkedMapOf("x" to min.x, "y" to min.y, "z" to min.z),
    "max" to linkedMapOf("x" to max.x, "y" to max.y, "z" to max.z),
  )

  private fun unionSceneBounds(first: SceneBounds, second: SceneBounds): SceneBounds = SceneBounds(
    min = ScenePoint(
      minOf(first.min.x, second.min.x),
      minOf(first.min.y, second.min.y),
      minOf(first.min.z, second.min.z),
    ),
    max = ScenePoint(
      maxOf(first.max.x, second.max.x),
      maxOf(first.max.y, second.max.y),
      maxOf(first.max.z, second.max.z),
    ),
  )

  private fun centerX(bounds: SceneBounds): Double = (bounds.min.x + bounds.max.x) * 0.5
  private fun centerY(bounds: SceneBounds): Double = (bounds.min.y + bounds.max.y) * 0.5

  private fun sectionMap(name: String, startX: Double, startY: Double, endX: Double, endY: Double): Map<String, Any> =
    linkedMapOf(
      "name" to name,
      "start" to linkedMapOf("x" to startX, "y" to startY, "z" to 0.0),
      "end" to linkedMapOf("x" to endX, "y" to endY, "z" to 0.0),
    )

  class NativeBimCache internal constructor(
    private val handle: Long,
    val chunks: List<NativeBimCacheChunk>,
    val primitives: List<NativeBimCachePrimitive>,
  ) : AutoCloseable {
    private var closed = false

    fun pick(origin: ScenePoint, direction: ScenePoint, visibleKinds: Set<String>): Long? {
      if (closed) return null
      val elementId = nativePick(
        handle,
        origin.x,
        -origin.z,
        origin.y,
        direction.x,
        -direction.z,
        direction.y,
        visibleKindMask(visibleKinds),
      )
      return elementId.takeIf { it != 0L }
    }

    override fun close() {
      if (!closed) {
        nativeClose(handle)
        closed = true
      }
    }
  }
}

internal data class NativeBimCacheGeometry(
  val positions: ByteBuffer,
  val indices: IntBuffer,
)

/**
 * Lightweight chunk manifest. Geometry is a lazy direct-native view.
 *
 * [estimatedGpuBytes] intentionally uses an index-derived upper-bound style
 * estimate. Exact driver allocation accounting is not available here and, more
 * importantly, querying exact vertex buffers would eagerly materialize the
 * very geometry this class is designed to keep cold.
 */
internal class NativeBimCacheChunk(
  val levelId: Long,
  val materialCategory: String,
  val kindMask: Long,
  val kind: String,
  val sourceBounds: SceneBounds,
  val estimatedIndexCount: Int,
  val primitiveRanges: List<NativeBimCachePrimitiveRange> = emptyList(),
  private val geometryLoader: () -> NativeBimCacheGeometry?,
) {
  @Volatile
  private var loadedGeometry: NativeBimCacheGeometry? = null

  val estimatedGpuBytes: Long
    get() = estimatedIndexCount.toLong().coerceAtLeast(0L) * 16L + 4096L

  fun geometry(): NativeBimCacheGeometry? {
    loadedGeometry?.let { return it }
    return synchronized(this) {
      loadedGeometry ?: geometryLoader()?.also { loadedGeometry = it }
    }
  }

  val positions: ByteBuffer
    get() = geometry()?.positions ?: EMPTY_BYTE_BUFFER.duplicate()

  val indices: IntBuffer
    get() = geometry()?.indices ?: EMPTY_INT_BUFFER.duplicate()

  /**
   * Drops Kotlin's direct-buffer views after the renderer has destroyed the
   * corresponding Filament resources. The native cache remains authoritative,
   * so a later camera revisit can materialize fresh views without reparsing IFC.
   */
  fun releaseGeometryView() {
    synchronized(this) {
      loadedGeometry = null
    }
  }

  companion object {
    private val EMPTY_BYTE_BUFFER = ByteBuffer.allocateDirect(0).order(ByteOrder.nativeOrder())
    private val EMPTY_INT_BUFFER = ByteBuffer.allocateDirect(0)
      .order(ByteOrder.nativeOrder())
      .asIntBuffer()
  }
}

internal data class NativeBimCachePrimitiveRange(
  val firstIndex: Int,
  val indexCount: Int,
  val kind: String,
  val metadata: Map<String, String> = emptyMap(),
  val featureEdges: List<SceneFeatureEdge> = emptyList(),
)

internal data class NativeBimCachePrimitive(
  val elementId: Long,
  val kind: String,
  val levelId: Long,
  val sourceBounds: SceneBounds,
  val metadata: Map<String, String> = emptyMap(),
  val featureEdges: List<SceneFeatureEdge> = emptyList(),
)

internal data class NativeBimCacheCompileStats(
  val elapsedMs: Long,
  val byteSize: Long,
  val objectCount: Long,
  val triangleCount: Long,
  val chunkCount: Long,
  val primitiveCount: Long,
  val bvhNodeCount: Long,
)