import 'dart:math' as math;

import '../render_scene_editor.dart';
import '../render_scene_models.dart';
import '../render_scene_viewport_planar.dart';
import '../render_scene_viewport_types.dart';
import 'plan_sketch_geometry.dart';

/// Pure wall authoring geometry shared by wall draw and wall edit tools.
final class WallAuthoringGeometry {
  const WallAuthoringGeometry._();

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
  }) {
    final snapLevelId = _wallSnapLevelId(
      scene,
      activeLevelId: activeLevelId,
      excludeWallId: excludeWallId,
    );
    final candidatePoints = scene == null
        ? const <RenderScenePoint>[]
        : _wallEndpointCandidates(
            scene,
            rawPoint,
            referenceStart: referenceStart,
            levelId: snapLevelId,
            excludeWallId: excludeWallId,
            wallOrthogonalSnap: wallOrthogonalSnap,
          );
    final projectedCandidates = scene == null
        ? const <RenderScenePoint>[]
        : _wallProjectionCandidates(
            scene,
            rawPoint,
            referenceStart: referenceStart,
            excludeWallId: excludeWallId,
            levelId: snapLevelId,
            wallOrthogonalSnap: wallOrthogonalSnap,
          );
    return PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: rawPoint,
      referenceStart: referenceStart,
      candidatePoints: <RenderScenePoint>[
        ...candidatePoints,
        ...projectedCandidates,
      ],
      useGridSnap: snapToGrid,
      lockElevationAxis: projectionMode.isElevation,
      snapVertical: projectionMode.isElevation,
      orthogonalDominance: useOrthogonalSnap && wallOrthogonalSnap
          ? PlanSketchGeometry.wallOrthogonalDominance
          : null,
    );
  }

  static Iterable<RenderScenePoint> _wallEndpointCandidates(
    RenderScene scene,
    RenderScenePoint rawPoint, {
    required RenderScenePoint? referenceStart,
    required int? levelId,
    required int? excludeWallId,
    required bool wallOrthogonalSnap,
  }) sync* {
    final start = referenceStart;
    final dx = start == null ? 0.0 : rawPoint.x - start.x;
    final dy = start == null ? 0.0 : rawPoint.y - start.y;
    final dominance =
        wallOrthogonalSnap ? PlanSketchGeometry.wallOrthogonalDominance : 10.0;
    final horizontal = start != null && dx.abs() > dy.abs() * dominance;
    final vertical = start != null && dy.abs() > dx.abs() * dominance;

    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          wall.elementId == excludeWallId ||
          (levelId != null && wall.levelId != levelId)) {
        continue;
      }
      final wallStart = RenderSceneEditor.wallStartPoint(wall);
      final wallEnd = RenderSceneEditor.wallEndPoint(wall);
      if (wallStart == null || wallEnd == null) continue;
      final axisX = wallEnd.x - wallStart.x;
      final axisY = wallEnd.y - wallStart.y;
      final wallLength = math.sqrt(axisX * axisX + axisY * axisY);
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

  static Iterable<RenderScenePoint> _wallProjectionCandidates(
    RenderScene scene,
    RenderScenePoint point, {
    required RenderScenePoint? referenceStart,
    required int? excludeWallId,
    required int? levelId,
    required bool wallOrthogonalSnap,
  }) sync* {
    final start = referenceStart;
    final dx = start == null ? 0.0 : point.x - start.x;
    final dy = start == null ? 0.0 : point.y - start.y;
    final dominance =
        wallOrthogonalSnap ? PlanSketchGeometry.wallOrthogonalDominance : 10.0;
    final horizontal = start != null && dx.abs() > dy.abs() * dominance;
    final vertical = start != null && dy.abs() > dx.abs() * dominance;

    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          wall.elementId == excludeWallId ||
          (levelId != null && wall.levelId != levelId)) {
        continue;
      }
      final wallStart = RenderSceneEditor.wallStartPoint(wall);
      final wallEnd = RenderSceneEditor.wallEndPoint(wall);
      if (wallStart == null || wallEnd == null) continue;
      final axisX = wallEnd.x - wallStart.x;
      final axisY = wallEnd.y - wallStart.y;
      final lengthSquared = axisX * axisX + axisY * axisY;
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
  }) sync* {
    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          wall.elementId == excludeWallId ||
          (levelId != null && wall.levelId != levelId)) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      if (start == null || end == null) continue;
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

  static RenderScenePoint snapMovedWallPoint(
    RenderScene scene,
    RenderSceneObject wall,
    RenderScenePoint point,
    RenderScenePoint originalPoint, {
    double toleranceMeters = 0.45,
    bool snapToGrid = true,
  }) {
    var bestPoint = snapPoint(point, enabled: snapToGrid);
    var bestDistance = toleranceMeters;
    final candidates = <RenderScenePoint?>[
      ...wallSnapCandidates(
        scene,
        point,
        excludeWallId: wall.elementId,
        levelId: wall.levelId,
      ),
    ];
    for (final object in scene.objects) {
      if (object.kindKey != 'wall' ||
          object.elementId == wall.elementId ||
          (wall.levelId != null && object.levelId != wall.levelId)) {
        continue;
      }
      candidates
        ..add(RenderSceneEditor.wallStartPoint(object))
        ..add(RenderSceneEditor.wallEndPoint(object));
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
