part of 'viewer_app.dart';

/// Wall, opening and trim/extend editing.
extension _ViewerViewportWallEditing on _ViewerHomePageState {
  void _updateMoveLevelPreview({
    required RenderScene scene,
    required RenderScenePoint point,
  }) {
    final levelId = _draftMoveLevelId;
    final originalElevation = _moveLevelOriginalElevation;
    if (levelId == null || originalElevation == null) {
      return;
    }
    final nextElevation = _snapDouble(point.z, 0.1);
    final preview = _levelDraftEndpointsForElevation(scene, nextElevation);
    _updateViewportState(() {
      _draftWallStart = preview.$1;
      _draftWallEnd = preview.$2;
      _editStatusMessage =
          'Level move preview: ${nextElevation.toStringAsFixed(2)} m';
    });
    _viewportController.setWallDraft(preview.$1, preview.$2);
  }

  Future<void> _handleMoveOpeningTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final selected = _selectedObject(scene);
    final opening = (tappedObject != null &&
            (tappedObject.kindKey == 'door' ||
                tappedObject.kindKey == 'window'))
        ? tappedObject
        : ((selected != null &&
                (selected.kindKey == 'door' || selected.kindKey == 'window'))
            ? selected
            : null);
    if (opening == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Move opening uchun door yoki window tanlang.';
      });
      return;
    }
    if (_draftMoveTarget?.elementId != opening.elementId) {
      await _selectObject(opening);
    }
    final hostWallId = _metadataInt(opening, 'host_wall_id');
    final hostWall = hostWallId == null ? null : scene.objectById(hostWallId);
    if (hostWall == null || hostWall.kindKey != 'wall') {
      _updateViewportState(() {
        _editStatusMessage = 'Opening host wall topilmadi.';
      });
      return;
    }

    if (_moveAnchorPoint == null) {
      _primeOpeningDraftFromObject(opening);
      final anchor = modelPoint ??
          RenderSceneEditor.openingCenterPoint(
            hostWall: hostWall,
            offsetMeters: _draftOpeningOffsetMeters,
          );
      if (anchor == null) {
        return;
      }
      _updateViewportState(() {
        _draftMoveTarget = opening;
        _draftHostWall = hostWall;
        _moveAnchorPoint = anchor;
        _editStatusMessage =
            'Opening move preview boshlandi. Kursorni devor bo‘ylab suring va Confirm bosing.';
      });
      _syncOpeningDraft();
      return;
    }

    if (_draftCanConfirm) {
      await _confirmDraft();
    }
  }

  void _updateMoveWallPreview({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint point,
  }) {
    final anchor = _moveAnchorPoint;
    final originalStart = _moveWallOriginalStart;
    final originalEnd = _moveWallOriginalEnd;
    if (anchor == null || originalStart == null || originalEnd == null) {
      return;
    }
    RenderScenePoint nextStart;
    RenderScenePoint nextEnd;
    // A body drag is a wall offset: movement along the wall changes neither
    // its length nor its position in the useful direction. Endpoint handles
    // are different: the selected wall endpoint may move freely, while the
    // native transaction keeps every joined neighbor fixed and rebuilds the
    // new intersection.
    final constrainedPoint = _wallMoveMode == WallMoveMode.translate
        ? WallAuthoringGeometry.projectToWallNormal(
            point,
            anchor: anchor,
            start: originalStart,
            end: originalEnd,
          )
        : point;
    if (_wallMoveMode == WallMoveMode.translate) {
      // Snap the grabbed point once, then apply one shared delta to both
      // endpoints. Snapping each endpoint independently changes the wall's
      // angle and is the source of the old one-edge/diagonal jump.
      final snappedPoint = WallAuthoringGeometry.snapMovedWallPoint(
        scene,
        wall,
        constrainedPoint,
        anchor,
        snapToGrid: false,
      );
      final delta = WallAuthoringGeometry.projectToWallNormal(
            snappedPoint,
            anchor: anchor,
            start: originalStart,
            end: originalEnd,
          ) -
          anchor;
      nextStart = RenderScenePoint(
        x: originalStart.x + delta.x,
        y: originalStart.y + delta.y,
        z: originalStart.z,
      );
      nextEnd = RenderScenePoint(
        x: originalEnd.x + delta.x,
        y: originalEnd.y + delta.y,
        z: originalEnd.z,
      );
    } else if (_wallMoveMode == WallMoveMode.startHandle) {
      nextStart = _draftLinePoint(
        rawPoint: constrainedPoint,
        referenceStart: originalEnd,
        excludeWallId: wall.elementId,
      );
      nextStart = WallAuthoringGeometry.snapMovedWallPoint(
        scene,
        wall,
        nextStart,
        originalStart,
      );
      nextEnd = originalEnd;
    } else {
      nextStart = originalStart;
      nextEnd = _draftLinePoint(
        rawPoint: constrainedPoint,
        referenceStart: originalStart,
        excludeWallId: wall.elementId,
      );
      nextEnd = WallAuthoringGeometry.snapMovedWallPoint(
        scene,
        wall,
        nextEnd,
        originalEnd,
      );
    }
    // The viewport controller owns this transient draft. Avoid rebuilding the
    // whole editor for every pointer sample on a tablet.
    _draftWallStart = nextStart;
    _draftWallEnd = nextEnd;
    _viewportController.setWallDraft(nextStart, nextEnd);
  }

  Future<RenderSceneLoadResult> _setWallAxisKeepingJoins({
    required RenderSceneObject wall,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) async {
    // The native repository applies endpoint-connected walls atomically and
    // rebuilds joins once. Sending the derived neighbours one by one caused
    // the first mutation to invalidate the join used by the next one.
    return _authoringCommands.setWallAxis(
      wallId: wall.elementId!,
      start: start,
      end: end,
    );
  }

  void _updateMoveOpeningPreview({
    required RenderScene scene,
    required RenderSceneObject opening,
    required RenderScenePoint point,
  }) {
    final hostWall = _draftHostWall;
    if (hostWall == null) {
      return;
    }
    _updateOpeningDraftPreview(
      scene: scene,
      hostWall: hostWall,
      point: point,
      announce: false,
    );
    _updateViewportState(() {
      _editStatusMessage = 'Opening move preview tayyor.';
    });
  }

  void _updateOpeningDraftPreview({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required RenderScenePoint point,
    required bool announce,
  }) {
    // Project onto the host axis before applying grid snapping. Global X/Y
    // snapping can otherwise move a touch to the opposite end of a wall.
    final placement = OpeningAuthoringGeometry.preview(
      hostWall: hostWall,
      point: point,
      widthMeters: _draftOpeningWidthMeters,
      snapToGrid: _snapDraftToGrid,
    );
    if (placement == null) {
      if (announce) {
        _updateViewportState(() {
          _editStatusMessage = 'Unable to compute wall-local offset.';
        });
      }
      return;
    }

    final snappedOffset = placement.offsetMeters;
    final valid = placement.valid;
    final kind = _interactionMode == RenderSceneInteractionMode.addDoor
        ? 'Door'
        : 'Window';
    final sameWall = _draftHostWall?.elementId == hostWall.elementId;
    final sameOffset = (_draftOpeningOffsetMeters - snappedOffset).abs() < 1e-6;
    if (!announce && sameWall && sameOffset) {
      return;
    }

    _updateViewportState(() {
      _draftHostWall = hostWall;
      _draftOpeningOffsetMeters = snappedOffset;
      if (announce) {
        _editStatusMessage = valid
            ? '$kind preview on wall #${hostWall.elementId}'
            : '$kind is near wall edge.';
      }
    });

    _viewportController.setOpeningDraft(
      RenderSceneOpeningDraft(
        kind: kind,
        hostWallId: hostWall.elementId,
        offsetMeters: snappedOffset,
        widthMeters: _draftOpeningWidthMeters,
        heightMeters: _draftOpeningHeightMeters,
        sillHeightMeters: _draftOpeningSillHeightMeters,
        valid: valid,
        message:
            valid ? 'Ready to create $kind.' : 'Adjust the offset or width.',
      ),
    );
  }

  Future<void> _handleTrimExtendTap(
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    if (tappedObject == null || tappedObject.kindKey != 'wall') {
      _updateViewportState(() {
        _editStatusMessage =
            'Trim / Extend uchun wallni, o‘zgartirmoqchi bo‘lgan uchiga yaqin joyidan bosing.';
      });
      return;
    }
    final start = RenderSceneEditor.wallStartPoint(tappedObject);
    final end = RenderSceneEditor.wallEndPoint(tappedObject);
    if (start == null || end == null || tappedObject.elementId == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Tanlangan wallning tahrir qilinadigan axis geometriyasi yo‘q.';
      });
      return;
    }
    final touchPoint =
        modelPoint ?? RenderSceneEditor.wallCenterPoint(tappedObject) ?? start;
    _trimTool.selectWall(
      wall: tappedObject,
      axis: PlanSketchLine(start: start, end: end),
      touchPoint: touchPoint,
    );
    await _selectObject(tappedObject);
    await _viewportController
        .highlightElement(tappedObject.elementId!.toString());
    if (!mounted) return;
    _updateViewportState(() {
      _editStatusMessage = _trimTool.message;
      _statusMessage = _trimTool.message;
    });
  }

  Future<void> _commitTrimExtend() async {
    final first = _trimTool.first;
    final second = _trimTool.second;
    final preview = _trimTool.preview;
    final firstId = first?.wall.elementId;
    final secondId = second?.wall.elementId;
    if (first == null ||
        second == null ||
        preview == null ||
        firstId == null ||
        secondId == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Avval ikkita wallni ularning trim/extend qilinadigan uchidan tanlang.';
      });
      return;
    }
    if (!_engineBackedMode || _engineRepository == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Trim / Extend productionda engine-backed transaction talab qiladi.';
      });
      return;
    }
    try {
      final result = await _authoringCommands.trimExtendWalls(
        firstWallId: firstId,
        firstUsesStart: first.endpoint == PlanSketchEndpoint.start,
        secondWallId: secondId,
        secondUsesStart: second.endpoint == PlanSketchEndpoint.start,
      );
      await _applyEngineSceneResult(
        result,
        message: 'Walls trimmed/extended and auto-joined.',
      );
      await _clearDraft();
      await _viewportController.selectElement(firstId.toString());
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _editStatusMessage = 'Trim / Extend failed: $error';
      });
    }
  }

  Future<void> _handleSurfaceTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom &&
        _surfaceSupportsRoomAutoPick) {
      var detectedScene = RenderSceneEditor.detectRooms(scene);
      // The engine room graph is authoritative and already understands
      // interior partitions/T-junctions. It is computed only when Auto Room
      // is invoked, keeping normal viewport navigation lightweight.
      final repository = _engineRepository;
      if (_engineBackedMode && repository != null) {
        try {
          final detected = await _authoringCommands.detectRooms();
          if (detected.scene != null) {
            detectedScene = detected.scene!;
          }
        } catch (_) {
          // Legacy engines can still use the local closed-cell detector.
        }
      }
      var room = tappedObject?.kindKey == 'room'
          ? tappedObject
          : (modelPoint == null
              ? null
              : RenderSceneEditor.roomContainingPoint(
                  detectedScene,
                  modelPoint,
                  levelId: _activeLevelId,
                ));
      if (room != null &&
          RenderSceneEditor.roomBoundaryWallIds(room).length < 3 &&
          modelPoint != null) {
        room = RenderSceneEditor.roomContainingPoint(
          detectedScene,
          modelPoint,
          levelId: _activeLevelId,
        );
      }
      if (room == null) {
        _updateViewportState(() {
          _editStatusMessage =
              'Yopiq devorlar orasidagi xona ichiga bosing. Auto Room shu xonani topadi.';
        });
        return;
      }
      final boundaryWallIds = RenderSceneEditor.roomBoundaryWallIds(room);
      final polygon = RenderSceneEditor.roomBoundaryPolygon(
        detectedScene,
        room,
      );
      if (_engineBackedMode &&
          repository != null &&
          _activeLevelId != null &&
          boundaryWallIds.length >= 3 &&
          polygon != null &&
          polygon.length >= 3) {
        // A blank project intentionally has no material catalog yet. The
        // native document supports assemblyId=0 and creates a valid plain
        // slab in that case; do not make Finish a no-op just because the
        // optional layered assembly has not been created yet.
        final assemblyId = _authoringCommands.defaultAssemblyId(
              _interactionMode == RenderSceneInteractionMode.addFloor
                  ? 'Floor'
                  : 'Ceiling',
            ) ??
            0;
        try {
          final result = await _authoringCommands.createProfile(
            targetKind: _surfaceTargetKind(),
            draftMode: 3,
            levelId: _activeLevelId!,
            points: polygon,
            wallIds: const <int>[],
            closed: true,
            thicknessMeters: _draftSurfaceThicknessMeters,
            heightMeters: _draftSurfaceHeightMeters,
            verticalOffsetMeters:
                _interactionMode == RenderSceneInteractionMode.addFloor
                    ? _draftFloorTopElevationMeters
                    : _draftCeilingHeightOffsetMeters,
            assemblyId: assemblyId,
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
            message: '${_surfaceKindLabel()} #$createdId created by Auto Room.',
          );
          await _viewportController.selectElement(createdId.toString());
          await _viewportController.highlightElement(createdId.toString());
        } catch (error) {
          if (!mounted) return;
          _updateViewportState(() {
            _editStatusMessage =
                'Auto Room ${_surfaceKindLabel()} yaratolmadi: $error';
            _statusMessage = _editStatusMessage;
          });
          return;
        }
      } else {
        if (polygon == null || polygon.length < 3) {
          _updateViewportState(() {
            _editStatusMessage =
                'Xona konturi yopilmagan yoki devor geometriyasi yetarli emas.';
          });
          return;
        }
        final nextScene =
            _interactionMode == RenderSceneInteractionMode.addFloor
                ? RenderSceneEditor.addFloorFromPolygon(
                    scene: scene,
                    polygon: polygon,
                    thicknessMeters: _draftSurfaceThicknessMeters,
                    topElevationMeters: _draftFloorTopElevationMeters,
                    levelId: room.levelId ?? _activeLevelId,
                  )
                : RenderSceneEditor.addCeilingFromPolygon(
                    scene: scene,
                    polygon: polygon,
                    thicknessMeters: _draftSurfaceThicknessMeters,
                    heightMeters: _draftCeilingHeightOffsetMeters,
                    levelId: room.levelId ?? _activeLevelId,
                  );
        await _applySceneChange(
          nextScene,
          message: '${_surfaceKindLabel()} created by Auto Room.',
        );
        final created =
            nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
        if (created != null) {
          await _viewportController
              .selectElement(created.elementId?.toString());
          await _viewportController.highlightElement(
            created.elementId?.toString(),
          );
        }
      }
      await _clearDraft();
      return;
    }

    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
      // Native Filament owns the visible plan camera on Android, so its ray
      // hit-test must be preferred while Pick Walls is active. Flutter's
      // logical-pixel projection can differ from the PlatformView's physical
      // camera scale on a large blank workspace; use the model-space search as
      // a fallback for platforms without a native hit result.
      // In a top-down plan the wall is a thin line, while the native Android
      // view and the Flutter overlay can have slightly different physical
      // pixel scales. Resolve Pick Walls from the model-space tap first. The
      // projected object is only a fallback; otherwise a neighbouring wall
      // can win the hit-test and leave Finish disabled even though the user
      // visibly tapped the wall under their finger.
      final pick = modelPoint == null
          ? (tappedObject?.kindKey == 'wall' ? tappedObject : null)
          : (_findWallNearPlanPoint(
                scene,
                modelPoint,
                toleranceMeters: 0.65,
              ) ??
              (tappedObject?.kindKey == 'wall'
                  ? tappedObject
                  : _resolvePlanPick(
                      modelPoint,
                      const <String>{'wall'},
                      0.65,
                    )));
      if (pick == null || pick.kindKey != 'wall') {
        _updateViewportState(() {
          _editStatusMessage =
              'Wall chizig‘iga yaqinroq bosing. Pick Walls rectangle chizmaydi.';
        });
        return;
      }
      final wallId = pick.elementId;
      if (wallId != null) {
        if (_draftSurfaceWallIds.contains(wallId)) {
          _updateViewportState(() {
            _editStatusMessage =
                'Wall #$wallId is already selected. Use Undo to remove the last picked wall.';
          });
          await _viewportController.highlightElement(wallId.toString());
          return;
        }
        _updateViewportState(() {
          _draftSurfaceWallIds.add(wallId);
          _draftSurfacePoints.clear();
          _editStatusMessage =
              '${_draftSurfaceWallIds.length} wall picked for ${_surfaceKindLabel()} boundary. Blue walls are selected.';
        });
        await _selectObject(pick);
        await _viewportController.highlightElement(wallId.toString());
        _syncSurfaceDraftFromWalls(scene);
        return;
      }
    }

    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
      return;
    }

    if (modelPoint == null) {
      _updateViewportState(() {
        _editStatusMessage =
            'Tap plan area to draw ${_surfaceKindLabel()} boundary.';
      });
      return;
    }

    final snapped = _surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline
        ? _draftLinePoint(
            rawPoint: modelPoint,
            referenceStart: _draftSurfacePoints.lastOrNull,
          )
        : (_snapDraftToGrid ? _snapPoint(modelPoint) : modelPoint);
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
      if (_surfaceTool.boundaryClosed) {
        _updateViewportState(() {
          _editStatusMessage =
              'Boundary closed. Pink outline-ni tekshiring, keyin Finish bosing.';
        });
        return;
      }
      final first = _draftSurfacePoints.firstOrNull;
      if (first != null &&
          _draftSurfacePoints.length >= 3 &&
          SurfaceAuthoringGeometry.isNearFirstPoint(
            _draftSurfacePoints,
            snapped,
            toleranceMeters: PlanSketchGeometry.defaultEndpointToleranceMeters,
          )) {
        _updateViewportState(() {
          _draftSurfaceEnd = first;
          _editStatusMessage = 'First point snapped. Closing boundary...';
        });
        _syncSurfaceDraftPreview();
        _toggleBoundaryClosed();
        return;
      }
      final previous = _draftSurfacePoints.lastOrNull;
      if (previous != null &&
          PlanSketchGeometry.planDistance(previous, snapped) <
              PlanSketchGeometry.minimumSegmentMeters) {
        return;
      }
      _updateViewportState(() {
        _draftSurfaceWallIds.clear();
        _draftSurfacePoints.add(snapped);
        _draftSurfaceStart ??= snapped;
        _draftSurfaceEnd = snapped;
        _editStatusMessage = _draftSurfacePoints.length < 3
            ? 'Boundary point ${_draftSurfacePoints.length} added. Add the next corner.'
            : 'Pink boundary draft ready. Close contour, then Finish.';
      });
      _syncSurfaceDraftPreview();
      return;
    }

    if (_draftSurfaceStart == null) {
      _updateViewportState(() {
        _draftSurfaceStart = snapped;
        _draftSurfaceEnd = snapped;
        _draftSurfacePoints
          ..clear()
          ..add(snapped);
        _draftSurfaceWallIds.clear();
        _editStatusMessage =
            '${_surfaceKindLabel()} draft start set. Tap opposite corner to finish rectangle.';
      });
      _syncSurfaceDraftPreview();
      return;
    }

    _updateViewportState(() {
      _draftSurfaceEnd = snapped;
      if (_draftSurfacePoints.length == 1) {
        _draftSurfacePoints.add(snapped);
      } else {
        _draftSurfacePoints[1] = snapped;
      }
      _editStatusMessage = '${_surfaceKindLabel()} rectangle ready.';
    });
    _syncSurfaceDraftPreview();
    await _confirmDraft();
  }

  String _surfaceKindKey() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 'floor',
      RenderSceneInteractionMode.addCeiling => 'ceiling',
      RenderSceneInteractionMode.addRoof => 'roof',
      _ => 'surface',
    };
  }

  String _surfaceKindLabel() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 'floor',
      RenderSceneInteractionMode.addCeiling => 'ceiling',
      RenderSceneInteractionMode.addRoof => 'roof',
      _ => 'surface',
    };
  }

  int _surfaceTargetKind() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 1,
      RenderSceneInteractionMode.addCeiling => 2,
      RenderSceneInteractionMode.addRoof => 3,
      _ => 1,
    };
  }

  bool get _surfaceSupportsRoomAutoPick =>
      _interactionMode == RenderSceneInteractionMode.addFloor ||
      _interactionMode == RenderSceneInteractionMode.addCeiling;
}
