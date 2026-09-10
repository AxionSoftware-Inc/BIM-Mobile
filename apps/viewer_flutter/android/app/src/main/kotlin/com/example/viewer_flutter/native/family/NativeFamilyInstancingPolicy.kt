package com.example.viewer_flutter

/**
 * Renderer-side admission policy for shared family geometry.
 *
 * Geometry equality remains the final safety boundary in
 * RenderSceneFilamentHostView.normalizedInstanceGeometry(): this policy merely
 * decides which semantic objects are worth attempting to group. It must never
 * turn system geometry such as walls/floors into family instances.
 */
internal object NativeFamilyInstancingPolicy {
  private val legacyInstanceKinds = setOf("door", "window", "column")

  private val familyInstanceKinds = setOf(
    "proxy",
    "furniture",
    "casework",
    "genericmodel",
    "generic_model",
    "mechanicalequipment",
    "mechanical_equipment",
    "plumbingfixture",
    "plumbing_fixture",
    "lightingfixture",
    "lighting_fixture",
    "specialtyequipment",
    "specialty_equipment",
    "planting",
  )

  private val systemGeometryKinds = setOf(
    "wall",
    "floor",
    "slab",
    "ceiling",
    "roof",
    "beam",
    "stair",
    "room",
  )

  fun isCandidate(
    normalizedKind: String,
    metadata: Map<String, String>,
    groupingEnabled: Boolean,
    clipActive: Boolean,
  ): Boolean {
    if (!groupingEnabled || clipActive) return false
    val kind = normalizedKind.trim().lowercase()
    if (kind in legacyInstanceKinds) return true
    if (kind in systemGeometryKinds) return false
    if (kind !in familyInstanceKinds) return false

    // A proxy/category alone is not enough. Only explicit family-backed
    // objects may enter the shared-family path; imported IFC/CAD proxy meshes
    // remain ordinary streamed/batched geometry.
    return metadata["family_asset_id"]?.isNotBlank() == true ||
      metadata["familyAssetId"]?.isNotBlank() == true ||
      metadata["family_asset_key"]?.isNotBlank() == true
  }
}
