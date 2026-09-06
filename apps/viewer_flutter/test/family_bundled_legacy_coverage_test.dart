import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_authoring/built_in_family_catalog.dart';
import 'package:viewer_flutter/src/family_authoring/family_bundled_catalog.dart';
import 'package:viewer_flutter/src/family_authoring/family_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog covers every legacy built-in stable id', () async {
    final legacy = BuiltInFamilyCatalog.families;
    expect(legacy, hasLength(23));

    final bundled = await FamilyBundledCatalog.load();
    final byId = <String, dynamic>{
      for (final family in bundled) family.id: family,
    };

    expect(
      bundled.length,
      greaterThanOrEqualTo(legacy.length),
      reason: 'Every legacy shipped Family must have a bundled asset.',
    );

    for (final family in legacy) {
      expect(
        byId,
        contains(family.id),
        reason:
            'Migrate ${family.id} to assets/families/*.bimfamily before removing legacy coverage.',
      );
      final bundledFamily = byId[family.id]!;
      expect(
        FamilyDocumentValidator.validate(bundledFamily).isValid,
        isTrue,
        reason: 'Bundled Family ${family.id} must pass production validation.',
      );
    }
  });
}
