part of 'widget_test.dart';

void registerWallTypeTests() {
  test('floor type catalog preserves surface key and layered thickness', () {
    final result = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 2,
        'floor_types': <Object?>[
          <String, Object?>{
            'id': 24,
            'name': 'Asphalt Floor',
            'surface_key': 'asphalt',
            'total_thickness_meters': 0.20,
            'layers': <Object?>[
              <String, Object?>{
                'material_id': 7,
                'thickness_meters': 0.20,
                'function': 0,
              },
            ],
          },
        ],
        'objects': <Object?>[],
      }),
      source: 'floor type catalog test',
    );
    final scene = result.scene!;
    expect(scene.floorTypes, hasLength(1));
    expect(scene.floorTypes.single.surfaceKind, FloorSurfaceKind.asphalt);
    expect(scene.floorTypes.single.totalThicknessMeters, 0.20);
    expect(scene.floorTypes.single.layers, hasLength(1));
  });

  test('wall type catalog preserves native layers and material references', () {
    final result = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 1,
        'levels': <Object?>[],
        'materials': <Object?>[
          <String, Object?>{
            'id': 7,
            'name': 'Template Glass',
            'category': '3',
            'display_color': '#A8D8E8',
          },
        ],
        'wall_types': <Object?>[
          <String, Object?>{
            'id': 19,
            'name': 'Exterior Glass Wall',
            'category': 'Exterior',
            'total_thickness_meters': 0.215,
            'core_start_layer': -1,
            'core_end_layer': -1,
            'layers': <Object?>[
              <String, Object?>{
                'material_id': 7,
                'thickness_meters': 0.12,
                'function': 0,
                'priority': 100,
                'structural': false,
                'side': 0,
                'wraps_openings': true,
                'wraps_ends': true,
              },
              <String, Object?>{
                'material_id': 7,
                'thickness_meters': 0.095,
                'function': 3,
                'priority': 70,
                'structural': false,
                'side': 0,
                'wraps_openings': true,
                'wraps_ends': true,
              },
            ],
          },
        ],
        'objects': <Object?>[],
      }),
      source: 'wall type catalog test',
    );
    final scene = result.scene!;
    expect(scene.wallTypes, hasLength(1));
    final wallType = scene.wallTypes.single;
    expect(wallType.name, 'Exterior Glass Wall');
    expect(wallType.category, WallTypeCategory.exterior);
    expect(wallType.layers, hasLength(2));
    expect(wallType.layers.first.function, WallLayerFunction.core);
    expect(scene.materialById(wallType.layers.first.materialId)?.name,
        'Template Glass');
  });

  testWidgets('wall Inspector shows type selector and mapped materials',
      (WidgetTester tester) async {
    final parsed = parseRenderSceneJson(
      File('test/fixtures/render_scene_sample.json').readAsStringSync(),
      source: 'wall Inspector type test',
    ).scene!;
    final wallSource =
        parsed.objects.firstWhere((object) => object.kindKey == 'wall');
    final wall = RenderSceneObject(
      elementId: wallSource.elementId,
      kind: wallSource.kind,
      levelId: wallSource.levelId,
      selectable: wallSource.selectable,
      visibleByDefault: wallSource.visibleByDefault,
      revision: wallSource.revision,
      bounds: wallSource.bounds,
      mesh: wallSource.mesh,
      materialCategory: wallSource.materialCategory,
      metadata: <String, Object?>{
        ...wallSource.metadata,
        'wall_type_id': '101',
      },
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
      levels: parsed.levels,
      materials: parsed.materials,
      wallTypes: const <WallTypeDefinition>[
        WallTypeDefinition(
          id: 101,
          name: 'Exterior Glass Wall',
          category: WallTypeCategory.exterior,
          totalThicknessMeters: 0.12,
          coreStartLayer: -1,
          coreEndLayer: -1,
          layers: <WallTypeLayerDefinition>[
            WallTypeLayerDefinition(
              materialId: 1,
              thicknessMeters: 0.12,
              function: WallLayerFunction.core,
              priority: 100,
              structural: false,
              side: WallLayerSide.unspecified,
              wrapsOpenings: true,
              wrapsEnds: true,
            ),
          ],
        ),
      ],
      sections: parsed.sections,
      source: parsed.source,
      diagnostics: parsed.diagnostics,
    );
    final commands = AuthoringCommandService(
      repository: () => null,
      creationGateway: () => null,
      engineEnabled: () => false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropertyEditor(
              scene: scene,
              target: InspectorTarget.object(wall),
              commands: commands,
              onApplied: (result, message) async {},
              onClearSelection: () {},
              viewRangeMeters: 2,
              onViewRangeChanged: (value) async {},
              showPlanViewRange: false,
              activePlanLevel: scene.levels.first,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Wall type'), findsOneWidget);
    expect(find.textContaining('Exterior Glass Wall'), findsOneWidget);
    expect(find.textContaining('Assembly'), findsOneWidget);
    expect(find.textContaining('layers'), findsOneWidget);
  });
}
