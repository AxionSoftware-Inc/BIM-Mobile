import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/cache/ifc_import_cache_store.dart';

void main() {
  test('cache key is deterministic and separates different source paths', () {
    final first = IfcImportCacheStore.cacheKey('/models/site.ifc');
    final repeated = IfcImportCacheStore.cacheKey('/models/site.ifc');
    final other = IfcImportCacheStore.cacheKey('/archive/site.ifc');

    expect(first, repeated);
    expect(first, isNot(other));
    expect(first, contains('site.ifc_'));
  });

  test('import signature includes source identity, size and modified time', () {
    final signature = IfcImportCacheStore.importSignatureFor(
      path: '/models/site.ifc',
      size: 123456,
      modifiedMilliseconds: 987654321,
    );

    expect(
      signature,
      'tbe-ifc-cache-v2|/models/site.ifc|123456|987654321',
    );
  });

  test('native cache signature is versioned on top of IFC signature', () {
    const sourceSignature = 'tbe-ifc-cache-v2|model.ifc|10|20';
    expect(
      IfcImportCacheStore.nativeBimCacheSignatureFor(
        importSignature: sourceSignature,
      ),
      'tbe-bimcache-v4-simple-box-window|$sourceSignature',
    );
  });
}
