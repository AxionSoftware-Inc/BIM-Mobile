package com.example.viewer_flutter

/**
 * Stable, low-cardinality viewport material families.
 *
 * A campus model may contain tens of thousands of walls, but the renderer
 * should never create one material or texture object per wall. Geometry is
 * batched by these semantic surface families; per-element state remains a
 * compact family/type id plus the ordinary BIM parameters.
 *
 * The current Android wall shader deliberately stays on the proven UNLIT
 * mobile path. [roughness], [metallic] and [reflectance] are therefore policy
 * targets for the validated PBR path rather than evidence that the current
 * shader is physically lit. Keeping them here prevents a future texture/PBR
 * migration from accidentally assigning glossy metal defaults to plaster,
 * brick or concrete.
 */
internal object ViewportArchitecturalMaterialPolicy {
  enum class WallFamily(
    val shaderKind: Float,
    val batchKey: String,
    val roughness: Float,
    val metallic: Float,
    val reflectance: Float,
    val textureScaleMeters: Float,
  ) {
    BRICK(
      shaderKind = 0.0f,
      batchKey = "wall:brick",
      roughness = 0.90f,
      metallic = 0.0f,
      reflectance = 0.32f,
      textureScaleMeters = 0.24f,
    ),
    PLASTER(
      shaderKind = 1.0f,
      batchKey = "wall:plaster",
      roughness = 0.94f,
      metallic = 0.0f,
      reflectance = 0.28f,
      textureScaleMeters = 0.50f,
    ),
    CONCRETE(
      shaderKind = 2.0f,
      batchKey = "wall:concrete",
      roughness = 0.92f,
      metallic = 0.0f,
      reflectance = 0.30f,
      textureScaleMeters = 0.65f,
    ),
    GLASS(
      shaderKind = 3.0f,
      batchKey = "wall:glass",
      // Glass is a dedicated transparent pipeline. These values are kept
      // conservative so the eventual PBR migration does not make glazing
      // read like chrome on mobile HDRI environments.
      roughness = 0.18f,
      metallic = 0.0f,
      reflectance = 0.50f,
      textureScaleMeters = 1.0f,
    ),
  }

  data class Descriptor(
    val family: WallFamily,
    val batchKey: String = family.batchKey,
    val shaderKind: Float = family.shaderKind,
    val roughness: Float = family.roughness,
    val metallic: Float = family.metallic,
    val reflectance: Float = family.reflectance,
    val textureScaleMeters: Float = family.textureScaleMeters,
  )

  fun wallDescriptor(
    metadata: Map<String, String>,
    materialCategory: String,
  ): Descriptor {
    val typeName = metadata["wall_type_name"]?.trim()?.lowercase().orEmpty()
    val category = metadata["wall_type_category"]?.trim()?.lowercase().orEmpty()
    val cacheSurface = materialCategory.trim().lowercase()

    val family = when {
      typeName.contains("glass") || cacheSurface.contains("glass") -> WallFamily.GLASS
      typeName.contains("concrete") || cacheSurface.contains("concrete") -> WallFamily.CONCRETE
      typeName.contains("brick") || cacheSurface.contains("brick") -> WallFamily.BRICK
      typeName.contains("interior") || category == "interior" ||
        cacheSurface.contains("interior") -> WallFamily.PLASTER
      typeName.contains("exterior") || category == "exterior" ||
        cacheSurface.contains("exterior") -> WallFamily.BRICK
      else -> WallFamily.PLASTER
    }
    return Descriptor(family)
  }

  /**
   * Quantizes an arbitrary wall collection to the small renderer family set.
   * Useful for diagnostics/benchmarks: the number of wall surface batches
   * should track spatial tiles and these families, not wall count.
   */
  fun wallFamilyKey(
    metadata: Map<String, String>,
    materialCategory: String,
  ): String = wallDescriptor(metadata, materialCategory).batchKey
}
