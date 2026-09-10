import 'dart:convert';
import 'dart:io';

import '../../../../core/infrastructure/io/atomic_file_writer.dart';
import '../../../../core/infrastructure/storage/app_project_storage.dart';

final class IfcImportCacheEntry {
  const IfcImportCacheEntry({
    required this.json,
    required this.path,
  });

  final String json;
  final String path;
}

final class NativeBimCachePaths {
  const NativeBimCachePaths({
    required this.cachePath,
    required this.signaturePath,
  });

  final String cachePath;
  final String signaturePath;
}

/// App-owned persistent acceleration cache for IFC imports.
///
/// IFC source files remain authoritative. Every operation here is best-effort:
/// an unreadable, stale or partially-written cache is treated as a cache miss
/// and must never hide a valid IFC source.
final class IfcImportCacheStore {
  const IfcImportCacheStore();

  static const int nativeFirstThresholdBytes = 8 * 1024 * 1024;
  static const String _directoryName = 'ifc-cache';

  Future<IfcImportCacheEntry?> readProjectJson(String ifcPath) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;

      final files = await _projectJsonPaths(ifcPath);
      final cached = File(files.cachePath);
      final signatureFile = File(files.signaturePath);
      if (!await cached.exists() || await cached.length() <= 0) return null;
      if (!await signatureFile.exists() ||
          await signatureFile.readAsString() != importSignature(ifcPath, stat)) {
        return null;
      }

      final json = await cached.readAsString();
      final decoded = jsonDecode(json);
      if (decoded is! Map || decoded['schema_version'] == null) return null;
      return IfcImportCacheEntry(json: json, path: cached.path);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeProjectJson(String ifcPath, String json) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          json.isEmpty) {
        return;
      }

      final files = await _projectJsonPaths(ifcPath);
      final cached = File(files.cachePath);
      final signatureFile = File(files.signaturePath);
      final signature = importSignature(ifcPath, stat);
      if (await cached.exists() &&
          await cached.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() == signature) {
        return;
      }

      await atomicWriteString(cached, json);
      await atomicWriteString(signatureFile, signature);
    } catch (_) {
      // Cache storage is optional. Document-provider paths can be read-only and
      // a failed cache write must not turn a valid IFC import into an error.
    }
  }

  Future<NativeBimCachePaths> nativeBimCachePaths(String ifcPath) async {
    final directory = await _cacheDirectory();
    final key = cacheKey(ifcPath);
    final cachePath =
        '${directory.path}${Platform.pathSeparator}$key.bimcache';
    return NativeBimCachePaths(
      cachePath: cachePath,
      signaturePath: '$cachePath.sig',
    );
  }

  Future<NativeBimCachePaths> _projectJsonPaths(String ifcPath) async {
    final directory = await _cacheDirectory();
    final key = cacheKey(ifcPath);
    final cachePath = '${directory.path}${Platform.pathSeparator}$key.json';
    return NativeBimCachePaths(
      cachePath: cachePath,
      signaturePath:
          '${directory.path}${Platform.pathSeparator}$key.sig',
    );
  }

  Future<Directory> _cacheDirectory() async {
    final projectDirectory = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}$_directoryName',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String cacheKey(String path) {
    var hash = 2166136261;
    for (final codeUnit in path.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    final baseName = path
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${baseName}_$hash';
  }

  static String importSignature(String path, FileStat stat) =>
      importSignatureFor(
        path: path,
        size: stat.size,
        modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
      );

  static String importSignatureFor({
    required String path,
    required int size,
    required int modifiedMilliseconds,
  }) =>
      'tbe-ifc-cache-v2|$path|$size|$modifiedMilliseconds';

  static String nativeBimCacheSignature(String path, FileStat stat) =>
      nativeBimCacheSignatureFor(
        importSignature: importSignature(path, stat),
      );

  static String nativeBimCacheSignatureFor({required String importSignature}) =>
      'tbe-bimcache-v4-simple-box-window|$importSignature';
}
