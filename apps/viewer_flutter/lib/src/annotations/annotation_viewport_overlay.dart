import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../project_unit_settings.dart';
import '../render_scene_models.dart';
import '../render_scene_viewport_controller.dart';
import '../render_scene_viewport_projection.dart';
import 'annotation_render_batches.dart';
import 'annotation_store.dart';

/// Flutter annotation renderer used while the native glyph/line atlas is being
/// integrated. It consumes only the active-view render plan, so annotations in
/// unrelated floors/sheets create no paint work.
class AnnotationViewportOverlay extends StatelessWidget {
  const AnnotationViewportOverlay({
    super.key,
    required this.controller,
    required this.store,
    required this.viewId,
    this.selectedAnnotationId,
    this.units = const ProjectUnitSettings.defaults(),
  });

  final RenderSceneViewportController controller;
  final AnnotationStore store;
  final int viewId;
  final int? selectedAnnotationId;
  final ProjectUnitSettings units;

  @override
  Widget build(BuildContext context) {
    if (store.isEmpty || controller.scene == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? math.max(constraints.maxWidth, 1.0).toDouble()
                : 1.0;
            final height = constraints.maxHeight.isFinite
                ? math.max(constraints.maxHeight, 1.0).toDouble()
                : 1.0;
            return CustomPaint(
              size: Size(width, height),
              painter: _AnnotationPainter(
                controller: controller,
                store: store,
                plan: AnnotationRenderPlanner.forView(store, viewId),
                selectedAnnotationId: selectedAnnotationId,
                units: units,
                lineColor: colors.primary,
                textColor: colors.onSurface,
                tagBackground: colors.surface.withValues(alpha: 0.92),
                selectionColor: colors.tertiary,
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.controller,
    required this.store,
    required this.plan,
    required this.selectedAnnotationId,
    required this.units,
    required this.lineColor,
    required this.textColor,
    required this.tagBackground,
    required this.selectionColor,
  });

  final RenderSceneViewportController controller;
  final AnnotationStore store;
  final AnnotationRenderPlan plan;
  final int? selectedAnnotationId;
  final ProjectUnitSettings units;
  final Color lineColor;
  final Color textColor;
  final Color tagBackground;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.visibleAnnotationCount == 0) return;
    final projection = RenderSceneProjection(
      sceneBounds: controller.sceneBounds,
      canvasSize: size,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: 48,
    );

    final textRow = _rowLookup(store.length, store.text.annotationIndices);
    final dimensionRow =
        _rowLookup(store.length, store.dimensions.annotationIndices);
    final tagRow = _rowLookup(store.length, store.tags.annotationIndices);
    final detailRow =
        _rowLookup(store.length, store.detailLines.annotationIndices);
    final symbolRow = _rowLookup(store.length, store.symbols.annotationIndices);

    for (final batch in plan.batches) {
      final style = store.styles[batch.styleId];
      switch (batch.kind) {
        case AnnotationKind.text:
          for (final annotationIndex in batch.annotationIndices) {
            final row = textRow[annotationIndex];
            if (row < 0) continue;
            final anchor = _anchor(annotationIndex);
            final point = projection.project(anchor).screen;
            _paintLabel(
              canvas,
              point,
              store.strings[store.text.stringIds[row]],
              style,
              background: false,
            );
          }
        case AnnotationKind.linearDimension:
          for (final annotationIndex in batch.annotationIndices) {
            final row = dimensionRow[annotationIndex];
            if (row < 0) continue;
            _paintDimension(canvas, projection, row, style);
          }
        case AnnotationKind.tag:
          for (final annotationIndex in batch.annotationIndices) {
            final row = tagRow[annotationIndex];
            if (row < 0) continue;
            final anchor = _anchor(annotationIndex);
            final point = projection.project(anchor).screen;
            _paintLabel(
              canvas,
              point,
              store.strings[store.tags.labelStringIds[row]],
              style,
              background: true,
            );
          }
        case AnnotationKind.detailLine:
          for (final annotationIndex in batch.annotationIndices) {
            final row = detailRow[annotationIndex];
            if (row < 0) continue;
            _paintDetailLine(canvas, projection, row, style);
          }
        case AnnotationKind.symbol:
          for (final annotationIndex in batch.annotationIndices) {
            final row = symbolRow[annotationIndex];
            if (row < 0) continue;
            _paintSymbol(canvas, projection, annotationIndex, row, style);
          }
      }
    }

    _paintSelection(canvas, projection);
  }

  Int32List _rowLookup(int length, Uint32List annotationIndices) {
    final rows = Int32List(length)..fillRange(0, length, -1);
    for (var row = 0; row < annotationIndices.length; row++) {
      final annotationIndex = annotationIndices[row];
      if (annotationIndex < length) rows[annotationIndex] = row;
    }
    return rows;
  }

