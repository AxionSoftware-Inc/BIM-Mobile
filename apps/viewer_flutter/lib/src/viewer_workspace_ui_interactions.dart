// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

/// View range, section and pointer interaction bridge.
extension _ViewerWorkspaceInteractions on _ViewerHomePageState {
  Future<void> _setPlanViewRangeMeters(double value) async {
    if (!value.isFinite || value <= 0.05) {
      return;
    }
    _updateViewportState(() {
      _planViewRangeMeters = value.clamp(0.1, 20.0);
      _statusMessage =
          'Plan view range: ${_projectUnitSettings.formatLength(_planViewRangeMeters)}';
    });
    final scene = _scene;
    if (scene != null && _projectionMode == RenderSceneProjectionMode.topDown) {
      await _viewportController.updateRenderScene(_sceneForViewport(scene));
      await _viewportController.setVisibleKinds(_visibleKinds);
    }
  }

  Future<void> _showSectionDialog() {
    if (_workspaceBusy || !mounted) return Future<void>.value();
    return _runViewNavigation(_showSectionDialogNow);
  }

  Future<void> _showSectionDialogNow() async {
    final scene = _scene;
    if (_engineRepository == null ||
        scene == null ||
        !_engineBackedMode ||
        !mounted) {
      return;
    }
    // Section placement is a plan-view command: create the default section
    // through the building centre without exposing coordinate fields. The
    // Project Browser still owns Section A/B, while this command gives the
    // same predictable horizontal cut as Revit's first section marker.
    final margin =
        math.max(scene.bounds.width, scene.bounds.depth) * 0.08 + 0.5;
    final section = RenderSceneSection(
      name: 'Section',
      start: RenderScenePoint(
        x: scene.bounds.min.x - margin,
        y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
        z: 0,
      ),
      end: RenderScenePoint(
        x: scene.bounds.max.x + margin,
        y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
        z: 0,
      ),
    );
    _updateViewportState(() {
      _isBusy = true;
      _statusMessage = 'Creating section...';
      _loadError = null;
    });
    try {
      final result = await _sceneViews.setFullSceneRenderScope(true);
      await _activateSectionView(section, result);
    } catch (error) {
      if (mounted) {
        _updateViewportState(() {
          _isBusy = false;
          _loadError = error.toString();
          _statusMessage = 'Section failed.';
        });
      }
    }
    return;
  }

