import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy family_runtime directory remains compatibility-facade only', () {
    final root = _sourceRoot();
    final legacy = Directory('${root.path}/family_runtime');
    expect(legacy.existsSync(), isTrue);

    final violations = <String>[];
    for (final entity in legacy.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      final name = entity.uri.pathSegments.last;
      if (!text.contains('COMPATIBILITY:') ||
          !text.contains('REMOVE WHEN:') ||
          text.length > 1024) {
        violations.add(name);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Legacy family_runtime may contain only small marked facades; '
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
