part of 'viewer_app.dart';

/// Pointer routing and wall/stair/level creation.
extension _ViewerViewportInput on _ViewerHomePageState {
  Future<void> _handleSceneTap(RenderSceneTapDetails details) async {
    final scene = _scene;
    final tappedObject = details.pickedObject;
    final pickedLevel = details.pickedLevel;
    final modelPoint = details.modelPoint;

    if (scene == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        if (pickedLevel != null && _projectionMode.isElevation) {
          await _selectLevel(pickedLevel);
          return;
        }
        if (tappedObject != null) {
          final tappedId = tappedObject.elementId?.toString();
          // Modifier selection is already resolved by ViewportInteractionController.
          // A Ctrl-click may have removed this object, so never re-add it here.
          if (tappedId != null &&
              !_viewportController.selectedElementIds.contains(tappedId)) {
            if (_viewportController.selectedElementIds.isEmpty) {
              await _clearSelection();
            } else {
              _updateViewportState(() {
                _statusMessage =
                    '${_viewportController.selectedElementIds.length} objects selected';
              });
            }
            return;
          }
          if (_projectionMode.isElevation && tappedObject.levelId != null) {
            await _setActiveLevel(tappedObject.levelId);
            _updateViewportState(() {
              _editStatusMessage =
                  '${prettySceneKind(tappedObject.kind)} leveli active qilindi.';
              _statusMessage = _editStatusMessage;
            });
          }
          await _selectObject(tappedObject);
          return;
        }
        if (_projectionMode.isElevation) {
          final pickedLevel = _pickLevelAtElevation(scene, modelPoint);
          if (pickedLevel != null) {
            await _selectLevel(pickedLevel);
            return;
          }
        }
        await _clearSelection();
        return;
      case RenderSceneInteractionMode.addWall:
        await _handleAddWallTap(modelPoint);
        return;
      case RenderSceneInteractionMode.addLevel:
        await _handleAddLevelTap(modelPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        _handleMoveLevelStart(
          scene,
          modelPoint,
          pickedLevel: pickedLevel,
        );
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        await _handleOpeningTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.moveWall:
        await _handleMoveWallTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.moveOpening:
        await _handleMoveOpeningTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.trimExtend:
        await _handleTrimExtendTap(tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        _surfaceBoundaryMultiTouch = false;
        await _handleSurfaceTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.addStair:
        await _handleAddStairTap(modelPoint);
        return;
    }
  }

  void _handleSceneHover(RenderSceneTapDetails details) {
    final modelPoint = details.modelPoint;
    if (modelPoint == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return;
      case RenderSceneInteractionMode.addWall:
        final start = _wallTool.start;
        if (start == null) {
          return;
        }
        final snappedPoint = _draftLinePoint(
          rawPoint: modelPoint,
          referenceStart: start,
        );
        if (_wallTool.end == snappedPoint) {
          return;
        }
        _wallTool.preview(snappedPoint);
        _viewportController.setWallDraft(start, snappedPoint);
        return;
      case RenderSceneInteractionMode.addLevel:
        final start = _levelTool.start;
        if (start == null) {
          return;
        }
        final snappedPoint = _draftLinePoint(
          rawPoint: modelPoint,
          referenceStart: start,
        );
        if (_levelTool.end == snappedPoint) {
          return;
        }
        _levelTool.preview(snappedPoint);
        _updateViewportState(() {
          _editStatusMessage =
              'Level draft: ${snappedPoint.z.toStringAsFixed(2)} m';
        });
        _viewportController.setWallDraft(start, snappedPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final scene = _scene;
        if (scene == null) {
          return;
        }
        final hostWall = _resolveHostWall(scene, details.pickedObject);
        if (hostWall == null) {
          return;
        }
        _updateOpeningDraftPreview(
          scene: scene,
          hostWall: hostWall,
          point: modelPoint,
          announce: false,
        );
        return;
      case RenderSceneInteractionMode.moveWall:
        final scene = _scene;
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (scene == null ||
            target == null ||
            target.kindKey != 'wall' ||
            _moveAnchorPoint == null ||
            _moveWallOriginalStart == null ||
            _moveWallOriginalEnd == null) {
          return;
        }
        _updateMoveWallPreview(
          scene: scene,
          wall: target,
          point: modelPoint,
        );
        return;
      case RenderSceneInteractionMode.moveOpening:
        final scene = _scene;
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (scene == null ||
            target == null ||
            (target.kindKey != 'door' && target.kindKey != 'window') ||
            _moveAnchorPoint == null) {
          return;
        }
        _updateMoveOpeningPreview(
          scene: scene,
          opening: target,
          point: modelPoint,
        );
        return;
      case RenderSceneInteractionMode.trimExtend:
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceBoundaryMultiTouch || details.pointerCount > 1) {
          return;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
          final candidate = details.pickedObject;
          if (candidate?.kindKey == 'wall' && candidate?.elementId != null) {
            unawaited(_viewportController
                .highlightElement(candidate!.elementId.toString()));
          }
          return;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
          final candidate = details.pickedObject;
          if (candidate?.kindKey == 'room' && candidate?.elementId != null) {
            unawaited(_viewportController
                .highlightElement(candidate!.elementId.toString()));
          }
          return;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          if (_surfaceTool.boundaryClosed) {
            return;
          }
          final snapped = _surfaceBoundarySnap(modelPoint);
          final first = _draftSurfacePoints.firstOrNull;
          final previewPoint = first != null &&
                  _draftSurfacePoints.length >= 3 &&
                  SurfaceAuthoringGeometry.isNearFirstPoint(
                    _draftSurfacePoints,
                    snapped,
                    toleranceMeters:
                        PlanSketchGeometry.defaultEndpointToleranceMeters,
                  )
              ? first
              : snapped;
          if (_draftSurfaceEnd == previewPoint) {
            return;
          }
          _updateViewportState(() {
            _draftSurfaceEnd = previewPoint;
            _editStatusMessage = first != null &&
                    _draftSurfacePoints.length >= 3 &&
                    previewPoint == first
                ? 'Close target: release near the first point or press Close contour.'
                : _draftSurfacePoints.isEmpty
                    ? 'Touch the first boundary corner, then drag the next segment.'
                    : 'Pink preview: drag to the next corner and release.';
          });
          _syncSurfaceDraftPreview();
          return;
        }
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) {
          return;
        }
        final start = _draftSurfaceStart;
        if (start == null || _draftSurfaceWallIds.isNotEmpty) {
          return;
        }
        final snapped = _snapDraftToGrid ? _snapPoint(modelPoint) : modelPoint;
        if (_draftSurfaceEnd == snapped) {
          return;
        }
        _updateViewportState(() {
          _draftSurfaceEnd = snapped;
          if (_draftSurfacePoints.length == 1) {
            _draftSurfacePoints.add(snapped);
          } else if (_draftSurfacePoints.length >= 2) {
            _draftSurfacePoints[1] = snapped;
          }
        });
        _syncSurfaceDraftPreview();
        return;
      case RenderSceneInteractionMode.addStair:
        final start = _stairTool.start;
        if (start == null) {
          return;
        }
        final snapped =
            _draftLinePoint(rawPoint: modelPoint, referenceStart: start);
        _stairTool.preview(snapped);
        _viewportController.setWallDraft(start, snapped);
        _updateViewportState(() {
          _editStatusMessage =
              'Stair run: ${start.distanceTo(snapped).toStringAsFixed(2)} m';
        });
        return;
    }
  }

  Future<void> _handleAddWallTap(RenderScenePoint? modelPoint) async {
    if (modelPoint == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Tap the 2D plan to place wall endpoints.';
      });
      return;
    }

