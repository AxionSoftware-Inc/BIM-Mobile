part of 'widget_test.dart';

void registerSceneGeometryTests() {
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

  test('Pick Walls and Auto Room resolve a closed wall loop', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'pick walls test',
    ).scene!;
    final walls = scene.objects
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);

    final polygon = RenderSceneEditor.surfacePolygonForWalls(walls);
    expect(polygon, isNotNull);
    expect(polygon!.length, greaterThanOrEqualTo(4));

    final detected = RenderSceneEditor.detectRooms(scene);
    final room = RenderSceneEditor.roomContainingPoint(
      detected,
      const RenderScenePoint(x: 3, y: 2, z: 0),
    );
    expect(room, isNotNull);
    expect(
      RenderSceneEditor.roomBoundaryWallIds(room!),
      containsAll(walls.map((wall) => wall.elementId)),
    );
  });

  test('ceiling Pick Walls follows the floor polygon and level height', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'ceiling pick walls test',
    ).scene!;
    final walls = scene.objects
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(walls);
    expect(polygon, isNotNull);

    final level = scene.levels.first;
    final ceiling = RenderSceneEditor.addCeilingFromPolygon(
      scene: scene,
      polygon: polygon!,
      levelId: level.levelId,
      heightMeters: 2.6,
    );
    final created = ceiling.objects.lastWhere(
      (object) => object.kindKey == 'ceiling',
    );
    expect(created.levelId, level.levelId);
    expect(
      created.bounds.min.z,
      closeTo(level.elevationMeters + 2.6 - 0.05, 1e-9),
    );
    expect(created.metadata['footprint_mode'], 'picked_wall_polygon');
  });

  test('Auto Room ignores an open wall boundary', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'open room test',
    ).scene!;
    final opened = RenderSceneEditor.deleteObject(
      scene: scene,
      target: scene.objectById(4)!,
    );
    final detected = RenderSceneEditor.detectRooms(opened);
    expect(
      RenderSceneEditor.roomContainingPoint(
        detected,
        const RenderScenePoint(x: 3, y: 2, z: 0),
      ),
      isNull,
    );
  });

  test('Auto Room keeps an L-shaped boundary instead of its bounding box', () {
    var scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'L room test',
    ).scene!;
    for (final wall in scene.objects
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false)) {
      scene = RenderSceneEditor.deleteObject(scene: scene, target: wall);
    }
    const points = <RenderScenePoint>[
      RenderScenePoint(x: 0, y: 0, z: 0),
      RenderScenePoint(x: 6, y: 0, z: 0),
      RenderScenePoint(x: 6, y: 3, z: 0),
      RenderScenePoint(x: 3, y: 3, z: 0),
      RenderScenePoint(x: 3, y: 6, z: 0),
      RenderScenePoint(x: 0, y: 6, z: 0),
    ];
    for (var index = 0; index < points.length; index += 1) {
      scene = RenderSceneEditor.addWall(
        scene: scene,
        start: points[index],
        end: points[(index + 1) % points.length],
        levelId: 1,
        topLevelId: 2,
      );
    }
    final detected = RenderSceneEditor.detectRooms(scene);
    final room = RenderSceneEditor.roomContainingPoint(
      detected,
      const RenderScenePoint(x: 1, y: 1, z: 0),
      levelId: 1,
    );
    expect(room, isNotNull);
    final polygon = RenderSceneEditor.roomBoundaryPolygon(detected, room!);
    expect(polygon, isNotNull);
    expect(polygon!.length, 6);
    expect(
        RenderSceneEditor.roomContainingPoint(
          detected,
          const RenderScenePoint(x: 5, y: 5, z: 0),
          levelId: 1,
        ),
        isNull);
  });

  test('wall move propagation is immediate and endpoint edits stay local', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'wall propagation test',
    ).scene!;
    final walls = scene.objects
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    final bottom = walls.firstWhere((wall) => wall.elementId == 2);
    final start = RenderSceneEditor.wallStartPoint(bottom)!;
    final end = RenderSceneEditor.wallEndPoint(bottom)!;
    const delta = RenderScenePoint(x: 0, y: 1, z: 0);

    final bodyUpdates = RenderSceneEditor.wallAxisUpdatesForJoin(
      scene: scene,
      wall: bottom,
      start: start + delta,
      end: end + delta,
    );
    expect(bodyUpdates.keys, containsAll(<int>[2, 3, 5]));
    expect(bodyUpdates.keys, isNot(contains(4)));
    expect(bodyUpdates.length, 3);

    final endpointUpdates = RenderSceneEditor.wallAxisUpdatesForJoin(
      scene: scene,
      wall: bottom,
      start: start,
      end: RenderScenePoint(x: end.x - 1, y: end.y, z: end.z),
    );
    expect(endpointUpdates.keys, <int>[2]);
  });

  test('rigid wall move carries a directly attached T endpoint only', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'T move propagation test',
    ).scene!;
    final withBranch = RenderSceneEditor.addWall(
      scene: scene,
      start: const RenderScenePoint(x: 3, y: 0, z: 0),
      end: const RenderScenePoint(x: 3, y: 2, z: 0),
      levelId: 1,
      topLevelId: 2,
    );
    final base = withBranch.objectById(2)!;
    final branch = withBranch.objects.lastWhere(
      (object) =>
          object.kindKey == 'wall' && object.elementId != base.elementId,
    );
    final start = RenderSceneEditor.wallStartPoint(base)!;
    final end = RenderSceneEditor.wallEndPoint(base)!;
    const delta = RenderScenePoint(x: 0, y: 1, z: 0);

    final updates = RenderSceneEditor.wallAxisUpdatesForJoin(
      scene: withBranch,
      wall: base,
      start: start + delta,
      end: end + delta,
    );

    final branchUpdate = updates[branch.elementId]!;
    expect(branchUpdate.start.x, closeTo(3, 1e-6));
    expect(branchUpdate.start.y, closeTo(1, 1e-6));
    expect(branchUpdate.end.x, closeTo(3, 1e-6));
    expect(branchUpdate.end.y, closeTo(2, 1e-6));
    expect(updates.containsKey(4), isFalse);
  });

  test('RenderScene parser reports invalid JSON cleanly', () {
    final result = parseRenderSceneJson(
      'this is not valid json',
      source: 'broken.json',
    );
    expect(result.scene, isNull);
    expect(result.errors, isNotEmpty);
  });

  test('Scene view service owns engine-backed navigation queries', () async {
    final gateway = _RecordingSceneGateway();
    final service = SceneViewService(
      repository: () => gateway,
      engineEnabled: () => true,
    );

    expect(await service.refresh(), same(_RecordingSceneGateway.result));
    await service.activateLevel(42);
    await service.setFullSceneRenderScope(true);

    expect(gateway.activeLevelId, 42);
    expect(gateway.fullSceneEnabled, isTrue);
  });

  test('section box and section view are mutually exclusive clip modes',
      () async {
    final controller = RenderSceneViewportController();
    const bounds = RenderSceneBounds(
      min: RenderScenePoint(x: -5, y: -5, z: -5),
      max: RenderScenePoint(x: 5, y: 5, z: 5),
    );
    const section = RenderSceneSection(
      name: 'Section A',
      start: RenderScenePoint(x: -6, y: 0, z: 0),
      end: RenderScenePoint(x: 6, y: 0, z: 0),
    );

    await controller.setSectionBox(bounds);
    expect(controller.hasSectionBox, isTrue);
    expect(controller.hasSectionView, isFalse);

    await controller.setSectionView(section);
    expect(controller.hasSectionBox, isFalse);
    expect(controller.hasSectionView, isTrue);

    await controller.setSectionView(null);
    expect(controller.hasSectionBox, isFalse);
    expect(controller.hasSectionView, isFalse);
    controller.dispose();
  });

  test('Project persistence service owns JSON checkpoints and replacement',
      () async {
    final gateway = _RecordingProjectGateway();
    final service = ProjectPersistenceService(
      repository: () => gateway,
      engineEnabled: () => true,
    );

    expect(await service.exportJson(), '{"schema_version": 1}');
    expect(
        (await service.saveToDefaultLocation()).path, '/tmp/example.tbe.json');
    await service.replaceFromJson(
      projectName: 'Layer edit',
      json: '{"materials": []}',
    );

    expect(gateway.receivedProjectName, 'Layer edit');
    expect(gateway.receivedJson, '{"materials": []}');
  });

  test('Project lifecycle service owns template session creation and reuse',
      () async {
    final createdSession = _RecordingProjectSession();
    final factory = _RecordingSessionFactory(createdSession);
    final service = ProjectLifecycleService<_RecordingProjectSession>(
      sessionFactory: factory,
    );

    final created = await service.createResidentialTemplate(
      buildingCount: 1,
      storyCount: 3,
    );
    final reused = await service.createResidentialTemplate(
      existingSession: createdSession,
      buildingCount: 6,
      storyCount: 9,
    );

    expect(created.session, same(createdSession));
    expect(created.createdSession, isTrue);
    expect(reused.createdSession, isFalse);
    expect(factory.createCount, 1);
    expect(createdSession.buildingCount, 6);
    expect(createdSession.storyCount, 9);
    expect(createdSession.disposed, isFalse);
  });

  test('Project session controller replaces and disposes native sessions', () {
    final first = _RecordingProjectSession();
    final second = _RecordingProjectSession();
    final controller = ProjectSessionController<_RecordingProjectSession>();

    controller.activate(first);
    controller.activate(first);
    controller.activate(second);

    expect(controller.session, same(second));
    expect(controller.isEngineBacked, isTrue);
    expect(first.disposed, isTrue);
    expect(second.disposed, isFalse);

    controller.dispose();
    expect(second.disposed, isTrue);
    expect(controller.session, isNull);
  });

  test('plan view range excludes the storey below at a shared level elevation',
      () {
    final result = parseRenderSceneJson(r'''{
      "scene_version": 1,
      "units": "meters",
      "coordinate_system": "X/Y plan, Z up",
      "levels": [
        {"level_id": 1, "name": "Level 1", "elevation_meters": 0},
        {"level_id": 2, "name": "Level 2", "elevation_meters": 3.2}
      ],
      "objects": [
        {"element_id": 11, "kind": "Wall", "level_id": 1, "bounds": {"min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 4, "y": 0.2, "z": 3.2}}, "mesh": {"positions": [], "indices": []}},
        {"element_id": 12, "kind": "Floor", "level_id": 1, "bounds": {"min": {"x": 0, "y": 0, "z": -0.15}, "max": {"x": 4, "y": 4, "z": 0}}, "mesh": {"positions": [], "indices": []}},
        {"element_id": 13, "kind": "Ceiling", "level_id": 1, "bounds": {"min": {"x": 0, "y": 0, "z": 2.7}, "max": {"x": 4, "y": 4, "z": 2.8}}, "mesh": {"positions": [], "indices": []}},
        {"element_id": 14, "kind": "Beam", "level_id": 1, "bounds": {"min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 4, "y": 0.3, "z": 0.4}}, "mesh": {"positions": [], "indices": []}},
        {"element_id": 21, "kind": "Wall", "level_id": 2, "bounds": {"min": {"x": 0, "y": 0, "z": 3.2}, "max": {"x": 4, "y": 0.2, "z": 6.4}}, "mesh": {"positions": [], "indices": []}}
      ]
    }''');
    final scene = result.scene!;

    final levelOne = scene.filteredByVerticalRange(
      activeLevelId: 1,
      bottomMeters: 0,
      topMeters: 2,
    );
    expect(levelOne.objects.map((object) => object.elementId),
        containsAll(<int>[11, 12]));
    expect(levelOne.objectById(13), isNull);
    expect(levelOne.objectById(14), isNull);
    expect(levelOne.objectById(21), isNull);

    final levelTwo = scene.filteredByVerticalRange(
      activeLevelId: 2,
      bottomMeters: 3.2,
      topMeters: 5.2,
    );
    expect(levelTwo.objectById(21), isNotNull);
    expect(levelTwo.objectById(11), isNull);
  });


}
