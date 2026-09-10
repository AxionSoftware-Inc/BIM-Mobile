import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _sourceFile(String repositoryPath, String packagePath) {
  final repositoryFile = File(repositoryPath);
  return repositoryFile.existsSync() ? repositoryFile : File(packagePath);
}

void main() {
  test('native loader root path is facade-only', () {
    final source = _sourceFile(
      'apps/viewer_flutter/lib/src/native_engine_library_loader.dart',
      'lib/src/native_engine_library_loader.dart',
    ).readAsStringSync();

    expect(source, contains('COMPATIBILITY:'));
    expect(source, contains('REMOVE WHEN:'));
    expect(
      source,
      contains("export 'platform/native_engine/native_engine_library_loader.dart';"),
    );
    expect(source, isNot(contains('DynamicLibrary.open')));
  });

  test('canonical native loader imports the engine contract directly', () {
    final source = _sourceFile(
      'apps/viewer_flutter/lib/src/platform/native_engine/native_engine_library_loader.dart',
      'lib/src/platform/native_engine/native_engine_library_loader.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("../../core/application/engine/viewer_engine_contracts.dart"),
    );
    expect(source, isNot(contains("import '../../viewer_engine_contracts.dart'")));
  });

  test('workspace legacy paths are facade-only', () {
    final storeSource = _sourceFile(
      'apps/viewer_flutter/lib/src/view_workspace_store.dart',
      'lib/src/view_workspace_store.dart',
    ).readAsStringSync();
    final contextSource = _sourceFile(
      'apps/viewer_flutter/lib/src/workspace_view_runtime_context.dart',
      'lib/src/workspace_view_runtime_context.dart',
    ).readAsStringSync();

    for (final source in <String>[storeSource, contextSource]) {
      expect(source, contains('COMPATIBILITY:'));
      expect(source, contains('REMOVE WHEN:'));
      expect(source, isNot(contains('class ViewWorkspaceStore extends')));
      expect(source, isNot(contains('static String workspaceViewId')));
    }
  });
}
