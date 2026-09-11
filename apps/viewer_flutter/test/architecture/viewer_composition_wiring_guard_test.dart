import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace consumes composition-owned persistence and scene services',
      () {
    final sourceRoot = _sourceRoot();
    final app = StringBuffer()
      ..write(
        File('${sourceRoot.path}${Platform.pathSeparator}viewer_app.dart')
            .readAsStringSync(),
      )
      ..write(
        File(
          '${sourceRoot.path}${Platform.pathSeparator}features'
          '${Platform.pathSeparator}viewer${Platform.pathSeparator}presentation'
          '${Platform.pathSeparator}workspace${Platform.pathSeparator}'
          'viewer_home_page_state.dart',
        ).readAsStringSync(),
      );

    expect(
      app.toString(),
      contains('_projectPersistence = _dependencies.projectPersistence;'),
      reason: 'The workspace must reuse the companion-aware persistence stack '
          'assembled by ViewerAppDependencies.',
    );
    expect(
      app.toString(),
      contains('_sceneViews = _dependencies.createSceneViewService();'),
      reason:
          'Scene gateway/session resolution belongs to the composition root.',
    );
    expect(
      app.toString(),
      isNot(contains('_projectPersistence = ProjectPersistenceService(')),
      reason: 'Presentation code must not create a parallel persistence stack.',
    );
    expect(
      app.toString(),
      isNot(contains('_sceneViews = SceneViewService(')),
      reason:
          'Presentation code must not coordinate scene repository callbacks.',
    );
  });

  test('start gate consumes composition-owned adapters', () {
    final sourceRoot = _sourceRoot();
    final start = File(
      '${sourceRoot.path}${Platform.pathSeparator}viewer_start_screen.dart',
    ).readAsStringSync();

    expect(start, contains('final ViewerStartDependencies dependencies;'));
    expect(
        start, contains('_recoveryRepository = widget.dependencies.recovery;'));
    expect(
        start, contains('_projectPicker = widget.dependencies.projectPicker;'));
    expect(
      start,
      contains(
        'templatePreferencesRepository: widget.dependencies.templatePreferences',
      ),
    );
    expect(start, isNot(contains('FileStartScreenRecoveryRepository(')));
    expect(start, isNot(contains('FileProjectOpenDocumentPicker(')));
    expect(
      start,
      isNot(contains('FileStartScreenTemplatePreferencesRepository(')),
    );
  });

  test('legacy RenderScene source path stays a thin compatibility facade', () {
    final sourceRoot = _sourceRoot();
    final facade = File(
      '${sourceRoot.path}${Platform.pathSeparator}render_scene_repository.dart',
    );
    final canonical = File(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}viewer${Platform.pathSeparator}infrastructure'
      '${Platform.pathSeparator}render_scene_source.dart',
    ).readAsStringSync();

    expect(facade.existsSync(), isFalse);
    expect(canonical, contains('abstract interface class RenderSceneSource'));
    expect(canonical, contains('final class AssetRenderSceneSource'));
  });
}

Directory _sourceRoot() {
  final packageLocal = Directory('lib/src');
  if (packageLocal.existsSync()) return packageLocal.absolute;

  final repositoryLocal = Directory('apps/viewer_flutter/lib/src');
  if (repositoryLocal.existsSync()) return repositoryLocal.absolute;

  throw StateError('Could not locate apps/viewer_flutter/lib/src.');
}
