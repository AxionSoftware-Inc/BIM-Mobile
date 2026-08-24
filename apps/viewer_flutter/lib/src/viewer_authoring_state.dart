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
      _statusMessage = 'Selected ${level.name}';
      _editStatusMessage =
          '${level.name}: ${level.elevationMeters.toStringAsFixed(2)} m. Inspector orqali tahrir qiling yoki level line’ni torting.';
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
      _editStatusMessage = mode == RenderSceneInteractionMode.select
          ? 'Selection mode'
          : 'Editing mode: ${mode.authoringLabel}';
      _statusMessage = _editStatusMessage;
    });

    await _viewportController.setInteractionMode(mode);
    await _clearDraft();

    if (mode == RenderSceneInteractionMode.addFloor ||
        mode == RenderSceneInteractionMode.addCeiling ||
        mode == RenderSceneInteractionMode.addRoof) {
      _surfaceTool.drawMode = RenderSceneSurfaceDrawMode.pickWalls;
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage =
              'Pick Walls: tap each enclosing wall. Selected walls turn blue; use Undo to remove the last one.';
        });
      }
    }

    if ((mode == RenderSceneInteractionMode.moveOpening ||
            mode == RenderSceneInteractionMode.addDoor ||
            mode == RenderSceneInteractionMode.addWindow) &&
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

  Future<void> _prepareAutomaticFlatRoof() async {
    final scene = _scene;
    final baseLevelId = _activeLevelId;
    if (scene == null || baseLevelId == null) {
      return;
    }
    final baseLevel = scene.levelById(baseLevelId);
    final candidates = scene.objects
        .where((object) => object.kindKey == 'wall')
        .where((object) =>
            (_metadataInt(object, 'base_level_id') ?? object.levelId) ==
            baseLevelId)
        .where((object) => object.elementId != null)
        .toList(growable: false);
    final topLevelIds = <int>{
      for (final wall in candidates)
        if ((_metadataInt(wall, 'top_level_id') ?? 0) > 0)
          _metadataInt(wall, 'top_level_id')!,
    };
    final roofLevelId = topLevelIds.isNotEmpty
        ? (topLevelIds.toList()
              ..sort((left, right) =>
                  (scene.levelById(left)?.elevationMeters ?? 0)
                      .compareTo(scene.levelById(right)?.elevationMeters ?? 0)))
            .last
        : (scene.levels
                .where((level) =>
                    baseLevel != null &&
                    level.elevationMeters > baseLevel.elevationMeters + 1e-6)
                .toList()
              ..sort((left, right) =>
                  left.elevationMeters.compareTo(right.elevationMeters)))
            .firstOrNull
            ?.levelId;
    if (roofLevelId == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Automatic roof uchun wall top level yoki undan yuqori level kerak.';
      });
      return;
    }
    final boundWalls = candidates
        .where(
            (wall) => (_metadataInt(wall, 'top_level_id') ?? 0) == roofLevelId)
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(boundWalls);
    if (polygon == null || polygon.length < 3) {
      _updateViewportState(() {
        _editStatusMessage =
            'Automatic roof faqat bitta yopiq outer wall loop topilganda yaratiladi. Murakkab plan uchun wall loop tanlang yoki footprint chizing.';
      });
      return;
    }
    final existingRoof = scene.objects.any(
      (object) => object.kindKey == 'roof' && object.levelId == roofLevelId,
    );
    if (existingRoof) {
      _updateViewportState(() {
        _editStatusMessage =
            'Bu roof levelda roof bor. Duplicate yaratilmadi; avval mavjud roofni tahrir qiling.';
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
          'Automatic roof footprint ready: ${boundWalls.length} wall, ${scene.levelById(roofLevelId)?.name ?? 'Level'}. Confirm bosing.';
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
      _draftMoveLevelId = null;
      _moveLevelOriginalElevation = null;
      _wallMoveMode = WallMoveMode.translate;
    });

    _viewportController.clearDraft();
  }

  Future<void> _deleteSelectedObject() async {
    final scene = _scene;
    if (scene == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Delete uchun avval obyektni tanlang.';
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
        _editStatusMessage = 'Delete uchun avval obyektni tanlang.';
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
        message: '${selectedIds.length} ta obyekt o‘chirildi.',
      );
      return;
    }

    var nextScene = scene;
    for (final id in selectedIds) {
      final target = nextScene.objectByStableId(id.toString());
      if (target != null) {
        nextScene =
            RenderSceneEditor.deleteObject(scene: nextScene, target: target);
      }
    }
    await _applySceneChange(
      nextScene,
      message: '${selectedIds.length} ta obyekt o‘chirildi.',
    );
  }

  Future<void> _applySceneChange(
    RenderScene nextScene, {
    required String message,
    bool authoritative = false,
  }) async {
    if (!authoritative) {
      _updateViewportState(() {
        _editStatusMessage =
            'Engine ulanmagan: preview ko‘rsatilyapti, lekin model o‘zgartirilmaydi.';
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
    final resolvedLevelId =
        _resolveInitialLevelId(nextScene, preferred: _activeLevelId);
    _viewWorkspace.clearSheetCache();

    _updateViewportState(() {
      _scene = nextScene;
      _activeLevelId = resolvedLevelId;
      _activeSectionView = null;
      _statusMessage = message;
      _editStatusMessage = message;
      _loadError = null;
    });

    final nextViewportScene = _sceneForViewport(nextScene);

    _updateViewportState(() {
      if (_usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(nextScene);
      } else {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: nextViewportScene,
        );
      }
      _visibleKinds = _ensurePlanCoreVisibility(_visibleKinds, nextScene);
    });

    // A delete can remove the active renderable. Clear its native selection
    // before rebuilding Filament so a frame never tries to tint/highlight an
    // entity that has just been destroyed, which showed up as a tablet flash.
    if (previousSelectedId != null && nextSelected == null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    }

    await _viewportController.updateRenderScene(nextViewportScene);
    await _viewportController.setVisibleKinds(_visibleKinds);

    if (previousSelectedLevelId != null &&
        nextScene.levelById(previousSelectedLevelId) != null) {
      await _viewportController.selectLevel(previousSelectedLevelId);
      return;
    }

    if (nextSelected != null) {
      await _viewportController
          .selectElement(nextSelected.elementId?.toString());
      await _viewportController
          .highlightElement(nextSelected.elementId?.toString());
    } else if (previousSelectedId != null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    } else if (selectedBefore != null) {
      await _viewportController
          .selectElement(selectedBefore.elementId?.toString());
      await _viewportController
          .highlightElement(selectedBefore.elementId?.toString());
    } else {
      await _viewportController.highlightElement(previousHighlightedId);
    }
  }

  Future<void> _applyEngineSceneResult(
    RenderSceneLoadResult result, {
    required String message,
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
