import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Which part of a wall the move tool owns.
enum WallMoveMode {
  translate,
  startHandle,
  endHandle,
  arcControl,
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
          'Create one smooth wall: first point, second point, then adjust the midpoint handle.',
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
  bool _arcFirstPointAdjustmentActive = false;
  bool _arcSecondPointAdjustmentActive = false;
  bool _arcControlAdjustmentActive = false;
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
  bool get isArcFirstPointAdjustmentActive => _arcFirstPointAdjustmentActive;
  bool get isArcSecondPointAdjustmentActive => _arcSecondPointAdjustmentActive;
  bool get isArcControlAdjustmentActive => _arcControlAdjustmentActive;

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
  /// the next gestures are the second point and the midpoint-handle radius.
  void switchDrawMode(WallDrawMode value) {
    if (_drawMode == value) return;

    final anchor = _chainEndpoint;
    _drawMode = value;
    _start = null;
    _end = null;
    _arcStart = null;
    _arcEnd = null;
    _arcControl = null;
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = false;

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
        beginArcControlAdjustment(point);
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
    _arcControlAdjustmentActive = false;
    notifyListeners();
  }

  void beginArcFirst(RenderScenePoint point) {
    _arcStart = point;
    _arcEnd = null;
    _arcControl = null;
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = false;
    notifyListeners();
  }

  /// Starts a first-point drag. The point remains provisional until the
  /// gesture ends, so a touch can be held and moved without leaking the
  /// initial contact into the next arc stage.
  void beginArcFirstAdjustment(RenderScenePoint point) {
    beginArcFirst(point);
    _arcFirstPointAdjustmentActive = true;
  }

  void previewArcFirst(RenderScenePoint point) {
    if (!_arcFirstPointAdjustmentActive || _arcStart == point) return;
    _arcStart = point;
    notifyListeners();
  }

  void commitArcFirst() {
    if (!_arcFirstPointAdjustmentActive) return;
    _arcFirstPointAdjustmentActive = false;
    notifyListeners();
  }

  void setArcSecond(RenderScenePoint point) {
    if (_arcStart == null || _arcStart == point) return;
    _arcEnd = point;
    _arcControl = _defaultArcControl(_arcStart!, point);
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = false;
    notifyListeners();
  }

  /// Starts the second endpoint drag without committing its initial contact.
  /// The endpoint and standard-radius midpoint are visible immediately, but
  /// [previewArcSecond] keeps moving them until [commitArcSecond] on release.
  void beginArcSecondAdjustment(RenderScenePoint point) {
    if (_arcStart == null || _arcStart == point) return;
    _arcEnd = point;
    _arcControl = _defaultArcControl(_arcStart!, point);
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = true;
    _arcControlAdjustmentActive = false;
    notifyListeners();
  }

  void previewArcSecond(RenderScenePoint point) {
    if (!_arcSecondPointAdjustmentActive || _arcStart == null) return;
    if (_arcEnd == point) return;
    _arcEnd = point;
    _arcControl = _defaultArcControl(_arcStart!, point);
    notifyListeners();
  }

  void commitArcSecond() {
    if (!_arcSecondPointAdjustmentActive) return;
    _arcSecondPointAdjustmentActive = false;
    notifyListeners();
  }

  /// Arms the third point of the three-point arc. The control point is
  /// already present after [setArcSecond], so the user can see a valid,
  /// standard-radius arc before touching the handle. A subsequent drag/tap
  /// only changes this point and does not alter either endpoint.
  void beginArcControlAdjustment(RenderScenePoint point) {
    if (_arcStart == null || _arcEnd == null) return;
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = true;
    _arcControl = point;
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
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = false;
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
    _arcFirstPointAdjustmentActive = false;
    _arcSecondPointAdjustmentActive = false;
    _arcControlAdjustmentActive = false;
    _chainEndpoint = null;
    _wallTypeId = 0;
    _drawMode = WallDrawMode.straight;
    notifyListeners();
  }

  static RenderScenePoint _defaultArcControl(
    RenderScenePoint first,
    RenderScenePoint second,
  ) {
    final dx = second.x - first.x;
    final dy = second.y - first.y;
    final chord = math.sqrt(dx * dx + dy * dy);
    if (chord <= 1e-9) return second;

    // A 90-degree arc is a predictable architectural starting point. For
    // short chords, keep the radius above the kernel's 0.25 m minimum so the
    // automatically created preview is valid as soon as the second point is
    // placed.
    final radius = math.max(chord / math.sqrt2, 0.25);
    final halfChord = chord * 0.5;
    final sagitta = radius -
        math.sqrt(math.max(radius * radius - halfChord * halfChord, 0.0));
    final midpointX = (first.x + second.x) * 0.5;
    final midpointY = (first.y + second.y) * 0.5;
    return RenderScenePoint(
      x: midpointX - dy / chord * sagitta,
      y: midpointY + dx / chord * sagitta,
      z: first.z,
    );
  }
}
