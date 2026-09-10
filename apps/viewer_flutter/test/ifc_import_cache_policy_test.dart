import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/application/import/ifc_import_policy.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/cache/ifc_import_cache_store.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/ifc_import_cache_service.dart';

void main() {
  group('IFC import cache policy', () {
    test('native-first threshold has one application policy value', () {
      expect(
        IfcImportPolicy.nativeFirstThresholdBytes,
        8 * 1024 * 1024,
      );
      expect(
        IfcImportCacheStore.nativeFirstThresholdBytes,
        IfcImportPolicy.nativeFirstThresholdBytes,
      );
      expect(
        IfcImportCacheService.nativeFirstThresholdBytes,
        IfcImportPolicy.nativeFirstThresholdBytes,
      );
    });

    test('application policy requires both threshold and native viewport', () {
      const threshold = IfcImportPolicy.nativeFirstThresholdBytes;
      expect(
        IfcImportPolicy.shouldPreferNativeFirst(
          sourceBytes: threshold - 1,
          nativeViewport: true,
        ),
        isFalse,
      );
      expect(
        IfcImportPolicy.shouldPreferNativeFirst(
          sourceBytes: threshold,
          nativeViewport: false,
        ),
        isFalse,
      );
      expect(
        IfcImportPolicy.shouldPreferNativeFirst(
          sourceBytes: threshold,
          nativeViewport: true,
        ),
        isTrue,
      );
    });

    test('project JSON cache signature remains versioned and source-sensitive', () {
      expect(
        IfcImportCacheStore.importSignatureFor(
          path: '/models/tower.ifc',
          size: 123456,
          modifiedMilliseconds: 987654321,
        ),
        'tbe-ifc-cache-v2|/models/tower.ifc|123456|987654321',
      );
    });

    test('native BIM cache signature wraps the authoritative IFC signature', () {
      const importSignature =
          'tbe-ifc-cache-v2|/models/tower.ifc|123456|987654321';
      expect(
        IfcImportCacheStore.nativeBimCacheSignatureFor(
          importSignature: importSignature,
        ),
        'tbe-bimcache-v4-simple-box-window|$importSignature',
      );
    });

    test('cache key is deterministic and changes with source path', () {
      final first = IfcImportCacheStore.cacheKey('/a/model.ifc');
      final repeated = IfcImportCacheStore.cacheKey('/a/model.ifc');
      final other = IfcImportCacheStore.cacheKey('/b/model.ifc');

      expect(repeated, first);
      expect(other, isNot(first));
      expect(first, endsWith('.ifc_${first.split('_').last}'));
    });
  });
}
