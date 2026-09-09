import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recently migrated modules cannot depend on root compatibility facades',
      () {
    final sourceRoot = _sourceRoot();
    const canonicalByFacade = <String, String>{
      'bim_compact_instance_store.dart':
          'features/viewer/application/runtime/bim_compact_instance_store.dart',
      'bim_spatial_grid_index.dart':
          'features/viewer/application/runtime/bim_spatial_grid_index.dart',
      'bim_compact_estimator.dart':
          'features/schedules/application/bim_compact_estimator.dart',
      'quantity_schedule_service.dart':
          'features/schedules/application/quantity_schedule_service.dart',
      'quantity_schedule_dialog.dart':
          'features/schedules/presentation/quantity_schedule_workspace.dart',
      'scene_view_service.dart':
          'features/viewer/application/scene_view_service.dart',
      'selection_controller.dart':
          'features/viewer/presentation/selection_controller.dart',
      'inspector_controller.dart':
          'features/elements/presentation/inspector_controller.dart',
      'authoring_command_service.dart':
          'features/authoring/application/authoring_command_service.dart',
      'scene_mutation_service.dart':
          'features/authoring/application/scene_mutation_service.dart',
      'family_instance_adapter.dart':
          'features/families/application/family_instance_adapter.dart',
    };
    final directivePattern =
        RegExp(r"(?:import|export)\s+['\"]([^'\"]+)['\"]");
    final violations = <String>[];

    for (final file in _dartFiles(sourceRoot)) {
      final relativeFile = _relativeTo(sourceRoot, file).replaceAll('\\', '/');
      final migrated = relativeFile.startsWith('app/') ||
          relativeFile.startsWith('core/') ||
          relativeFile.startsWith('features/') ||
          relativeFile.startsWith('platform/');
      if (!migrated) continue;

      final text = file.readAsStringSync();
      for (final match in directivePattern.allMatches(text)) {
        final target = match.group(1)!.replaceAll('\\', '/');
        final basename = target.split('/').last;
        final canonical = canonicalByFacade[basename];
        if (canonical == null || target.contains(canonical)) continue;
        violations.add('$relativeFile -> $target');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'New architecture code must import canonical feature owners, '
          'never a legacy root facade.',
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
