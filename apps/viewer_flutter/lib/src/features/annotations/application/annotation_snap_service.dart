import 'dart:ui';

import '../../../core/application/render_scene/render_scene_models.dart';

/// The semantic source that won a touch snap.  Keeping this value in the
/// annotation application layer lets the viewport render a visual cue without
/// making the persistent annotation store aware of BIM geometry.
enum AnnotationSnapKind { endpoint, midpoint, edge, center, alignment, grid }

final class AnnotationSnapCandidate {
  const AnnotationSnapCandidate({
    required this.modelPoint,
    required this.screenPoint,
    required this.kind,
    this.elementId,
  });

  final RenderScenePoint modelPoint;
  final Offset screenPoint;
  final AnnotationSnapKind kind;
  final int? elementId;
}

final class AnnotationSnapSegment {
  const AnnotationSnapSegment({
    required this.start,
    required this.end,
    required this.startScreen,
    required this.endScreen,
    this.elementId,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
  final Offset startScreen;
  final Offset endScreen;
  final int? elementId;
}

final class AnnotationSnapResult {
  const AnnotationSnapResult({
    required this.modelPoint,
    required this.screenPoint,
    required this.kind,
    required this.distancePixels,
    this.elementId,
  });

  final RenderScenePoint modelPoint;
  final Offset screenPoint;
  final AnnotationSnapKind kind;
  final double distancePixels;
  final int? elementId;
}

/// Pure screen-space snap resolver.
///
/// Geometry is projected by the viewport and supplied as candidates. This
/// keeps the annotation module independent from the viewport controller and
/// makes snapping cheap to unit-test. Segments are projected onto in screen
/// space, then interpolated in model space, so a dimension can snap to the
/// middle of a wall/edge rather than only to its endpoints.
abstract final class AnnotationSnapResolver {
  static AnnotationSnapResult? resolve({
    required Offset pointer,
    Iterable<AnnotationSnapCandidate> points =
        const <AnnotationSnapCandidate>[],
    Iterable<AnnotationSnapSegment> segments = const <AnnotationSnapSegment>[],
    double tolerancePixels = 24,
  }) {
    if (!pointer.dx.isFinite ||
        !pointer.dy.isFinite ||
        !tolerancePixels.isFinite ||
        tolerancePixels <= 0) {
      return null;
    }

    AnnotationSnapResult? best;
    for (final candidate in points) {
      final distance = (candidate.screenPoint - pointer).distance;
      if (!distance.isFinite || distance > tolerancePixels) continue;
      final result = AnnotationSnapResult(
        modelPoint: candidate.modelPoint,
        screenPoint: candidate.screenPoint,
        kind: candidate.kind,
        distancePixels: distance,
        elementId: candidate.elementId,
      );
      if (_isBetter(result, best)) best = result;
    }

    for (final segment in segments) {
      final dx = segment.endScreen.dx - segment.startScreen.dx;
      final dy = segment.endScreen.dy - segment.startScreen.dy;
      final lengthSquared = dx * dx + dy * dy;
      if (!lengthSquared.isFinite || lengthSquared <= 1e-9) continue;
      final rawT = ((pointer.dx - segment.startScreen.dx) * dx +
              (pointer.dy - segment.startScreen.dy) * dy) /
          lengthSquared;
      final t = rawT.clamp(0.0, 1.0).toDouble();
      final screenPoint = Offset(
        segment.startScreen.dx + dx * t,
        segment.startScreen.dy + dy * t,
      );
      final distance = (screenPoint - pointer).distance;
      if (!distance.isFinite || distance > tolerancePixels) continue;
      final modelPoint = RenderScenePoint(
        x: _lerp(segment.start.x, segment.end.x, t),
        y: _lerp(segment.start.y, segment.end.y, t),
        z: _lerp(segment.start.z, segment.end.z, t),
      );
      final result = AnnotationSnapResult(
        modelPoint: modelPoint,
        screenPoint: screenPoint,
        kind: AnnotationSnapKind.edge,
        distancePixels: distance,
        elementId: segment.elementId,
      );
      if (_isBetter(result, best)) best = result;
    }
    return best;
  }

  static bool _isBetter(
    AnnotationSnapResult candidate,
    AnnotationSnapResult? current,
  ) {
    if (current == null) return true;
    final distanceDelta = candidate.distancePixels - current.distancePixels;
    if (distanceDelta.abs() > 1.5) return distanceDelta < 0;
    return _priority(candidate.kind) < _priority(current.kind);
  }

  static int _priority(AnnotationSnapKind kind) => switch (kind) {
        AnnotationSnapKind.endpoint => 0,
        AnnotationSnapKind.midpoint => 1,
        AnnotationSnapKind.center => 2,
        AnnotationSnapKind.alignment => 3,
        AnnotationSnapKind.edge => 4,
        AnnotationSnapKind.grid => 5,
      };

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Small helper shared by the viewport adapter when building a grid fallback.
RenderScenePoint snapAnnotationPointToGrid(
  RenderScenePoint point, {
  double spacing = 0.1,
}) {
  if (!spacing.isFinite || spacing <= 0) return point;
  double snap(double value) => (value / spacing).round() * spacing;
  return RenderScenePoint(
    x: snap(point.x),
    y: snap(point.y),
    z: snap(point.z),
  );
}
