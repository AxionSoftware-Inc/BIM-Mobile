part of 'viewer_app.dart';

/// Surface drafting, snapping and footprint handling.
extension _ViewerViewportSurfaceEditing on _ViewerHomePageState {
  void _syncSurfaceDraftPreview() {
    final kind = _surfaceKindKey();
    final points = SurfaceAuthoringGeometry.previewPoints(
      mode: _surfaceDrawMode,
      start: _draftSurfaceStart,
      end: _draftSurfaceEnd,
      points: _draftSurfacePoints,
    );
    if (points.isNotEmpty) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: kind,
          points: points,
          closed: SurfaceAuthoringGeometry.previewIsClosed(
            mode: _surfaceDrawMode,
            points: points,
          ),
        ),
      );
      return;
    }
    _viewportController.setSurfaceDraft(null);
  }

  List<RenderScenePoint> _surfaceProfilePointsForCommit() {
    return SurfaceAuthoringGeometry.profilePoints(
      mode: _surfaceDrawMode,
      start: _draftSurfaceStart,
      end: _draftSurfaceEnd,
      points: _draftSurfacePoints,
    );
  }

  RenderSceneObject? _resolveHostWall(
    RenderScene scene,
    RenderSceneObject? tappedObject,
  ) {
    if (tappedObject != null && tappedObject.kindKey == 'wall') {
      return tappedObject;
    }

    final selected = _selectedObject(scene);
    if (selected != null && selected.kindKey == 'wall') {
      return selected;
    }

    return _draftHostWall;
  }

  RenderScenePoint _snapPoint(RenderScenePoint point, [double step = 0.25]) {
    return WallAuthoringGeometry.snapPoint(
      point,
      enabled: _snapDraftToGrid,
      stepMeters: step,
    );
  }

  RenderScenePoint _draftLinePoint({
    required RenderScenePoint rawPoint,
    required RenderScenePoint? referenceStart,
    bool useOrthogonalSnap = true,
    int? excludeWallId,
  }) {
    return WallAuthoringGeometry.resolveLineEndpoint(
      rawPoint: rawPoint,
      referenceStart: referenceStart,
      scene: _scene,
      activeLevelId: _activeLevelId,
      snapToGrid: _snapDraftToGrid,
      projectionMode: _projectionMode,
      useOrthogonalSnap: useOrthogonalSnap,
      wallOrthogonalSnap:
          _interactionMode == RenderSceneInteractionMode.addWall ||
              _interactionMode == RenderSceneInteractionMode.moveWall,
      excludeWallId: excludeWallId,
    );
  }

  double _snapDouble(double value, double step) {
    return WallAuthoringGeometry.snapDouble(
      value,
      enabled: _snapDraftToGrid,
      step: step,
    );
  }

  bool get _draftCanConfirm {
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return false;
      case RenderSceneInteractionMode.addWall:
        return _wallTool.hasStart;
      case RenderSceneInteractionMode.addLevel:
        return _levelTool.hasDraft;
      case RenderSceneInteractionMode.moveLevel:
        return _draftMoveLevelId != null &&
            _draftWallStart != null &&
            _draftWallEnd != null;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
      case RenderSceneInteractionMode.moveOpening:
        final openingDraft = _viewportController.draftOpening;
        final selectedWall = _selectedObject(_scene)?.kindKey == 'wall';
        final selectedOpening = _selectedObject(_scene)?.kindKey == 'door' ||
            _selectedObject(_scene)?.kindKey == 'window';
        return openingDraft != null &&
            openingDraft.valid &&
            (_draftHostWall != null || selectedWall || selectedOpening);
      case RenderSceneInteractionMode.moveWall:
        final start = _draftWallStart;
        final end = _draftWallEnd;
        final target = _draftMoveTarget ?? _selectedObject(_scene);
        return target?.kindKey == 'wall' && start != null && end != null;
      case RenderSceneInteractionMode.trimExtend:
        return _trimTool.isReady;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
          final draft = _viewportController.draftSurface;
          return _draftSurfaceWallIds.length >= 3 &&
              draft != null &&
              draft.closed &&
              draft.points.length >= 3;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          return _draftSurfacePoints.length >= 3;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
          return false;
        }
        if (_draftSurfaceWallIds.length >= 3) {
          return true;
        }
        final start = _draftSurfaceStart;
        final end = _draftSurfaceEnd;
        if (start == null || end == null) {
          return false;
        }
        return SurfaceAuthoringGeometry.isUsableRectangle(start, end);
      case RenderSceneInteractionMode.addStair:
        return _stairTool.hasRun;
    }
  }

  Future<void> _confirmDraft() async {
    final scene = _scene;
    if (scene == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return;
      case RenderSceneInteractionMode.addWall:
        await _clearDraft();
        await _setInteractionMode(RenderSceneInteractionMode.select);
        _updateViewportState(() {
          _editStatusMessage = 'Wall chizish tugatildi.';
        });
        return;
      case RenderSceneInteractionMode.addLevel:
        await _commitLevelDraft();
        return;
      case RenderSceneInteractionMode.addStair:
        await _commitStairDraft();
        return;
      case RenderSceneInteractionMode.moveLevel:
        final sceneLevel = _scene;
        final levelId = _draftMoveLevelId;
        final end = _draftWallEnd;
        if (sceneLevel == null || levelId == null || end == null) {
          _updateViewportState(() {
            _editStatusMessage = 'Move level preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null) {
          final result = await _authoringCommands.moveLevelElevation(
            levelId: levelId,
            elevationMeters: end.z,
          );
          await _applyEngineSceneResult(
            result,
            message:
                'Level elevation updated to ${end.z.toStringAsFixed(2)} m.',
          );
        } else {
          final nextScene = RenderSceneEditor.setLevelElevation(
            scene: sceneLevel,
            levelId: levelId,
            elevationMeters: end.z,
          );
          await _applySceneChange(
            nextScene,
            message:
                'Level elevation updated to ${end.z.toStringAsFixed(2)} m.',
          );
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final hostWall = _draftHostWall ?? _selectedObject(scene);
        if (hostWall == null || hostWall.kindKey != 'wall') {
          _updateViewportState(() {
            _editStatusMessage = 'Select a wall first.';
          });
          return;
        }
        await _commitOpeningDraft(scene, hostWall);
        return;
      case RenderSceneInteractionMode.moveWall:
        final wall = _draftMoveTarget ?? _selectedObject(scene);
        final start = _draftWallStart;
        final end = _draftWallEnd;
        if (wall == null ||
            wall.kindKey != 'wall' ||
            start == null ||
            end == null) {
          _updateViewportState(() {
            _editStatusMessage = 'Move wall preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null && wall.elementId != null) {
          final result = await _setWallAxisKeepingJoins(
            wall: wall,
            start: start,
            end: end,
          );
          await _applyEngineSceneResult(result, message: 'Wall moved.');
        } else {
          final nextScene = RenderSceneEditor.setWallAxis(
            scene: scene,
            wall: wall,
            start: start,
            end: end,
          );
          await _applySceneChange(nextScene, message: 'Wall moved.');
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.moveOpening:
        final opening = _draftMoveTarget ?? _selectedObject(scene);
        if (opening == null ||
            (opening.kindKey != 'door' && opening.kindKey != 'window')) {
          _updateViewportState(() {
            _editStatusMessage = 'Move opening preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode &&
            repository != null &&
            opening.elementId != null) {
          await _authoringCommands.moveOpening(
            openingId: opening.elementId!,
            offsetMeters: _draftOpeningOffsetMeters,
          );
          final result = await _authoringCommands.resizeHostedOpening(
            openingId: opening.elementId!,
            kind: opening.kindKey,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            sillHeightMeters: _draftOpeningSillHeightMeters,
          );
          await _applyEngineSceneResult(
            result,
            message: '${prettySceneKind(opening.kind)} moved.',
          );
        } else {
          final nextScene = RenderSceneEditor.moveOpening(
            scene: scene,
            opening: opening,
            offsetMeters: _draftOpeningOffsetMeters,
          );
          await _applySceneChange(
            nextScene,
            message: '${prettySceneKind(opening.kind)} moved.',
          );
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.trimExtend:
        await _commitTrimExtend();
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null && _activeLevelId != null) {
          final targetKind = _surfaceTargetKind();
          final assemblyId =
              _interactionMode == RenderSceneInteractionMode.addRoof
                  ? 0
                  : _authoringCommands.defaultAssemblyId(
                      _interactionMode == RenderSceneInteractionMode.addFloor
                          ? 'Floor'
                          : 'Ceiling',
                    );
          // assemblyId=0 is valid for a new blank project: the engine then
          // creates a plain floor/ceiling with the requested thickness.
          if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
            _updateViewportState(() {
              _editStatusMessage =
                  'Tap a room to create ${_surfaceKindLabel()} automatically.';
            });
            return;
          }
          final pickedWallProfile = _viewportController.draftSurface;
          final keepSemanticRoofWalls =
              _surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
                  _interactionMode == RenderSceneInteractionMode.addRoof;
          final resolvedPickPolygon =
              _surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
                      !keepSemanticRoofWalls
                  ? pickedWallProfile?.points ?? const <RenderScenePoint>[]
                  : const <RenderScenePoint>[];
          if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
              !keepSemanticRoofWalls &&
              resolvedPickPolygon.length < 3) {
            _updateViewportState(() {
              _editStatusMessage =
                  'Picked wall loop yopilmagan. Barcha devorlar uzluksiz ko‘k kontur hosil qilishi kerak.';
            });
            return;
          }
          try {
            final result = await _authoringCommands.createProfile(
              targetKind: targetKind,
              draftMode: keepSemanticRoofWalls
                  ? 2
                  : _surfaceDrawMode == RenderSceneSurfaceDrawMode.rectangle
                      ? 1
                      : 0,
              levelId: _activeLevelId!,
              points: resolvedPickPolygon.isNotEmpty
                  ? resolvedPickPolygon
                  : _surfaceProfilePointsForCommit(),
              wallIds: keepSemanticRoofWalls
                  ? _draftSurfaceWallIds.toList(growable: false)
                  : const <int>[],
              closed: true,
              thicknessMeters: _draftSurfaceThicknessMeters,
              heightMeters: _draftSurfaceHeightMeters,
              verticalOffsetMeters: _interactionMode ==
                      RenderSceneInteractionMode.addFloor
                  ? _draftFloorTopElevationMeters
                  : _interactionMode == RenderSceneInteractionMode.addCeiling
                      ? _draftCeilingHeightOffsetMeters
                      : 0.0,
              assemblyId: assemblyId ?? 0,
            );
            final createdId = _authoringCommands.lastCreatedElementId;
            final created =
                createdId == null ? null : result.scene?.objectById(createdId);
            if (created == null) {
              throw StateError(
                  'Engine ${_surfaceKindLabel()} yaratganini tasdiqlamadi.');
            }
            await _applyEngineSceneResult(
              result,
              message: '${_surfaceKindLabel()} #$createdId created.',
            );
            await _viewportController.selectElement(createdId.toString());
            await _viewportController.highlightElement(createdId.toString());
            await _clearDraft();
          } catch (error) {
            if (!mounted) return;
            _updateViewportState(() {
              _editStatusMessage = '${_surfaceKindLabel()} yaratilmadi: $error';
              _statusMessage = _editStatusMessage;
            });
          }
          return;
        }
        if (_interactionMode == RenderSceneInteractionMode.addRoof) {
          _updateViewportState(() {
            _editStatusMessage =
                'Roof creation hozircha engine-backed mode talab qiladi.';
          });
          return;
        }
        RenderScene nextScene;
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
          final polygon = SurfaceAuthoringGeometry.wallBoundaryPolygon(
            scene,
            _draftSurfaceWallIds,
          );
          if (polygon == null || polygon.length < 3) {
            _updateViewportState(() {
              _editStatusMessage =
                  'Pick all connected boundary walls until the blue outline closes. Bounding rectangle ishlatilmaydi.';
            });
            return;
          }
          nextScene = _interactionMode == RenderSceneInteractionMode.addFloor
              ? RenderSceneEditor.addFloorFromPolygon(
                  scene: scene,
                  polygon: polygon,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  topElevationMeters: _draftFloorTopElevationMeters,
                  levelId: _activeLevelId,
                )
              : RenderSceneEditor.addCeilingFromPolygon(
                  scene: scene,
                  polygon: polygon,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftCeilingHeightOffsetMeters,
                  levelId: _activeLevelId,
                );
          if (identical(nextScene, scene)) {
            _updateViewportState(() {
              _editStatusMessage = 'Closed wall loop topilmadi.';
            });
            return;
          }
        } else {
          final start = _draftSurfaceStart;
          final end = _draftSurfaceEnd;
          if (start == null || end == null) {
            _updateViewportState(() {
              _editStatusMessage =
                  'Draw a rectangle first, or multi-select walls.';
            });
            return;
          }
          final bounds = SurfaceAuthoringGeometry.rectangleBounds(start, end);
          if (bounds == null) {
            _updateViewportState(() {
              _editStatusMessage = 'Surface rectangle juda kichik.';
            });
            return;
          }
          nextScene = _interactionMode == RenderSceneInteractionMode.addFloor
              ? RenderSceneEditor.addFloorFromBounds(
                  scene: scene,
                  bounds: bounds,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  topElevationMeters: _draftFloorTopElevationMeters,
                  levelId: _activeLevelId,
                )
              : RenderSceneEditor.addCeilingFromBounds(
                  scene: scene,
                  bounds: bounds,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftCeilingHeightOffsetMeters,
                  levelId: _activeLevelId,
                );
        }
        await _applySceneChange(
          nextScene,
          message: '${_surfaceKindLabel()} created.',
        );
        final created =
            nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
        if (created != null) {
          await _viewportController
              .selectElement(created.elementId?.toString());
          await _viewportController
              .highlightElement(created.elementId?.toString());
        }
        await _clearDraft();
        return;
    }
  }

  Future<void> _cancelDraft() async {
    await _clearDraft();
    _updateViewportState(() {
      _editStatusMessage = 'Draft canceled.';
      _statusMessage = _editStatusMessage;
    });
  }

  Future<void> _commitOpeningDraft(
    RenderScene scene,
    RenderSceneObject hostWall,
  ) async {
    final openingDraft = _viewportController.draftOpening;
    if (openingDraft != null && !openingDraft.valid) {
      _updateViewportState(() {
        _editStatusMessage = openingDraft.message;
      });
      return;
    }

    final offset = _draftOpeningOffsetMeters;
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null && hostWall.elementId != null) {
      final result = _interactionMode == RenderSceneInteractionMode.addDoor
          ? await _authoringCommands.createDoor(
              name: 'Door',
              hostWallId: hostWall.elementId!,
              offsetMeters: offset,
              widthMeters: _draftOpeningWidthMeters,
              heightMeters: _draftOpeningHeightMeters,
            )
          : await _authoringCommands.createWindow(
              name: 'Window',
              hostWallId: hostWall.elementId!,
              offsetMeters: offset,
              widthMeters: _draftOpeningWidthMeters,
              heightMeters: _draftOpeningHeightMeters,
              sillHeightMeters: _draftOpeningSillHeightMeters,
            );
      await _applyEngineSceneResult(
        result,
        message:
            '${_interactionMode == RenderSceneInteractionMode.addDoor ? 'Door' : 'Window'} created.',
      );
      await _clearDraft();
      return;
    }
    final nextScene = _interactionMode == RenderSceneInteractionMode.addDoor
        ? RenderSceneEditor.addDoor(
            scene: scene,
            hostWall: hostWall,
            offsetMeters: offset,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            levelId: hostWall.levelId ?? _activeLevelId,
          )
        : RenderSceneEditor.addWindow(
            scene: scene,
            hostWall: hostWall,
            offsetMeters: offset,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            sillHeightMeters: _draftOpeningSillHeightMeters,
            levelId: hostWall.levelId ?? _activeLevelId,
          );
    await _applySceneChange(
      nextScene,
      message:
          '${_interactionMode == RenderSceneInteractionMode.addDoor ? 'Door' : 'Window'} created.',
    );
    final created =
        nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
    if (created != null) {
      await _viewportController.selectElement(created.elementId?.toString());
      await _viewportController.highlightElement(created.elementId?.toString());
    }
    await _clearDraft();
  }

  void _syncOpeningDraft() {
    final hostWall = _draftHostWall;
    if (hostWall == null) {
      _viewportController.setOpeningDraft(null);
      return;
    }

    final offset = _draftOpeningOffsetMeters;
    final valid = OpeningAuthoringGeometry.isValid(
      hostWall: hostWall,
      offsetMeters: offset,
      widthMeters: _draftOpeningWidthMeters,
    );
    final kind = _interactionMode == RenderSceneInteractionMode.addDoor
        ? 'Door'
        : 'Window';

    _viewportController.setOpeningDraft(
      RenderSceneOpeningDraft(
        kind: kind,
        hostWallId: hostWall.elementId,
        offsetMeters: offset,
        widthMeters: _draftOpeningWidthMeters,
        heightMeters: _draftOpeningHeightMeters,
        sillHeightMeters: _draftOpeningSillHeightMeters,
        valid: valid,
        message: valid
            ? 'Ready to create $kind.'
            : 'Opening overlaps wall edge or is too wide.',
      ),
    );
  }

  void _syncSurfaceDraftFromWalls(RenderScene scene) {
    // Tablet touch authoring can leave a small endpoint gap even when the
    // wall faces visibly meet. Try the precise topology first, then a
    // bounded architectural tolerance so Finish is not disabled for a room
    // whose walls were drawn with a finger. The fallback still requires all
    // picked segments to form one closed loop; it cannot create a bounding
    // rectangle from an incomplete selection.
    final polygon = SurfaceAuthoringGeometry.wallBoundaryPolygon(
          scene,
          _draftSurfaceWallIds,
          toleranceMeters: 0.45,
        ) ??
        SurfaceAuthoringGeometry.wallBoundaryPolygon(
          scene,
          _draftSurfaceWallIds,
          toleranceMeters: 1.5,
        );
    if (polygon != null && polygon.length >= 3) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: _surfaceKindKey(),
          points: polygon,
          closed: true,
        ),
      );
      return;
    }
    // Pick Walls must never fall back to the union bounding rectangle. A
    // two-wall partial selection is not a room footprint and would silently
    // create the wrong floor for L-, U- or angled plans.
    _draftSurfaceStart = null;
    _draftSurfaceEnd = null;
    _viewportController.setSurfaceDraft(null);
  }
}
