import '../../../elements/wall_type_catalog.dart';
import '../../../render_scene_models.dart';
import '../../../tools/wall_authoring_geometry.dart';

/// Application boundary used by authoring and Inspector use-cases.
///
/// It exposes semantic commands and authoritative scene snapshots only. FFI
/// handles, native ABI details, persistence paths and platform library loading
/// remain below this boundary.
///
/// MIGRATION: this broad compatibility port will be split by authoring
/// capability after callers migrate to feature-level commands. Do not add a
/// new unrelated command here when a typed feature port already exists.
abstract interface class ViewerAuthoringGateway {
  int? get lastCreatedElementId;

  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  });

  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  });

  Future<RenderSceneLoadResult> moveElement({
    required int elementId,
    required double deltaX,
    required double deltaY,
  });

  Future<RenderSceneLoadResult> createWall({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
  });

  Future<RenderSceneLoadResult> createCurvedWall({
    required String name,
    required int levelId,
    required WallArcGeometry geometry,
    required double thicknessMeters,
    required double heightMeters,
  });

  Future<RenderSceneLoadResult> setWallType({
    required int wallId,
    required int wallTypeId,
  });

  Future<RenderSceneLoadResult> createWallTypeForWall({
    required int wallId,
    required WallTypeCategory category,
    required String name,
    required List<WallTypeLayerDefinition> layers,
  });

  Future<RenderSceneLoadResult> setElementAssembly({
    required int elementId,
    required int assemblyId,
  });

  Future<RenderSceneLoadResult> setElementFamilyReference({
    required int elementId,
    required String familyAssetId,
    required String familyName,
    required String familyTypeId,
    required String familyTypeName,
    required String familyCategory,
    String familyAssetPath = '',
    String familyParameterDefinitionsJson = '',
    String familyParameterValuesJson = '',
    String familyPlanSvg = '',
  });

  Future<RenderSceneLoadResult> updateFamilyInstance({
    required int elementId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    required List<RenderScenePoint> vertices,
    required List<int> indices,
  });

  Future<RenderSceneLoadResult> createWallTransaction({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
    int topLevelId = 0,
    bool autoJoin = false,
  });

  Future<RenderSceneLoadResult> setWallLevelConstraints({
    required int wallId,
    required int baseLevelId,
    int topLevelId = 0,
    double baseOffsetMeters = 0.0,
    double topOffsetMeters = 0.0,
    int heightMode = 0,
  });

  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  });

  Future<RenderSceneLoadResult> setCurvedWallGeometry({
    required int wallId,
    required WallArcGeometry geometry,
  });

  Future<RenderSceneLoadResult> autoJoinWalls();

  Future<RenderSceneLoadResult> trimExtendWalls({
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  });

  Future<RenderSceneLoadResult> moveHostedOpening({
    required int openingId,
    required double offsetMeters,
  });

  Future<RenderSceneLoadResult> resizeOpening({
    required int openingId,
    required String kind,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  });

  Future<RenderSceneLoadResult> updateHostedOpening({
    required int openingId,
    required String kind,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  });

  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  });

  Future<RenderSceneLoadResult> setOpeningLevelConstraint({
    required int openingId,
    required int levelId,
    required double levelOffsetMeters,
  });

  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  });

  Future<RenderSceneLoadResult> updateStairLayout({
    required int stairId,
    required List<RenderScenePoint> pathPoints,
    required double widthMeters,
    required double landingDepthMeters,
    required int layoutKind,
    required bool railingEnabled,
  });

  Future<RenderSceneLoadResult> deleteElement({
    required int elementId,
  });
}