  Future<void> _handleSceneSecondaryTap(RenderSceneTapDetails details) async {
    if (!mounted) {
      return;
    }

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    final pickedLevel = details.pickedLevel;
    final tappedObject = details.pickedObject;
    if (pickedLevel != null && _projectionMode.isElevation) {
      await _selectLevel(pickedLevel);
      if (!mounted) {
        return;
      }
      final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(
            details.globalPosition.dx,
            details.globalPosition.dy,
            1,
            1,
          ),
          Offset.zero & (overlay?.size ?? const Size(1, 1)),
        ),
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'edit_level',
            child: Text('Edit level'),
          ),
        ],
      );
      if (!mounted) {
        return;
      }
      if (action == 'edit_level') {
        await _showEditLevelDialog(pickedLevel);
      }
      return;
    }
    if (tappedObject != null) {
      await _selectObject(tappedObject);
    }
    if (tappedObject == null && _projectionMode.isElevation) {
      final scene = _scene;
      final pickedLevel = scene == null
          ? null
          : _pickLevelAtElevation(scene, details.modelPoint);
      if (pickedLevel != null) {
        await _setActiveLevel(pickedLevel.levelId);
        if (!mounted) {
          return;
        }
        final action = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(
              details.globalPosition.dx,
              details.globalPosition.dy,
              1,
              1,
            ),
            Offset.zero & (overlay?.size ?? const Size(1, 1)),
          ),
          items: const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'edit_level',
              child: Text('Edit level'),
            ),
          ],
        );
        if (!mounted) {
          return;
        }
        if (action == 'edit_level') {
          await _showEditLevelDialog(pickedLevel);
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }

    final selected = tappedObject ?? _selectedObject(_scene);
    if (selected == null || overlay == null) {
      return;
    }

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete'),
        ),
      ],
    );

    if (!mounted) {
      return;
    }
    if (action == 'delete') {
      await _deleteSelectedObject();
    }
  }

  void _handleSceneMultiTouchStart() {
    if (!_isSurfaceAuthoring) {
      return;
    }

    _surfaceBoundaryMultiTouch = true;
    final lastPoint = _draftSurfacePoints.lastOrNull;
    _updateViewportState(() {
      // Keep only committed corners. The live cursor belongs to the
      // one-finger authoring gesture and must not be committed by a pinch.
      _draftSurfaceEnd = lastPoint;
      _editStatusMessage = 'Two-finger pan/zoom: boundary drawing paused.';
    });
    _syncSurfaceDraftPreview();
  }

  void _handleSceneDragStart(RenderSceneTapDetails details) {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        final level = details.pickedLevel;
        if (level != null) {
          unawaited(_selectLevel(level));
          _handleMoveLevelStart(
            scene,
            details.modelPoint,
            pickedLevel: level,
          );
          return;
        }
        if (details.pickedObject != null) {
          final object = details.pickedObject!;
          if (object.kindKey == 'wall') {
            unawaited(_handleMoveWallTap(scene, object, details.modelPoint));
          } else if (object.kindKey == 'door' || object.kindKey == 'window') {
            unawaited(_handleMoveOpeningTap(scene, object, details.modelPoint));
          } else if (object.kindKey == 'column' || object.kindKey == 'proxy') {
            _handleMoveElementStart(scene, object, details.modelPoint);
          } else {
            unawaited(_selectObject(object));
          }
        }
        return;
      case RenderSceneInteractionMode.addWall:
        final point = details.modelPoint;
        if (point == null) return;
        if (_wallTool.drawMode == WallDrawMode.arc) {
          final snapped = _wallDraftPoint(
            rawPoint: point,
            referenceStart: _wallTool.arcEnd ?? _wallTool.arcStart,
          );
          final hadFirstPoint = _wallTool.hasArcFirstPoint;
          final hadSecondPoint = _wallTool.hasArcSecondPoint;
          if (!hadFirstPoint) {
            _wallTool.beginArcFirstAdjustment(snapped);
          } else if (!hadSecondPoint) {
            _wallTool.beginArcSecondAdjustment(snapped);
          } else {
            _wallTool.beginArcControlAdjustment(snapped);
          }
          _syncWallArcDraft();
          _updateViewportState(() {
            _editStatusMessage = !hadFirstPoint
                ? 'Drag to set the first point.'
                : !hadSecondPoint
                    ? 'Drag to set the second point. Release to lock it; the midpoint handle is ready next.'
                    : 'Drag the midpoint handle to set the radius, then release.';
          });
          return;
        }
        final snapped = _wallDraftPoint(
          rawPoint: point,
          referenceStart: _wallTool.start,
        );
        if (!_wallTool.hasStart) {
          _wallTool.begin(snapped);
        } else {
          _wallTool.preview(snapped);
        }
        _viewportController.setWallDraft(_wallTool.start, _wallTool.end);
        _updateViewportState(() {
          _editStatusMessage = _wallTool.hasSegment
              ? _wallTool.drawMode == WallDrawMode.rectangle
                  ? 'Release to create the four walls of this rectangle.'
                  : 'Release to create this wall.'
              : _wallTool.drawMode == WallDrawMode.rectangle
                  ? 'Drag to the opposite corner, or tap it.'
                  : 'Drag to draw, or tap the next wall corner.';
        });
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final point = details.modelPoint;
        final hostWall = details.pickedObject?.kindKey == 'wall'
            ? details.pickedObject
            : (point == null ? null : _findWallNearPlanPoint(scene, point));
        if (hostWall == null || point == null) {
          _updateViewportState(() {
            _editStatusMessage = 'Long-press a wall to place an opening.';
            _draftHostWall = null;
            _openingGestureActive = false;
          });
          return;
        }
        // Lock the host before any move sample is processed.  A touch can
        // briefly hit another wall at a dense corner or through a wall cut,
        // but moving a door/window must remain an offset along the wall that
        // received the initial contact.
        _updateViewportState(() {
          _openingGestureActive = true;
        });
        _updateOpeningDraftPreview(
          scene: scene,
          hostWall: hostWall,
          point: point,
          announce: true,
        );
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        _surfaceBoundaryMultiTouch = false;
        final point = details.modelPoint;
        if (point == null) return;
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          _beginSurfaceBoundarySegment(point);
          return;
        }
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) return;
        final snapped = _snapDraftToGrid ? _snapPoint(point) : point;
        _updateViewportState(() {
          if (_draftSurfaceStart == null) {
            _draftSurfaceStart = snapped;
            _draftSurfaceEnd = snapped;
            _draftSurfacePoints
              ..clear()
              ..add(snapped);
          } else {
            _draftSurfaceEnd = snapped;
            if (_draftSurfacePoints.length == 1) {
              _draftSurfacePoints.add(snapped);
            } else {
              _draftSurfacePoints[1] = snapped;
            }
          }
          _editStatusMessage = 'Drag and release to create rectangle.';
        });
        _syncSurfaceDraftPreview();
        return;
      case RenderSceneInteractionMode.addStair:
        final point = details.modelPoint;
        if (point == null) return;
        final snapped = _draftLinePoint(
          rawPoint: point,
          referenceStart: _stairTool.start,
        );
        if (!_stairTool.hasStart) {
          _stairTool.begin(snapped);
        } else {
          _stairTool.preview(snapped);
        }
        _viewportController.setWallDraft(_stairTool.start, _stairTool.end);
        return;
      case RenderSceneInteractionMode.moveWall:
        _handleMoveWallTap(scene, details.pickedObject, details.modelPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        _handleMoveLevelStart(
          scene,
          details.modelPoint,
          pickedLevel: details.pickedLevel,
        );
        return;
      case RenderSceneInteractionMode.moveOpening:
        _handleMoveOpeningTap(scene, details.pickedObject, details.modelPoint);
        return;
      default:
        return;
    }
  }

  void _handleSceneDragUpdate(RenderSceneTapDetails details) {
    final scene = _scene;
    final point = details.modelPoint;
    if (scene == null || point == null) {
      return;
    }
    if (details.pointerCount > 1) {
      return;
    }
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        if (_draftMoveLevelId != null) {
          _updateMoveLevelPreview(scene: scene, point: point);
        } else {
          final target = _draftMoveTarget;
          if (target?.kindKey == 'wall') {
            _updateMoveWallPreview(scene: scene, wall: target!, point: point);
          } else if (target?.kindKey == 'door' || target?.kindKey == 'window') {
            _updateMoveOpeningPreview(
                scene: scene, opening: target!, point: point);
          } else if (target?.kindKey == 'column' ||
              target?.kindKey == 'proxy') {
            _draftMoveElementPoint = point;
            final anchor = _moveAnchorPoint;
            if (anchor != null) {
              _viewportController.setObjectMoveDraft(
                RenderSceneObjectMoveDraft(
                  object: target!,
                  delta: point - anchor,
                ),
              );
            }
          }
        }
        return;
      case RenderSceneInteractionMode.moveWall:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null && target.kindKey == 'wall') {
          _updateMoveWallPreview(scene: scene, wall: target, point: point);
        }
        return;
      case RenderSceneInteractionMode.moveLevel:
        _updateMoveLevelPreview(scene: scene, point: point);
        return;
      case RenderSceneInteractionMode.moveOpening:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null &&
            (target.kindKey == 'door' || target.kindKey == 'window')) {
          _updateMoveOpeningPreview(
              scene: scene, opening: target, point: point);
        }
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        _handleSceneHover(details);
        return;
      case RenderSceneInteractionMode.addWall:
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
      case RenderSceneInteractionMode.addStair:
        if ((_interactionMode == RenderSceneInteractionMode.addFloor ||
                _interactionMode == RenderSceneInteractionMode.addCeiling ||
                _interactionMode == RenderSceneInteractionMode.addRoof) &&
            _surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          _updateSurfaceBoundarySegment(point, announce: false);
          return;
        }
        _handleSceneHover(details);
        return;
      default:
        return;
    }
  }

  Future<void> _handleSceneDragEnd(RenderSceneTapDetails details) async {
    switch (_interactionMode) {
      case RenderSceneInteractionMode.addWall:
        if (_wallTool.drawMode == WallDrawMode.arc) {
          // First and second endpoint gestures are provisional until release.
          // The third gesture is the only one that commits a curved wall.
          if (_wallTool.isArcFirstPointAdjustmentActive) {
            _wallTool.commitArcFirst();
            _syncWallArcDraft();
          } else if (_wallTool.isArcSecondPointAdjustmentActive) {
            _wallTool.commitArcSecond();
            _syncWallArcDraft();
          } else if (_wallTool.hasSegment &&
              _wallTool.isArcControlAdjustmentActive) {
            await _commitWallArc();
          }
          return;
        }
        _handleSceneHover(details);
        if (_wallTool.hasSegment) {
          if (_wallTool.drawMode == WallDrawMode.rectangle) {
            await _commitWallRectangle();
          } else {
            await _commitWallDraft(autoContinue: true);
          }
        }
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final scene = _scene;
        final hostWall = _draftHostWall;
        final draft = _viewportController.draftOpening;
        // The draft already contains the last previewed wall-local offset.
        // Do not re-pick/re-project at PointerUp: Android may deliver a
        // delayed release sample, and a fresh hit can select a neighbouring
        // wall.  Recomputing here was the source of the visible left/right
        // jump between the finger preview and the committed opening.
        _openingGestureActive = false;
        if (scene == null || hostWall == null || draft == null) return;
        if (draft.valid) {
          await _commitOpeningDraft(scene, hostWall);
        } else if (mounted) {
          _updateViewportState(() {
            _editStatusMessage = draft.message;
          });
        }
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceBoundaryMultiTouch || details.pointerCount > 1) {
          return;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          _commitSurfaceBoundarySegment(details.modelPoint);
          return;
        }
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) return;
        _handleSceneHover(details);
        if (SurfaceAuthoringGeometry.isUsableRectangle(
          _draftSurfaceStart,
          _draftSurfaceEnd,
        )) {
          await _confirmDraft();
        }
        return;
      case RenderSceneInteractionMode.addStair:
        // Stair paths are tap-to-place points, not one continuous drag.  The
        // viewport normally routes this mode through onSceneTap; keep this
        // guard for native/fallback gesture implementations that still emit
        // a drag end so an incomplete L/U path can never be committed.
        if (_stairTool.hasCompleteLayout) {
          await _commitStairDraft();
        } else if (mounted) {
          _updateViewportState(() {
            _editStatusMessage =
                'Stair path is incomplete: add ${_stairTool.requiredPointCount - _stairTool.pathPoints.length} more point(s).';
          });
        }
        return;
      case RenderSceneInteractionMode.select:
        if (_draftMoveLevelId != null && _draftWallEnd != null) {
          final repository = _engineRepository;
          final levelId = _draftMoveLevelId!;
          final elevation = _draftWallEnd!.z;
          if (_engineBackedMode && repository != null) {
            final result = await _authoringCommands.moveLevelElevation(
              levelId: levelId,
              elevationMeters: elevation,
            );
            await _applyEngineSceneResult(
              result,
              message:
                  'Level elevation updated to ${_projectUnitSettings.formatLength(elevation)}.',
            );
          }
          await _clearDraft();
        } else if (_draftMoveTarget?.kindKey == 'wall' &&
            _draftWallArcGeometry != null &&
            _draftMoveTarget?.elementId != null) {
          final wall = _draftMoveTarget!;
          final geometry = _draftWallArcGeometry!;
          final repository = _engineRepository;
          if (_engineBackedMode && repository != null) {
            final result = await _authoringCommands.setCurvedWallGeometry(
              wallId: wall.elementId!,
              geometry: geometry,
            );
            await _applyEngineSceneResult(
              result,
              message: 'Curved wall updated.',
            );
          } else if (_scene != null) {
            final nextScene = RenderSceneEditor.setCurvedWallGeometry(
              scene: _scene!,
              wall: wall,
              geometry: geometry,
            );
            await _applySceneChange(
              nextScene,
              message: 'Curved wall updated.',
              authoritative: true,
            );
          }
          await _clearDraft();
        } else if (_draftMoveTarget?.kindKey == 'wall' &&
            _draftWallStart != null &&
            _draftWallEnd != null) {
          final wall = _draftMoveTarget!;
          final repository = _engineRepository;
          if (_engineBackedMode &&
              repository != null &&
              wall.elementId != null) {
            final result = await _setWallAxisKeepingJoins(
              wall: wall,
              start: _draftWallStart!,
              end: _draftWallEnd!,
            );
            await _applyEngineSceneResult(result, message: 'Wall moved.');
          }
          await _clearDraft();
        } else if ((_draftMoveTarget?.kindKey == 'door' ||
                _draftMoveTarget?.kindKey == 'window') &&
            _draftMoveTarget?.elementId != null) {
          final opening = _draftMoveTarget!;
          final repository = _engineRepository;
          if (_engineBackedMode && repository != null) {
            final result = await _authoringCommands.updateOpening(
              object: opening,
              offsetMeters: _draftOpeningOffsetMeters,
              widthMeters: _draftOpeningWidthMeters,
              heightMeters: _draftOpeningHeightMeters,
              sillHeightMeters: _draftOpeningSillHeightMeters,
            );
            await _applyEngineSceneResult(
              result,
              message: '${prettySceneKind(opening.kind)} moved.',
            );
          }
          await _clearDraft();
        } else if ((_draftMoveTarget?.kindKey == 'column' ||
                _draftMoveTarget?.kindKey == 'proxy') &&
            _draftMoveTarget?.elementId != null &&
            _moveAnchorPoint != null &&
            _draftMoveElementPoint != null) {
          final target = _draftMoveTarget!;
          final delta = _draftMoveElementPoint! - _moveAnchorPoint!;
          if (_engineBackedMode &&
              _engineRepository != null &&
              (delta.x.abs() > 1e-6 || delta.y.abs() > 1e-6)) {
            final result = await _authoringCommands.moveElement(
              elementId: target.elementId!,
              deltaX: delta.x,
              deltaY: delta.y,
            );
            await _applyEngineSceneResult(
              result,
              message: '${prettySceneKind(target.kind)} moved.',
            );
          }
          await _clearDraft();
        }
        return;
      case RenderSceneInteractionMode.moveWall:
      case RenderSceneInteractionMode.moveOpening:
      case RenderSceneInteractionMode.moveLevel:
        if (_draftCanConfirm) {
          await _confirmDraft();
        }
        return;
      default:
        return;
    }
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEE2E2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Color(0xFF991B1B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}
