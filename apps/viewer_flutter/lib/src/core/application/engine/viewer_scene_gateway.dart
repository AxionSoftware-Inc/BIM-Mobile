import '../render_scene/render_scene_models.dart';

/// Read-only native scene query boundary used by viewport/navigation features.
abstract interface class ViewerSceneGateway {
  Future<RenderSceneLoadResult> currentRenderScene();

  Future<RenderSceneLoadResult> setActiveLevel(int levelId);

  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled);

  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  );
}

/// Optional fast-open capability. Keeping this separate from the normal scene
/// gateway means fallback/test gateways do not know about the native primary
/// stage query.
abstract interface class ViewerPrimarySceneGateway
    implements ViewerSceneGateway {
  Future<RenderSceneLoadResult> currentPrimaryRenderScene();
}
