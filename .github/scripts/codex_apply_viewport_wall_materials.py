from pathlib import Path

HOST = Path(
    "apps/viewer_flutter/android/app/src/main/kotlin/"
    "com/example/viewer_flutter/RenderSceneFilamentHostView.kt"
)

OLD = r'''private const val WALL_SURFACE_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    material.normal = normalize(cross(dFdx(world), dFdy(world)));
    float variant = materialParams.surfaceKind;
    float brickMask = 1.0 - step(0.5, variant);
    float plasterMask = step(0.5, variant) * (1.0 - step(1.5, variant));
    float concreteMask = step(1.5, variant) * (1.0 - step(2.5, variant));
    float glassMask = step(2.5, variant);

    // Solid keeps the wall achromatic, so its only semantic cue is the
    // readable brick pattern. Use wider, slightly stronger joints in
    // Solid; Shaded retains the finer light brick pattern used previously.
    float brickRowSpacing = mix(0.18, 0.075, materialParams.displayShade);
    float brickWidth = mix(0.48, 0.24, materialParams.displayShade);
    // The brick cue is a viewport aid, not a texture atlas. Hard step()
    // joints alias when the curved facade is viewed at a grazing angle and
    // become a visible shimmer during a close pinch. Use periodic distance
    // plus screen-space derivatives so the same cue remains stable at every
    // zoom level and on every tessellated arc station.
    float rowCoord = world.y / brickRowSpacing;
    float row = floor(rowCoord);
    float rowCell = fract(rowCoord);
    float rowDistance = min(rowCell, 1.0 - rowCell);
    float rowAa = max(fwidth(rowCoord) * 1.25, 0.0005);
    float jointY = 1.0 - smoothstep(0.022 - rowAa, 0.022 + rowAa, rowDistance);
    float brickCoord = (world.x + mod(row, 2.0) * brickWidth * 0.5) / brickWidth;
    float brickCell = fract(brickCoord);
    float brickDistance = min(brickCell, 1.0 - brickCell);
    float brickAa = max(fwidth(brickCoord) * 1.25, 0.0005);
    float jointX = 1.0 - smoothstep(0.018 - brickAa, 0.018 + brickAa, brickDistance);
    float mortar = max(jointY, jointX) * mix(0.66, 0.52, materialParams.displayShade);
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);

    float plasterVariation = 0.026 * sin(world.x * 31.0 + world.y * 17.0 + world.z * 23.0);
    float3 plaster = materialParams.baseColor.rgb * (1.0 + plasterVariation);

    float speckle = fract(sin(dot(world.xz, float2(12.9898, 78.233))) * 43758.5453);
    float3 concrete = materialParams.baseColor.rgb * (1.0 + (speckle - 0.5) * 0.08);

    float glassLine = step(0.965, fract((world.x + world.y + world.z) * 0.42));
    // Keep Solid glass neutral; introduce the light cyan tint only in Shaded.
    float3 glassTint = mix(float3(0.84, 0.84, 0.84), float3(0.38, 0.68, 0.76), materialParams.displayShade);
    float3 glass = mix(materialParams.baseColor.rgb, glassTint, 0.28);
    glass *= 1.0 - glassLine * 0.18;

    float3 surface = brick * brickMask + plaster * plasterMask + concrete * concreteMask + glass * glassMask;
    float directionalShade = mix(1.0, 0.84 + 0.16 * sin(world.x * 0.45 + world.z * 0.31), materialParams.displayShade);
    material.baseColor = float4(surface * directionalShade, materialParams.baseColor.a);
}
"""
'''

