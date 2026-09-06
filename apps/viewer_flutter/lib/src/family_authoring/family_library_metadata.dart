import 'family_document.dart';

/// Derived, presentation-safe metadata for Family Library surfaces.
///
/// The document remains the source of truth. Library cards, detail panes and
/// future search/indexing code should consume this model instead of each
/// reimplementing feature/parameter classification rules.
final class FamilyLibraryMetadata {
  const FamilyLibraryMetadata({
    required this.typeCount,
    required this.parameterCount,
    required this.formulaCount,
    required this.constraintCount,
    required this.sketchCount,
    required this.featureCount,
    required this.nestedFamilyCount,
    required this.freeformMeshCount,
    required this.booleanCount,
    required this.parametricFeatureCount,
  });

  final int typeCount;
  final int parameterCount;
  final int formulaCount;
  final int constraintCount;
  final int sketchCount;
  final int featureCount;
  final int nestedFamilyCount;
  final int freeformMeshCount;
  final int booleanCount;
  final int parametricFeatureCount;

  bool get hasMultipleTypes => typeCount > 1;
  bool get hasFormulas => formulaCount > 0;
  bool get hasConstraints => constraintCount > 0;
  bool get hasNestedFamilies => nestedFamilyCount > 0;
  bool get hasFreeformMesh => freeformMeshCount > 0;
  bool get hasBooleans => booleanCount > 0;

  /// True when the Family exposes authored semantics beyond a single frozen
  /// mesh. Core dimensions alone count because every shipped Family retains the
  /// stable width/depth/height type contract.
  bool get isParametric =>
      parameterCount > 0 ||
      formulaCount > 0 ||
      constraintCount > 0 ||
      parametricFeatureCount > 0;

  factory FamilyLibraryMetadata.fromDocument(FamilyDocument document) {
    var nestedFamilyCount = 0;
    var freeformMeshCount = 0;
    var booleanCount = 0;
    var parametricFeatureCount = 0;

    for (final feature in document.features) {
      switch (feature.kind) {
        case FamilyFeatureKind.nestedFamily:
          nestedFamilyCount += 1;
          parametricFeatureCount += 1;
          break;
        case FamilyFeatureKind.freeformMesh:
          freeformMeshCount += 1;
          break;
        case FamilyFeatureKind.booleanUnion:
        case FamilyFeatureKind.booleanSubtract:
          booleanCount += 1;
          parametricFeatureCount += 1;
          break;
        case FamilyFeatureKind.box:
        case FamilyFeatureKind.extrude:
        case FamilyFeatureKind.revolve:
        case FamilyFeatureKind.transform:
          parametricFeatureCount += 1;
          break;
        case FamilyFeatureKind.profile:
          break;
      }
    }

    return FamilyLibraryMetadata(
      typeCount: document.types.length,
      parameterCount: document.parameters.length,
      formulaCount:
          document.parameters.where((parameter) => parameter.hasFormula).length,
      constraintCount: document.constraints.length,
      sketchCount: document.sketches.length,
      featureCount: document.features.length,
      nestedFamilyCount: nestedFamilyCount,
      freeformMeshCount: freeformMeshCount,
      booleanCount: booleanCount,
      parametricFeatureCount: parametricFeatureCount,
    );
  }

  /// Compact labels suitable for cards/chips. Keep values deterministic so
  /// search indexes and screenshots do not change due to map iteration order.
  List<String> get capabilityLabels => List<String>.unmodifiable(<String>[
        '$typeCount ${typeCount == 1 ? 'type' : 'types'}',
        if (hasMultipleTypes) 'Multi-type',
        if (hasFormulas) '$formulaCount formula${formulaCount == 1 ? '' : 's'}',
        if (hasConstraints)
          '$constraintCount constraint${constraintCount == 1 ? '' : 's'}',
        if (hasNestedFamilies) 'Nested',
        if (hasBooleans) 'Boolean',
        if (hasFreeformMesh) 'Mesh',
        if (!hasFreeformMesh && isParametric) 'Parametric',
      ]);
}
