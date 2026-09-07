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

/// Minimal geometric Arvela mark shared by the in-app chrome and launch UI.
class ArvelaMark extends StatelessWidget {
  const ArvelaMark({
    super.key,
    this.size = 24,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${ArvelaBrand.name} logo',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ArvelaMarkPainter(
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _ArvelaMarkPainter extends CustomPainter {
  const _ArvelaMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = Offset(size.width * 0.18, size.height * 0.82);
    final peak = Offset(size.width * 0.5, size.height * 0.16);
    final right = Offset(size.width * 0.82, size.height * 0.82);
    canvas.drawPath(
      Path()
        ..moveTo(left.dx, left.dy)
        ..lineTo(peak.dx, peak.dy)
        ..lineTo(right.dx, right.dy),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.62),
      Offset(size.width * 0.66, size.height * 0.62),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArvelaMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
