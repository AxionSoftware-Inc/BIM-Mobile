import '../../domain/assemblies/wall_type_catalog.dart';
import '../../domain/geometry/wall_arc_geometry.dart';
import '../render_scene/render_scene_models.dart';

/// Semantic mutations owned by the wall authoring capability.
abstract interface class ViewerWallAuthoringGateway {
  int? get lastCreatedElementId;

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
}
