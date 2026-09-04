import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Which part of a wall the move tool owns.
enum WallMoveMode {
  translate,
  startHandle,
  endHandle,
}

/// Construction method for new walls.
///
/// Rectangle creates four walls, while Arc creates one semantic curved wall.
enum WallDrawMode {
  straight,
  rectangle,
  arc,
}

extension WallDrawModeLabel on WallDrawMode {
  String get label => switch (this) {
        WallDrawMode.straight => 'Straight',
        WallDrawMode.rectangle => 'Rectangle',
        WallDrawMode.arc => 'Arc',
      };

  String get description => switch (this) {
        WallDrawMode.straight =>
          'Chain straight wall segments from endpoint to endpoint.',
        WallDrawMode.rectangle =>
          'Create four straight walls from two opposite corners.',
        WallDrawMode.arc =>
          'Create one smooth wall: first point, second point, then bend/radius.',
      };
}

/// State-only controller for the chained wall tool.
///
/// It deliberately has no engine or widget dependency. Creating a wall stays
/// in the authoring gateway, while this controller owns only the gesture
/// stages and the transition to the next chained wall.
class WallToolController extends ChangeNotifier {
  RenderScenePoint? _start;
  RenderScenePoint? _end;
  RenderScenePoint? _arcStart;
  RenderScenePoint? _arcEnd;
  RenderScenePoint? _arcControl;
  RenderScenePoint? _chainEndpoint;
  int _wallTypeId = 0;
  WallDrawMode _drawMode = WallDrawMode.straight;

  RenderScenePoint? get start => _start;
  RenderScenePoint? get end => _end;
  RenderScenePoint? get arcStart => _arcStart;
  RenderScenePoint? get arcEnd => _arcEnd;
  RenderScenePoint? get arcControl => _arcControl;
  RenderScenePoint? get chainEndpoint => _chainEndpoint;
  bool get hasStart =>
      _drawMode == WallDrawMode.arc ? _arcStart != null : _start != null;
  bool get hasSegment => _drawMode == WallDrawMode.arc
      ? _arcStart != null &&
          _arcEnd != null &&
          _arcControl != null &&
          _arcStart!.distanceTo(_arcEnd!) >= 0.1 &&
          ((_arcEnd!.x - _arcStart!.x) * (_arcControl!.y - _arcStart!.y) -
                      (_arcEnd!.y - _arcStart!.y) *
                          (_arcControl!.x - _arcStart!.x))
                  .abs() >=
              1e-5
      : _start != null && _end != null && _start!.distanceTo(_end!) >= 0.1;

  bool get hasArcFirstPoint => _arcStart != null;
  bool get hasArcSecondPoint => _arcEnd != null;
  bool get hasArcControlPoint => _arcControl != null;

  int get wallTypeId => _wallTypeId;
  set wallTypeId(int value) {
    if (_wallTypeId == value) return;
    _wallTypeId = value;
    notifyListeners();
  }

  WallDrawMode get drawMode => _drawMode;
  set drawMode(WallDrawMode value) {
    switchDrawMode(value);
  }

  /// Switches construction method without breaking a committed wall chain.
  /// When an existing endpoint is available it becomes Arc's first point, so
  /// the next two gestures are the second point and the bend point.
  void switchDrawMode(WallDrawMode value) {
    if (_drawMode == value) return;

    final anchor = _chainEndpoint;
    _drawMode = value;
    _start = null;
    _end = null;
    _arcStart = null;
    _arcEnd = null;
    _arcControl = null;

    if (anchor != null) {
      if (value == WallDrawMode.arc) {
        _arcStart = anchor;
      } else if (value == WallDrawMode.straight) {
        _start = anchor;
        _end = anchor;
      }
    }
    notifyListeners();
  }

  void begin(RenderScenePoint point) {
    if (_drawMode == WallDrawMode.arc) {
      beginArcFirst(point);
      return;
    }
    _start = point;
    _end = point;
    notifyListeners();
  }

  void preview(RenderScenePoint point) {
    if (_drawMode == WallDrawMode.arc) {
      if (_arcStart == null) {
        beginArcFirst(point);
      } else if (_arcEnd == null) {
        setArcSecond(point);
      } else {
        previewArcControl(point);
      }
      return;
    }
    if (_start == null || _end == point) return;
    _end = point;
    notifyListeners();
  }

  /// Makes [point] the next chained-wall start after a successful commit.
  void continueFrom(RenderScenePoint point) {
    _chainEndpoint = point;
    _start = _drawMode == WallDrawMode.straight ? point : null;
    _end = _drawMode == WallDrawMode.straight ? point : null;
    _arcStart = _drawMode == WallDrawMode.arc ? point : null;
    _arcEnd = null;
    _arcControl = null;
    notifyListeners();
  }

  void beginArcFirst(RenderScenePoint point) {
    _arcStart = point;
    _arcEnd = null;
    _arcControl = null;
    notifyListeners();
  }

  void setArcSecond(RenderScenePoint point) {
    if (_arcStart == null || _arcStart == point) return;
    _arcEnd = point;
    _arcControl = null;
    notifyListeners();
  }

  void previewArcControl(RenderScenePoint point) {
    if (_arcStart == null || _arcEnd == null || _arcControl == point) return;
    _arcControl = point;
    notifyListeners();
  }

  /// Clears only the current geometry draft while preserving the selected
  /// wall type and draw mode for the next gesture. A chained endpoint is
  /// cleared by default; arc commit uses [preserveChainEndpoint] until its
  /// final endpoint has been accepted.
  void clearDraft({bool preserveChainEndpoint = false}) {
    if (_start == null &&
        _end == null &&
        _arcStart == null &&
        _arcEnd == null &&
        _arcControl == null &&
        (!preserveChainEndpoint && _chainEndpoint == null)) {
      return;
    }
    _start = null;
    _end = null;
    _arcStart = null;
    _arcEnd = null;
    _arcControl = null;
    if (!preserveChainEndpoint) {
      _chainEndpoint = null;
    }
    notifyListeners();
  }

  void reset() {
    if (_start == null &&
        _end == null &&
        _arcStart == null &&
        _arcEnd == null &&
        _arcControl == null &&
        _chainEndpoint == null &&
        _wallTypeId == 0 &&
        _drawMode == WallDrawMode.straight) {
      return;
    }
    _start = null;
    _end = null;
    _arcStart = null;
    _arcEnd = null;
    _arcControl = null;
    _chainEndpoint = null;
    _wallTypeId = 0;
    _drawMode = WallDrawMode.straight;
    notifyListeners();
  }
}
