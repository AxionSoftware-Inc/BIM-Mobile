import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/application/engine/viewer_bim_cache_gateway.dart';
import '../../../core/infrastructure/io/atomic_file_writer.dart';
import '../../../core/infrastructure/storage/app_project_storage.dart';

/// Validated cached project-JSON checkpoint derived from one IFC source.
final class IfcImportCacheEntry {
  const IfcImportCacheEntry({required this.json, required this.path});

  final String json;
  final String path;
}

/// Infrastructure owner for IFC-derived acceleration artifacts.
///
/// OWNERSHIP:
/// - the IFC file remains authoritative;
/// - JSON and `.bimcache` files are disposable/rebuildable derivatives;
/// - no Flutter/widget state is stored here;
/// - failures are best-effort and must never hide a valid IFC source.
final class IfcImportCacheService {
  const IfcImportCacheService();

  static const int nativeFirstThresholdBytes = 8 * 1024 * 1024;

  Future<bool> shouldUseNativeFirst(String ifcPath) async {
    try {
      final stat = await File(ifcPath).stat();
      return stat.type == FileSystemEntityType.file &&
          stat.size >= nativeFirstThresholdBytes;
    } catch (_) {
      return false;
    }
  }

  Future<IfcImportCacheEntry?> readProjectJson(String ifcPath) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (!_validSource(stat)) return null;
      final directory = await _cacheDirectory();
      final key = _cacheKey(ifcPath);
      final cached = File('${directory.path}${Platform.pathSeparator}$key.json');
      final signatureFile =
          File('${directory.path}${Platform.pathSeparator}$key.sig');
      if (!await cached.exists() || await cached.length() <= 0) return null;
      if (!await signatureFile.exists() ||
          await signatureFile.readAsString() != _ifcSignature(ifcPath, stat)) {
        return null;
      }
      final json = await cached.readAsString();
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema_version'] == null) {
        return null;
      }
      return IfcImportCacheEntry(json: json, path: cached.path);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeProjectJson(String ifcPath, String json) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (!_validSource(stat) || json.isEmpty) return;
      final directory = await _cacheDirectory();
      final key = _cacheKey(ifcPath);
      final cached = File('${directory.path}${Platform.pathSeparator}$key.json');
      final signatureFile =
          File('${directory.path}${Platform.pathSeparator}$key.sig');
      final signature = _ifcSignature(ifcPath, stat);
      if (await cached.exists() &&
          await cached.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() == signature) {
        return;
      }
      await atomicWriteString(cached, json);
      await atomicWriteString(signatureFile, signature);
    } catch (_) {
      // Cache storage is optional. External/document-provider paths may be
      // read-only, while the original IFC remains usable.
    }
  }

  Future<String?> ensureNativeBimCache({
    required String ifcPath,
    required ViewerBimRuntimeCacheGateway? gateway,
    FutureOr<void> Function()? onCompileStart,
  }) async {
    if (gateway == null) return null;
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (!_validSource(stat)) return null;
      final paths = await _nativeCachePaths(ifcPath);
      final cacheFile = File(paths.cachePath);
      final signatureFile = File(paths.signaturePath);
      final signature = _nativeCacheSignature(ifcPath, stat);
      if (await cacheFile.exists() &&
          await cacheFile.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() == signature) {
        return paths.cachePath;
      }

      await onCompileStart?.call();
      final result = await gateway.compileBimRuntimeCache(
        sourceIfcPath: ifcPath,
        cachePath: paths.cachePath,
      );
      if (!result.sourceValid || result.chunkCount == 0) return null;
      await atomicWriteString(signatureFile, signature);
      return paths.cachePath;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _cacheDirectory() async {
    final projectDirectory = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}ifc-cache',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<({String cachePath, String signaturePath})> _nativeCachePaths(
    String ifcPath,
  ) async {
    final directory = await _cacheDirectory();
    final key = _cacheKey(ifcPath);
    final basePath = '${directory.path}${Platform.pathSeparator}$key.bimcache';
    return (cachePath: basePath, signaturePath: '$basePath.sig');
  }

  String _cacheKey(String path) {
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

  bool _validSource(FileStat stat) =>
      stat.type == FileSystemEntityType.file && stat.size > 0;

  String _ifcSignature(String path, FileStat stat) =>
      'tbe-ifc-cache-v2|$path|${stat.size}|'
      '${stat.modified.millisecondsSinceEpoch}';

  String _nativeCacheSignature(String path, FileStat stat) =>
      'tbe-bimcache-v4-simple-box-window|${_ifcSignature(path, stat)}';
}
