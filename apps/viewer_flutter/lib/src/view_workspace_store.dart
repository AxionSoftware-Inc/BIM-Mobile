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
      : _tabs = <OpenedViewTab>[
          OpenedViewTab(
            id: 'view-3d-default',
            label: '3D View',
            kind: OpenedViewKind.threeD,
            projectionMode: RenderSceneProjectionMode.isometric,
          ),
        ],
        _activeTabId = 'view-3d-default';

  final List<OpenedViewTab> _tabs;
  final Map<String, OpenedViewTab> _savedPresentations =
      <String, OpenedViewTab>{};
  final Map<String, RenderScene> _sheetScenes = <String, RenderScene>{};
  String? _activeTabId;
  RenderScene? _sheetSourceScene;

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
