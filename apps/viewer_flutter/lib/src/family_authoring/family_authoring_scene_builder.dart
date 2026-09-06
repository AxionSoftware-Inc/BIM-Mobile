import 'dart:convert';

import '../render_scene_models.dart';
import 'family_dependency_resolver.dart';
import 'family_document.dart';
import 'family_geometry.dart';
import 'family_render_scene_adapter.dart';

/// Builds project-viewport scenes for Family Authoring.
///
/// Final-result preview still uses [FamilyRenderSceneAdapter]. Tool workflows
/// can instead request individual feature outputs as separate selectable
/// RenderScene objects. This is what lets Boolean/Move pick solids directly in
/// the same viewport used by the project workspace instead of falling back to
/// dropdown-only authoring.
abstract final class FamilyAuthoringSceneBuilder {
  static const int _featureElementBase = 920000;

  static int elementIdForFeatureIndex(int index) => _featureElementBase + index;

  static Future<RenderScene> buildCandidates(
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required Iterable<String> featureIds,
  }) async {
    final requested = featureIds.toSet();
    final objects = <RenderSceneObject>[];

    for (var index = 0; index < document.features.length; index++) {
      final feature = document.features[index];
      if (!requested.contains(feature.id) || !_isSolid(feature.kind)) continue;

      final truncated = document.copyWith(
        features: document.features.sublist(0, index + 1),
      );
      FamilyDocument evaluatedDocument = truncated;
      if (truncated.features.any(
        (item) => item.kind == FamilyFeatureKind.nestedFamily,
      )) {
        evaluatedDocument = await FamilyDependencyResolver.resolveFromLibrary(
          truncated,
          type,
        );
      }
      final mesh = FamilyGeometryEvaluator.evaluateMesh(evaluatedDocument, type);
      final renderMesh = _renderMesh(mesh);
      if (!renderMesh.hasGeometry) continue;
      final bounds = _bounds(renderMesh.positions);
      objects.add(
        RenderSceneObject(
          elementId: elementIdForFeatureIndex(index),
          kind: 'proxy',
          levelId: 1,
          selectable: true,
          visibleByDefault: true,
          revision: '${document.id}:${type.id}:${feature.id}:${document.toJsonText()}'
                  .hashCode &
              0x7fffffff,
          bounds: bounds,
          mesh: renderMesh,
          materialCategory: 'generic',
          metadata: <String, Object?>{
            'family_editor_preview': true,
            'family_candidate': true,
            'family_id': document.id,
            'family_feature_id': feature.id,
            'family_feature_kind': feature.kind.name,
            'family_feature_label': feature.label,
          },
        ),
      );
    }

    if (objects.isEmpty) {
      return FamilyRenderSceneAdapter.build(document, type);
    }

    final sceneBounds = RenderSceneBounds.union(
      objects.map((object) => object.bounds),
      fallback: RenderSceneBounds.zero(),
    );
    final vertexCount = objects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.positions.length,
    );
    final indexCount = objects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.indices.length,
    );

    final payload = <String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': objects.length,
      'vertex_count': vertexCount,
      'index_count': indexCount,
      'bounds': sceneBounds.toJson(),
      'levels': <Object?>[
        const RenderSceneLevel(
          levelId: 1,
          name: 'Family origin',
          elevationMeters: 0,
          defaultWallHeightMeters: 3,
        ).toJson(),
      ],
      'materials': const <Object?>[],
      'sections': const <Object?>[],
      'objects': objects.map((object) => object.toJson()).toList(),
    };
    final parsed = parseRenderSceneJson(
      jsonEncode(payload),
      source: 'family-authoring:${document.id}',
    );
    final scene = parsed.scene;
    if (scene == null) {
      throw FormatException(
        'Family authoring candidates could not enter RenderScene: '
        '${parsed.errors.join('; ')}',
      );
    }
    return scene;
  }

  static String? featureIdForObject(RenderSceneObject? object) {
    if (object == null) return null;
    final raw = object.metadata['family_feature_id'];
    final id = raw?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  static RenderSceneMesh _renderMesh(FamilyEvaluatedMesh mesh) {
    final positions = <RenderScenePoint>[
      for (final vertex in mesh.vertices)
        RenderScenePoint(x: vertex.x, y: vertex.z, z: vertex.y),
    ];
    final indices = <int>[];
    for (final face in mesh.faces) {
      final valid = face.indices
          .where((index) => index >= 0 && index < positions.length)
          .toList(growable: false);
      if (valid.length < 3) continue;
      final first = valid.first;
      for (var index = 1; index < valid.length - 1; index++) {
        // Family -> RenderScene swaps Y/Z and reverses handedness.
        indices
          ..add(first)
          ..add(valid[index + 1])
          ..add(valid[index]);
      }
    }
    return RenderSceneMesh(
      positions: List<RenderScenePoint>.unmodifiable(positions),
      indices: List<int>.unmodifiable(indices),
      normals: null,
    );
  }

  static RenderSceneBounds _bounds(List<RenderScenePoint> points) {
    if (points.isEmpty) return RenderSceneBounds.zero();
    var minX = points.first.x;
    var minY = points.first.y;
    var minZ = points.first.z;
    var maxX = minX;
    var maxY = minY;
    var maxZ = minZ;
    for (final point in points.skip(1)) {
      if (point.x < minX) minX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.z < minZ) minZ = point.z;
      if (point.x > maxX) maxX = point.x;
      if (point.y > maxY) maxY = point.y;
      if (point.z > maxZ) maxZ = point.z;
    }
    return RenderSceneBounds(
      min: RenderScenePoint(x: minX, y: minY, z: minZ),
      max: RenderScenePoint(x: maxX, y: maxY, z: maxZ),
    );
  }

  static bool _isSolid(FamilyFeatureKind kind) =>
      kind == FamilyFeatureKind.box ||
      kind == FamilyFeatureKind.extrude ||
      kind == FamilyFeatureKind.revolve ||
      kind == FamilyFeatureKind.booleanUnion ||
      kind == FamilyFeatureKind.booleanSubtract ||
      kind == FamilyFeatureKind.transform ||
      kind == FamilyFeatureKind.freeformMesh ||
      kind == FamilyFeatureKind.nestedFamily;
}
