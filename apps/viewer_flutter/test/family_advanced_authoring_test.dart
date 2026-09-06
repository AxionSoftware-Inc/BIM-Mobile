import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  group('Family V5 advanced authoring', () {
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

    testWidgets(
      'Sketch advanced panel exposes parameters, types and geometry constraints',
      (tester) async {
        await pumpEditor(tester);

        await tester.tap(find.text('Sketch').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Constraints'));
        await tester.pumpAndSettle();

        expect(find.text('Family parameters'), findsOneWidget);
        expect(find.text('Reference planes & constraints'), findsOneWidget);
        expect(find.byTooltip('Add parameter'), findsOneWidget);
        expect(find.text('Duplicate type'), findsOneWidget);
        expect(find.text('Rename type'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('custom parameter can be authored from the V5 UI',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Sketch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Constraints'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add parameter'));
      await tester.pumpAndSettle();
      expect(find.text('Add Family parameter'), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(5));
      await tester.enterText(fields.at(0), 'Seat Height');
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();

      expect(find.text('Seat Height'), findsOneWidget);
      expect(find.textContaining('Parameter Seat Height added.'), findsOneWidget);
      expect(find.textContaining('4 parameters'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('named Family Type can be duplicated from the V5 UI',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Sketch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Constraints'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duplicate type'));
      await tester.pumpAndSettle();
      expect(find.text('Duplicate Family Type'), findsOneWidget);

      final field = find.byType(TextField).last;
      await tester.enterText(field, 'Large');
      await tester.tap(find.text('Apply').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Family Type Large created.'), findsOneWidget);
      expect(find.textContaining('2 types'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
