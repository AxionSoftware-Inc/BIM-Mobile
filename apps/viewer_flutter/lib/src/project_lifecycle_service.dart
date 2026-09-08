import 'dart:io';

import 'annotations/annotation_sidecar_store.dart';
import 'annotations/annotation_workspace_runtime.dart';
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
  final AnnotationSidecarStore _annotationSidecar =
      const AnnotationSidecarStore();

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
      // A new BIM document must never inherit view annotations from the
      // previously open project. Annotation history is a separate document.
      AnnotationWorkspaceRuntime.resetProject();
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
      AnnotationWorkspaceRuntime.resetProject();
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
      AnnotationWorkspaceRuntime.resetProject();
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
      await _restoreAnnotations(sourcePath);
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
      AnnotationWorkspaceRuntime.resetProject();
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
      await _restoreAnnotations(packagePath);
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

  Future<void> _restoreAnnotations(String? projectPath) async {
    AnnotationWorkspaceRuntime.cancelDraft();
    if (projectPath == null || projectPath.trim().isEmpty) {
      AnnotationWorkspaceRuntime.document.reset();
      return;
    }
    try {
      final store = await _annotationSidecar.load(File(projectPath));
      if (store == null) {
        AnnotationWorkspaceRuntime.document.reset();
      } else {
        AnnotationWorkspaceRuntime.document.replaceStore(store);
      }
    } catch (_) {
      // Documentation corruption must never make the authoritative BIM project
      // unopenable. Start with an empty annotation document; the user can save
      // a fresh versioned sidecar without touching model geometry.
      AnnotationWorkspaceRuntime.document.reset();
    }
  }
}
