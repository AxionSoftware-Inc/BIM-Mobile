import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical property editor does not import infrastructure adapters', () {
    final root = _sourceRoot();
    final propertyEditor = Directory(
      '${root.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}elements'
      '${Platform.pathSeparator}presentation'
      '${Platform.pathSeparator}property_editor',
    );
    final violations = <String>[];
    final directivePattern =
        RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');

    for (final entity in propertyEditor.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in directivePattern.allMatches(text)) {
        final target = match.group(1)!.replaceAll('\\', '/');
        if (target.contains('/infrastructure/')) {
          violations.add('${_relativeTo(root, entity)} -> $target');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Property editor presentation must consume application/domain '
          'contracts. Local files, bundled catalogs and other infrastructure '
          'belong behind injected ports.',
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

String _relativeTo(Directory root, File file) {
  final normalizedRoot = root.path.replaceAll('\\', '/');
  final normalizedFile = file.path.replaceAll('\\', '/');
  return normalizedFile.startsWith('$normalizedRoot/')
      ? normalizedFile.substring(normalizedRoot.length + 1)
      : normalizedFile;
}
