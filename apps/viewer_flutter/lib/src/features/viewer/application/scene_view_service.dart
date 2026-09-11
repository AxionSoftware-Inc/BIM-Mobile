import '../../../core/application/engine/viewer_engine_contracts.dart';
import '../../../core/application/engine/viewer_scene_gateway.dart';
import '../../../core/application/engine/viewer_scene_gateway_resolver.dart';
import '../../../core/domain/scene/render_scene_models.dart';

/// Application service for refreshing and navigating authoritative scenes.
///
/// VIEWER APPLICATION OWNERSHIP: it keeps viewport feature code independent of
/// concrete FFI/native repositories while preserving engine level-streaming and
/// full-scene policies.
class SceneViewService {
  /// Compatibility constructor for callers that still expose session state as
  /// callbacks. New composition code should prefer [SceneViewService.resolved]
  /// and own availability/session resolution outside this use-case service.
  SceneViewService({
    required ViewerSceneGateway? Function() repository,
    required bool Function() engineEnabled,
  }) : this.resolved(
          _CallbackViewerSceneGatewayResolver(
            repository: repository,
            engineEnabled: engineEnabled,
          ),
        );

  SceneViewService.resolved(ViewerSceneGatewayResolver resolver)
      : _resolver = resolver;

  final ViewerSceneGatewayResolver _resolver;

  Future<RenderSceneLoadResult> refresh() =>
      _resolver.requireSceneGateway().currentRenderScene();

  Future<RenderSceneLoadResult> refreshPrimary() {
    final repository = _resolver.requireSceneGateway();
    if (repository is ViewerPrimarySceneGateway) {
      return repository.currentPrimaryRenderScene();
    }
    return repository.currentRenderScene();
  }

  Future<RenderSceneLoadResult> activateLevel(int levelId) =>
      _resolver.requireSceneGateway().setActiveLevel(levelId);

  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled) =>
      _resolver.requireSceneGateway().setFullSceneRenderScope(enabled);

  Future<RenderSceneLoadResult> section(
    RenderScenePoint start,
    RenderScenePoint end,
  ) =>
      _resolver.requireSceneGateway().sectionScene(start, end);
}

/// Transitional adapter for the pre-resolver construction API.
///
/// Keeping it private prevents callback-based dependency lookup from becoming
/// another public boundary while existing callers migrate incrementally.
final class _CallbackViewerSceneGatewayResolver
    implements ViewerSceneGatewayResolver {
  const _CallbackViewerSceneGatewayResolver({
    required ViewerSceneGateway? Function() repository,
    required bool Function() engineEnabled,
  })  : _repository = repository,
        _engineEnabled = engineEnabled;

  final ViewerSceneGateway? Function() _repository;
  final bool Function() _engineEnabled;

  @override
  ViewerSceneGateway requireSceneGateway() {
    final repository = _repository();
    if (!_engineEnabled() || repository == null) {
      throw TbeApiException('Authoritative engine is required for this view');
    }
    return repository;
  }
}
