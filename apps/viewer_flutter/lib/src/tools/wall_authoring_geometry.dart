import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../render_scene_editor.dart';
import '../render_scene_models.dart';
import '../render_scene_viewport_planar.dart';
import '../render_scene_viewport_types.dart';
import 'plan_sketch_geometry.dart';

/// Precomputed wall axes used by live snapping. Building this once per scene
/// avoids extracting endpoints and recomputing wall vectors for every pointer
/// sample during a drag.
@immutable
class WallSnapSegment {
  const WallSnapSegment({
    required this.elementId,
    required this.levelId,
    required this.start,
    required this.end,
    this.thicknessMeters = 0.0,
    this.profileCorners = const <RenderScenePoint>[],
  });

  final int? elementId;
  final int? levelId;
  final RenderScenePoint start;
  final RenderScenePoint end;
  final double thicknessMeters;
  final List<RenderScenePoint> profileCorners;

  double get axisX => end.x - start.x;
  double get axisY => end.y - start.y;
  double get lengthSquared => axisX * axisX + axisY * axisY;

  /// The final plan profile corners produced by the native wall geometry. A
  /// joined wall has mitered or trimmed endpoint corners here, so the two
  /// pre-join face corners never become snap targets. A zero thickness keeps
  /// manually constructed test segments and legacy data compatible.
  Iterable<RenderScenePoint> get faceCorners sync* {
    if (profileCorners.isNotEmpty) {
      yield* profileCorners;
      return;
    }

    final length = math.sqrt(lengthSquared);
    final halfThickness = thicknessMeters.abs() * 0.5;
    if (length <= 1e-9 || halfThickness <= 1e-9) {
      yield start;
      yield end;
      return;
    }
    final offsetX = -axisY / length * halfThickness;
    final offsetY = axisX / length * halfThickness;
    yield RenderScenePoint(
      x: start.x + offsetX,
      y: start.y + offsetY,
      z: start.z,
    );
    yield RenderScenePoint(
      x: start.x - offsetX,
      y: start.y - offsetY,
      z: start.z,
    );
    yield RenderScenePoint(
      x: end.x + offsetX,
      y: end.y + offsetY,
      z: end.z,
    );
    yield RenderScenePoint(
      x: end.x - offsetX,
      y: end.y - offsetY,
      z: end.z,
    );
  }
}

@immutable
class WallSnapIndex {
  const WallSnapIndex(this.segments);

  factory WallSnapIndex.fromScene(
    RenderScene scene, {
    int? levelId,
    int? excludeWallId,
  }) {
    final segments = <WallSnapSegment>[];
    for (final object in scene.objects) {
      if (object.kindKey != 'wall' ||
          object.elementId == excludeWallId ||
          (levelId != null && object.levelId != levelId)) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(object);
      final end = RenderSceneEditor.wallEndPoint(object);
      if (start == null || end == null) continue;
      final wallThickness = RenderSceneEditor.wallThickness(object);
      final profileCorners = _parseWallProfileCorners(object.metadata);
      final segment = WallSnapSegment(
        elementId: object.elementId,
        levelId: object.levelId,
        start: start,
        end: end,
        thicknessMeters: wallThickness != null && wallThickness.isFinite
            ? wallThickness
            : RenderSceneEditor.defaultWallThicknessMeters,
        profileCorners: profileCorners,
      );
      if (segment.lengthSquared <= 1e-9) continue;
      segments.add(segment);
    }
    return WallSnapIndex(List<WallSnapSegment>.unmodifiable(segments));
  }

  final List<WallSnapSegment> segments;
}

List<RenderScenePoint> _parseWallProfileCorners(
  Map<String, Object?> metadata,
) {
  final raw = metadata['profile_corners'] ?? metadata['profileCorners'];
  if (raw is String) {
    final corners = <RenderScenePoint>[];
    for (final token in raw.split(';')) {
      final values = token.split(',');
      if (values.length < 2) continue;
      final x = double.tryParse(values[0].trim());
      final y = double.tryParse(values[1].trim());
      if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
      corners.add(RenderScenePoint(x: x, y: y, z: 0.0));
    }
    return List<RenderScenePoint>.unmodifiable(corners);
  }

  if (raw is List) {
    final corners = raw
        .map(RenderScenePoint.fromJson)
        .whereType<RenderScenePoint>()
        .toList(growable: false);
    return List<RenderScenePoint>.unmodifiable(corners);
  }
  return const <RenderScenePoint>[];
}

/// Pure wall authoring geometry shared by wall draw and wall edit tools.
final class WallAuthoringGeometry {
  const WallAuthoringGeometry._();

