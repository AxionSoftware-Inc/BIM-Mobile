import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Draft state shared by door, window and hosted-opening move tools.
class OpeningToolController extends ChangeNotifier {
  RenderSceneObject? _hostWall;
  double _offsetMeters = 1.0;
  double _widthMeters = 0.9;
  double _heightMeters = 2.1;
  double _sillHeightMeters = 0.9;

  RenderSceneObject? get hostWall => _hostWall;
  double get offsetMeters => _offsetMeters;
  double get widthMeters => _widthMeters;
  double get heightMeters => _heightMeters;
  double get sillHeightMeters => _sillHeightMeters;

  void setHostWall(RenderSceneObject? wall) {
    if (identical(_hostWall, wall)) return;
    _hostWall = wall;
    notifyListeners();
  }

  void setOffset(double value) =>
      _set(value, _offsetMeters, (next) => _offsetMeters = next);
  void setWidth(double value) =>
      _set(value, _widthMeters, (next) => _widthMeters = next);
  void setHeight(double value) =>
      _set(value, _heightMeters, (next) => _heightMeters = next);
  void setSillHeight(double value) =>
      _set(value, _sillHeightMeters, (next) => _sillHeightMeters = next);

  void loadFromMetadata(Map<String, Object?> metadata) {
    _offsetMeters = _number(metadata['offset_meters']) ?? _offsetMeters;
    _widthMeters = _number(metadata['width_meters']) ?? _widthMeters;
    _heightMeters = _number(metadata['height_meters']) ?? _heightMeters;
    _sillHeightMeters =
        _number(metadata['sill_height_meters']) ?? _sillHeightMeters;
    notifyListeners();
  }

  void reset() {
    _hostWall = null;
    _offsetMeters = 1.0;
    _widthMeters = 0.9;
    _heightMeters = 2.1;
    _sillHeightMeters = 0.9;
    notifyListeners();
  }

  void _set(double value, double current, void Function(double) assign) {
    if (!value.isFinite || (value - current).abs() < 1e-9) return;
    assign(value);
    notifyListeners();
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
