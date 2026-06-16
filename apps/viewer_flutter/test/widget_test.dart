import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_repository.dart';
import 'package:viewer_flutter/src/viewer_app.dart';

void main() {
  test('RenderScene parser loads the bundled sample and keeps finite bounds',
      () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(json,
        source: 'test/fixtures/render_scene_sample.json');
    expect(result.scene, isNotNull);
    expect(result.errors, isEmpty);

    final scene = result.scene!;
    expect(scene.objectCount, 6);
    expect(scene.kindCounts['wall'], 4);
    expect(scene.kindCounts['door'], 1);
    expect(scene.kindCounts['window'], 1);
    expect(scene.vertexCount, greaterThan(0));
    expect(scene.triangleCount, greaterThan(0));
    expect(scene.bounds.isFinite, isTrue);
    for (final object in scene.objects) {
      expect(object.bounds.isFinite, isTrue);
    }
  });

  test('RenderScene parser reports invalid JSON cleanly', () {
    final result = parseRenderSceneJson(
      'this is not valid json',
      source: 'broken.json',
    );
    expect(result.scene, isNull);
    expect(result.errors, isNotEmpty);
  });

  test('RenderScene editor can add wall, door, and window locally', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final scene = result.scene!;
    final wallAdded = RenderSceneEditor.addWall(
      scene: scene,
      start: const RenderScenePoint(x: 10, y: 0, z: 0),
      end: const RenderScenePoint(x: 14, y: 0, z: 0),
    );
    expect(wallAdded.objectCount, greaterThan(scene.objectCount));
    expect(wallAdded.kindCounts['wall'],
        greaterThan(scene.kindCounts['wall'] ?? 0));

    final hostWall = scene.objectById(2);
    expect(hostWall, isNotNull);

    final doorAdded = RenderSceneEditor.addDoor(
      scene: scene,
      hostWall: hostWall!,
      offsetMeters: 1.2,
    );
    expect(doorAdded.kindCounts['door'],
        greaterThan(scene.kindCounts['door'] ?? 0));

    final windowAdded = RenderSceneEditor.addWindow(
      scene: scene,
      hostWall: hostWall,
      offsetMeters: 2.0,
    );
    expect(windowAdded.kindCounts['window'],
        greaterThan(scene.kindCounts['window'] ?? 0));
  });

  testWidgets('Viewer loads the bundled scene and shows diagnostics',
      (WidgetTester tester) async {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    await tester.pumpWidget(
      ViewerApp(
        source: MemoryRenderSceneSource(
          json,
          source: 'test/fixtures/render_scene_sample.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BIM Viewer'), findsOneWidget);
    expect(find.textContaining('Objects: 6'), findsWidgets);
    expect(find.textContaining('Walls: 4'), findsWidgets);
  });
}
