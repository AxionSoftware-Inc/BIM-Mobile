import 'dart:convert';

import '../render_scene_models.dart';
import 'family_document.dart';
import 'family_geometry.dart';

/// Converts the independent Family geometry contract into the exact same
/// RenderScene contract used by the project viewport.
///
/// Family coordinates are X = width, Y = height, Z = depth. RenderScene uses
/// X/Y for the plan plane and Z for elevation, therefore the only coordinate
/// conversion is (x, z, y). No camera, gesture or renderer logic belongs here.
abstract final class FamilyRenderSceneAdapter {
  static const int familyPreviewElementId = 910001;

  static RenderScene build(
    FamilyDocument document,
    FamilyTypeDefinition type, {
    FamilyEvaluatedMesh? mesh,
  }) {
    final evaluated = mesh ?? FamilyGeometryEvaluator.evaluateMesh(document, type);
    final points = <RenderScenePoint>[
      for (final vertex in evaluated.vertices)
        RenderScenePoint(x: vertex.x, y: vertex.z, z: vertex.y),
    ];
    final indices = _triangulate(evaluated.faces, points.length);
    final bounds = _bounds(points);
    final finalFeature = _lastSolidFeature(document);

    final payload = <String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': 1,
      'vertex_count': points.length,
      'index_count': indices.length,
      'bounds': bounds.toJson(),
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
      'objects': <Object?>[
        RenderSceneObject(
          elementId: familyPreviewElementId,
          kind: 'proxy',
          levelId: 1,
          selectable: true,
          visibleByDefault: true,
          revision: document.toJsonText().hashCode & 0x7fffffff,
          bounds: bounds,
          mesh: RenderSceneMesh(
            positions: points,
            indices: indices,
            normals: null,
          ),
          materialCategory: 'generic',
          metadata: <String, Object?>{
            'family_editor_preview': true,
            'family_id': document.id,
            'family_name': document.name,
            'family_type_id': type.id,
            'family_type_name': type.name,
            if (finalFeature != null) 'family_feature_id': finalFeature.id,
            if (finalFeature != null) 'family_feature_kind': finalFeature.kind.name,
            'family_mesh_source': evaluated.source,
            if (evaluated.isApproximate) 'family_geometry_approximate': true,
          },
        ).toJson(),
      ],
    };

    final parsed = parseRenderSceneJson(
      jsonEncode(payload),
      source: 'family:${document.id}',
    );
    final scene = parsed.scene;
    if (scene == null) {
      throw FormatException(
        'Family preview could not enter RenderScene: ${parsed.errors.join('; ')}',
      );
    }
    return scene;
  }

  static List<int> _triangulate(List<FamilyMeshFace> faces, int vertexCount) {
    final indices = <int>[];
    for (final face in faces) {
      final valid = face.indices
          .where((index) => index >= 0 && index < vertexCount)
          .toList(growable: false);
      if (valid.length < 3) continue;
      final first = valid.first;
      for (var index = 1; index < valid.length - 1; index++) {
        // Family -> RenderScene swaps Y/Z and therefore reverses handedness.
        // Reverse triangle winding once here so the project renderer receives
        // the same outward orientation as the Family evaluator produced.
        indices
          ..add(first)
          ..add(valid[index + 1])
          ..add(valid[index]);
      }
    }
    return List<int>.unmodifiable(indices);
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

  static FamilyFeature? _lastSolidFeature(FamilyDocument document) {
    for (var index = document.features.length - 1; index >= 0; index--) {
      final feature = document.features[index];
      if (_isSolid(feature.kind)) return feature;
    }
    return null;
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