    final snappedPoint = _draftLinePoint(
      rawPoint: modelPoint,
      referenceStart: _wallTool.start,
    );

    if (!_wallTool.hasStart) {
      _wallTool.begin(snappedPoint);
      _updateViewportState(() {
        _editStatusMessage =
            'Wall start set. Tap again for the end point. Ortho/snap is active.';
      });
      _viewportController.setWallDraft(snappedPoint, snappedPoint);
      return;
    }

    _wallTool.preview(snappedPoint);
    _updateViewportState(() {
      _editStatusMessage =
          'Wall segment: ${_wallTool.start!.distanceTo(snappedPoint).toStringAsFixed(2)} m. Creating...';
    });
    _viewportController.setWallDraft(_wallTool.start, snappedPoint);
    await _commitWallDraft(autoContinue: true);
  }

  Future<void> _handleAddStairTap(RenderScenePoint? modelPoint) async {
    final scene = _scene;
    if (scene == null || modelPoint == null) {
      _updateViewportState(() =>
          _editStatusMessage = 'Place two points on the 2D plan for a stair.');
      return;
    }
    final active = _activeLevel(scene);
    final top = active == null ? null : _nextHigherLevel(scene, active.levelId);
    if (active == null || top == null) {
      _updateViewportState(() => _editStatusMessage =
          'A stair needs a Base Level and a higher Top Level.');
      return;
    }
    final point =
        _draftLinePoint(rawPoint: modelPoint, referenceStart: _stairTool.start);
    if (!_stairTool.hasStart) {
      _stairTool.begin(point);
      _viewportController.setWallDraft(point, point);
      _updateViewportState(() => _editStatusMessage =
          'Stair start set. Ikkinchi nuqta run/directionni belgilaydi.');
      return;
    }
    _stairTool.preview(point);
    _viewportController.setWallDraft(_stairTool.start, point);
    await _commitStairDraft();
  }

  Future<void> _commitStairDraft() async {
    final scene = _scene;
    final start = _stairTool.start;
    final end = _stairTool.end;
    final repository = _engineRepository;
    final base = scene == null ? null : _activeLevel(scene);
    final top = base == null || scene == null
        ? null
        : _nextHigherLevel(scene, base.levelId);
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
    final preview = StairAuthoringGeometry.preview(
      start: start,
      end: end,
      baseLevel: base,
      topLevel: top,
    );
    if (preview == null) {
      final run = start.distanceTo(end);
      _updateViewportState(() => _editStatusMessage = run < 0.8
          ? 'A stair run must be at least 0.80 m.'
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

  Future<void> _handleAddLevelTap(RenderScenePoint? modelPoint) async {
    if (modelPoint == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Tap the elevation view to place a level line.';
      });
      return;
    }

    final snappedPoint = _draftLinePoint(
      rawPoint: modelPoint,
      referenceStart: _levelTool.start,
    );

    if (!_levelTool.hasDraft) {
      _levelTool.begin(snappedPoint);
      _updateViewportState(() {
        _editStatusMessage =
            'Level elevation set. Tap again to define the line length.';
      });
      _viewportController.setWallDraft(snappedPoint, snappedPoint);
      return;
    }

    _levelTool.preview(snappedPoint);
    _updateViewportState(() {
      _editStatusMessage =
          'Level line ready at ${snappedPoint.z.toStringAsFixed(2)} m. Creating level...';
    });
    _viewportController.setWallDraft(_levelTool.start, snappedPoint);
    await _commitLevelDraft();
  }

  Future<void> _commitWallDraft({required bool autoContinue}) async {
    final start = _wallTool.start;
    final end = _wallTool.end;
    if (start == null || end == null) {
      return;
    }

    // Advance the authoring cursor before awaiting the engine. This makes the
    // next finger gesture independent of native commit latency and preserves
    // the exact endpoint that the user just released.
    if (autoContinue) {
      _wallTool.continueFrom(end);
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage =
              'Wall draft ready. Continue from the last endpoint.';
        });
      }
      _viewportController.setWallDraft(end, end);
    }

    final queued = _wallCommitTail.then<void>((_) async {
      try {
        await _commitWallSegment(start, end);
      } catch (error) {
        if (mounted) {
          _updateViewportState(() {
            _editStatusMessage = 'Wall mutation failed: $error';
          });
        }
      }
    });
    _wallCommitTail = queued;
    await queued;
  }

  Future<void> _commitWallSegment(
    RenderScenePoint start,
    RenderScenePoint end,
  ) async {
    final scene = _scene;
    if (scene == null) {
      return;
    }

    final length = start.distanceTo(end);
    if (length < 0.1) {
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage = 'Wall is too short.';
        });
      }
      return;
    }

    final activeLevelId = _activeLevel(scene)?.levelId;
    final baseElevation = _activeLevelElevation(scene);
    final wallHeight = _activeLevelDefaultWallHeight(scene);
    final topLevel =
        activeLevelId == null ? null : _nextHigherLevel(scene, activeLevelId);
    _traceAndroidMutation(
      'wall commit: start=${start.x.toStringAsFixed(2)},${start.y.toStringAsFixed(2)} '
      'end=${end.x.toStringAsFixed(2)},${end.y.toStringAsFixed(2)} '
      'base=$activeLevelId top=${topLevel?.levelId} sceneWalls=${scene.kindCounts['wall'] ?? 0}',
    );
    if (activeLevelId == null) {
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage = 'Select a Base Level before drawing a wall.';
        });
      }
      return;
    }
    final mutation = SceneMutationService(
      engineRepository: _engineBackedMode ? _engineRepository : null,
    );
    final outcome = await mutation.createWall(
      CreateWallRequest(
        scene: scene,
        start: RenderScenePoint(x: start.x, y: start.y, z: baseElevation),
        end: RenderScenePoint(x: end.x, y: end.y, z: baseElevation),
        baseLevelId: activeLevelId,
        topLevelId: topLevel?.levelId ?? 0,
        heightMeters: wallHeight,
        thicknessMeters: _ViewerHomePageState._defaultWallThicknessMeters,
      ),
    );
    for (final entry in outcome.trace) {
      _traceAndroidMutation(entry);
    }
    if (!outcome.success || outcome.scene == null) {
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage = outcome.error ?? 'Wall could not be created.';
        });
      }
      return;
    }
    await _applySceneChange(
      outcome.scene!,
      message: topLevel == null
          ? 'Wall created with the active level height.'
          : 'Wall created and constrained to ${topLevel.name}.',
      authoritative: true,
    );
    if (outcome.createdElementId != null) {
      await _viewportController
          .selectElement(outcome.createdElementId.toString());
      await _viewportController
          .highlightElement(outcome.createdElementId.toString());
    }
  }

  Future<void> _commitLevelDraft() async {
    final scene = _scene;
    final start = _levelTool.start;
    final end = _levelTool.end;
    if (scene == null || start == null || end == null) {
      return;
    }

    final elevation = end.z;
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await _authoringCommands.createLevel(
        name: 'Level ${scene.levels.length + 1}',
        elevationMeters: elevation,
        defaultWallHeightMeters: _activeLevelDefaultWallHeight(scene),
      );
      await _applyEngineSceneResult(
        result,
        message: 'Level created at ${elevation.toStringAsFixed(2)} m.',
      );
      await _clearDraft();
      return;
    }
    final nextIndex = scene.levels.length + 1;
    final nextScene = RenderSceneEditor.createLevel(
      scene: scene,
      name: 'Level $nextIndex',
      elevationMeters: elevation,
      defaultWallHeightMeters: _activeLevelDefaultWallHeight(scene),
    );
    await _applySceneChange(
      nextScene,
      message: 'Level created at ${elevation.toStringAsFixed(2)} m.',
    );
    await _clearDraft();
  }

  Future<void> _handleOpeningTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final hostWall = _resolveHostWall(scene, tappedObject);
    if (hostWall == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Click a wall to place opening.';
        _draftHostWall = null;
      });
      return;
    }

    final point = modelPoint ?? RenderSceneEditor.wallCenterPoint(hostWall);
    if (point == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Unable to resolve opening offset on this wall.';
      });
      return;
    }
    _updateOpeningDraftPreview(
      scene: scene,
      hostWall: hostWall,
      point: point,
      announce: true,
    );

    final openingDraft = _viewportController.draftOpening;
    if (openingDraft != null && openingDraft.valid) {
      await _commitOpeningDraft(scene, hostWall);
    }
  }

  Future<void> _handleMoveWallTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final selected = _selectedObject(scene);
    final wall = tappedObject?.kindKey == 'wall'
        ? tappedObject
        : (selected?.kindKey == 'wall' ? selected : null);
    if (wall == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Select a wall before moving it.';
      });
      return;
    }
    if (_draftMoveTarget?.elementId != wall.elementId) {
      // Selection is visual state; it must not delay the first move sample on
      // a tablet. The draft is initialized below before the Inspector update
      // is allowed to rebuild the scene.
      unawaited(_selectObject(wall));
    }
    if (_moveAnchorPoint == null) {
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      final anchor = modelPoint ?? RenderSceneEditor.wallCenterPoint(wall);
      if (start == null || end == null || anchor == null) {
        return;
      }
      final startDistance = anchor.distanceTo(start);
      final endDistance = anchor.distanceTo(end);
      var moveMode = WallMoveMode.translate;
      final wallLength = start.distanceTo(end);
      // A fixed 45 cm hit radius made the middle of short walls look like an
      // endpoint. Keep the handles touchable, but make their hit area scale
      // with the wall so a body drag always translates the whole wall.
      final handleTolerance = math.min(
        0.32,
        math.max(0.12, wallLength * 0.22),
      );
      if (startDistance <= handleTolerance && startDistance <= endDistance) {
        moveMode = WallMoveMode.startHandle;
      } else if (endDistance <= handleTolerance &&
          endDistance < startDistance) {
        moveMode = WallMoveMode.endHandle;
      }
      _updateViewportState(() {
        _draftMoveTarget = wall;
        _moveAnchorPoint = moveMode == WallMoveMode.translate
            ? anchor
            : (moveMode == WallMoveMode.startHandle ? start : end);
        _moveWallOriginalStart = start;
        _moveWallOriginalEnd = end;
        _wallMoveMode = moveMode;
        _draftWallStart = start;
        _draftWallEnd = end;
        _editStatusMessage = moveMode == WallMoveMode.translate
            ? 'Wall move preview started. Drag the wall.'
            : 'Wall endpoint preview started. Drag the endpoint.';
      });
      _viewportController.setWallDraft(start, end);
      return;
    }

    if (_draftCanConfirm) {
      await _confirmDraft();
    }
  }

  void _handleMoveLevelStart(
    RenderScene scene,
    RenderScenePoint? modelPoint, {
    RenderSceneLevel? pickedLevel,
  }) {
    if (!_projectionMode.isElevation) {
      _updateViewportState(() {
        _editStatusMessage = 'Move level works only in an elevation view.';
      });
      return;
    }
    final level = pickedLevel ??
        _pickLevelAtElevation(scene, modelPoint) ??
        _activeLevel(scene);
    if (level == null || modelPoint == null) {
      return;
    }
    if (pickedLevel == null &&
        (modelPoint.z - level.elevationMeters).abs() > 0.8) {
      _updateViewportState(() {
        _editStatusMessage =
            'Level line yaqinidan ushlab suring. Active level: ${level.name}.';
      });
      return;
    }
    final preview =
        _levelDraftEndpointsForElevation(scene, level.elevationMeters);
    _updateViewportState(() {
      _draftMoveLevelId = level.levelId;
      _moveLevelOriginalElevation = level.elevationMeters;
      _moveAnchorPoint = modelPoint;
      _draftWallStart = preview.$1;
      _draftWallEnd = preview.$2;
      _editStatusMessage =
          '${level.name} move preview started (${level.elevationMeters.toStringAsFixed(2)} m).';
    });
    _viewportController.setWallDraft(preview.$1, preview.$2);
  }

  (RenderScenePoint, RenderScenePoint) _levelDraftEndpointsForElevation(
    RenderScene scene,
    double elevation,
  ) {
    final bounds = scene.bounds;
    final descriptor = _projectionMode.planarDescriptor;
    if (descriptor == null || !descriptor.isElevation) {
      return (
        RenderScenePoint(
            x: bounds.min.x - 1.0, y: bounds.center.y, z: elevation),
        RenderScenePoint(
            x: bounds.max.x + 1.0, y: bounds.center.y, z: elevation),
      );
    }
    final horizontalMin =
        descriptor.minAxis(bounds, descriptor.horizontalAxis) - 1.0;
    final horizontalMax =
        descriptor.maxAxis(bounds, descriptor.horizontalAxis) + 1.0;
    return (
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMin,
        verticalValue: elevation,
      ),
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMax,
        verticalValue: elevation,
      ),
    );
  }
}
