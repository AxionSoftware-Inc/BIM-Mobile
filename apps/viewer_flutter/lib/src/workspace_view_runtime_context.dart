// COMPATIBILITY: legacy mutable runtime mirror used by pre-migration callers.
// REMOVE WHEN: remaining family/documentation consumers receive active-view
// state through application composition instead of a process-global static.

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
