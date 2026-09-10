import 'dart:io';

import '../../../../core/application/engine/viewer_bim_cache_gateway.dart';
import '../../../../core/infrastructure/io/atomic_file_writer.dart';
import 'ifc_import_cache_store.dart';

/// Coordinates the disposable engine-owned `.bimcache` artifact for one IFC.
///
/// This infrastructure service owns filesystem freshness checks and the native
/// cache compiler capability. It deliberately has no Flutter/widget/status
/// dependency; callers decide how to present progress and fallback behavior.
final class NativeBimCacheService {
  const NativeBimCacheService({
    required this.gateway,
    this.cacheStore = const IfcImportCacheStore(),
  });

  final ViewerBimRuntimeCacheGateway gateway;
  final IfcImportCacheStore cacheStore;

  Future<String?> ensure(
    String ifcPath, {
    void Function()? onCompile,
  }) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;

      final paths = await cacheStore.nativeBimCachePaths(ifcPath);
      final cacheFile = File(paths.cachePath);
      final signatureFile = File(paths.signaturePath);
      final signature = IfcImportCacheStore.nativeBimCacheSignature(
        ifcPath,
        stat,
      );

      if (await cacheFile.exists() &&
          await cacheFile.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() == signature) {
        return paths.cachePath;
      }

      onCompile?.call();
      final result = await gateway.compileBimRuntimeCache(
        sourceIfcPath: ifcPath,
        cachePath: paths.cachePath,
      );
      if (!result.sourceValid || result.chunkCount == 0) return null;

      await atomicWriteString(signatureFile, signature);
      return paths.cachePath;
    } catch (_) {
      // Acceleration failure is recoverable. The authoritative IFC / project
      // JSON path remains available to the caller.
      return null;
    }
  }
}
