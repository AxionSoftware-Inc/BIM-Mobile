from pathlib import Path
import re

HOST = Path("apps/viewer_flutter/android/app/src/main/kotlin/com/example/viewer_flutter/RenderSceneFilamentHostView.kt")
text = HOST.read_text(encoding="utf-8")

MARKER = "NATIVE_STREAMING_WORKING_SET_V2"
if MARKER in text:
    print("Native streaming patch already applied; no changes needed.")
    raise SystemExit(0)


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


def replace_function(signature: str, replacement: str) -> None:
    global text
    start = text.find(signature)
    if start < 0:
        raise RuntimeError(f"Function not found: {signature}")
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError(f"Opening brace not found: {signature}")
    depth = 0
    i = brace
    in_string = False
    in_char = False
    in_line_comment = False
    in_block_comment = False
    escaped = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
        elif in_char:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "'":
                in_char = False
        else:
            if ch == "/" and nxt == "/":
                in_line_comment = True
                i += 1
            elif ch == "/" and nxt == "*":
                in_block_comment = True
                i += 1
            elif ch == '"':
                in_string = True
            elif ch == "'":
                in_char = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    text = text[:start] + replacement + text[end:]
                    return
        i += 1
    raise RuntimeError(f"Closing brace not found: {signature}")


# Track ownership so one streamed chunk can be destroyed without touching
# unrelated scene batches. This is required for true bounded GPU residency.
face_pattern = re.compile(
    r"(private data class FaceBatchEntry\([\s\S]*?val nativeKindMask: Long\? = null,\n)(\s*var attached: Boolean = false,)",
    re.MULTILINE,
)
text, n = face_pattern.subn(r"\1  val nativeChunkIndex: Int? = null,\n\2", text, count=1)
if n != 1:
    raise RuntimeError(f"FaceBatchEntry ownership field: expected 1 match, found {n}")

edge_pattern = re.compile(
    r"(private data class EdgeBatchKey\([\s\S]*?val nativeKindMask: Long\? = null,\n)(\s*\))",
    re.MULTILINE,
)
text, n = edge_pattern.subn(r"\1  val nativeChunkIndex: Int? = null,\n\2", text, count=1)
if n != 1:
    raise RuntimeError(f"EdgeBatchKey ownership field: expected 1 match, found {n}")

replace_once(
    "  private var nativeCacheFullBounds: SceneBounds? = null\n",
    "  private var nativeCacheFullBounds: SceneBounds? = null\n"
    "  // NATIVE_STREAMING_WORKING_SET_V2: residency is camera/budget bounded.\n"
    "  // Knowing every cache chunk must never imply keeping every GPU resource alive.\n"
    "  private val nativeSpatialStreamingPolicy = NativeSpatialStreamingPolicy()\n"
    "  private var nativeCacheTargetResidentBytes = 0L\n"
    "  private var nativeCacheEvictionCount = 0L\n",
    "streaming state",
)

# Semantic scene creation must stay geometry-free. Touching positions/indices
# here would materialize every direct buffer before the first camera frame.
replace_once(
    "      vertexCount = cache.chunks.sumOf { it.positions.capacity() / 12 },\n"
    "      indexCount = cache.chunks.sumOf { it.indices.capacity() },\n",
    "      // The Flutter/Kotlin semantic scene owns no mesh payload. Exact GPU\n"
    "      // counts are resident-working-set metrics, not startup metadata.\n"
    "      vertexCount = 0,\n"
    "      indexCount = 0,\n",
    "native semantic scene counts",
)

# Metrics must report the resident render working set without forcing cold
# native geometry into memory merely to count it.
replace_once(
    "      vertexCount = cache?.chunks?.sumOf { it.positions.capacity() / 12 }\n"
    "        ?: (entries.sumOf { it.vertexBuffer.vertexCount } + faceBatches.sumOf { it.vertexCount } +\n"
    "          instanceFaceGroups.sumOf { it.vertexCount * it.objectCount }),\n"
    "      indexCount = cache?.chunks?.sumOf { it.indices.capacity() }\n"
    "        ?: (entries.sumOf { it.indexBuffer.indexCount } + faceBatches.sumOf { it.indexCount } +\n"
    "          instanceFaceGroups.sumOf { it.indexCount * it.objectCount }),\n",
    "      // Resident counts only. Reading cache.positions/indices here would\n"
    "      // defeat lazy CPU streaming during a diagnostics/status refresh.\n"
    "      vertexCount = entries.sumOf { it.vertexBuffer.vertexCount } +\n"
    "        faceBatches.sumOf { it.vertexCount } +\n"
    "        instanceFaceGroups.sumOf { it.vertexCount * it.objectCount },\n"
    "      indexCount = entries.sumOf { it.indexBuffer.indexCount } +\n"
    "        faceBatches.sumOf { it.indexCount } +\n"
    "        instanceFaceGroups.sumOf { it.indexCount * it.objectCount },\n",
    "resident metrics counts",
)

