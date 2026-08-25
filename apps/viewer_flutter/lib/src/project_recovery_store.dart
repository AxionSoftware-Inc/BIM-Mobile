import 'dart:convert';
import 'dart:io';

import 'app_project_storage.dart';

/// Small durable checkpoint store used only for crash recovery. Recovery files
/// are deliberately separate from user saves so an autosave can never replace
/// the last explicit project checkpoint.
final class ProjectRecoveryEntry {
  const ProjectRecoveryEntry({
    required this.projectName,
    required this.jsonPath,
    required this.updatedAt,
  });

  final String projectName;
  final String jsonPath;
  final DateTime updatedAt;

  Future<String> readJson() => File(jsonPath).readAsString();
}

final class ProjectRecoveryStore {
  static const _metadataSuffix = '.tbe.recovery.meta.json';
  static const _jsonSuffix = '.tbe.recovery.json';

  Future<ProjectRecoveryEntry> write({
    required String projectName,
    required String json,
  }) async {
    final directory = await AppProjectStorage.projectDirectory();
    final baseName = _safeName(projectName);
    final jsonFile = File(
      '${directory.path}${Platform.pathSeparator}$baseName$_jsonSuffix',
    );
    final metadataFile = File(
      '${directory.path}${Platform.pathSeparator}$baseName$_metadataSuffix',
    );
    final updatedAt = DateTime.now().toUtc();
    await jsonFile.writeAsString(json, flush: true);
    await metadataFile.writeAsString(
      jsonEncode(<String, Object>{
        'project_name': projectName,
        'json_path': jsonFile.path,
        'updated_at': updatedAt.toIso8601String(),
      }),
      flush: true,
    );
    return ProjectRecoveryEntry(
      projectName: projectName,
      jsonPath: jsonFile.path,
      updatedAt: updatedAt,
    );
  }

  Future<List<ProjectRecoveryEntry>> list() async {
    final directory = await AppProjectStorage.projectDirectory();
    final entries = <ProjectRecoveryEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith(_metadataSuffix)) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final path = decoded['json_path']?.toString();
        if (path == null || !await File(path).exists()) continue;
        final updatedAt = DateTime.tryParse(
              decoded['updated_at']?.toString() ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        entries.add(ProjectRecoveryEntry(
          projectName: decoded['project_name']?.toString() ?? 'Recovered project',
          jsonPath: path,
          updatedAt: updatedAt,
        ));
      } catch (_) {
        // A partially written recovery record is ignored; the next autosave
        // will replace it and a broken entry must not block the start screen.
      }
    }
    entries.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return entries;
  }

  Future<void> deleteForProject(String projectName) async {
    final directory = await AppProjectStorage.projectDirectory();
    final baseName = _safeName(projectName);
    for (final suffix in <String>[_jsonSuffix, _metadataSuffix]) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$baseName$suffix',
      );
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> deleteEntry(ProjectRecoveryEntry entry) async {
    final jsonFile = File(entry.jsonPath);
    if (await jsonFile.exists()) await jsonFile.delete();
    final metadataPath = entry.jsonPath.endsWith(_jsonSuffix)
        ? '${entry.jsonPath.substring(0, entry.jsonPath.length - _jsonSuffix.length)}$_metadataSuffix'
        : null;
    if (metadataPath != null) {
      final metadataFile = File(metadataPath);
      if (await metadataFile.exists()) await metadataFile.delete();
    }
  }

  String _safeName(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    return normalized.isEmpty ? 'tablet_bim_project' : normalized;
  }
}
