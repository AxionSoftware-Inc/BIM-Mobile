import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('viewer domain view contracts are Flutter neutral', () {
    final root = _sourceRoot();
    final directory = Directory('${root.path}/features/viewer/domain/view');
    final violations = <String>[];
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("package:flutter/") ||
          source.contains("dart:ffi") ||
          source.contains("dart:io")) {
        violations.add(entity.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Viewer domain view contracts must remain Flutter/FFI/I/O neutral.',
    );
  });
}

Directory _sourceRoot() {
  final local = Directory('lib/src');
  if (local.existsSync()) return local.absolute;
  final repo = Directory('apps/viewer_flutter/lib/src');
  if (repo.existsSync()) return repo.absolute;
  throw StateError('Could not locate viewer_flutter lib/src.');
}
