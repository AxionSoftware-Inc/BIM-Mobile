import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// The endpoint intentionally selected by a plan-authoring gesture.
///
/// Keeping this explicit is important for Trim/Extend: the user can select a
/// wall near the exact end they want to change instead of the tool guessing
/// from an ambiguous crossing.
enum PlanSketchEndpoint { start, end }

/// A compact, UI-independent plan line used by every line-based authoring
/// tool. It is deliberately not a BIM element or an engine DTO.
@immutable
class PlanSketchLine {
  const PlanSketchLine({required this.start, required this.end});

  final RenderScenePoint start;
  final RenderScenePoint end;

  double get planLength => PlanSketchGeometry.planDistance(start, end);

  RenderScenePoint pointAt(PlanSketchEndpoint endpoint) => switch (endpoint) {
        PlanSketchEndpoint.start => start,
        PlanSketchEndpoint.end => end,
      };

  PlanSketchEndpoint endpointNearestTo(RenderScenePoint point) =>
      PlanSketchGeometry.planDistance(start, point) <=
              PlanSketchGeometry.planDistance(end, point)
          ? PlanSketchEndpoint.start
          : PlanSketchEndpoint.end;

  PlanSketchLine withEndpoint(
    PlanSketchEndpoint endpoint,
    RenderScenePoint point,
  ) =>
      switch (endpoint) {
        PlanSketchEndpoint.start => PlanSketchLine(start: point, end: end),
        PlanSketchEndpoint.end => PlanSketchLine(start: start, end: point),
      };
}

/// A validated Trim/Extend preview. The engine receives the same endpoint
/// choices so the committed mutation matches this preview exactly.
@immutable
class PlanSketchTrimResult {
  const PlanSketchTrimResult({
    required this.first,
    required this.second,
    required this.firstEndpoint,
    required this.secondEndpoint,
    required this.intersection,
  });

  final PlanSketchLine first;
  final PlanSketchLine second;
  final PlanSketchEndpoint firstEndpoint;
  final PlanSketchEndpoint secondEndpoint;
  final RenderScenePoint intersection;
}

/// Shared geometry kernel for tablet plan authoring.
///
/// Wall, stair, floor, ceiling and roof tools intentionally share snapping,
/// orthogonal constraints, rectangles and line operations here. This keeps
/// future tools such as Offset, Trim/Extend and Align out of widget code.
class PlanSketchGeometry {
  const PlanSketchGeometry._();

  static const double defaultGridStepMeters = 0.25;
  static const double defaultEndpointToleranceMeters = 0.45;
  static const double minimumSegmentMeters = 0.10;
  // Only remove a small hand wobble. A 10–15° intentional bend must remain a
  // bend; the old 1.35 ratio forced almost every diagonal continuation onto
  // the nearest horizontal/vertical axis and broke joined wall chains.
  static const double _orthogonalDominance = 10.0;
  // Wall authoring is deliberately a little more forgiving than the generic
  // sketch tools: a hand wobble up to roughly ten degrees should still make a
  // clean horizontal/vertical wall. Intentional diagonals remain available
  // once they are clearly diagonal.
  static const double wallOrthogonalDominance = 5.5;
  // When a line is clearly horizontal/vertical, an endpoint candidate must
  // also be close to that same axis. Otherwise a nearby corner from the
  // previous segment can pull a straight continuation into a diagonal.
  static const double _orthogonalEndpointTolerance = 0.18;
  static const double _epsilon = 1e-9;

