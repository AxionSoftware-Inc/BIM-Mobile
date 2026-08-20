part of 'tbe_ffi.dart';

/// Project checkpoint and metadata policy for a native session.
///
/// This module owns source-path bookkeeping, level discovery from imported
/// JSON/packages and lazy assembly-catalog lookup. It does not create or
/// mutate the native document; the repository supplies the JSON checkpoint.
final class TbeProjectPersistenceRepository {
  TbeProjectPersistenceRepository({
    required TbeViewerApi api,
    required TbeRepositoryState state,
  })  : _api = api,
        _state = state;

  final TbeViewerApi _api;
  final TbeRepositoryState _state;

  int primaryLevelIdFromPackage(String packagePath) {
    final projectJsonFile = File('$packagePath/project.json');
    if (!projectJsonFile.existsSync()) return 0;
    try {
      return primaryLevelIdFromProjectJson(projectJsonFile.readAsStringSync());
    } catch (_) {
      return 0;
    }
  }

  int primaryLevelIdFromProjectJson(String json) {
    try {
      final decoded = jsonDecode(json);
      final document =
          decoded is Map<String, dynamic> ? decoded['document'] : null;
      final elements =
          document is Map<String, dynamic> ? document['elements'] : null;
      if (elements is List) {
        for (final element in elements) {
          if (element is Map<String, dynamic> &&
              element['kind']?.toString().toLowerCase() == 'level') {
            final id = element['id'];
            if (id is int) return id;
            if (id is num) return id.toInt();
          }
        }
      }
    } catch (_) {
      return 0;
    }
    return 0;
  }

  Future<File> saveToDefaultLocation({
    required String json,
    required String? projectName,
  }) async {
    final directory = await AppProjectStorage.projectDirectory();
    final rawName = projectName ?? 'tablet_bim_project';
    final fileName = rawName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${fileName.isEmpty ? 'tablet_bim_project' : fileName}.tbe.json',
    );
    await file.writeAsString(json, flush: true);
    _state.currentJsonPath = file.path;
    return file;
  }

  int? defaultAssemblyId(String kind) {
    try {
      var json = _state.currentJson;
      final packagePath = _state.currentPackagePath;
      if (json == null && packagePath != null) {
        json = File('$packagePath/project.json').readAsStringSync();
      }
      if (json == null && _state.handle != null) {
        json = _api.saveProjectJson(_state.handle!);
        _state.currentJson = json;
        _state.currentJsonPath = null;
      }
      if (json == null) return null;
      final decoded = jsonDecode(json);
      final document =
          decoded is Map<String, dynamic> ? decoded['document'] : null;
      final assemblies =
          document is Map<String, dynamic> ? document['assemblies'] : null;
      if (assemblies is List) {
        for (final entry in assemblies) {
          if (entry is Map<String, dynamic> &&
              entry['kind']?.toString().toLowerCase() == kind.toLowerCase()) {
            final id = entry['assembly_id'];
            if (id is int) return id;
            if (id is num) return id.toInt();
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
