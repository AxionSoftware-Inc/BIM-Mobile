import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_estimator.dart';
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
    expect(scene.levels, isNotEmpty);
    expect(scene.levels.first.name, contains('Level'));
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

  test('RenderScene editor can create and filter levels', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final leveled = RenderSceneEditor.createLevel(
      scene: result.scene!,
      name: 'Level 2',
      elevationMeters: 3.2,
      defaultWallHeightMeters: 3.0,
    );
    expect(leveled.levels.length, greaterThan(result.scene!.levels.length));

    final level2 = leveled.levels.firstWhere((level) => level.name == 'Level 2');
    final wallOnLevel2 = RenderSceneEditor.addWall(
      scene: leveled,
      start: const RenderScenePoint(x: 20, y: 0, z: 3.2),
      end: const RenderScenePoint(x: 24, y: 0, z: 3.2),
      levelId: level2.levelId,
      heightMeters: 3.0,
    );

    final filtered = wallOnLevel2.filteredByLevel(level2.levelId);
    expect(filtered.objects.every((object) => object.levelId == level2.levelId), isTrue);
    expect(filtered.kindCounts['wall'], greaterThan(0));
  });

  test('RenderScene estimator responds to custom unit prices', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final summaryDefault = RenderSceneEstimator.summarize(result.scene!);
    final summaryCustom = RenderSceneEstimator.summarize(
      result.scene!,
      catalog: const RenderSceneEstimateCatalog(
        brickUnitCost: 1.0,
        concreteCostPerCubicMeter: 200.0,
        floorFinishCostPerSquareMeter: 30.0,
        ceilingCostPerSquareMeter: 25.0,
        doorUnitCost: 500.0,
        windowUnitCost: 700.0,
      ),
    );

    expect(summaryCustom.totalCost, greaterThan(summaryDefault.totalCost));
    expect(summaryCustom.lineItems.length, 6);
  });

  testWidgets('Viewer loads the bundled scene and shows diagnostics',
      (WidgetTester tester) async {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      ViewerApp(
        source: MemoryRenderSceneSource(
          json,
          source: 'test/fixtures/render_scene_sample.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tablet BIM'), findsOneWidget);
    expect(find.text('2D'), findsOneWidget);
    expect(find.text('3D'), findsOneWidget);
  });
}
