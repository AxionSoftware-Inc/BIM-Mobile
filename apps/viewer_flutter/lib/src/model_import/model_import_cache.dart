import 'dart:convert';
import 'dart:io';

import '../app_project_storage.dart';
import '../atomic_file_writer.dart';
import 'model_import_models.dart';

class ModelImportSemanticCacheEntry {
  const ModelImportSemanticCacheEntry({
    required this.json,
    required this.path,
  });

  final String json;
  final String path;
}

/// Disposable import artifacts. Source files and the live BIM document remain
/// authoritative; every cache entry is versioned and fingerprinted.
class ModelImportCacheStore {
  Future<Directory> _formatDirectory(ModelImportSource source) async {
    final projectDirectory = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}import-cache'
      '${Platform.pathSeparator}${source.format.id}',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  String _sourceKey(ModelImportSource source) {
    var hash = 2166136261;
    for (final codeUnit in source.path.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    final baseName = source.displayName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '${baseName.isEmpty ? source.format.id : baseName}_$hash';
  }

  String _semanticSignature(ModelImportSource source) =>
      'tbe-import-semantic-v${source.format.semanticCacheVersion}|'
      '${source.format.id}|${source.path}|${source.byteSize}|'
      '${source.modifiedMilliseconds}';

  Future<ModelImportSemanticCacheEntry?> readSemantic(
    ModelImportSource source,
  ) async {
    try {
      final directory = await _formatDirectory(source);
      final key = _sourceKey(source);
      final cached = File(
        '${directory.path}${Platform.pathSeparator}$key.project.json',
      );
      final signatureFile = File('${cached.path}.sig');
      if (!await cached.exists() || await cached.length() <= 0) return null;
      if (!await signatureFile.exists() ||
          await signatureFile.readAsString() != _semanticSignature(source)) {
        return null;
      }
      final json = await cached.readAsString();
      final decoded = jsonDecode(json);
      if (decoded is! Map || decoded['schema_version'] == null) return null;
      return ModelImportSemanticCacheEntry(json: json, path: cached.path);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSemantic(ModelImportSource source, String json) async {
    if (json.isEmpty) return;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map || decoded['schema_version'] == null) return;
      final directory = await _formatDirectory(source);
      final key = _sourceKey(source);
      final cached = File(
        '${directory.path}${Platform.pathSeparator}$key.project.json',
      );
      await atomicWriteString(cached, json);
      await atomicWriteString(File('${cached.path}.sig'), _semanticSignature(source));
    } catch (_) {
      // Import remains valid even when a document provider or filesystem does
      // not allow a local acceleration cache.
    }
  }

  Future<void> invalidateSemantic(ModelImportSource source) async {
    try {
      final directory = await _formatDirectory(source);
      final key = _sourceKey(source);
      final cached = File(
        '${directory.path}${Platform.pathSeparator}$key.project.json',
      );
      final signature = File('${cached.path}.sig');
      if (await cached.exists()) await cached.delete();
      if (await signature.exists()) await signature.delete();
    } catch (_) {}
  }

  Future<String?> runtimeCachePath(ModelImportSource source) async {
    if (!source.format.supportsNativeRuntimeCache) return null;
    final directory = await _formatDirectory(source);
    final key = _sourceKey(source);
    return '${directory.path}${Platform.pathSeparator}$key.'
        'runtime-v${source.format.runtimeCacheVersion}.bimcache';
  }
}
