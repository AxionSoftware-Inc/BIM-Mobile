import '../../features/annotations/application/annotation_workspace_runtime.dart';
import '../../features/viewer/application/workspace/opened_view_tab.dart';
import 'workspace_view_runtime_context.dart';

/// Composition-owned bridge for the remaining process-wide active-view
/// runtimes.
///
/// Viewer application state emits semantic [OpenedViewTab] changes. Until the
/// legacy workspace/annotation runtimes become instance-owned, this adapter is
/// the only place that mirrors those changes into their static compatibility
/// contexts.
final class ActiveViewRuntimeSynchronizer {
  const ActiveViewRuntimeSynchronizer();

  void sync(OpenedViewTab? tab) {
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
    final activeLevelId = tab.levelId ?? 0;
    WorkspaceViewRuntimeContext.activate(
      viewId: tab.id,
      activeLevelId: activeLevelId,
      viewKind: runtimeKind,
    );
    AnnotationWorkspaceRuntime.activateView(
      workspaceViewId: tab.id,
      levelId: activeLevelId,
      acceptsAnnotations: WorkspaceViewRuntimeContext.isModelViewport,
    );
  }
}
