import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_estimator.dart';
import 'package:viewer_flutter/src/render_scene_level_overlay.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_repository.dart';
import 'package:viewer_flutter/src/render_scene_viewport_controller.dart';
import 'package:viewer_flutter/src/render_scene_viewport_planar.dart';
import 'package:viewer_flutter/src/render_scene_viewport_projection.dart';
import 'package:viewer_flutter/src/render_scene_viewport_types.dart';
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

  test('Bundled render scene retains wall level metadata', () {
    final json =
        File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);
    final wall = result.scene!.objects.firstWhere((object) => object.kindKey == 'wall');
    expect(wall.metadata['base_level_id'], isNotNull);
    expect(wall.metadata['top_level_id'], isNotNull);
    expect(wall.metadata['height_mode'], isNotNull);
  });

  test('normalizeSceneGeometry preserves wall level constraint metadata', () {
    final json = File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);
    final scene = result.scene!;
    final wallBefore = scene.objects.firstWhere((object) => object.kindKey == 'wall');
    expect(wallBefore.metadata['base_level_id'], isNotNull);

    final normalized = RenderSceneEditor.normalizeSceneGeometry(scene);
    final wallAfter = normalized.objectById(wallBefore.elementId)!;
    expect(wallAfter.metadata['base_level_id'], equals(wallBefore.metadata['base_level_id']));
    expect(wallAfter.metadata['top_level_id'], equals(wallBefore.metadata['top_level_id']));
    expect(wallAfter.metadata['height_mode'], equals(wallBefore.metadata['height_mode']));
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

  test('Level elevation moves locked wall and leaves unlocked wall in place', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final baseScene = result.scene!;
    final wall = baseScene.objects.firstWhere((object) => object.kindKey == 'wall');
    final startBefore = RenderSceneEditor.wallStartPoint(wall)!;

    final movedScene = RenderSceneEditor.setLevelElevation(
      scene: baseScene,
      levelId: wall.levelId ?? 1,
      elevationMeters: 1.5,
    );
    final movedWall = movedScene.objectById(wall.elementId)!;
    final startAfter = RenderSceneEditor.wallStartPoint(movedWall)!;
    expect(startAfter.z, closeTo(startBefore.z + 1.5, 1e-6));

    final unlockedScene = RenderSceneEditor.setElementLevelLock(
      scene: movedScene,
      object: movedWall,
      locked: false,
    );
    final unchangedScene = RenderSceneEditor.setLevelElevation(
      scene: unlockedScene,
      levelId: wall.levelId ?? 1,
      elevationMeters: 3.0,
    );
    final unchangedWall = unchangedScene.objectById(wall.elementId)!;
    final startUnlocked = RenderSceneEditor.wallStartPoint(unchangedWall)!;
    expect(startUnlocked.z, closeTo(startAfter.z, 1e-6));
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

  test('RenderScene estimator accepts numeric metadata stored as strings', () {
    final json = File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);

    final summary = RenderSceneEstimator.summarize(result.scene!);
    expect(summary.wallCount, greaterThan(0));
    expect(summary.totalCost.isFinite, isTrue);
    expect(summary.wallGrossVolume, greaterThan(0));
  });

  test('Cardinal elevation specs are driven by one projection registry', () {
    expect(kRenderSceneProjectionSpecs.length, 6);

    final north = RenderSceneProjectionMode.northElevation.spec;
    final south = RenderSceneProjectionMode.southElevation.spec;
    final east = RenderSceneProjectionMode.eastElevation.spec;
    final west = RenderSceneProjectionMode.westElevation.spec;
    final plan = RenderSceneProjectionMode.topDown.spec;

    expect(plan.isPlanar, isTrue);
    expect(plan.isElevation, isFalse);
    expect(plan.showGrid, isTrue);
    expect(plan.showAxes, isTrue);
    expect(plan.showLevelsOverlay, isFalse);
    expect(plan.useProjectedBoundsOutline, isFalse);
    expect(north.isElevation, isTrue);
    expect(south.isElevation, isTrue);
    expect(east.isElevation, isTrue);
    expect(west.isElevation, isTrue);
    expect(north.showLevelsOverlay, isTrue);
    expect(east.useBoundsCenterLabelAnchor, isTrue);
    expect(north.useProjectedBoundsOutline, isTrue);

    expect(north.planarDescriptor!.horizontalAxis, RenderSceneAxis.x);
    expect(north.planarDescriptor!.verticalAxis, RenderSceneAxis.z);
    expect(north.planarDescriptor!.depthAxis, RenderSceneAxis.y);

    expect(south.planarDescriptor!.horizontalAxis, RenderSceneAxis.x);
    expect(south.planarDescriptor!.verticalAxis, RenderSceneAxis.z);
    expect(south.planarDescriptor!.depthAxis, RenderSceneAxis.y);
    expect(south.planarDescriptor!.horizontalSign, -1.0);

    expect(east.planarDescriptor!.horizontalAxis, RenderSceneAxis.y);
    expect(east.planarDescriptor!.verticalAxis, RenderSceneAxis.z);
    expect(east.planarDescriptor!.depthAxis, RenderSceneAxis.x);

    expect(west.planarDescriptor!.horizontalAxis, RenderSceneAxis.y);
    expect(west.planarDescriptor!.verticalAxis, RenderSceneAxis.z);
    expect(west.planarDescriptor!.depthAxis, RenderSceneAxis.x);
    expect(west.planarDescriptor!.horizontalSign, -1.0);

    expect(north.orbitYawRadians, closeTo(-3.141592653589793 / 2, 1e-9));
    expect(south.orbitYawRadians, closeTo(3.141592653589793 / 2, 1e-9));
    expect(east.orbitYawRadians, closeTo(3.141592653589793, 1e-9));
    expect(west.orbitYawRadians, closeTo(0, 1e-9));

    expect(north.viewDirection, const RenderScenePoint(x: 0, y: -1, z: 0));
    expect(south.viewDirection, const RenderScenePoint(x: 0, y: 1, z: 0));
    expect(east.viewDirection, const RenderScenePoint(x: -1, y: 0, z: 0));
    expect(west.viewDirection, const RenderScenePoint(x: 1, y: 0, z: 0));
  });

  test('Level overlays use the same geometry for draw and hit-test', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final scene = result.scene!;
    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: const Size(1280, 720),
      projectionMode: RenderSceneProjectionMode.northElevation,
      orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
      planCamera: const RenderScenePlanCameraState(
        center: RenderScenePoint(x: 0, y: 0, z: 0),
        zoom: 80,
      ),
      camera: const RenderSceneCameraState(
        center: RenderScenePoint(x: 0, y: 0, z: 0),
        distance: 20,
        yawRadians: 0.0,
        pitchRadians: 0.0,
        zoomScale: 1.0,
      ),
      padding: 48,
    );

    final overlays = buildLevelOverlayEntries(
      scene: scene,
      projectionMode: RenderSceneProjectionMode.northElevation,
      projection: projection,
    );
    expect(overlays, isNotEmpty);

    final first = overlays.first;
    final probe = Offset(
      (first.lineStart.dx + first.lineEnd.dx) * 0.5,
      first.lineStart.dy + 2,
    );
    final picked = pickLevelOverlayAt(
      scene: scene,
      projectionMode: RenderSceneProjectionMode.northElevation,
      projection: projection,
      localPosition: probe,
    );
    expect(picked, isNotNull);
    expect(picked!.levelId, first.level.levelId);
  });

  test('Top-down picking prefers wall over slab-style area objects', () {
    final json = File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);
    final scene = result.scene!;

    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: const Size(1280, 720),
      projectionMode: RenderSceneProjectionMode.topDown,
      orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
      planCamera: const RenderScenePlanCameraState(
        center: RenderScenePoint(x: 4, y: 5, z: 0),
        zoom: 60,
      ),
      camera: const RenderSceneCameraState(
        center: RenderScenePoint(x: 0, y: 0, z: 0),
        distance: 20,
        yawRadians: 0.0,
        pitchRadians: 0.0,
        zoomScale: 1.0,
      ),
      padding: 48,
    );

    final tapPoint =
        projection.project(const RenderScenePoint(x: 0.0, y: 0.05, z: 1.5)).screen;
    final picked = pickObjectAt(
      scene: scene,
      size: const Size(1280, 720),
      localPosition: tapPoint,
      projectionMode: RenderSceneProjectionMode.topDown,
      orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
      planCamera: const RenderScenePlanCameraState(
        center: RenderScenePoint(x: 4, y: 5, z: 0),
        zoom: 60,
      ),
      camera: const RenderSceneCameraState(
        center: RenderScenePoint(x: 0, y: 0, z: 0),
        distance: 20,
        yawRadians: 0.0,
        pitchRadians: 0.0,
        zoomScale: 1.0,
      ),
      visibleKinds: <String>{},
      padding: 48,
    );
    expect(picked, isNotNull);
    expect(picked!.kindKey, 'wall');
  });

  test('North/South/East/West are true planar re-projections of the same model', () {
    const bounds = RenderSceneBounds(
      min: RenderScenePoint(x: 0, y: 0, z: 0),
      max: RenderScenePoint(x: 10, y: 20, z: 6),
    );
    const planCamera = RenderScenePlanCameraState(
      center: RenderScenePoint(x: 5, y: 10, z: 3),
      zoom: 10,
    );
    const orbitCamera = RenderSceneCameraState(
      center: RenderScenePoint(x: 5, y: 10, z: 3),
      distance: 20,
      yawRadians: 0.7,
      pitchRadians: 0.5,
      zoomScale: 1.0,
    );
    const point = RenderScenePoint(x: 7, y: 14, z: 5);
    const size = Size(800, 600);

    RenderSceneProjection projectionFor(RenderSceneProjectionMode mode) {
      return RenderSceneProjection(
        sceneBounds: bounds,
        canvasSize: size,
        projectionMode: mode,
        orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
        planCamera: planCamera,
        camera: orbitCamera,
        padding: 48,
      );
    }

    final north = projectionFor(RenderSceneProjectionMode.northElevation)
        .project(point)
        .screen;
    final south = projectionFor(RenderSceneProjectionMode.southElevation)
        .project(point)
        .screen;
    final east =
        projectionFor(RenderSceneProjectionMode.eastElevation).project(point).screen;
    final west =
        projectionFor(RenderSceneProjectionMode.westElevation).project(point).screen;

    // Same vertical axis for all elevation views: higher Z must move up equally.
    expect(north.dy, closeTo(south.dy, 1e-6));
    expect(east.dy, closeTo(west.dy, 1e-6));

    // Opposite cardinal views mirror horizontally around the same center.
    expect((north.dx + south.dx) * 0.5, closeTo(size.width * 0.5, 1e-6));
    expect((east.dx + west.dx) * 0.5, closeTo(size.width * 0.5, 1e-6));

    // North/South are driven by X/Z, East/West by Y/Z.
    expect(north.dx, closeTo(size.width * 0.5 + 20, 1e-6));
    expect(south.dx, closeTo(size.width * 0.5 - 20, 1e-6));
    expect(east.dx, closeTo(size.width * 0.5 + 40, 1e-6));
    expect(west.dx, closeTo(size.width * 0.5 - 40, 1e-6));
  });

  test('Interaction mode fallback uses shared projection defaults', () async {
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );

    await controller.setProjectionMode(RenderSceneProjectionMode.westElevation);
    await controller.setInteractionMode(RenderSceneInteractionMode.moveWall);
    expect(controller.projectionMode, kDefaultPlanProjectionMode);

    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    await controller.setInteractionMode(RenderSceneInteractionMode.addLevel);
    expect(controller.projectionMode, RenderSceneProjectionMode.isometric);

    await controller.setProjectionMode(RenderSceneProjectionMode.eastElevation);
    controller.panPlanBy(const Offset(30, -20));
    expect(controller.planCamera.center.x, 0);
    expect(controller.planCamera.center.y, closeTo(-30, 1e-6));
    expect(controller.planCamera.center.z, closeTo(-20, 1e-6));
  });

  test('Switching from elevation to 3D preserves directional meaning', () async {
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );

    await controller.setProjectionMode(RenderSceneProjectionMode.northElevation);
    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    expect(
      controller.camera.yawRadians,
      closeTo(RenderSceneProjectionMode.northElevation.spec.orbitYawRadians!, 1e-9),
    );

    await controller.setProjectionMode(RenderSceneProjectionMode.westElevation);
    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    expect(
      controller.camera.yawRadians,
      closeTo(RenderSceneProjectionMode.westElevation.spec.orbitYawRadians!, 1e-9),
    );
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
        preferEngineBackedBundledSample: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tablet BIM'), findsOneWidget);
    expect(find.text('2D'), findsOneWidget);
    expect(find.text('3D'), findsOneWidget);
  });

  testWidgets('Selecting a wall shows inline wall level controls',
      (WidgetTester tester) async {
    final json =
        File('assets/render_scene.json').readAsStringSync();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      ViewerApp(
        source: MemoryRenderSceneSource(
          json,
          source: 'assets/render_scene.json',
        ),
        preferEngineBackedBundledSample: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show object list').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wall #11'));
    await tester.pumpAndSettle();

    expect(find.text('Wall levels'), findsWidgets);
    expect(find.text('Apply wall levels'), findsOneWidget);
    expect(find.text('Base level'), findsWidgets);
    expect(find.text('Top level'), findsWidgets);
  });
}
