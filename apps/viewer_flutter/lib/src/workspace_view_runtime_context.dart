/// Lightweight active-view context shared by documentation and family runtime.
///
/// This contains no scene or geometry references. It is only the semantic view
/// identity/level needed to choose lightweight 2D representations and to scope
/// view annotations. Keeping it separate prevents family/annotation systems
/// from depending on the workspace widget tree.
enum WorkspaceRuntimeViewKind {
  model3d,
  floorPlan,
  elevation,
  section,
  sheet,
  schedule,
  none,
}

abstract final class WorkspaceViewRuntimeContext {
  static String workspaceViewId = '';
  static int levelId = 0;
  static WorkspaceRuntimeViewKind kind = WorkspaceRuntimeViewKind.none;

  static bool get isModelViewport => switch (kind) {
        WorkspaceRuntimeViewKind.model3d ||
        WorkspaceRuntimeViewKind.floorPlan ||
        WorkspaceRuntimeViewKind.elevation ||
        WorkspaceRuntimeViewKind.section => true,
        _ => false,
      };

  static bool get isTwoDimensional => switch (kind) {
        WorkspaceRuntimeViewKind.floorPlan ||
        WorkspaceRuntimeViewKind.elevation ||
        WorkspaceRuntimeViewKind.section => true,
        _ => false,
      };

  static void activate({
    required String viewId,
    required int activeLevelId,
    required WorkspaceRuntimeViewKind viewKind,
  }) {
    workspaceViewId = viewId;
    levelId = activeLevelId;
    kind = viewKind;
  }

  static void clear() {
    workspaceViewId = '';
    levelId = 0;
    kind = WorkspaceRuntimeViewKind.none;
  }
}
