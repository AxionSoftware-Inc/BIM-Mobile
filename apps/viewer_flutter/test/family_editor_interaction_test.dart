import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  testWidgets('family preview supports orbit gestures and reset controls',
      (tester) async {
    final family = FamilyDocument.starter(name: 'Orbit Family');
    final mesh = FamilyGeometryEvaluator.evaluateMesh(
      family,
      family.types.single,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 420,
            child: FamilyInteractivePreview(
              mesh: mesh,
              lineColor: Colors.black,
              fillColor: Colors.blue.withValues(alpha: 0.2),
              background: Colors.white,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Drag: orbit'), findsOneWidget);
    await tester.drag(find.byType(FamilyInteractivePreview), const Offset(80, 45));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byTooltip('Reset 3D view'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('boolean feature exposes editable ordered operands',
      (tester) async {
    final starter = FamilyDocument.starter(name: 'Boolean Family');
    final base = starter.features.single;
    final moved = FamilyFeature(
      id: 'moved-box',
      kind: FamilyFeatureKind.transform,
      label: 'Moved box',
      inputs: <String>[base.id],
      parameters: const <String, Object?>{
        'translationX': 0.3,
        'translationY': 0.0,
        'translationZ': 0.0,
        'rotationZ': 0.0,
        'scale': 0.6,
      },
    );
    final subtract = FamilyFeature(
      id: 'subtract',
      kind: FamilyFeatureKind.booleanSubtract,
      label: 'Cut opening',
      inputs: <String>[base.id, moved.id],
      parameters: const <String, Object?>{'operation': 'booleanSubtract'},
    );
    final document = starter.copyWith(
      features: <FamilyFeature>[base, moved, subtract],
    );

    FamilyDocument? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FamilyFeatureWorkbench(
              document: document,
              selectedFeatureId: subtract.id,
              onSelected: (_) {},
              onChanged: (next, _) => changed = next,
              onStatus: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cut opening'), findsWidgets);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Base / left'), findsOneWidget);
    expect(find.text('Tool / right'), findsOneWidget);
    expect(find.byTooltip('Swap operands'), findsOneWidget);

    await tester.tap(find.byTooltip('Swap operands'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    final edited = changed!.features.last;
    expect(edited.inputs, <String>[moved.id, base.id]);
  });

  testWidgets('legacy FamilyEditorV2 route opens interactive V3 shell',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FamilyEditorV2Page()),
    );
    await tester.pump();

    expect(find.text('Family Editor'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.textContaining('Drag: orbit'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Geometry'), findsOneWidget);
    expect(find.text('Feature graph'), findsOneWidget);
  });
}
