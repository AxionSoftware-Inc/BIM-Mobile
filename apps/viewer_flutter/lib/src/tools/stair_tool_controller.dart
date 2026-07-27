import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Draft owned by the stair tool.  It has no engine or widget dependency.
///
/// A stair is authored as a single straight run: first tap is its base/start,
/// second tap defines run direction and length.  The engine derives the rise
/// from the selected base and top levels, so a moved level updates the stair.
class StairToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;
  double _widthMeters = 1.2;

  RenderScenePoint? get start => _start;
  RenderScenePoint? get end => _end;
  double get widthMeters => _widthMeters;
  bool get hasStart => _start != null;
  bool get hasRun =>
      _start != null && _end != null && _start!.distanceTo(_end!) >= 0.8;

  void begin(RenderScenePoint point) {
    _start = point;
    _end = point;
    notifyListeners();
  }

  void preview(RenderScenePoint point) {
    if (_start == null || _end == point) {
      return;
    }
    _end = point;
    notifyListeners();
  }

  void setWidth(double value) {
    if (!value.isFinite ||
        value < 0.6 ||
        value > 4.0 ||
        (value - _widthMeters).abs() < 1e-9) {
      return;
    }
    _widthMeters = value;
    notifyListeners();
  }

  void reset() {
    if (_start == null && _end == null) return;
    _start = null;
    _end = null;
    notifyListeners();
  }
}
