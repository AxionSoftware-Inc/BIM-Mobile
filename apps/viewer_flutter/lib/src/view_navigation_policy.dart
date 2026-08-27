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

    // 3D is an overview view, not a nearby-level view. Returning to it after
    // a plan must restore every storey; otherwise level overlays remain while
    // the geometry snapshot silently contains only the active neighbourhood.
    // Large IFC models use the native cache path for memory safety, so scope
    // streaming is not allowed to change the meaning of the 3D view.
    final useFullScene = mode.isElevation || (mode.is3D && !generatedSection);
    return ViewNavigationScope(
      refreshSceneScope: true,
      useFullScene: useFullScene,
      sourceLabel: useFullScene
          ? (mode.isElevation ? 'Full building elevation' : 'Full tower 3D')
          : 'Nearby levels',
    );
  }
}
