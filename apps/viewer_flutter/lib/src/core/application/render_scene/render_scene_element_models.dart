part of 'render_scene_models.dart';

@immutable
class RenderSceneObject {
  const RenderSceneObject({
    required this.elementId,
    required this.kind,
    required this.levelId,
    required this.selectable,
    required this.visibleByDefault,
    required this.revision,
    required this.bounds,
    required this.mesh,
    required this.materialCategory,
    this.metadata = const <String, Object?>{},
    this.featureEdges = const <RenderSceneFeatureEdge>[],
  });

  final int? elementId;
  final String kind;
  final int? levelId;
  final bool selectable;
  final bool visibleByDefault;
  final int revision;
  final RenderSceneBounds bounds;
  final RenderSceneMesh mesh;
  final String materialCategory;
  final Map<String, Object?> metadata;
  final List<RenderSceneFeatureEdge> featureEdges;

  String get kindKey => normalizeSceneKind(kind);
  String? get elementIdRaw => elementId?.toString();

  Map<String, Object?> toJson() => <String, Object?>{
        if (elementId != null) 'element_id': elementId,
        'kind': kind,
        if (levelId != null) 'level_id': levelId,
        'selectable': selectable,
        'visible_by_default': visibleByDefault,
        'revision': revision,
        'bounds': bounds.toJson(),
        'mesh': mesh.toJson(),
        'material_category': materialCategory,
        if (metadata.isNotEmpty) 'metadata': metadata,
        if (featureEdges.isNotEmpty)
          'feature_edges': featureEdges.map((edge) => edge.toJson()).toList(),
      };

  static RenderSceneObject fromJson(
    Object? value,
    List<String> warnings,
    List<String> errors,
  ) {
    if (value is! Map) {
      errors.add('Encountered a malformed render object.');
      return RenderSceneObject(
        elementId: null,
        kind: 'Unknown',
        levelId: null,
        selectable: false,
        visibleByDefault: false,
        revision: 0,
        bounds: RenderSceneBounds(
          min: RenderScenePoint.zero(),
          max: RenderScenePoint.zero(),
        ),
        mesh: RenderSceneMesh.empty(),
        materialCategory: 'generic',
        metadata: const <String, Object?>{},
        featureEdges: const <RenderSceneFeatureEdge>[],
      );
    }
    final mesh = RenderSceneMesh.fromJson(value['mesh'], warnings);
    final explicitBounds = RenderSceneBounds.fromJson(value['bounds']);
    final derivedBounds = _boundsFromPositions(mesh.positions);
    final bounds = explicitBounds ?? derivedBounds;
    if (explicitBounds == null && mesh.positions.isEmpty) {
      warnings.add(
          'Render object ${value['kind'] ?? 'Unknown'} has no valid bounds or mesh.');
    }
    if (!bounds.isFinite) {
      warnings.add(
          'Render object ${value['kind'] ?? 'Unknown'} has non-finite bounds; zeroing them.');
    }
    return RenderSceneObject(
      elementId: _toNullableInt(value['element_id'] ?? value['elementId']),
      kind: toSceneString(value['kind'], fallback: 'Unknown'),
      levelId: _toNullableInt(value['level_id'] ?? value['levelId']),
      selectable: value['selectable'] != false,
      visibleByDefault: value['visible_by_default'] != false,
      revision: _toNullableInt(value['revision']) ?? 0,
      bounds: bounds.isFinite ? bounds : RenderSceneBounds.zero(),
      mesh: mesh,
      materialCategory: toSceneString(
        value['material_category'] ?? value['materialCategory'],
        fallback: 'generic',
      ),
      metadata: value['metadata'] is Map
          ? Map<String, Object?>.from(
              (value['metadata'] as Map).cast<String, Object?>(),
            )
          : const <String, Object?>{},
      featureEdges: value['feature_edges'] is List
          ? (value['feature_edges'] as List)
              .map(RenderSceneFeatureEdge.fromJson)
              .whereType<RenderSceneFeatureEdge>()
              .toList(growable: false)
          : const <RenderSceneFeatureEdge>[],
    );
  }
}
