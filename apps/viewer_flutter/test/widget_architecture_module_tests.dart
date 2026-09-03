part of 'widget_test.dart';

void registerArchitectureModuleTests() {
  test('element Inspector adapters decode typed family parameters', () {
    const object = RenderSceneObject(
      elementId: 42,
      kind: 'Wall',
      levelId: 7,
      selectable: true,
      visibleByDefault: true,
      revision: 3,
      bounds: RenderSceneBounds(
        min: RenderScenePoint(x: 0, y: 0, z: 0),
        max: RenderScenePoint(x: 0, y: 0, z: 0),
      ),
      mesh: RenderSceneMesh(
        positions: <RenderScenePoint>[],
        indices: <int>[],
        normals: null,
      ),
      materialCategory: 'brick',
      metadata: <String, Object?>{
        'base_level_id': '7',
        'top_level_id': 8,
        'wall_type_id': '101',
        'base_offset_meters': 0.15,
        'top_offset_meters': '0.05',
        'thickness_meters': 0.24,
        'length_meters': '4.5',
        'layer_profile': 'brick;insulation;plaster',
        'wall_type_category': 'Exterior',
        'host_wall_id': 42,
        'offset_meters': 1.2,
        'width_meters': '0.9',
        'height_meters': 2.1,
        'sill_height_meters': 0.0,
        'level_offset_meters': 0.1,
        'level_locked': 'true',
        'assembly_id': '12',
        'area_m2': 24.0,
        'vertical_offset_meters': '0.2',
        'floor_type_name': 'Concrete',
        'roof_type': 'SimpleGable',
        'slope_degrees': '30',
        'overhang_meters': 0.3,
        'total_run_meters': 3.6,
        'total_rise_meters': '2.4',
        'tread_count': '12',
        'riser_count': 13,
      },
    );

    final wall = WallElementParameters.fromObject(object);
    expect(wall.baseLevelId, 7);
    expect(wall.topLevelId, 8);
    expect(wall.wallTypeId, 101);
    expect(wall.layerCount, 3);
    expect(wall.thicknessMeters, 0.24);

    final opening = OpeningElementParameters.fromObject(object);
    expect(opening.hostWallId, 42);
    expect(opening.widthMeters, 0.9);
    expect(opening.levelLocked, isTrue);

    final surface = SurfaceElementParameters.fromObject(object);
    expect(surface.assemblyId, 12);
    expect(surface.areaSquareMeters, 24);
    expect(surface.typeName, 'Concrete');

    final roof = RoofElementParameters.fromObject(object);
    expect(roof.roofType, 1);
    expect(roof.slopeDegrees, 30);

    final stair = StairElementParameters.fromObject(object);
    expect(stair.totalRunMeters, 3.6);
    expect(stair.riserCount, 13);

    final linear = LinearElementParameters.fromObject(object);
    expect(linear.heightMeters, 2.1);
    expect(linear.lengthMeters, 4.5);

    final room = RoomElementParameters.fromObject(object);
    expect(room.areaSquareMeters, 24);
    expect(room.perimeterMeters, isNull);

    const malformed = RenderSceneObject(
      elementId: 43,
      kind: 'Wall',
      levelId: 7,
      selectable: true,
      visibleByDefault: true,
      revision: 1,
      bounds: RenderSceneBounds(
        min: RenderScenePoint(x: 0, y: 0, z: 0),
        max: RenderScenePoint(x: 0, y: 0, z: 0),
      ),
      mesh: RenderSceneMesh(
        positions: <RenderScenePoint>[],
        indices: <int>[],
        normals: null,
      ),
      materialCategory: 'generic',
      metadata: <String, Object?>{
        'height_meters': 'NaN',
        'level_locked': 'unknown',
      },
    );
    expect(LinearElementParameters.fromObject(malformed).heightMeters, isNull);
    expect(
      OpeningElementParameters.fromObject(malformed).levelLocked,
      isTrue,
    );
  });

  test('element modules resolve one Inspector adapter route per family', () {
    const registry = BimElementInspectorRegistry.standard;
    expect(registry.keyForKind('wall'), BimElementInspectorKeys.wall);
    expect(registry.keyForKind('door'), BimElementInspectorKeys.opening);
    expect(registry.keyForKind('window'), BimElementInspectorKeys.opening);
    expect(registry.keyForKind('floor'), BimElementInspectorKeys.surface);
    expect(registry.keyForKind('slab'), BimElementInspectorKeys.surface);
    expect(registry.keyForKind('roof'), BimElementInspectorKeys.roof);
    expect(
        registry.keyForKind('unknown-kind'), BimElementInspectorKeys.generic);
  });

  testWidgets('shared side panel switches between browser and Inspector',
      (WidgetTester tester) async {
    var activeTab = WorkspaceSidePanelTab.projectBrowser;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SizedBox(
              width: 340,
              child: WorkspaceSidePanelTabs(
                activeTab: activeTab,
                onChanged: (tab) => setState(() => activeTab = tab),
              ),
            ),
          ),
        ),
      ),
    );

    expect(activeTab, WorkspaceSidePanelTab.projectBrowser);
    expect(find.text('Project Browser'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);

    await tester.tap(find.text('Inspector'));
    await tester.pump();
    expect(activeTab, WorkspaceSidePanelTab.inspector);
  });

  testWidgets('Inspector renders Level and Wall property surfaces',
      (WidgetTester tester) async {
    final parsed = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'Inspector property surface test',
    ).scene!;
    const level = RenderSceneLevel(
      levelId: 1,
      name: 'Level 1',
      elevationMeters: 0,
      defaultWallHeightMeters: 3,
    );
    final scene = RenderScene(
      sceneVersion: parsed.sceneVersion,
      units: parsed.units,
      coordinateSystem: parsed.coordinateSystem,
      objectCount: parsed.objectCount,
      vertexCount: parsed.vertexCount,
      indexCount: parsed.indexCount,
      bounds: parsed.bounds,
      objects: parsed.objects,
      levels: const <RenderSceneLevel>[level],
      materials: parsed.materials,
      sections: parsed.sections,
      source: parsed.source,
      diagnostics: parsed.diagnostics,
    );
    final wall = scene.objects.firstWhere((object) => object.kindKey == 'wall');
    final commands = AuthoringCommandService(
      repository: () => null,
      creationGateway: () => null,
      engineEnabled: () => false,
    );

    Widget editor(InspectorTarget target) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PropertyEditor(
                scene: scene,
                target: target,
                commands: commands,
                units: const ProjectUnitSettings.defaults(),
                onApplied: (result, message) async {},
                onClearSelection: () {},
                viewRangeMeters: 2,
                onViewRangeChanged: (value) async {},
                showPlanViewRange: false,
                activePlanLevel: level,
              ),
            ),
          ),
        );

    await tester.pumpWidget(editor(const InspectorTarget.level(level)));
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Elevation (m)'), findsOneWidget);
    expect(find.text('Default wall height (m)'), findsOneWidget);

    await tester.pumpWidget(editor(InspectorTarget.object(wall)));
    expect(find.text('Wall properties'), findsOneWidget);
    expect(find.text('Wall type'), findsOneWidget);
    expect(find.text('Layer count'), findsOneWidget);
    expect(find.text('Base level'), findsOneWidget);
    expect(find.text('Top level constraint'), findsOneWidget);
  });

  test('scene commit queue preserves mutation result order', () async {
    final queue = AsyncSerialQueue();
    final events = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    final first = queue.run(() async {
      events.add('wall-start');
      firstStarted.complete();
      await releaseFirst.future;
      events.add('wall-commit');
    });
    await firstStarted.future;

    final second = queue.run(() async {
      events.add('door-start');
    });
    expect(events, <String>['wall-start']);

    releaseFirst.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(events, <String>['wall-start', 'wall-commit', 'door-start']);
  });

  test('scene commit queue remains usable after a failed commit', () async {
    final queue = AsyncSerialQueue();

    await expectLater(
      queue.run<void>(() async {
        throw StateError('viewport commit failed');
      }),
      throwsA(isA<StateError>()),
    );

    var recovered = false;
    await queue.run<void>(() async {
      recovered = true;
    });
    expect(recovered, isTrue);
  });

  test(
    'viewport scene policy keeps 3D presentation separate from authoring',
    () {
      final scene = parseRenderSceneJson(
        File('test/fixtures/render_scene_sample.json').readAsStringSync(),
        source: 'viewport policy test',
      ).scene!;
      const policy = ViewerViewportScenePolicy(
        projectionMode: RenderSceneProjectionMode.isometric,
        activeLevelId: 1,
      );

      expect(policy.sceneForViewport(scene), same(scene));
      expect(policy.defaultDisplayStyle, RenderSceneDisplayStyle.solid);
      expect(
        policy.defaultVisibleKinds(scene),
        containsAll(<String>{'wall', 'door', 'window'}),
      );
      expect(
        policy.sanitizeVisibleKinds(
          visibleKinds: <String>{'wall', 'missing'},
          scene: scene,
        ),
        <String>{'wall'},
      );
    },
  );

  test(
    'view navigation coordinator serializes engine-backed transitions',
    () async {
      final coordinator = ViewNavigationCoordinator();
      final events = <String>[];
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();

      final first = coordinator.run(() async {
        events.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        events.add('first-end');
      });
      await firstStarted.future;

      final second = coordinator.run(() async {
        events.add('second');
      });
      expect(events, <String>['first-start']);

      releaseFirst.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(events, <String>['first-start', 'first-end', 'second']);
    },
  );

  test(
    'view navigation coordinator continues after a failed transition',
    () async {
      final coordinator = ViewNavigationCoordinator();
      final events = <String>[];

      final failed = coordinator.run(() async {
        events.add('failed');
        throw StateError('engine response failed');
      });
      await expectLater(failed, throwsA(isA<StateError>()));

      await coordinator.run(() async {
        events.add('recovered');
      });
      expect(events, <String>['failed', 'recovered']);
    },
  );

  test('viewport gesture module owns shared two-finger camera rules', () {
    final target = _RecordingCameraTarget();
    final gestures = ViewportGestureController();

    gestures.handleScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(40, 40)),
      target: target,
      nativeOwned: false,
    );
    gestures.handleScaleUpdate(
      ScaleUpdateDetails(
        scale: 1.5,
        localFocalPoint: const Offset(50, 45),
        pointerCount: 2,
      ),
      target: target,
      viewportSize: const Size(400, 300),
      nativeOwned: false,
    );

    expect(target.planPan, const Offset(10, 5));
    expect(target.planZoom, 1.5);
    expect(target.planZoomFocalPoint, const Offset(50, 45));
    expect(target.planZoomViewport, const Size(400, 300));

    final previousPanCount = target.panCount;
    gestures.handleScaleUpdate(
      ScaleUpdateDetails(
        scale: 2.0,
        localFocalPoint: const Offset(65, 55),
        pointerCount: 1,
      ),
      target: target,
      viewportSize: const Size(400, 300),
      nativeOwned: false,
    );
    expect(target.panCount, previousPanCount);
  });

  test('view workspace store keeps presentation metadata by view id', () {
    final store = ViewWorkspaceStore.standard();
    final tab = OpenedViewTab(
      id: 'floor-plan-1',
      label: 'Level 1 plan',
      kind: OpenedViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: 1,
    );

    expect(store.addTab(tab), isTrue);
    expect(store.tabById(tab.id), same(tab));
    expect(
      store.savePresentation(
        tab.id,
        displayStyle: RenderSceneDisplayStyle.shaded,
        shadowsEnabled: true,
      ),
      isTrue,
    );

    final reopened = store.withSavedPresentation(tab);
    expect(reopened.displayStyle, RenderSceneDisplayStyle.shaded);
    expect(reopened.shadowsEnabled, isTrue);
    expect(store.savedPresentations.keys, contains(tab.id));
    expect(store.removeTab(tab.id), isTrue);
    expect(store.tabById(tab.id), isNull);
    expect(store.savedPresentations, isEmpty);
  });

  test('view workspace defaults to the first level floor plan', () {
    final scene = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'view workspace defaults test',
    ).scene!;
    final store = ViewWorkspaceStore.standard();

    store.resetForScene(scene);

    final firstLevel = scene.levels.first;
    expect(
        store.activeTabId, ViewWorkspaceStore.floorPlanId(firstLevel.levelId));
    expect(store.tabs.first.kind, OpenedViewKind.floorPlan);
    expect(store.tabs.first.label, '${firstLevel.name} plan');
    expect(store.tabs.first.projectionMode, RenderSceneProjectionMode.topDown);
    expect(store.tabs, hasLength(1));
    expect(store.tabById(ViewWorkspaceStore.threeDViewId), isNull);
  });
}

final class _RecordingCameraTarget implements ViewportCameraTarget {
  @override
  RenderSceneProjectionMode projectionMode = RenderSceneProjectionMode.topDown;

  Offset? planPan;
  double? planZoom;
  Offset? planZoomFocalPoint;
  Size? planZoomViewport;
  int panCount = 0;

  @override
  void panPlanBy(Offset delta) {
    planPan = delta;
    panCount += 1;
  }

  @override
  void zoomPlanBy(double scaleDelta, {Offset? focalPoint, Size? viewportSize}) {
    planZoom = scaleDelta;
    planZoomFocalPoint = focalPoint;
    planZoomViewport = viewportSize;
  }

  @override
  void orbitBy(Offset delta, Size viewportSize) {}

  @override
  void panOrbitBy(Offset delta, Size viewportSize) {}

  @override
  void zoomOrbit(double scaleDelta) {}
}
