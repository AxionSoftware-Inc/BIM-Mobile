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
    late final RenderSceneLoadResult created;
    switch (category) {
      case FamilyCategory.column:
      case FamilyCategory.structural:
        created = await creationGateway.createColumn(
          levelId: levelId,
          position: position,
          widthMeters: _lengthValue(family, type, 'width'),
          depthMeters: _lengthValue(family, type, 'depth'),
          heightMeters: _lengthValue(family, type, 'height'),
        );
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
        throw const FormatException(
          'Generic family placement is not enabled yet; use a Column family.',
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
