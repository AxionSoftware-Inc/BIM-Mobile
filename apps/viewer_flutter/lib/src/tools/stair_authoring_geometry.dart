import '../render_scene_models.dart';

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

/// Pure stair run constraints. No viewport, engine or widget dependency.
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
}
