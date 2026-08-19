import 'dart:math' as math;

import 'render_scene_models.dart';

enum DrawingToolKind { wall, floor, ceiling }

enum DrawingSnapKind {
  none,
  endpoint,
  intersection,
  midpoint,
  parallel,
  perpendicular,
  grid,
}

class DrawingSegment {
  const DrawingSegment({
    this.elementId,
    required this.start,
    required this.end,
    this.thickness = 0.2,
  });

  final int? elementId;
  final RenderScenePoint start;
  final RenderScenePoint end;
  final double thickness;
}

class DrawingSnap {
  const DrawingSnap({
    required this.point,
    required this.kind,
    required this.distance,
    this.sourceElementId,
  });

  final RenderScenePoint point;
  final DrawingSnapKind kind;
  final double distance;
  final int? sourceElementId;
}

class DrawingSegmentSolution {
  const DrawingSegmentSolution({
    required this.end,
    required this.snap,
    required this.angleRadians,
  });

  final RenderScenePoint end;
  final DrawingSnap? snap;
  final double angleRadians;
}

/// UI-independent 2D drafting rules. Walls, floor outlines and ceiling
/// outlines all use this kernel; only their commit adapter differs.
class DrawingKernel {
  const DrawingKernel({
    this.gridSize = 0.25,
    this.endpointTolerance = 0.22,
    this.angleToleranceRadians = 8 * math.pi / 180,
  });

  final double gridSize;
  final double endpointTolerance;
  final double angleToleranceRadians;

  DrawingSegmentSolution solveSegment({
    required RenderScenePoint start,
    required RenderScenePoint rawEnd,
    required List<DrawingSegment> existing,
    bool snapToGrid = true,
    bool snapToAngles = true,
  }) {
    final endpoint = nearestEndpoint(rawEnd, existing, endpointTolerance);
    if (endpoint != null) {
      return DrawingSegmentSolution(
        end: endpoint.point,
        snap: endpoint,
        angleRadians: math.atan2(endpoint.point.y - start.y, endpoint.point.x - start.x),
      );
    }

    final intersection = nearestIntersection(rawEnd, existing, endpointTolerance);
    if (intersection != null) {
      return DrawingSegmentSolution(
        end: intersection.point,
        snap: intersection,
        angleRadians: math.atan2(intersection.point.y - start.y, intersection.point.x - start.x),
      );
    }

    var candidate = rawEnd;
    DrawingSnap? snap;
    final rawAngle = math.atan2(rawEnd.y - start.y, rawEnd.x - start.x);
    final rawLength = distance(start, rawEnd);
    if (rawLength > 1e-6 && snapToAngles) {
      final constrained = _constrainAngle(start, rawEnd, existing);
      if (constrained != null) {
        candidate = constrained.point;
        snap = constrained;
      }
    }

    if (snapToGrid) {
      final grid = _gridPoint(candidate);
      final gridDistance = distance(candidate, grid);
      final gridTolerance = math.min(endpointTolerance * 0.7, gridSize * 0.45);
      if (gridDistance <= gridTolerance && (snap == null || gridDistance < snap.distance)) {
        candidate = grid;
        snap = DrawingSnap(point: grid, kind: DrawingSnapKind.grid, distance: gridDistance);
      }
    }

    return DrawingSegmentSolution(
      end: candidate,
      snap: snap,
      angleRadians: snap == null ? rawAngle : math.atan2(candidate.y - start.y, candidate.x - start.x),
    );
  }

  DrawingSnap? nearestEndpoint(
    RenderScenePoint point,
    List<DrawingSegment> segments,
    double tolerance,
  ) {
    DrawingSnap? best;
    for (final segment in segments) {
      for (final endpoint in <RenderScenePoint>[segment.start, segment.end]) {
        final d = distance(point, endpoint);
        if (d <= tolerance && (best == null || d < best.distance)) {
          best = DrawingSnap(
            point: endpoint,
            kind: DrawingSnapKind.endpoint,
            distance: d,
            sourceElementId: segment.elementId,
          );
        }
      }
    }
    return best;
  }

