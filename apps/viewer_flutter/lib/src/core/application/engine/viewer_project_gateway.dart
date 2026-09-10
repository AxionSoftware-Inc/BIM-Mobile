import '../../../render_scene_models.dart';
import 'viewer_engine_contracts.dart';

/// Persistence and project-session boundary for the authoritative BIM document.
///
/// This intentionally excludes viewport navigation and element authoring so
/// project checkpoints can evolve without widening those feature contracts.
abstract interface class ViewerProjectGateway {
  Future<ViewerLoadResult> loadFromJson({
    required String projectName,
    required String json,
    String? sourcePath,
  });

  Future<ViewerLoadResult> loadFromPackage({
    required String packagePath,
  });

  Future<ViewerLoadResult> loadFromIfc({
    required String ifcPath,
  });

  Future<void> exportIfc({
    required String path,
  });

  Future<Map<String, dynamic>> getUnitSettings();

  Future<void> setUnitSettings({
    required String system,
    required String length,
    required String angle,
  });

  Future<ViewerLoadResult> reloadCurrent();

  Future<String> saveProjectJson();

  /// Legacy native adapters may still return a platform save artifact (for
  /// example dart:io File). Application code must not inspect that artifact;
  /// projects infrastructure translates it to a neutral saved path.
  Future<Object> saveProjectToDefaultLocation();

  Future<RenderSceneLoadResult> undo();

  Future<RenderSceneLoadResult> redo();

  Future<({int undoCount, int redoCount})> historyCounts();

  Future<String> snapshotProjectJson();

  Future<String> snapshotImportedProjectJson();
}
