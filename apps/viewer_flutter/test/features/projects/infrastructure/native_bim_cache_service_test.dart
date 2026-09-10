import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/core/application/engine/viewer_bim_cache_gateway.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/cache/native_bim_cache_service.dart';

void main() {
  test('missing IFC returns cache miss without invoking native compiler', () async {
    final gateway = _FakeGateway();
    final service = NativeBimCacheService(gateway: gateway);

    final result = await service.ensure('/definitely/missing/model.ifc');

    expect(result, isNull);
    expect(gateway.compileCalls, 0);
  });
}

final class _FakeGateway implements ViewerBimRuntimeCacheGateway {
  int compileCalls = 0;

  @override
  Future<BimRuntimeCacheStats> compileBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    compileCalls += 1;
    return const BimRuntimeCacheStats(
      formatVersion: 1,
      sourceValid: true,
      sourceObjectCount: 1,
      sourceTriangleCount: 1,
      chunkCount: 1,
      primitiveCount: 1,
      bvhNodeCount: 1,
      byteSize: 1,
    );
  }

  @override
  Future<BimRuntimeCacheStats> inspectBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    return const BimRuntimeCacheStats(
      formatVersion: 1,
      sourceValid: true,
      sourceObjectCount: 1,
      sourceTriangleCount: 1,
      chunkCount: 1,
      primitiveCount: 1,
      bvhNodeCount: 1,
      byteSize: 1,
    );
  }
}
