part of 'widget_test.dart';

void registerEditorProjectionTests() {
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
    final wallMeshBefore = wallBefore.mesh.positions
        .map((point) => point.toJson())
        .toList(growable: false);
    expect(wallBefore.metadata['base_level_id'], isNotNull);

    final normalized = RenderSceneEditor.normalizeSceneGeometry(scene);
    final wallAfter = normalized.objectById(wallBefore.elementId)!;
    expect(wallAfter.metadata['base_level_id'],
        equals(wallBefore.metadata['base_level_id']));
    expect(wallAfter.metadata['top_level_id'], isNot(equals('0')));
    expect(wallAfter.metadata['height_mode'], equals('TopLevel'));
    // Engine-produced meshes are already joined and cut. Normalization may
    // enrich constraints but must never replace that authoritative topology.
    expect(
      wallAfter.mesh.positions.map((point) => point.toJson()).toList(),
      equals(wallMeshBefore),
    );
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

  test('opening offsets use the raw host-wall axis for diagonal walls', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final source = parseRenderSceneJson(
      json,
      source: 'test/fixtures/render_scene_sample.json',
    ).scene!;
    final scene = RenderSceneEditor.addWall(
      scene: source,
      start: const RenderScenePoint(x: 10, y: 0, z: 0),
      end: const RenderScenePoint(x: 14, y: 4, z: 0),
    );
    final wall = scene.objects.lastWhere((object) => object.kindKey == 'wall');
    final start = RenderSceneEditor.wallStartPoint(wall)!;
    final end = RenderSceneEditor.wallEndPoint(wall)!;
    final axis = end - start;
    final length = axis.distanceTo(RenderScenePoint.zero());
    final axisUnit = axis.scale(1 / length);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final expectedOffset = length * 0.30;
    // Deliberately offset the pointer away from the wall centreline. A door
    // still belongs at the closest point on its host axis, not at a globally
    // snapped X/Y grid point near a wall end.
    final pointer = start + axisUnit.scale(expectedOffset) + normal.scale(0.4);

    expect(
      RenderSceneEditor.wallOffsetMeters(wall, pointer),
      closeTo(expectedOffset, 1e-9),
    );
    final projected =
        RenderSceneEditor.projectModelPointToWallOffset(wall, pointer)!;
    final expectedPoint = start + axisUnit.scale(expectedOffset);
    expect(projected.x, closeTo(expectedPoint.x, 1e-9));
    expect(projected.y, closeTo(expectedPoint.y, 1e-9));
  });

  test('native string wall metadata preserves a reversed wall axis', () {
    final result = parseRenderSceneJson(
      '''
{
  "scene_version": 2,
  "units": "meters",
  "coordinate_system": "X/Y plan, Z up",
  "levels": [{"level_id": 1, "name": "Level 1", "elevation_meters": 0, "default_wall_height_meters": 3}],
  "objects": [{
    "element_id": 10,
    "kind": "Wall",
    "level_id": 1,
    "bounds": {"min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 8, "y": 0.2, "z": 3}},
    "mesh": {"positions": [], "indices": []},
    "metadata": {
      "start_x": "8.0",
      "start_y": "0.0",
      "end_x": "0.0",
      "end_y": "0.0",
      "thickness_meters": "0.2",
      "height_meters": "3.0"
    }
  }]
}
''',
      source: 'reversed native wall metadata',
    );
    expect(result.scene, isNotNull);
    final wall = result.scene!.objects.single;
    expect(RenderSceneEditor.wallStartPoint(wall)!.x, closeTo(8.0, 1e-9));
    expect(RenderSceneEditor.wallEndPoint(wall)!.x, closeTo(0.0, 1e-9));
    // A point at world x=2 is 6 m from the authoritative start at x=8.
    expect(
      RenderSceneEditor.wallOffsetMeters(
        wall,
        const RenderScenePoint(x: 2, y: 0, z: 0),
      ),
      closeTo(6.0, 1e-9),
    );
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

  test('fallback keeps one-level walls unconnected and rejects bad levels', () {
    final json =
        File('test/fixtures/render_scene_sample.json').readAsStringSync();
    final source = parseRenderSceneJson(json, source: 'one-level').scene!;
    final wallScene = RenderSceneEditor.addWall(
      scene: source,
      start: const RenderScenePoint(x: 12, y: 0, z: 0),
      end: const RenderScenePoint(x: 16, y: 0, z: 0),
    );
    final wall =
        wallScene.objects.lastWhere((object) => object.kindKey == 'wall');
    expect(wall.metadata['height_mode'], equals('Unconnected'));
    expect(wall.metadata['top_level_id'], isNull);

    final duplicate = RenderSceneEditor.createLevel(
      scene: source,
      name: 'Duplicate',
      elevationMeters: 0.0,
    );
    expect(duplicate.levels.length, equals(source.levels.length));

    final invalidMove = RenderSceneEditor.setLevelElevation(
      scene: source,
      levelId: source.levels.first.levelId,
      elevationMeters: double.nan,
    );
    expect(invalidMove.levels.first.elevationMeters,
        equals(source.levels.first.elevationMeters));
  });

  test(
      'legacy camelCase level ids are preserved and inferred levels do not overlap',
      () {
    final result = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'objects': <Object?>[
          <String, Object?>{
            'elementId': 1,
            'kind': 'Wall',
            'levelId': 10,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
              'max': <String, Object?>{'x': 2, 'y': 0.2, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[
                <String, Object?>{'x': 0, 'y': 0, 'z': 0},
                <String, Object?>{'x': 2, 'y': 0, 'z': 3},
              ],
              'indices': <int>[0, 1, 1],
            },
          },
          <String, Object?>{
            'elementId': 2,
            'kind': 'Wall',
            'levelId': 20,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
              'max': <String, Object?>{'x': 2, 'y': 0.2, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[
                <String, Object?>{'x': 0, 'y': 0, 'z': 0},
                <String, Object?>{'x': 2, 'y': 0, 'z': 3},
              ],
              'indices': <int>[0, 1, 1],
            },
          },
        ],
      }),
      source: 'legacy-camel-case',
    );
    expect(result.scene, isNotNull);
    expect(result.scene!.objects.map((object) => object.levelId),
        containsAll(<int?>[10, 20]));
    expect(
        result.scene!.levels
            .map((level) => level.elevationMeters)
            .toSet()
            .length,
        equals(result.scene!.levels.length));
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
    final probe = first.labelOrigin + const Offset(20, 10);
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

  test('3D orbit, pan and pinch zoom remain available after a plan switch',
      () async {
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );
    addTearDown(controller.dispose);

    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    final initial = controller.camera;
    controller.orbitBy(const Offset(90, -36), const Size(900, 600));
    controller.panOrbitBy(const Offset(48, 24), const Size(900, 600));
    controller.zoomOrbit(1.2);
    final moved = controller.camera;
    expect(moved.yawRadians, isNot(closeTo(initial.yawRadians, 1e-9)));
    expect(moved.center, isNot(initial.center));
    expect(moved.zoomScale, greaterThan(initial.zoomScale));

    await controller.setProjectionMode(RenderSceneProjectionMode.topDown);
    final planZoom = controller.planCamera.zoom;
    controller.zoomPlanBy(
      1.2,
      focalPoint: const Offset(450, 300),
      viewportSize: const Size(900, 600),
    );
    expect(controller.planCamera.zoom, greaterThan(planZoom));

    await controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    final restored = controller.camera;
    controller.orbitBy(const Offset(-48, 18), const Size(900, 600));
    expect(controller.camera.yawRadians,
        isNot(closeTo(restored.yawRadians, 1e-9)));
  });
}
