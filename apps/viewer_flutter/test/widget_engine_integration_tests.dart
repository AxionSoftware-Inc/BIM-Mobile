part of 'widget_test.dart';

void registerEngineIntegrationTests() {
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

  test('global engine history is exposed through the project session',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    final blank =
        await repository.createBlankProject(projectName: 'History test');
    final levelId = blank.scene!.levels.first.levelId;
    final before = await repository.historyCounts();
    final created = await repository.createWall(
      name: 'Undo wall',
      levelId: levelId,
      start: const RenderScenePoint(x: 0, y: 0, z: 0),
      end: const RenderScenePoint(x: 4, y: 0, z: 0),
      thicknessMeters: 0.2,
      heightMeters: 3.2,
    );
    expect((await repository.historyCounts()).undoCount,
        greaterThan(before.undoCount));
    expect(created.scene!.kindCounts['wall'], greaterThanOrEqualTo(1));

    final undone = await repository.undo();
    expect(undone.scene!.kindCounts['wall'] ?? 0, 0);
    expect((await repository.historyCounts()).redoCount, greaterThan(0));

    final redone = await repository.redo();
    expect(redone.scene!.kindCounts['wall'], greaterThanOrEqualTo(1));
  });

  test('engine residential tower template is level-bound and reload-safe',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);

    final result = await repository.createResidentialTemplate(
      buildingCount: 1,
      storyCount: 9,
    );
    final scene = result.scene!;
    expect(result.errors, isEmpty);
    expect(scene.levels, hasLength(10));
    expect(scene.kindCounts['wall'], greaterThanOrEqualTo(10));
    final topLevelScene =
        (await repository.setActiveLevel(scene.levels.last.levelId)).scene!;
    expect(topLevelScene.kindCounts['roof'], 1);

    final saved = await repository.saveProjectJson();
    expect(saved, contains('9 Storey Residential Tower'));
    expect(saved, contains('source_wall_ids'));
    await repository.reloadCurrent();
    expect((await repository.currentRenderScene()).scene, isNotNull);
  });

  test('engine residential template exposes and applies wall types safely',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);

    final result = await repository.createResidentialTemplate(
      buildingCount: 1,
      storyCount: 3,
    );
    final initial = result.scene!;
    expect(
        initial.wallTypes.map((type) => type.name),
        containsAll(<String>[
          'Exterior Wall',
          'Interior Wall',
          'Basic Wall',
          'Exterior Glass Wall',
          'Interior Glass Partition',
          'Concrete Core Wall',
        ]));
    expect(
      initial.materials.any((material) => material.name == 'Glass'),
      isTrue,
    );
    expect(
      initial.floorTypes.map((type) => type.name),
      containsAll(
          <String>['Asphalt Surface', 'Concrete Floor', 'Residential Floor']),
    );
    expect(initial.roofTypes.map((type) => type.name), contains('Roof'));
    final opening = initial.objects.firstWhere(
      (object) => object.kindKey == 'door' || object.kindKey == 'window',
    );
    final hostWallId = int.parse(opening.metadata['host_wall_id'].toString());
    final wall = initial.objectById(hostWallId)!;
    final glassType = initial.wallTypes.firstWhere(
      (type) => type.name == 'Exterior Glass Wall',
    );
    await expectLater(
      repository.setWallType(
        wallId: wall.elementId!,
        wallTypeId: glassType.id,
      ),
      throwsA(
        isA<TbeApiException>().having(
          (error) => error.message,
          'message',
          contains('glass walls'),
        ),
      ),
    );
    final unchanged = (await repository.currentRenderScene()).scene!;
    final unchangedWall = unchanged.objectById(wall.elementId)!;
    expect(
        unchangedWall.metadata['wall_type_id'], wall.metadata['wall_type_id']);
    expect(unchanged.objects.length, initial.objects.length);
    expect(unchanged.objectById(opening.elementId)?.metadata['host_wall_id'],
        hostWallId.toString());
    expect(unchanged.wallTypes, hasLength(initial.wallTypes.length));
    expect(
      unchanged.materials.any((material) => material.name == 'Glass'),
      isTrue,
    );
  });

  test('engine residential campus template creates six 9-storey buildings',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);

    final result = await repository.createResidentialTemplate(
      buildingCount: 6,
      storyCount: 9,
    );
    expect(result.scene!.levels, hasLength(10));
    final saved = await repository.saveProjectJson();
    expect(saved, contains('Residential Campus'));
    expect(saved, contains('Building 6 exterior wall'));
    expect(saved, contains('source_wall_ids'));
  });

  test('engine showcase template exposes ordered site and glass facade',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);

    final result = await repository.createShowcaseTemplate(templateKind: 0);
    final scene = result.scene!;
    expect(result.errors, isEmpty);
    expect(scene.levels, hasLength(4));
    expect(
      scene.wallTypes.map((type) => type.name),
      contains('Exterior Glass Wall'),
    );
    expect(
      scene.floorTypes.map((type) => type.surfaceKind),
      containsAll(<FloorSurfaceKind>[
        FloorSurfaceKind.grass,
        FloorSurfaceKind.paving,
        FloorSurfaceKind.asphalt,
        FloorSurfaceKind.wood,
      ]),
    );
    expect(scene.kindCounts['stair'], greaterThanOrEqualTo(2));
    expect(scene.kindCounts['window'], greaterThanOrEqualTo(4));
    final saved = await repository.saveProjectJson();
    expect(saved, contains('Modern Glass Courtyard House'));
    expect(saved, contains('Landscape Ground'));
  });

  test('engine authoring creates a picked-wall floor in the render scene',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    final result = await repository.createResidentialTemplate(
      buildingCount: 1,
      storyCount: 3,
    );
    final levelId = result.scene!.levels.first.levelId;
    const polygon = <RenderScenePoint>[
      RenderScenePoint(x: 20, y: 0, z: 0),
      RenderScenePoint(x: 24, y: 0, z: 0),
      RenderScenePoint(x: 24, y: 4, z: 0),
      RenderScenePoint(x: 20, y: 4, z: 0),
    ];
    final assemblyId = await repository.defaultAssemblyId('Floor');
    expect(assemblyId, isNotNull);
    final created = await repository.createProfile(
      targetKind: 1,
      draftMode: 0,
      levelId: levelId,
      points: polygon,
      closed: true,
      thicknessMeters: 0.18,
      heightMeters: 0,
      verticalOffsetMeters: 0,
      assemblyId: assemblyId!,
    );
    final createdId = repository.lastCreatedElementId;
    expect(createdId, isNotNull);
    expect(created.scene!.objectById(createdId)!.kindKey, 'floor');
    final createdScene = created.scene!;
    final asphaltFloor = createdScene.floorTypes.firstWhere(
      (type) => type.surfaceKind == FloorSurfaceKind.asphalt,
    );
    final changedResult = await repository.setElementAssembly(
      elementId: createdId!,
      assemblyId: asphaltFloor.id,
    );
    final changedFloor = changedResult.scene!.objectById(createdId)!;
    expect(changedFloor.metadata['assembly_id'], asphaltFloor.id.toString());
    expect(changedFloor.metadata['floor_type'], 'asphalt');
  });

  test('blank project creates picked-wall floor and ceiling without assemblies',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    final blank = await repository.createBlankProject(
      projectName: 'Blank picked-wall floor',
    );
    final levelId = blank.scene!.levels.first.levelId;
    const points = <RenderScenePoint>[
      RenderScenePoint(x: 0, y: 0, z: 0),
      RenderScenePoint(x: 8, y: 0, z: 0),
      RenderScenePoint(x: 8, y: 6, z: 0),
      RenderScenePoint(x: 0, y: 6, z: 0),
    ];
    final wallIds = <int>[];
    for (var index = 0; index < points.length; index += 1) {
      await repository.createWall(
        name: 'Blank boundary wall $index',
        levelId: levelId,
        start: points[index],
        end: points[(index + 1) % points.length],
        thicknessMeters: 0.2,
        heightMeters: 3.2,
      );
      wallIds.add(repository.lastCreatedElementId!);
    }

    final created = await repository.createProfile(
      targetKind: 1,
      draftMode: 2,
      levelId: levelId,
      points: const <RenderScenePoint>[],
      wallIds: wallIds,
      closed: true,
      thicknessMeters: 0.18,
      heightMeters: 0,
      verticalOffsetMeters: 0,
      assemblyId: 0,
    );
    final createdId = repository.lastCreatedElementId;
    expect(createdId, isNotNull);
    expect(created.scene!.objectById(createdId)!.kindKey, 'floor');

    final createdCeiling = await repository.createProfile(
      targetKind: 2,
      draftMode: 2,
      levelId: levelId,
      points: const <RenderScenePoint>[],
      wallIds: wallIds,
      closed: true,
      thicknessMeters: 0.05,
      heightMeters: 3.0,
      verticalOffsetMeters: 2.6,
      assemblyId: 0,
    );
    final ceilingId = repository.lastCreatedElementId;
    expect(ceilingId, isNotNull);
    expect(createdCeiling.scene!.objectById(ceilingId)!.kindKey, 'ceiling');
  });

  test('engine Auto Room exposes exact room boundaries to the viewer',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    final loaded = await repository.createResidentialTemplate(
      buildingCount: 1,
      storyCount: 3,
    );
    final levelId = loaded.scene!.levels.first.levelId;
    await repository.setActiveLevel(levelId);

    final detected = await repository.detectRooms();
    final rooms = detected.scene!.objects
        .where(
            (object) => object.kindKey == 'room' && object.levelId == levelId)
        .toList(growable: false);
    expect(rooms, isNotEmpty);
    for (final room in rooms) {
      expect(RenderSceneEditor.roomBoundaryWallIds(room).length,
          greaterThanOrEqualTo(3));
      expect(
        RenderSceneEditor.roomBoundaryPolygon(detected.scene!, room)!.length,
        greaterThanOrEqualTo(3),
      );
    }
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
      levelId: 2,
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

  test('engine-created floor and ceiling remain bound to their level',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    await repository.loadFromJson(
      projectName: 'Level-bound floor',
      json: File('assets/sample_project.json').readAsStringSync(),
    );
    await repository.createProfile(
      targetKind: 1,
      draftMode: 1,
      levelId: 2,
      points: const <RenderScenePoint>[
        RenderScenePoint(x: 12, y: 0, z: 0),
        RenderScenePoint(x: 16, y: 4, z: 0),
      ],
      closed: true,
      thicknessMeters: 0.18,
      heightMeters: 0,
      verticalOffsetMeters: 0,
      assemblyId: 9,
    );
    final floorId = repository.lastCreatedElementId;
    expect(floorId, isNotNull);
    await repository.createProfile(
      targetKind: 2,
      draftMode: 1,
      levelId: 2,
      points: const <RenderScenePoint>[
        RenderScenePoint(x: 12, y: 0, z: 0),
        RenderScenePoint(x: 16, y: 4, z: 0),
      ],
      closed: true,
      thicknessMeters: 0.05,
      heightMeters: 3,
      verticalOffsetMeters: 2.6,
      assemblyId: 10,
    );
    final ceilingId = repository.lastCreatedElementId;
    expect(ceilingId, isNotNull);
    final before = (await repository.currentRenderScene()).scene!;
    final beforeFloor = before.objectById(floorId)!;
    final beforeCeiling = before.objectById(ceilingId)!;

    await repository.moveLevelElevation(levelId: 2, elevationMeters: 4.45);
    final after = (await repository.currentRenderScene()).scene!;
    final afterFloor = after.objectById(floorId)!;
    final afterCeiling = after.objectById(ceilingId)!;
    expect(afterFloor.kindKey, 'floor');
    expect(afterFloor.levelId, 2);
    expect(afterCeiling.kindKey, 'ceiling');
    expect(afterCeiling.levelId, 2);
    expect(
      afterFloor.bounds.min.z - beforeFloor.bounds.min.z,
      closeTo(1.25, 1e-6),
    );
    expect(
      afterCeiling.bounds.min.z - beforeCeiling.bounds.min.z,
      closeTo(1.25, 1e-6),
    );
  });

  test('automatic roof footprint survives level move and save reload',
      () async {
    final api = TbeViewerApi.load();
    final repository = ViewerRepository(api);
    addTearDown(repository.dispose);
    await repository.loadFromJson(
      projectName: 'Automatic roof',
      json: File('assets/sample_project.json').readAsStringSync(),
    );
    final wallIds = <int>[];
    const points = <RenderScenePoint>[
      RenderScenePoint(x: 12, y: 0, z: 0),
      RenderScenePoint(x: 16, y: 0, z: 0),
      RenderScenePoint(x: 16, y: 4, z: 0),
      RenderScenePoint(x: 12, y: 4, z: 0),
    ];
    for (var index = 0; index < points.length; index += 1) {
      await repository.createWall(
        name: 'Roof footprint wall $index',
        levelId: 1,
        start: points[index],
        end: points[(index + 1) % points.length],
        thicknessMeters: 0.2,
        heightMeters: 3.2,
      );
      final wallId = repository.lastCreatedElementId!;
      wallIds.add(wallId);
      await repository.setWallLevelConstraints(
        wallId: wallId,
        baseLevelId: 1,
        topLevelId: 2,
        heightMode: 1,
      );
    }
    await repository.createProfile(
      targetKind: 3,
      draftMode: 2,
      levelId: 2,
      wallIds: wallIds,
      points: const <RenderScenePoint>[],
      closed: true,
      thicknessMeters: 0.2,
      heightMeters: 0,
      verticalOffsetMeters: 0,
      roofType: 0,
    );
    final roofId = repository.lastCreatedElementId;
    expect(roofId, isNotNull);
    final beforeRoof =
        (await repository.currentRenderScene()).scene!.objectById(roofId)!;

    await repository.moveLevelElevation(levelId: 2, elevationMeters: 4.45);
    final after = (await repository.currentRenderScene()).scene!;
    final afterRoof = after.objectById(roofId)!;
    expect(afterRoof.kindKey, 'roof');
    expect(afterRoof.levelId, 2);
    expect(
      afterRoof.bounds.min.z - beforeRoof.bounds.min.z,
      closeTo(1.25, 1e-6),
    );

    // The roof remembers the picked wall loop in C++, not only its first
    // Flutter preview polygon.  While the loop is edited it retains the last
    // valid footprint, then follows it once the loop closes again.
    const movedPoints = <RenderScenePoint>[
      RenderScenePoint(x: 12, y: 0, z: 0),
      RenderScenePoint(x: 17, y: 0, z: 0),
      RenderScenePoint(x: 17, y: 4, z: 0),
      RenderScenePoint(x: 12, y: 4, z: 0),
    ];
    for (var index = 0; index < wallIds.length; index += 1) {
      await repository.setWallAxis(
        wallId: wallIds[index],
        start: movedPoints[index],
        end: movedPoints[(index + 1) % movedPoints.length],
      );
    }
    final rebuiltRoof =
        (await repository.currentRenderScene()).scene!.objectById(roofId)!;
    expect(rebuiltRoof.bounds.max.x, closeTo(17, 1e-6));

    final saved = await repository.saveProjectJson();
    expect(saved, contains('source_wall_ids'));
    final restored = ViewerRepository(api);
    addTearDown(restored.dispose);
    await restored.loadFromJson(projectName: 'Restored roof', json: saved);
    expect((await restored.currentRenderScene()).scene!.objectById(roofId),
        isNotNull);
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
}
