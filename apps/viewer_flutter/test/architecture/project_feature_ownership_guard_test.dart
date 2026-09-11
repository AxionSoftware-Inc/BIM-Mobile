import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects is the only canonical project bounded context', () {
    final root = _sourceRoot();
    final violations = <String>[];
    final directivePattern =
        RegExp(r'''(?:import|export)\s+['\"]([^'\"]+)['\"]''');

    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relativeTo(root, entity).replaceAll('\\', '/');
      if (relative.startsWith('features/project/')) continue;
      final source = entity.readAsStringSync();
      for (final match in directivePattern.allMatches(source)) {
        final uri = match.group(1)!.replaceAll('\\', '/');
        final target = _resolve(relative, uri);
        if (target.startsWith('features/project/')) {
          violations.add('$relative -> $target');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Canonical code must use features/projects; features/project is '
          'a compatibility-only path.\n${violations.join('\n')}',
    );

    final legacy = Directory('${root.path}/features/project');
    if (!legacy.existsSync()) return;
    final legacyDartFiles = <File>[
      for (final entity in legacy.listSync(recursive: true, followLinks: false))
        if (entity is File && entity.path.endsWith('.dart')) entity,
    ];
    expect(
      legacyDartFiles,
      isEmpty,
      reason: 'The singular features/project compatibility tree is retired.',
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

String _relativeTo(Directory root, File file) {
  final a = root.path.replaceAll('\\', '/');
  final b = file.path.replaceAll('\\', '/');
  return b.startsWith('$a/') ? b.substring(a.length + 1) : b;
}

String _resolve(String importingFile, String uri) {
  const packagePrefix = 'package:viewer_flutter/src/';
  if (uri.startsWith(packagePrefix)) return uri.substring(packagePrefix.length);
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
  final parts = importingFile.split('/')..removeLast();
  for (final part in uri.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}
