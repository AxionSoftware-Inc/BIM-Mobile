package com.example.viewer_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ViewportArchitecturalMaterialPolicyTest {
  @Test
  fun `wall families stay low cardinality and matte`() {
    val samples = listOf(
      mapOf("wall_type_name" to "Exterior Brick Wall") to "wall:Exterior",
      mapOf("wall_type_name" to "Interior Gypsum") to "wall:Interior",
      mapOf("wall_type_name" to "Cast Concrete") to "wall:Structural",
      mapOf("wall_type_name" to "Curtain Glass") to "wall:Exterior",
      emptyMap<String, String>() to "wall:Unknown",
    )

    val descriptors = samples.map { (metadata, materialCategory) ->
      ViewportArchitecturalMaterialPolicy.wallDescriptor(metadata, materialCategory)
    }

    assertEquals(
      setOf(
        ViewportArchitecturalMaterialPolicy.WallFamily.BRICK,
        ViewportArchitecturalMaterialPolicy.WallFamily.PLASTER,
        ViewportArchitecturalMaterialPolicy.WallFamily.CONCRETE,
        ViewportArchitecturalMaterialPolicy.WallFamily.GLASS,
      ),
      descriptors.map { it.family }.toSet(),
    )
    descriptors
      .filter { it.family != ViewportArchitecturalMaterialPolicy.WallFamily.GLASS }
      .forEach { descriptor ->
        assertEquals(0.0f, descriptor.metallic, 0.0f)
        assertTrue(descriptor.roughness >= 0.90f)
      }
  }

  @Test
  fun `many identical walls collapse to one material family key`() {
    val keys = List(10_000) {
      ViewportArchitecturalMaterialPolicy.wallFamilyKey(
        metadata = mapOf(
          "wall_type_name" to "Exterior Brick Wall",
          "wall_type_category" to "Exterior",
        ),
        materialCategory = "wall:Exterior|Exterior Brick Wall",
      )
    }

    assertEquals(1, keys.toSet().size)
    assertEquals("wall:brick", keys.first())
  }

  @Test
  fun `cache category can recover surface family without object metadata`() {
    assertEquals(
      ViewportArchitecturalMaterialPolicy.WallFamily.CONCRETE,
      ViewportArchitecturalMaterialPolicy.wallDescriptor(
        metadata = emptyMap(),
        materialCategory = "wall:Structural Concrete",
      ).family,
    )
  }
}
