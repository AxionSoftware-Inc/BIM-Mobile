import 'family_authoring/family_document.dart';
import 'family_authoring/family_geometry.dart';
import 'family_authoring/family_validation.dart';
import 'render_scene_models.dart';
import 'viewer_authoring_gateway.dart';
import 'viewer_element_creation_gateway.dart';

/// Result of mapping one reusable family type to a native project instance.
/// The project stores the family/type reference; the family feature graph is
/// never copied into the project object.
final class FamilyInstancePlacementResult {
  const FamilyInstancePlacementResult({
    required this.elementId,
    required this.type,
    required this.scene,
  });

  final int elementId;
  final FamilyTypeDefinition type;
  final RenderSceneLoadResult scene;
}

/// Application-side adapter between the independent Family Authoring module
/// and the project gateways. Keeping this outside `family_authoring/` makes
/// the family editor detachable while still allowing project placement.
abstract final class FamilyInstanceAdapter {
  static Future<FamilyInstancePlacementResult> place({
    required FamilyDocument family,
    required FamilyTypeDefinition type,
    required String familyAssetPath,
    required int levelId,
    required RenderScenePoint position,
    required ViewerElementCreationGateway creationGateway,
    required ViewerAuthoringGateway authoringGateway,
    int? hostWallId,
    double offsetMeters = 0.0,
  }) async {
    final validation = FamilyDocumentValidator.validate(family);
    if (!validation.isValid) {
      throw FormatException(validation.errors.join('; '));
    }
    if (!family.types.any((candidate) => candidate.id == type.id)) {
      throw const FormatException(
          'Selected family type does not belong to the family.');
    }

    final evaluatedMesh = FamilyGeometryEvaluator.evaluateMesh(family, type);
    if (evaluatedMesh.vertices.isEmpty || evaluatedMesh.faces.isEmpty) {
      throw const FormatException('Family type has no usable solid geometry.');
    }

    final category = family.category;
    final customMeshGeometry = family.features.any(
      (feature) =>
          feature.kind != FamilyFeatureKind.box &&
          feature.kind != FamilyFeatureKind.profile,
    );
    late final RenderSceneLoadResult created;
    switch (category) {
      case FamilyCategory.column:
      case FamilyCategory.structural:
        if (customMeshGeometry) {
          created = await _createMeshInstance(
            family: family,
            type: type,
            position: position,
            levelId: levelId,
            evaluatedMesh: evaluatedMesh,
            creationGateway: creationGateway,
          );
        } else {
          created = await creationGateway.createColumn(
            levelId: levelId,
            position: position,
            widthMeters: _lengthValue(family, type, 'width'),
            depthMeters: _lengthValue(family, type, 'depth'),
            heightMeters: _lengthValue(family, type, 'height'),
          );
        }
      case FamilyCategory.door:
        final wallId = hostWallId;
        if (wallId == null) {
          throw const FormatException(
              'A door family must be hosted by a wall.');
        }
        created = await creationGateway.createDoor(
          name: family.name,
          hostWallId: wallId,
          offsetMeters: offsetMeters,
          widthMeters: _lengthValue(family, type, 'width'),
          heightMeters: _lengthValue(family, type, 'height'),
        );
      case FamilyCategory.window:
        final wallId = hostWallId;
        if (wallId == null) {
          throw const FormatException(
              'A window family must be hosted by a wall.');
        }
        created = await creationGateway.createWindow(
          name: family.name,
          hostWallId: wallId,
          offsetMeters: offsetMeters,
          widthMeters: _lengthValue(family, type, 'width'),
          heightMeters: _lengthValue(family, type, 'height'),
          sillHeightMeters: _lengthValue(
            family,
            type,
            'sillHeight',
            fallback: 0.9,
          ),
        );
      case FamilyCategory.genericModel:
      case FamilyCategory.furniture:
        created = await _createMeshInstance(
          family: family,
          type: type,
          position: position,
          levelId: levelId,
          evaluatedMesh: evaluatedMesh,
          creationGateway: creationGateway,
        );
    }

    if (created.scene == null || created.errors.isNotEmpty) {
      throw StateError(
        created.errors.isEmpty
            ? 'Native family instance creation returned no scene.'
            : created.errors.join('\n'),
      );
    }
    final elementId = creationGateway.lastCreatedElementId;
    if (elementId == null) {
      throw StateError('Native family instance id was not returned.');
    }
    final withReference = await authoringGateway.setElementFamilyReference(
      elementId: elementId,
      familyAssetId: family.id,
      familyName: family.name,
      familyTypeId: type.id,
      familyTypeName: type.name,
      familyCategory: family.category.name,
      familyAssetPath: familyAssetPath,
    );
    if (withReference.scene == null || withReference.errors.isNotEmpty) {
      throw StateError(
        withReference.errors.isEmpty
            ? 'Family reference could not be attached to the instance.'
            : withReference.errors.join('\n'),
      );
    }
    return FamilyInstancePlacementResult(
      elementId: elementId,
      type: type,
      scene: withReference,
    );
  }

  static Future<RenderSceneLoadResult> _createMeshInstance({
    required FamilyDocument family,
    required FamilyTypeDefinition type,
    required RenderScenePoint position,
    required int levelId,
    required FamilyEvaluatedMesh evaluatedMesh,
    required ViewerElementCreationGateway creationGateway,
  }) {
    final indices = _triangleIndices(evaluatedMesh);
    if (indices.isEmpty) {
      throw const FormatException('Family mesh has no renderable triangles.');
    }
    final vertices = <RenderScenePoint>[
      for (final vertex in evaluatedMesh.vertices)
        RenderScenePoint(
          x: position.x + vertex.x,
          y: position.y + vertex.z,
          z: position.z + vertex.y,
        ),
    ];
    return creationGateway.createFamilyProxy(
      name: '${family.name} · ${type.name}',
      levelId: levelId,
      position: position,
      widthMeters: _lengthValue(family, type, 'width', fallback: 1.0),
      depthMeters: _lengthValue(family, type, 'depth', fallback: 1.0),
      heightMeters: _lengthValue(family, type, 'height', fallback: 1.0),
      vertices: vertices,
      indices: indices,
    );
  }

  static List<int> _triangleIndices(FamilyEvaluatedMesh mesh) {
    final result = <int>[];
    for (final face in mesh.faces) {
      if (face.indices.length < 3) continue;
      for (var index = 1; index < face.indices.length - 1; index++) {
        result
          ..add(face.indices[0])
          ..add(face.indices[index])
          ..add(face.indices[index + 1]);
      }
    }
    return result;
  }

  static double _lengthValue(
    FamilyDocument family,
    FamilyTypeDefinition type,
    String parameterId, {
    double? fallback,
  }) {
    for (final parameter in family.parameters) {
      if (parameter.id != parameterId) continue;
      final value = type.valueFor(parameter);
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed.isFinite && parsed > 0.0) return parsed;
      break;
    }
    if (fallback != null) return fallback;
    throw FormatException('Family parameter "$parameterId" must be positive.');
  }
}
