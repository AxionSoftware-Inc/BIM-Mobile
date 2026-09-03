part of 'widget_test.dart';

void registerInteractionAuthoringTests() {
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
      creationGateway: () => repository,
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
    final historyBeforeOpeningEdit = await repository.historyCounts();
    await commands.updateOpening(
      object: door,
      offsetMeters: 1.15,
      widthMeters: 1.05,
      heightMeters: 2.2,
      sillHeightMeters: 0,
    );
    final historyAfterOpeningEdit = await repository.historyCounts();
    expect(
      historyAfterOpeningEdit.undoCount,
      historyBeforeOpeningEdit.undoCount + 1,
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

  testWidgets('native BIM cache replays only after a platform-view restart',
      (WidgetTester tester) async {
    const channel = MethodChannel('tbe/render_scene_view_78');
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
    await controller.attachNativeBridge(78);
    await tester.pump(const Duration(milliseconds: 300));
    calls.clear();

    await controller.loadNativeBimCache(
      sourceIfcPath: '/tmp/sample.ifc',
      cachePath: '/tmp/sample.bimcache',
    );
    expect(
      calls.where((call) => call.method == 'loadNativeBimCache'),
      hasLength(1),
    );
    calls.clear();

    await controller.setProjectionMode(
      RenderSceneProjectionMode.eastElevation,
    );
    expect(
      calls.where((call) => call.method == 'loadNativeBimCache'),
      isEmpty,
    );

    controller.detachNativeBridge();
    await controller.attachNativeBridge(78);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      calls.where((call) => call.method == 'loadNativeBimCache'),
      hasLength(1),
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
    tool.prepareForCreation(window: true);
    expect(tool.widthMeters, closeTo(0.9, 1e-9));
    expect(tool.heightMeters, closeTo(1.2, 1e-9));
    expect(tool.sillHeightMeters, closeTo(0.9, 1e-9));
    tool.prepareForCreation(window: false);
    expect(tool.heightMeters, closeTo(2.1, 1e-9));
    expect(tool.sillHeightMeters, closeTo(0.0, 1e-9));
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

  test('boundary close is explicit and undo reopens before deleting a point',
      () {
    final tool = SurfaceToolController()
      ..drawMode = RenderSceneSurfaceDrawMode.polyline;
    addTearDown(tool.dispose);
    const points = <RenderScenePoint>[
      RenderScenePoint(x: 0, y: 0, z: 0),
      RenderScenePoint(x: 4, y: 0, z: 0),
      RenderScenePoint(x: 4, y: 3, z: 0),
    ];
    tool.replacePoints(points);

    expect(tool.boundaryClosed, isFalse);
    tool.closeBoundary();
    expect(tool.boundaryClosed, isTrue);
    expect(tool.undoLast(), isTrue);
    expect(tool.boundaryClosed, isFalse);
    expect(tool.points, points);
    expect(tool.undoLast(), isTrue);
    expect(tool.points, hasLength(2));
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
}
