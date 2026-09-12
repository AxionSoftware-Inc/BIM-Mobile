import 'package:flutter/material.dart';

/// Transient touch feedback for annotation commands.
///
/// This is deliberately not part of the persistent annotation painter: snap
/// targets and drag previews are interaction state and must disappear without
/// entering the annotation document or its history.
class AnnotationInteractionOverlay extends StatelessWidget {
  const AnnotationInteractionOverlay({
    super.key,
    this.snapPoint,
    this.draftStart,
    this.draftEnd,
    this.dragStart,
    this.dragEnd,
  });

  final Offset? snapPoint;
  final Offset? draftStart;
  final Offset? draftEnd;
  final Offset? dragStart;
  final Offset? dragEnd;

  @override
  Widget build(BuildContext context) {
    if (snapPoint == null &&
        (draftStart == null || draftEnd == null) &&
        (dragStart == null || dragEnd == null)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _AnnotationInteractionPainter(
          color: Theme.of(context).colorScheme.primary,
          snapPoint: snapPoint,
          draftStart: draftStart,
          draftEnd: draftEnd,
          dragStart: dragStart,
          dragEnd: dragEnd,
        ),
        size: Size.infinite,
      ),
    );
  }
}

final class _AnnotationInteractionPainter extends CustomPainter {
  const _AnnotationInteractionPainter({
    required this.color,
    this.snapPoint,
    this.draftStart,
    this.draftEnd,
    this.dragStart,
    this.dragEnd,
  });

  final Color color;
  final Offset? snapPoint;
  final Offset? draftStart;
  final Offset? draftEnd;
  final Offset? dragStart;
  final Offset? dragEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final previewPaint = Paint()
      ..color = color.withValues(alpha: 0.48)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (draftStart != null && draftEnd != null) {
      canvas.drawLine(draftStart!, draftEnd!, linePaint);
    }
    if (dragStart != null && dragEnd != null) {
      canvas.drawLine(dragStart!, dragEnd!, previewPaint);
    }
    if (snapPoint != null) {
      final point = snapPoint!;
      canvas.drawCircle(point, 8, linePaint);
      canvas.drawLine(
        Offset(point.dx - 13, point.dy),
        Offset(point.dx + 13, point.dy),
        linePaint,
      );
      canvas.drawLine(
        Offset(point.dx, point.dy - 13),
        Offset(point.dx, point.dy + 13),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationInteractionPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.snapPoint != snapPoint ||
      oldDelegate.draftStart != draftStart ||
      oldDelegate.draftEnd != draftEnd ||
      oldDelegate.dragStart != dragStart ||
      oldDelegate.dragEnd != dragEnd;
}