  static double planDistance(RenderScenePoint first, RenderScenePoint second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static RenderScenePoint snapToGrid(
    RenderScenePoint point, {
    double stepMeters = defaultGridStepMeters,
    bool snapVertical = false,
  }) {
    if (!point.isFinite || !stepMeters.isFinite || stepMeters <= 0) {
      return point;
    }
    double snap(double value) =>
        (value / stepMeters).roundToDouble() * stepMeters;
    return RenderScenePoint(
      x: snap(point.x),
      y: snap(point.y),
      z: snapVertical ? snap(point.z) : point.z,
    );
  }

  /// Snaps in the XY authoring plane and deliberately retains the input Z.
  /// A plan tool must not accidentally inherit a vertex elevation from a
  /// different storey just because it shares the same footprint.
  static RenderScenePoint snapToCandidate(
    RenderScenePoint point,
    Iterable<RenderScenePoint> candidates, {
    double toleranceMeters = defaultEndpointToleranceMeters,
  }) {
    if (!point.isFinite || !toleranceMeters.isFinite || toleranceMeters <= 0) {
      return point;
    }
    var best = point;
    var bestDistance = toleranceMeters;
    for (final candidate in candidates) {
      if (!candidate.isFinite) continue;
      final distance = planDistance(candidate, point);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return RenderScenePoint(x: best.x, y: best.y, z: point.z);
  }

  /// Resolves a line endpoint with the same reusable plan constraints.
  ///
  /// [lockElevationAxis] is used by elevation-line tools: their second click
  /// changes the line width while the first click owns the elevation.
  static RenderScenePoint resolveLineEndpoint({
    required RenderScenePoint rawPoint,
    required RenderScenePoint? referenceStart,
    Iterable<RenderScenePoint> candidatePoints = const <RenderScenePoint>[],
    bool useGridSnap = true,
    bool constrainOrtho = true,
    bool lockElevationAxis = false,
    bool snapVertical = false,
    double? orthogonalDominance,
  }) {
    RenderScenePoint point;
    if (useGridSnap) {
      point = snapToGrid(rawPoint, snapVertical: snapVertical);
    } else {
      point = rawPoint;
    }
    final start = referenceStart;
    if (start == null) {
      // Endpoint snapping is last on purpose. Grid snapping a point that has
      // already matched a real wall endpoint moves it away from the join.
      return snapToCandidate(point, candidatePoints);
    }
    if (lockElevationAxis) {
      return RenderScenePoint(x: point.x, y: point.y, z: start.z);
    }
    if (!constrainOrtho) return point;

    final dx = point.x - start.x;
    final dy = point.y - start.y;
    if (dx.abs() < _epsilon && dy.abs() < _epsilon) return point;
    final dominance = orthogonalDominance ?? _orthogonalDominance;
    if (dx.abs() > dy.abs() * dominance) {
      final horizontal = _snapOrthogonalCandidate(
        point: point,
        start: start,
        candidates: candidatePoints,
        horizontal: true,
      );
      return RenderScenePoint(
          x: horizontal?.x ?? point.x, y: start.y, z: point.z);
    }
    if (dy.abs() > dx.abs() * dominance) {
      final vertical = _snapOrthogonalCandidate(
        point: point,
        start: start,
        candidates: candidatePoints,
        horizontal: false,
      );
      return RenderScenePoint(
          x: start.x, y: vertical?.y ?? point.y, z: point.z);
    }
    return snapToCandidate(point, candidatePoints);
  }

  static RenderScenePoint? _snapOrthogonalCandidate({
    required RenderScenePoint point,
    required RenderScenePoint start,
    required Iterable<RenderScenePoint> candidates,
    required bool horizontal,
  }) {
    RenderScenePoint? best;
    var bestDistance = defaultEndpointToleranceMeters;
    for (final candidate in candidates) {
      if (!candidate.isFinite) continue;
      final axisDistance = horizontal
          ? (candidate.y - start.y).abs()
          : (candidate.x - start.x).abs();
      if (axisDistance > _orthogonalEndpointTolerance) continue;
      final alongDistance = horizontal
          ? (candidate.x - point.x).abs()
          : (candidate.y - point.y).abs();
      if (alongDistance < bestDistance) {
        bestDistance = alongDistance;
        best = candidate;
      }
    }
    return best;
  }

  static List<RenderScenePoint> rectangle(
    RenderScenePoint start,
    RenderScenePoint end,
  ) {
    final minX = math.min(start.x, end.x);
    final maxX = math.max(start.x, end.x);
    final minY = math.min(start.y, end.y);
    final maxY = math.max(start.y, end.y);
    final z = math.max(start.z, end.z);
    return <RenderScenePoint>[
      RenderScenePoint(x: minX, y: minY, z: z),
      RenderScenePoint(x: maxX, y: minY, z: z),
      RenderScenePoint(x: maxX, y: maxY, z: z),
      RenderScenePoint(x: minX, y: maxY, z: z),
    ];
  }

  static bool isUsableRectangle(
    RenderScenePoint? start,
    RenderScenePoint? end, {
    double minimumSizeMeters = minimumSegmentMeters,
  }) {
    if (start == null || end == null) return false;
    return (end.x - start.x).abs() >= minimumSizeMeters &&
        (end.y - start.y).abs() >= minimumSizeMeters;
  }

  /// Extends or trims the explicitly selected endpoint of each line to their
  /// infinite-line intersection. Parallel lines and zero-length results are
  /// rejected before an engine mutation is attempted.
  static PlanSketchTrimResult? trimExtend({
    required PlanSketchLine first,
    required PlanSketchEndpoint firstEndpoint,
    required PlanSketchLine second,
    required PlanSketchEndpoint secondEndpoint,
  }) {
    if (first.planLength < minimumSegmentMeters ||
        second.planLength < minimumSegmentMeters) {
      return null;
    }
    final intersection = _lineIntersection(first, second);
    if (intersection == null) return null;

    final firstPoint = RenderScenePoint(
      x: intersection.x,
      y: intersection.y,
      z: first.pointAt(firstEndpoint).z,
    );
    final secondPoint = RenderScenePoint(
      x: intersection.x,
      y: intersection.y,
      z: second.pointAt(secondEndpoint).z,
    );
    final trimmedFirst = first.withEndpoint(firstEndpoint, firstPoint);
    final trimmedSecond = second.withEndpoint(secondEndpoint, secondPoint);
    if (trimmedFirst.planLength < minimumSegmentMeters ||
        trimmedSecond.planLength < minimumSegmentMeters) {
      return null;
    }
    return PlanSketchTrimResult(
      first: trimmedFirst,
      second: trimmedSecond,
      firstEndpoint: firstEndpoint,
      secondEndpoint: secondEndpoint,
      intersection: RenderScenePoint(
        x: intersection.x,
        y: intersection.y,
        z: firstPoint.z,
      ),
    );
  }

  static RenderScenePoint? _lineIntersection(
    PlanSketchLine first,
    PlanSketchLine second,
  ) {
    final x1 = first.start.x;
    final y1 = first.start.y;
    final x2 = first.end.x;
    final y2 = first.end.y;
    final x3 = second.start.x;
    final y3 = second.start.y;
    final x4 = second.end.x;
    final y4 = second.end.y;
    final denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4));
    if (denominator.abs() < _epsilon) return null;
    return RenderScenePoint(
      x: (((x1 * y2) - (y1 * x2)) * (x3 - x4) -
              (x1 - x2) * ((x3 * y4) - (y3 * x4))) /
          denominator,
      y: (((x1 * y2) - (y1 * x2)) * (y3 - y4) -
              (y1 - y2) * ((x3 * y4) - (y3 * x4))) /
          denominator,
      z: first.start.z,
    );
  }
}
