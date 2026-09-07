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

    // The active level is authoring/navigation state. It must never replace
    // the authoritative full-building scene with the engine's level-scoped
    // render snapshot. Doing so makes a later 3D transition reuse only the
    // nearby storeys and is the root cause of roofs/floors disappearing after
    // repeated 2D <-> 3D switching.
    var authoritativeScene = initialScene;
    if (wasGeneratedSection) {
      _updateViewportState(() => _activeSectionView = null);
      await _viewportController.setSectionView(null);
    }

    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final levelResult = await _sceneViews.activateLevel(levelId);
      if (!mounted) return;
      if (levelResult.scene == null) {
        final detail = levelResult.errors.isEmpty
            ? 'The engine returned an empty RenderScene.'
            : levelResult.errors.join('\n');
        throw StateError('Level $levelId activation failed: $detail');
      }

      // Restore render scope immediately after the engine has accepted the
      // active authoring level. Plan isolation belongs to the viewport policy,
      // not to the document snapshot. This also guarantees that native BIM
      // geometry cannot remain stuck in a level-only scope when 3D is opened.
      final fullResult = await _sceneViews.setFullSceneRenderScope(true);
      if (!mounted) return;
      if (fullResult.scene != null) {
        authoritativeScene = fullResult.scene!;
      } else {
        // Preserve the previous known-full scene rather than promoting the
        // temporary level snapshot. Surface the engine warning without
        // corrupting presentation state.
        _engineLoadDiagnostic = fullResult.errors.isEmpty
            ? 'Full-building render scope returned no scene.'
            : fullResult.errors.join('\n');
      }
    }

    final level = authoritativeScene.levelById(levelId) ??
        initialScene.levelById(levelId);
    _updateViewportState(() {
      _scene = authoritativeScene;
      _activeLevelId = levelId;
      _draftFloorTopElevationMeters = level?.elevationMeters ?? 0.0;
      _draftSurfaceHeightMeters = level?.defaultWallHeightMeters ??
          _ViewerHomePageState._defaultWallHeightMeters;
      _statusMessage = level == null
          ? 'Active level changed.'
          : '${level.name} · active level';
      if (_usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(authoritativeScene);
      } else {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: _sceneForViewport(authoritativeScene),
        );
      }
      if (_usesProjectionDefaultDisplayStyle) {
        _displayStyle = _defaultDisplayStyleForProjection();
      }
    });

    // Only this presentation snapshot is level-filtered. `_scene` remains the
    // complete building, so switching back to 3D is always lossless.
    await _viewportController.loadRenderScene(
      _sceneForViewport(authoritativeScene),
    );
    await _viewportController.setVisibleKinds(_visibleKinds);
    await _viewportController.setProjectionMode(_projectionMode);
    await _viewportController.setOrbitProjectionStyle(_orbitProjectionStyle);
    await _viewportController.setDisplayStyle(_displayStyle);
    await _viewportController.selectElement(null);
    await _viewportController.highlightElement(null);
    await _viewportController.fitCamera();
  }
}
