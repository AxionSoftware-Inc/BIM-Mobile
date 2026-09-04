part of 'viewer_app.dart';

/// Stair authoring coordinator.
///
/// The viewport only collects path points.  This coordinator resolves level
/// constraints and sends one semantic stair transaction to the engine, so a
/// straight, L-shaped, or U-shaped stair never becomes a set of unrelated
/// wall-like fragments.
extension _ViewerViewportStairEditing on _ViewerHomePageState {
  Future<void> _handleAddStairTap(RenderScenePoint? modelPoint) async {
    final scene = _scene;
    if (scene == null || modelPoint == null) {
      _updateViewportState(() =>
          _editStatusMessage = 'Place the stair path points on the 2D plan.');
      return;
    }
    final active = _activeLevel(scene);
    final top = active == null ? null : _nextHigherLevel(scene, active.levelId);
    if (active == null || top == null) {
      _updateViewportState(() => _editStatusMessage =
          'A stair needs a Base Level and a higher Top Level.');
      return;
    }
    final referencePoint = _stairTool.pathPoints.lastOrNull ?? _stairTool.start;
    final point =
        _draftLinePoint(rawPoint: modelPoint, referenceStart: referencePoint);
    if (!_stairTool.hasStart) {
      _stairTool.begin(point);
      _viewportController.setWallDraft(point, point);
      _updateViewportState(() => _editStatusMessage =
          'Stair start set. Next tap defines the first flight.');
      return;
    }
    _stairTool.addPoint(point);
    _viewportController.setWallDraft(
      _stairTool.layoutKind == 0 ? _stairTool.start : referencePoint,
      _stairTool.end,
    );
    if (_stairTool.hasCompleteLayout) {
      await _commitStairDraft();
    } else {
      final remaining =
          _stairTool.requiredPointCount - _stairTool.pathPoints.length;
      _updateViewportState(() => _editStatusMessage =
          'Tap $remaining more point${remaining == 1 ? '' : 's'} to finish the ${_stairTool.layoutKind == 1 ? 'L' : 'U'} stair.');
    }
  }

  Future<void> _commitStairDraft() async {
    final scene = _scene;
    final start = _stairTool.start;
    final end = _stairTool.end;
    final pathPoints = _stairTool.pathPoints;
    final repository = _engineRepository;
    final activeBase = scene == null ? null : _activeLevel(scene);
    final base = scene == null
        ? null
        : scene.levelById(_stairTool.baseLevelId ?? activeBase?.levelId) ??
            activeBase;
    final activeTop = base == null || scene == null
        ? null
        : _nextHigherLevel(scene, base.levelId);
    final top = scene == null
        ? null
        : scene.levelById(_stairTool.topLevelId ?? activeTop?.levelId) ??
            activeTop;
    if (scene == null ||
        start == null ||
        end == null ||
        base == null ||
        top == null) {
      return;
    }
    if (!_engineBackedMode || repository == null) {
      _updateViewportState(() => _editStatusMessage =
          'Stair productionda engine-backed mode talab qiladi.');
      return;
    }
    if (_stairTool.layoutKind != 0) {
      var totalRun = 0.0;
      for (var index = 1; index < pathPoints.length; index += 1) {
        totalRun += pathPoints[index].distanceTo(pathPoints[index - 1]);
      }
      if (pathPoints.length < _stairTool.requiredPointCount || totalRun < 0.8) {
        _updateViewportState(() => _editStatusMessage =
            'Stair path must contain complete flights and be at least 0.8 m long.');
        return;
      }
      final result = await _authoringCommands.createStairLayout(
        baseLevelId: base.levelId,
        topLevelId: top.levelId,
        pathPoints: pathPoints,
        widthMeters: _stairTool.widthMeters,
        totalRiseMeters: top.elevationMeters - base.elevationMeters,
        riserCount: math
            .max(1, (top.elevationMeters - base.elevationMeters) / 0.18)
            .round(),
        treadCount: math.max(2, (totalRun / 0.28).round()),
        landingDepthMeters: _stairTool.landingDepthMeters,
        layoutKind: _stairTool.layoutKind,
        railingEnabled: _stairTool.railingEnabled,
      );
      await _applyEngineSceneResult(result,
          message: 'Stair created: ${base.name} → ${top.name}.');
      final id = _authoringCommands.lastCreatedElementId;
      await _clearDraft();
      if (id != null) {
        await _viewportController.selectElement(id.toString());
      }
      return;
    }
    final preview = StairAuthoringGeometry.preview(
      start: start,
      end: end,
      baseLevel: base,
      topLevel: top,
    );
    if (preview == null) {
      final run = start.distanceTo(end);
      _updateViewportState(() => _editStatusMessage = run < 0.8
          ? 'A stair run must be at least ${_projectUnitSettings.formatLength(0.8)}.'
          : 'Top Level must be above Base Level.');
      return;
    }
    final result = await _authoringCommands.createStair(
      baseLevelId: base.levelId,
      topLevelId: top.levelId,
      start: preview.start,
      direction: preview.direction,
      widthMeters: _stairTool.widthMeters,
      totalRiseMeters: preview.riseMeters,
      totalRunMeters: preview.runMeters,
      riserCount: preview.riserCount,
      treadCount: preview.treadCount,
    );
    await _applyEngineSceneResult(result,
        message: 'Stair created: ${base.name} → ${top.name}.');
    final id = _authoringCommands.lastCreatedElementId;
    await _clearDraft();
    if (id != null) {
      await _viewportController.selectElement(id.toString());
    }
  }
}
