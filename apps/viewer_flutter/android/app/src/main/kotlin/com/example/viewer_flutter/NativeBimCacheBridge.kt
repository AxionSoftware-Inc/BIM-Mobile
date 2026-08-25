package com.example.viewer_flutter

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.IntBuffer

/**
 * JNI access to an engine-owned `.bimcache` file.
 *
 * Only compact metadata crosses the Kotlin boundary. Vertex/index arrays stay
 * in native memory and are exposed as direct buffers for Filament; Dart never
 * receives the mesh payload.
 */
internal object NativeBimCacheBridge {
  init {
    System.loadLibrary("tbe_capi")
  }

  private external fun nativeOpen(cachePath: String, sourceIfcPath: String): Long
  private external fun nativeClose(handle: Long)
  private external fun nativeLastError(): String
  private external fun nativeChunkCount(handle: Long): Int
  private external fun nativeChunkLevelId(handle: Long, index: Int): Long
  private external fun nativeChunkMaterial(handle: Long, index: Int): String
  private external fun nativeChunkBounds(handle: Long, index: Int): DoubleArray?
  private external fun nativeChunkPositions(handle: Long, index: Int): ByteBuffer?
  private external fun nativeChunkIndices(handle: Long, index: Int): ByteBuffer?
  private external fun nativePrimitiveData(handle: Long): LongArray?
  private external fun nativePrimitiveBounds(handle: Long): DoubleArray?
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

  fun open(cachePath: String, sourceIfcPath: String): NativeBimCache? {
    val handle = nativeOpen(cachePath, sourceIfcPath)
    if (handle == 0L) return null
    return try {
      val chunks = buildList {
        repeat(nativeChunkCount(handle)) { index ->
          val bounds = nativeChunkBounds(handle, index) ?: return@repeat
          val positions = nativeChunkPositions(handle, index) ?: return@repeat
          val indices = nativeChunkIndices(handle, index) ?: return@repeat
          if (bounds.size != 6 || positions.capacity() < 12 || indices.capacity() < Int.SIZE_BYTES) return@repeat
          add(
            NativeBimCacheChunk(
              levelId = nativeChunkLevelId(handle, index),
              materialCategory = nativeChunkMaterial(handle, index),
              sourceBounds = sceneBounds(bounds),
              positions = positions.duplicate().order(ByteOrder.nativeOrder()).apply { rewind() },
              indices = indices.duplicate().order(ByteOrder.nativeOrder()).asIntBuffer().apply { rewind() },
            ),
          )
        }
      }
      val primitiveData = nativePrimitiveData(handle) ?: LongArray(0)
      val primitiveBounds = nativePrimitiveBounds(handle) ?: DoubleArray(0)
      NativeBimCache(
        handle = handle,
        chunks = chunks,
        primitives = buildPrimitives(primitiveData, primitiveBounds),
      )
    } catch (_: Throwable) {
      nativeClose(handle)
      null
    }
  }

  fun lastError(): String = nativeLastError()

  private fun buildPrimitives(data: LongArray, bounds: DoubleArray): List<NativeBimCachePrimitive> {
    val primitiveCount = minOf(data.size / 4, bounds.size / 6)
    return List(primitiveCount) { index ->
      NativeBimCachePrimitive(
        elementId = data[index * 4],
        kind = kindFromNativeValue(data[index * 4 + 1]),
        levelId = data[index * 4 + 3],
        sourceBounds = sceneBounds(bounds, index * 6),
      )
    }
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

  class NativeBimCache internal constructor(
    private val handle: Long,
    val chunks: List<NativeBimCacheChunk>,
    val primitives: List<NativeBimCachePrimitive>,
  ) : AutoCloseable {
    private var closed = false

    fun pick(origin: ScenePoint, direction: ScenePoint, visibleKinds: Set<String>): Long? {
      if (closed) return null
      // Filament: X/Y-up/-Z-plan. Cache: X/Y-plan/Z-up.
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

internal data class NativeBimCacheChunk(
  val levelId: Long,
  val materialCategory: String,
  val sourceBounds: SceneBounds,
  val positions: ByteBuffer,
  val indices: IntBuffer,
)

internal data class NativeBimCachePrimitive(
  val elementId: Long,
  val kind: String,
  val levelId: Long,
  val sourceBounds: SceneBounds,
)
