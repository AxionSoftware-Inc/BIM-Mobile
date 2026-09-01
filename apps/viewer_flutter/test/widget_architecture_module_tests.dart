part of 'widget_test.dart';

void registerArchitectureModuleTests() {
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
