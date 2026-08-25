import 'package:flutter/material.dart';

import 'src/telemetry_service.dart';
import 'src/viewer_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTelemetry.initialize(
    appRunner: () {
      AppTelemetry.track('app_started');
      runApp(const ViewerApp(preferEngineBackedBundledSample: true));
    },
  );
}
