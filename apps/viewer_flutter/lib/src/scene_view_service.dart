import 'render_scene_models.dart';
import 'viewer_engine_contracts.dart';
import 'viewer_scene_gateway.dart';

/// Application service for refreshing and navigating authoritative scenes.
///
/// It keeps viewport feature code independent of the concrete FFI repository
/// while preserving the engine's level-streaming and full-scene policies.
class SceneViewService {
  SceneViewService({
    required ViewerSceneGateway? Function() repository,
    required bool Function() engineEnabled,
  })  : _repository = repository,
        _engineEnabled = engineEnabled;

  final ViewerSceneGateway? Function() _repository;
  final bool Function() _engineEnabled;

  Future<RenderSceneLoadResult> refresh() =>
      _requireRepository().currentRenderScene();

  Future<RenderSceneLoadResult> activateLevel(int levelId) =>
      _requireRepository().setActiveLevel(levelId);

  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled) =>
      _requireRepository().setFullSceneRenderScope(enabled);

  Future<RenderSceneLoadResult> section(
    RenderScenePoint start,
    RenderScenePoint end,
  ) =>
      _requireRepository().sectionScene(start, end);

  ViewerSceneGateway _requireRepository() {
    final repository = _repository();
    if (!_engineEnabled() || repository == null) {
      throw TbeApiException('Authoritative engine is required for this view');
    }
    return repository;
  }
}
