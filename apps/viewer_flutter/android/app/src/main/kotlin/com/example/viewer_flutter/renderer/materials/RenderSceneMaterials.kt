package com.example.viewer_flutter

// BIM sun preset: a strong directional source with restrained environment
// fill. This keeps the sun-facing facade bright while preserving a readable
// light/shadow boundary on the opposite facade and on the receiver plane.
internal const val BIM_SUN_INTENSITY = 65000.0f
// Keep the environment restrained for the lit Shaded view. Solid is unlit and
// therefore independent of scene lighting, matching a clean coordination view.
internal const val BIM_IBL_INTENSITY = 6000.0f
internal const val BIM_SUN_ANGULAR_RADIUS = 0.018f

internal const val FLAT_COLOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    // Solid must be a genuinely flat coordination surface. Deriving a normal
    // from screen-space derivatives here exposed triangulation as a moving
    // diagonal band while orbiting. Architectural borders belong to the
    // separate depth-tested edge pass.
    material.baseColor = materialParams.baseColor;
}
"""

internal const val PLASTER_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float footprint = max(max(fwidth(world.x), fwidth(world.y)), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.020, 0.12, footprint);
    // Broad, low-contrast grain reads as plaster without turning into a
    // sparkling screen-space pattern when the camera rotates.
    float grain = 0.5 * sin(world.x * 2.1 + world.z * 1.7)
        + 0.5 * sin(world.y * 2.7 - world.x * 1.1);
    float variation = grain * 0.014 * detailFade * materialParams.displayShade;
    material.baseColor = float4(
        materialParams.baseColor.rgb * (1.0 + variation),
        materialParams.baseColor.a
    );
}
"""

internal const val WOOD_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float footprint = max(fwidth(world.x + world.z), 0.0005);
    float detailFade = 1.0 - smoothstep(0.012, 0.085, footprint);
    // Keep the grain deliberately broad. The old 46x sinusoid crawled across
    // the surface at grazing angles and looked like a specular highlight.
    float grain = 0.5 * sin((world.x + world.z) * 7.5 + sin(world.y * 1.6))
        + 0.5 * sin((world.x - world.z) * 3.2);
    float variation = grain * 0.045 * detailFade * materialParams.displayShade;
    material.baseColor = float4(
        materialParams.baseColor.rgb * (1.0 + variation),
        materialParams.baseColor.a
    );
}
"""

internal const val FLOOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float floorKind = materialParams.floorKind;
    float footprint = max(fwidth(world.x), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.020, 0.13, footprint);

    float woodCoord = (world.x + world.z * 0.18) / 0.18;
    float woodCell = fract(woodCoord);
    float woodDistance = min(woodCell, 1.0 - woodCell);
    float woodAa = max(fwidth(woodCoord) * 1.35, 0.001);
    float woodJoint = 1.0 - smoothstep(0.030 - woodAa, 0.030 + woodAa, woodDistance);

    float concreteX = world.x / 0.60;
    float concreteZ = world.z / 0.60;
    float concreteCellX = fract(concreteX);
    float concreteCellZ = fract(concreteZ);
    float concreteDistanceX = min(concreteCellX, 1.0 - concreteCellX);
    float concreteDistanceZ = min(concreteCellZ, 1.0 - concreteCellZ);
    float concreteAaX = max(fwidth(concreteX) * 1.35, 0.001);
    float concreteAaZ = max(fwidth(concreteZ) * 1.35, 0.001);
    float concreteJointX = 1.0 - smoothstep(0.022 - concreteAaX, 0.022 + concreteAaX, concreteDistanceX);
    float concreteJointZ = 1.0 - smoothstep(0.022 - concreteAaZ, 0.022 + concreteAaZ, concreteDistanceZ);

    float asphaltCoord = (world.x + world.z) / 0.42;
    float asphaltCell = fract(asphaltCoord);
    float asphaltDistance = min(asphaltCell, 1.0 - asphaltCell);
    float asphaltAa = max(fwidth(asphaltCoord) * 1.35, 0.001);
    float asphaltJoint = 1.0 - smoothstep(0.018 - asphaltAa, 0.018 + asphaltAa, asphaltDistance);

    float grassCoord = (world.x - world.z) / 0.31;
    float grassCell = fract(grassCoord);
    float grassDistance = min(grassCell, 1.0 - grassCell);
    float grassAa = max(fwidth(grassCoord) * 1.35, 0.001);
    float grassJoint = 1.0 - smoothstep(0.026 - grassAa, 0.026 + grassAa, grassDistance);

    float pavingX = world.x / 0.45;
    float pavingZ = world.z / 0.45;
    float pavingCellX = fract(pavingX);
    float pavingCellZ = fract(pavingZ);
    float pavingDistanceX = min(pavingCellX, 1.0 - pavingCellX);
    float pavingDistanceZ = min(pavingCellZ, 1.0 - pavingCellZ);
    float pavingAaX = max(fwidth(pavingX) * 1.35, 0.001);
    float pavingAaZ = max(fwidth(pavingZ) * 1.35, 0.001);
    float pavingJointX = 1.0 - smoothstep(0.022 - pavingAaX, 0.022 + pavingAaX, pavingDistanceX);
    float pavingJointZ = 1.0 - smoothstep(0.022 - pavingAaZ, 0.022 + pavingAaZ, pavingDistanceZ);

    float line = floorKind < 0.5
        ? asphaltJoint * 0.08
        : floorKind < 1.5
            ? max(concreteJointX, concreteJointZ) * 0.12
            : floorKind < 2.5
                ? woodJoint * 0.18
                : floorKind < 3.5
                    ? grassJoint * 0.06
                    : max(pavingJointX, pavingJointZ) * 0.13;
    line *= detailFade;

    float broadA = 0.5 * sin(world.x * 1.23 + world.z * 0.71);
    float broadB = 0.5 * sin(world.z * 1.67 - world.x * 0.54);
    float broad = (broadA + broadB) * detailFade * materialParams.displayShade;
    float woodGrain = (
        0.5 * sin(world.x * 7.0 + world.z * 1.8)
        + 0.5 * sin(world.x * 3.0 - world.z * 0.9)
    ) * detailFade * materialParams.displayShade;

    float3 asphalt = materialParams.baseColor.rgb * (0.94 + broad * 0.018 - line);
    float3 concrete = materialParams.baseColor.rgb * (0.99 + broad * 0.022 - line);
    float3 wood = materialParams.baseColor.rgb * (1.0 + woodGrain * 0.035 - line);
    float3 grass = materialParams.baseColor.rgb * (0.98 + broad * 0.030 - line);
    float3 paving = materialParams.baseColor.rgb * (1.0 + broad * 0.018 - line);
    float3 textured = floorKind < 0.5 ? asphalt
        : floorKind < 1.5 ? concrete
        : floorKind < 2.5 ? wood
        : floorKind < 3.5 ? grass
        : paving;
    material.baseColor = float4(textured, materialParams.baseColor.a);
}
"""

