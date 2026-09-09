import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/elements/bim_element_module.dart';
import 'package:viewer_flutter/src/elements/bim_element_registry.dart';

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
        final isMigratedDomain = normalized.contains('/features/') &&
                normalized.contains('/domain/') ||
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

String _basename(String path) =>
    path.replaceAll('\\', '/').split('/').last;

String _relativeTo(Directory root, File file) {
  final normalizedRoot = root.path.replaceAll('\\', '/');
  final normalizedFile = file.path.replaceAll('\\', '/');
  if (normalizedFile.startsWith('$normalizedRoot/')) {
    return normalizedFile.substring(normalizedRoot.length + 1);
  }
  return normalizedFile;
}
