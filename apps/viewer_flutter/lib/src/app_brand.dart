import 'package:flutter/material.dart';

/// Single source of truth for the product name and its display typography.
///
/// The condensed system face gives Arvela a compact architectural/technical
/// wordmark on Android tablets, while the fallback keeps the same hierarchy on
/// iOS and desktop hosts without downloading a font at runtime.
abstract final class ArvelaBrand {
  static const String name = 'Arvela';
  static const String projectName = 'Arvela Project';
  static const String displayFontFamily = 'sans-serif-condensed';
  static const String bodyFontFamily = 'sans-serif';
  static const List<String> fontFallback = <String>[
    'Avenir Next',
    'sans-serif',
  ];

  static ThemeData applyTypography(ThemeData theme) {
    final text = theme.textTheme.apply(fontFamily: bodyFontFamily);

    TextStyle? display(TextStyle? style, FontWeight weight) => style?.copyWith(
          fontFamily: displayFontFamily,
          fontFamilyFallback: fontFallback,
          fontWeight: weight,
        );

    return theme.copyWith(
      textTheme: text.copyWith(
        displayLarge: display(text.displayLarge, FontWeight.w700),
        displayMedium: display(text.displayMedium, FontWeight.w700),
        displaySmall: display(text.displaySmall, FontWeight.w700),
        headlineLarge: display(text.headlineLarge, FontWeight.w700),
        headlineMedium: display(text.headlineMedium, FontWeight.w700),
        headlineSmall: display(text.headlineSmall, FontWeight.w700),
        titleLarge: display(text.titleLarge, FontWeight.w700),
        titleMedium: display(text.titleMedium, FontWeight.w600),
        titleSmall: display(text.titleSmall, FontWeight.w600),
      ),
    );
  }
}
