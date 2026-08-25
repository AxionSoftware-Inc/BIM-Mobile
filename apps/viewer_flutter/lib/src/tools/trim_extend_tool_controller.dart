import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';
import 'plan_sketch_geometry.dart';

@immutable
class TrimExtendWallSelection {
  const TrimExtendWallSelection({
    required this.wall,
    required this.axis,
    required this.endpoint,
  });

  final RenderSceneObject wall;
  final PlanSketchLine axis;
  final PlanSketchEndpoint endpoint;
}

/// State-only controller for one safe Trim/Extend operation.
///
/// The tool records which wall endpoint the user touched, previews the shared
/// sketch-kernel result and leaves the authoritative mutation to the engine.
class TrimExtendToolController extends ChangeNotifier {
  TrimExtendWallSelection? _first;
  TrimExtendWallSelection? _second;
  PlanSketchTrimResult? _preview;
  String? _message;

  TrimExtendWallSelection? get first => _first;
  TrimExtendWallSelection? get second => _second;
  PlanSketchTrimResult? get preview => _preview;
  String? get message => _message;
  bool get isReady => _first != null && _second != null && _preview != null;

  void selectWall({
    required RenderSceneObject wall,
    required PlanSketchLine axis,
    required RenderScenePoint touchPoint,
  }) {
    final id = wall.elementId;
    if (id == null || wall.kindKey != 'wall') {
      _message = 'Trim/Extend works only with walls that have a stable ID.';
      notifyListeners();
      return;
    }
    final selection = TrimExtendWallSelection(
      wall: wall,
      axis: axis,
      endpoint: axis.endpointNearestTo(touchPoint),
    );
    if (_first == null || _first!.wall.elementId == id) {
      _first = selection;
      _second = null;
      _preview = null;
      _message =
          'First wall selected. Tap the second wall near the endpoint to edit.';
      notifyListeners();
      return;
    }

    _second = selection;
    _preview = PlanSketchGeometry.trimExtend(
      first: _first!.axis,
      firstEndpoint: _first!.endpoint,
      second: selection.axis,
      secondEndpoint: selection.endpoint,
    );
    _message = _preview == null
        ? 'The wall endpoints could not be joined. The result would be parallel or zero length.'
        : 'Preview ready. Confirm updates both walls in one transaction.';
    notifyListeners();
  }

  void reset() {
    if (_first == null &&
        _second == null &&
        _preview == null &&
        _message == null) {
      return;
    }
    _first = null;
    _second = null;
    _preview = null;
    _message = null;
    notifyListeners();
  }
}
