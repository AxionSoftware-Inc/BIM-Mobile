import '../../../../render_scene_models.dart';
import '../../domain/view/view_configuration.dart';
import 'opened_view_tab.dart';

typedef ActiveWorkspaceViewChanged = void Function(OpenedViewTab? tab);

/// Owns opened-view tabs, per-view display metadata, and sheet scene caches.
///
/// Geometry remains outside this store. Active-view synchronization is emitted
/// exactly when state changes, so presentation widgets never mutate runtime
/// state while building.
class ViewWorkspaceStore {
  ViewWorkspaceStore.standard({
    ActiveWorkspaceViewChanged? onActiveViewChanged,
  })  : _onActiveViewChanged = onActiveViewChanged,
        _tabs = <OpenedViewTab>[],
        _activeTabId = null;

  final ActiveWorkspaceViewChanged? _onActiveViewChanged;
  final List<OpenedViewTab> _tabs;
  final Map<String, OpenedViewTab> _savedPresentations =
      <String, OpenedViewTab>{};
  final Map<String, RenderScene> _sheetScenes = <String, RenderScene>{};
  String? _activeTabId;
  RenderScene? _sheetSourceScene;

  void resetForScene(RenderScene scene) {
    final firstLevel = scene.levels.isEmpty ? null : scene.levels.first;
    final planId = firstLevel == null ? null : floorPlanId(firstLevel.levelId);
    _tabs
      ..clear()
      ..addAll(<OpenedViewTab>[
        if (firstLevel != null)
          OpenedViewTab(
            id: planId!,
            label: '${firstLevel.name} plan',
            kind: OpenedViewKind.floorPlan,
            projectionMode: RenderSceneProjectionMode.topDown,
            levelId: firstLevel.levelId,
          ),
        OpenedViewTab(
          id: threeDViewId,
          label: '3D View',
          kind: OpenedViewKind.threeD,
          projectionMode: RenderSceneProjectionMode.isometric,
        ),
      ]);
    _savedPresentations.clear();
    _sheetSourceScene = null;
    _sheetScenes.clear();
    _activeTabId = planId ?? threeDViewId;
    _notifyActiveViewChanged();
  }

  static const String threeDViewId = 'view-3d-default';
  static String floorPlanId(int levelId) => 'floor-plan-$levelId';

  List<OpenedViewTab> get tabs => List<OpenedViewTab>.unmodifiable(_tabs);
  String? get activeTabId => _activeTabId;
  Map<String, OpenedViewTab> get savedPresentations =>
      Map<String, OpenedViewTab>.unmodifiable(_savedPresentations);
  Map<String, RenderScene> get sheetScenes =>
      Map<String, RenderScene>.unmodifiable(_sheetScenes);
  RenderScene? get sheetSourceScene => _sheetSourceScene;

  OpenedViewTab? tabById(String id) {
    for (final tab in _tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  OpenedViewTab? get activeTab {
    final id = _activeTabId;
    return id == null ? null : tabById(id);
  }

  OpenedViewTab withSavedPresentation(OpenedViewTab tab) {
    final saved = _savedPresentations[tab.id];
    if (saved == null) return tab;
    return tab.copyWith(
      displayStyle: saved.displayStyle,
      shadowsEnabled: saved.shadowsEnabled,
      orbitProjectionStyle: saved.orbitProjectionStyle,
    );
  }

  bool addTab(OpenedViewTab tab) {
    if (tabById(tab.id) != null) return false;
    _tabs.add(tab);
    return true;
  }

  bool replaceTab(OpenedViewTab tab) {
    final index = _tabs.indexWhere((item) => item.id == tab.id);
    if (index < 0) return false;
    _tabs[index] = tab;
    return true;
  }

  bool removeTab(String id) {
    final index = _tabs.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    _tabs.removeAt(index);
    _savedPresentations.remove(id);
    if (_activeTabId == id) {
      _activeTabId = _tabs.isEmpty ? null : _tabs.first.id;
      _notifyActiveViewChanged();
    }
    return true;
  }

  void setActiveTab(String? id) {
    if (id != null && tabById(id) == null) return;
    if (_activeTabId == id) return;
    _activeTabId = id;
    _notifyActiveViewChanged();
  }

  bool savePresentation(
    String viewId, {
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    final current = tabById(viewId);
    if (current == null) return false;
    final updated = current.copyWith(
      displayStyle: displayStyle,
      shadowsEnabled: shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle,
    );
    _savedPresentations[viewId] = updated;
    return replaceTab(updated);
  }

  void cacheSheetSource(RenderScene? scene) {
    _sheetSourceScene = scene;
  }

  void cacheSheetScene(String viewId, RenderScene scene) {
    _sheetScenes[viewId] = scene;
  }

  void clearSheetCache() {
    _sheetSourceScene = null;
    _sheetScenes.clear();
  }

  void _notifyActiveViewChanged() {
    _onActiveViewChanged?.call(activeTab);
  }
}