# Give both face and contour resources an owning cache chunk. The first form is
# the face batch; the remaining native edge keys all have an `index` in scope.
replace_once(
    "          nativeKindMask = chunk.kindMask,\n          attached = visible,\n",
    "          nativeKindMask = chunk.kindMask,\n"
    "          nativeChunkIndex = index,\n"
    "          attached = visible,\n",
    "native face ownership",
)

# Every native edge key is created inside a resident/pending chunk loop with an
# `index` variable. Generic RenderScene edge keys keep nativeChunkIndex == null.
text, edge_key_count = re.subn(
    r"(nativeKindMask = chunk\.kindMask,\n)(\s*)(\))",
    r"\1\2nativeChunkIndex = index,\n\2\3",
    text,
)
if edge_key_count < 2:
    raise RuntimeError(f"native edge ownership: expected >=2 matches, found {edge_key_count}")

# Initial cache build selects only the camera-relevant bounded target rather
# than enqueueing the entire project for eventual upload.
replace_once(
    "    cache.chunks.indices\n"
    "      .sortedBy { index -> nativeCacheChunkDistanceSquared(cache, index) }\n"
    "      .forEach(nativeCachePendingChunks::addLast)\n",
    "    val initialDecision = nativeSpatialStreamingPolicy.decide(\n"
    "      camera = nativeCacheStreamingCamera(),\n"
    "      chunks = nativeSpatialStreamingPolicy.chunksFromCache(cache.chunks),\n"
    "      currentResident = nativeCacheResidentChunks,\n"
    "    )\n"
    "    nativeCacheTargetResidentBytes = initialDecision.targetResidentBytes\n"
    "    initialDecision.loadOrder.forEach(nativeCachePendingChunks::addLast)\n",
    "initial bounded target",
)

# Existing completion text assumed the whole project was uploaded. With real
# streaming, completion means the current working set is ready.
text = text.replace(
    '      statusMessage = "Loaded ${nativeCacheResidentChunks.size}/${cache.chunks.size} native BIM chunks."',
    '      statusMessage = "Resident ${nativeCacheResidentChunks.size}/${cache.chunks.size} native BIM chunks (camera-bounded working set)."',
)

# Real Android PSS includes native/direct allocations that JVM heap alone misses.
text = text.replace(
    "    val processMemory = (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()).toDouble() / (1024.0 * 1024.0)",
    "    val processMemory = (NativeProcessMemoryTelemetry.snapshot()[\"totalPssMb\"] as? Double) ?: 0.0",
    1,
)
text = text.replace(
    "    residentMemoryMb = (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()).toDouble() / (1024.0 * 1024.0)",
    "    residentMemoryMb = (NativeProcessMemoryTelemetry.snapshot()[\"totalPssMb\"] as? Double) ?: 0.0",
    1,
)

# Surface the memory and residency budget in diagnostics without changing the
# existing top-level diagnostics contract.
replace_once(
    '    "nativeCachePendingChunks" to nativeCachePendingChunks.size,\n',
    '    "nativeCachePendingChunks" to nativeCachePendingChunks.size,\n'
    '    "nativeCacheTargetResidentMb" to nativeCacheTargetResidentBytes.toDouble() / (1024.0 * 1024.0),\n'
    '    "nativeCacheEvictions" to nativeCacheEvictionCount,\n'
    '    "processMemory" to NativeProcessMemoryTelemetry.snapshot(),\n',
    "diagnostics residency telemetry",
)

replace_function(
    "  private fun closeNativeBimCache()",
    '''  private fun closeNativeBimCache() {
    nativeCacheUploadRevision += 1L
    nativeCacheUploadPosted = false
    nativeCacheReprioritizePosted = false
    nativeCachePendingChunks.clear()

    val cache = nativeBimCache
    val currentEngine = engine
    if (cache != null && currentEngine != null) {
      // Destroy Filament resources before dropping direct native views. This
      // order prevents a buffer from being invalidated while the driver still
      // references it and also prevents double-destroy during global cleanup.
      nativeCacheResidentChunks.toList().forEach { index ->
        destroyNativeBimCacheChunk(currentEngine, scene, cache, index)
      }
    } else {
      cache?.chunks?.forEach(NativeBimCacheChunk::releaseGeometryView)
      nativeCacheResidentChunks.clear()
    }
    nativeCacheTargetResidentBytes = 0L
    nativeCacheFullBounds = null
    cache?.close()
    nativeBimCache = null
  }''',
)

