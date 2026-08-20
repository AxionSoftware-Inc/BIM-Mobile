import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';
import '../render_scene_viewport_types.dart';

/// Draft state for floor, ceiling and roof profile tools.
class SurfaceToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;
  final List<RenderScenePoint> _points = <RenderScenePoint>[];
  final Set<int> _wallIds = <int>{};
  bool _boundaryClosed = false;
  // Picking the enclosing walls is the safest default on a touch screen: it
  // avoids an accidental rectangle when the user intended to follow the
  // building footprint.
  RenderSceneSurfaceDrawMode _drawMode = RenderSceneSurfaceDrawMode.pickWalls;
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
  bool get boundaryClosed => _boundaryClosed;
  bool get canUndo => switch (_drawMode) {
        RenderSceneSurfaceDrawMode.polyline => _points.isNotEmpty,
        RenderSceneSurfaceDrawMode.pickWalls => _wallIds.isNotEmpty,
        RenderSceneSurfaceDrawMode.rectangle =>
          _start != null || _end != null || _points.isNotEmpty,
        RenderSceneSurfaceDrawMode.autoRoom => false,
      };
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

  void closeBoundary() {
    if (_boundaryClosed) return;
    _boundaryClosed = true;
    notifyListeners();
  }

  void reopenBoundary() {
    if (!_boundaryClosed) return;
    _boundaryClosed = false;
    notifyListeners();
  }

  void replaceWallIds(Iterable<int> value) {
    _wallIds
      ..clear()
      ..addAll(value);
    notifyListeners();
  }

  /// Removes the most recent touch decision without cancelling the tool.
  /// Dart's insertion-ordered Set makes wall picking reversible in the same
  /// order the user selected boundaries.
  bool undoLast() {
    switch (_drawMode) {
      case RenderSceneSurfaceDrawMode.polyline:
        if (_boundaryClosed) {
          _boundaryClosed = false;
          notifyListeners();
          return true;
        }
        if (_points.isEmpty) return false;
        _points.removeLast();
        _start = _points.firstOrNull;
        _end = _points.lastOrNull;
        break;
      case RenderSceneSurfaceDrawMode.pickWalls:
        if (_wallIds.isEmpty) return false;
        _wallIds.remove(_wallIds.last);
        _points.clear();
        _start = null;
        _end = null;
        break;
      case RenderSceneSurfaceDrawMode.rectangle:
        if (_start == null && _end == null && _points.isEmpty) return false;
        _start = null;
        _end = null;
        _points.clear();
        _boundaryClosed = false;
        break;
      case RenderSceneSurfaceDrawMode.autoRoom:
        return false;
    }
    notifyListeners();
    return true;
  }

  void reset({required double levelElevation, required double defaultHeight}) {
    _start = null;
    _end = null;
    _points.clear();
    _wallIds.clear();
    _boundaryClosed = false;
    _drawMode = RenderSceneSurfaceDrawMode.pickWalls;
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
