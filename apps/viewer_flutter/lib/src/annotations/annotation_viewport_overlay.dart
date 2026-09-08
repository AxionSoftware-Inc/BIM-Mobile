import 'dart:math' as math;

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
    this.units = const ProjectUnitSettings.defaults(),
  });

  final RenderSceneViewportController controller;
  final AnnotationStore store;
  final int viewId;
  final ProjectUnitSettings units;

  @override
  Widget build(BuildContext context) {
    if (store.isEmpty || controller.scene == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            math.max(constraints.maxWidth, 1),
            math.max(constraints.maxHeight, 1),
          );
          return CustomPaint(
            size: size,
            painter: _AnnotationPainter(
              controller: controller,
              store: store,
              plan: AnnotationRenderPlanner.forView(store, viewId),
              units: units,
              lineColor: colors.primary,
              textColor: colors.onSurface,
              tagBackground: colors.surface.withValues(alpha: 0.92),
            ),
          );
        },
      ),
    );
  }
}

final class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.controller,
    required this.store,
    required this.plan,
    required this.units,
    required this.lineColor,
    required this.textColor,
    required this.tagBackground,
  });

  final RenderSceneViewportController controller;
  final AnnotationStore store;
  final AnnotationRenderPlan plan;
  final ProjectUnitSettings units;
  final Color lineColor;
  final Color textColor;
  final Color tagBackground;

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

    final textRow = <int, int>{};
    for (var row = 0; row < store.text.annotationIndices.length; row++) {
      textRow[store.text.annotationIndices[row]] = row;
    }
    final dimensionRow = <int, int>{};
    for (var row = 0; row < store.dimensions.annotationIndices.length; row++) {
      dimensionRow[store.dimensions.annotationIndices[row]] = row;
    }
    final tagRow = <int, int>{};
    for (var row = 0; row < store.tags.annotationIndices.length; row++) {
      tagRow[store.tags.annotationIndices[row]] = row;
    }

    for (final batch in plan.batches) {
      final style = store.styles[batch.styleId];
      switch (batch.kind) {
        case AnnotationKind.text:
          for (final annotationIndex in batch.annotationIndices) {
            final row = textRow[annotationIndex];
            if (row == null) continue;
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
            if (row == null) continue;
            _paintDimension(canvas, projection, row, style);
          }
        case AnnotationKind.tag:
          for (final annotationIndex in batch.annotationIndices) {
            final row = tagRow[annotationIndex];
            if (row == null) continue;
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
        case AnnotationKind.symbol:
          // Their packed payload tables are the next renderer extension. They
          // intentionally remain no-op rather than falling back to 3D objects.
          break;
      }
    }
  }

  RenderScenePoint _anchor(int annotationIndex) {
    final offset = annotationIndex * 3;
    return RenderScenePoint(
      x: store.anchors[offset],
      y: store.anchors[offset + 1],
      z: store.anchors[offset + 2],
    );
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
      oldDelegate.controller.sceneRevision != controller.sceneRevision ||
      oldDelegate.controller.fitRevision != controller.fitRevision ||
      oldDelegate.controller.projectionMode != controller.projectionMode ||
      oldDelegate.controller.planCamera != controller.planCamera ||
      oldDelegate.controller.camera != controller.camera ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.textColor != textColor;
}
