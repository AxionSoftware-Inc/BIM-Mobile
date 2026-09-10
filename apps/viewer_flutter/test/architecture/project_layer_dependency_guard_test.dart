import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Project application layer avoids infrastructure, presentation and legacy',
      () {
    final sourceRoot = _sourceRoot();
    final applicationRoot = Directory(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}projects'
      '${Platform.pathSeparator}application',
    );
    expect(applicationRoot.existsSync(), isTrue);

    final directivePattern =
        RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
    final violations = <String>[];

    for (final file in _dartFiles(applicationRoot)) {
      final source = file.readAsStringSync();
      final relativeFile = _relativeTo(sourceRoot, file).replaceAll('\\', '/');
      for (final match in directivePattern.allMatches(source)) {
        final target = _resolveImportTarget(
          relativeFile,
          match.group(1)!.replaceAll('\\', '/'),
        );
        if (target.contains('features/projects/infrastructure/') ||
            target.contains('features/projects/presentation/') ||
            target == 'viewer_project_lifecycle.dart' ||
            target == 'viewer_app.dart') {
          violations.add('$relativeFile -> $target');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Project application policy/use-cases must remain UI and IO free.',
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

String _resolveImportTarget(String importingFile, String target) {
  const packagePrefix = 'package:viewer_flutter/src/';
  if (target.startsWith(packagePrefix)) {
    return target.substring(packagePrefix.length);
  }
  if (target.startsWith('dart:') || target.startsWith('package:')) {
    return target;
  }

  final parts = <String>[];
  final importingDirectory = importingFile.split('/')..removeLast();
  for (final part in <String>[...importingDirectory, ...target.split('/')]) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}