  DrawingSnap? nearestIntersection(
    RenderScenePoint point,
    List<DrawingSegment> segments,
    double tolerance,
  ) {
    DrawingSnap? best;
    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final intersection = segmentIntersection(segments[i], segments[j]);
        if (intersection == null) {
          continue;
        }
        final d = distance(point, intersection);
        if (d <= tolerance && (best == null || d < best.distance)) {
          best = DrawingSnap(
            point: intersection,
            kind: DrawingSnapKind.intersection,
            distance: d,
          );
        }
      }
    }
    return best;
  }

  RenderScenePoint? segmentIntersection(
    DrawingSegment first,
    DrawingSegment second,
  ) {
    final x1 = first.start.x;
    final y1 = first.start.y;
    final x2 = first.end.x;
    final y2 = first.end.y;
    final x3 = second.start.x;
    final y3 = second.start.y;
    final x4 = second.end.x;
    final y4 = second.end.y;
    final denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denominator.abs() < 1e-9) {
      return null;
    }
    final px = ((x1 * y2 - y1 * x2) * (x3 - x4) -
            (x1 - x2) * (x3 * y4 - y3 * x4)) /
        denominator;
    final py = ((x1 * y2 - y1 * x2) * (y3 - y4) -
            (y1 - y2) * (x3 * y4 - y3 * x4)) /
        denominator;
    final candidate = RenderScenePoint(x: px, y: py, z: 0);
    if (distanceToSegment(candidate, first) > 1e-7 ||
        distanceToSegment(candidate, second) > 1e-7) {
      return null;
    }
    return candidate;
  }

  DrawingSegment? pickSegment(
    RenderScenePoint point,
    List<DrawingSegment> segments, {
    double tolerance = 0.28,
  }) {
    DrawingSegment? best;
    var bestDistance = double.infinity;
    for (final segment in segments) {
      final d = distanceToSegment(point, segment);
      final hitTolerance = tolerance + segment.thickness / 2;
      if (d <= hitTolerance && d < bestDistance) {
        best = segment;
        bestDistance = d;
      }
    }
    return best;
  }

  double distance(RenderScenePoint a, RenderScenePoint b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

  double distanceToSegment(RenderScenePoint point, DrawingSegment segment) {
    final dx = segment.end.x - segment.start.x;
    final dy = segment.end.y - segment.start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-12) {
      return distance(point, segment.start);
    }
    final t = (((point.x - segment.start.x) * dx) +
            ((point.y - segment.start.y) * dy)) /
        lengthSquared;
    final clamped = t.clamp(0.0, 1.0).toDouble();
    final projected = RenderScenePoint(
      x: segment.start.x + dx * clamped,
      y: segment.start.y + dy * clamped,
      z: 0,
    );
    return distance(point, projected);
  }

  RenderScenePoint _gridPoint(RenderScenePoint point) {
    return RenderScenePoint(
      x: (point.x / gridSize).round() * gridSize,
      y: (point.y / gridSize).round() * gridSize,
      z: 0,
    );
  }

  DrawingSnap? _constrainAngle(
    RenderScenePoint start,
    RenderScenePoint rawEnd,
    List<DrawingSegment> existing,
  ) {
    final dx = rawEnd.x - start.x;
    final dy = rawEnd.y - start.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 1e-6) {
      return null;
    }
    final rawAngle = math.atan2(dy, dx);
    final candidates = <({double angle, DrawingSnapKind kind})>[
      (angle: 0, kind: DrawingSnapKind.parallel),
      (angle: math.pi / 2, kind: DrawingSnapKind.perpendicular),
      (angle: math.pi, kind: DrawingSnapKind.parallel),
      (angle: -math.pi / 2, kind: DrawingSnapKind.perpendicular),
    ];
    for (final segment in existing) {
      final segmentAngle = math.atan2(
        segment.end.y - segment.start.y,
        segment.end.x - segment.start.x,
      );
      candidates.add((angle: segmentAngle, kind: DrawingSnapKind.parallel));
      candidates.add((angle: segmentAngle + math.pi / 2, kind: DrawingSnapKind.perpendicular));
    }

    ({double angle, DrawingSnapKind kind})? best;
    var bestDelta = angleToleranceRadians;
    for (final candidate in candidates) {
      final delta = _angleDistance(rawAngle, candidate.angle);
      if (delta < bestDelta) {
        best = candidate;
        bestDelta = delta;
      }
    }
    if (best == null) {
      return null;
    }
    final end = RenderScenePoint(
      x: start.x + math.cos(best.angle) * length,
      y: start.y + math.sin(best.angle) * length,
      z: 0,
    );
    return DrawingSnap(
      point: end,
      kind: best.kind,
      distance: distance(rawEnd, end),
    );
  }

  double _angleDistance(double first, double second) {
    var delta = (first - second).abs() % (2 * math.pi);
    if (delta > math.pi) {
      delta = 2 * math.pi - delta;
    }
    return math.min(delta, (math.pi - delta).abs());
  }
}

List<DrawingSegment> drawingSegmentsFromScene(RenderScene scene) {
  return scene.objects
      .where((object) => object.kindKey == 'wall' && object.axis != null)
      .map(
        (object) => DrawingSegment(
          elementId: object.elementId,
          start: object.axis!.start,
          end: object.axis!.end,
          thickness: object.axis!.thickness,
        ),
      )
      .toList(growable: false);
}
