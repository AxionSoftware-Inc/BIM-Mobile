import 'dart:math' as math;

import '../../../../core/application/render_scene/render_scene_models.dart';

/// Validated straight-run stair preview shared by the stair tool and commit
/// command. The engine still owns the final stair element and mesh.
final class StairRunPreview {
  const StairRunPreview({
    required this.start,
    required this.direction,
    required this.runMeters,
    required this.riseMeters,
    required this.riserCount,
    required this.treadCount,
  });

  final RenderScenePoint start;
  final RenderScenePoint direction;
  final double runMeters;
  final double riseMeters;
  final int riserCount;
  final int treadCount;
}

final class StairLayoutMetrics {
  const StairLayoutMetrics({
    required this.totalRunMeters,
    required this.totalRiseMeters,
    required this.riserCount,
    required this.treadCount,
  });

  final double totalRunMeters;
  final double totalRiseMeters;
  final int riserCount;
  final int treadCount;
}

/// Pure stair constraints. No viewport, engine or widget dependency.
final class StairAuthoringGeometry {
  const StairAuthoringGeometry._();

  static StairRunPreview? preview({
    required RenderScenePoint start,
    required RenderScenePoint end,
    required RenderSceneLevel baseLevel,
    required RenderSceneLevel topLevel,
    double minimumRunMeters = 0.8,
    double riserHeightMeters = 0.175,
  }) {
    final run = start.distanceTo(end);
    final rise = topLevel.elevationMeters - baseLevel.elevationMeters;
    if (!run.isFinite ||
        run < minimumRunMeters ||
        !rise.isFinite ||
        rise <= 0.1) {
      return null;
    }
    final risers = (rise / riserHeightMeters).round().clamp(1, 60);
    return StairRunPreview(
      start: RenderScenePoint(
        x: start.x,
        y: start.y,
        z: baseLevel.elevationMeters,
      ),
      direction: RenderScenePoint(
        x: end.x - start.x,
        y: end.y - start.y,
        z: 0,
      ),
      runMeters: run,
      riseMeters: rise,
      riserCount: risers,
      treadCount: risers,
    );
  }

  static StairLayoutMetrics? layoutMetrics({
    required List<RenderScenePoint> pathPoints,
    required int requiredPointCount,
    required RenderSceneLevel baseLevel,
    required RenderSceneLevel topLevel,
    double minimumRunMeters = 0.8,
    double targetRiserMeters = 0.18,
    double targetTreadMeters = 0.28,
  }) {
    if (pathPoints.length < requiredPointCount) return null;
    var totalRun = 0.0;
    for (var index = 1; index < pathPoints.length; index += 1) {
      final segment = pathPoints[index].distanceTo(pathPoints[index - 1]);
      if (!segment.isFinite) return null;
      totalRun += segment;
    }
    final rise = topLevel.elevationMeters - baseLevel.elevationMeters;
    if (!totalRun.isFinite ||
        totalRun < minimumRunMeters ||
        !rise.isFinite ||
        rise <= 0.1) {
      return null;
    }
    return StairLayoutMetrics(
      totalRunMeters: totalRun,
      totalRiseMeters: rise,
      riserCount: math.max(1, (rise / targetRiserMeters).round()),
      treadCount: math.max(2, (totalRun / targetTreadMeters).round()),
    );
  }
}
