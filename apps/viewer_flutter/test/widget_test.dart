import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/documentation/document_models.dart';
import 'package:viewer_flutter/src/documentation/document_pdf_service.dart';
import 'package:viewer_flutter/src/documentation/sheet_workspace_controller.dart';
import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_estimator.dart';
import 'package:viewer_flutter/src/render_scene_level_overlay.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_repository.dart';
import 'package:viewer_flutter/src/scene_mutation_service.dart';
import 'package:viewer_flutter/src/scene_view_service.dart';
import 'package:viewer_flutter/src/project_persistence_service.dart';
import 'package:viewer_flutter/src/project_lifecycle_service.dart';
import 'package:viewer_flutter/src/project_session_controller.dart';
import 'package:viewer_flutter/src/render_scene_viewport_controller.dart';
import 'package:viewer_flutter/src/render_scene_viewport_planar.dart';
import 'package:viewer_flutter/src/render_scene_viewport_projection.dart';
import 'package:viewer_flutter/src/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/selection_controller.dart';
import 'package:viewer_flutter/src/inspector_controller.dart';
import 'package:viewer_flutter/src/authoring_command_service.dart';
import 'package:viewer_flutter/src/tbe_ffi.dart';
import 'package:viewer_flutter/src/viewer_engine_contracts.dart';
import 'package:viewer_flutter/src/viewer_project_gateway.dart';
import 'package:viewer_flutter/src/viewer_project_session.dart';
import 'package:viewer_flutter/src/viewer_scene_gateway.dart';
import 'package:viewer_flutter/src/tools/level_tool_controller.dart';
import 'package:viewer_flutter/src/tools/opening_tool_controller.dart';
import 'package:viewer_flutter/src/tools/plan_sketch_geometry.dart';
import 'package:viewer_flutter/src/tools/surface_tool_controller.dart';
import 'package:viewer_flutter/src/tools/wall_tool_controller.dart';
import 'package:viewer_flutter/src/viewer_app.dart';
import 'package:viewer_flutter/src/viewport_interaction.dart';

class _RecordingSceneGateway implements ViewerSceneGateway {
  int? activeLevelId;
  bool? fullSceneEnabled;

  static const RenderSceneLoadResult result = RenderSceneLoadResult(
    scene: null,
    warnings: <String>[],
    errors: <String>[],
  );

  @override
  Future<RenderSceneLoadResult> currentRenderScene() async => result;

  @override
  Future<RenderSceneLoadResult> setActiveLevel(int levelId) async {
    activeLevelId = levelId;
    return result;
  }

  @override
  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled) async {
    fullSceneEnabled = enabled;
    return result;
  }

  @override
  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  ) async =>
      result;
}

class _RecordingProjectGateway implements ViewerProjectGateway {
  String? receivedProjectName;
  String? receivedJson;

  @override
  Future<ViewerLoadResult> loadFromJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    receivedProjectName = projectName;
    receivedJson = json;
    return _emptyLoadResult();
  }

  @override
  Future<ViewerLoadResult> loadFromPackage({
    required String packagePath,
  }) async =>
      _emptyLoadResult();

  @override
  Future<ViewerLoadResult> reloadCurrent() async => _emptyLoadResult();

  @override
  Future<String> saveProjectJson() async => '{"schema_version": 1}';

  @override
  Future<File> saveProjectToDefaultLocation() async =>
      File('/tmp/example.tbe.json');

  ViewerLoadResult _emptyLoadResult() => ViewerLoadResult(
        snapshot: ViewerSnapshot(
          projectName: 'Test project',
          engineVersion: 'test',
          apiVersion: 'test',
          schemaVersion: 1,
          levelId: 0,
          validation: ValidationSummary(
            issueCount: 0,
            warningCount: 0,
            errorCount: 0,
          ),
          schedule: ScheduleSummary(
            wallRows: 0,
            openingRows: 0,
            roomRows: 0,
            slabRows: 0,
            roofRows: 0,
            columnRows: 0,
            beamRows: 0,
            stairRows: 0,
            floorRows: 0,
            ceilingRows: 0,
            materialTakeoffRows: 0,
          ),
          svgPath: '',
          packagePath: '',
          validationMessages: const <String>[],
        ),
        hitCandidates: const <HitCandidateView>[],
      );
}

