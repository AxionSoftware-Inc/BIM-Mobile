import 'render_scene_models.dart';
import 'viewer_authoring_gateway.dart';
import 'viewer_element_creation_gateway.dart';
import 'viewer_project_gateway.dart';
import 'viewer_scene_gateway.dart';
import 'viewer_spatial_gateway.dart';

/// Native command required to create an engine-owned starter project.
abstract interface class ViewerTemplateGateway {
  Future<RenderSceneLoadResult> createBlankProject({
    String projectName,
  });

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

/// Complete application-facing session contract used by the workspace.
///
/// The concrete FFI-backed repository implements this contract, but the app
/// shell and feature services depend only on these semantic gateways. This is
/// the seam future local/mock/cloud sessions can implement without changing
/// widgets or authoring controllers.
abstract interface class ViewerEngineSession
    implements
        ViewerProjectSession,
        ViewerAuthoringGateway,
        ViewerElementCreationGateway,
        ViewerSceneGateway,
        ViewerSpatialGateway {}

/// Composition boundary for creating native sessions.
abstract interface class ViewerSessionFactory<T extends ViewerProjectSession> {
  Future<T> create();
}
