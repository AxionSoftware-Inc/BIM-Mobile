import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/cache/ifc_import_cache_store.dart';

void main() {
  group('IFC import cache policy', () {
    test('native-first threshold remains eight MiB', () {
      expect(
        IfcImportCacheStore.nativeFirstThresholdBytes,
        8 * 1024 * 1024,
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
