import 'dart:io';

import 'viewer_engine_contracts.dart';
import 'render_scene_models.dart';

/// Persistence and project-session boundary for the native BIM document.
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

  Future<File> saveProjectToDefaultLocation();

  /// Applies one native global history transaction and returns the
  /// authoritative scene snapshot.
  Future<RenderSceneLoadResult> undo();

  /// Reapplies one native global history transaction and returns the
  /// authoritative scene snapshot.
  Future<RenderSceneLoadResult> redo();

  Future<({int undoCount, int redoCount})> historyCounts();

  /// Captures native JSON without changing the user's explicit save path.
  Future<String> snapshotProjectJson();

  /// Returns the exact JSON captured during the most recent IFC import.
  ///
  /// IFC import already creates this authoritative checkpoint so the native
  /// adapter can discover the active level. Reusing it avoids serializing a
  /// large model a second time just to populate the import cache.
  Future<String> snapshotImportedProjectJson();
}
