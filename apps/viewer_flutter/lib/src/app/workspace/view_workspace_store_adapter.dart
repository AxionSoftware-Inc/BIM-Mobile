// COMPATIBILITY: legacy adapter while viewer_app still expects implicit
// active-view runtime synchronization.
// REMOVE WHEN: viewer composition wires active-view listeners explicitly.
import '../../features/viewer/application/workspace/view_workspace_store.dart'
    as canonical;
import 'active_view_runtime_synchronizer.dart';

export '../../features/viewer/application/workspace/view_tab_lifecycle_controller.dart';

class ViewWorkspaceStore extends canonical.ViewWorkspaceStore {
  ViewWorkspaceStore.standard({
    ActiveViewRuntimeSynchronizer runtimeSynchronizer =
        const ActiveViewRuntimeSynchronizer(),
  }) : super.standard(onActiveViewChanged: runtimeSynchronizer.sync);

  static const String threeDViewId = canonical.ViewWorkspaceStore.threeDViewId;

  static String floorPlanId(int levelId) =>
      canonical.ViewWorkspaceStore.floorPlanId(levelId);
}
