// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

extension _ViewerViewState on _ViewerHomePageState {
  ViewerViewportScenePolicy get _viewportScenePolicy =>
      ViewerViewportScenePolicy(
        projectionMode: _projectionMode,
        activeLevelId: _activeLevelId,
        planViewRangeMeters: _planViewRangeMeters,
      );

  Set<String> _sanitizeVisibleKinds({
    required Set<String> visibleKinds,
    required RenderScene scene,
  }) =>
      _viewportScenePolicy.sanitizeVisibleKinds(
        visibleKinds: visibleKinds,
        scene: scene,
      );

  int? _resolveInitialLevelId(RenderScene scene, {int? preferred}) {
    final levels = scene.levels;
    if (levels.isEmpty) {
      return preferred;
    }
    if (preferred != null && scene.levelById(preferred) != null) {
      return preferred;
    }
    return levels.first.levelId;
  }

  RenderScene _sceneForViewport(RenderScene scene) =>
      _viewportScenePolicy.sceneForViewport(scene);

  Set<String> _defaultVisibleKindsForProjection(RenderScene scene) =>
      _viewportScenePolicy.defaultVisibleKinds(scene);

  Set<String> _ensurePlanCoreVisibility(Set<String> kinds, RenderScene scene) =>
      _viewportScenePolicy.ensurePlanCoreVisibility(kinds, scene);

  RenderSceneDisplayStyle _defaultDisplayStyleForProjection() =>
      _viewportScenePolicy.defaultDisplayStyle;

  RenderSceneLevel? _activeLevel(RenderScene? scene) {
    if (scene == null) {
      return null;
    }
    return scene.levelById(_activeLevelId) ??
        (scene.levels.isNotEmpty ? scene.levels.first : null);
  }

  double _activeLevelElevation(RenderScene? scene) {
    return _activeLevel(scene)?.elevationMeters ?? 0.0;
  }

  double _activeLevelDefaultWallHeight(RenderScene? scene) {
    return _activeLevel(scene)?.defaultWallHeightMeters ??
        _ViewerHomePageState._defaultWallHeightMeters;
  }

  RenderSceneLevel? _pickLevelAtElevation(
    RenderScene scene,
    RenderScenePoint? modelPoint, {
    double toleranceMeters = 1.4,
  }) {
    if (modelPoint == null ||
        !(_projectionMode.isElevation ||
            _projectionMode.supportsPlanFootprintEditing)) {
      return null;
    }
    RenderSceneLevel? bestLevel;
    var bestDistance = toleranceMeters;
    for (final level in scene.levels) {
      final distance = (modelPoint.z - level.elevationMeters).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestLevel = level;
      }
    }
    return bestLevel;
  }

  RenderSceneLevel? _nextHigherLevel(RenderScene scene, int baseLevelId) {
    final base = scene.levelById(baseLevelId);
    if (base == null) {
      return null;
    }
    final sorted = [...scene.levels]
      ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
    for (final level in sorted) {
      if (level.elevationMeters > base.elevationMeters + 1e-6) {
        return level;
      }
    }
    return null;
  }

  Future<void> _attachWallToActiveLevel(
    RenderSceneObject object, {
    required bool constrainToNextLevel,
  }) async {
    final scene = _scene;
    final repository = _engineRepository;
    final wallId = object.elementId;
    final activeLevelId = _activeLevelId;
    if (scene == null ||
        repository == null ||
        !_engineBackedMode ||
        wallId == null ||
        activeLevelId == null ||
        object.kindKey != 'wall') {
      _updateViewportState(() {
        _editStatusMessage =
            'Wall attachment requires engine mode and an active level.';
      });
      return;
    }

    final nextLevel =
        constrainToNextLevel ? _nextHigherLevel(scene, activeLevelId) : null;
    if (constrainToNextLevel && nextLevel == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'No level above the active level was found for the top constraint.';
      });
      return;
    }

    final parameters = WallElementParameters.fromObject(object);
    final result = await repository.setWallLevelConstraints(
      wallId: wallId,
      baseLevelId: activeLevelId,
      topLevelId: nextLevel?.levelId ?? 0,
      baseOffsetMeters: parameters.baseOffsetMeters,
      topOffsetMeters: parameters.topOffsetMeters,
      heightMode: constrainToNextLevel ? 1 : 0,
    );
    await _applyEngineSceneResult(
      result,
      message: constrainToNextLevel
          ? 'Wall active levelga biriktirildi, top ${nextLevel?.name}ga constraint qilindi.'
          : 'Wall active levelga biriktirildi.',
    );
  }

  Future<void> _setActiveLevel(int? levelId) {
    if (!mounted || _workspaceBusy) return Future<void>.value();
    return _runViewNavigation(() => _setActiveLevelNow(levelId));
  }

  Future<void> _setActiveLevelNow(int? levelId) async {
    final initialScene = _scene;
    final wasGeneratedSection = _activeSectionView != null;
    if (initialScene == null ||
        levelId == null ||
        (_activeLevelId == levelId && !wasGeneratedSection)) {
      return;
    }
    var activeScene = initialScene;
    if (wasGeneratedSection) {
      // Selecting a plan level is an explicit navigation away from the
      // generated cut scene. The engine call below reloads the authoritative
      // model snapshot for that level.
      _updateViewportState(() => _activeSectionView = null);
      await _viewportController.setSectionView(null);
    }
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await _sceneViews.activateLevel(levelId);
      if (!mounted) {
        return;
      }
      final loadedScene = result.scene;
      if (loadedScene == null) {
        final detail = result.errors.isEmpty
            ? 'The engine returned an empty RenderScene.'
            : result.errors.join('\n');
        throw StateError('Level $levelId activation failed: $detail');
      }
      activeScene = loadedScene;
    }
    final level = activeScene.levelById(levelId);
    _updateViewportState(() {
      _scene = activeScene;
      _activeLevelId = levelId;
      _draftFloorTopElevationMeters = level?.elevationMeters ?? 0.0;
      _draftSurfaceHeightMeters = level?.defaultWallHeightMeters ??
          _ViewerHomePageState._defaultWallHeightMeters;
      _statusMessage = 'Active level changed.';
      if (_usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(activeScene);
      } else {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: _sceneForViewport(activeScene),
        );
      }
      if (_usesProjectionDefaultDisplayStyle) {
        _displayStyle = _defaultDisplayStyleForProjection();
      }
    });
    await _viewportController.loadRenderScene(_sceneForViewport(activeScene));
    await _viewportController.setVisibleKinds(_visibleKinds);
    await _viewportController.setProjectionMode(_projectionMode);
    await _viewportController.setOrbitProjectionStyle(_orbitProjectionStyle);
    await _viewportController.setDisplayStyle(_displayStyle);
    await _viewportController.selectElement(null);
    await _viewportController.highlightElement(null);
    await _viewportController.fitCamera();
  }
}
