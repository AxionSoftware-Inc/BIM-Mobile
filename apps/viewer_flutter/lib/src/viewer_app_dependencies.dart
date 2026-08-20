import 'native_viewer_session_factory.dart';
import 'project_lifecycle_service.dart';
import 'project_session_controller.dart';
import 'viewer_project_session.dart';

/// Dependencies owned by one workspace instance.
///
/// Production construction is kept in one composition root. Widgets receive
/// semantic services and do not construct FFI adapters or native sessions.
final class ViewerAppDependencies {
  ViewerAppDependencies({
    required this.projectLifecycle,
    required this.projectSession,
  });

  factory ViewerAppDependencies.production() {
    return ViewerAppDependencies(
      projectLifecycle: ProjectLifecycleService<ViewerEngineSession>(
        sessionFactory: NativeViewerSessionFactory(),
      ),
      projectSession: ProjectSessionController<ViewerEngineSession>(),
    );
  }

  final ProjectLifecycleService<ViewerEngineSession> projectLifecycle;
  final ProjectSessionController<ViewerEngineSession> projectSession;

  void dispose() {
    projectSession.dispose();
  }
}
