import '../render_scene/render_scene_models.dart';

/// Semantic mutations owned by the level authoring capability.
abstract interface class ViewerLevelAuthoringGateway {
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
}
