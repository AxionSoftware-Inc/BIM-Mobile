import '../render_scene/render_scene_models.dart';

/// Generic element mutations shared by element property surfaces.
abstract interface class ViewerElementAuthoringGateway {
  Future<RenderSceneLoadResult> moveElement({
    required int elementId,
    required double deltaX,
    required double deltaY,
  });

  Future<RenderSceneLoadResult> setElementAssembly({
    required int elementId,
    required int assemblyId,
  });

  Future<RenderSceneLoadResult> deleteElement({
    required int elementId,
  });
}
