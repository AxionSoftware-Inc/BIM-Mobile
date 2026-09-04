import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_document.dart';

/// Lightweight, touch-friendly 2D profile editor owned by Family Authoring.
///
/// It intentionally speaks only in family-local points. No viewport camera,
/// project selection, wall join or scene mutation code is involved here.
class FamilySketchCanvas extends StatefulWidget {
  const FamilySketchCanvas({
    super.key,
    required this.sketch,
    required this.onAddPoint,
    required this.onMovePoint,
  });

  final FamilySketch sketch;
  final ValueChanged<FamilySketchPoint> onAddPoint;
  final void Function(int index, FamilySketchPoint point) onMovePoint;

  @override
  State<FamilySketchCanvas> createState() => _FamilySketchCanvasState();
}

class _FamilySketchCanvasState extends State<FamilySketchCanvas> {
  int? _dragIndex;
  Offset? _pointerDown;
  bool _didMove = false;

  @override
  void didUpdateWidget(covariant FamilySketchCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sketch.id != widget.sketch.id) _dragIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _pointerDown = event.localPosition;
            _didMove = false;
            _dragIndex = _nearestPoint(event.localPosition, size);
          },
          onPointerMove: (event) {
            if (_pointerDown != null &&
                (event.localPosition - _pointerDown!).distance > 8) {
              _didMove = true;
            }
            final index = _dragIndex;
            if (index == null) return;
            widget.onMovePoint(index, _toModel(event.localPosition, size));
          },
          onPointerUp: (event) {
            if (_dragIndex == null && !_didMove) {
              widget.onAddPoint(_toModel(event.localPosition, size));
            }
            _resetPointer();
          },
          onPointerCancel: (_) => _resetPointer(),
          child: CustomPaint(
            painter: _FamilySketchPainter(
              sketch: widget.sketch,
              grid: colors.outlineVariant.withValues(alpha: 0.42),
              axis: colors.outline.withValues(alpha: 0.8),
              line: colors.primary,
              point: colors.tertiary,
              fill: colors.primary.withValues(alpha: 0.12),
              background: colors.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  void _resetPointer() {
    _pointerDown = null;
    _dragIndex = null;
    _didMove = false;
  }

  int? _nearestPoint(Offset position, Size size) {
    const radius = 28.0;
    int? closest;
    var closestDistance = double.infinity;
    for (var index = 0; index < widget.sketch.points.length; index++) {
      final screenPoint = _toScreen(widget.sketch.points[index], size);
      final distance = (screenPoint - position).distance;
      if (distance <= radius && distance < closestDistance) {
        closest = index;
        closestDistance = distance;
      }
    }
    return closest;
  }

  FamilySketchPoint _toModel(Offset position, Size size) {
    final scale = _scaleFor(size);
    return FamilySketchPoint(
      x: (position.dx - size.width / 2) / scale,
      y: (size.height / 2 - position.dy) / scale,
    );
  }

  Offset _toScreen(FamilySketchPoint point, Size size) {
    final scale = _scaleFor(size);
    return Offset(
      size.width / 2 + point.x * scale,
      size.height / 2 - point.y * scale,
    );
  }

  double _scaleFor(Size size) => math.min(size.width, size.height) / 4.0;
}

class _FamilySketchPainter extends CustomPainter {
  const _FamilySketchPainter({
    required this.sketch,
    required this.grid,
    required this.axis,
    required this.line,
    required this.point,
    required this.fill,
    required this.background,
  });

  final FamilySketch sketch;
  final Color grid;
  final Color axis;
  final Color line;
  final Color point;
  final Color fill;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final scale = math.min(size.width, size.height) / 4.0;
    final center = Offset(size.width / 2, size.height / 2);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.7;
    for (var i = -4; i <= 4; i++) {
      final offset = i * scale / 2;
      canvas.drawLine(
        Offset(center.dx + offset, 0),
        Offset(center.dx + offset, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, center.dy + offset),
        Offset(size.width, center.dy + offset),
        gridPaint,
      );
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.2;
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
    canvas.drawLine(
        Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);

    final points = <Offset>[
      for (final item in sketch.points)
        Offset(center.dx + item.x * scale, center.dy - item.y * scale),
    ];
    if (points.isNotEmpty) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final item in points.skip(1)) {
        path.lineTo(item.dx, item.dy);
      }
      if (sketch.closed) path.close();
      if (sketch.closed) canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final item in points) {
      canvas.drawCircle(item, 7, Paint()..color = point);
      canvas.drawCircle(
        item,
        7,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FamilySketchPainter oldDelegate) =>
      oldDelegate.sketch != sketch ||
      oldDelegate.grid != grid ||
      oldDelegate.axis != axis ||
      oldDelegate.line != line ||
      oldDelegate.point != point ||
      oldDelegate.fill != fill ||
      oldDelegate.background != background;
}
