part of 'viewer_app.dart';

/// Revit-like room placement interaction.
///
/// Room detection is cheap and local while the finger moves, so the preview
/// never waits for a native round-trip. Release is the only point at which the
/// authoritative engine is asked to persist the room graph.
extension _ViewerViewportRoomPlacement on _ViewerHomePageState {
  void _updateRoomPlacementPreview(RenderSceneTapDetails details) {
    if (details.pointerCount > 1) return;
    final scene = _scene;
    final point = details.modelPoint;
    if (scene == null || point == null) return;

    final plan = RoomPlacementPreviewPlanner.plan(
      scene: scene,
      point: point,
      activeLevelId: _activeLevelId,
      pickedObject: details.pickedObject,
    );
    final area = plan.areaSquareMeters;

    _updateViewportState(() {
      _draftRoom = plan.room;
      _draftRoomPoint = point;
      _draftRoomValid = plan.valid;
      _editStatusMessage = plan.valid
          ? 'Valid room: ${area == null ? '--' : area.toStringAsFixed(2)} m². Release to place Room.'
          : 'Invalid room location. Move inside a closed wall boundary.';
      _statusMessage = _editStatusMessage;
    });
    _viewportController.setSurfaceDraft(
      RenderSceneSurfaceDraft(
        kind: plan.valid ? 'room-valid' : 'room-invalid',
        points: plan.previewPoints,
        closed: true,
      ),
    );
  }

  Future<void> _commitRoomPlacement({RenderScenePoint? point}) async {
    final scene = _scene;
    final roomPreview = _draftRoom;
    final targetPoint = point ?? _draftRoomPoint;
    if (scene == null || !_draftRoomValid || roomPreview == null) {
      if (mounted) {
        _updateViewportState(() {
          _editStatusMessage =
              'Room qo‘yilmadi: avval yopiq, valid xona ichiga kiriting.';
          _statusMessage = _editStatusMessage;
        });
      }
      return;
    }

    try {
      RenderSceneObject? committedRoom = roomPreview;
      final repository = _engineRepository;
      if (_engineBackedMode && repository != null) {
        final result = await _authoringCommands.detectRooms();
        final resultScene = result.scene;
        if (resultScene == null) {
          throw StateError('Room detection returned no scene.');
        }
        committedRoom = targetPoint == null
            ? resultScene.objectById(roomPreview.elementId)
            : RenderSceneEditor.roomContainingPoint(
                resultScene,
                targetPoint,
                levelId: _activeLevelId,
              );
        if (committedRoom == null) {
          throw StateError('The released point is no longer inside a room.');
        }
        await _applyEngineSceneResult(
          result,
          message: 'Room placed and room quantities updated.',
        );
      } else {
        final nextScene = RenderSceneEditor.detectRooms(scene);
        committedRoom = targetPoint == null
            ? nextScene.objectById(roomPreview.elementId)
            : RenderSceneEditor.roomContainingPoint(
                nextScene,
                targetPoint,
                levelId: _activeLevelId,
              );
        if (committedRoom == null) {
          throw StateError('The released point is no longer inside a room.');
        }
        await _applySceneChange(
          nextScene,
          message: 'Room placed and room quantities updated.',
        );
      }

      final id = committedRoom.elementId;
      if (id != null) {
        await _viewportController.selectElement(id.toString());
        await _viewportController.highlightElement(id.toString());
      }
      await _clearDraft();
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _editStatusMessage = 'Room placement failed: $error';
        _statusMessage = _editStatusMessage;
      });
    }
  }
}
