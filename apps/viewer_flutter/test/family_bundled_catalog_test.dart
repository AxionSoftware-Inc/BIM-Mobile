import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('bundled Family decoder accepts a production-valid .bimfamily document',
      () {
    final source = FamilyDocument.starter(name: 'Bundled Chair');
    final decoded = FamilyBundledCatalog.decodeAsset(
      'assets/families/bundled_chair.bimfamily',
      source.toJsonText(),
    );

    expect(decoded.id, source.id);
    expect(decoded.name, 'Bundled Chair');
    expect(decoded.types.single.id, source.types.single.id);
    expect(FamilyDocumentValidator.validate(decoded).isValid, true);
  });

  test('bundled Family decoder rejects malformed JSON', () {
    expect(
      () => FamilyBundledCatalog.decodeAsset(
        'assets/families/broken.bimfamily',
        '{ definitely not json',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('invalid JSON'),
        ),
      ),
    );
  });

  test('bundled Family decoder rejects unsupported documents', () {
    expect(
      () => FamilyBundledCatalog.decodeAsset(
        'assets/families/not_family.bimfamily',
        '{"format":"something_else"}',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('not a supported .bimfamily'),
        ),
      ),
    );
  });
}
