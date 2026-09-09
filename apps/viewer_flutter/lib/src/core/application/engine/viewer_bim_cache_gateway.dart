/// Immutable metadata for the engine-owned render cache derived from an IFC.
///
/// The cache is a disposable acceleration artifact: the IFC source remains the
/// authoritative BIM document and is validated before a cached scene is used.
class BimRuntimeCacheStats {
  const BimRuntimeCacheStats({
    required this.formatVersion,
    required this.sourceValid,
    required this.sourceObjectCount,
    required this.sourceTriangleCount,
    required this.chunkCount,
    required this.primitiveCount,
    required this.bvhNodeCount,
    required this.byteSize,
  });

  final int formatVersion;
  final bool sourceValid;
  final int sourceObjectCount;
  final int sourceTriangleCount;
  final int chunkCount;
  final int primitiveCount;
  final int bvhNodeCount;
  final int byteSize;
}

/// Optional native acceleration capability.
///
/// Project/session contracts deliberately do not require it so test, cloud,
/// and fallback sessions remain valid while the Filament path migrates from
/// JSON scene payloads to native cache chunks.
abstract interface class ViewerBimRuntimeCacheGateway {
  Future<BimRuntimeCacheStats> compileBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  });

  Future<BimRuntimeCacheStats> inspectBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  });
}
