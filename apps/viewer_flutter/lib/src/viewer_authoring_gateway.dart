import 'render_scene_models.dart';
import 'elements/wall_type_catalog.dart';
import 'tools/wall_authoring_geometry.dart';

/// Application boundary used by authoring and Inspector use-cases.
///
/// It deliberately exposes semantic commands and authoritative render-scene
/// snapshots only. FFI handles, native ABI details, persistence paths, and
/// platform library loading remain below this boundary.
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

  /// Creates an isolated wall type from the edited layer stack and assigns it
  /// to one wall. Existing walls using the source type remain unchanged.
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

  /// Creates a wall and applies its level constraint/interactive join as one
  /// native-session transaction. The resulting snapshot is refreshed only
  /// after the complete wall state is valid.
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

  /// Applies move and size fields together and refreshes one authoritative
  /// snapshot only after the native transaction succeeds.
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

  Future<RenderSceneLoadResult> deleteElement({
    required int elementId,
  });
}
