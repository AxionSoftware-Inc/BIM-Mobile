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
    await atomicWriteString(file, json);
    _state.currentJsonPath = file.path;
    return file;
  }

  int? defaultAssemblyId(String kind) {
    try {
      var json = _state.currentJson;
      final packagePath = _state.currentPackagePath;
      // The native document is authoritative after any edit. A cached load
      // JSON can otherwise miss a newly-created catalog entry or retain an
      // obsolete assembly ordering.
      if (_state.handle != null) {
        final currentJsonPath = _state.currentJsonPath;
        final currentPackagePath = _state.currentPackagePath;
        json = _api.saveProjectJson(_state.handle!);
        _state.currentJson = json;
        // Looking up a catalog entry is read-only from the user's point of
        // view. Keep the original save/reload target intact; otherwise merely
        // adding a floor or ceiling would silently turn a loaded project into
        // an untitled in-memory document.
        _state.currentJsonPath = currentJsonPath;
        _state.currentPackagePath = currentPackagePath;
      } else if (json == null && packagePath != null) {
        json = File('$packagePath/project.json').readAsStringSync();
      }
      if (json == null) return null;
      final decoded = jsonDecode(json);
      final document =
          decoded is Map<String, dynamic> ? decoded['document'] : null;
      final assemblies =
          document is Map<String, dynamic> ? document['assemblies'] : null;
      if (assemblies is! List) return null;

      // ProjectCatalog is authoritative for these semantic defaults. Keep
      // the Dart fallback deterministic for legacy snapshots and never pick
      // an arbitrary first Floor assembly such as Asphalt Surface for a new
      // room floor.
      const preferredNames = <String, List<String>>{
        'floor': <String>['Residential Floor', 'Concrete Floor', 'Wood Floor'],
        'ceiling': <String>['Ceiling'],
        'roof': <String>['Roof'],
        'stair': <String>['Stair'],
      };
      final normalizedKind = kind.toLowerCase();
      final candidates = assemblies
          .whereType<Map<String, dynamic>>()
          .where(
            (entry) =>
                entry['kind']?.toString().toLowerCase() == normalizedKind,
          )
          .toList(growable: false);
      for (final preferred
          in preferredNames[normalizedKind] ?? const <String>[]) {
        for (final entry in candidates) {
          if (entry['name']?.toString().toLowerCase() !=
              preferred.toLowerCase()) {
            continue;
          }
          final id = entry['assembly_id'];
          if (id is int) return id;
          if (id is num) return id.toInt();
        }
      }
      candidates.sort((left, right) {
        final leftId = (left['assembly_id'] as num?)?.toInt() ?? 0;
        final rightId = (right['assembly_id'] as num?)?.toInt() ?? 0;
        return leftId.compareTo(rightId);
      });
      for (final entry in candidates) {
        final id = entry['assembly_id'];
        if (id is int) return id;
        if (id is num) return id.toInt();
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