# Camera movement now changes the target set, evicts old resources and uploads
# only newly relevant chunks. The delayed coalescing remains so gestures do not
# turn into per-MotionEvent allocation/destruction storms.
replace_function(
    "  private fun scheduleNativeBimCacheReprioritization()",
    '''  private fun scheduleNativeBimCacheReprioritization() {
    val cache = nativeBimCache ?: return
    if (nativeCacheReprioritizePosted) return
    val revision = nativeCacheUploadRevision
    nativeCacheReprioritizePosted = true
    postDelayed({
      nativeCacheReprioritizePosted = false
      if (disposed || revision != nativeCacheUploadRevision || cache !== nativeBimCache) return@postDelayed

      val decision = nativeSpatialStreamingPolicy.decide(
        camera = nativeCacheStreamingCamera(),
        chunks = nativeSpatialStreamingPolicy.chunksFromCache(cache.chunks),
        currentResident = nativeCacheResidentChunks,
      )
      nativeCacheTargetResidentBytes = decision.targetResidentBytes

      // Evict first so a camera jump cannot transiently hold both the old and
      // new working sets and spike tablet GPU/native memory.
      val currentEngine = engine ?: return@postDelayed
      val currentScene = scene
      decision.evict.forEach { index ->
        destroyNativeBimCacheChunk(currentEngine, currentScene, cache, index)
      }

      nativeCachePendingChunks.clear()
      decision.loadOrder.forEach(nativeCachePendingChunks::addLast)
      if (nativeCachePendingChunks.isNotEmpty()) {
        val currentSceneRequired = currentScene ?: return@postDelayed
        val fallbackMaterial = material ?: return@postDelayed
        nativeCacheEdgeBudgetRemaining = NATIVE_CACHE_EDGE_SEGMENT_BUDGET
        uploadNativeBimCacheChunks(
          engine = currentEngine,
          scene = currentSceneRequired,
          cache = cache,
          fallbackMaterial = fallbackMaterial,
          revision = revision,
          maxChunks = NATIVE_CACHE_STEADY_UPLOAD_CHUNKS,
        )
      } else {
        updateMetrics()
        syncVisibility()
        renderDirty = true
        requestRender(250L)
      }
    }, NATIVE_CACHE_REPRIORITIZE_DELAY_MS)
  }''',
)

# Insert the real working-set lifecycle helpers directly before chunk creation.
anchor = "  private fun createNativeBimCacheChunk(\n"
pos = text.find(anchor)
if pos < 0:
    raise RuntimeError("createNativeBimCacheChunk anchor not found")
helpers = '''  /**
   * Returns the orbit camera in native cache coordinates (X/Y plan, Z up).
   * Filament uses X/Y-up/-Z-plan, so both position and direction need the same
   * axis conversion. Keeping this conversion here prevents policy drift from
   * the native picking/cache transform contract.
   */
  private fun nativeCacheStreamingCamera(): NativeSpatialStreamingPolicy.Camera {
    val center = orbitCenter
    val eye = if (projectionMode == "topDown") {
      ScenePoint(center.x, center.y + max(orbitDistance, topDownZoom * 2.5), center.z)
    } else {
      val cosPitch = cos(orbitPitchRadians)
      ScenePoint(
        center.x + orbitDistance * cosPitch * cos(orbitYawRadians),
        center.y + orbitDistance * sin(orbitPitchRadians),
        center.z + orbitDistance * cosPitch * sin(orbitYawRadians),
      )
    }
    val forward = ScenePoint(center.x - eye.x, center.y - eye.y, center.z - eye.z)
    return NativeSpatialStreamingPolicy.Camera(
      position = ScenePoint(eye.x, -eye.z, eye.y),
      forward = ScenePoint(forward.x, -forward.z, forward.y),
    )
  }

  /**
   * Frees one streamed chunk completely: scene attachment, Filament entity,
   * buffers/material instances and finally Kotlin's direct-buffer view.
   *
   * Removing entries from the batch lists is essential. Global teardown later
   * iterates those lists, so leaving an evicted entry there would double-free
   * Filament resources.
   */
  private fun destroyNativeBimCacheChunk(
    engine: Engine,
    scene: Scene?,
    cache: NativeBimCacheBridge.NativeBimCache,
    chunkIndex: Int,
  ) {
    val faceIterator = faceBatches.iterator()
    while (faceIterator.hasNext()) {
      val batch = faceIterator.next()
      if (batch.nativeChunkIndex != chunkIndex) continue
      if (batch.attached) scene?.removeEntity(batch.entity)
      engine.destroyEntity(batch.entity)
      engine.destroyMaterialInstance(batch.materialInstance)
      engine.destroyVertexBuffer(batch.vertexBuffer)
      engine.destroyIndexBuffer(batch.indexBuffer)
      EntityManager.get().destroy(batch.entity)
      faceIterator.remove()
    }

    val edgeIterator = edgeBatches.iterator()
    while (edgeIterator.hasNext()) {
      val batch = edgeIterator.next()
      if (batch.key.nativeChunkIndex != chunkIndex) continue
      if (batch.attached) scene?.removeEntity(batch.entity)
      engine.destroyEntity(batch.entity)
      engine.destroyMaterialInstance(batch.materialInstance)
      engine.destroyVertexBuffer(batch.vertexBuffer)
      engine.destroyIndexBuffer(batch.indexBuffer)
      EntityManager.get().destroy(batch.entity)
      edgeIterator.remove()
    }

    cache.chunks.getOrNull(chunkIndex)?.releaseGeometryView()
    if (nativeCacheResidentChunks.remove(chunkIndex)) nativeCacheEvictionCount += 1L
  }

'''
text = text[:pos] + helpers + text[pos:]

HOST.write_text(text, encoding="utf-8")
print("Applied bounded native BIM streaming/resource-lifecycle patch.")
