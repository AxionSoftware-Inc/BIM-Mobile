import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';
import 'view_tabs.dart';

/// Owns opened-view tabs, per-view display metadata, and sheet scene caches.
///
/// Geometry remains outside this store. It only keeps navigation/presentation
/// state so 3D, floor plan, elevation, section, and sheet hosts can share one
/// view identity without copying metadata into each feature.
final class ViewWorkspaceStore {
  ViewWorkspaceStore.standard()
      : _tabs = <OpenedViewTab>[],
        _activeTabId = null;

  final List<OpenedViewTab> _tabs;
  final Map<String, OpenedViewTab> _savedPresentations =
      <String, OpenedViewTab>{};
  final Map<String, RenderScene> _sheetScenes = <String, RenderScene>{};
  String? _activeTabId;
  RenderScene? _sheetSourceScene;

  /// Rebuilds the standard view set for a newly opened project.
  ///
  /// A view tab is only a navigation recipe; it must be created from the
  /// same scene that initializes the viewport. Keeping this reset here avoids
  /// the old split-brain state where the viewport started in Level 1 plan
  /// while the tab strip still advertised the placeholder 3D view.
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
    }
    return true;
  }

  void setActiveTab(String? id) {
    if (id == null || tabById(id) != null) {
      _activeTabId = id;
    }
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
}
