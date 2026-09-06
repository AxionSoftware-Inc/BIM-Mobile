import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  testWidgets('Type matrix edits a non-current Family Type value', (tester) async {
    var document = FamilyDocument.starter(name: 'Matrix');
    final currentTypeId = document.types.single.id;
    document = FamilyParameterAuthoring.duplicateType(
      document,
      sourceTypeId: currentTypeId,
      name: 'Large',
    );
    final largeTypeId = document.types.singleWhere((type) => type.name == 'Large').id;
    document = FamilyParameterAuthoring.setTypeValue(
      document,
      typeId: largeTypeId,
      parameterId: 'width',
      value: 2.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 1000,
              child: FamilyTypeMatrixPanel(
                document: document,
                currentTypeId: currentTypeId,
                onChanged: (next) => setState(() => document = next),
                onStatus: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Family Type matrix'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('2 m'), findsOneWidget);

    await tester.tap(find.text('2 m'));
    await tester.pumpAndSettle();

    expect(find.text('Large · Width'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '3.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(
      document.types.singleWhere((type) => type.id == largeTypeId).values['width'],
      3.5,
    );
    expect(find.text('3.5 m'), findsOneWidget);
  });

  testWidgets('Type matrix exposes custom parameters on demand', (tester) async {
    var document = FamilyDocument.starter(name: 'Custom matrix');
    document = FamilyParameterAuthoring.addParameter(
      document,
      label: 'Seat Depth',
      kind: FamilyParameterKind.length,
      defaultValue: 0.45,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 1000,
              child: FamilyTypeMatrixPanel(
                document: document,
                currentTypeId: document.types.first.id,
                onChanged: (next) => setState(() => document = next),
                onStatus: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Seat Depth'), findsNothing);
    await tester.tap(find.text('Core dimensions'));
    await tester.pumpAndSettle();
    expect(find.text('Seat Depth'), findsOneWidget);
    expect(find.text('0.45 m'), findsOneWidget);
  });
}
