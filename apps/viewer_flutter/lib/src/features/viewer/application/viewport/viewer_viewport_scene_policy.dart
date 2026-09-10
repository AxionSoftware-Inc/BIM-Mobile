import '../../../elements/application/bim_element_registry.dart';
import '../../../../render_scene_models.dart';
import '../../domain/view/view_configuration.dart';

/// Defines the presentation boundary between the authoritative BIM snapshot
/// and a viewport.
///
/// A viewport may receive a filtered scene and category defaults, but it must
/// never decide how walls, doors, or other domain objects are regenerated.
/// Keeping this decision in a small value object prevents an authoring change
/// from accidentally changing rendering policy in a widget callback.
///
/// MIGRATION: RenderScene is still a root engine DTO library. Keep that known
/// dependency explicit until the render-scene contract is split from Flutter
/// annotations and element-registry helpers; do not hide it behind a facade.
final class ViewerViewportScenePolicy {
  const ViewerViewportScenePolicy({
    required this.projectionMode,
    required this.activeLevelId,
    this.planViewRangeMeters = 2.0,
  });

  final RenderSceneProjectionMode projectionMode;
  final int? activeLevelId;
  final double planViewRangeMeters;

  RenderScene sceneForViewport(RenderScene scene) {
    if (projectionMode != RenderSceneProjectionMode.topDown) {
      return scene;
    }

    final activeLevel = scene.levelById(activeLevelId) ??
        (scene.levels.isNotEmpty ? scene.levels.first : null);
    if (activeLevel == null) {
      return scene;
    }

    return scene.filteredByVerticalRange(
      activeLevelId: activeLevel.levelId,
      bottomMeters: activeLevel.elevationMeters,
      topMeters: activeLevel.elevationMeters + planViewRangeMeters,
      stripFamilyMeshes: true,
    );
  }

  Set<String> defaultVisibleKinds(RenderScene scene) {
    final available = scene.kindCounts.keys.toSet();
    final familyKinds = <String>{
      for (final object in scene.objects)
        if ((object.kindKey == 'column' || object.kindKey == 'proxy') &&
            (object.metadata['family_asset_id']?.toString().trim().isNotEmpty ??
                false))
          object.kindKey,
    };
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      final visible = <String>{
        ...BimElementRegistry.standard.planCoreKinds,
        ...familyKinds,
      }.intersection(available);
      if (visible.isNotEmpty) {
        return visible;
      }
    }

    final architectural = <String>{
      ...BimElementRegistry.standard.architecturalKinds,
      ...familyKinds,
    }.intersection(available);
    if (architectural.isNotEmpty) {
      return architectural;
    }
    return <String>{};
  }

  Set<String> ensurePlanCoreVisibility(Set<String> kinds, RenderScene scene) {
    if (projectionMode != RenderSceneProjectionMode.topDown || kinds.isEmpty) {
      return kinds;
    }
    final available = scene.kindCounts.keys.toSet();
    return <String>{
      ...kinds,
      for (final kind in BimElementRegistry.standard.planCoreKinds)
        if (available.contains(kind)) kind,
    };
  }

  Set<String> sanitizeVisibleKinds({
    required Set<String> visibleKinds,
    required RenderScene scene,
  }) {
    if (visibleKinds.isEmpty) {
      return <String>{};
    }
    return visibleKinds.intersection(scene.kindCounts.keys.toSet());
  }

  int? resolveInitialLevelId(RenderScene scene, {int? preferred}) {
    final levels = scene.levels;
    if (levels.isEmpty) return preferred;
    if (preferred != null && scene.levelById(preferred) != null) {
      return preferred;
    }
    return levels.first.levelId;
  }

  RenderSceneLevel? activeLevel(RenderScene? scene) {
    if (scene == null) return null;
    return scene.levelById(activeLevelId) ??
        (scene.levels.isNotEmpty ? scene.levels.first : null);
  }

  double activeLevelElevation(RenderScene? scene) =>
      activeLevel(scene)?.elevationMeters ?? 0.0;

  double activeLevelDefaultWallHeight(
    RenderScene? scene, {
    required double fallbackMeters,
  }) =>
      activeLevel(scene)?.defaultWallHeightMeters ?? fallbackMeters;

  RenderSceneLevel? pickLevelAtElevation(
    RenderScene scene,
    RenderScenePoint? modelPoint, {
    double toleranceMeters = 1.4,
  }) {
    if (modelPoint == null ||
        !(projectionMode.isElevation ||
            projectionMode.supportsPlanFootprintEditing)) {
      return null;
    }
    RenderSceneLevel? bestLevel;
    var bestDistance = toleranceMeters;
    for (final level in scene.levels) {
      final distance = (modelPoint.z - level.elevationMeters).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestLevel = level;
      }
    }
    return bestLevel;
  }

  RenderSceneLevel? nextHigherLevel(RenderScene scene, int baseLevelId) {
    final base = scene.levelById(baseLevelId);
    if (base == null) return null;
    final sorted = [...scene.levels]
      ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
    for (final level in sorted) {
      if (level.elevationMeters > base.elevationMeters + 1e-6) {
        return level;
      }
    }
    return null;
  }

  RenderSceneDisplayStyle get defaultDisplayStyle =>
      RenderSceneDisplayStyle.solid;
}
