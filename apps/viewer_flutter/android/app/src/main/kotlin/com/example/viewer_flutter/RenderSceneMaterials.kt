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
    // Solid must be a genuinely flat coordination surface.  Deriving a
    // normal from screen-space derivatives here made a non-planar or
    // diagonally tessellated wall quad receive two different values, exposing
    // its internal triangle as a moving diagonal band while orbiting.  Edge
    // readability belongs to the separate depth-tested edge pass.
    material.baseColor = materialParams.baseColor;
}
"""

internal const val WALL_BRICK_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float row = floor(world.y / 0.075);
    float jointY = step(fract(world.y / 0.075), 0.018);
    float jointX = step(fract((world.x + mod(row, 2.0) * 0.12) / 0.24), 0.014);
    // Keep this subtle enough for a working BIM view, but distinct on a
    // tablet-sized wall face; the prior 16% contrast disappeared in Solid.
    float mortar = max(jointY, jointX) * 0.58 * materialParams.displayShade;
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(brick * shade, materialParams.baseColor.a);
}
"""

internal const val PLASTER_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float variation = 0.035 * sin(world.x * 31.0 + world.y * 17.0 + world.z * 23.0) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + variation) * shade, materialParams.baseColor.a);
}
"""

internal const val WOOD_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float grain = 0.10 * sin((world.x + world.z) * 46.0 + sin(world.y * 5.0)) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + grain) * shade, materialParams.baseColor.a);
}
"""

internal const val FLOOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float floorKind = materialParams.floorKind;
    float woodJoint = step(0.94, fract((world.x + world.z * 0.18) / 0.18));
    float woodGrain = 0.06 * sin(world.x * 58.0 + world.z * 9.0);
    float concreteJointX = step(0.965, fract(world.x / 0.60));
    float concreteJointZ = step(0.965, fract(world.z / 0.60));
    float asphaltJoint = step(0.975, fract((world.x + world.z) / 0.42));
    float line = floorKind < 0.5
        ? asphaltJoint * 0.12
        : floorKind < 1.5
            ? max(concreteJointX, concreteJointZ) * 0.16
            : floorKind < 2.5
                ? woodJoint * 0.25
                : floorKind < 3.5
                    ? step(0.94, fract((world.x - world.z) / 0.31)) * 0.10
                    : max(step(0.965, fract(world.x / 0.45)), step(0.965, fract(world.z / 0.45))) * 0.18;
    float speckle = fract(sin(dot(world.xz, float2(12.9898, 78.233))) * 43758.5453);
    float3 asphalt = materialParams.baseColor.rgb * (0.78 + speckle * 0.10 - line);
    float3 concrete = materialParams.baseColor.rgb * (0.96 + (speckle - 0.5) * 0.12 - line);
    float3 wood = materialParams.baseColor.rgb * (1.0 + woodGrain - line);
    float3 grass = materialParams.baseColor.rgb * (0.88 + speckle * 0.18 - line);
    float3 paving = materialParams.baseColor.rgb * (0.98 + (speckle - 0.5) * 0.08 - line);
    float3 textured = floorKind < 0.5 ? asphalt
        : floorKind < 1.5 ? concrete
        : floorKind < 2.5 ? wood
        : floorKind < 3.5 ? grass
        : paving;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(textured * shade, materialParams.baseColor.a);
}
"""

internal const val SOLID_FLOOR_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float floorKind = materialParams.floorKind;
    float woodJoint = step(0.94, fract((world.x + world.z * 0.18) / 0.18));
    float concreteJointX = step(0.965, fract(world.x / 0.60));
    float concreteJointZ = step(0.965, fract(world.z / 0.60));
    float asphaltJoint = step(0.975, fract((world.x + world.z) / 0.42));
    float line = floorKind < 0.5
        ? asphaltJoint * 0.22
        : floorKind < 1.5
            ? max(concreteJointX, concreteJointZ) * 0.24
            : floorKind < 2.5
                ? woodJoint * 0.30
                : floorKind < 3.5
                    ? step(0.94, fract((world.x - world.z) / 0.31)) * 0.14
                    : max(step(0.965, fract(world.x / 0.45)), step(0.965, fract(world.z / 0.45))) * 0.24;
    float3 neutral = materialParams.baseColor.rgb * (1.0 - line);
    material.baseColor = float4(neutral, materialParams.baseColor.a);
}
"""

internal const val ROOF_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float course = step(0.90, fract((world.x + world.z) / 0.28)) * materialParams.displayShade;
    float joint = step(0.94, fract((world.x - world.z) / 0.42)) * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 - max(course, joint) * 0.24) * shade, materialParams.baseColor.a);
}
"""

internal const val CONCRETE_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float speckle = fract(sin(dot(world.xz, float2(12.9898, 78.233))) * 43758.5453);
    float variation = (speckle - 0.5) * 0.10 * materialParams.displayShade;
    float shade = mix(1.0, 0.82 + 0.18 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(materialParams.baseColor.rgb * (1.0 + variation) * shade, materialParams.baseColor.a);
}
"""

// The model uses Filament's real lit path. The previous unlit workaround
// avoided black faces only because the scene had no environment light; with a
// stable baked IBL, the normal/tangent data can now drive actual sun + ambient
// shading without camera-dependent procedural patterns.
internal const val ARCHITECTURAL_LIT_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    material.baseColor = materialParams.baseColor;
    material.metallic = 0.0;
    material.roughness = 0.88;
    material.reflectance = 0.35;
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
