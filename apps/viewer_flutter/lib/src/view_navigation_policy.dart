import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_types.dart';

/// The render scope required when a view changes projection.
///
/// This is deliberately independent of Flutter state and repositories. It is
/// the single policy used by the workspace when deciding whether a plan,
/// elevation, or orbit view needs a full-scene refresh.
class ViewNavigationScope {
  const ViewNavigationScope({
    required this.refreshSceneScope,
    required this.useFullScene,
    required this.sourceLabel,
  });

  final bool refreshSceneScope;
  final bool useFullScene;
  final String sourceLabel;
}

/// Pure view-navigation policy shared by browser, tabs and the workspace.
final class ViewNavigationPolicy {
  const ViewNavigationPolicy._();

  static const int _largeSceneObjectThreshold = 120;

  static ViewNavigationScope scopeFor({
    required RenderSceneProjectionMode mode,
    required int objectCount,
    required bool generatedSection,
  }) {
    final refreshSceneScope = mode.isElevation || mode.is3D;
    if (!refreshSceneScope) {
      return const ViewNavigationScope(
        refreshSceneScope: false,
        useFullScene: false,
        sourceLabel: 'Nearby levels',
      );
    }

    final isLargeScene = objectCount > _largeSceneObjectThreshold;
    final useFullScene =
        mode.isElevation || (mode.is3D && !isLargeScene && !generatedSection);
    return ViewNavigationScope(
      refreshSceneScope: true,
      useFullScene: useFullScene,
      sourceLabel: useFullScene
          ? (mode.isElevation ? 'Full building elevation' : 'Full tower 3D')
          : 'Nearby levels',
    );
  }
}
