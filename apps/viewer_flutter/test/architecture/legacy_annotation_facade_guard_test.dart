import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy annotations directory stays facade-only', () {
    final sourceRoot = _sourceRoot();
    final legacyDirectory = Directory('${sourceRoot.path}/annotations');
    if (!legacyDirectory.existsSync()) return;
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
      if (!isFacade) {
        violations.add(_basename(entity.path));
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Legacy lib/src/annotations is compatibility-only. Add new '
          'annotation behavior under features/annotations and leave only a '
          'thin export facade here while migration callers remain.',
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
