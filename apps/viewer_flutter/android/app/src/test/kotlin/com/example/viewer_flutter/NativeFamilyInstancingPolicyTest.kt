package com.example.viewer_flutter

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeFamilyInstancingPolicyTest {
  @Test
  fun preservesExistingOpeningAndColumnInstancing() {
    for (kind in listOf("door", "window", "column")) {
      assertTrue(
        NativeFamilyInstancingPolicy.isCandidate(
          normalizedKind = kind,
          metadata = emptyMap(),
          groupingEnabled = true,
          clipActive = false,
        ),
      )
    }
  }

  @Test
  fun acceptsExplicitFamilyBackedProxyAndFurniture() {
    for (kind in listOf("proxy", "furniture", "casework", "genericmodel")) {
      assertTrue(
        NativeFamilyInstancingPolicy.isCandidate(
          normalizedKind = kind,
          metadata = mapOf("family_asset_id" to "builtin:chair"),
          groupingEnabled = true,
          clipActive = false,
        ),
      )
    }
  }

  @Test
  fun rejectsGenericImportedProxyWithoutFamilyIdentity() {
    assertFalse(
      NativeFamilyInstancingPolicy.isCandidate(
        normalizedKind = "proxy",
        metadata = mapOf("source_format" to "ifc"),
        groupingEnabled = true,
        clipActive = false,
      ),
    )
  }

  @Test
  fun neverAdmitsSystemGeometryEvenWithFamilyMetadata() {
    for (kind in listOf("wall", "floor", "slab", "ceiling", "roof", "beam", "stair", "room")) {
      assertFalse(
        NativeFamilyInstancingPolicy.isCandidate(
          normalizedKind = kind,
          metadata = mapOf("family_asset_id" to "unexpected:$kind"),
          groupingEnabled = true,
          clipActive = false,
        ),
      )
    }
  }

  @Test
  fun clippingAndSmallSceneModesDisableGrouping() {
    val metadata = mapOf("family_asset_id" to "builtin:chair")
    assertFalse(
      NativeFamilyInstancingPolicy.isCandidate(
        normalizedKind = "furniture",
        metadata = metadata,
        groupingEnabled = false,
        clipActive = false,
      ),
    )
    assertFalse(
      NativeFamilyInstancingPolicy.isCandidate(
        normalizedKind = "furniture",
        metadata = metadata,
        groupingEnabled = true,
        clipActive = true,
      ),
    )
  }
}
