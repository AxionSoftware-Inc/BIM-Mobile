import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// Draft owned by the stair tool.  It has no engine or widget dependency.
///
/// A stair is authored as one path: two points for a straight run, three for
/// an L, and four for a U. The engine derives the rise from the selected base
/// and top levels, so a moved level updates the whole semantic stair.
class StairToolController extends ChangeNotifier {
  final List<RenderScenePoint> _points = <RenderScenePoint>[];
  RenderScenePoint? _previewEnd;
  double _widthMeters = 1.2;
  double _landingDepthMeters = 1.0;
  int _layoutKind = 0;
  bool _railingEnabled = false;
  int? _baseLevelId;
  int? _topLevelId;

  RenderScenePoint? get start => _points.isEmpty ? null : _points.first;
  RenderScenePoint? get end => _points.length < 2 ? _previewEnd : _points.last;
  RenderScenePoint? get previewEnd => _previewEnd;
  List<RenderScenePoint> get pathPoints =>
      List<RenderScenePoint>.unmodifiable(_points);
  double get widthMeters => _widthMeters;
  double get landingDepthMeters => _landingDepthMeters;
  int get layoutKind => _layoutKind;
  bool get railingEnabled => _railingEnabled;
  int? get baseLevelId => _baseLevelId;
  int? get topLevelId => _topLevelId;
  bool get hasStart => _points.isNotEmpty;
  bool get hasRun =>
      start != null && end != null && start!.distanceTo(end!) >= 0.8;
  int get requiredPointCount => _layoutKind == 0
      ? 2
      : _layoutKind == 1
          ? 3
          : 4;
  bool get hasCompleteLayout => _points.length >= requiredPointCount;

  void begin(RenderScenePoint point) {
    _points
      ..clear()
      ..add(point);
    _previewEnd = point;
    notifyListeners();
  }

  void preview(RenderScenePoint point) {
    if (!hasStart || _previewEnd == point) {
      return;
    }
    _previewEnd = point;
    notifyListeners();
  }

  void addPoint(RenderScenePoint point) {
    if (!hasStart) {
      begin(point);
      return;
    }
    if (_points.last.distanceTo(point) < 0.08) return;
    _points.add(point);
    _previewEnd = point;
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

  void setLandingDepth(double value) {
    if (!value.isFinite ||
        value < 0.6 ||
        value > 4.0 ||
        (value - _landingDepthMeters).abs() < 1e-9) {
      return;
    }
    _landingDepthMeters = value;
    notifyListeners();
  }

  void setLayoutKind(int value) {
    if (value < 0 || value > 2 || value == _layoutKind) return;
    _layoutKind = value;
    if (_points.length > 1) {
      final first = _points.first;
      _points
        ..clear()
        ..add(first);
      _previewEnd = first;
    }
    notifyListeners();
  }

  void setRailingEnabled(bool value) {
    if (_railingEnabled == value) return;
    _railingEnabled = value;
    notifyListeners();
  }

  void setBaseLevelId(int? value) {
    if (_baseLevelId == value) return;
    _baseLevelId = value;
    notifyListeners();
  }

  void setTopLevelId(int? value) {
    if (_topLevelId == value) return;
    _topLevelId = value;
    notifyListeners();
  }

  void reset() {
    if (_points.isEmpty && _previewEnd == null) return;
    _points.clear();
    _previewEnd = null;
    notifyListeners();
  }
}
