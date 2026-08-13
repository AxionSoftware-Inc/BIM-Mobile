import 'render_scene_models.dart';
import 'viewer_engine_contracts.dart';
import 'viewer_project_session.dart';

/// Result of a lifecycle operation that may have created a replacement session.
class ProjectSessionResult<T extends ViewerProjectSession> {
  const ProjectSessionResult({
    required this.session,
    required this.createdSession,
    this.renderScene,
    this.load,
  });

  final T session;
  final bool createdSession;
  final RenderSceneLoadResult? renderScene;
  final ViewerLoadResult? load;
}

/// Engine project lifecycle use-cases: session creation, templates and imports.
///
/// It owns failure cleanup for sessions it created. The app shell owns only the
/// successful active-session replacement.
class ProjectLifecycleService<T extends ViewerProjectSession> {
  ProjectLifecycleService({required ViewerSessionFactory<T> sessionFactory})
      : _sessionFactory = sessionFactory;

  final ViewerSessionFactory<T> _sessionFactory;

  Future<ProjectSessionResult<T>> createBlankProject({
    T? existingSession,
    String projectName = 'New Project',
  }) async {
    final createdSession = existingSession == null;
    final session = existingSession ?? await _sessionFactory.create();
    try {
      final renderScene = await session.createBlankProject(
        projectName: projectName,
      );
      return ProjectSessionResult<T>(
        session: session,
        createdSession: createdSession,
        renderScene: renderScene,
      );
    } catch (_) {
      if (createdSession) session.dispose();
      rethrow;
    }
  }

  Future<ProjectSessionResult<T>> createResidentialTemplate({
    T? existingSession,
    required int buildingCount,
    required int storyCount,
  }) async {
    final createdSession = existingSession == null;
    final session = existingSession ?? await _sessionFactory.create();
    try {
      final renderScene = await session.createResidentialTemplate(
        buildingCount: buildingCount,
        storyCount: storyCount,
      );
      return ProjectSessionResult<T>(
        session: session,
        createdSession: createdSession,
        renderScene: renderScene,
      );
    } catch (_) {
      if (createdSession) session.dispose();
      rethrow;
    }
  }

  Future<ProjectSessionResult<T>> loadJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    final session = await _sessionFactory.create();
    try {
      final load = await session.loadFromJson(
        projectName: projectName,
        json: json,
        sourcePath: sourcePath,
      );
      return ProjectSessionResult<T>(
        session: session,
        createdSession: true,
        load: load,
      );
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }

  Future<ProjectSessionResult<T>> loadPackage({
    required String packagePath,
  }) async {
    final session = await _sessionFactory.create();
    try {
      final load = await session.loadFromPackage(packagePath: packagePath);
      return ProjectSessionResult<T>(
        session: session,
        createdSession: true,
        load: load,
      );
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }
}
