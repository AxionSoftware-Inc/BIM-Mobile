import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Family application layer does not depend on UI, infrastructure or legacy',
      () {
    final sourceRoot = _sourceRoot();
    final applicationRoot = Directory(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}families'
      '${Platform.pathSeparator}application',
    );
    expect(applicationRoot.existsSync(), isTrue);

    final violations = _dependencyViolations(
      sourceRoot: sourceRoot,
      layerRoot: applicationRoot,
      isForbidden: (target) =>
          target.contains('features/families/infrastructure/') ||
          target.contains('features/families/presentation/') ||
          target.contains('family_authoring/'),
    );

    expect(
      violations,
      isEmpty,
      reason: 'Family application services may depend on domain and ports only.',
    );
  });

  test('Family presentation layer does not depend on infrastructure or legacy',
      () {
    final sourceRoot = _sourceRoot();
    final presentationRoot = Directory(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}families'
      '${Platform.pathSeparator}presentation',
    );
    expect(presentationRoot.existsSync(), isTrue);

    final violations = _dependencyViolations(
      sourceRoot: sourceRoot,
      layerRoot: presentationRoot,
      isForbidden: (target) =>
          target.contains('features/families/infrastructure/') ||
          target.contains('family_authoring/'),
    );

    expect(
      violations,
      isEmpty,
      reason: 'Family presentation must consume application/domain contracts; '
          'storage, bundled catalogs and legacy authoring stay outside UI.',
    );
  });
}

List<String> _dependencyViolations({
  required Directory sourceRoot,
  required Directory layerRoot,
  required bool Function(String target) isForbidden,
}) {
  final directivePattern =
      RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
  final violations = <String>[];

  for (final file in _dartFiles(layerRoot)) {
    final source = file.readAsStringSync();
    final relativeFile = _relativeTo(sourceRoot, file).replaceAll('\\', '/');
    for (final match in directivePattern.allMatches(source)) {
      final raw = match.group(1)!.replaceAll('\\', '/');
      final target = _resolveImportTarget(relativeFile, raw);
      if (isForbidden(target)) violations.add('$relativeFile -> $target');
    }
  }
  return violations;
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
