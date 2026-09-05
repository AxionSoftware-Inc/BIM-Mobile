// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

extension _ViewerAuthoringState on _ViewerHomePageState {
  Future<void> _setVisibleKinds(Set<String> kinds) async {
    _updateViewportState(() {
      _visibleKinds = kinds;
      _usesProjectionDefaultVisibility = false;
      _statusMessage =
          kinds.isEmpty ? 'Showing all categories' : 'Updated category filter';
    });

    await _viewportController.setVisibleKinds(kinds);
  }

  Future<void> _selectObject(RenderSceneObject object) async {
    final id = object.elementId?.toString();

    _updateViewportState(() {
      _showSidePanel = true;
      _sidePanelTab = WorkspaceSidePanelTab.inspector;
      _statusMessage = id == null
          ? 'Selected ${prettySceneKind(object.kind)}'
          : 'Selected ${prettySceneKind(object.kind)} #$id';
    });

    // The interaction module may already have created a multi-selection. Keep
    // it intact while making the clicked item the active Inspector object.
    if (id == null || !_viewportController.selectedElementIds.contains(id)) {
      await _selectionController.selectObject(object);
    } else {
      await _viewportController.highlightElement(id);
    }
  }

  Future<void> _clearSelection() async {
    _updateViewportState(() {
      _statusMessage = 'Selection cleared';
    });

    await _selectionController.clear();
  }

  Future<void> _selectLevel(RenderSceneLevel level) async {
    await _setActiveLevel(level.levelId);
    if (!mounted) {
      return;
    }
    _updateViewportState(() {
      _showSidePanel = true;
      _sidePanelTab = WorkspaceSidePanelTab.inspector;
      _statusMessage = 'Selected ${level.name}';
      _editStatusMessage =
          '${level.name}: ${_projectUnitSettings.formatLength(level.elevationMeters)}. Edit it in Inspector or drag the level line.';
    });
    await _selectionController.selectLevel(level.levelId);
  }

