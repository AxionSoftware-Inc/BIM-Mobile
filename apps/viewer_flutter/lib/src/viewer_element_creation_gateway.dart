import 'render_scene_models.dart';

/// Semantic creation and room/surface authoring boundary.
///
/// The workspace uses this contract for authoring primitives that are not
/// part of the wall/opening edit commands. Implementations may be native,
/// replayed, or in-memory without exposing ABI handles to the UI.
abstract interface class ViewerElementCreationGateway {
  int? get lastCreatedElementId;

  Future<RenderSceneLoadResult> createLevel({
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  });

  Future<RenderSceneLoadResult> createStair({
    required int baseLevelId,
    required int topLevelId,
    required RenderScenePoint start,
    required RenderScenePoint direction,
    required double widthMeters,
    required double totalRiseMeters,
    required double totalRunMeters,
    required int riserCount,
    required int treadCount,
  });

  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  });

  Future<RenderSceneLoadResult> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  });

  Future<RenderSceneLoadResult> createProfile({
    required int targetKind,
    required int draftMode,
    required int levelId,
    required List<RenderScenePoint> points,
    List<int> wallIds,
    required bool closed,
    required double thicknessMeters,
    required double heightMeters,
    required double verticalOffsetMeters,
    int materialId,
    int assemblyId,
    int roofType,
  });

  Future<RenderSceneLoadResult> detectRooms();

  Future<RenderSceneLoadResult> createFloorSystemForRoom({
    required int roomId,
    required int assemblyId,
  });

  Future<RenderSceneLoadResult> createCeilingSystemForRoom({
    required int roomId,
    required int assemblyId,
    required double heightOffsetMeters,
  });

  Future<RenderSceneLoadResult> setStructuralWallCut({
    required int wallId,
    required int cutterId,
    required bool enabled,
    double clearanceMeters,
  });

  Future<RenderSceneLoadResult> setBeamColumnJoin({
    required int beamId,
    required int columnId,
    required bool enabled,
  });

  Future<int?> defaultAssemblyId(String kind);
}
