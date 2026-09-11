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
          'features/schedules/presentation/quantity_schedule_dialog.dart',
      'scene_view_service.dart':
          'features/viewer/application/scene_view_service.dart',
      'selection_controller.dart':
          'features/viewer/presentation/selection_controller.dart',
      'viewport_interaction.dart':
          'features/viewer/presentation/viewport/viewport_interaction.dart',
      'viewport_gesture_controller.dart':
          'features/viewer/presentation/viewport/viewport_gesture_controller.dart',
      'render_scene_viewport_types.dart':
          'features/viewer/presentation/viewport/render_scene_viewport_types.dart',
      'render_scene_viewport_planar.dart':
          'features/viewer/presentation/viewport/render_scene_viewport_planar.dart',
      'render_scene_viewport_projection.dart':
          'features/viewer/presentation/viewport/render_scene_viewport_projection.dart',
      'workspace_chrome.dart':
          'features/viewer/presentation/workspace/workspace_chrome.dart',
      'workspace_view_runtime_context.dart':
          'app/workspace/workspace_view_runtime_context.dart',
      'view_workspace_store.dart':
          'app/workspace/view_workspace_store_adapter.dart',
      'native_engine_library_loader.dart':
          'platform/native_engine/native_engine_library_loader.dart',
      'inspector_controller.dart':
          'features/elements/presentation/inspector_controller.dart',
      'material_layer_editor.dart':
          'features/elements/presentation/material_layer_editor.dart',
      'authoring_command_service.dart':
          'features/authoring/application/authoring_command_service.dart',
      'scene_mutation_service.dart':
          'features/authoring/application/scene_mutation_service.dart',
      'family_instance_adapter.dart':
          'features/families/application/family_instance_adapter.dart',
      'family_dependency_resolver.dart':
          'features/families/application/dependencies/family_dependency_resolver.dart',
      'family_render_scene_adapter.dart':
          'features/families/application/integration/family_render_scene_adapter.dart',
      'family_authoring_scene_builder.dart':
          'features/families/application/integration/family_authoring_scene_builder.dart',
      'family_parameter_authoring.dart':
          'features/families/application/authoring/family_parameter_authoring.dart',
      'family_constraint_models.dart':
          'features/families/domain/constraints/family_constraint_models.dart',
      'family_document.dart':
          'features/families/domain/document/family_document.dart',
      'family_parameter_resolver.dart':
          'features/families/domain/parameters/family_parameter_resolver.dart',
      'family_constraint_solver.dart':
          'features/families/domain/constraints/family_constraint_solver.dart',
      'family_validation.dart':
          'features/families/domain/validation/family_validation.dart',
      'family_geometry.dart':
          'features/families/domain/geometry/family_geometry.dart',
      'family_library_metadata.dart':
          'features/families/application/library/family_library_metadata.dart',
      'family_bundled_catalog.dart':
          'features/families/infrastructure/catalog/family_bundled_catalog.dart',
      'built_in_family_catalog.dart':
          'features/families/infrastructure/catalog/built_in_family_catalog.dart',
      'family_file_store.dart':
          'features/families/infrastructure/library/family_file_store.dart',
      'family_parameters_panel.dart':
          'features/families/presentation/panels/family_parameters_panel.dart',
      'family_type_matrix_panel.dart':
          'features/families/presentation/panels/family_type_matrix_panel.dart',
      'family_constraints_geometry_panel.dart':
          'features/families/presentation/panels/family_constraints_geometry_panel.dart',
      'family_constraints_panel.dart':
          'features/families/presentation/panels/family_constraints_panel.dart',
      'family_sketch_viewport.dart':
          'features/families/presentation/sketch/family_sketch_viewport.dart',
      'family_sketch_canvas.dart':
          'features/families/presentation/sketch/family_sketch_canvas.dart',
      'family_authoring_viewport.dart':
          'features/families/presentation/viewport/family_authoring_viewport.dart',
      'family_import_units_dialog.dart':
          'features/families/presentation/dialogs/family_import_units_dialog.dart',
      'start_screen_template_store.dart':
          'features/projects/infrastructure/templates/start_screen_template_store.dart',
      'project_browser_views.dart':
          'features/projects/presentation/browser/project_browser_views.dart',
      'project_browser_panel.dart':
          'features/projects/presentation/browser/project_browser_panel.dart',
      'onboarding_page.dart': 'app/routing/onboarding_page.dart',
      'annotation_render_batches.dart':
          'features/annotations/application/annotation_render_batches.dart',
      'annotation_history_controls.dart':
          'features/annotations/presentation/annotation_history_controls.dart',
      'annotation_selection_controls.dart':
          'features/annotations/presentation/annotation_selection_controls.dart',
      'annotation_viewport_overlay.dart':
          'features/annotations/presentation/annotation_viewport_overlay.dart',
      'annotation_hit_test.dart':
          'features/annotations/presentation/annotation_hit_test.dart',
      'view_navigation_coordinator.dart':
          'features/viewer/application/navigation/view_navigation_coordinator.dart',
      'document_models.dart':
          'features/documentation/application/document_models.dart',
      'sheet_workspace_controller.dart':
          'features/documentation/presentation/sheet_workspace_controller.dart',
      'sheet_canvas.dart':
          'features/documentation/presentation/sheet_canvas.dart',
      'documentation_workspace.dart':
          'features/documentation/presentation/documentation_workspace.dart',
      'document_pdf_service.dart':
          'features/documentation/presentation/export/document_pdf_service.dart',
    };
    final directivePattern =
        RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
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
        final target = _resolveImportTarget(
          relativeFile,
          match.group(1)!.replaceAll('\\', '/'),
        );
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
