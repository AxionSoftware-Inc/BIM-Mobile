import 'render_scene_models.dart';

/// Native query boundary used by viewport navigation.
///
/// It contains snapshot queries only. Project lifecycle, persistence and FFI
/// implementation remain separate concerns.
abstract interface class ViewerSceneGateway {
  Future<RenderSceneLoadResult> currentRenderScene();

  Future<RenderSceneLoadResult> setActiveLevel(int levelId);

  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled);

  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  );
}

/// Optional fast-open capability. Keeping this separate from the normal
/// scene gateway means fallback/test gateways do not need to know about the
/// native primary-stage query.
abstract interface class ViewerPrimarySceneGateway
    implements ViewerSceneGateway {
  Future<RenderSceneLoadResult> currentPrimaryRenderScene();
}
