import 'dart:io';

import '../../../render_scene_models.dart';
import 'viewer_engine_contracts.dart';

/// Persistence and project-session boundary for the authoritative BIM document.
///
/// This intentionally excludes viewport navigation and element authoring so
/// project checkpoints can evolve without widening those feature contracts.
///
/// MIGRATION: `File` remains here for API compatibility in 0.3.2. Replace it
/// with a platform-neutral checkpoint/path value once the native repository
/// adapter and save callers are migrated together.
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

  Future<File> saveProjectToDefaultLocation();

  Future<RenderSceneLoadResult> undo();

  Future<RenderSceneLoadResult> redo();

  Future<({int undoCount, int redoCount})> historyCounts();

  Future<String> snapshotProjectJson();

  Future<String> snapshotImportedProjectJson();
}
