import '../../features/annotations/application/annotation_workspace_runtime.dart';
import '../../features/viewer/application/workspace/opened_view_tab.dart';

/// Composition-owned bridge for the remaining annotation runtime.
///
/// Viewer application state emits semantic [OpenedViewTab] changes. Until the
/// annotation runtime becomes instance-owned, this adapter is the only place
/// that mirrors those changes into its static runtime.
final class ActiveViewRuntimeSynchronizer {
  const ActiveViewRuntimeSynchronizer();

  void sync(OpenedViewTab? tab) {
    if (tab == null) {
      AnnotationWorkspaceRuntime.activateView(
        workspaceViewId: '',
        levelId: 0,
        acceptsAnnotations: false,
      );
      return;
    }

    final activeLevelId = tab.levelId ?? 0;
    AnnotationWorkspaceRuntime.activateView(
      workspaceViewId: tab.id,
      levelId: activeLevelId,
      acceptsAnnotations: switch (tab.kind) {
        OpenedViewKind.threeD ||
        OpenedViewKind.floorPlan ||
        OpenedViewKind.elevation ||
        OpenedViewKind.section =>
          true,
        OpenedViewKind.sheet || OpenedViewKind.schedule => false,
      },
    );
  }
}
