import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace consumes composition-owned persistence and scene services', () {
    final sourceRoot = _sourceRoot();
    final app = File('${sourceRoot.path}${Platform.pathSeparator}viewer_app.dart')
        .readAsStringSync();

    expect(
      app,
      contains('_projectPersistence = _dependencies.projectPersistence;'),
      reason: 'The workspace must reuse the companion-aware persistence stack '
          'assembled by ViewerAppDependencies.',
    );
    expect(
      app,
      contains('_sceneViews = _dependencies.createSceneViewService();'),
      reason: 'Scene gateway/session resolution belongs to the composition root.',
    );
    expect(
      app,
      isNot(contains('_projectPersistence = ProjectPersistenceService(')),
      reason: 'Presentation code must not create a parallel persistence stack.',
    );
    expect(
      app,
      isNot(contains('_sceneViews = SceneViewService(')),
      reason: 'Presentation code must not coordinate scene repository callbacks.',
    );
  });

  test('legacy RenderScene source path stays a thin compatibility facade', () {
    final sourceRoot = _sourceRoot();
    final facade = File(
      '${sourceRoot.path}${Platform.pathSeparator}render_scene_repository.dart',
    ).readAsStringSync();
    final canonical = File(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}viewer${Platform.pathSeparator}infrastructure'
      '${Platform.pathSeparator}render_scene_source.dart',
    ).readAsStringSync();

    expect(
      facade,
      contains("export 'features/viewer/infrastructure/render_scene_source.dart';"),
    );
    expect(facade, isNot(contains("import 'dart:io';")));
    expect(facade, isNot(contains('rootBundle')));
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
