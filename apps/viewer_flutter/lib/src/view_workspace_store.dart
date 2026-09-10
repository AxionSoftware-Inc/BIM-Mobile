// COMPATIBILITY: legacy adapter while viewer_app still imports the root store.
// REMOVE WHEN: viewer composition creates the canonical store with an explicit
// active-view runtime adapter.
import 'annotations/annotation_workspace_runtime.dart';
import 'features/viewer/application/workspace/opened_view_tab.dart';
import 'features/viewer/application/workspace/view_workspace_store.dart'
    as canonical;
import 'workspace_view_runtime_context.dart';

class ViewWorkspaceStore extends canonical.ViewWorkspaceStore {
  ViewWorkspaceStore.standard()
      : super.standard(onActiveViewChanged: _syncLegacyRuntime);

  static const String threeDViewId = canonical.ViewWorkspaceStore.threeDViewId;

  static String floorPlanId(int levelId) =>
      canonical.ViewWorkspaceStore.floorPlanId(levelId);

  static void _syncLegacyRuntime(OpenedViewTab? tab) {
    if (tab == null) {
      WorkspaceViewRuntimeContext.clear();
      AnnotationWorkspaceRuntime.activateView(
        workspaceViewId: '',
        levelId: 0,
        acceptsAnnotations: false,
      );
      return;
    }
    final runtimeKind = switch (tab.kind) {
      OpenedViewKind.threeD => WorkspaceRuntimeViewKind.model3d,
      OpenedViewKind.floorPlan => WorkspaceRuntimeViewKind.floorPlan,
      OpenedViewKind.elevation => WorkspaceRuntimeViewKind.elevation,
      OpenedViewKind.section => WorkspaceRuntimeViewKind.section,
      OpenedViewKind.sheet => WorkspaceRuntimeViewKind.sheet,
      OpenedViewKind.schedule => WorkspaceRuntimeViewKind.schedule,
    };
    WorkspaceViewRuntimeContext.activate(
      viewId: tab.id,
      activeLevelId: tab.levelId ?? 0,
      viewKind: runtimeKind,
    );
    AnnotationWorkspaceRuntime.activateView(
      workspaceViewId: tab.id,
      levelId: tab.levelId ?? 0,
      acceptsAnnotations: WorkspaceViewRuntimeContext.isModelViewport,
    );
  }
}
