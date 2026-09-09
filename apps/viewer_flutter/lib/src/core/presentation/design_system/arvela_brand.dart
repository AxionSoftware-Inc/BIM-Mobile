import 'package:flutter/material.dart';

/// Single source of truth for the product name and display typography.
///
/// PRESENTATION: branding belongs to the design system, not project/domain
/// code. Other presentation modules consume this contract instead of defining
/// local product names, fonts or wordmark styling.
abstract final class ArvelaBrand {
  static const String name = 'Arvela';
  static const String projectName = 'Arvela Project';
  static const String displayFontFamily = 'Avenir Next';
  static const String bodyFontFamily = 'sans-serif';
  static const List<String> fontFallback = <String>[
    'sans-serif',
    'Roboto',
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
        displayLarge: display(text.displayLarge, FontWeight.w600),
        displayMedium: display(text.displayMedium, FontWeight.w600),
        displaySmall: display(text.displaySmall, FontWeight.w600),
        headlineLarge: display(text.headlineLarge, FontWeight.w600),
        headlineMedium: display(text.headlineMedium, FontWeight.w600),
        headlineSmall: display(text.headlineSmall, FontWeight.w600),
        titleLarge: display(text.titleLarge, FontWeight.w600),
        titleMedium: display(text.titleMedium, FontWeight.w500),
        titleSmall: display(text.titleSmall, FontWeight.w500),
      ),
    );
  }
}