class _RecordingProjectSession extends _RecordingProjectGateway
    implements ViewerProjectSession {
  int? buildingCount;
  int? storyCount;
  bool disposed = false;

  @override
  Future<RenderSceneLoadResult> createBlankProject({
    String projectName = 'New Project',
  }) async {
    return const RenderSceneLoadResult(
      scene: null,
      warnings: <String>[],
      errors: <String>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> createResidentialTemplate({
    required int buildingCount,
    required int storyCount,
  }) async {
    this.buildingCount = buildingCount;
    this.storyCount = storyCount;
    return const RenderSceneLoadResult(
      scene: null,
      warnings: <String>[],
      errors: <String>[],
    );
  }

  @override
  void dispose() => disposed = true;
}

class _RecordingSessionFactory
    implements ViewerSessionFactory<_RecordingProjectSession> {
  _RecordingSessionFactory(this.session);

  final _RecordingProjectSession session;
  int createCount = 0;

  @override
  Future<_RecordingProjectSession> create() async {
    createCount += 1;
    return session;
  }
}

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
    final assemblyId = repository.defaultAssemblyId('Floor');
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
  });

  test('blank project creates a picked-wall floor without an assembly',
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

  test(
      'central selection drives every Inspector target and survives view changes',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    await repository.loadFromJson(
      projectName: 'Inspector selection',
      json: File('assets/sample_project.json').readAsStringSync(),
    );
    final scene = (await repository.currentRenderScene()).scene!;
    final viewport = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );
    final selection = SelectionController(viewport);
    final inspector = InspectorController(selection);
    addTearDown(inspector.dispose);
    addTearDown(selection.dispose);
    addTearDown(viewport.dispose);
    await viewport.updateRenderScene(scene);

    for (final kind in <String>[
      'wall',
      'door',
      'window',
      'floor',
      'ceiling',
      'stair',
      'roof',
      'column',
      'beam',
    ]) {
      final object = scene.objects.firstWhere((entry) => entry.kindKey == kind);
      await selection.selectObject(object);
      expect(inspector.targetFor(scene).kind, InspectorTargetKind.object);
      expect(inspector.targetFor(scene).object!.elementId, object.elementId);

      await viewport.setProjectionMode(RenderSceneProjectionMode.isometric);
      await viewport
          .setProjectionMode(RenderSceneProjectionMode.northElevation);
      expect(viewport.activeElementId, object.elementId.toString());
      expect(inspector.targetFor(scene).object!.elementId, object.elementId);
    }

    await viewport.selectElements(<String>{'11', '25'}, activeElementId: '25');
    expect(inspector.targetFor(scene).kind, InspectorTargetKind.multiple);
    await selection.selectLevel(scene.levels.first.levelId);
    expect(inspector.targetFor(scene).kind, InspectorTargetKind.level);
    await selection.clear();
    expect(inspector.targetFor(scene).kind, InspectorTargetKind.empty);
  });

  test('Inspector commands persist level and opening edits through reload',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    await repository.loadFromJson(
      projectName: 'Inspector persistence',
      json: File('assets/sample_project.json').readAsStringSync(),
    );
    final commands = AuthoringCommandService(
      repository: () => repository,
      engineEnabled: () => true,
    );
    final initial = (await repository.currentRenderScene()).scene!;
    final door = initial.objects.firstWhere((entry) => entry.kindKey == 'door');
    final doorId = door.elementId!;
    final level = initial.levels.first;

    await commands.updateLevel(
      levelId: level.levelId,
      name: 'Ground authoring level',
      elevationMeters: 0.15,
      defaultWallHeightMeters: 3.35,
    );
    await commands.setOpeningLevelConstraint(
      openingId: doorId,
      levelId: level.levelId,
      levelOffsetMeters: 0.25,
    );
    await commands.updateOpening(
      object: door,
      offsetMeters: 1.15,
      widthMeters: 1.05,
      heightMeters: 2.2,
      sillHeightMeters: 0,
    );
    final saved = await repository.saveProjectJson();
    expect(saved, contains('Ground authoring level'));
    await repository.reloadCurrent();
    final reloaded = (await repository.currentRenderScene()).scene!;
    final nextLevel = reloaded.levelById(level.levelId)!;
    final nextDoor = reloaded.objectById(doorId)!;
    expect(nextLevel.name, 'Ground authoring level');
    expect(nextLevel.elevationMeters, closeTo(0.15, 1e-6));
    expect(
      double.parse(nextDoor.metadata['width_meters'].toString()),
      closeTo(1.05, 1e-6),
    );
    expect(
      double.parse(nextDoor.metadata['level_offset_meters'].toString()),
      closeTo(0.25, 1e-6),
    );
  });

  test('viewport owns a backend-independent selection rectangle', () {
    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.fallback,
    );
    addTearDown(controller.dispose);
    const rectangle = Rect.fromLTRB(10, 20, 80, 90);
    controller.setSelectionRectangle(rectangle, crossing: true);
    expect(controller.selectionRectangle, rectangle);
    expect(controller.selectionRectangleCrossing, isTrue);
    controller.setSelectionRectangle(null);
    expect(controller.selectionRectangle, isNull);
    expect(controller.selectionRectangleCrossing, isFalse);
  });

  testWidgets('clearing selection clears the native highlight mirror',
      (WidgetTester tester) async {
    const channel = MethodChannel('tbe/render_scene_view_77');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final controller = RenderSceneViewportController(
      backend: RenderSceneViewportBackend.native,
    );
    addTearDown(controller.dispose);
    await controller.attachNativeBridge(77);
    await tester.pump(const Duration(milliseconds: 300));
    calls.clear();

    await controller.selectElement('27');
    await controller.highlightElement('27');
    calls.clear();

    await controller.selectLevel(null);

    expect(
      calls.where((call) => call.method == 'highlightElement'),
      contains(predicate<MethodCall>((call) => call.arguments == null)),
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
    expect(tool.drawMode, RenderSceneSurfaceDrawMode.pickWalls);
    expect(tool.floorTopMeters, closeTo(4.2, 1e-9));
    expect(tool.heightMeters, closeTo(3.6, 1e-9));
  });

  test('surface touch undo reverses points, picked walls and rectangles', () {
    final tool = SurfaceToolController();
    addTearDown(tool.dispose);
    const first = RenderScenePoint(x: 1, y: 2, z: 0);
    const second = RenderScenePoint(x: 4, y: 2, z: 0);

    tool
      ..drawMode = RenderSceneSurfaceDrawMode.polyline
      ..replacePoints(const <RenderScenePoint>[first, second]);
    expect(tool.canUndo, isTrue);
    expect(tool.undoLast(), isTrue);
    expect(tool.points, const <RenderScenePoint>[first]);
    expect(tool.start, first);
    expect(tool.end, first);

    tool
      ..drawMode = RenderSceneSurfaceDrawMode.pickWalls
      ..replaceWallIds(const <int>[8, 3, 11]);
    expect(tool.undoLast(), isTrue);
    expect(tool.wallIds, const <int>{8, 3});

    tool
      ..drawMode = RenderSceneSurfaceDrawMode.rectangle
      ..start = first
      ..end = second;
    expect(tool.undoLast(), isTrue);
    expect(tool.start, isNull);
    expect(tool.end, isNull);
    expect(tool.canUndo, isFalse);
  });

  test('plan sketch kernel shares snap, ortho and rectangle rules', () {
    const start = RenderScenePoint(x: 0, y: 0, z: 3.2);
    const raw = RenderScenePoint(x: 2.10, y: 2.84, z: 3.2);
    const wallEnd = RenderScenePoint(x: 2.0, y: 3.0, z: 0);
    final endpoint = PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: raw,
      referenceStart: start,
      candidatePoints: const <RenderScenePoint>[wallEnd],
    );
    // A diagonal continuation is preserved; only a small hand wobble is
    // corrected to an axis.
    expect(endpoint.x, closeTo(2, 1e-9));
    expect(endpoint.y, closeTo(3, 1e-9));
    expect(endpoint.z, closeTo(3.2, 1e-9));

    final slightWobble = PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 2.10, y: 0.08, z: 3.2),
      referenceStart: start,
      useGridSnap: false,
    );
    expect(slightWobble.x, closeTo(2.10, 1e-9));
    expect(slightWobble.y, closeTo(0, 1e-9));

    final wallWobble = PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 2.10, y: 0.30, z: 3.2),
      referenceStart: start,
      useGridSnap: false,
      orthogonalDominance: PlanSketchGeometry.wallOrthogonalDominance,
    );
    expect(wallWobble.x, closeTo(2.10, 1e-9));
    expect(wallWobble.y, closeTo(0, 1e-9));

    final rectangle = PlanSketchGeometry.rectangle(
      const RenderScenePoint(x: 4, y: 6, z: 1),
      const RenderScenePoint(x: 1, y: 2, z: 2),
    );
    expect(rectangle, hasLength(4));
    expect(rectangle.first.x, closeTo(1, 1e-9));
    expect(rectangle.first.y, closeTo(2, 1e-9));
    expect(rectangle[2].x, closeTo(4, 1e-9));
    expect(rectangle[2].y, closeTo(6, 1e-9));
    expect(rectangle.every((point) => point.z == 2), isTrue);
  });

  test('plan sketch Trim/Extend respects explicitly selected endpoints', () {
    const first = PlanSketchLine(
      start: RenderScenePoint(x: 0, y: 0, z: 0),
      end: RenderScenePoint(x: 3, y: 0, z: 0),
    );
    const second = PlanSketchLine(
      start: RenderScenePoint(x: 4, y: 1, z: 0),
      end: RenderScenePoint(x: 4, y: 4, z: 0),
    );
    final result = PlanSketchGeometry.trimExtend(
      first: first,
      firstEndpoint: PlanSketchEndpoint.end,
      second: second,
      secondEndpoint: PlanSketchEndpoint.start,
    );
    expect(result, isNotNull);
    expect(result!.first.end.x, closeTo(4, 1e-9));
    expect(result.first.end.y, closeTo(0, 1e-9));
    expect(result.second.start.x, closeTo(4, 1e-9));
    expect(result.second.start.y, closeTo(0, 1e-9));

    final parallel = PlanSketchGeometry.trimExtend(
      first: first,
      firstEndpoint: PlanSketchEndpoint.end,
      second: const PlanSketchLine(
        start: RenderScenePoint(x: 0, y: 1, z: 0),
        end: RenderScenePoint(x: 3, y: 1, z: 0),
      ),
      secondEndpoint: PlanSketchEndpoint.start,
    );
    expect(parallel, isNull);
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
    expect(find.byTooltip('Floor plan'), findsOneWidget);
    expect(find.byTooltip('3D view'), findsOneWidget);
    expect(find.byTooltip('Wall'), findsOneWidget);
    expect(find.byTooltip('Documentation and PDF'), findsOneWidget);
  });

  testWidgets('App launch shows the project start screen',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(const ViewerApp());
    await tester.pumpAndSettle();

    expect(find.text('Start a project'), findsOneWidget);
    expect(find.text('Open project'), findsOneWidget);
    expect(find.text('Create new'), findsOneWidget);
    expect(find.text('Default building'), findsOneWidget);
    expect(find.text('Residential tower'), findsOneWidget);
    expect(find.text('Residential campus'), findsOneWidget);
    expect(find.text('Wall #11'), findsNothing);
  });

  testWidgets('Roof tool exposes contextual boundary and Trim controls',
      (WidgetTester tester) async {
    final json = File('assets/render_scene.json').readAsStringSync();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      ViewerApp(
        source:
            MemoryRenderSceneSource(json, source: 'assets/render_scene.json'),
        preferEngineBackedBundledSample: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Roof'));
    await tester.pumpAndSettle();

    expect(find.text('Draw Roof'), findsOneWidget);
    expect(find.text('Boundary'), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Pick Walls'), findsOneWidget);
    expect(find.text('Trim / Extend'), findsOneWidget);
    expect(find.text('Auto Room'), findsNothing);
  });

  testWidgets('Project Browser keeps categories without an object list',
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

    expect(find.text('Sections (2)'), findsOneWidget);
    expect(find.textContaining('Sheets ('), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Wall #11'), findsNothing);
  });

  test('documentation sheet resolver supports current and all floor plans', () {
    final scene = parseRenderSceneJson(
      File('assets/render_scene.json').readAsStringSync(),
      source: 'documentation test',
    ).scene!;
    final activeLevel = scene.levels.first.levelId;
    final base = SheetDocumentSettings(
      projectName: 'Test Project',
      author: 'Test Team',
      sheetPrefix: 'A',
      scaleDenominator: 100,
      scope: DocumentationScope.currentFloorPlan,
      generatedAt: DateTime.utc(2026, 8, 11),
    );

    final current = resolveDocumentationSheets(
      scene: scene,
      settings: base,
      activeLevelId: activeLevel,
    );
    final all = resolveDocumentationSheets(
      scene: scene,
      settings: base.copyWith(scope: DocumentationScope.allFloorPlans),
      activeLevelId: activeLevel,
    );

    expect(current, hasLength(1));
    expect(current.single.number, 'A101');
    expect(all, hasLength(scene.levels.length));
    expect(all.last.number, 'A${(100 + scene.levels.length)}');
  });

  test('sheet workspace creates sheets and keeps normalized view placements',
      () {
    final controller = SheetWorkspaceController();
    final sheet = controller.createSheet(title: 'General Arrangement');
    const view = SheetViewReference(
      id: 'floor-plan-1',
      label: 'Level 1 plan',
      kind: SheetViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: 1,
    );

    expect(sheet.number, 'A101');
    expect(
      controller.placeView(view: view, centerX: 0.5, centerY: 0.42),
      isTrue,
    );
    expect(
      controller.placeView(view: view, centerX: 0.7, centerY: 0.4),
      isFalse,
    );

    final placement = controller.activeSheet!.placements.single;
    controller.movePlacement(placement.id, 5, 5);
    final moved = controller.activeSheet!.placements.single;
    expect(moved.left + moved.width, lessThanOrEqualTo(1));
    expect(moved.top + moved.height, lessThanOrEqualTo(0.9));
    controller.dispose();
  });

  test('sheet placements follow their own view presentation metadata', () {
    final controller = SheetWorkspaceController();
    controller.createSheet(title: 'Presentation metadata');
    const floorPlan = SheetViewReference(
      id: 'floor-plan-1',
      label: 'Level 1 plan',
      kind: SheetViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: 1,
      displayStyle: RenderSceneDisplayStyle.shaded,
    );
    const threeD = SheetViewReference(
      id: 'view-3d-default',
      label: '3D View',
      kind: SheetViewKind.threeD,
      projectionMode: RenderSceneProjectionMode.isometric,
      displayStyle: RenderSceneDisplayStyle.solid,
    );
    controller.placeView(view: floorPlan, centerX: 0.35, centerY: 0.35);
    controller.placeView(view: threeD, centerX: 0.7, centerY: 0.35);

    controller.updateViewPresentation(
      'floor-plan-1',
      displayStyle: RenderSceneDisplayStyle.solid,
    );

    final placements = controller.activeSheet!.placements;
    expect(
      placements
          .singleWhere((item) => item.view.id == 'floor-plan-1')
          .view
          .displayStyle,
      RenderSceneDisplayStyle.solid,
    );
    expect(
      placements
          .singleWhere((item) => item.view.id == 'view-3d-default')
          .view
          .displayStyle,
      RenderSceneDisplayStyle.solid,
    );
    controller.dispose();
  });

  testWidgets('Project Browser opens a blank A3 sheet in the main workspace',
      (WidgetTester tester) async {
    final json = File('assets/render_scene.json').readAsStringSync();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(
      ViewerApp(
        source: MemoryRenderSceneSource(json, source: 'sheet widget test'),
        preferEngineBackedBundledSample: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheets (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Sheet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('A101 · Unnamed Sheet'), findsWidgets);
    expect(find.text('Sheet hali bo‘sh'), findsOneWidget);
    expect(find.textContaining('Floor Plan, Elevation'), findsOneWidget);
  });

  testWidgets('documentation service builds a real PDF sheet',
      (WidgetTester tester) async {
    final scene = parseRenderSceneJson(
      File('assets/render_scene.json').readAsStringSync(),
      source: 'documentation PDF test',
    ).scene!;
    final bytes = await tester.runAsync(
      () => const DocumentPdfService().buildPdf(
        scene: scene,
        settings: SheetDocumentSettings(
          projectName: 'Test Project',
          author: 'Test Team',
          sheetPrefix: 'A',
          scaleDenominator: 100,
          scope: DocumentationScope.currentFloorPlan,
          generatedAt: DateTime.utc(2026, 8, 11),
        ),
        activeLevelId: scene.levels.first.levelId,
      ),
    );
    final pdfBytes = bytes!;

    expect(pdfBytes.length, greaterThan(10000));
    expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
  });

  testWidgets('documentation service exports placed sheet viewports',
      (WidgetTester tester) async {
    final scene = parseRenderSceneJson(
      File('assets/render_scene.json').readAsStringSync(),
      source: 'composed sheet PDF test',
    ).scene!;
    final controller = SheetWorkspaceController();
    controller.createSheet(title: 'General Arrangement');
    final level = scene.levels.first;
    final view = SheetViewReference(
      id: 'floor-plan-${level.levelId}',
      label: '${level.name} plan',
      kind: SheetViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: level.levelId,
    );
    controller.placeView(view: view, centerX: 0.45, centerY: 0.42);

    final bytes = await tester.runAsync(
      () => const DocumentPdfService().buildComposedSheetPdf(
        scene: scene,
        sheet: controller.activeSheet!,
        resolvedScenes: <String, RenderScene>{},
        settings: SheetDocumentSettings(
          projectName: 'Test Project',
          author: 'Test Team',
          sheetPrefix: 'A',
          scaleDenominator: 100,
          scope: DocumentationScope.currentFloorPlan,
          generatedAt: DateTime.utc(2026, 8, 11),
        ),
      ),
    );
    final pdfBytes = bytes!;

    expect(pdfBytes.length, greaterThan(10000));
    expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
    controller.dispose();
  });
}
