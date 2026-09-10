import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('property editor has one canonical library owner', () {
    final root = _sourceRoot();
    final canonical = File(
      '${root.path}/features/elements/presentation/property_editor/property_editor.dart',
    );
    expect(canonical.existsSync(), isTrue);

    final source = canonical.readAsStringSync();
    expect(source, isNot(contains("import '../../../../family_authoring/")));
    expect(source, isNot(contains("import '../../../../elements/")));

    final legacyParts = Directory('${root.path}/elements/inspectors');
    if (legacyParts.existsSync()) {
      final dartParts = legacyParts
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(
        dartParts,
        isEmpty,
        reason: 'Inspector parts must live with the canonical PropertyEditor library.',
      );
    }
  });
}

Directory _sourceRoot() {
  final local = Directory('lib/src');
  if (local.existsSync()) return local.absolute;
  final repo = Directory('apps/viewer_flutter/lib/src');
  if (repo.existsSync()) return repo.absolute;
  throw StateError('Could not locate viewer_flutter lib/src.');
}
