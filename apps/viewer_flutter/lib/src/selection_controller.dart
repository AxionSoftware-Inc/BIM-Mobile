import 'package:flutter/foundation.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';

/// The one selection authority used by every view and by the Inspector.
///
/// Rendering backends only mirror this state.  No Inspector widget keeps its
/// own selected object, which prevents 2D/3D/elevation selection drift.
class SelectionController extends ChangeNotifier {
  SelectionController(this._viewport) {
    _viewport.addListener(_onViewportChanged);
  }

  final RenderSceneViewportActions _viewport;
  Set<String> _elementIds = <String>{};
  String? _activeElementId;
  int? _levelId;

  Set<String> get elementIds => Set<String>.unmodifiable(_elementIds);
  String? get activeElementId => _activeElementId;
  int? get levelId => _levelId;
  bool get hasMultiple => _elementIds.length > 1;
  bool get isEmpty => _elementIds.isEmpty && _levelId == null;

  RenderSceneObject? activeObject(RenderScene? scene) {
    final id = int.tryParse(_activeElementId ?? '');
    return scene?.objectById(id);
  }

  List<RenderSceneObject> selectedObjects(RenderScene? scene) {
    if (scene == null) return const <RenderSceneObject>[];
    return <RenderSceneObject>[
      for (final id in _elementIds)
        if (int.tryParse(id) case final parsed?)
          if (scene.objectById(parsed) case final object?) object,
    ];
  }

  Future<void> selectObject(RenderSceneObject object,
      {bool preserve = false}) async {
    final id = object.elementId?.toString();
    if (id == null) return;
    final ids = preserve ? <String>{..._elementIds, id} : <String>{id};
    await _viewport.selectElements(ids, activeElementId: id);
    await _viewport.highlightElement(id);
  }

  Future<void> selectLevel(int levelId) => _viewport.selectLevel(levelId);

  Future<void> clear() async {
    await _viewport.selectLevel(null);
    await _viewport.highlightElement(null);
  }

  void _onViewportChanged() {
    final nextIds = _viewport.selectedElementIds;
    final nextActive = _viewport.activeElementId;
    final nextLevel = _viewport.selectedLevelId;
    if (setEquals(_elementIds, nextIds) &&
        _activeElementId == nextActive &&
        _levelId == nextLevel) {
      return;
    }
    _elementIds = Set<String>.from(nextIds);
    _activeElementId = nextActive;
    _levelId = nextLevel;
    notifyListeners();
  }

  @override
  void dispose() {
    _viewport.removeListener(_onViewportChanged);
    super.dispose();
  }
}
