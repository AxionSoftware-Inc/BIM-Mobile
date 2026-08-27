import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/telemetry_service.dart';
import 'src/viewer_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await AppTelemetry.initialize(
    appRunner: () {
      AppTelemetry.track('app_started');
      runApp(const ViewerApp(preferEngineBackedBundledSample: true));
    },
  );
}