internal const val SOLID_FLOOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float floorKind = materialParams.floorKind;
    float footprint = max(fwidth(world.x), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.020, 0.13, footprint);

    float woodCoord = (world.x + world.z * 0.18) / 0.18;
    float woodCell = fract(woodCoord);
    float woodDistance = min(woodCell, 1.0 - woodCell);
    float woodAa = max(fwidth(woodCoord) * 1.35, 0.001);
    float woodJoint = 1.0 - smoothstep(0.030 - woodAa, 0.030 + woodAa, woodDistance);

    float concreteX = world.x / 0.60;
    float concreteZ = world.z / 0.60;
    float concreteCellX = fract(concreteX);
    float concreteCellZ = fract(concreteZ);
    float concreteDistanceX = min(concreteCellX, 1.0 - concreteCellX);
    float concreteDistanceZ = min(concreteCellZ, 1.0 - concreteCellZ);
    float concreteAaX = max(fwidth(concreteX) * 1.35, 0.001);
    float concreteAaZ = max(fwidth(concreteZ) * 1.35, 0.001);
    float concreteJointX = 1.0 - smoothstep(0.022 - concreteAaX, 0.022 + concreteAaX, concreteDistanceX);
    float concreteJointZ = 1.0 - smoothstep(0.022 - concreteAaZ, 0.022 + concreteAaZ, concreteDistanceZ);

    float asphaltCoord = (world.x + world.z) / 0.42;
    float asphaltCell = fract(asphaltCoord);
    float asphaltDistance = min(asphaltCell, 1.0 - asphaltCell);
    float asphaltAa = max(fwidth(asphaltCoord) * 1.35, 0.001);
    float asphaltJoint = 1.0 - smoothstep(0.018 - asphaltAa, 0.018 + asphaltAa, asphaltDistance);

    float grassCoord = (world.x - world.z) / 0.31;
    float grassCell = fract(grassCoord);
    float grassDistance = min(grassCell, 1.0 - grassCell);
    float grassAa = max(fwidth(grassCoord) * 1.35, 0.001);
    float grassJoint = 1.0 - smoothstep(0.026 - grassAa, 0.026 + grassAa, grassDistance);

    float pavingX = world.x / 0.45;
    float pavingZ = world.z / 0.45;
    float pavingCellX = fract(pavingX);
    float pavingCellZ = fract(pavingZ);
    float pavingDistanceX = min(pavingCellX, 1.0 - pavingCellX);
    float pavingDistanceZ = min(pavingCellZ, 1.0 - pavingCellZ);
    float pavingAaX = max(fwidth(pavingX) * 1.35, 0.001);
    float pavingAaZ = max(fwidth(pavingZ) * 1.35, 0.001);
    float pavingJointX = 1.0 - smoothstep(0.022 - pavingAaX, 0.022 + pavingAaX, pavingDistanceX);
    float pavingJointZ = 1.0 - smoothstep(0.022 - pavingAaZ, 0.022 + pavingAaZ, pavingDistanceZ);

    float line = floorKind < 0.5
        ? asphaltJoint * 0.16
        : floorKind < 1.5
            ? max(concreteJointX, concreteJointZ) * 0.18
            : floorKind < 2.5
                ? woodJoint * 0.22
                : floorKind < 3.5
                    ? grassJoint * 0.10
                    : max(pavingJointX, pavingJointZ) * 0.18;
    float3 neutral = materialParams.baseColor.rgb * (1.0 - line * detailFade);
    // Solid floor faces are always opaque. Transparency is reserved for the
    // dedicated glass-wall material, otherwise imported alpha can make slabs
    // look like ghost geometry.
    material.baseColor = float4(neutral, 1.0);
}
"""

internal const val ROOF_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float footprint = max(fwidth(world.x), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.020, 0.13, footprint);

    float courseCoord = (world.x + world.z) / 0.28;
    float courseCell = fract(courseCoord);
    float courseDistance = min(courseCell, 1.0 - courseCell);
    float courseAa = max(fwidth(courseCoord) * 1.35, 0.001);
    float course = 1.0 - smoothstep(0.040 - courseAa, 0.040 + courseAa, courseDistance);

    float jointCoord = (world.x - world.z) / 0.42;
    float jointCell = fract(jointCoord);
    float jointDistance = min(jointCell, 1.0 - jointCell);
    float jointAa = max(fwidth(jointCoord) * 1.35, 0.001);
    float joint = 1.0 - smoothstep(0.030 - jointAa, 0.030 + jointAa, jointDistance);

    float line = max(course, joint) * 0.16 * detailFade * materialParams.displayShade;
    material.baseColor = float4(
        materialParams.baseColor.rgb * (1.0 - line),
        materialParams.baseColor.a
    );
}
"""

