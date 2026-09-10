import 'dart:async';
import 'dart:io';

import '../../../core/application/engine/viewer_bim_cache_gateway.dart';
import '../application/import/ifc_import_policy.dart';
import 'cache/ifc_import_cache_store.dart' as canonical;
import 'cache/native_bim_cache_service.dart';

/// COMPATIBILITY: validated cached project-JSON checkpoint retained for the
/// pre-store IFC cache API.
/// REMOVE WHEN: no caller imports IfcImportCacheService.
final class IfcImportCacheEntry {
  const IfcImportCacheEntry({required this.json, required this.path});

  final String json;
  final String path;
}

/// COMPATIBILITY: thin adapter for the pre-split IFC cache service.
/// REMOVE WHEN: all callers depend on IfcImportCacheStore,
/// NativeBimCacheService and IfcImportPolicy directly.
///
/// The cache algorithms have a single canonical owner under `cache/`; this
/// adapter preserves the old public surface without retaining duplicate file,
/// signature or native-cache logic.
final class IfcImportCacheService {
  const IfcImportCacheService();

  static const int nativeFirstThresholdBytes =
      IfcImportPolicy.nativeFirstThresholdBytes;
  static const canonical.IfcImportCacheStore _store =
      canonical.IfcImportCacheStore();

  Future<bool> shouldUseNativeFirst(String ifcPath) async {
    try {
      final stat = await File(ifcPath).stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        return false;
      }
      return IfcImportPolicy.shouldPreferNativeFirst(
        sourceBytes: stat.size,
        nativeViewport: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<IfcImportCacheEntry?> readProjectJson(String ifcPath) async {
    final entry = await _store.readProjectJson(ifcPath);
    if (entry == null) return null;
    return IfcImportCacheEntry(json: entry.json, path: entry.path);
  }

  Future<void> writeProjectJson(String ifcPath, String json) =>
      _store.writeProjectJson(ifcPath, json);

  Future<String?> ensureNativeBimCache({
    required String ifcPath,
    required ViewerBimRuntimeCacheGateway? gateway,
    FutureOr<void> Function()? onCompileStart,
  }) {
    if (gateway == null) return Future<String?>.value(null);
    return NativeBimCacheService(
      gateway: gateway,
      cacheStore: _store,
    ).ensure(
      ifcPath,
      onCompile: onCompileStart,
    );
  }
}
