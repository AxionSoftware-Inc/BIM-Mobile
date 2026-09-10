import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opened view presentation has no runtime mutation', () {
    final root = _sourceRoot();
    final bar = File(
      '${root.path}/features/viewer/presentation/workspace/opened_view_tab_bar.dart',
    );
    final source = bar.readAsStringSync();
    expect(source, isNot(contains('AnnotationWorkspaceRuntime')));
    expect(source, isNot(contains('WorkspaceViewRuntimeContext')));
    expect(source, isNot(contains('_syncRuntimeViewContext')));
  });

  test('canonical view workspace store is Flutter neutral', () {
    final root = _sourceRoot();
    final directory = Directory(
      '${root.path}/features/viewer/application/workspace',
    );
    final violations = <String>[];
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('package:flutter/') ||
          source.contains('workspace_view_runtime_context.dart') ||
          source.contains('annotation_workspace_runtime.dart')) {
        violations.add(entity.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Canonical workspace application code must not depend on Flutter '
          'or legacy process-global runtime state.',
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
