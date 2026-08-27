import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';

/// Defines the presentation boundary between the authoritative BIM snapshot
/// and a viewport.
///
/// A viewport may receive a filtered scene and category defaults, but it must
/// never decide how walls, doors, or other domain objects are regenerated.
/// Keeping this decision in a small value object prevents an authoring change
/// from accidentally changing rendering policy in a widget callback.
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

    final activeLevel =
        scene.levelById(activeLevelId) ??
        (scene.levels.isNotEmpty ? scene.levels.first : null);
    if (activeLevel == null) {
      return scene;
    }

    return scene.filteredByVerticalRange(
      activeLevelId: activeLevel.levelId,
      bottomMeters: activeLevel.elevationMeters,
      topMeters: activeLevel.elevationMeters + planViewRangeMeters,
    );
  }

  Set<String> defaultVisibleKinds(RenderScene scene) {
    final available = scene.kindCounts.keys.toSet();
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      const preferred = <String>{
        'wall',
        'door',
        'window',
        'room',
        'floor',
        'ceiling',
        'column',
        'beam',
        'stair',
      };
      final visible = preferred.intersection(available);
      if (visible.isNotEmpty) {
        return visible;
      }
    }

    // Keep the initial 3D view architectural and solid. Imported/detail
    // proxies remain available through category controls.
    const architecturalKinds = <String>{
      'wall',
      'door',
      'window',
      'room',
      'floor',
      'ceiling',
      'column',
      'beam',
      'stair',
      'slab',
      'roof',
    };
    final architectural = architecturalKinds.intersection(available);
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
      for (final kind in <String>{'wall', 'door', 'window'})
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

  RenderSceneDisplayStyle get defaultDisplayStyle =>
      RenderSceneDisplayStyle.solid;
}
