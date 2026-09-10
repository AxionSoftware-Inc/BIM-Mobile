import '../../core/application/engine/viewer_engine_contracts.dart';
import '../../core/application/engine/viewer_project_session.dart';
import '../../core/application/engine/viewer_scene_gateway.dart';
import '../../core/application/engine/viewer_scene_gateway_resolver.dart';
import '../../features/projects/application/project_session_controller.dart';

/// Composition adapter that resolves the scene capability from the active
/// project session.
///
/// Availability/session coordination belongs here rather than in viewer
/// application services. This also keeps feature code independent of the
/// concrete [ViewerEngineSession] lifecycle owner.
final class ProjectSessionSceneGatewayResolver
    implements ViewerSceneGatewayResolver {
  const ProjectSessionSceneGatewayResolver(this._projectSession);

  final ProjectSessionController<ViewerEngineSession> _projectSession;

  @override
  ViewerSceneGateway requireSceneGateway() {
    final session = _projectSession.session;
    if (!_projectSession.isEngineBacked || session == null) {
      throw TbeApiException('Authoritative engine is required for this view');
    }
    return session;
  }
}
