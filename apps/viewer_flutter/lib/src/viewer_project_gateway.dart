import 'dart:io';

import 'viewer_engine_contracts.dart';

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

  Future<ViewerLoadResult> reloadCurrent();

  Future<String> saveProjectJson();

  Future<File> saveProjectToDefaultLocation();
}
