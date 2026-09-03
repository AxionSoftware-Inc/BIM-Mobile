import 'dart:convert';
import 'dart:io';

import 'app_project_storage.dart';
import 'atomic_file_writer.dart';
import 'async_serial_queue.dart';

bool _isOwnedRecoveryPath({
  required Directory directory,
  required String path,
  required String baseName,
  required bool metadata,
}) {
  final directoryPrefix = '${directory.absolute.path}${Platform.pathSeparator}';
  final absolutePath = File(path).absolute.path;
  if (!absolutePath.startsWith(directoryPrefix)) return false;
  final fileName = absolutePath.substring(directoryPrefix.length);
  if (metadata) return fileName == '$baseName.tbe.recovery.meta.json';
  if (fileName == '$baseName.tbe.recovery.meta.json') return false;
  return fileName == '$baseName.tbe.recovery.json' ||
      (fileName.startsWith('$baseName.tbe.recovery.') &&
          fileName.endsWith('.json'));
}

/// Small durable checkpoint store used only for crash recovery. Recovery files
/// are deliberately separate from user saves so an autosave can never replace
/// the last explicit project checkpoint.
final class ProjectRecoveryEntry {
  const ProjectRecoveryEntry({
    required this.projectName,
    required this.jsonPath,
    required this.updatedAt,
    this.metadataPath,
  });

  final String projectName;
  final String jsonPath;
  final DateTime updatedAt;
  final String? metadataPath;

  Future<String> readJson() async {
    final directory = await AppProjectStorage.projectDirectory();
    final baseName = projectName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    final safeBaseName = baseName.isEmpty ? 'tablet_bim_project' : baseName;
    if (!_isOwnedRecoveryPath(
      directory: directory,
      path: jsonPath,
      baseName: safeBaseName,
      metadata: false,
    )) {
      throw StateError('Recovery file is outside the app recovery store.');
    }
    return File(jsonPath).readAsString();
  }
}

final class ProjectRecoveryStore {
  static const _metadataSuffix = '.tbe.recovery.meta.json';
  static const _jsonSuffix = '.tbe.recovery.json';
  static final SerializedFileWriter _writer = SerializedFileWriter();
  static final AsyncSerialQueue _operationQueue = AsyncSerialQueue();

  Future<ProjectRecoveryEntry> write({
    required String projectName,
    required String json,
  }) =>
      _operationQueue.run<ProjectRecoveryEntry>(() async {
        final directory = await AppProjectStorage.projectDirectory();
        final baseName = _safeName(projectName);
        // Publish a new immutable JSON payload first. The metadata manifest is
        // the commit record, so a crash between the two writes leaves the
        // prior manifest pointing at the prior complete payload.
        final generation = DateTime.now().microsecondsSinceEpoch;
        final jsonFile = File(
          '${directory.path}${Platform.pathSeparator}'
          '$baseName.tbe.recovery.$generation.json',
        );
        final metadataFile = File(
          '${directory.path}${Platform.pathSeparator}$baseName$_metadataSuffix',
        );
        final updatedAt = DateTime.now().toUtc();
        await _writer.write(jsonFile, json);
        await _writer.write(
          metadataFile,
          jsonEncode(<String, Object>{
            'project_name': projectName,
            'json_path': jsonFile.path,
            'updated_at': updatedAt.toIso8601String(),
          }),
        );
        await _removeStalePayloads(
          directory: directory,
          baseName: baseName,
          currentPath: jsonFile.path,
        );
        return ProjectRecoveryEntry(
          projectName: projectName,
          jsonPath: jsonFile.path,
          updatedAt: updatedAt,
          metadataPath: metadataFile.path,
        );
      });

  Future<List<ProjectRecoveryEntry>> list() async {
    final directory = await AppProjectStorage.projectDirectory();
    final entries = <ProjectRecoveryEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith(_metadataSuffix)) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final projectName =
            decoded['project_name']?.toString() ?? 'Recovered project';
        final path = decoded['json_path']?.toString();
        final baseName = _safeName(projectName);
        if (path == null ||
            !_isOwnedRecoveryPath(
              directory: directory,
              path: path,
              baseName: baseName,
              metadata: false,
            ) ||
            !await File(path).exists()) {
          continue;
        }
        final updatedAt = DateTime.tryParse(
              decoded['updated_at']?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        entries.add(ProjectRecoveryEntry(
          projectName: projectName,
          jsonPath: path,
          updatedAt: updatedAt,
          metadataPath: entity.path,
        ));
      } catch (_) {
        // A partially written recovery record is ignored; the next
        // autosave will replace it and a broken entry must not block the
        // start screen.
      }
    }
    entries.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return entries;
  }

  Future<void> _removeStalePayloads({
    required Directory directory,
    required String baseName,
    required String currentPath,
  }) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File || entity.path == currentPath) continue;
        if (!_isOwnedRecoveryPath(
          directory: directory,
          path: entity.path,
          baseName: baseName,
          metadata: false,
        )) {
          continue;
        }
        try {
          await entity.delete();
        } catch (_) {
          // The current manifest and payload are already durable. A stale
          // payload can be cleaned by the next write or explicit deletion.
        }
      }
    } catch (_) {
      // Cleanup is best effort; never turn a durable recovery write into a
      // failed save because an old payload could not be removed.
    }
  }

  Future<void> deleteForProject(String projectName) =>
      _operationQueue.run<void>(() async {
        final directory = await AppProjectStorage.projectDirectory();
        final baseName = _safeName(projectName);
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          final ownedJson = _isOwnedRecoveryPath(
            directory: directory,
            path: entity.path,
            baseName: baseName,
            metadata: false,
          );
          final ownedMetadata = _isOwnedRecoveryPath(
            directory: directory,
            path: entity.path,
            baseName: baseName,
            metadata: true,
          );
          if ((ownedJson || ownedMetadata) && await entity.exists()) {
            await entity.delete();
          }
        }
      });

  Future<void> deleteEntry(ProjectRecoveryEntry entry) =>
      _operationQueue.run<void>(() async {
        final directory = await AppProjectStorage.projectDirectory();
        final baseName = _safeName(entry.projectName);
        final metadataPath = entry.metadataPath ??
            (entry.jsonPath.endsWith(_jsonSuffix)
                ? '${entry.jsonPath.substring(0, entry.jsonPath.length - _jsonSuffix.length)}$_metadataSuffix'
                : null);
        if (metadataPath != null &&
            _isOwnedRecoveryPath(
              directory: directory,
              path: metadataPath,
              baseName: baseName,
              metadata: true,
            )) {
          final metadataFile = File(metadataPath);
          if (await metadataFile.exists()) await metadataFile.delete();
        }
        if (_isOwnedRecoveryPath(
          directory: directory,
          path: entry.jsonPath,
          baseName: baseName,
          metadata: false,
        )) {
          final jsonFile = File(entry.jsonPath);
          if (await jsonFile.exists()) await jsonFile.delete();
        }
      });

  String _safeName(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    return normalized.isEmpty ? 'tablet_bim_project' : normalized;
  }
}
