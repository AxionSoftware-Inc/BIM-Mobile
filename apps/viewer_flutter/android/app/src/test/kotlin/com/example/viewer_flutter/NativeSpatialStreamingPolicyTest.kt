package com.example.viewer_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeSpatialStreamingPolicyTest {
  @Test
  fun keepsOnlyCameraRelevantBoundedWorkingSet() {
    val policy = NativeSpatialStreamingPolicy(
      NativeSpatialStreamingPolicy.Config(
        maxResidentChunks = 4,
        maxResidentBytes = 64L * 1024L * 1024L,
        alwaysResidentDistanceMeters = 15.0,
        streamDistanceMeters = 120.0,
      ),
    )
    val chunks = buildList {
      for (index in 0 until 8) {
        add(chunk(index, x = 20.0 + index * 10.0))
      }
      add(chunk(100, x = -80.0))
    }

    val decision = policy.decide(
      camera = NativeSpatialStreamingPolicy.Camera(
        position = ScenePoint(0.0, 0.0, 0.0),
        forward = ScenePoint(1.0, 0.0, 0.0),
      ),
      chunks = chunks,
      currentResident = setOf(100),
    )

    assertEquals(4, decision.loadOrder.size)
    assertFalse(decision.keepResident.contains(100))
    assertTrue(decision.evict.contains(100))
    assertTrue(decision.loadOrder.all { it in 0 until 8 })
  }

  @Test
  fun residencyHysteresisPreventsCameraThrash() {
    val policy = NativeSpatialStreamingPolicy(
      NativeSpatialStreamingPolicy.Config(
        maxResidentChunks = 8,
        maxResidentBytes = 64L * 1024L * 1024L,
        alwaysResidentDistanceMeters = 10.0,
        streamDistanceMeters = 100.0,
        residentHysteresisMultiplier = 1.25,
      ),
    )
    val resident = chunk(1, x = 112.0)
    val sameDistanceCold = chunk(2, x = 112.0, y = 2.0)

    val decision = policy.decide(
      camera = NativeSpatialStreamingPolicy.Camera(
        position = ScenePoint(0.0, 0.0, 0.0),
        forward = ScenePoint(1.0, 0.0, 0.0),
      ),
      chunks = listOf(resident, sameDistanceCold),
      currentResident = setOf(1),
    )

    assertTrue(decision.keepResident.contains(1))
    assertFalse(decision.loadOrder.contains(2))
    assertFalse(decision.evict.contains(1))
  }

  @Test
  fun byteBudgetCapsResidentSetEvenWhenManyChunksAreVisible() {
    val policy = NativeSpatialStreamingPolicy(
      NativeSpatialStreamingPolicy.Config(
        maxResidentChunks = 100,
        maxResidentBytes = 10_000L,
        streamDistanceMeters = 500.0,
      ),
    )
    val chunks = List(20) { index ->
      NativeSpatialStreamingPolicy.Chunk(
        index = index,
        bounds = bounds(20.0 + index, 0.0),
        estimatedGpuBytes = 4_000L,
      )
    }

    val decision = policy.decide(
      camera = NativeSpatialStreamingPolicy.Camera(
        position = ScenePoint(0.0, 0.0, 0.0),
        forward = ScenePoint(1.0, 0.0, 0.0),
      ),
      chunks = chunks,
      currentResident = emptySet(),
    )

    assertEquals(2, decision.loadOrder.size)
    assertEquals(8_000L, decision.targetResidentBytes)
  }

  private fun chunk(
    index: Int,
    x: Double,
    y: Double = 0.0,
  ): NativeSpatialStreamingPolicy.Chunk = NativeSpatialStreamingPolicy.Chunk(
    index = index,
    bounds = bounds(x, y),
    estimatedGpuBytes = 1024L,
  )

  private fun bounds(x: Double, y: Double): SceneBounds = SceneBounds(
    min = ScenePoint(x - 1.0, y - 1.0, -1.0),
    max = ScenePoint(x + 1.0, y + 1.0, 1.0),
  )
}
