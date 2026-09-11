import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy family_runtime directory remains compatibility-facade only', () {
    final root = _sourceRoot();
    final legacy = Directory('${root.path}/family_runtime');
    if (!legacy.existsSync()) return;

    expect(
      legacy
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      isEmpty,
      reason: 'The legacy family_runtime compatibility directory is retired; '
          'implementations belong to features/families.',
    );
  });
}

Directory _sourceRoot() {
  final local = Directory('lib/src');
  if (local.existsSync()) return local.absolute;
  final repo = Directory('apps/viewer_flutter/lib/src');
  if (repo.existsSync()) return repo.absolute;
  throw StateError('Could not locate apps/viewer_flutter/lib/src.');
}