  Future<void> _setInteractionMode(RenderSceneInteractionMode mode) async {
    if (_interactionMode == mode) {
      return;
    }

    // A projection switch reloads the engine scene and intentionally resets
    // transient authoring state. Do that first, then activate the requested
    // tool so Floor/Ceiling/Roof stays active when it brings the user to plan.
    if (mode.requiresPlanProjection &&
        _projectionMode != kDefaultPlanProjectionMode) {
      await _setProjectionMode(kDefaultPlanProjectionMode);
    }

    if (mode.prefersElevationProjection &&
        _projectionMode == RenderSceneProjectionMode.isometric) {
      await _setProjectionMode(kDefaultElevationProjectionMode);
    }

    final selected = _selectedObject(_scene);

    _updateViewportState(() {
      _interactionMode = mode;
      if (mode != RenderSceneInteractionMode.select) {
        _showSidePanel = true;
        _sidePanelTab = WorkspaceSidePanelTab.inspector;
      }
      _editStatusMessage = mode == RenderSceneInteractionMode.select
          ? 'Selection mode'
          : 'Editing mode: ${mode.authoringLabel}';
      _statusMessage = _editStatusMessage;
    });

    await _viewportController.setInteractionMode(mode);
    await _clearDraft();

    if (mode == RenderSceneInteractionMode.addDoor ||
        mode == RenderSceneInteractionMode.addWindow) {
      _openingTool.prepareForCreation(
        window: mode == RenderSceneInteractionMode.addWindow,
      );
    }

    if (mode == RenderSceneInteractionMode.addFloor ||
        mode == RenderSceneInteractionMode.addCeiling ||
        mode == RenderSceneInteractionMode.addRoof) {
      _surfaceTool.drawMode = RenderSceneSurfaceDrawMode.pickWalls;
      if (mode == RenderSceneInteractionMode.addFloor) {
        _surfaceTool.floorAssemblyId = _scene?.floorTypes.firstOrNull?.id ?? 0;
      }
      if (mode == RenderSceneInteractionMode.addRoof) {
        _surfaceTool.roofAssemblyId = _scene?.roofTypes.firstOrNull?.id ?? 0;
      }
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage =
              'Pick Walls: tap each enclosing wall. Selected walls turn blue; use Undo to remove the last one.';
        });
      }
    }

    if (mode == RenderSceneInteractionMode.addStair) {
      final base = _activeLevel(_scene);
      final top = base == null || _scene == null
          ? null
          : _nextHigherLevel(_scene!, base.levelId);
      _stairTool
        ..setBaseLevelId(base?.levelId)
        ..setTopLevelId(top?.levelId);
    }

    if (mode == RenderSceneInteractionMode.moveOpening &&
        selected != null &&
        (selected.kindKey == 'door' || selected.kindKey == 'window')) {
      _updateViewportState(() {
        _primeOpeningDraftFromObject(selected);
      });
    }

    if (mode == RenderSceneInteractionMode.addRoof) {
      await _prepareAutomaticFlatRoof();
    }
  }

  Future<void> _setWallDrawMode(WallDrawMode mode) async {
    if (_interactionMode != RenderSceneInteractionMode.addWall ||
        _wallTool.drawMode == mode) {
      return;
    }

    final hadChainEndpoint = _wallTool.chainEndpoint != null;
    _wallTool.switchDrawMode(mode);
    _viewportController.clearDraft();
    if (mode == WallDrawMode.arc) {
      _syncWallArcDraft();
    } else if (_wallTool.start != null) {
      _viewportController.setWallDraft(
        _wallTool.start,
        _wallTool.end ?? _wallTool.start,
      );
    }
    if (!mounted) return;
    _updateViewportState(() {
      _editStatusMessage = hadChainEndpoint
          ? mode == WallDrawMode.arc
              ? 'Arc mode: set two endpoints, then drag the midpoint handle for radius.'
              : mode == WallDrawMode.straight
                  ? 'Continue from the last wall endpoint.'
                  : mode.description
          : mode.description;
      _statusMessage = _editStatusMessage;
    });
  }

  Future<void> _prepareAutomaticFlatRoof() async {
    final scene = _scene;
    final baseLevelId = _activeLevelId;
    if (scene == null || baseLevelId == null) {
      return;
    }
    final baseLevel = scene.levelById(baseLevelId);
    final candidates = scene.objects
        .where((object) => object.kindKey == 'wall')
        .where(
          (object) =>
              (WallElementParameters.fromObject(object).baseLevelId ??
                  object.levelId) ==
              baseLevelId,
        )
        .where((object) => object.elementId != null)
        .toList(growable: false);
    final topLevelIds = <int>{
      for (final wall in candidates)
        if ((WallElementParameters.fromObject(wall).topLevelId ?? 0) > 0)
          WallElementParameters.fromObject(wall).topLevelId!,
    };
    final roofLevelId = topLevelIds.isNotEmpty
        ? (topLevelIds.toList()
              ..sort(
                (left, right) => (scene.levelById(left)?.elevationMeters ?? 0)
                    .compareTo(scene.levelById(right)?.elevationMeters ?? 0),
              ))
            .last
        : (scene.levels
                .where(
                  (level) =>
                      baseLevel != null &&
                      level.elevationMeters > baseLevel.elevationMeters + 1e-6,
                )
                .toList()
              ..sort(
                (left, right) =>
                    left.elevationMeters.compareTo(right.elevationMeters),
              ))
            .firstOrNull
            ?.levelId;
    if (roofLevelId == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Automatic roof requires a wall top level or a higher level.';
      });
      return;
    }
    final boundWalls = candidates
        .where(
          (wall) =>
              (WallElementParameters.fromObject(wall).topLevelId ?? 0) ==
              roofLevelId,
        )
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(boundWalls);
    if (polygon == null || polygon.length < 3) {
      _updateViewportState(() {
        _editStatusMessage =
            'Automatic roof needs one closed outer wall loop. Select a wall loop or draw a footprint for a complex plan.';
      });
      return;
    }
    final existingRoof = scene.objects.any(
      (object) => object.kindKey == 'roof' && object.levelId == roofLevelId,
    );
    if (existingRoof) {
      _updateViewportState(() {
        _editStatusMessage =
            'This level already has a roof. No duplicate was created; edit the existing roof instead.';
      });
      return;
    }
    _surfaceTool
      ..drawMode = RenderSceneSurfaceDrawMode.pickWalls
      ..replaceWallIds(
        boundWalls.map((wall) => wall.elementId!).toList(growable: false),
      )
      ..replacePoints(polygon);
    _updateViewportState(() {
      _activeLevelId = roofLevelId;
      _editStatusMessage =
          'Automatic roof footprint ready: ${boundWalls.length} walls on ${scene.levelById(roofLevelId)?.name ?? 'Level'}. Tap Confirm.';
    });
    _viewportController.setSurfaceDraft(
      RenderSceneSurfaceDraft(kind: 'roof', points: polygon, closed: true),
    );
  }

  void _setSurfaceDrawMode(RenderSceneSurfaceDrawMode value) {
    if (_surfaceDrawMode == value) {
      return;
    }
    _updateViewportState(() {
      _surfaceDrawMode = value;
      _draftSurfaceStart = null;
      _draftSurfaceEnd = null;
      _draftSurfacePoints.clear();
      _draftSurfaceWallIds.clear();
      _surfaceTool.reopenBoundary();
      _editStatusMessage = switch (value) {
        RenderSceneSurfaceDrawMode.polyline =>
          'Boundary sketch: drag one straight segment at a time around the room. Close it, then Finish.',
        RenderSceneSurfaceDrawMode.rectangle =>
          'Rectangle sketch: tap two opposite corners.',
        RenderSceneSurfaceDrawMode.pickWalls =>
          'Pick Walls: tap enclosing walls, then Finish.',
        RenderSceneSurfaceDrawMode.autoRoom =>
          'Auto Room: tap a room to create the system.',
      };
    });
    _viewportController.setSurfaceDraft(null);
  }

  void _undoSurfaceDraft() {
    final scene = _scene;
    if (!_surfaceTool.undoLast()) return;
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
        scene != null) {
      _syncSurfaceDraftFromWalls(scene);
    } else {
      _syncSurfaceDraftPreview();
    }
    _updateViewportState(() {
      _editStatusMessage = switch (_surfaceDrawMode) {
        RenderSceneSurfaceDrawMode.polyline => _surfaceTool.boundaryClosed
            ? 'Boundary reopened. Undo again to remove the last point.'
            : '${_draftSurfacePoints.length} boundary points remain. Add the next corner or close the contour.',
        RenderSceneSurfaceDrawMode.pickWalls =>
          '${_draftSurfaceWallIds.length} picked walls remain.',
        RenderSceneSurfaceDrawMode.rectangle =>
          'Rectangle cleared. Drag again to draw.',
        RenderSceneSurfaceDrawMode.autoRoom => 'Tap a room.',
      };
    });
  }

  void _toggleBoundaryClosed() {
    if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.polyline) {
      return;
    }
    if (_surfaceTool.boundaryClosed) {
      _surfaceTool.reopenBoundary();
      _draftSurfaceEnd = _draftSurfacePoints.lastOrNull;
      _syncSurfaceDraftPreview();
      _updateViewportState(() {
        _editStatusMessage =
            'Boundary reopened. Fix the pink sketch, then close it again.';
      });
      return;
    }

    final points = _draftSurfacePoints;
    if (!SurfaceAuthoringGeometry.isValidBoundary(points, closed: true)) {
      _updateViewportState(() {
        _editStatusMessage = SurfaceAuthoringGeometry.boundaryValidationMessage(
          points,
          closed: false,
        );
      });
      return;
    }
    _surfaceTool.closeBoundary();
    _draftSurfaceEnd = points.firstOrNull;
    _syncSurfaceDraftPreview();
    _updateViewportState(() {
      _editStatusMessage =
          'Boundary closed. Check the pink outline, then tap Finish.';
    });
  }

  Future<void> _clearDraft() async {
    final activeLevel = _activeLevel(_scene);
    _wallTool.reset();
    _levelTool.reset();
    _openingTool.reset();
    _surfaceTool.reset(
      levelElevation: activeLevel?.elevationMeters ?? 0.0,
      defaultHeight: activeLevel?.defaultWallHeightMeters ??
          _ViewerHomePageState._defaultWallHeightMeters,
    );
    _stairTool.reset();
    _trimTool.reset();
    _updateViewportState(() {
      _draftWallStart = null;
      _draftWallEnd = null;
      _draftMoveTarget = null;
      _moveAnchorPoint = null;
      _moveWallOriginalStart = null;
      _moveWallOriginalEnd = null;
      _draftWallArcGeometry = null;
      _draftMoveElementPoint = null;
      _draftMoveLevelId = null;
      _moveLevelOriginalElevation = null;
      _wallMoveMode = WallMoveMode.translate;
      _openingGestureActive = false;
    });

    _viewportController.clearDraft();
  }

  Future<void> _deleteSelectedObject() async {
    final scene = _scene;
    if (scene == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Select an object before deleting.';
      });
      return;
    }

    final selectedIds = _viewportController.selectedElementIds
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (selectedIds.isEmpty) {
      final selected = _selectedObject(scene);
      if (selected?.elementId != null) selectedIds.add(selected!.elementId!);
    }
    if (selectedIds.isEmpty) {
      _updateViewportState(() {
        _editStatusMessage = 'Select an object before deleting.';
      });
      return;
    }

    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final selectedObjects = scene.objects
          .where((object) => selectedIds.contains(object.elementId))
          .toList(growable: false)
        ..sort((a, b) {
          final aOpening = a.kindKey == 'door' || a.kindKey == 'window';
          final bOpening = b.kindKey == 'door' || b.kindKey == 'window';
          return aOpening == bOpening ? 0 : (aOpening ? -1 : 1);
        });
      RenderSceneLoadResult? result;
      for (final object in selectedObjects) {
        if (object.elementId == null) continue;
        result = await repository.deleteElement(elementId: object.elementId!);
      }
      if (result == null) return;
      await _applyEngineSceneResult(
        result,
        message: '${selectedIds.length} object(s) deleted.',
      );
      return;
    }

    var nextScene = scene;
    for (final id in selectedIds) {
      final target = nextScene.objectByStableId(id.toString());
      if (target != null) {
        nextScene = RenderSceneEditor.deleteObject(
          scene: nextScene,
          target: target,
        );
      }
    }
    await _applySceneChange(
      nextScene,
      message: '${selectedIds.length} object(s) deleted.',
    );
  }

  Future<void> _applySceneChange(
    RenderScene nextScene, {
    required String message,
    bool authoritative = false,
    int? revealElementId,
    int? selectElementId,
  }) {
    // Reserve the next presentation revision before entering the queue. This
    // invalidates any deferred read immediately, even while the native
    // command's scene snapshot is waiting for its turn to render.
    final sceneDataRevision = ++_sceneDataRevision;
    return _sceneCommitQueue.run(
      () => _applySceneChangeNow(
        nextScene,
        message: message,
        authoritative: authoritative,
        revealElementId: revealElementId,
        selectElementId: selectElementId,
        sceneDataRevision: sceneDataRevision,
      ),
    );
  }

  Future<void> _applySceneChangeNow(
    RenderScene nextScene, {
    required String message,
    bool authoritative = false,
    int? revealElementId,
    int? selectElementId,
    required int sceneDataRevision,
  }) async {
    // Engine mutations are already serialized, so a newer queued snapshot
    // contains every change represented by this one. Do not spend a native
    // scene rebuild on an intermediate snapshot after several rapid edits;
    // this is the presentation-side latest-wins rule that keeps the viewport
    // responsive without dropping any document mutation.
    if (sceneDataRevision != _sceneDataRevision) return;
    if (!authoritative) {
      _updateViewportState(() {
        _editStatusMessage =
            'The engine is not connected: preview is available, but the model is read-only.';
      });
      return;
    }
    final previousSelectedId = _viewportController.selectedElementId;
    final previousSelectedLevelId = _viewportController.selectedLevelId;
    final previousHighlightedId = _viewportController.highlightedElementId;
    final selectedBefore = _selectedObject(nextScene);
    final nextSelected = previousSelectedId != null
        ? nextScene.objectByStableId(previousSelectedId)
        : null;
    final resolvedLevelId = _resolveInitialLevelId(
      nextScene,
      preferred: _activeLevelId,
    );
    _viewWorkspace.clearSheetCache();

    final nextViewportScene = _sceneForViewport(nextScene);
    final nextVisibleKinds = _usesProjectionDefaultVisibility
        ? _defaultVisibleKindsForProjection(nextScene)
        : _sanitizeVisibleKinds(
            visibleKinds: _visibleKinds,
            scene: nextViewportScene,
          );
    final resolvedVisibleKinds = _ensurePlanCoreVisibility(
      nextVisibleKinds,
      nextScene,
    );
    // A newly created element must remain visible even when the user has an
    // explicit category filter active.  Placement is a focused authoring
    // action: reveal only the new element's category, preserving every other
    // filter choice instead of resetting the whole visibility policy.
    final revealedKind = revealElementId == null
        ? null
        : nextScene.objectById(revealElementId)?.kindKey;
    if (revealedKind != null) {
      resolvedVisibleKinds.add(revealedKind);
    }

    // Publish the semantic scene and its presentation policy together. An
    // intermediate frame with a new scene but stale visibility/active-level
    // state could resize overlays while the native viewport was committing,
    // which made a wall endpoint appear to jump on release.
    _updateViewportState(() {
      _scene = nextScene;
      _projectHasChanges = true;
      _activeLevelId = resolvedLevelId;
      _activeSectionView = null;
      _statusMessage = message;
      _editStatusMessage = message;
      _loadError = null;
      _visibleKinds = resolvedVisibleKinds;
    });

    // A delete can remove the active renderable. Clear its native selection
    // before rebuilding Filament so a frame never tries to tint/highlight an
    // entity that has just been destroyed, which showed up as a tablet flash.
    if (previousSelectedId != null && nextSelected == null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    }

    // Scene and its visibility policy are one viewport presentation commit.
    await _viewportController.updateRenderScene(
      nextViewportScene,
      visibleKinds: _visibleKinds,
    );

    if (selectElementId != null &&
        nextScene.objectById(selectElementId) != null) {
      // Selection and visibility are committed together for placement. This
      // avoids restoring the previous wall/level selection for one frame and
      // makes the newly placed family the only active Inspector object.
      final selectedId = selectElementId.toString();
      await _viewportController.selectElements(
        <String>{selectedId},
        activeElementId: selectedId,
      );
      await _viewportController.highlightElement(selectedId);
      _scheduleRecoveryAutosave();
      return;
    }

    if (previousSelectedLevelId != null &&
        nextScene.levelById(previousSelectedLevelId) != null) {
      await _viewportController.selectLevel(previousSelectedLevelId);
      _scheduleRecoveryAutosave();
      return;
    }

    if (nextSelected != null) {
      await _viewportController.selectElement(
        nextSelected.elementId?.toString(),
      );
      await _viewportController.highlightElement(
        nextSelected.elementId?.toString(),
      );
    } else if (previousSelectedId != null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    } else if (selectedBefore != null) {
      await _viewportController.selectElement(
        selectedBefore.elementId?.toString(),
      );
      await _viewportController.highlightElement(
        selectedBefore.elementId?.toString(),
      );
    } else {
      await _viewportController.highlightElement(previousHighlightedId);
    }
    _scheduleRecoveryAutosave();
  }

  Future<void> _applyEngineSceneResult(
    RenderSceneLoadResult result, {
    required String message,
    int? revealElementId,
    int? selectElementId,
  }) async {
    if (result.scene == null) {
      _updateViewportState(() {
        _editStatusMessage = result.errors.isNotEmpty
            ? result.errors.join('\n')
            : 'Engine update failed.';
      });
      return;
    }
    await _applySceneChange(
      result.scene!,
      message: message,
      authoritative: true,
      revealElementId: revealElementId,
      selectElementId: selectElementId,
    );
  }

  RenderSceneObject? _selectedObject(RenderScene? scene) {
    if (scene == null) {
      return null;
    }

    final selectedId = _viewportController.selectedElementId;
    if (selectedId == null) {
      return null;
    }

    final parsedId = int.tryParse(selectedId);
    return scene.objectById(parsedId);
  }

  void _primeOpeningDraftFromObject(RenderSceneObject object) {
    _openingTool.loadFromMetadata(object.metadata);
  }

  List<String> _availableKinds(RenderScene? scene) {
    if (scene == null) {
      return <String>[];
    }

    final available = scene.kindCounts.keys.toSet();
    final ordered = <String>[
      for (final kind in _ViewerHomePageState._coreKindOrder)
        if (available.contains(kind)) kind,
      for (final kind in available)
        if (!_ViewerHomePageState._coreKindOrder.contains(kind)) kind,
    ];

    return ordered;
  }
}
