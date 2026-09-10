import '../../domain/document/family_document.dart';

/// Pure construction rules for Family Editor live-preview operations.
///
/// Presentation chooses the active tool and edits raw field strings. This
/// builder turns those values into immutable FamilyDocument snapshots without
/// knowing about Flutter, focus, dialogs, viewports, or persistence.
abstract final class FamilyEditorDraftBuilder {
  static FamilyDocument extrude(
    FamilyDocument document, {
    required String featureId,
    required String profileId,
    required String depth,
    String? label,
  }) {
    return upsertFeature(
      document,
      FamilyFeature(
        id: featureId,
        kind: FamilyFeatureKind.extrude,
        label: _labelFor(
          document,
          featureId,
          FamilyFeatureKind.extrude,
          label ?? 'Extrude',
        ),
        inputs: <String>[profileId],
        parameters: <String, Object?>{
          'profileId': profileId,
          'depth': depth.trim(),
        },
      ),
    );
  }

  static FamilyDocument revolve(
    FamilyDocument document, {
    required String featureId,
    required String profileId,
    required String angle,
    String? label,
  }) {
    return upsertFeature(
      document,
      FamilyFeature(
        id: featureId,
        kind: FamilyFeatureKind.revolve,
        label: _labelFor(
          document,
          featureId,
          FamilyFeatureKind.revolve,
          label ?? 'Revolve',
        ),
        inputs: <String>[profileId],
        parameters: <String, Object?>{
          'profileId': profileId,
          'angle': angle.trim(),
        },
      ),
    );
  }

  static FamilyDocument transform(
    FamilyDocument document, {
    required String featureId,
    required String sourceFeatureId,
    required String translationX,
    required String translationY,
    required String translationZ,
    required String rotation,
    required String scale,
    String? label,
  }) {
    return upsertFeature(
      document,
      FamilyFeature(
        id: featureId,
        kind: FamilyFeatureKind.transform,
        label: _labelFor(
          document,
          featureId,
          FamilyFeatureKind.transform,
          label ?? 'Transform',
        ),
        inputs: <String>[sourceFeatureId],
        parameters: <String, Object?>{
          'translationX': translationX,
          'translationY': translationY,
          'translationZ': translationZ,
          // Serialized field remains rotationZ for schema compatibility. The
          // geometry evaluator interprets it as the Family vertical/yaw axis.
          'rotationZ': rotation,
          'scale': scale,
        },
      ),
    );
  }

  static FamilyDocument boolean(
    FamilyDocument document, {
    required String featureId,
    required String baseFeatureId,
    required String toolFeatureId,
    required FamilyFeatureKind kind,
    String? label,
  }) {
    if (kind != FamilyFeatureKind.booleanUnion &&
        kind != FamilyFeatureKind.booleanSubtract) {
      throw ArgumentError.value(kind, 'kind', 'Expected a boolean feature kind.');
    }
    if (baseFeatureId == toolFeatureId) {
      throw ArgumentError('Boolean Base and Tool must be different features.');
    }
    final fallback = kind == FamilyFeatureKind.booleanUnion ? 'Union' : 'Subtract';
    return upsertFeature(
      document,
      FamilyFeature(
        id: featureId,
        kind: kind,
        label: _labelFor(document, featureId, kind, label ?? fallback),
        inputs: <String>[baseFeatureId, toolFeatureId],
        parameters: <String, Object?>{'operation': kind.name},
      ),
    );
  }

  static FamilyDocument upsertFeature(
    FamilyDocument document,
    FamilyFeature feature,
  ) {
    final index =
        document.features.indexWhere((candidate) => candidate.id == feature.id);
    if (index < 0) {
      return document.copyWith(
        features: <FamilyFeature>[...document.features, feature],
      );
    }
    return document.copyWith(
      features: <FamilyFeature>[
        for (final current in document.features)
          current.id == feature.id ? feature : current,
      ],
    );
  }

  static List<FamilyFeature> eligibleSolids(
    FamilyDocument document, {
    String? draftFeatureId,
  }) {
    final draftIndex = draftFeatureId == null
        ? -1
        : document.features
            .indexWhere((feature) => feature.id == draftFeatureId);
    final limit = draftIndex >= 0 ? draftIndex : document.features.length;
    return List<FamilyFeature>.unmodifiable(<FamilyFeature>[
      for (var index = 0; index < limit; index++)
        if (isSolid(document.features[index].kind)) document.features[index],
    ]);
  }

  static FamilyFeature? lastSolid(FamilyDocument document) {
    for (var index = document.features.length - 1; index >= 0; index--) {
      final feature = document.features[index];
      if (isSolid(feature.kind)) return feature;
    }
    return null;
  }

  static bool isSolid(FamilyFeatureKind kind) =>
      kind == FamilyFeatureKind.box ||
      kind == FamilyFeatureKind.extrude ||
      kind == FamilyFeatureKind.revolve ||
      kind == FamilyFeatureKind.booleanUnion ||
      kind == FamilyFeatureKind.booleanSubtract ||
      kind == FamilyFeatureKind.transform ||
      kind == FamilyFeatureKind.freeformMesh ||
      kind == FamilyFeatureKind.nestedFamily;

  static String _labelFor(
    FamilyDocument document,
    String featureId,
    FamilyFeatureKind kind,
    String fallback,
  ) {
    for (final feature in document.features) {
      if (feature.id == featureId &&
          feature.kind == kind &&
          feature.label.trim().isNotEmpty) {
        return feature.label.trim();
      }
    }
    return fallback;
  }
}
