import '../../../../core/application/render_scene/render_scene_models.dart';
import '../../../elements/application/wall_element_parameters.dart';

/// Immutable selection plan for the automatic flat-roof workflow.
///
/// Geometry generation remains in the authoring geometry layer. This planner
/// only decides which authored level and wall set define the candidate roof,
/// keeping that policy out of Flutter state and dialogs.
final class AutomaticFlatRoofPlan {
  const AutomaticFlatRoofPlan({
    required this.roofLevelId,
    required this.boundWalls,
    required this.existingRoof,
  });

  final int roofLevelId;
  final List<RenderSceneObject> boundWalls;
  final bool existingRoof;
}

/// Pure policy for selecting the target level and wall loop candidates used by
/// automatic flat-roof authoring.
abstract final class AutomaticFlatRoofPlanner {
  static AutomaticFlatRoofPlan? plan({
    required RenderScene scene,
    required int baseLevelId,
  }) {
    final baseLevel = scene.levelById(baseLevelId);
    final candidates = scene.objects
        .where((object) => object.kindKey == 'wall')
        .where(
          (object) =>
              (WallElementParameters.fromObject(object).baseLevelId ??
                  object.levelId) ==
              baseLevelId,
        )
        .where((object) => object.elementId != null)
        .toList(growable: false);

    final topLevelIds = <int>{
      for (final wall in candidates)
        if ((WallElementParameters.fromObject(wall).topLevelId ?? 0) > 0)
          WallElementParameters.fromObject(wall).topLevelId!,
    };

    final roofLevelId = topLevelIds.isNotEmpty
        ? (topLevelIds.toList()
              ..sort(
                (left, right) => (scene.levelById(left)?.elevationMeters ?? 0)
                    .compareTo(scene.levelById(right)?.elevationMeters ?? 0),
              ))
            .last
        : (scene.levels
                .where(
                  (level) =>
                      baseLevel != null &&
                      level.elevationMeters > baseLevel.elevationMeters + 1e-6,
                )
                .toList()
              ..sort(
                (left, right) =>
                    left.elevationMeters.compareTo(right.elevationMeters),
              ))
            .firstOrNull
            ?.levelId;

    if (roofLevelId == null) return null;

    final boundWalls = candidates
        .where(
          (wall) =>
              (WallElementParameters.fromObject(wall).topLevelId ?? 0) ==
              roofLevelId,
        )
        .toList(growable: false);

    return AutomaticFlatRoofPlan(
      roofLevelId: roofLevelId,
      boundWalls: List<RenderSceneObject>.unmodifiable(boundWalls),
      existingRoof: scene.objects.any(
        (object) => object.kindKey == 'roof' && object.levelId == roofLevelId,
      ),
    );
  }
}
