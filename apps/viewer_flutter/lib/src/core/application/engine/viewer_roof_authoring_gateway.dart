import '../render_scene/render_scene_models.dart';

/// Roof-specific property mutations.
abstract interface class ViewerRoofAuthoringGateway {
  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  });
}
