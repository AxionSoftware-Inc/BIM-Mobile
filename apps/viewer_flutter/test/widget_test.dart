import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_estimator.dart';
import 'package:viewer_flutter/src/render_scene_level_overlay.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_repository.dart';
import 'package:viewer_flutter/src/scene_mutation_service.dart';
import 'package:viewer_flutter/src/render_scene_viewport_controller.dart';
import 'package:viewer_flutter/src/render_scene_viewport_planar.dart';
import 'package:viewer_flutter/src/render_scene_viewport_projection.dart';
import 'package:viewer_flutter/src/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/tbe_ffi.dart';
import 'package:viewer_flutter/src/tools/level_tool_controller.dart';
import 'package:viewer_flutter/src/tools/opening_tool_controller.dart';
import 'package:viewer_flutter/src/tools/surface_tool_controller.dart';
import 'package:viewer_flutter/src/tools/wall_tool_controller.dart';
import 'package:viewer_flutter/src/viewer_app.dart';
import 'package:viewer_flutter/src/viewport_interaction.dart';

void main() {
  test('RenderScene parser loads the bundled sample and keeps finite bounds',
      () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(json,
        source: 'test/fixtures/render_scene_sample.json');
    expect(result.scene, isNotNull);
    expect(result.errors, isEmpty);

    final scene = RenderSceneEditor.createLevel(
      scene: result.scene!,
      name: 'Level 2',
      elevationMeters: 3.2,
    );
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

  test('native engine returns RenderScene without package export', () async {
    final api = TbeViewerApi.load();
    final repository = ViewerRepository(api);
    addTearDown(repository.dispose);
    final projectJson = File('assets/sample_project.json').readAsStringSync();
    await repository.loadFromJson(
      projectName: 'FFI direct scene',
      json: projectJson,
    );
    final result = await repository.currentRenderScene();
    expect(result.errors, isEmpty);
    expect(result.scene, isNotNull);
    expect(result.scene!.objects, isNotEmpty);
  });

  test('level move updates a wall constrained to that level', () async {
    final api = TbeViewerApi.load();
    final repository = ViewerRepository(api);
    addTearDown(repository.dispose);
    final projectJson = File('assets/sample_project.json').readAsStringSync();
    await repository.loadFromJson(
        projectName: 'Level constraints', json: projectJson);

    final created = await repository.createWall(
      name: 'Constrained test wall',
      levelId: 1,
      start: const RenderScenePoint(x: 12, y: 0, z: 0),
      end: const RenderScenePoint(x: 16, y: 0, z: 0),
      thicknessMeters: 0.2,
      heightMeters: 3.0,
    );
    final wallId = repository.lastCreatedElementId;
    expect(wallId, isNotNull);
    await repository.setWallLevelConstraints(
      wallId: wallId!,
      baseLevelId: 1,
      topLevelId: 2,
      heightMode: 1,
    );
    final before = (await repository.currentRenderScene()).scene!;
    final beforeWall = before.objectById(wallId)!;

    await repository.moveLevelElevation(levelId: 2, elevationMeters: 4.5);
    final after = (await repository.currentRenderScene()).scene!;
    final afterWall = after.objectById(wallId)!;
    expect(afterWall.bounds.max.z, greaterThan(beforeWall.bounds.max.z));
    expect(created.scene, isNotNull);
  });

  test('Android vertical slice survives engine save and reload', () async {
    final api = TbeViewerApi.load();
    final repository = ViewerRepository(api);
    addTearDown(repository.dispose);
    final projectJson = File('assets/sample_project.json').readAsStringSync();
    await repository.loadFromJson(
      projectName: 'Android vertical slice',
      json: projectJson,
    );

    await repository.createWall(
      name: 'Tablet wall',
      levelId: 1,
      start: const RenderScenePoint(x: 12, y: 0, z: 0),
      end: const RenderScenePoint(x: 16, y: 0, z: 0),
      thicknessMeters: 0.2,
      heightMeters: 3,
    );
    final wallId = repository.lastCreatedElementId;
    expect(wallId, isNotNull);
    await repository.setWallLevelConstraints(
      wallId: wallId!,
      baseLevelId: 1,
      topLevelId: 2,
      heightMode: 1,
    );
    await repository.createDoor(
      name: 'Tablet door',
      hostWallId: wallId,
      offsetMeters: 0.8,
      widthMeters: 0.9,
      heightMeters: 2.1,
    );
    await repository.createWindow(
      name: 'Tablet window',
      hostWallId: wallId,
      offsetMeters: 2.4,
      widthMeters: 1.0,
      heightMeters: 1.2,
      sillHeightMeters: 0.9,
    );
    await repository.moveLevelElevation(levelId: 2, elevationMeters: 3.8);

    final savedJson = await repository.saveProjectJson();
    expect(savedJson, contains('Tablet wall'));
    expect(savedJson, contains('Tablet door'));
    expect(savedJson, contains('Tablet window'));
    final savedFile = await repository.saveProjectToDefaultLocation();
    addTearDown(() async {
      if (await savedFile.exists()) {
        await savedFile.delete();
      }
    });
    expect(await savedFile.readAsString(), contains('Tablet wall'));
    await repository.reloadCurrent();

    final restored = ViewerRepository(api);
    addTearDown(restored.dispose);
    await restored.loadFromJson(
      projectName: 'Restored Android vertical slice',
      json: savedJson,
    );
    final reloaded = (await restored.currentRenderScene()).scene!;
    final wall = reloaded.objectById(wallId)!;
    expect(reloaded.kindCounts['wall'], 11);
    expect(reloaded.kindCounts['door'], 2);
    expect(reloaded.kindCounts['window'], 3);
    expect(wall.metadata['base_level_id'], '1');
    expect(wall.metadata['top_level_id'], '2');
    expect(wall.metadata['height_mode'], 'TopLevel');
    expect(reloaded.levelById(2)!.elevationMeters, closeTo(3.8, 1e-9));
  });

  test('wall mutation transaction returns a constrained wall in its snapshot',
      () async {
    final api = TbeViewerApi.load();
    final repository = ViewerRepository(api);
    addTearDown(repository.dispose);
    await repository.loadFromJson(
      projectName: 'Wall transaction',
      json: File('assets/sample_project.json').readAsStringSync(),
    );
    final before = (await repository.currentRenderScene()).scene!;
    final outcome =
        await SceneMutationService(engineRepository: repository).createWall(
      CreateWallRequest(
        scene: before,
        start: const RenderScenePoint(x: 12, y: 1, z: 0),
        end: const RenderScenePoint(x: 16, y: 1, z: 0),
        baseLevelId: 1,
        topLevelId: 2,
        thicknessMeters: 0.2,
        heightMeters: 3.0,
      ),
    );
    expect(outcome.success, isTrue, reason: outcome.error);
    expect(outcome.createdElementId, isNotNull);
    expect(outcome.scene, isNotNull);
    expect(outcome.scene!.kindCounts['wall'],
        greaterThan(before.kindCounts['wall'] ?? 0));
    final wall = outcome.scene!.objectById(outcome.createdElementId)!;
    expect(wall.metadata['base_level_id']?.toString(), equals('1'));
    expect(wall.metadata['top_level_id']?.toString(), equals('2'));
  });

  test('Bundled render scene retains wall level metadata', () {
    final json = File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);
    final wall =
        result.scene!.objects.firstWhere((object) => object.kindKey == 'wall');
    expect(wall.metadata['base_level_id'], isNotNull);
    expect(wall.metadata['top_level_id'], isNotNull);
    expect(wall.metadata['height_mode'], isNotNull);
  });

  test('normalizeSceneGeometry upgrades legacy walls to level constraints', () {
    final json = File('assets/render_scene.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'assets/render_scene.json',
    );
    expect(result.scene, isNotNull);
    final scene = result.scene!;
    final wallBefore =
        scene.objects.firstWhere((object) => object.kindKey == 'wall');
    expect(wallBefore.metadata['base_level_id'], isNotNull);

    final normalized = RenderSceneEditor.normalizeSceneGeometry(scene);
    final wallAfter = normalized.objectById(wallBefore.elementId)!;
    expect(wallAfter.metadata['base_level_id'],
        equals(wallBefore.metadata['base_level_id']));
    expect(wallAfter.metadata['top_level_id'], isNot(equals('0')));
    expect(wallAfter.metadata['height_mode'], equals('TopLevel'));
  });

  test('RenderScene editor can add wall, door, and window locally', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final scene = RenderSceneEditor.createLevel(
      scene: result.scene!,
      name: 'Level 2',
      elevationMeters: 3.2,
    );
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

    final level2 =
        leveled.levels.firstWhere((level) => level.name == 'Level 2');
    final withTopLevel = RenderSceneEditor.createLevel(
      scene: leveled,
      name: 'Level 3',
      elevationMeters: 6.4,
    );
    final wallOnLevel2 = RenderSceneEditor.addWall(
      scene: withTopLevel,
      start: const RenderScenePoint(x: 20, y: 0, z: 3.2),
      end: const RenderScenePoint(x: 24, y: 0, z: 3.2),
      levelId: level2.levelId,
      heightMeters: 3.0,
    );

    final filtered = wallOnLevel2.filteredByLevel(level2.levelId);
    expect(filtered.objects.every((object) => object.levelId == level2.levelId),
        isTrue);
    expect(filtered.kindCounts['wall'], greaterThan(0));
  });

  test('Level elevation moves locked wall and leaves unlocked wall in place',
      () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final result = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    );
    expect(result.scene, isNotNull);

    final baseScene = result.scene!;
    final wall =
        baseScene.objects.firstWhere((object) => object.kindKey == 'wall');
    final door =
        baseScene.objects.firstWhere((object) => object.kindKey == 'door');
    final startBefore = RenderSceneEditor.wallStartPoint(wall)!;
    final doorBaseBefore = door.bounds.min.z;

    final movedScene = RenderSceneEditor.setLevelElevation(
      scene: baseScene,
      levelId: wall.levelId ?? 1,
      elevationMeters: 1.5,
    );
    final movedWall = movedScene.objectById(wall.elementId)!;
    final startAfter = RenderSceneEditor.wallStartPoint(movedWall)!;
    expect(startAfter.z, closeTo(startBefore.z + 1.5, 1e-6));
    final movedDoor = movedScene.objectById(door.elementId)!;
    expect(movedDoor.bounds.min.z, closeTo(doorBaseBefore + 1.5, 1e-6));

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

    final tapPoint = projection
        .project(const RenderScenePoint(x: 0.0, y: 0.05, z: 1.5))
        .screen;
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

  test('North/South/East/West are true planar re-projections of the same model',
      () {
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
    final east = projectionFor(RenderSceneProjectionMode.eastElevation)
        .project(point)
        .screen;
    final west = projectionFor(RenderSceneProjectionMode.westElevation)
        .project(point)
        .screen;

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

  test('Revit-style selection controller clears, toggles and windows objects',
      () {
    final interaction = ViewportInteractionController();
    const initial = ViewportSelectionState(selectedElementIds: <String>{'1'});
    interaction.begin(
      position: const Offset(10, 10),
      elementId: '2',
      modifiers: const ViewportSelectionModifiers(additive: true),
      allowObjectDrag: true,
    );
    expect(interaction.resolveClick(current: initial, elementId: '2'),
        <String>{'1', '2'});

    interaction.begin(
      position: const Offset(10, 10),
      elementId: null,
      modifiers: const ViewportSelectionModifiers(),
      allowObjectDrag: true,
    );
    expect(
        interaction.resolveClick(current: initial, elementId: null), isEmpty);
    interaction.update(const Offset(100, 100));
    expect(
      interaction.resolveRectangle(
        current: initial,
        rect: const Rect.fromLTWH(10, 10, 90, 90),
        candidates: const <MapEntry<String, Rect>>[
          MapEntry<String, Rect>('inside', Rect.fromLTWH(20, 20, 20, 20)),
          MapEntry<String, Rect>('crossing', Rect.fromLTWH(90, 90, 30, 30)),
        ],
      ),
      <String>{'inside'},
    );

    interaction.begin(
      position: const Offset(100, 10),
      elementId: null,
      modifiers: const ViewportSelectionModifiers(),
      allowObjectDrag: true,
    );
    interaction.update(const Offset(10, 100));
    expect(
      interaction.resolveRectangle(
        current: initial,
        rect: const Rect.fromLTWH(10, 10, 90, 90),
        candidates: const <MapEntry<String, Rect>>[
          MapEntry<String, Rect>('inside', Rect.fromLTWH(20, 20, 20, 20)),
          MapEntry<String, Rect>('crossing', Rect.fromLTWH(90, 90, 30, 30)),
        ],
      ),
      <String>{'inside', 'crossing'},
    );
  });

  test('touch selection window requires a hold before it starts', () {
    final interaction = ViewportInteractionController();
    interaction.begin(
      position: const Offset(10, 10),
      elementId: null,
      modifiers: const ViewportSelectionModifiers(),
      allowObjectDrag: true,
      requireRectangleArm: true,
    );
    expect(interaction.intent, ViewportDragIntent.idle);
    expect(interaction.update(const Offset(100, 100)), isNull);

    interaction.armRectangleSelect();
    expect(interaction.intent, ViewportDragIntent.rectangleSelect);
    expect(interaction.update(const Offset(100, 100)), isNotNull);
  });

  test('wall tool controller chains each committed endpoint', () {
    final tool = WallToolController();
    addTearDown(tool.dispose);
    const a = RenderScenePoint(x: 0, y: 0, z: 0);
    const b = RenderScenePoint(x: 4, y: 0, z: 0);
    const c = RenderScenePoint(x: 4, y: 3, z: 0);

    tool.begin(a);
    tool.preview(b);
    expect(tool.hasSegment, isTrue);
    expect(tool.start, a);
    expect(tool.end, b);

    tool.continueFrom(b);
    expect(tool.hasSegment, isFalse);
    tool.preview(c);
    expect(tool.hasSegment, isTrue);
    expect(tool.start, b);
    expect(tool.end, c);
  });

  test('level tool controller keeps elevation draft separate from wall tool',
      () {
    final tool = LevelToolController();
    addTearDown(tool.dispose);
    const start = RenderScenePoint(x: 0, y: 0, z: 3.2);
    const end = RenderScenePoint(x: 6, y: 0, z: 3.2);
    tool.begin(start);
    tool.preview(end);
    expect(tool.hasDraft, isTrue);
    expect(tool.start, start);
    expect(tool.end, end);
    tool.reset();
    expect(tool.hasDraft, isFalse);
  });

  test('opening tool controller owns hosted-opening dimensions', () {
    final tool = OpeningToolController();
    addTearDown(tool.dispose);
    tool.loadFromMetadata(const <String, Object?>{
      'offset_meters': '1.25',
      'width_meters': 1.1,
      'height_meters': '2.2',
      'sill_height_meters': 0.85,
    });
    expect(tool.offsetMeters, closeTo(1.25, 1e-9));
    expect(tool.widthMeters, closeTo(1.1, 1e-9));
    expect(tool.heightMeters, closeTo(2.2, 1e-9));
    expect(tool.sillHeightMeters, closeTo(0.85, 1e-9));
    tool.reset();
    expect(tool.offsetMeters, closeTo(1.0, 1e-9));
  });

  test('surface tool controller resets a level-bound surface draft', () {
    final tool = SurfaceToolController();
    addTearDown(tool.dispose);
    const start = RenderScenePoint(x: 1, y: 2, z: 3);
    const end = RenderScenePoint(x: 5, y: 6, z: 3);
    tool
      ..start = start
      ..end = end
      ..points.addAll(const <RenderScenePoint>[start, end])
      ..wallIds.addAll(const <int>[10, 11])
      ..drawMode = RenderSceneSurfaceDrawMode.pickWalls
      ..thicknessMeters = 0.24;

    tool.reset(levelElevation: 4.2, defaultHeight: 3.6);

    expect(tool.start, isNull);
    expect(tool.end, isNull);
    expect(tool.points, isEmpty);
    expect(tool.wallIds, isEmpty);
    expect(tool.drawMode, RenderSceneSurfaceDrawMode.rectangle);
    expect(tool.floorTopMeters, closeTo(4.2, 1e-9));
    expect(tool.heightMeters, closeTo(3.6, 1e-9));
  });

  test('Switching from elevation to 3D preserves directional meaning',
      () async {
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );

    await controller
        .setProjectionMode(RenderSceneProjectionMode.northElevation);
    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    expect(
      controller.camera.yawRadians,
      closeTo(
          RenderSceneProjectionMode.northElevation.spec.orbitYawRadians!, 1e-9),
    );

    await controller.setProjectionMode(RenderSceneProjectionMode.westElevation);
    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    expect(
      controller.camera.yawRadians,
      closeTo(
          RenderSceneProjectionMode.westElevation.spec.orbitYawRadians!, 1e-9),
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
    final json = File('assets/render_scene.json').readAsStringSync();
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
