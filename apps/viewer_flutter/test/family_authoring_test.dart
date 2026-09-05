import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';
import 'package:viewer_flutter/src/family_authoring/built_in_family_catalog.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/viewer_viewport_scene_policy.dart';

void main() {
  test('starter family is an independent parametric document', () {
    final family = FamilyDocument.starter(
      name: 'Column Family',
      category: FamilyCategory.column,
    );
    final restored = FamilyDocument.fromJson(family.toJson());

    expect(restored, isNotNull);
    expect(restored!.name, 'Column Family');
    expect(restored.category, FamilyCategory.column);
    expect(
      restored.parameters.map((item) => item.id),
      containsAll(<String>['width', 'depth', 'height']),
    );
    expect(restored.types.single.values['width'], 1.0);
    expect(restored.features.single.kind, FamilyFeatureKind.box);
    expect(restored.features.single.parameters['width'], 'width');
  });

  test('profile and extrude remain independent from project geometry', () {
    final starter = FamilyDocument.starter();
    const sketch = FamilySketch(
      id: 'sketch-triangle',
      name: 'Triangle profile',
      plane: FamilySketchPlane.xy,
      closed: true,
      points: <FamilySketchPoint>[
        FamilySketchPoint(x: -1, y: 0),
        FamilySketchPoint(x: 1, y: 0),
        FamilySketchPoint(x: 0, y: 2),
      ],
    );
    final document = starter.copyWith(
      sketches: const <FamilySketch>[sketch],
      parameters: <FamilyParameterDefinition>[
        ...starter.parameters,
        const FamilyParameterDefinition(
          id: 'extrusionDepth',
          label: 'Extrusion depth',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
        ),
      ],
      types: <FamilyTypeDefinition>[
        starter.types.single.copyWith(
          values: <String, Object?>{
            ...starter.types.single.values,
            'extrusionDepth': 2.5,
          },
        ),
      ],
      features: <FamilyFeature>[
        ...starter.features,
        const FamilyFeature(
          id: 'feature-profile',
          kind: FamilyFeatureKind.profile,
          inputs: <String>['sketch-triangle'],
          parameters: <String, Object?>{'profileId': 'sketch-triangle'},
        ),
        const FamilyFeature(
          id: 'feature-extrude',
          kind: FamilyFeatureKind.extrude,
          inputs: <String>['sketch-triangle'],
          parameters: <String, Object?>{
            'profileId': 'sketch-triangle',
            'depth': 'extrusionDepth',
          },
        ),
      ],
    );
    final restored = FamilyDocument.fromJson(document.toJson());

    expect(restored, isNotNull);
    final shape = FamilyGeometryEvaluator.evaluate(
      restored!,
      restored.types.single,
    );
    expect(shape.source, 'Triangle profile');
    expect(shape.profile, hasLength(3));
    expect(shape.depth, 2.5);
  });

  test('family type dimensions drive curated mesh geometry', () {
    final family = BuiltInFamilyCatalog.families.last;
    final sourceType = family.types.single;
    final type = sourceType.copyWith(values: <String, Object?>{
      ...sourceType.values,
      'width': 3.2,
      'depth': 1.1,
      'height': 2.0,
    });
    final mesh = FamilyGeometryEvaluator.evaluateMesh(family, type);
    final xs = mesh.vertices.map((vertex) => vertex.x);
    final ys = mesh.vertices.map((vertex) => vertex.y);
    final zs = mesh.vertices.map((vertex) => vertex.z);
    expect(
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
        closeTo(3.2, 1e-9));
    expect(
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        closeTo(2.0, 1e-9));
    expect(
        zs.reduce((a, b) => a > b ? a : b) - zs.reduce((a, b) => a < b ? a : b),
        closeTo(1.1, 1e-9));
  });

  test('family plan symbol is compact and independent from the 3D mesh', () {
    final family = BuiltInFamilyCatalog.families.last;
    final svg = FamilyPlanSymbolGenerator.svgFor(family, family.types.single);
    final paths = FamilyPlanSymbolPath.parse(svg);

    expect(svg, contains('<svg'));
    expect(svg, contains('data-family-category="furniture"'));
    expect(paths, isNotEmpty);
    expect(paths.expand((path) => path.commands), isNotEmpty);
    // The plan contract contains strokes only; no family feature vertices are
    // embedded in the instance symbol.
    expect(svg, isNot(contains('vertices')));
  });

  test('floor-plan scene keeps family bounds and SVG but drops its 3D mesh',
      () {
    final family = FamilyDocument.starter(
      name: 'Plan Column',
      category: FamilyCategory.column,
    );
    final svg = FamilyPlanSymbolGenerator.svgFor(family, family.types.single);
    final loaded = parseRenderSceneJson(jsonEncode(<String, Object?>{
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
      'materials': <Object?>[],
      'sections': <Object?>[],
      'objects': <Object?>[
        <String, Object?>{
          'element_id': 7,
          'kind': 'Column',
          'level_id': 1,
          'bounds': <String, Object?>{
            'min': <String, double>{'x': 0, 'y': 0, 'z': 0},
            'max': <String, double>{'x': 1, 'y': 1, 'z': 2},
          },
          'mesh': <String, Object?>{
            'positions': <Object?>[
              <String, double>{'x': 0, 'y': 0, 'z': 0},
              <String, double>{'x': 1, 'y': 0, 'z': 0},
              <String, double>{'x': 0, 'y': 1, 'z': 0},
            ],
            'indices': <int>[0, 1, 2],
          },
          'material_category': 'generic',
          'metadata': <String, Object?>{
            'family_asset_id': 'plan-column',
            'family_plan_svg': svg,
          },
        },
      ],
    }));
    final source = loaded.scene!;
    final plan = const ViewerViewportScenePolicy(
      projectionMode: RenderSceneProjectionMode.topDown,
      activeLevelId: 1,
    ).sceneForViewport(source);

    expect(source.objects.single.mesh.hasGeometry, isTrue);
    expect(plan.objects.single.mesh.hasGeometry, isFalse);
    expect(plan.objects.single.bounds.width, closeTo(1.0, 1e-9));
    expect(plan.objects.single.metadata['family_plan_svg'], svg);
  });

  test('family validation rejects an open profile used by a solid', () {
    final starter = FamilyDocument.starter();
    final document = starter.copyWith(
      sketches: const <FamilySketch>[
        FamilySketch(
          id: 'sketch-open',
          name: 'Open profile',
          plane: FamilySketchPlane.xy,
          points: <FamilySketchPoint>[
            FamilySketchPoint(x: 0, y: 0),
            FamilySketchPoint(x: 1, y: 0),
            FamilySketchPoint(x: 1, y: 1),
          ],
        ),
      ],
      features: <FamilyFeature>[
        ...starter.features,
        const FamilyFeature(
          id: 'feature-open-extrude',
          kind: FamilyFeatureKind.extrude,
          inputs: <String>['sketch-open'],
          parameters: <String, Object?>{'profileId': 'sketch-open'},
        ),
      ],
    );
    final validation = FamilyDocumentValidator.validate(document);

    expect(validation.isValid, isFalse);
    expect(validation.errors, contains('extrude requires a closed profile'));
  });

  test('family evaluator emits isolated box, extrude and revolve meshes', () {
    final starter = FamilyDocument.starter();
    final box = FamilyGeometryEvaluator.evaluateMesh(
      starter,
      starter.types.single,
    );
    expect(box.vertices, hasLength(8));
    expect(box.faces, hasLength(6));

    const sketch = FamilySketch(
      id: 'sketch-mesh',
      name: 'Mesh profile',
      plane: FamilySketchPlane.xy,
      closed: true,
      points: <FamilySketchPoint>[
        FamilySketchPoint(x: 0, y: 0),
        FamilySketchPoint(x: 1, y: 0),
        FamilySketchPoint(x: 0.5, y: 2),
      ],
    );
    final extrude = starter.copyWith(
      sketches: const <FamilySketch>[sketch],
      features: <FamilyFeature>[
        ...starter.features,
        const FamilyFeature(
          id: 'feature-extrude-mesh',
          kind: FamilyFeatureKind.extrude,
          label: 'Extrude mesh profile',
          parameters: <String, Object?>{
            'profileId': 'sketch-mesh',
            'depth': 2.0,
          },
        ),
      ],
    );
    final extruded = FamilyGeometryEvaluator.evaluateMesh(
      extrude,
      extrude.types.single,
    );
    expect(extruded.vertices, hasLength(6));
    expect(extruded.faces, hasLength(5));

    final revolve = extrude.copyWith(features: <FamilyFeature>[
      ...extrude.features,
      const FamilyFeature(
        id: 'feature-revolve-mesh',
        kind: FamilyFeatureKind.revolve,
        label: 'Revolve mesh profile',
        parameters: <String, Object?>{'profileId': 'sketch-mesh'},
      ),
    ]);
    final revolved = FamilyGeometryEvaluator.evaluateMesh(
      revolve,
      revolve.types.single,
    );
    expect(revolved.vertices, hasLength(72));
    expect(revolved.faces, hasLength(48));

    final halfRevolve = extrude.copyWith(features: <FamilyFeature>[
      ...extrude.features,
      const FamilyFeature(
        id: 'feature-half-revolve-mesh',
        kind: FamilyFeatureKind.revolve,
        label: 'Half revolve mesh profile',
        parameters: <String, Object?>{
          'profileId': 'sketch-mesh',
          'angle': 180.0,
        },
      ),
    ]);
    final halfRevolved = FamilyGeometryEvaluator.evaluateMesh(
      halfRevolve,
      halfRevolve.types.single,
    );
    expect(halfRevolved.vertices, hasLength(39));
    expect(halfRevolved.faces, hasLength(24));
  });

  test('curated exterior column and cabinet contain usable project meshes', () {
    final families = BuiltInFamilyCatalog.families;
    expect(families, hasLength(2));

    final column = families.firstWhere(
      (family) => family.category == FamilyCategory.column,
    );
    final cabinet = families.firstWhere(
      (family) => family.category == FamilyCategory.furniture,
    );
    expect(FamilyDocumentValidator.validate(column).isValid, isTrue);
    expect(FamilyDocumentValidator.validate(cabinet).isValid, isTrue);

    final columnMesh = FamilyGeometryEvaluator.evaluateMesh(
      column,
      column.types.single,
    );
    final cabinetMesh = FamilyGeometryEvaluator.evaluateMesh(
      cabinet,
      cabinet.types.single,
    );
    expect(columnMesh.vertices.length, greaterThan(100));
    expect(columnMesh.faces.length, greaterThan(100));
    expect(cabinetMesh.vertices.length, 104);
    expect(cabinetMesh.faces.length, 78);
    expect(cabinetMesh.isApproximate, isFalse);
  });

  testWidgets('Create family opens the detachable authoring page',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => FamilyAuthoringModule.createFamily(context),
              child: const Text('Create family'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create family'));
    await tester.pumpAndSettle();

    expect(find.text('Family Editor'), findsOneWidget);
    expect(find.text('Family type'), findsOneWidget);
    expect(find.text('Feature graph'), findsOneWidget);
    final featureGraphTile = find.ancestor(
      of: find.text('Feature graph'),
      matching: find.byType(ExpansionTile),
    );
    await tester.ensureVisible(featureGraphTile);
    await tester.tap(featureGraphTile);
    await tester.pumpAndSettle();
    expect(find.text('Box solid'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use in project'));
    await tester.pumpAndSettle();
    expect(find.text('Use this family in a project'), findsOneWidget);
    expect(find.textContaining('Add family to project'), findsNWidgets(2));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  });

  testWidgets('profile canvas closes and creates a parametric extrude',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: FamilyEditorPage()));
    await tester.pumpAndSettle();

    final profile = find.widgetWithText(OutlinedButton, 'Profile');
    await tester.tap(profile);
    await tester.pumpAndSettle();
    final canvas = find.byType(FamilySketchCanvas);
    expect(canvas, findsOneWidget);
    final rect = tester.getRect(canvas);
    for (final point in <Offset>[
      Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.70),
      Offset(rect.left + rect.width * 0.75, rect.top + rect.height * 0.70),
      Offset(rect.left + rect.width * 0.50, rect.top + rect.height * 0.25),
    ]) {
      await tester.tapAt(point);
      await tester.pump();
    }

    expect(find.text('Profile 1 · 3 points'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pump();
    expect(
        find.text('Closed profile · drag points to reshape'), findsOneWidget);

    final extrude = find.widgetWithText(OutlinedButton, 'Extrude');
    await tester.ensureVisible(extrude);
    await tester.pumpAndSettle();
    await tester.tap(extrude);
    await tester.pump();
    final featureGraphTile = find.ancestor(
      of: find.text('Feature graph'),
      matching: find.byType(ExpansionTile),
    );
    await tester.ensureVisible(featureGraphTile);
    await tester.tap(featureGraphTile);
    await tester.pumpAndSettle();
    expect(find.text('Extrude Profile 1'), findsOneWidget);
    expect(find.text('Extrusion depth'), findsOneWidget);
  });
}
