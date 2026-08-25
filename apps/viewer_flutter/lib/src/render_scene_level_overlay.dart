import 'package:flutter/material.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

@immutable
class RenderSceneLevelOverlayEntry {
  const RenderSceneLevelOverlayEntry({
    required this.level,
    required this.lineStart,
    required this.lineEnd,
    required this.labelOrigin,
    required this.hitBounds,
  });

  final RenderSceneLevel level;
  final Offset lineStart;
  final Offset lineEnd;
  final Offset labelOrigin;
  final Rect hitBounds;
}

/// Paints level annotations from the same projection/camera state as the
/// viewport. Native Android rendering can still own the model pixels, but it
/// must not maintain a second, drifting level-overlay camera for elevations or
/// sections.
final class RenderSceneLevelOverlayPainter extends CustomPainter {
  const RenderSceneLevelOverlayPainter({
    required this.scene,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.planCamera,
    required this.camera,
    required this.selectedLevelId,
    this.padding = 48.0,
  });

  final RenderScene scene;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderScenePlanCameraState planCamera;
  final RenderSceneCameraState camera;
  final int? selectedLevelId;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (!projectionMode.isElevation || size.width <= 1 || size.height <= 1) {
      return;
    }
    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      planCamera: planCamera,
      camera: camera,
      padding: padding,
    );
    final overlays = buildLevelOverlayEntries(
      scene: scene,
      projectionMode: projectionMode,
      projection: projection,
    );
    const textStyle = TextStyle(
      color: Color(0xFF334155),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    for (final overlay in overlays) {
      final selected = overlay.level.levelId == selectedLevelId;
      _drawDashedLine(
        canvas,
        overlay.lineStart,
        overlay.lineEnd,
        Paint()
          ..color =
              (selected ? const Color(0xFF2563EB) : const Color(0xFF0F766E))
                  .withValues(alpha: 0.96)
          ..strokeWidth = selected ? 3.2 : 1.6,
      );
      final painter = TextPainter(
        text: TextSpan(
          text:
              '${overlay.level.name} ${overlay.level.elevationMeters.toStringAsFixed(2)}m',
          style: selected
              ? textStyle.copyWith(
                  color: const Color(0xFF1D4ED8),
                  fontSize: 13,
                )
              : textStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 220);
      painter.paint(canvas, overlay.labelOrigin);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final vector = end - start;
    final length = vector.distance;
    if (length <= 1e-6) return;
    final direction = vector / length;
    const dashLength = 12.0;
    const gapLength = 6.0;
    var distance = 0.0;
    while (distance < length) {
      final dashEnd = (distance + dashLength).clamp(0.0, length);
      canvas.drawLine(
        start + direction * distance,
        start + direction * dashEnd,
        paint,
      );
      distance += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant RenderSceneLevelOverlayPainter oldDelegate) =>
      true;
}

List<RenderSceneLevelOverlayEntry> buildLevelOverlayEntries({
  required RenderScene scene,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneProjection projection,
}) {
  final descriptor = projectionMode.planarDescriptor;
  if (!projectionMode.showLevelsOverlay && !projectionMode.is3D) {
    return const <RenderSceneLevelOverlayEntry>[];
  }

  final bounds = scene.bounds;
  if (projectionMode.is3D) {
    return scene.levels.map((level) {
      final a = projection.project(RenderScenePoint(
        x: bounds.min.x - 1.0,
        y: bounds.min.y - 1.0,
        z: level.elevationMeters,
      ));
      final b = projection.project(RenderScenePoint(
        x: bounds.max.x + 1.0,
        y: bounds.min.y - 1.0,
        z: level.elevationMeters,
      ));
      return RenderSceneLevelOverlayEntry(
        level: level,
        lineStart: a.screen,
        lineEnd: b.screen,
        labelOrigin: a.screen + const Offset(6, -18),
        hitBounds: Rect.fromPoints(a.screen, b.screen).inflate(12),
      );
    }).toList(growable: false);
  }
  if (descriptor == null || !descriptor.isElevation) {
    return const <RenderSceneLevelOverlayEntry>[];
  }
  final horizontalMin = descriptor.minAxis(bounds, descriptor.horizontalAxis) -
      _levelAnnotationMargin(bounds, descriptor);
  final horizontalMax = descriptor.maxAxis(bounds, descriptor.horizontalAxis) +
      _levelAnnotationMargin(bounds, descriptor);

  return scene.levels.map((level) {
    final z = level.elevationMeters;
    final a = projection.project(
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMin,
        verticalValue: z,
      ),
    );
    final b = projection.project(
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMax,
        verticalValue: z,
      ),
    );
    // Prefer the screen-left side, but keep the label visible when the datum
    // endpoint is already close to the viewport edge. The opposite side can
    // be covered by the Project Browser in wide section/elevation layouts.
    final labelEndpoint = a.screen.dx <= b.screen.dx ? a.screen : b.screen;
    final labelOrigin = labelEndpoint.dx >= 180
        ? labelEndpoint + const Offset(-170, -18)
        : labelEndpoint + const Offset(12, -18);
    return RenderSceneLevelOverlayEntry(
      level: level,
      lineStart: a.screen,
      lineEnd: b.screen,
      // Keep the datum text outside the model envelope using the extended
      // endpoint rather than anchoring it to the building geometry.
      labelOrigin: labelOrigin,
      // The datum line is an annotation, not a pan handle. Only the label
      // area should start level dragging; otherwise a normal section pan
      // crossing any level line is mistaken for an elevation edit.
      hitBounds: Rect.fromLTWH(labelOrigin.dx, labelOrigin.dy - 6, 220, 34),
    );
  }).toList(growable: false);
}

double _levelAnnotationMargin(
  RenderSceneBounds bounds,
  RenderScenePlanarDescriptor descriptor,
) {
  final horizontalSpan = descriptor.maxAxis(bounds, descriptor.horizontalAxis) -
      descriptor.minAxis(bounds, descriptor.horizontalAxis);
  return (horizontalSpan * 0.12).clamp(2.0, 6.0);
}

RenderSceneLevel? pickLevelOverlayAt({
  required RenderScene scene,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneProjection projection,
  required Offset localPosition,
  double tolerancePixels = 24.0,
}) {
  final overlays = buildLevelOverlayEntries(
    scene: scene,
    projectionMode: projectionMode,
    projection: projection,
  );
  RenderSceneLevel? bestLevel;
  var bestDistance = tolerancePixels;
  for (final overlay in overlays) {
    if (!overlay.hitBounds.inflate(tolerancePixels).contains(localPosition)) {
      continue;
    }
    if (projectionMode.isElevation) {
      // In elevations and sections the datum line is a visual annotation.
      // Only its label/handle area is interactive so the rest of the line
      // remains available for two-finger camera navigation.
      bestLevel = overlay.level;
      break;
    }
    final distance =
        _distanceToSegment(localPosition, overlay.lineStart, overlay.lineEnd);
    if (distance <= bestDistance) {
      bestDistance = distance;
      bestLevel = overlay.level;
    }
  }
  return bestLevel;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final abLengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (abLengthSquared <= 1e-9) {
    return (point - a).distance;
  }
  final t = (((point.dx - a.dx) * ab.dx) + ((point.dy - a.dy) * ab.dy)) /
      abLengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  final projection = Offset(
    a.dx + ab.dx * clamped,
    a.dy + ab.dy * clamped,
  );
  return (point - projection).distance;
}
