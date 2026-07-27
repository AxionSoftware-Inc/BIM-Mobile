import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';
import '../render_scene_viewport_types.dart';

/// Draft state for floor, ceiling and roof profile tools.
class SurfaceToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;
  final List<RenderScenePoint> _points = <RenderScenePoint>[];
  final Set<int> _wallIds = <int>{};
  RenderSceneSurfaceDrawMode _drawMode = RenderSceneSurfaceDrawMode.rectangle;
  double _thicknessMeters = 0.18;
  double _heightMeters = 3.0;
  double _floorTopMeters = 0.0;
  double _ceilingOffsetMeters = 2.6;

  RenderScenePoint? get start => _start;
  set start(RenderScenePoint? value) =>
      _setPoint(value, _start, (next) => _start = next);
  RenderScenePoint? get end => _end;
  set end(RenderScenePoint? value) =>
      _setPoint(value, _end, (next) => _end = next);

  /// Mutable only for the private [ViewerApp] tool adapter. All mutations still
  /// remain scoped to this controller instead of the app-level UI state.
  List<RenderScenePoint> get points => _points;
  Set<int> get wallIds => _wallIds;
  RenderSceneSurfaceDrawMode get drawMode => _drawMode;
  set drawMode(RenderSceneSurfaceDrawMode value) {
    if (_drawMode == value) return;
    _drawMode = value;
    notifyListeners();
  }

  double get thicknessMeters => _thicknessMeters;
  set thicknessMeters(double value) =>
      _setDouble(value, _thicknessMeters, (next) => _thicknessMeters = next);
  double get heightMeters => _heightMeters;
  set heightMeters(double value) =>
      _setDouble(value, _heightMeters, (next) => _heightMeters = next);
  double get floorTopMeters => _floorTopMeters;
  set floorTopMeters(double value) =>
      _setDouble(value, _floorTopMeters, (next) => _floorTopMeters = next);
  double get ceilingOffsetMeters => _ceilingOffsetMeters;
  set ceilingOffsetMeters(double value) => _setDouble(
      value, _ceilingOffsetMeters, (next) => _ceilingOffsetMeters = next);

  void replacePoints(Iterable<RenderScenePoint> value) {
    _points
      ..clear()
      ..addAll(value);
    notifyListeners();
  }

  void replaceWallIds(Iterable<int> value) {
    _wallIds
      ..clear()
      ..addAll(value);
    notifyListeners();
  }

  void reset({required double levelElevation, required double defaultHeight}) {
    _start = null;
    _end = null;
    _points.clear();
    _wallIds.clear();
    _drawMode = RenderSceneSurfaceDrawMode.rectangle;
    _thicknessMeters = 0.18;
    _heightMeters = defaultHeight;
    _floorTopMeters = levelElevation;
    _ceilingOffsetMeters = 2.6;
    notifyListeners();
  }

  void _setPoint(
    RenderScenePoint? value,
    RenderScenePoint? current,
    void Function(RenderScenePoint?) assign,
  ) {
    if (value == current) return;
    assign(value);
    notifyListeners();
  }

  void _setDouble(double value, double current, void Function(double) assign) {
    if (!value.isFinite || (value - current).abs() < 1e-9) return;
    assign(value);
    notifyListeners();
  }
}