internal const val CONCRETE_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float footprint = max(max(fwidth(world.x), fwidth(world.y)), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.020, 0.12, footprint);
    // No hash speckle: broad deterministic grain stays matte while orbiting.
    float grain = 0.5 * sin(world.x * 1.55 + world.y * 0.83)
        + 0.5 * sin(world.z * 2.05 - world.x * 0.74);
    float variation = grain * 0.020 * detailFade * materialParams.displayShade;
    material.baseColor = float4(
        materialParams.baseColor.rgb * (1.0 + variation),
        materialParams.baseColor.a
    );
}
"""

// Stable mobile shaded face material. Keep this path deterministic on the
// tablet OpenGL backend; semantic material colors provide the shaded
// appearance without a fake world-space light band or driver-sensitive custom
// LIT inputs. The real matte-PBR path can be enabled only after device
// validation of normals/IBL on Adreno/Mali.
internal const val ARCHITECTURAL_SHADED_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    material.baseColor = materialParams.baseColor;
}
"""

internal const val GRID_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float2 relative = world.xz - materialParams.gridCenter.xz;
    float distanceFromCenter = length(relative);
    float fade = 1.0 - smoothstep(materialParams.gridFadeStart, materialParams.gridRadius, distanceFromCenter);
    float majorX = 1.0 - smoothstep(0.0, 0.06, abs(fract(relative.x / 5.0 + 0.5) - 0.5));
    float majorZ = 1.0 - smoothstep(0.0, 0.06, abs(fract(relative.y / 5.0 + 0.5) - 0.5));
    float major = max(majorX, majorZ);
    float strength = mix(0.68, 1.0, major);
    material.baseColor = float4(materialParams.baseColor.rgb, materialParams.baseColor.a * fade * strength);
}
"""
