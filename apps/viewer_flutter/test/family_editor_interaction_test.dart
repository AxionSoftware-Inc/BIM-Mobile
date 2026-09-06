import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('family RenderScene adapter preserves physical XYZ dimensions', () {
    final family = FamilyDocument.starter(name: 'Viewport Family');
    final mesh = FamilyGeometryEvaluator.evaluateMesh(
      family,
      family.types.single,
    );
    final scene = FamilyRenderSceneAdapter.build(
      family,
      family.types.single,
      mesh: mesh,
    );

    expect(scene.objects, hasLength(1));
    expect(scene.objects.single.kindKey, 'proxy');
    expect(scene.objects.single.metadata['family_editor_preview'], true);
    expect(scene.bounds.width, closeTo(1.0, 1e-9));
    expect(scene.bounds.depth, closeTo(1.0, 1e-9));
    expect(scene.bounds.height, closeTo(1.0, 1e-9));
    expect(scene.indexCount % 3, 0);
    expect(scene.indexCount, greaterThanOrEqualTo(36));
  });

  test('authoring candidate scene exposes solids as independently pickable objects',
      () async {
    final starter = FamilyDocument.starter(name: 'Pickable Family');
    final base = starter.features.single;
    final moved = FamilyFeature(
      id: 'moved-box',
      kind: FamilyFeatureKind.transform,
      label: 'Moved box',
      inputs: <String>[base.id],
      parameters: const <String, Object?>{
        'translationX': 0.4,
        'translationY': 0.0,
        'translationZ': 0.0,
        'rotationZ': 0.0,
        'scale': 1.0,
      },
    );
    final document = starter.copyWith(
      features: <FamilyFeature>[base, moved],
    );

    final scene = await FamilyAuthoringSceneBuilder.buildCandidates(
      document,
      document.types.single,
      featureIds: <String>{base.id, moved.id},
    );

    expect(scene.objects, hasLength(2));
    final featureIds = scene.objects
        .map((object) => object.metadata['family_feature_id'])
        .toSet();
    expect(featureIds, <Object?>{base.id, moved.id});
    expect(scene.objects.every((object) => object.selectable), true);
    expect(
      scene.objects.every(
        (object) => object.metadata['family_candidate'] == true,
      ),
      true,
    );
  });

  group('Family Editor V5 direct manipulation workflow', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: FamilyEditorV2Page()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('legacy route opens one V5 workspace with project viewport tools',
        (tester) async {
      await pumpEditor(tester);

      expect(find.byType(FamilyAuthoringViewport), findsOneWidget);
      expect(find.text('Project viewport · Family'), findsOneWidget);
      expect(find.text('CREATE'), findsOneWidget);
      expect(find.text('MODIFY'), findsOneWidget);
      expect(find.text('COMBINE'), findsOneWidget);
      expect(find.text('INSERT'), findsOneWidget);
      expect(find.text('Sketch'), findsOneWidget);
      expect(find.text('Extrude'), findsOneWidget);
      expect(find.text('Revolve'), findsOneWidget);
      expect(find.text('Move'), findsWidgets);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Scale'), findsOneWidget);
      expect(find.text('Union'), findsOneWidget);
      expect(find.text('Subtract'), findsOneWidget);
      expect(find.text('Simple'), findsNothing);
      expect(find.text('Advanced'), findsNothing);

      // History is optional in V5 rather than the primary editing surface.
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.byTooltip('Model history'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsWidgets);
      expect(find.text('Box'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rectangle sketch becomes live Extrude and applies from UI',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Sketch').first);
      await tester.pumpAndSettle();
      expect(find.byType(FamilySketchCanvas), findsOneWidget);
      expect(find.text('Rectangle'), findsOneWidget);
      expect(
        find.textContaining('Project plan viewport'),
        findsOneWidget,
      );

      await tester.tap(find.text('Rectangle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyAuthoringViewport), findsOneWidget);

      await tester.tap(find.text('Extrude').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('live preview'), findsWidgets);
      expect(find.text('Apply Extrude'), findsOneWidget);

      // The direct model-space depth handle must exist in addition to precise
      // numeric input. Dragging it changes only the live draft until Apply.
      final depthHandle = find.descendant(
        of: find.byType(FamilyAuthoringViewport),
        matching: find.text('D'),
      );
      expect(depthHandle, findsOneWidget);
      await tester.drag(depthHandle, const Offset(32, -12));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Extrude'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Extrude applied.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Model history'));
      await tester.pumpAndSettle();
      expect(find.text('Extrude'), findsWidgets);
    });

    testWidgets('Move uses a viewport gizmo and commits one direct drag step',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Move').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Drag the gizmo on the model'),
        findsOneWidget,
      );

      final xHandle = find.descendant(
        of: find.byType(FamilyAuthoringViewport),
        matching: find.text('X'),
      );
      expect(xHandle, findsOneWidget);
      await tester.drag(xHandle, const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Move committed.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Done / leave tool'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Model history'));
      await tester.pumpAndSettle();
      expect(find.text('Transform'), findsWidgets);
    });

    testWidgets('Subtract enters viewport Base and Tool pick workflow',
        (tester) async {
      await pumpEditor(tester);

      // Make a second solid through the same direct Move tool so Boolean has
      // two independently selectable candidates.
      await tester.tap(find.text('Move').first);
      await tester.pumpAndSettle();
      final xHandle = find.descendant(
        of: find.byType(FamilyAuthoringViewport),
        matching: find.text('X'),
      );
      await tester.drag(xHandle, const Offset(55, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done / leave tool'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Subtract').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Base − Tool'), findsOneWidget);
      expect(find.textContaining('Tool · tap in viewport'), findsOneWidget);
      expect(find.text('Pick a solid in the viewport'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard Enter, Escape and Cmd-Z follow editor command semantics',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Sketch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rectangle'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(FamilyAuthoringViewport), findsOneWidget);
      expect(find.textContaining('Profile ready'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Model history'));
      await tester.pumpAndSettle();
      expect(find.text('Profile 1'), findsNothing);
      expect(find.text('Box'), findsWidgets);

      await tester.tap(find.byTooltip('Model history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move').first);
      await tester.pumpAndSettle();
      expect(find.text('Done / leave tool'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Done / leave tool'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
