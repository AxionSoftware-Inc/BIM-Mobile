import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/app/settings/app_settings_model.dart';

void main() {
  group('ViewerAppSettings', () {
    test('defaults stay semantic and renderer-independent', () {
      const settings = ViewerAppSettings.defaults();

      expect(settings.appTheme, AppThemeMode.light);
      expect(settings.viewportTheme, AppViewportTheme.light);
      expect(settings.onboardingComplete, isFalse);
      expect(settings.largeTouchTargets, isTrue);
      expect(settings.highContrast, isFalse);
      expect(settings.textScale, 1.0);
    });

    test('viewport theme serialization remains backward compatible', () {
      for (final theme in AppViewportTheme.values) {
        final decoded = ViewerAppSettings.fromJson(<String, Object?>{
          'appTheme': AppThemeMode.standardDark.name,
          'viewportTheme': theme.name,
          'onboardingComplete': true,
          'largeTouchTargets': false,
          'highContrast': true,
          'textScale': 1.2,
        });

        expect(decoded.viewportTheme, theme);
        expect(decoded.toJson()['viewportTheme'], theme.name);
      }
    });

    test('unknown persisted viewport theme falls back safely', () {
      final decoded = ViewerAppSettings.fromJson(<String, Object?>{
        'viewportTheme': 'future-theme',
      });

      expect(decoded.viewportTheme, AppViewportTheme.light);
    });
  });
}