  RenderScenePoint _anchor(int annotationIndex) {
    final offset = annotationIndex * 3;
    return RenderScenePoint(
      x: store.anchors[offset],
      y: store.anchors[offset + 1],
      z: store.anchors[offset + 2],
    );
  }

  void _paintSelection(
    Canvas canvas,
    RenderSceneProjection projection,
  ) {
    final selectedId = selectedAnnotationId;
    if (selectedId == null) return;
    final visible = store.queryView(plan.viewId);
    var selectedIndex = -1;
    for (final annotationIndex in visible) {
      if (annotationIndex < store.length &&
          store.annotationIds[annotationIndex] == selectedId) {
        selectedIndex = annotationIndex;
        break;
      }
    }
    if (selectedIndex < 0) return;
    final point = projection.project(_anchor(selectedIndex)).screen;
    final paint = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(point, 11, paint);
    canvas.drawLine(point + const Offset(-14, 0), point + const Offset(-8, 0), paint);
    canvas.drawLine(point + const Offset(8, 0), point + const Offset(14, 0), paint);
    canvas.drawLine(point + const Offset(0, -14), point + const Offset(0, -8), paint);
    canvas.drawLine(point + const Offset(0, 8), point + const Offset(0, 14), paint);
  }

  void _paintDimension(
    Canvas canvas,
    RenderSceneProjection projection,
    int row,
    AnnotationStyle style,
  ) {
    final startOffset = row * 3;
    final start = RenderScenePoint(
      x: store.dimensions.startPoints[startOffset],
      y: store.dimensions.startPoints[startOffset + 1],
      z: store.dimensions.startPoints[startOffset + 2],
    );
    final end = RenderScenePoint(
      x: store.dimensions.endPoints[startOffset],
      y: store.dimensions.endPoints[startOffset + 1],
      z: store.dimensions.endPoints[startOffset + 2],
    );
    var a = projection.project(start).screen;
    var b = projection.project(end).screen;
    final delta = b - a;
    final lengthPixels = delta.distance;
    if (lengthPixels <= 1e-6) return;
    final normal = Offset(-delta.dy / lengthPixels, delta.dx / lengthPixels);
    final screenOffset = normal * (18 + store.dimensions.offsets[row] * 10);
    a += screenOffset;
    b += screenOffset;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = math.max(style.lineWeight.toDouble(), 1)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(a, b, paint);
    final tick = normal * 5;
    canvas.drawLine(a - tick, a + tick, paint);
    canvas.drawLine(b - tick, b + tick, paint);

    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final dz = end.z - start.z;
    final meters = math.sqrt(dx * dx + dy * dy + dz * dz);
    _paintLabel(
      canvas,
      Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5),
      units.formatLength(meters),
      style,
      background: true,
      centered: true,
    );
  }

  void _paintDetailLine(
    Canvas canvas,
    RenderSceneProjection projection,
    int row,
    AnnotationStyle style,
  ) {
    final offset = row * 3;
    final start = projection
        .project(RenderScenePoint(
          x: store.detailLines.startPoints[offset],
          y: store.detailLines.startPoints[offset + 1],
          z: store.detailLines.startPoints[offset + 2],
        ))
        .screen;
    final end = projection
        .project(RenderScenePoint(
          x: store.detailLines.endPoints[offset],
          y: store.detailLines.endPoints[offset + 1],
          z: store.detailLines.endPoints[offset + 2],
        ))
        .screen;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = lineColor
        ..strokeWidth = math.max(style.lineWeight.toDouble(), 1)
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintSymbol(
    Canvas canvas,
    RenderSceneProjection projection,
    int annotationIndex,
    int row,
    AnnotationStyle style,
  ) {
    final point = projection.project(_anchor(annotationIndex)).screen;
    final scale = store.symbols.scales[row].clamp(0.25, 8.0);
    final rotation = store.symbols.rotations[row];
    final radius = 8.0 * scale;
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = math.max(style.lineWeight.toDouble(), 1)
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(rotation);
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.drawLine(Offset(-radius, 0), Offset(radius, 0), paint);
    canvas.drawLine(Offset(0, -radius), Offset(0, radius), paint);
    canvas.restore();
  }

  void _paintLabel(
    Canvas canvas,
    Offset point,
    String value,
    AnnotationStyle style, {
    required bool background,
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: textColor,
          fontSize: math.max(11, style.textHeightMeters * 5000),
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 220);
    final origin = centered
        ? point - Offset(painter.width * 0.5, painter.height * 0.5)
        : point + const Offset(5, -5);
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            origin.dx - 4,
            origin.dy - 2,
            painter.width + 8,
            painter.height + 4,
          ),
          const Radius.circular(4),
        ),
        Paint()..color = tagBackground,
      );
    }
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) =>
      oldDelegate.store != store ||
      oldDelegate.plan.viewId != plan.viewId ||
      oldDelegate.selectedAnnotationId != selectedAnnotationId ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.tagBackground != tagBackground ||
      oldDelegate.selectionColor != selectionColor;
}
