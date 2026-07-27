import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// State-only controller for the chained wall tool.
///
/// It deliberately has no engine or widget dependency. Creating a wall stays
/// in [SceneMutationService], while this controller owns only the current
/// endpoint draft and the transition to the next segment.
class WallToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;

  RenderScenePoint? get start => _start;
  RenderScenePoint? get end => _end;
  bool get hasStart => _start != null;
  bool get hasSegment =>
      _start != null && _end != null && _start!.distanceTo(_end!) >= 0.1;

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

  /// Makes [point] the next chained-wall start after a successful commit.
  void continueFrom(RenderScenePoint point) {
    _start = point;
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
