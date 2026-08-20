part of 'widget_test.dart';

void registerAuthoringToolModuleTests() {
  RenderScene loadSampleScene() {
    return parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'authoring tool module test',
    ).scene!;
  }

  test('scene queries expose read-only wall geometry without the editor facade',
      () {
    final scene = loadSampleScene();
    final wall = scene.objects.firstWhere((object) => object.kindKey == 'wall');

    expect(RenderSceneQueries.objectById(scene, wall.elementId), same(wall));
    expect(RenderSceneQueries.wallLength(wall), greaterThan(0.0));
    expect(RenderSceneQueries.wallCenterPoint(wall), isNotNull);
    expect(RenderSceneQueries.wallSnapPoints(scene), isNotEmpty);
  });

  test('wall authoring geometry keeps body moves on the wall normal', () {
    final scene = loadSampleScene();
    final wall = scene.objects.firstWhere((object) => object.kindKey == 'wall');
    final start = RenderSceneEditor.wallStartPoint(wall)!;
    final end = RenderSceneEditor.wallEndPoint(wall)!;
    final anchor = RenderSceneEditor.wallCenterPoint(wall)!;
    final projected = WallAuthoringGeometry.projectToWallNormal(
      RenderScenePoint(x: anchor.x + 2.0, y: anchor.y + 1.0, z: anchor.z),
      anchor: anchor,
      start: start,
      end: end,
    );

    expect(projected.isFinite, isTrue);
    expect(projected.distanceTo(anchor), closeTo(1.0, 1e-9));
    expect(
      projected.distanceTo(
        RenderScenePoint(x: anchor.x, y: anchor.y, z: anchor.z),
      ),
      closeTo(1.0, 1e-9),
    );
  });

  test('wall authoring geometry shares endpoint and grid snapping', () {
    final scene = loadSampleScene();
    final wall = scene.objects.firstWhere((object) => object.kindKey == 'wall');
    final start = RenderSceneEditor.wallStartPoint(wall)!;
    final resolved = WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 5.96, y: 4.03, z: 0),
      referenceStart: start,
      scene: scene,
      activeLevelId: wall.levelId,
      snapToGrid: true,
      projectionMode: RenderSceneProjectionMode.topDown,
      useOrthogonalSnap: true,
      wallOrthogonalSnap: true,
      excludeWallId: wall.elementId,
    );

    expect(resolved.isFinite, isTrue);
    expect(resolved.distanceTo(const RenderScenePoint(x: 6, y: 4, z: 0)),
        lessThan(0.15));
    expect(
      WallAuthoringGeometry.wallSnapCandidates(
        scene,
        const RenderScenePoint(x: 3, y: 0.08, z: 0),
        levelId: wall.levelId,
      ),
      isNotEmpty,
    );
  });

  test('wall continuation ignores a nearby parallel wall', () {
    final scene = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 1,
        'units': 'meters',
        'coordinate_system': 'X/Y plan, Z up',
        'levels': <Object?>[
          <String, Object?>{
            'level_id': 1,
            'name': 'Level 1',
            'elevation_meters': 0.0,
            'default_wall_height_meters': 3.0,
          },
        ],
        'objects': <Object?>[
          <String, Object?>{
            'element_id': 1,
            'kind': 'Wall',
            'level_id': 1,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 0, 'y': -0.1, 'z': 0},
              'max': <String, Object?>{'x': 8, 'y': 0.1, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[],
              'indices': <Object?>[]
            },
            'metadata': <String, Object?>{
              'axis_start': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
              'axis_end': <String, Object?>{'x': 8, 'y': 0, 'z': 0},
              'thickness_meters': 0.2,
            },
          },
          <String, Object?>{
            'element_id': 2,
            'kind': 'Wall',
            'level_id': 1,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
              'max': <String, Object?>{'x': 8, 'y': 0.2, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[],
              'indices': <Object?>[]
            },
            'metadata': <String, Object?>{
              'axis_start': <String, Object?>{'x': 0, 'y': 0.1, 'z': 0},
              'axis_end': <String, Object?>{'x': 8, 'y': 0.1, 'z': 0},
              'thickness_meters': 0.2,
            },
          },
        ],
      }),
      source: 'parallel continuation test',
    ).scene!;

    final resolved = WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 7.9, y: 0.1, z: 0),
      referenceStart: const RenderScenePoint(x: 0, y: 0, z: 0),
      scene: scene,
      activeLevelId: 1,
      snapToGrid: false,
      projectionMode: RenderSceneProjectionMode.topDown,
      useOrthogonalSnap: true,
      wallOrthogonalSnap: true,
      excludeWallId: 1,
    );
    expect(resolved.y, closeTo(0.0, 1e-9));
  });

  test('wall repair chooses the closest bounded endpoint gap', () {
    final scene = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 1,
        'units': 'meters',
        'coordinate_system': 'X/Y plan, Z up',
        'levels': <Object?>[
          <String, Object?>{
            'level_id': 1,
            'name': 'Level 1',
            'elevation_meters': 0.0,
            'default_wall_height_meters': 3.0,
          },
        ],
        'objects': <Object?>[
          <String, Object?>{
            'element_id': 11,
            'kind': 'Wall',
            'level_id': 1,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 0, 'y': -0.1, 'z': 0},
              'max': <String, Object?>{'x': 4.5, 'y': 0.1, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[],
              'indices': <Object?>[]
            },
            'metadata': <String, Object?>{
              'axis_start': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
              'axis_end': <String, Object?>{'x': 4.5, 'y': 0, 'z': 0},
              'thickness_meters': 0.2,
            },
          },
          <String, Object?>{
            'element_id': 12,
            'kind': 'Wall',
            'level_id': 1,
            'bounds': <String, Object?>{
              'min': <String, Object?>{'x': 4.3, 'y': 0.1, 'z': 0},
              'max': <String, Object?>{'x': 4.5, 'y': 3.2, 'z': 3},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[],
              'indices': <Object?>[]
            },
            'metadata': <String, Object?>{
              'axis_start': <String, Object?>{'x': 4.35, 'y': 0.16, 'z': 0},
              'axis_end': <String, Object?>{'x': 4.35, 'y': 3.2, 'z': 0},
              'thickness_meters': 0.2,
            },
          },
        ],
      }),
      source: 'wall repair test',
    ).scene!;
    final candidate = WallRepairGeometry.bestCandidate(
      scene,
      wallIds: const <int>{11, 12},
      levelId: 1,
    );
    expect(candidate, isNotNull);
    expect(candidate!.firstWallId, 11);
    expect(candidate.secondWallId, 12);
    expect(candidate.maxGapMeters, lessThan(0.5));
    expect(candidate.intersection.x, closeTo(4.35, 1e-9));
    expect(
      WallRepairGeometry.bestCandidate(
        scene,
        wallIds: const <int>{11, 12},
        levelId: 2,
      ),
      isNull,
    );
  });

  test('opening authoring geometry projects and validates hosted placement',
      () {
    final scene = loadSampleScene();
    final wall = scene.objects.firstWhere((object) => object.kindKey == 'wall');
    final center = RenderSceneEditor.wallCenterPoint(wall)!;
    final preview = OpeningAuthoringGeometry.preview(
      hostWall: wall,
      point: RenderScenePoint(x: center.x, y: center.y + 0.8, z: center.z),
      widthMeters: 0.9,
      snapToGrid: false,
    );

    expect(preview, isNotNull);
    expect(preview!.valid, isTrue);
    expect(preview.offsetMeters, closeTo(preview.wallLengthMeters / 2, 1e-9));
    expect(
      OpeningAuthoringGeometry.isValid(
        hostWall: wall,
        offsetMeters: 0,
        widthMeters: 0.9,
      ),
      isFalse,
    );
  });

  test('surface authoring geometry shares real footprint rules', () {
    const start = RenderScenePoint(x: 1, y: 2, z: 0);
    const end = RenderScenePoint(x: 5, y: 6, z: 0);
    final preview = SurfaceAuthoringGeometry.previewPoints(
      mode: RenderSceneSurfaceDrawMode.rectangle,
      start: start,
      end: end,
    );
    final bounds = SurfaceAuthoringGeometry.rectangleBounds(start, end);

    expect(preview, hasLength(4));
    expect(SurfaceAuthoringGeometry.isUsableRectangle(start, end), isTrue);
    expect(bounds, isNotNull);
    expect(bounds!.width, closeTo(4, 1e-9));
    expect(bounds.depth, closeTo(4, 1e-9));
    expect(
      SurfaceAuthoringGeometry.profilePoints(
        mode: RenderSceneSurfaceDrawMode.polyline,
        points: preview,
      ),
      preview,
    );
  });

  test('stair authoring geometry validates run, rise and riser count', () {
    var scene = loadSampleScene();
    scene = RenderSceneEditor.createLevel(
      scene: scene,
      name: 'Level 2',
      elevationMeters: 3.2,
    );
    final base = scene.levels.first;
    final top = scene.levels.last;
    final preview = StairAuthoringGeometry.preview(
      start: const RenderScenePoint(x: 1, y: 1, z: 0),
      end: const RenderScenePoint(x: 4, y: 1, z: 0),
      baseLevel: base,
      topLevel: top,
    );

    expect(preview, isNotNull);
    expect(preview!.runMeters, closeTo(3, 1e-9));
    expect(preview.riseMeters, closeTo(3.2, 1e-9));
    expect(preview.riserCount, inInclusiveRange(1, 60));
    expect(
      StairAuthoringGeometry.preview(
        start: const RenderScenePoint(x: 1, y: 1, z: 0),
        end: const RenderScenePoint(x: 1.5, y: 1, z: 0),
        baseLevel: base,
        topLevel: top,
      ),
      isNull,
    );
  });
}
