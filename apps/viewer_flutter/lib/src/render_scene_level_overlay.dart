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

List<RenderSceneLevelOverlayEntry> buildLevelOverlayEntries({
  required RenderScene scene,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneProjection projection,
}) {
  final descriptor = projectionMode.planarDescriptor;
  if (!projectionMode.showLevelsOverlay ||
      descriptor == null ||
      !descriptor.isElevation) {
    return const <RenderSceneLevelOverlayEntry>[];
  }

  final bounds = scene.bounds;
  final horizontalMin =
      descriptor.minAxis(bounds, descriptor.horizontalAxis) - 1.0;
  final horizontalMax =
      descriptor.maxAxis(bounds, descriptor.horizontalAxis) + 1.0;

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
    final minX = a.screen.dx < b.screen.dx ? a.screen.dx : b.screen.dx;
    final maxX = a.screen.dx > b.screen.dx ? a.screen.dx : b.screen.dx;
    final minY = a.screen.dy < b.screen.dy ? a.screen.dy : b.screen.dy;
    final maxY = a.screen.dy > b.screen.dy ? a.screen.dy : b.screen.dy;
    return RenderSceneLevelOverlayEntry(
      level: level,
      lineStart: a.screen,
      lineEnd: b.screen,
      labelOrigin: a.screen + const Offset(6, -18),
      hitBounds: Rect.fromLTRB(minX, minY - 10, maxX, maxY + 10),
    );
  }).toList(growable: false);
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
