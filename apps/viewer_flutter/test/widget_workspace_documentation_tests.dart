part of 'widget_test.dart';

void registerWorkspaceDocumentationTests() {
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
    expect(find.text('Level 1 plan'), findsOneWidget);
    expect(find.text('3D View'), findsOneWidget);
    expect(find.byTooltip('Floor plan'), findsOneWidget);
    expect(find.byTooltip('3D view'), findsOneWidget);
    expect(find.byTooltip('Wall'), findsOneWidget);
    expect(find.byTooltip('Workspace actions'), findsOneWidget);
    await tester.tap(find.byTooltip('Workspace actions'));
    await tester.pumpAndSettle();
    expect(find.text('Documentation and PDF'), findsOneWidget);
  });

  testWidgets('wall draw modes are exposed inside the Inspector',
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

    await tester.tap(find.byTooltip('Wall'));
    await tester.pumpAndSettle();

    expect(find.text('Wall draw mode'), findsOneWidget);
    expect(find.byTooltip('Straight'), findsOneWidget);
    expect(find.byTooltip('Rectangle'), findsOneWidget);
    expect(find.byTooltip('Arc'), findsOneWidget);
    expect(find.text('Draw Walls'), findsNothing);
  });

  testWidgets('App launch shows the project start screen',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpWidget(const ViewerApp());
    await tester.pumpAndSettle();

    while (find.text('Continue').evaluate().isNotEmpty) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    if (find.text('Get started').evaluate().isNotEmpty) {
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Start a project'), findsOneWidget);
    expect(find.text('Open project'), findsOneWidget);
    expect(find.text('Create new'), findsOneWidget);
    expect(find.text('Default building'), findsOneWidget);
    expect(find.text('Residential tower'), findsOneWidget);
    expect(find.text('Residential campus'), findsOneWidget);
    expect(find.text('Wall #11'), findsNothing);

    final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
    expect(grids, hasLength(2));
    for (final grid in grids) {
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 5);
    }
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
    expect(find.text('Active tool'), findsNothing);
    expect(find.text('Select an element'), findsNothing);
    expect(find.text('Roof type'), findsOneWidget);
    expect(find.textContaining('Overhang'), findsOneWidget);
  });

  testWidgets('Boundary tool uses an explicit close-before-finish workflow',
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

    await tester.tap(find.byTooltip('Floor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boundary'));
    await tester.pumpAndSettle();

    expect(find.text('Close contour'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Trim / Extend'), findsNothing);
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
    final view = SheetViewReference(
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
    final floorPlan = SheetViewReference(
      id: 'floor-plan-1',
      label: 'Level 1 plan',
      kind: SheetViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: 1,
      displayStyle: RenderSceneDisplayStyle.shaded,
    );
    final threeD = SheetViewReference(
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
    expect(find.text('Sheet is empty'), findsOneWidget);
    expect(find.textContaining('Long-press a Floor Plan'), findsOneWidget);
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
