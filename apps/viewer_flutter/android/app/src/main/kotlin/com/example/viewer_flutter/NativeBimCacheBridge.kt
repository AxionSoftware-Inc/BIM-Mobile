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
        levelId = data[index * 4 + 3],
        sourceBounds = sceneBounds(bounds, index * 6),
      )
    }
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
  val levelId: Long,
  val sourceBounds: SceneBounds,
)