NEW = r'''private const val WALL_SURFACE_MAT = """
void material(inout MaterialInputs material) {
    prepareMaterial(material);
    float3 world = getWorldPosition();
    float variant = materialParams.surfaceKind;
    float shaded = materialParams.displayShade;
    float brickMask = 1.0 - step(0.5, variant);
    float plasterMask = step(0.5, variant) * (1.0 - step(1.5, variant));
    float concreteMask = step(1.5, variant) * (1.0 - step(2.5, variant));
    float glassMask = step(2.5, variant);

    // One shared procedural wall-surface family is used by every wall batch.
    // It behaves like a tiny default texture atlas without allocating a
    // texture/material per wall. Fine detail fades when its world-space
    // footprint becomes sub-pixel, which prevents shimmer while orbiting.
    float footprint = max(max(fwidth(world.x), fwidth(world.y)), fwidth(world.z));
    float detailFade = 1.0 - smoothstep(0.018, 0.11, footprint);

    // Brick remains the only visible cue in Solid; Shaded uses a smaller,
    // softer architectural bond. Derivative AA keeps mortar stable at grazing
    // angles and avoids the crawling line pattern of an unfiltered texture.
    float brickRowSpacing = mix(0.18, 0.075, shaded);
    float brickWidth = mix(0.48, 0.24, shaded);
    float rowCoord = world.y / brickRowSpacing;
    float row = floor(rowCoord);
    float rowCell = fract(rowCoord);
    float rowDistance = min(rowCell, 1.0 - rowCell);
    float rowAa = max(fwidth(rowCoord) * 1.35, 0.0005);
    float jointY = 1.0 - smoothstep(0.022 - rowAa, 0.022 + rowAa, rowDistance);
    float brickCoord = (world.x + mod(row, 2.0) * brickWidth * 0.5) / brickWidth;
    float brickCell = fract(brickCoord);
    float brickDistance = min(brickCell, 1.0 - brickCell);
    float brickAa = max(fwidth(brickCoord) * 1.35, 0.0005);
    float jointX = 1.0 - smoothstep(0.018 - brickAa, 0.018 + brickAa, brickDistance);
    float mortar = max(jointY, jointX) * mix(0.58, 0.38, shaded) * detailFade;
    float3 brick = materialParams.baseColor.rgb * (1.0 - mortar);

    // Plaster and concrete use broad, low-contrast grain. The previous very
    // high-frequency sin/hash noise aliased under camera rotation and read as
    // metallic sparkle even though the wall material itself is unlit.
    float plasterGrain = 0.5 * sin(world.x * 2.1 + world.z * 1.7)
        + 0.5 * sin(world.y * 2.7 - world.x * 1.1);
    float3 plaster = materialParams.baseColor.rgb
        * (1.0 + plasterGrain * 0.014 * detailFade * shaded);

    float concreteGrain = 0.5 * sin(world.x * 1.55 + world.y * 0.83)
        + 0.5 * sin(world.z * 2.05 - world.x * 0.74);
    float3 concrete = materialParams.baseColor.rgb
        * (1.0 + concreteGrain * 0.020 * detailFade * shaded);

    float glassCoord = (world.x + world.y + world.z) * 0.42;
    float glassCell = fract(glassCoord);
    float glassAa = max(fwidth(glassCoord) * 1.4, 0.001);
    float glassLine = smoothstep(0.965 - glassAa, 0.965 + glassAa, glassCell);
    float3 glassTint = mix(float3(0.84, 0.84, 0.84), float3(0.38, 0.68, 0.76), shaded);
    float3 glass = mix(materialParams.baseColor.rgb, glassTint, 0.28);
    glass *= 1.0 - glassLine * 0.10 * detailFade;

    float3 surface = brick * brickMask
        + plaster * plasterMask
        + concrete * concreteMask
        + glass * glassMask;

    // Do not add a fake world-space light band here. Shaded material identity
    // comes from the stable surface family; real sun/IBL belongs to a later
    // matte PBR pass once the tablet driver path is validated.
    material.baseColor = float4(surface, materialParams.baseColor.a);
}
"""
'''

MARKER = "One shared procedural wall-surface family is used by every wall batch."


def main() -> None:
    source = HOST.read_text(encoding="utf-8")
    if MARKER in source:
        print("Stable matte wall material is already wired into the host.")
        return

    occurrences = source.count(OLD)
    if occurrences != 1:
        raise SystemExit(
            "Guard failed: expected exactly one legacy WALL_SURFACE_MAT block, "
            f"found {occurrences}. Host left unchanged."
        )

    patched = source.replace(OLD, NEW, 1)
    if patched.count(MARKER) != 1:
        raise SystemExit("Guard failed: wall-material marker count is not one.")
    if "float directionalShade" in patched:
        raise SystemExit("Guard failed: legacy fake directional shading remains.")
    if "43758.5453" in patched:
        raise SystemExit("Guard failed: legacy high-frequency concrete hash remains.")

    HOST.write_text(patched, encoding="utf-8")
    print("Applied stable batched wall material to RenderSceneFilamentHostView.")


if __name__ == "__main__":
    main()
