import 'dart:convert';
import 'dart:math' as math;

import 'family_authoring/family_dependency_resolver.dart';
import 'family_authoring/family_document.dart';
import 'family_authoring/family_geometry.dart';
import 'family_authoring/family_parameter_resolver.dart';
import 'family_authoring/family_plan_symbol.dart';
import 'family_authoring/family_validation.dart';
import 'render_scene_editor.dart';
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
/// and project gateways. This is also the single resolver boundary available
/// to project Inspector code, so editor/plan/3D/Inspector cannot drift apart.
abstract final class FamilyInstanceAdapter {
  static List<int> triangleIndices(FamilyEvaluatedMesh mesh) {
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

  static List<RenderScenePoint> projectVertices(
    FamilyEvaluatedMesh mesh,
    RenderScenePoint position,
  ) {
    return <RenderScenePoint>[
      for (final vertex in mesh.vertices)
        RenderScenePoint(
          x: position.x + vertex.x,
          y: position.y + vertex.z,
          z: position.z + vertex.y,
        ),
    ];
  }

  static List<RenderScenePoint> projectWallHostedVertices({
    required FamilyEvaluatedMesh mesh,
    required RenderSceneObject hostWall,
    required double offsetMeters,
  }) {
    final center = RenderSceneQueries.wallPointAtOffset(hostWall, offsetMeters);
    final tangent = RenderSceneQueries.wallTangentAtOffset(hostWall, offsetMeters);
    if (center == null || tangent == null) {
      throw const FormatException('Wall host has no usable centerline.');
    }
    final normal = RenderScenePoint(x: -tangent.y, y: tangent.x, z: 0.0);
    return <RenderScenePoint>[
      for (final vertex in mesh.vertices)
        RenderScenePoint(
          x: center.x + tangent.x * vertex.x + normal.x * vertex.z,
          y: center.y + tangent.y * vertex.x + normal.y * vertex.z,
          z: vertex.y,
        ),
    ];
  }

  static List<RenderScenePoint> dimensionsForVerticesDummy() => const <RenderScenePoint>[];

  static ({double width, double depth, double height}) dimensionsForVertices(
    List<RenderScenePoint> vertices, {
    double fallbackWidth = 1.0,
    double fallbackDepth = 1.0,
    double fallbackHeight = 1.0,
  }) {
    if (vertices.isEmpty) {
      return (
        width: fallbackWidth,
        depth: fallbackDepth,
        height: fallbackHeight,
      );
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    for (final vertex in vertices) {
      minX = math.min(minX, vertex.x);
      minY = math.min(minY, vertex.y);
      minZ = math.min(minZ, vertex.z);
      maxX = math.max(maxX, vertex.x);
      maxY = math.max(maxY, vertex.y);
      maxZ = math.max(maxZ, vertex.z);
    }
    return (
      width: math.max(maxX - minX, 0.05),
      depth: math.max(maxY - minY, 0.05),
      height: math.max(maxZ - minZ, 0.05),
    );
  }

  static Map<String, Object?> resolvedValues(
    FamilyDocument family,
    FamilyTypeDefinition type,
  ) =>
      FamilyParameterResolver(family, type).resolveAll();

  static Object? resolvedValue(
    FamilyDocument family,
    FamilyTypeDefinition type,
    String parameterId,
  ) =>
      FamilyParameterResolver(family, type).resolveById(parameterId);

  static double lengthValue(
    FamilyDocument family,
    FamilyTypeDefinition type,
    String parameterId, {
    double? fallback,
  }) =>
      _lengthValue(family, type, parameterId, fallback: fallback);

  /// Evaluates project-ready geometry, resolving nested family assets when the
  /// document uses the schema-v6 nested-family feature.
  static Future<FamilyEvaluatedMesh> evaluatedMesh(
    FamilyDocument family,
    FamilyTypeDefinition type,
  ) async {
    final hasNested = family.features.any(
      (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
    );
    final resolvedFamily = hasNested
        ? await FamilyDependencyResolver.resolveFromLibrary(family, type)
        : family;
    return FamilyGeometryEvaluator.evaluateMesh(resolvedFamily, type);
  }

  static Future<FamilyInstancePlacementResult> place({
    required FamilyDocument family,
    required FamilyTypeDefinition type,
    required String familyAssetPath,
    required int levelId,
    required RenderScenePoint position,
    required ViewerElementCreationGateway creationGateway,
    required ViewerAuthoringGateway authoringGateway,
    int? hostWallId,
    RenderSceneObject? hostWall,
    double offsetMeters = 0.0,
  }) async {
    final validation = FamilyDocumentValidator.validate(family);
    if (!validation.isValid) {
      throw FormatException(validation.errors.join('; '));
    }
    if (!family.types.any((candidate) => candidate.id == type.id)) {
      throw const FormatException(
        'Selected family type does not belong to the family.',
      );
    }

    final resolver = FamilyParameterResolver(family, type);
    final resolved = resolver.resolveAll();
    final evaluatedMesh = await FamilyInstanceAdapter.evaluatedMesh(family, type);
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
            widthMeters: _resolvedLength(resolver, 'width'),
            depthMeters: _resolvedLength(resolver, 'depth'),
            heightMeters: _resolvedLength(resolver, 'height'),
          );
        }
      case FamilyCategory.door:
        final wallId = hostWallId;
        if (wallId == null) {
          throw const FormatException('A door family must be hosted by a wall.');
        }
        created = await creationGateway.createDoor(
          name: family.name,
          hostWallId: wallId,
          offsetMeters: offsetMeters,
          widthMeters: _resolvedLength(resolver, 'width'),
          heightMeters: _resolvedLength(resolver, 'height'),
        );
      case FamilyCategory.window:
        final wallId = hostWallId;
        if (wallId == null) {
          throw const FormatException('A window family must be hosted by a wall.');
        }
        created = await creationGateway.createWindow(
          name: family.name,
          hostWallId: wallId,
          offsetMeters: offsetMeters,
          widthMeters: _resolvedLength(resolver, 'width'),
          heightMeters: _resolvedLength(resolver, 'height'),
          sillHeightMeters: _resolvedLength(
            resolver,
            'sillHeight',
            fallback: 0.9,
          ),
        );
      case FamilyCategory.wallSweep:
        final wallId = hostWallId;
        if (wallId == null || hostWall == null) {
          throw const FormatException('A wall sweep family must be hosted by a wall.');
        }
        final wallLength = RenderSceneQueries.wallLength(hostWall);
        final sweepWidth = _resolvedLength(resolver, 'width');
        if (wallLength == null ||
            !wallLength.isFinite ||
            wallLength <= 1e-6 ||
            sweepWidth > wallLength - 0.02) {
          throw const FormatException(
            'Wall sweep width must fit inside the selected wall.',
          );
        }
        created = await _createMeshInstance(
          family: family,
          type: type,
          position: RenderSceneQueries.wallPointAtOffset(hostWall, offsetMeters) ??
              position,
          levelId: levelId,
          evaluatedMesh: evaluatedMesh,
          creationGateway: creationGateway,
          hostWall: hostWall,
          hostOffsetMeters: offsetMeters,
        );
      case FamilyCategory.genericModel:
      case FamilyCategory.furniture:
      case FamilyCategory.casework:
      case FamilyCategory.stair:
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
      familyParameterDefinitionsJson: jsonEncode(
        family.parameters.map((parameter) => parameter.toJson()).toList(),
      ),
      familyParameterValuesJson: jsonEncode(
        <String, Object?>{
          ...resolved,
          if (category == FamilyCategory.wallSweep) ...<String, Object?>{
            '_hostWallId': hostWallId,
            '_hostOffsetMeters': offsetMeters,
          },
        },
      ),
      familyPlanSvg: FamilyPlanSymbolGenerator.svgFor(
        family,
        type,
        rotationRadians: category == FamilyCategory.wallSweep
            ? _wallRotation(hostWall, offsetMeters)
            : 0.0,
      ),
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
    RenderSceneObject? hostWall,
    double hostOffsetMeters = 0.0,
  }) {
    final indices = triangleIndices(evaluatedMesh);
    if (indices.isEmpty) {
      throw const FormatException('Family mesh has no renderable triangles.');
    }
    final vertices = hostWall == null
        ? projectVertices(evaluatedMesh, position)
        : projectWallHostedVertices(
            mesh: evaluatedMesh,
            hostWall: hostWall,
            offsetMeters: hostOffsetMeters,
          );
    final dimensions = dimensionsForVertices(
      vertices,
      fallbackWidth: _lengthValue(family, type, 'width', fallback: 1.0),
      fallbackDepth: _lengthValue(family, type, 'depth', fallback: 1.0),
      fallbackHeight: _lengthValue(family, type, 'height', fallback: 1.0),
    );
    return creationGateway.createFamilyProxy(
      name: '${family.name} · ${type.name}',
      levelId: levelId,
      position: position,
      widthMeters: dimensions.width,
      depthMeters: dimensions.depth,
      heightMeters: dimensions.height,
      vertices: vertices,
      indices: indices,
    );
  }

  static double _wallRotation(RenderSceneObject? wall, double offsetMeters) {
    if (wall == null) return 0.0;
    final tangent = RenderSceneQueries.wallTangentAtOffset(wall, offsetMeters);
    if (tangent == null) return 0.0;
    return math.atan2(tangent.y, tangent.x);
  }

  static double _resolvedLength(
    FamilyParameterResolver resolver,
    String parameterId, {
    double? fallback,
  }) {
    try {
      final value = resolver.resolveNumber(parameterId);
      if (value.isFinite && value > 0.0) return value;
    } on FormatException {
      if (fallback != null) return fallback;
      rethrow;
    }
    if (fallback != null) return fallback;
    throw FormatException('Family parameter "$parameterId" must be positive.');
  }

  static double _lengthValue(
    FamilyDocument family,
    FamilyTypeDefinition type,
    String parameterId, {
    double? fallback,
  }) {
    final resolver = FamilyParameterResolver(family, type);
    return _resolvedLength(resolver, parameterId, fallback: fallback);
  }
}
