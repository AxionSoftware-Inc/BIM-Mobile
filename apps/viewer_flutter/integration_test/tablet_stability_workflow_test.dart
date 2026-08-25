import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viewer_flutter/src/viewer_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tablet workflow keeps plan, elevation, section and 3D gestures alive',
    (tester) async {
      await tester.pumpWidget(const ViewerApp());
      await tester.pumpAndSettle();

      // First-run onboarding is part of the production flow, but should not
      // hide the workspace smoke coverage after it has been acknowledged.
      while (find.text('Continue').evaluate().isNotEmpty) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      if (find.text('Get started').evaluate().isNotEmpty) {
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Create new'), findsOneWidget);
      await tester.tap(find.text('Create new'));
      await tester.pump(const Duration(seconds: 3));

      // The real Android runner uses the native engine and Filament platform
      // view. This smoke test keeps the start-screen -> workspace transition
      // and the existing 2D/3D controls covered on that exact runtime.
      expect(find.byTooltip('Floor plan'), findsOneWidget);
      expect(find.byTooltip('3D view'), findsOneWidget);

      await tester.tap(find.byTooltip('Floor plan'));
      await tester.pump(const Duration(milliseconds: 500));

      final viewport = find.bySemanticsLabel('2D drawing viewport');
      expect(viewport, findsOneWidget);
      await _drag(tester, viewport, const Offset(90, 12));
      await _twoFingerPan(tester, viewport, const Offset(42, 28));
      await _pinch(tester, viewport, 1.08);

      // Exercise every planar toolbar direction when it is present. This is
      // intentionally resilient to compact tablet widths where some chips
      // can be outside the horizontal scroll viewport.
      for (final label in <String>['North', 'South', 'East', 'West']) {
        final button = find.text(label);
        if (button.evaluate().isEmpty) continue;
        await tester.tap(button.first);
        await tester.pump(const Duration(milliseconds: 350));
        await _drag(tester, find.bySemanticsLabel('2D drawing viewport'),
            const Offset(-36, 18));
        await _twoFingerPan(
          tester,
          find.bySemanticsLabel('2D drawing viewport'),
          const Offset(-20, 18),
        );
      }

      final sectionEntries = find.textContaining('Section');
      if (sectionEntries.evaluate().length > 1) {
        await tester.tap(sectionEntries.last);
        await tester.pump(const Duration(milliseconds: 500));
        final sectionViewport = find.bySemanticsLabel('2D drawing viewport');
        expect(sectionViewport, findsOneWidget);
        await _drag(tester, sectionViewport, const Offset(28, -22));
        await _twoFingerPan(tester, sectionViewport, const Offset(24, -16));
        await _pinch(tester, sectionViewport, 1.06);
      }

      await tester.tap(find.byTooltip('3D view'));
      await tester.pump(const Duration(milliseconds: 500));

      final modelViewport = find.bySemanticsLabel('3D model viewport');
      expect(modelViewport, findsOneWidget);
      await _twoFingerPan(tester, modelViewport, const Offset(30, 24));
      await _pinch(tester, modelViewport, 0.92);
      expect(find.byTooltip('Fit view'), findsOneWidget);
    },
  );
}

Future<void> _drag(
  WidgetTester tester,
  Finder viewport,
  Offset delta,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(viewport),
    pointer: 1,
  );
  await gesture.moveBy(delta);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _twoFingerPan(
  WidgetTester tester,
  Finder viewport,
  Offset delta,
) async {
  final center = tester.getCenter(viewport);
  final first = await tester.startGesture(
    center + const Offset(-24, 0),
    pointer: 11,
  );
  final second = await tester.startGesture(
    center + const Offset(24, 0),
    pointer: 12,
  );
  await first.moveBy(delta);
  await second.moveBy(delta);
  await first.up();
  await second.up();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pinch(
  WidgetTester tester,
  Finder viewport,
  double scale,
) async {
  final center = tester.getCenter(viewport);
  const start = 28.0;
  final first = await tester.startGesture(
    center + const Offset(-start, 0),
    pointer: 21,
  );
  final second = await tester.startGesture(
    center + const Offset(start, 0),
    pointer: 22,
  );
  await first.moveTo(center + Offset(-start * scale, 0));
  await second.moveTo(center + Offset(start * scale, 0));
  await first.up();
  await second.up();
  await tester.pump(const Duration(milliseconds: 100));
}
