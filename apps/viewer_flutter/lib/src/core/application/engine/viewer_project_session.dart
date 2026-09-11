import '../render_scene/render_scene_models.dart';
import 'viewer_element_authoring_gateway.dart';
import 'viewer_element_creation_gateway.dart';
import 'viewer_level_authoring_gateway.dart';
import 'viewer_opening_authoring_gateway.dart';
import 'viewer_project_gateway.dart';
import 'viewer_roof_authoring_gateway.dart';
import 'viewer_scene_gateway.dart';
import 'viewer_spatial_gateway.dart';
import 'viewer_stair_authoring_gateway.dart';
import 'viewer_wall_authoring_gateway.dart';

/// Native command required to create an engine-owned starter project.
abstract interface class ViewerTemplateGateway {
  Future<RenderSceneLoadResult> createBlankProject({
    String projectName,
  });

  Future<RenderSceneLoadResult> createResidentialTemplate({
    required int buildingCount,
    required int storyCount,
  });

  Future<RenderSceneLoadResult> createShowcaseTemplate({
    required int templateKind,
  });
}

/// A live, disposable project session owned above the native adapter.
abstract interface class ViewerProjectSession
    implements ViewerProjectGateway, ViewerTemplateGateway {
  void dispose();
}

/// Complete application-facing engine session contract used by the workspace.
///
/// Concrete FFI/cloud/test repositories implement this port. Feature services
/// depend on the semantic capabilities above, never on native ABI handles.
abstract interface class ViewerEngineSession
    implements
        ViewerProjectSession,
        ViewerElementAuthoringGateway,
        ViewerElementCreationGateway,
        ViewerLevelAuthoringGateway,
        ViewerOpeningAuthoringGateway,
        ViewerRoofAuthoringGateway,
        ViewerSceneGateway,
        ViewerSpatialGateway,
        ViewerStairAuthoringGateway,
        ViewerWallAuthoringGateway {}

/// Composition boundary for creating application-facing engine sessions.
abstract interface class ViewerSessionFactory<T extends ViewerProjectSession> {
  Future<T> create();
}
