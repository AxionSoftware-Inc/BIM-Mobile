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

  test('wall drawing quantizes freehand length to 10 mm and snap to 100 mm',
      () {
    const start = RenderScenePoint(x: 0, y: 0, z: 0);
    final freehand = WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 5.532, y: 0.01, z: 0),
      referenceStart: start,
      scene: null,
      activeLevelId: null,
      snapToGrid: false,
      projectionMode: RenderSceneProjectionMode.topDown,
      useOrthogonalSnap: true,
      wallOrthogonalSnap: true,
    );
    expect(freehand.x, closeTo(5.53, 1e-9));
    expect(freehand.y, closeTo(0, 1e-9));
    expect(
      WallAuthoringGeometry.formatWallLengthMeters(5.532),
      '5.53 m',
    );

    final snapped = WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 5.54, y: 0.01, z: 0),
      referenceStart: start,
      scene: null,
      activeLevelId: null,
      snapToGrid: true,
      projectionMode: RenderSceneProjectionMode.topDown,
      useOrthogonalSnap: true,
      wallOrthogonalSnap: true,
    );
    expect(snapped.x, closeTo(5.5, 1e-9));
    expect(snapped.y, closeTo(0, 1e-9));
  });

  test('wall drawing aligns distant corners on the active wall axis', () {
    const index = WallSnapIndex(<WallSnapSegment>[
      WallSnapSegment(
        elementId: 10,
        levelId: 1,
        start: RenderScenePoint(x: 8, y: 4, z: 0),
        end: RenderScenePoint(x: 12, y: 4, z: 0),
      ),
    ]);
    final resolved = WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: const RenderScenePoint(x: 7.94, y: 0.10, z: 0),
      referenceStart: const RenderScenePoint(x: 0, y: 0, z: 0),
      scene: null,
      activeLevelId: 1,
      snapToGrid: false,
      projectionMode: RenderSceneProjectionMode.topDown,
      useOrthogonalSnap: true,
      wallOrthogonalSnap: true,
      snapIndex: index,
    );

    expect(resolved.x, closeTo(8, 1e-9));
    expect(resolved.y, closeTo(0, 1e-9));
  });

  test('surface boundary snapping prioritizes nearby wall corners', () {
    const index = WallSnapIndex(<WallSnapSegment>[
      WallSnapSegment(
        elementId: 10,
        levelId: 1,
        start: RenderScenePoint(x: 0, y: 0, z: 0),
        end: RenderScenePoint(x: 4, y: 0, z: 0),
        thicknessMeters: 0.2,
      ),
      WallSnapSegment(
        elementId: 11,
        levelId: 1,
        start: RenderScenePoint(x: 4, y: 0, z: 0),
        end: RenderScenePoint(x: 4, y: 4, z: 0),
        thicknessMeters: 0.2,
      ),
    ]);

    final corner = WallAuthoringGeometry.snapBoundaryPointToWalls(
      const RenderScenePoint(x: 4.42, y: 0.08, z: 1.2),
      snapIndex: index,
    );
    expect(corner, isNotNull);
    expect(corner!.x, closeTo(4.1, 1e-9));
    expect(corner.y, closeTo(0.1, 1e-9));
    expect(corner.z, closeTo(1.2, 1e-9));

    final outerCorner = WallAuthoringGeometry.snapBoundaryPointToWalls(
      const RenderScenePoint(x: 4.34, y: -0.07, z: 0),
      snapIndex: index,
    );
    expect(outerCorner, isNotNull);
    expect(outerCorner!.x, closeTo(4.1, 1e-9));
    expect(outerCorner.y, closeTo(-0.1, 1e-9));

    final wallBody = WallAuthoringGeometry.snapBoundaryPointToWalls(
      const RenderScenePoint(x: 2.0, y: 0.24, z: 0),
      snapIndex: index,
    );
    expect(wallBody, isNull);

    expect(
      WallAuthoringGeometry.snapBoundaryPointToWalls(
        const RenderScenePoint(x: 7, y: 7, z: 0),
        snapIndex: index,
      ),
      isNull,
    );
  });

  test('surface boundary snapping uses the final joined wall profile', () {
    // These are the native mitered profiles for an east wall joining a north
    // wall at (4, 0). The old independent face endpoint (4.1, 0.1) is not a
    // snap target after the join; the final inner/outer points are (3.9, 0.1)
    // and (4.1, -0.1).
    const index = WallSnapIndex(<WallSnapSegment>[
      WallSnapSegment(
        elementId: 20,
        levelId: 1,
        start: RenderScenePoint(x: 0, y: 0, z: 0),
        end: RenderScenePoint(x: 4, y: 0, z: 0),
        thicknessMeters: 0.2,
        profileCorners: <RenderScenePoint>[
          RenderScenePoint(x: 0, y: -0.1, z: 0),
          RenderScenePoint(x: 4.1, y: -0.1, z: 0),
          RenderScenePoint(x: 3.9, y: 0.1, z: 0),
          RenderScenePoint(x: 0, y: 0.1, z: 0),
        ],
      ),
      WallSnapSegment(
        elementId: 21,
        levelId: 1,
        start: RenderScenePoint(x: 4, y: 0, z: 0),
        end: RenderScenePoint(x: 4, y: 4, z: 0),
        thicknessMeters: 0.2,
        profileCorners: <RenderScenePoint>[
          RenderScenePoint(x: 4.1, y: -0.1, z: 0),
          RenderScenePoint(x: 3.9, y: 0.1, z: 0),
          RenderScenePoint(x: 3.9, y: 4, z: 0),
          RenderScenePoint(x: 4.1, y: 4, z: 0),
        ],
      ),
    ]);

    final joinedCorner = WallAuthoringGeometry.snapBoundaryPointToWalls(
      const RenderScenePoint(x: 4.08, y: -0.08, z: 0),
      snapIndex: index,
    );
    expect(joinedCorner, isNotNull);
    expect(joinedCorner!.x, closeTo(4.1, 1e-9));
    expect(joinedCorner.y, closeTo(-0.1, 1e-9));

    final nearRemovedCorner = WallAuthoringGeometry.snapBoundaryPointToWalls(
      const RenderScenePoint(x: 4.08, y: 0.08, z: 0),
      snapIndex: index,
    );
    expect(nearRemovedCorner, isNotNull);
    expect(nearRemovedCorner!.x, closeTo(3.9, 1e-9));
    expect(nearRemovedCorner.y, closeTo(0.1, 1e-9));
    expect(nearRemovedCorner.x, isNot(closeTo(4.1, 1e-9)));
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

  test('boundary preview keeps a live cursor separate from committed points',
      () {
    const first = RenderScenePoint(x: 0, y: 0, z: 0);
    const second = RenderScenePoint(x: 4, y: 0, z: 0);
    const third = RenderScenePoint(x: 4, y: 3, z: 0);
    const cursor = RenderScenePoint(x: 0, y: 3, z: 0);
    final preview = SurfaceAuthoringGeometry.previewPoints(
      mode: RenderSceneSurfaceDrawMode.polyline,
      points: const <RenderScenePoint>[first, second, third],
      cursor: cursor,
    );

    expect(preview, hasLength(4));
    expect(preview.last, cursor);
    expect(
      SurfaceAuthoringGeometry.previewIsClosed(
        mode: RenderSceneSurfaceDrawMode.polyline,
        points: preview,
      ),
      isFalse,
    );
    expect(
      SurfaceAuthoringGeometry.isValidBoundary(
        const <RenderScenePoint>[first, second, third, cursor],
        closed: true,
      ),
      isTrue,
    );
  });

  test('boundary validation rejects self-crossing sketches', () {
    const bowTie = <RenderScenePoint>[
      RenderScenePoint(x: 0, y: 0, z: 0),
      RenderScenePoint(x: 4, y: 3, z: 0),
      RenderScenePoint(x: 0, y: 3, z: 0),
      RenderScenePoint(x: 4, y: 0, z: 0),
    ];

    expect(
      SurfaceAuthoringGeometry.isValidBoundary(bowTie, closed: true),
      isFalse,
    );
    expect(
      SurfaceAuthoringGeometry.boundaryValidationMessage(
        bowTie,
        closed: true,
      ),
      contains('kesishgan'),
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
