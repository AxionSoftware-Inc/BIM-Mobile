import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start screen depends on the preferences port, not file storage', () {
    final file = File(
      'apps/viewer_flutter/lib/src/features/projects/presentation/start_screen.dart',
    );
    final packageLocal = File(
      'lib/src/features/projects/presentation/start_screen.dart',
    );
    final source = (file.existsSync() ? file : packageLocal).readAsStringSync();

    expect(source, contains('StartScreenTemplatePreferencesRepository'));
    expect(source, contains('templatePreferencesRepository'));
    expect(source, isNot(contains('StartScreenTemplateStore')));
    expect(source, isNot(contains("infrastructure/templates")));
    expect(source, isNot(contains("import 'dart:io'")));
  });
}
