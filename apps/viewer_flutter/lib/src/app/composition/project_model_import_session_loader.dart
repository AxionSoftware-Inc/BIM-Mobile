import '../../core/application/engine/viewer_project_session.dart';
import '../../features/projects/application/import/model_import_models.dart';
import '../../features/projects/application/project_lifecycle_service.dart';

/// Composition adapter between project lifecycle and the independent import
/// feature. Import code sees only [ModelImportSessionLoader].
final class ProjectModelImportSessionLoader<T extends ViewerEngineSession>
    implements ModelImportSessionLoader<T> {
  const ProjectModelImportSessionLoader(this._lifecycle);

  final ProjectLifecycleService<T> _lifecycle;

  @override
  Future<T> loadJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    final result = await _lifecycle.loadJson(
      projectName: projectName,
      json: json,
      sourcePath: sourcePath,
    );
    return result.session;
  }

  @override
  Future<T> loadIfc({
    required String projectName,
    required String ifcPath,
  }) async {
    final result = await _lifecycle.loadIfc(
      projectName: projectName,
      ifcPath: ifcPath,
    );
    return result.session;
  }
}
