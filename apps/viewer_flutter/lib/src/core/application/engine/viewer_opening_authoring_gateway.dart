import '../render_scene/render_scene_models.dart';

/// Semantic mutations owned by hosted opening authoring.
abstract interface class ViewerOpeningAuthoringGateway {
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
}
