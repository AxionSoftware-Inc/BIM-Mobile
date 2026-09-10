package com.example.viewer_flutter

import android.os.Debug

/**
 * Process-memory telemetry used by viewport diagnostics.
 *
 * `Runtime.totalMemory() - Runtime.freeMemory()` is only the managed JVM heap
 * and misses exactly the allocations a native BIM renderer cares about:
 * direct buffers, C++ cache/BVH data and much of Filament's native state.
 * Android's PSS counters are not a perfect GPU-memory meter, but they are a
 * substantially better process-level guard for large-project regression tests.
 */
internal object NativeProcessMemoryTelemetry {
  fun snapshot(): Map<String, Any> {
    val info = Debug.MemoryInfo()
    Debug.getMemoryInfo(info)
    val runtime = Runtime.getRuntime()
    val javaHeapBytes = runtime.totalMemory() - runtime.freeMemory()

    return linkedMapOf(
      "javaHeapMb" to bytesToMb(javaHeapBytes),
      "totalPssMb" to kbToMb(info.totalPss),
      "dalvikPssMb" to kbToMb(info.dalvikPss),
      "nativePssMb" to kbToMb(info.nativePss),
      "otherPssMb" to kbToMb(info.otherPss),
      // PSS is the canonical regression metric. It includes shared pages
      // proportionally and is less misleading than JVM heap alone.
      "memoryMetric" to "android_pss",
    )
  }

  private fun kbToMb(kb: Int): Double = kb.toDouble() / 1024.0
  private fun bytesToMb(bytes: Long): Double = bytes.toDouble() / (1024.0 * 1024.0)
}
