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
        : scene.objects
            .where(
              (wall) =>
                  wall.kindKey == 'wall' &&
                  (snapLevelId == null || wall.levelId == snapLevelId) &&
                  wall.elementId != excludeWallId,
            )
            .expand<RenderScenePoint?>((wall) => <RenderScenePoint?>[
                  RenderSceneEditor.wallStartPoint(wall),
                  RenderSceneEditor.wallEndPoint(wall),
                ])
            .whereType<RenderScenePoint>()
            .where((candidate) =>
                referenceStart == null ||
                candidate.distanceTo(referenceStart) > 0.08);
    final projectedCandidates = scene == null
        ? const <RenderScenePoint>[]
        : wallSnapCandidates(
            scene,
            rawPoint,
            excludeWallId: excludeWallId,
            levelId: snapLevelId,
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
