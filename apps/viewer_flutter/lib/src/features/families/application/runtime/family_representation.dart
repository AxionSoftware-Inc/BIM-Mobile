/// View-specific family representation policy.
///
/// IMPORTANT RUNTIME CONTRACT:
/// - Family authoring decides how a family is created/evaluated.
/// - This runtime layer decides what representation a view needs.
/// - A 2D view must not materialize a detailed 3D family mesh merely to draw a
///   chair/table/door symbol. SVG is supported as one encoding, but it is not
///   the architecture: compact vector commands, generated linework or another
///   lightweight representation can be used without changing the instance DB.
/// - A 3D view requests only the LOD selected by projected size/distance.
enum FamilyViewRepresentation {
  plan2d,
  elevation2d,
  section2d,
  model3d,
}

enum FamilyGeometryLod {
  proxy,
  low,
  medium,
  full,
}

enum Family2dEncoding {
  /// Existing family assets already use this in parts of the application.
  svg,

  /// Preferred future runtime form: parsed/compiled vector commands.
  compactVector,

  /// Procedural symbols such as a door swing or simple furniture footprint.
  generated,

  /// Last-resort cheap representation derived from instance bounds.
  boundsProxy,
}

final class Family2dRepresentationDescriptor {
  const Family2dRepresentationDescriptor({
    required this.encoding,
    required this.assetKey,
  });

  final Family2dEncoding encoding;

  /// Stable cache key, not the full payload. The renderer/view cache owns the
  /// parsed symbol so ten thousand instances reference one representation.
  final String assetKey;
}

final class Family3dRepresentationDescriptor {
  const Family3dRepresentationDescriptor({
    required this.geometryVariantId,
    this.proxyAssetKey,
    this.lowAssetKey,
    this.mediumAssetKey,
    this.fullAssetKey,
  });

  final int geometryVariantId;
  final String? proxyAssetKey;
  final String? lowAssetKey;
  final String? mediumAssetKey;
  final String? fullAssetKey;

  String? assetFor(FamilyGeometryLod lod) => switch (lod) {
        FamilyGeometryLod.proxy =>
          proxyAssetKey ?? lowAssetKey ?? mediumAssetKey ?? fullAssetKey,
        FamilyGeometryLod.low =>
          lowAssetKey ?? mediumAssetKey ?? fullAssetKey ?? proxyAssetKey,
        FamilyGeometryLod.medium =>
          mediumAssetKey ?? fullAssetKey ?? lowAssetKey ?? proxyAssetKey,
        FamilyGeometryLod.full =>
          fullAssetKey ?? mediumAssetKey ?? lowAssetKey ?? proxyAssetKey,
      };
}

final class FamilyRepresentationSet {
  const FamilyRepresentationSet({
    this.plan,
    this.elevation,
    this.section,
    this.model3d,
  });

  final Family2dRepresentationDescriptor? plan;
  final Family2dRepresentationDescriptor? elevation;
  final Family2dRepresentationDescriptor? section;
  final Family3dRepresentationDescriptor? model3d;
}

final class FamilyRepresentationRequest {
  const FamilyRepresentationRequest({
    required this.view,
    this.projectedSizePixels = 0,
  });

  final FamilyViewRepresentation view;
  final double projectedSizePixels;
}

final class FamilyRepresentationDecision {
  const FamilyRepresentationDecision._({
    required this.requires3dGeometry,
    this.twoDimensional,
    this.lod,
    this.geometryAssetKey,
  });

  factory FamilyRepresentationDecision.twoDimensional(
    Family2dRepresentationDescriptor descriptor,
  ) =>
      FamilyRepresentationDecision._(
        requires3dGeometry: false,
        twoDimensional: descriptor,
      );

  factory FamilyRepresentationDecision.threeDimensional({
    required FamilyGeometryLod lod,
    required String? assetKey,
  }) =>
      FamilyRepresentationDecision._(
        requires3dGeometry: true,
        lod: lod,
        geometryAssetKey: assetKey,
      );

  final bool requires3dGeometry;
  final Family2dRepresentationDescriptor? twoDimensional;
  final FamilyGeometryLod? lod;
  final String? geometryAssetKey;
}

abstract final class FamilyRepresentationPolicy {
  /// Chooses the cheapest representation that preserves the meaning of the
  /// active view. Floor plans intentionally stay on a 2D path even when no
  /// authored SVG exists: the bounds/generated fallback is still preferable
  /// to loading a detailed furniture mesh into a plan viewport.
  static FamilyRepresentationDecision choose(
    FamilyRepresentationSet set,
    FamilyRepresentationRequest request,
  ) {
    switch (request.view) {
      case FamilyViewRepresentation.plan2d:
        return FamilyRepresentationDecision.twoDimensional(
          set.plan ??
              const Family2dRepresentationDescriptor(
                encoding: Family2dEncoding.boundsProxy,
                assetKey: 'generated:plan-bounds',
              ),
        );
      case FamilyViewRepresentation.elevation2d:
        return FamilyRepresentationDecision.twoDimensional(
          set.elevation ??
              const Family2dRepresentationDescriptor(
                encoding: Family2dEncoding.boundsProxy,
                assetKey: 'generated:elevation-bounds',
              ),
        );
      case FamilyViewRepresentation.section2d:
        return FamilyRepresentationDecision.twoDimensional(
          set.section ??
              const Family2dRepresentationDescriptor(
                encoding: Family2dEncoding.boundsProxy,
                assetKey: 'generated:section-bounds',
              ),
        );
      case FamilyViewRepresentation.model3d:
        final model = set.model3d;
        final pixels = request.projectedSizePixels.isFinite
            ? request.projectedSizePixels.clamp(0.0, double.infinity)
            : 0.0;
        final lod = pixels < 10
            ? FamilyGeometryLod.proxy
            : pixels < 48
                ? FamilyGeometryLod.low
                : pixels < 180
                    ? FamilyGeometryLod.medium
                    : FamilyGeometryLod.full;
        return FamilyRepresentationDecision.threeDimensional(
          lod: lod,
          assetKey: model?.assetFor(lod),
        );
    }
  }
}
