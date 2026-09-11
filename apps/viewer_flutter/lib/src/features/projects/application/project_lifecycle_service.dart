import '../../../core/application/engine/viewer_engine_contracts.dart';
import '../../../core/application/engine/viewer_project_session.dart';
import '../../../core/application/render_scene/render_scene_models.dart';
import 'project_companion_document.dart';

/// Result of a lifecycle operation that may have created a replacement session.
final class ProjectSessionResult<T extends ViewerProjectSession> {
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
/// OWNERSHIP:
/// - owns failure cleanup for sessions it creates;
/// - coordinates non-authoritative companion documents through a typed port;
/// - does not import annotation/documentation feature implementations;
/// - does not own Flutter widget state.
final class ProjectLifecycleService<T extends ViewerProjectSession> {
  ProjectLifecycleService({
    required ViewerSessionFactory<T> sessionFactory,
    ProjectCompanionDocuments? companions,
  })  : _sessionFactory = sessionFactory,
        _companions = companions ?? ProjectCompanionDocuments.empty;

  final ViewerSessionFactory<T> _sessionFactory;
  final ProjectCompanionDocuments _companions;

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
      await _companions.resetForNewProject();
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
      await _companions.resetForNewProject();
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

  Future<ProjectSessionResult<T>> createShowcaseTemplate({
    T? existingSession,
    required int templateKind,
  }) async {
    final createdSession = existingSession == null;
    final session = existingSession ?? await _sessionFactory.create();
    try {
      final renderScene = await session.createShowcaseTemplate(
        templateKind: templateKind,
      );
      await _companions.resetForNewProject();
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
      await _companions.restoreForProjectPath(sourcePath);
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

  Future<ProjectSessionResult<T>> loadIfc({
    required String projectName,
    required String ifcPath,
  }) async {
    final session = await _sessionFactory.create();
    try {
      final load = await session.loadFromIfc(ifcPath: ifcPath);
      await _companions.resetForNewProject();
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
      await _companions.restoreForProjectPath(packagePath);
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
