import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy model import directory stays facade-only', () {
    final sourceRoot = _sourceRoot();
    final legacyDirectory = Directory('${sourceRoot.path}/model_import');
    final violations = <String>[];

    for (final entity in legacyDirectory.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      final nonEmptyLines = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      final hasImportDirective =
          RegExp(r'^\s*import\s+', multiLine: true).hasMatch(text);
      final isFacade = text.contains('COMPATIBILITY:') &&
          text.contains('REMOVE WHEN:') &&
          text.contains('export ') &&
          !hasImportDirective &&
          nonEmptyLines.length <= 6;
      if (!isFacade) violations.add(_basename(entity.path));
    }

    expect(
      violations,
      isEmpty,
      reason: 'Legacy lib/src/model_import is compatibility-only. Add model '
          'import contracts under features/projects/application/import and '
          'filesystem/cache adapters under features/projects/infrastructure/import.',
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

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
