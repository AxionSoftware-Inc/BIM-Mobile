part of 'widget_test.dart';

void registerSceneGeometryTests() {
  test('viewport rejects an incompatible coordinate contract before rendering',
      () async {
    final parsed = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 3,
        'units': 'millimeters',
        'coordinate_system': 'X/Z plan, Y up',
        'objects': const <Object?>[],
      }),
      source: 'incompatible coordinate contract',
    );

    expect(parsed.scene, isNotNull);
    expect(parsed.errors, hasLength(3));
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );
    addTearDown(controller.dispose);
    await expectLater(
      controller.loadRenderScene(parsed.scene!),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('render-scene v2 preserves engine-authored opening feature edges', () {
    final result = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 2,
        'objects': <Object?>[
          <String, Object?>{
            'element_id': 7,
            'kind': 'Wall',
            'mesh': <String, Object?>{
              'positions': <Object?>[
                <String, Object?>{'x': 0, 'y': 0, 'z': 0},
                <String, Object?>{'x': 4, 'y': 0, 'z': 0},
                <String, Object?>{'x': 0, 'y': 0, 'z': 3},
              ],
              'indices': <int>[0, 1, 2],
            },
            'feature_edges': <Object?>[
              <String, Object?>{
                'role': 'opening_contour',
                'start': <String, Object?>{'x': 1, 'y': -0.1, 'z': 0.9},
                'end': <String, Object?>{'x': 2.2, 'y': -0.1, 'z': 0.9},
              },
            ],
          },
        ],
      }),
      source: 'feature-edge contract test',
    );

    expect(result.errors, isEmpty);
    final wall = result.scene!.objects.single;
    expect(wall.featureEdges, hasLength(1));
    expect(wall.featureEdges.single.role, 'opening_contour');
    expect(wall.featureEdges.single.start.x, 1);
    expect(wall.featureEdges.single.end.x, 2.2);
  });

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

  test('fallback keeps curved walls semantic and cuts curved openings',
      () async {
    final base = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'curved fallback test',
    ).scene!;
    const geometry = WallArcGeometry(
      center: RenderScenePoint(x: 4, y: 4, z: 0),
      start: RenderScenePoint(x: 4, y: 0, z: 0),
      end: RenderScenePoint(x: 8, y: 4, z: 0),
      radiusMeters: 4,
      sweepRadians: math.pi / 2,
      points: <RenderScenePoint>[],
    );
    final created = await const SceneMutationService().createCurvedWall(
      CreateCurvedWallRequest(
        scene: base,
        geometry: geometry,
        baseLevelId: 1,
        topLevelId: 2,
        heightMeters: 3,
        thicknessMeters: 0.3,
      ),
    );
    expect(created.success, isTrue);
    final curved = created.scene!.objectById(created.createdElementId)!;
    expect(curved.kindKey, 'wall');
    expect(
      RenderSceneEditor.wallCenterlinePoints(curved).length,
      greaterThan(3),
    );
    final opened = RenderSceneEditor.addWindow(
      scene: created.scene!,
      hostWall: curved,
      offsetMeters: 3.0,
      widthMeters: 1.0,
      heightMeters: 1.2,
      sillHeightMeters: 0.9,
      levelId: 1,
    );
    final rebuiltWall = opened.objectById(curved.elementId)!;
    final opening = opened.objects.lastWhere(
      (object) => object.kindKey == 'window',
    );
    expect(rebuiltWall.mesh.indices.length, greaterThan(0));
    expect(opening.metadata['host_wall_id'], curved.elementId);
    expect(rebuiltWall.featureEdges, isNotEmpty);
  });

  test('floor and ceiling profiles follow a semantic curved wall', () async {
    var scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'curved surface profile test',
    ).scene!;
    const geometry = WallArcGeometry(
      center: RenderScenePoint(x: 0, y: 0, z: 0),
      start: RenderScenePoint(x: 5, y: 0, z: 0),
      end: RenderScenePoint(x: 0, y: 5, z: 0),
      radiusMeters: 5,
      sweepRadians: math.pi / 2,
      points: <RenderScenePoint>[],
    );
    final curvedResult = await const SceneMutationService().createCurvedWall(
      CreateCurvedWallRequest(
        scene: scene,
        geometry: geometry,
        baseLevelId: 1,
        topLevelId: 2,
        heightMeters: 3,
        thicknessMeters: 0.2,
      ),
    );
    expect(curvedResult.success, isTrue);
    scene = curvedResult.scene!;
    final wallIds = <int>[curvedResult.createdElementId!];
    const straightEdges = <({RenderScenePoint start, RenderScenePoint end})>[
      (
        start: RenderScenePoint(x: 0, y: 5, z: 0),
        end: RenderScenePoint(x: 0, y: 8, z: 0),
      ),
      (
        start: RenderScenePoint(x: 0, y: 8, z: 0),
        end: RenderScenePoint(x: 5, y: 8, z: 0),
      ),
      (
        start: RenderScenePoint(x: 5, y: 8, z: 0),
        end: RenderScenePoint(x: 5, y: 0, z: 0),
      ),
    ];
    for (final edge in straightEdges) {
      scene = RenderSceneEditor.addWall(
        scene: scene,
        start: edge.start,
        end: edge.end,
        levelId: 1,
        topLevelId: 2,
      );
      wallIds.add(
        scene.objects
            .lastWhere((object) => object.kindKey == 'wall')
            .elementId!,
      );
    }
    final walls = wallIds
        .map(scene.objectById)
        .whereType<RenderSceneObject>()
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(walls);
    expect(polygon, isNotNull);
    expect(
      polygon!.any(
        (point) =>
            point.distanceTo(
              const RenderScenePoint(x: 3.5355339, y: 3.5355339, z: 0),
            ) <
            0.2,
      ),
      isTrue,
    );

    final floor = RenderSceneEditor.addFloorFromWalls(
      scene: scene,
      walls: walls,
      levelId: 1,
    );
    final ceiling = RenderSceneEditor.addCeilingFromWalls(
      scene: floor,
      walls: walls,
      levelId: 1,
    );
    for (final kind in <String>['floor', 'ceiling']) {
      final object = ceiling.objects.lastWhere((item) => item.kindKey == kind);
      final points = (object.metadata['footprint_points'] as List)
          .map(RenderScenePoint.fromJson)
          .whereType<RenderScenePoint>();
      expect(
        points.any(
          (point) =>
              point.distanceTo(
                const RenderScenePoint(x: 3.5355339, y: 3.5355339, z: 0),
              ) <
              0.2,
        ),
        isTrue,
      );
    }
  });

  test('fallback roof accepts a freeform footprint and preserves roof settings',
      () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'freeform roof test',
    ).scene!;
    final roof = RenderSceneEditor.addRoofFromPolygon(
      scene: scene,
      polygon: const <RenderScenePoint>[
        RenderScenePoint(x: 0, y: 0, z: 0),
        RenderScenePoint(x: 6, y: 0, z: 0),
        RenderScenePoint(x: 6, y: 2, z: 0),
        RenderScenePoint(x: 3, y: 4, z: 0),
        RenderScenePoint(x: 0, y: 2, z: 0),
      ],
      levelId: 1,
      roofType: 1,
      slopeDegrees: 30,
      overhangMeters: 0.25,
    );
    final created =
        roof.objects.lastWhere((object) => object.kindKey == 'roof');
    expect(created.mesh.indices, isNotEmpty);
    expect(created.metadata['roof_type'], 1);
    expect(created.metadata['slope_degrees'], 30);
    expect(created.metadata['overhang_meters'], 0.25);
    expect(created.metadata['footprint_points'], hasLength(5));
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

  test('RenderScene parser rejects payloads above the memory geometry guard',
      () {
    final result = parseRenderSceneJson(
      '{"objects": [], "index_count": ${kMaxRenderSceneIndices + 1}}',
      source: 'oversized.json',
    );
    expect(result.scene, isNull);
    expect(result.errors.single, contains('memory guard'));
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
