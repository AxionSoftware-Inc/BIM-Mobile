import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('family RenderScene adapter preserves physical XYZ dimensions', () {
    final family = FamilyDocument.starter(name: 'Viewport Family');
    final mesh = FamilyGeometryEvaluator.evaluateMesh(family, family.types.single);
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

  group('Family Editor V4 screen workflow', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('legacy route opens task-oriented V4 with shared project viewport',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: FamilyEditorV2Page()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Family Editor'), findsOneWidget);
      expect(find.byType(FamilyAuthoringViewport), findsOneWidget);
      expect(find.text('Project viewport · Family preview'), findsOneWidget);
      expect(find.text('Start here'), findsOneWidget);
      expect(find.text('History · tap a feature to inspect or edit it'), findsOneWidget);
      expect(find.text('Simple'), findsNothing);
      expect(find.text('Advanced'), findsNothing);
    });

    testWidgets('profile can be drawn, closed and extruded entirely from UI',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: FamilyEditorV2Page()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.polyline_outlined).first);
      await tester.pumpAndSettle();
      expect(find.byType(FamilySketchCanvas), findsOneWidget);
      expect(find.textContaining('Sketch mode ·'), findsOneWidget);

      final rect = tester.getRect(find.byType(FamilySketchCanvas));
      await tester.tapAt(Offset(rect.left + rect.width * 0.30, rect.top + rect.height * 0.32));
      await tester.pump();
      await tester.tapAt(Offset(rect.left + rect.width * 0.70, rect.top + rect.height * 0.32));
      await tester.pump();
      await tester.tapAt(Offset(rect.left + rect.width * 0.70, rect.top + rect.height * 0.68));
      await tester.pump();
      await tester.tapAt(Offset(rect.left + rect.width * 0.30, rect.top + rect.height * 0.68));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close profile').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('4 points · Closed'), findsOneWidget);

      await tester.tap(find.text('Finish').first);
      await tester.pumpAndSettle();
      expect(find.byType(FamilyAuthoringViewport), findsOneWidget);

      await tester.tap(find.byIcon(Icons.height).first);
      await tester.pumpAndSettle();
      expect(find.text('1 · Profile'), findsOneWidget);
      expect(find.text('2 · Depth'), findsOneWidget);
      expect(find.text('3 · Create Extrude'), findsOneWidget);

      await tester.tap(find.text('3 · Create Extrude'));
      await tester.pumpAndSettle();
      expect(find.text('Extrude'), findsWidgets);
      expect(find.textContaining('Extrude created.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('transform creates second solid and subtract is actionable inline',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: FamilyEditorV2Page()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.open_with_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Create Transform'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'X'), '0.25');
      await tester.tap(find.text('Create Transform'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Transform created.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.call_split_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('1 · Base solid'), findsOneWidget);
      expect(find.text('2 · Tool to remove'), findsOneWidget);
      expect(find.text('3 · Create Subtract'), findsOneWidget);

      await tester.tap(find.text('3 · Create Subtract'));
      await tester.pumpAndSettle();
      expect(find.text('Subtract'), findsWidgets);
      expect(find.textContaining('Subtract created.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