  /// Finger wall authoring snaps to a decimetre grid. When grid snap is off,
  /// the freehand result is still quantized to 10 mm so touch noise cannot
  /// create values such as 5532 mm; intentional 5530 mm remains possible.
  static const double wallGridStepMeters = 0.10;
  static const double wallFreehandPrecisionMeters = 0.01;

  static RenderScenePoint snapPoint(
    RenderScenePoint point, {
    bool enabled = true,
    double stepMeters = 0.25,
  }) {
    if (!enabled || stepMeters <= 0) return point;
    return PlanSketchGeometry.snapToGrid(point, stepMeters: stepMeters);
  }

  static RenderScenePoint resolveLineEndpoint({
    required RenderScenePoint rawPoint,
    required RenderScenePoint? referenceStart,
    required RenderScene? scene,
    required int? activeLevelId,
    required bool snapToGrid,
    required RenderSceneProjectionMode projectionMode,
    required bool useOrthogonalSnap,
    required bool wallOrthogonalSnap,
    int? excludeWallId,
    WallSnapIndex? snapIndex,
  }) {
    final index = snapIndex ??
        (scene == null
            ? const WallSnapIndex(<WallSnapSegment>[])
            : WallSnapIndex.fromScene(
                scene,
                levelId: _wallSnapLevelId(
                  scene,
                  activeLevelId: activeLevelId,
                  excludeWallId: excludeWallId,
                ),
                excludeWallId: excludeWallId,
              ));
    final candidatePoints = _wallEndpointCandidates(
      index,
      rawPoint,
      referenceStart: referenceStart,
      wallOrthogonalSnap: wallOrthogonalSnap,
    );
    final alignmentCandidates = _wallAlignmentCandidates(
      index,
      rawPoint,
      referenceStart: referenceStart,
      wallOrthogonalSnap: wallOrthogonalSnap,
    );
    final projectedCandidates = _wallProjectionCandidates(
      index,
      rawPoint,
      referenceStart: referenceStart,
      wallOrthogonalSnap: wallOrthogonalSnap,
    );
    final resolved = PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: rawPoint,
      referenceStart: referenceStart,
      candidatePoints: <RenderScenePoint>[
        ...candidatePoints,
        ...alignmentCandidates,
        ...projectedCandidates,
      ],
      useGridSnap: snapToGrid,
      gridStepMeters: wallOrthogonalSnap
          ? wallGridStepMeters
          : PlanSketchGeometry.defaultGridStepMeters,
      lockElevationAxis: projectionMode.isElevation,
      snapVertical: projectionMode.isElevation,
      orthogonalDominance: useOrthogonalSnap && wallOrthogonalSnap
          ? PlanSketchGeometry.wallOrthogonalDominance
          : null,
    );
    if (wallOrthogonalSnap && !snapToGrid && referenceStart != null) {
      return _quantizeFreehandLength(resolved, referenceStart);
    }
    return resolved;
  }

  static Iterable<RenderScenePoint> _wallEndpointCandidates(
    WallSnapIndex index,
    RenderScenePoint rawPoint, {
    required RenderScenePoint? referenceStart,
    required bool wallOrthogonalSnap,
  }) sync* {
    final start = referenceStart;
    final dx = start == null ? 0.0 : rawPoint.x - start.x;
    final dy = start == null ? 0.0 : rawPoint.y - start.y;
    final dominance =
        wallOrthogonalSnap ? PlanSketchGeometry.wallOrthogonalDominance : 10.0;
    final horizontal = start != null && dx.abs() > dy.abs() * dominance;
    final vertical = start != null && dy.abs() > dx.abs() * dominance;

    for (final wall in index.segments) {
      final wallStart = wall.start;
      final wallEnd = wall.end;
      final axisX = wall.axisX;
      final axisY = wall.axisY;
      final wallLength = math.sqrt(wall.lengthSquared);
      if (wallLength <= 1e-9) continue;
      final parallelToIntent = (horizontal || vertical) &&
          ((horizontal && axisX.abs() >= axisY.abs()) ||
              (vertical && axisY.abs() >= axisX.abs()));
      for (final candidate in <RenderScenePoint>[wallStart, wallEnd]) {
        if (start != null && candidate.distanceTo(start) <= 0.08) continue;
        // A nearby parallel wall is not a continuation target. Its endpoint
        // is accepted only when it is essentially collinear with the active
        // wall, preserving true end-to-end chains without the old jump to a
        // neighbouring parallel wall.
        if (parallelToIntent) {
          final axisGap = horizontal
              ? (candidate.y - start.y).abs()
              : (candidate.x - start.x).abs();
          if (axisGap > 0.08) continue;
        }
        yield candidate;
      }
    }
  }

  /// Adds virtual alignment guides through the active wall's start point.
  ///
  /// A normal endpoint snap only works when the pointer is close to the
  /// existing endpoint in both axes. For tablet authoring that makes a
  /// distant corner useless: the user often wants the new wall's endpoint to
  /// line up with an existing corner several metres away. These projected
  /// points keep the normal touch tolerance along the wall, while allowing
  /// the perpendicular distance to be arbitrary. Diagonal wall axes also get
  /// an infinite parallel guide when the drag is already close to that angle.
  static Iterable<RenderScenePoint> _wallAlignmentCandidates(
    WallSnapIndex index,
    RenderScenePoint rawPoint, {
    required RenderScenePoint? referenceStart,
    required bool wallOrthogonalSnap,
  }) sync* {
    final start = referenceStart;
    if (start == null || !wallOrthogonalSnap) return;

    final dx = rawPoint.x - start.x;
    final dy = rawPoint.y - start.y;
    final dominance = PlanSketchGeometry.wallOrthogonalDominance;
    final horizontal = dx.abs() > dy.abs() * dominance;
    final vertical = dy.abs() > dx.abs() * dominance;

    if (horizontal || vertical) {
      for (final wall in index.segments) {
        for (final corner in <RenderScenePoint>[wall.start, wall.end]) {
          yield horizontal
              ? RenderScenePoint(x: corner.x, y: start.y, z: rawPoint.z)
              : RenderScenePoint(x: start.x, y: corner.y, z: rawPoint.z);
        }
      }
      return;
    }

    final rawLength = math.sqrt(dx * dx + dy * dy);
    if (rawLength <= 1e-9) return;
    for (final wall in index.segments) {
      final wallLength = math.sqrt(wall.lengthSquared);
      if (wallLength <= 1e-9) continue;
      final ux = wall.axisX / wallLength;
      final uy = wall.axisY / wallLength;
      final direction = dx * ux + dy * uy >= 0 ? 1.0 : -1.0;
      final orientedX = ux * direction;
      final orientedY = uy * direction;
      final along = dx * orientedX + dy * orientedY;
      if (along <= 0) continue;
      final projection = RenderScenePoint(
        x: start.x + orientedX * along,
        y: start.y + orientedY * along,
        z: rawPoint.z,
      );
      if (projection.distanceTo(rawPoint) <=
          PlanSketchGeometry.defaultEndpointToleranceMeters) {
        yield projection;
      }
    }
  }

  static Iterable<RenderScenePoint> _wallProjectionCandidates(
    WallSnapIndex index,
    RenderScenePoint point, {
    required RenderScenePoint? referenceStart,
    required bool wallOrthogonalSnap,
  }) sync* {
    final start = referenceStart;
    final dx = start == null ? 0.0 : point.x - start.x;
    final dy = start == null ? 0.0 : point.y - start.y;
    final dominance =
        wallOrthogonalSnap ? PlanSketchGeometry.wallOrthogonalDominance : 10.0;
    final horizontal = start != null && dx.abs() > dy.abs() * dominance;
    final vertical = start != null && dy.abs() > dx.abs() * dominance;

    for (final wall in index.segments) {
      final wallStart = wall.start;
      final axisX = wall.axisX;
      final axisY = wall.axisY;
      final lengthSquared = wall.lengthSquared;
      if (lengthSquared <= 1e-9) continue;
      final parallelToIntent = (horizontal || vertical) &&
          ((horizontal && axisX.abs() >= axisY.abs()) ||
              (vertical && axisY.abs() >= axisX.abs()));
      // Projection onto another parallel wall is the ambiguous case. A
      // perpendicular wall projection remains useful for a T-junction.
      if (parallelToIntent) continue;
      final t =
          (((point.x - wallStart.x) * axisX + (point.y - wallStart.y) * axisY) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      final projection = RenderScenePoint(
        x: wallStart.x + axisX * t,
        y: wallStart.y + axisY * t,
        z: point.z,
      );
      if (projection.distanceTo(point) <= 0.35) yield projection;
    }
  }

  static Iterable<RenderScenePoint> wallSnapCandidates(
    RenderScene scene,
    RenderScenePoint point, {
    int? excludeWallId,
    int? levelId,
    double toleranceMeters = 0.35,
    WallSnapIndex? snapIndex,
  }) sync* {
    final index = snapIndex ??
        WallSnapIndex.fromScene(
          scene,
          levelId: levelId,
          excludeWallId: excludeWallId,
        );
    for (final wall in index.segments) {
      final start = wall.start;
      final end = wall.end;
      final axis = end - start;
      final lengthSquared = axis.x * axis.x + axis.y * axis.y;
      if (lengthSquared <= 1e-9) continue;
      final t = (((point.x - start.x) * axis.x + (point.y - start.y) * axis.y) /
              lengthSquared)
          .clamp(0.0, 1.0);
      final projection = RenderScenePoint(
        x: start.x + axis.x * t,
        y: start.y + axis.y * t,
        z: point.z,
      );
      if (projection.distanceTo(point) <= toleranceMeters) {
        yield projection;
      }
    }
  }

  /// Snaps a floor/ceiling/roof boundary point to a wall face corner.
  ///
  /// Only the four plan corners created from the wall thickness are accepted:
  /// the two inner and two outer corners. The wall centre line and arbitrary
  /// points along the wall are deliberately excluded, so a touch cannot pull
  /// a boundary vertex to an unintended location on the wall body.
  static RenderScenePoint? snapBoundaryPointToWalls(
    RenderScenePoint point, {
    required WallSnapIndex snapIndex,
    double cornerToleranceMeters = 0.60,
  }) {
    if (!point.isFinite || snapIndex.segments.isEmpty) return null;

    RenderScenePoint? nearestCorner;
    var nearestCornerDistance = cornerToleranceMeters;
    for (final wall in snapIndex.segments) {
      for (final corner in wall.faceCorners) {
        final distance = PlanSketchGeometry.planDistance(point, corner);
        if (distance < nearestCornerDistance) {
          nearestCornerDistance = distance;
          nearestCorner = corner;
        }
      }
    }
    if (nearestCorner != null) {
      return RenderScenePoint(
        x: nearestCorner.x,
        y: nearestCorner.y,
        z: point.z,
      );
    }
    return null;
  }

  static RenderScenePoint snapMovedWallPoint(
    RenderScene scene,
    RenderSceneObject wall,
    RenderScenePoint point,
    RenderScenePoint originalPoint, {
    double toleranceMeters = 0.45,
    bool snapToGrid = true,
    WallSnapIndex? snapIndex,
  }) {
    var bestPoint = snapPoint(point, enabled: snapToGrid);
    var bestDistance = toleranceMeters;
    final candidates = <RenderScenePoint?>[
      ...wallSnapCandidates(
        scene,
        point,
        excludeWallId: wall.elementId,
        levelId: wall.levelId,
        snapIndex: snapIndex,
      ),
    ];
    final index = snapIndex ??
        WallSnapIndex.fromScene(
          scene,
          levelId: wall.levelId,
          excludeWallId: wall.elementId,
        );
    for (final segment in index.segments) {
      candidates
        ..add(segment.start)
        ..add(segment.end);
    }
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final distance = candidate.distanceTo(point);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = candidate;
      }
    }
    return RenderScenePoint(
      x: bestPoint.x,
      y: bestPoint.y,
      z: originalPoint.z,
    );
  }

  static RenderScenePoint projectToWallNormal(
    RenderScenePoint point, {
    required RenderScenePoint anchor,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) {
    final axis = end - start;
    final lengthSquared = axis.x * axis.x + axis.y * axis.y;
    if (lengthSquared <= 1e-9) {
      return RenderScenePoint(x: anchor.x, y: anchor.y, z: point.z);
    }
    final normal = RenderScenePoint(x: -axis.y, y: axis.x, z: 0);
    final fromAnchor = point - anchor;
    final t =
        (fromAnchor.x * normal.x + fromAnchor.y * normal.y) / lengthSquared;
    return RenderScenePoint(
      x: anchor.x + normal.x * t,
      y: anchor.y + normal.y * t,
      z: point.z,
    );
  }

  static double snapDouble(
    double value, {
    bool enabled = true,
    double step = 0.25,
  }) {
    if (!enabled || step <= 0) return value;
    return (value / step).roundToDouble() * step;
  }

  static String formatWallLengthMeters(double lengthMeters) {
    if (!lengthMeters.isFinite || lengthMeters < 0) return '0.00 m';
    final millimeters =
        (lengthMeters * 1000.0 / (wallFreehandPrecisionMeters * 1000.0))
                .round() *
            (wallFreehandPrecisionMeters * 1000.0).round();
    final meters = millimeters / 1000.0;
    return '${meters.toStringAsFixed(2)} m';
  }

  static RenderScenePoint _quantizeFreehandLength(
    RenderScenePoint point,
    RenderScenePoint start,
  ) {
    final dx = point.x - start.x;
    final dy = point.y - start.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 1e-9) return point;
    final step = wallFreehandPrecisionMeters;
    final quantizedLength = (length / step).roundToDouble() * step;
    final scale = quantizedLength / length;
    return RenderScenePoint(
      x: start.x + dx * scale,
      y: start.y + dy * scale,
      z: point.z,
    );
  }

  static int? _wallSnapLevelId(
    RenderScene? scene, {
    required int? activeLevelId,
    int? excludeWallId,
  }) {
    if (scene != null && excludeWallId != null) {
      for (final object in scene.objects) {
        if (object.kindKey == 'wall' && object.elementId == excludeWallId) {
          return object.levelId ?? activeLevelId;
        }
      }
    }
    return activeLevelId;
  }
}
