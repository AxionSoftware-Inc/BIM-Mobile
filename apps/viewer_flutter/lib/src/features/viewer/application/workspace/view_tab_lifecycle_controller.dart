import 'opened_view_tab.dart';
import 'view_workspace_store.dart';

typedef WorkspaceViewActivator = Future<void> Function(OpenedViewTab tab);

/// Application-level lifecycle for opened workspace views.
///
/// The store owns tab state; this controller owns the transactional sequence
/// around asynchronous activation. A failed renderer/engine transition rolls
/// the active tab back instead of leaving workspace state ahead of the viewport.
final class ViewTabLifecycleController {
  const ViewTabLifecycleController(this.store);

  final ViewWorkspaceStore store;

  Future<OpenedViewTab?> open(
    OpenedViewTab requested, {
    required WorkspaceViewActivator activate,
  }) async {
    final previous = store.activeTab;
    final existing = store.tabById(requested.id);
    final target = existing ?? store.withSavedPresentation(requested);
    final added = existing == null && store.addTab(target);
    store.setActiveTab(target.id);

    try {
      await activate(target);
      return target;
    } catch (_) {
      if (added) store.removeTab(target.id);
      await _restore(previous, activate);
      rethrow;
    }
  }

  Future<OpenedViewTab?> select(
    String tabId, {
    required WorkspaceViewActivator activate,
  }) async {
    final target = store.tabById(tabId);
    if (target == null || store.activeTabId == tabId) return target;

    final previous = store.activeTab;
    store.setActiveTab(tabId);
    try {
      await activate(target);
      return target;
    } catch (_) {
      await _restore(previous, activate);
      rethrow;
    }
  }

  /// Closes [tabId] and returns the tab that became active.
  ///
  /// Returns `null` without mutation when closing would remove the final tab;
  /// presentation decides whether that means leaving the project workspace.
  Future<ViewTabCloseResult?> close(
    String tabId, {
    required WorkspaceViewActivator activate,
  }) async {
    final tabs = store.tabs;
    final index = tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return const ViewTabCloseResult.notFound();
    if (tabs.length <= 1) return null;

    final closing = tabs[index];
    final wasActive = store.activeTabId == tabId;
    final nextIndex = index < tabs.length - 1 ? index + 1 : index - 1;
    final next = tabs[nextIndex];

    store.removeTab(tabId);
    if (!wasActive) {
      return ViewTabCloseResult(
        closing: closing,
        active: store.activeTab,
        activated: false,
      );
    }

    store.setActiveTab(next.id);
    try {
      await activate(next);
      return ViewTabCloseResult(
        closing: closing,
        active: next,
        activated: true,
      );
    } catch (_) {
      // Closing already committed. Keep state coherent by retaining the chosen
      // neighbour as active; the caller owns the visible activation error.
      rethrow;
    }
  }

  Future<void> _restore(
    OpenedViewTab? previous,
    WorkspaceViewActivator activate,
  ) async {
    if (previous == null || store.tabById(previous.id) == null) {
      store.setActiveTab(null);
      return;
    }
    store.setActiveTab(previous.id);
    try {
      await activate(previous);
    } catch (_) {
      // Preserve the original transition error. State still points to the
      // previous semantic view so a later refresh can recover the renderer.
    }
  }
}

final class ViewTabCloseResult {
  const ViewTabCloseResult({
    required this.closing,
    required this.active,
    required this.activated,
  }) : found = true;

  const ViewTabCloseResult.notFound()
      : closing = null,
        active = null,
        activated = false,
        found = false;

  final OpenedViewTab? closing;
  final OpenedViewTab? active;
  final bool activated;
  final bool found;
}
