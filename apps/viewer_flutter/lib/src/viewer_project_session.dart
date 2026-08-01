import 'render_scene_models.dart';
import 'viewer_project_gateway.dart';

/// Native command required to create an engine-owned starter project.
abstract interface class ViewerTemplateGateway {
  Future<RenderSceneLoadResult> createResidentialTemplate({
    required int buildingCount,
    required int storyCount,
  });
}

/// A live, disposable native project session owned above the FFI adapter.
abstract interface class ViewerProjectSession
    implements ViewerProjectGateway, ViewerTemplateGateway {
  void dispose();
}

/// Composition boundary for creating native sessions.
abstract interface class ViewerSessionFactory<T extends ViewerProjectSession> {
  Future<T> create();
}
