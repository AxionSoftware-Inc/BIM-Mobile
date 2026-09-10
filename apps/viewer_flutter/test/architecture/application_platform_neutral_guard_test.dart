import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application layer has zero Flutter FFI and platform-I/O debt', () {
    final sourceRoot = _sourceRoot();
    const forbidden = <String>[
      "import 'dart:io'",
      "import 'dart:ffi'",
      'package:flutter/',
      'package:file_selector/',
    ];
    final violations = <String>[];

    for (final file in _dartFiles(sourceRoot)) {
      final relative = _relativeTo(sourceRoot, file).replaceAll('\\', '/');
      final isApplication = relative.startsWith('core/application/') ||
          (relative.startsWith('features/') &&
              relative.contains('/application/'));
      if (!isApplication) continue;

      final text = file.readAsStringSync();
      for (final token in forbidden) {
        if (text.contains(token)) violations.add('$relative -> $token');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Application use-cases must be framework/platform neutral. '
          'Put Flutter, FFI and dart:io behind presentation/platform adapters.',
    );
  });
}

Directory _sourceRoot() {
  final packageLocal = Directory('lib/src');
  if (packageLocal.existsSync()) return packageLocal.absolute;

  final repositoryLocal = Directory('apps/viewer_flutter/lib/src');
  if (repositoryLocal.existsSync()) return repositoryLocal.absolute;

  throw StateError('Could not locate apps/viewer_flutter/lib/src.');
}

Iterable<File> _dartFiles(Directory root) sync* {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

String _relativeTo(Directory root, File file) {
  final normalizedRoot = root.path.replaceAll('\\', '/');
  final normalizedFile = file.path.replaceAll('\\', '/');
  if (normalizedFile.startsWith('$normalizedRoot/')) {
    return normalizedFile.substring(normalizedRoot.length + 1);
  }
  return normalizedFile;
}
