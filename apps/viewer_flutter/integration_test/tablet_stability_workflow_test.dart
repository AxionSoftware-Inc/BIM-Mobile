import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viewer_flutter/src/viewer_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tablet workflow opens a blank project and preserves view navigation',
    (tester) async {
      await tester.pumpWidget(const ViewerApp());
      await tester.pumpAndSettle();

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
      await tester.tap(find.byTooltip('3D view'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byTooltip('Fit view'), findsOneWidget);
    },
  );
}
