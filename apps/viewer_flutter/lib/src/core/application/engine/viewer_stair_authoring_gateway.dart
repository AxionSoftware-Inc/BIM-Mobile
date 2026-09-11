import '../render_scene/render_scene_models.dart';

/// Stair-specific property mutations.
abstract interface class ViewerStairAuthoringGateway {
  Future<RenderSceneLoadResult> updateStairLayout({
    required int stairId,
    required List<RenderScenePoint> pathPoints,
    required double widthMeters,
    required double landingDepthMeters,
    required int layoutKind,
    required bool railingEnabled,
  });
}
