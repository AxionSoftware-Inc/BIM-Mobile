import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/elements/application/bim_element_registry.dart';
import 'package:viewer_flutter/src/features/elements/domain/bim_element_module.dart';
import 'package:viewer_flutter/src/features/project/application/project_companion_document.dart';

void main() {
  group('architecture guardrails', () {
    test('standard BIM element registry has unique canonical keys', () {
      expect(() => BimElementRegistry.standard.validate(), returnsNormally);
      expect(BimElementRegistry.standard.forKind('Wall')?.kindKey, 'wall');
      expect(BimElementRegistry.standard.forKind('w-a_l-l')?.kindKey, 'wall');
    });

    test('element registry rejects duplicate canonical keys and aliases', () {
      const registry = BimElementRegistry(<BimElementModule>[
        BimElementModule(
          kindKey: 'wall',
          displayName: 'Wall',
          typeFamily: BimElementTypeFamily.wall,
        ),
        BimElementModule(
          kindKey: 'w-all',
          displayName: 'Conflicting wall',
          typeFamily: BimElementTypeFamily.none,
        ),
      ]);

      expect(() => registry.validate(), throwsA(isA<StateError>()));
    });

    test('project companion registry rejects duplicate canonical keys', () {
      expect(
        () => ProjectCompanionDocuments(const <ProjectCompanionDocument>[
          _FakeCompanion('annotations'),
          _FakeCompanion('  ANNOTATIONS  '),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('viewer_app legacy part surface cannot grow', () {
      final sourceRoot = _sourceRoot();
      const allowedLegacyParts = <String>{
        'viewer_viewport_input.dart',
        'viewer_viewport_stair_editing.dart',
        'viewer_form_widgets.dart',
        'viewer_viewport_wall_editing.dart',
        'viewer_viewport_surface_editing.dart',
        'viewer_viewport_room_placement.dart',
        'viewer_inspector_draft_widgets.dart',
        'viewer_inspector_estimate_widgets.dart',
        'viewer_inspector_info_widgets.dart',
        'viewer_workspace_ui_layout.dart',
        'viewer_workspace_ui_interactions.dart',
        'viewer_start_screen.dart',
        'viewer_project_lifecycle.dart',
        'viewer_view_state.dart',
        'viewer_view_commands.dart',
        'viewer_authoring_state.dart',
      };

      final unexpected = <String>[];
      for (final file in _dartFiles(sourceRoot)) {
        final text = file.readAsStringSync();
        if (!text.contains("part of 'viewer_app.dart';")) continue;
        final name = _basename(file.path);
        if (!allowedLegacyParts.contains(name)) unexpected.add(name);
      }

      expect(
        unexpected,
        isEmpty,
        reason: 'Do not add another viewer_app part file. Create a typed '
            'domain/application/presentation module instead.',
      );
    });

    test('migrated domain modules stay platform and presentation neutral', () {
      final sourceRoot = _sourceRoot();
      final violations = <String>[];

      for (final file in _dartFiles(sourceRoot)) {
        final normalized = file.path.replaceAll('\\', '/');
        final isMigratedDomain =
            (normalized.contains('/features/') && normalized.contains('/domain/')) ||
                normalized.contains('/core/domain/');
        if (!isMigratedDomain) continue;

        final text = file.readAsStringSync();
        const forbidden = <String>[
          "import 'dart:io'",
          "import 'dart:ffi'",
          "package:flutter/",
          "package:file_selector/",
        ];
        for (final token in forbidden) {
          if (text.contains(token)) {
            violations.add('${_relativeTo(sourceRoot, file)} -> $token');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Domain code must not depend on Flutter, FFI or platform I/O.',
      );
    });

    test('new application modules stay platform-neutral by default', () {
      final sourceRoot = _sourceRoot();
      final violations = <String>[];
      const allowedDebt = <String, Set<String>>{
        'core/application/engine/viewer_project_gateway.dart': <String>{
          "import 'dart:io'",
        },
        'features/project/application/project_persistence_service.dart':
            <String>{"import 'dart:io'"},
        'features/annotations/application/annotation_document_controller.dart':
            <String>{"package:flutter/foundation.dart"},
        'features/annotations/application/annotation_workspace_runtime.dart':
            <String>{"package:flutter/foundation.dart"},
      };
      const forbidden = <String>[
        "import 'dart:io'",
        "import 'dart:ffi'",
        'package:flutter/',
        'package:file_selector/',
      ];

      for (final file in _dartFiles(sourceRoot)) {
        final relative = _relativeTo(sourceRoot, file).replaceAll('\\', '/');
        final isApplication = relative.startsWith('core/application/') ||
            (relative.startsWith('features/') &&
                relative.contains('/application/'));
        if (!isApplication) continue;

        final text = file.readAsStringSync();
        for (final token in forbidden) {
          if (!text.contains(token)) continue;
          final allowed = allowedDebt[relative] ?? const <String>{};
          if (allowed.any((entry) => token.contains(entry) || entry.contains(token))) {
            continue;
          }
          violations.add('$relative -> $token');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Application code coordinates use-cases. New Flutter, FFI and '
            'platform-I/O dependencies belong behind adapters/ports.',
      );
    });

    test('migrated modules cannot depend back on compatibility facades', () {
      final sourceRoot = _sourceRoot();
      final violations = <String>[];
      const canonicalByFacade = <String, String?>{
        'project_unit_settings.dart':
            'core/domain/units/project_unit_settings.dart',
        'async_serial_queue.dart':
            'core/application/concurrency/async_serial_queue.dart',
        'atomic_file_writer.dart':
            'core/infrastructure/io/atomic_file_writer.dart',
        'telemetry_service.dart':
            'core/infrastructure/telemetry/telemetry_service.dart',
        'app_project_storage.dart':
            'core/infrastructure/storage/app_project_storage.dart',
        'app_brand.dart': 'core/presentation/design_system/app_brand.dart',
        'app_settings.dart': null,
        'project_recovery_store.dart':
            'features/project/infrastructure/project_recovery_store.dart',
        'project_lifecycle_service.dart':
            'features/project/application/project_lifecycle_service.dart',
        'project_persistence_service.dart':
            'features/project/application/project_persistence_service.dart',
        'project_session_controller.dart':
            'features/project/application/project_session_controller.dart',
        'viewer_app_dependencies.dart':
            'app/composition/viewer_app_dependencies.dart',
        'native_viewer_session_factory.dart':
            'platform/native_engine/native_viewer_session_factory.dart',
        'viewer_engine_contracts.dart':
            'core/application/engine/viewer_engine_contracts.dart',
        'viewer_project_gateway.dart':
            'core/application/engine/viewer_project_gateway.dart',
        'viewer_scene_gateway.dart':
            'core/application/engine/viewer_scene_gateway.dart',
        'viewer_spatial_gateway.dart':
            'core/application/engine/viewer_spatial_gateway.dart',
        'viewer_element_creation_gateway.dart':
            'core/application/engine/viewer_element_creation_gateway.dart',
        'viewer_authoring_gateway.dart':
            'core/application/engine/viewer_authoring_gateway.dart',
        'viewer_project_session.dart':
            'core/application/engine/viewer_project_session.dart',
        'bim_element_module.dart':
            'features/elements/domain/bim_element_module.dart',
        'bim_element_registry.dart':
            'features/elements/application/bim_element_registry.dart',
        'inspector_registry.dart':
            'features/elements/presentation/bim_element_inspector_registry.dart',
        'wall_element_module.dart':
            'features/elements/domain/modules/wall_element_module.dart',
        'door_element_module.dart':
            'features/elements/domain/modules/door_element_module.dart',
        'window_element_module.dart':
            'features/elements/domain/modules/window_element_module.dart',
        'room_element_module.dart':
            'features/elements/domain/modules/room_element_module.dart',
        'floor_element_module.dart':
            'features/elements/domain/modules/floor_element_module.dart',
        'ceiling_element_module.dart':
            'features/elements/domain/modules/ceiling_element_module.dart',
        'roof_element_module.dart':
            'features/elements/domain/modules/roof_element_module.dart',
        'slab_element_module.dart':
            'features/elements/domain/modules/slab_element_module.dart',
        'column_element_module.dart':
            'features/elements/domain/modules/column_element_module.dart',
        'beam_element_module.dart':
            'features/elements/domain/modules/beam_element_module.dart',
        'stair_element_module.dart':
            'features/elements/domain/modules/stair_element_module.dart',
        'level_element_module.dart':
            'features/elements/domain/modules/level_element_module.dart',
        'proxy_element_module.dart':
            'features/elements/domain/modules/proxy_element_module.dart',
        'annotation_store.dart':
            'features/annotations/domain/annotation_store.dart',
        'annotation_view_key.dart':
            'features/annotations/domain/annotation_view_key.dart',
        'annotation_store_codec.dart':
            'features/annotations/infrastructure/annotation_store_codec.dart',
        'annotation_sidecar_store.dart':
            'features/annotations/infrastructure/annotation_sidecar_store.dart',
        'annotation_store_editor.dart':
            'features/annotations/application/annotation_store_editor.dart',
        'annotation_document_controller.dart':
            'features/annotations/application/annotation_document_controller.dart',
        'annotation_workspace_runtime.dart':
            'features/annotations/application/annotation_workspace_runtime.dart',
      };
      final directivePattern =
          RegExp(r"(?:import|export)\s+['\"]([^'\"]+)['\"]");

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
          if (!canonicalByFacade.containsKey(basename)) continue;
          final canonical = canonicalByFacade[basename];
          if (canonical != null && target.contains(canonical)) continue;
          violations.add('$relativeFile -> $target');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Migrated modules must depend on canonical owners, never back '
            'through root compatibility facades.',
      );
    });

    test('temporary compatibility facades carry an explicit removal condition',
        () {
      final sourceRoot = _sourceRoot();
      final violations = <String>[];
      for (final file in _dartFiles(sourceRoot)) {
        final text = file.readAsStringSync();
        if (text.contains('COMPATIBILITY:') && !text.contains('REMOVE WHEN:')) {
          violations.add(_relativeTo(sourceRoot, file));
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Every COMPATIBILITY facade needs a named removal condition.',
      );
    });
  });
}

final class _FakeCompanion implements ProjectCompanionDocument {
  const _FakeCompanion(this.key);

  @override
  final String key;

  @override
  Future<void> resetForNewProject() async {}

  @override
  Future<void> restoreForProjectPath(String? projectPath) async {}

  @override
  Future<void> saveForProjectPath(String projectPath) async {}
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

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

String _relativeTo(Directory root, File file) {
  final normalizedRoot = root.path.replaceAll('\\', '/');
  final normalizedFile = file.path.replaceAll('\\', '/');
  if (normalizedFile.startsWith('$normalizedRoot/')) {
    return normalizedFile.substring(normalizedRoot.length + 1);
  }
  return normalizedFile;
}
