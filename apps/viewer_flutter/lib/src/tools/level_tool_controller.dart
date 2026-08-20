import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Draft state for creating a level line in an elevation viewport.
class LevelToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;

  RenderScenePoint? get start => _start;
  RenderScenePoint? get end => _end;
  bool get hasDraft => _start != null && _end != null;

  void begin(RenderScenePoint point) {
    _start = point;
    _end = point;
    notifyListeners();
  }

  void preview(RenderScenePoint point) {
    if (_start == null || _end == point) return;
    _end = point;
    notifyListeners();
  }

  void reset() {
    if (_start == null && _end == null) return;
    _start = null;
    _end = null;
    notifyListeners();
  }
}
