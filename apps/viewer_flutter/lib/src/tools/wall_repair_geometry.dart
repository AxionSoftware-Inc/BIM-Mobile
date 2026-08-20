import 'dart:math' as math;

import '../render_scene_editor.dart';
import '../render_scene_models.dart';
import 'plan_sketch_geometry.dart';

/// A bounded, user-intended repair between two wall endpoints.
///
/// This is deliberately a candidate, not a mutation. The UI can preview or
/// commit it through the native transaction boundary. Limiting the endpoint
/// gap prevents a repair command from pulling unrelated walls across a plan.
class WallRepairCandidate {
  const WallRepairCandidate({
    required this.firstWallId,
    required this.firstEndpoint,
    required this.secondWallId,
    required this.secondEndpoint,
    required this.intersection,
    required this.firstGapMeters,
    required this.secondGapMeters,
  });

  final int firstWallId;
  final PlanSketchEndpoint firstEndpoint;
  final int secondWallId;
  final PlanSketchEndpoint secondEndpoint;
  final RenderScenePoint intersection;
  final double firstGapMeters;
  final double secondGapMeters;

  double get maxGapMeters => math.max(firstGapMeters, secondGapMeters);
  double get totalGapMeters => firstGapMeters + secondGapMeters;

  String get key =>
      '$firstWallId:$secondWallId:${firstEndpoint.index}:${secondEndpoint.index}';
}

/// Finds only the closest non-parallel endpoint pairs that can be repaired by
/// Trim/Extend. It never invents a bounding box and never repairs across
/// levels. This keeps the one-tap surface repair safe for L-shaped and
/// multi-room plans.
class WallRepairGeometry {
  const WallRepairGeometry._();

  static const double defaultMaximumGapMeters = 1.5;
  static const double minimumRepairGapMeters = 0.08;

  static WallRepairCandidate? bestCandidate(
    RenderScene scene, {
    Iterable<int>? wallIds,
    int? levelId,
    double maximumGapMeters = defaultMaximumGapMeters,
    Set<String>? excludedPairs,
  }) {
    if (!maximumGapMeters.isFinite || maximumGapMeters <= 0) return null;
    final allowedIds = wallIds?.toSet();
    final walls = scene.objects
        .where((object) => object.kindKey == 'wall')
        .where((object) => object.elementId != null)
        .where((object) => levelId == null || object.levelId == levelId)
        .where((object) =>
            allowedIds == null || allowedIds.contains(object.elementId))
        .toList(growable: false);

    WallRepairCandidate? best;
    for (var firstIndex = 0; firstIndex < walls.length; firstIndex++) {
      final first = walls[firstIndex];
      final firstStart = RenderSceneEditor.wallStartPoint(first);
      final firstEnd = RenderSceneEditor.wallEndPoint(first);
      if (firstStart == null || firstEnd == null) continue;
      for (var secondIndex = firstIndex + 1;
          secondIndex < walls.length;
          secondIndex++) {
        final second = walls[secondIndex];
        if (first.levelId != second.levelId) continue;
        final secondStart = RenderSceneEditor.wallStartPoint(second);
        final secondEnd = RenderSceneEditor.wallEndPoint(second);
        if (secondStart == null || secondEnd == null) continue;

        final firstLine = PlanSketchLine(start: firstStart, end: firstEnd);
        final secondLine = PlanSketchLine(start: secondStart, end: secondEnd);
        for (final firstEndpoint in PlanSketchEndpoint.values) {
          for (final secondEndpoint in PlanSketchEndpoint.values) {
            final preview = PlanSketchGeometry.trimExtend(
              first: firstLine,
              firstEndpoint: firstEndpoint,
              second: secondLine,
              secondEndpoint: secondEndpoint,
            );
            if (preview == null) continue;
            final firstGap = PlanSketchGeometry.planDistance(
              firstLine.pointAt(firstEndpoint),
              preview.intersection,
            );
            final secondGap = PlanSketchGeometry.planDistance(
              secondLine.pointAt(secondEndpoint),
              preview.intersection,
            );
            if (firstGap < minimumRepairGapMeters &&
                secondGap < minimumRepairGapMeters) {
              continue;
            }
            if (firstGap > maximumGapMeters || secondGap > maximumGapMeters) {
              continue;
            }
            final candidate = WallRepairCandidate(
              firstWallId: first.elementId!,
              firstEndpoint: firstEndpoint,
              secondWallId: second.elementId!,
              secondEndpoint: secondEndpoint,
              intersection: preview.intersection,
              firstGapMeters: firstGap,
              secondGapMeters: secondGap,
            );
            if (excludedPairs?.contains(candidate.key) ?? false) {
              continue;
            }
            final previous = best;
            if (previous == null || _score(candidate) < _score(previous)) {
              best = candidate;
            }
          }
        }
      }
    }
    return best;
  }

  static double _score(WallRepairCandidate candidate) =>
      (candidate.maxGapMeters * 2.0) + candidate.totalGapMeters;
}
