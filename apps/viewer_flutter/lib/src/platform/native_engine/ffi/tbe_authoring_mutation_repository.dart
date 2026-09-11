part of 'tbe_ffi.dart';

/// Native document mutation boundary.
///
/// This service owns only semantic authoring commands and their DTO mapping.
/// Session lifecycle, scene reads and project checkpoints are supplied as
/// narrow callbacks by the FFI composition adapter.
final class TbeAuthoringMutationRepository {
  TbeAuthoringMutationRepository({
    required TbeViewerApi api,
    required ffi.Pointer<ffi.Void>? Function() handle,
    required Future<RenderSceneLoadResult> Function() refresh,
    required Future<void> Function() warmSnapshot,
    required Future<void> Function() beforeLevelMove,
    required void Function(int? id) setLastCreatedElementId,
  })  : _api = api,
        _handle = handle,
        _refresh = refresh,
        _warmSnapshot = warmSnapshot,
        _beforeLevelMove = beforeLevelMove,
        _setLastCreatedElementId = setLastCreatedElementId;

  final TbeViewerApi _api;
  final ffi.Pointer<ffi.Void>? Function() _handle;
  final Future<RenderSceneLoadResult> Function() _refresh;
  final Future<void> Function() _warmSnapshot;
  final Future<void> Function() _beforeLevelMove;
  final void Function(int? id) _setLastCreatedElementId;

  Future<RenderSceneLoadResult> createLevel({
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  }) async {
    _api.createLevel(
      _requireHandle(),
      name,
      elevationMeters,
      defaultWallHeightMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  }) async {
    await _beforeLevelMove();
    _api.moveLevelElevation(_requireHandle(), levelId, elevationMeters);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> moveElement({
    required int elementId,
    required double deltaX,
    required double deltaY,
  }) async {
    _api.moveElement(
      _requireHandle(),
      elementId: elementId,
      deltaXMeters: deltaX,
      deltaYMeters: deltaY,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) async {
    _api.updateLevel(
      _requireHandle(),
      levelId,
      name: name,
      elevationMeters: elevationMeters,
      defaultWallHeightMeters: defaultWallHeightMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createWall({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
  }) async {
    final id = _api.createWall(
      _requireHandle(),
      name,
      levelId,
      start.x,
      start.y,
      end.x,
      end.y,
      thicknessMeters,
      heightMeters,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createCurvedWall({
    required String name,
    required int levelId,
    required WallArcGeometry geometry,
    required double thicknessMeters,
    required double heightMeters,
  }) async {
    final id = _api.createCurvedWall(
      _requireHandle(),
      name: name,
      levelId: levelId,
      startX: geometry.start.x,
      startY: geometry.start.y,
      endX: geometry.end.x,
      endY: geometry.end.y,
      centerX: geometry.center.x,
      centerY: geometry.center.y,
      radiusMeters: geometry.radiusMeters,
      startAngleRadians: math.atan2(
        geometry.start.y - geometry.center.y,
        geometry.start.x - geometry.center.x,
      ),
      sweepRadians: geometry.sweepRadians,
      thicknessMeters: thicknessMeters,
      heightMeters: heightMeters,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createWallTransaction({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
    int topLevelId = 0,
    bool autoJoin = false,
  }) async {
    final handle = _requireHandle();
    final id = _api.createWall(
      handle,
      name,
      levelId,
      start.x,
      start.y,
      end.x,
      end.y,
      thicknessMeters,
      heightMeters,
    );
    _setLastCreatedElementId(id);
    if (topLevelId != 0) {
      _api.setWallLevelConstraints(
        handle,
        wallId: id,
        baseLevelId: levelId,
        topLevelId: topLevelId,
        baseOffsetMeters: 0.0,
        topOffsetMeters: 0.0,
        heightMode: 1,
      );
    }
    if (autoJoin) {
      _api.autoJoinWalls(handle);
    }
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setWallType({
    required int wallId,
    required int wallTypeId,
  }) async {
    _api.setWallType(
      _requireHandle(),
      wallId: wallId,
      wallTypeId: wallTypeId,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createWallTypeForWall({
    required int wallId,
    required WallTypeCategory category,
    required String name,
    required List<WallTypeLayerDefinition> layers,
  }) async {
    final handle = _requireHandle();
    _api.upsertWallTypeForWall(
      handle,
      wallId: wallId,
      category: category,
      name: name,
      layers: layers,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createStair({
    required int baseLevelId,
    required int topLevelId,
    required RenderScenePoint start,
    required RenderScenePoint direction,
    required double widthMeters,
    required double totalRiseMeters,
    required double totalRunMeters,
    required int riserCount,
    required int treadCount,
  }) async {
    final id = _api.createStair(
      _requireHandle(),
      baseLevelId: baseLevelId,
      topLevelId: topLevelId,
      startX: start.x,
      startY: start.y,
      directionX: direction.x,
      directionY: direction.y,
      widthMeters: widthMeters,
      totalRiseMeters: totalRiseMeters,
      totalRunMeters: totalRunMeters,
      riserCount: riserCount,
      treadCount: treadCount,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createStairLayout({
    required int baseLevelId,
    required int topLevelId,
    required List<RenderScenePoint> pathPoints,
    required double widthMeters,
    required double totalRiseMeters,
    required int riserCount,
    required int treadCount,
    required double landingDepthMeters,
    required int layoutKind,
    required bool railingEnabled,
  }) async {
    final id = _api.createStairLayout(
      _requireHandle(),
      baseLevelId: baseLevelId,
      topLevelId: topLevelId,
      pathPoints: pathPoints,
      widthMeters: widthMeters,
      totalRiseMeters: totalRiseMeters,
      riserCount: riserCount,
      treadCount: treadCount,
      landingDepthMeters: landingDepthMeters,
      layoutKind: layoutKind,
      railingEnabled: railingEnabled,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> updateStairLayout({
    required int stairId,
    required List<RenderScenePoint> pathPoints,
    required double widthMeters,
    required double landingDepthMeters,
    required int layoutKind,
    required bool railingEnabled,
  }) async {
    _api.updateStairLayout(
      _requireHandle(),
      stairId: stairId,
      pathPoints: pathPoints,
      widthMeters: widthMeters,
      landingDepthMeters: landingDepthMeters,
      layoutKind: layoutKind,
      railingEnabled: railingEnabled,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setWallLevelConstraints({
    required int wallId,
    required int baseLevelId,
    int topLevelId = 0,
    double baseOffsetMeters = 0.0,
    double topOffsetMeters = 0.0,
    int heightMode = 0,
  }) async {
    _api.setWallLevelConstraints(
      _requireHandle(),
      wallId: wallId,
      baseLevelId: baseLevelId,
      topLevelId: topLevelId,
      baseOffsetMeters: baseOffsetMeters,
      topOffsetMeters: topOffsetMeters,
      heightMode: heightMode,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) async {
    _api.setWallAxis(
      _requireHandle(),
      wallId: wallId,
      startX: start.x,
      startY: start.y,
      endX: end.x,
      endY: end.y,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setCurvedWallGeometry({
    required int wallId,
    required WallArcGeometry geometry,
  }) async {
    _api.setCurvedWallGeometry(
      _requireHandle(),
      wallId: wallId,
      startX: geometry.start.x,
      startY: geometry.start.y,
      endX: geometry.end.x,
      endY: geometry.end.y,
      centerX: geometry.center.x,
      centerY: geometry.center.y,
      radiusMeters: geometry.radiusMeters,
      startAngleRadians: math.atan2(
        geometry.start.y - geometry.center.y,
        geometry.start.x - geometry.center.x,
      ),
      sweepRadians: geometry.sweepRadians,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> autoJoinWalls() async {
    _api.autoJoinWalls(_requireHandle());
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> trimExtendWalls({
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  }) async {
    _api.trimExtendWalls(
      _requireHandle(),
      firstWallId: firstWallId,
      firstUsesStart: firstUsesStart,
      secondWallId: secondWallId,
      secondUsesStart: secondUsesStart,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) async {
    final id = _api.createDoor(
      _requireHandle(),
      name,
      hostWallId,
      offsetMeters,
      widthMeters,
      heightMeters,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) async {
    final id = _api.createWindow(
      _requireHandle(),
      name,
      hostWallId,
      offsetMeters,
      widthMeters,
      heightMeters,
      sillHeightMeters,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createColumn({
    required int levelId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    int materialId = 0,
  }) async {
    final id = _api.createColumn(
      _requireHandle(),
      levelId: levelId,
      x: position.x,
      y: position.y,
      widthMeters: widthMeters,
      depthMeters: depthMeters,
      heightMeters: heightMeters,
      materialId: materialId,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createFamilyProxy({
    required String name,
    required int levelId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    required List<RenderScenePoint> vertices,
    required List<int> indices,
  }) async {
    final id = _api.createProxy(
      _requireHandle(),
      name: name,
      levelId: levelId,
      x: position.x,
      y: position.y,
      widthMeters: widthMeters,
      depthMeters: depthMeters,
      heightMeters: heightMeters,
      vertices: vertices,
      indices: indices,
    );
    _setLastCreatedElementId(id);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  }) async {
    _api.setOpeningLevelLock(_requireHandle(), openingId, locked);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setOpeningLevel({
    required int openingId,
    required int levelId,
  }) async {
    _api.setOpeningLevel(_requireHandle(), openingId, levelId);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setOpeningLevelConstraint({
    required int openingId,
    required int levelId,
    required double levelOffsetMeters,
  }) async {
    _api.setOpeningLevelConstraint(
      _requireHandle(),
      openingId,
      levelId,
      levelOffsetMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> moveHostedOpening({
    required int openingId,
    required double offsetMeters,
  }) async {
    _api.moveHostedOpening(_requireHandle(), openingId, offsetMeters);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> resizeOpening({
    required int openingId,
    required String kind,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  }) async {
    final handle = _requireHandle();
    if (kind == 'door') {
      _api.resizeDoor(
        handle,
        doorId: openingId,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
      );
    } else if (kind == 'window') {
      _api.resizeWindow(
        handle,
        windowId: openingId,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
      );
    } else {
      throw TbeApiException('Unsupported opening kind: $kind');
    }
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> updateHostedOpening({
    required int openingId,
    required String kind,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  }) async {
    if (kind != 'door' && kind != 'window') {
      throw TbeApiException('Unsupported opening kind: $kind');
    }
    _api.updateHostedOpening(
      _requireHandle(),
      openingId: openingId,
      offsetMeters: offsetMeters,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: sillHeightMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createProfile({
    required int targetKind,
    required int draftMode,
    required int levelId,
    required List<RenderScenePoint> points,
    List<int> wallIds = const <int>[],
    required bool closed,
    required double thicknessMeters,
    required double heightMeters,
    required double verticalOffsetMeters,
    int materialId = 0,
    int assemblyId = 0,
    int roofType = 0,
  }) async {
    final ids = _api.createProfile(
      _requireHandle(),
      targetKind: targetKind,
      draftMode: draftMode,
      levelId: levelId,
      points: points,
      wallIds: wallIds,
      closed: closed,
      thicknessMeters: thicknessMeters,
      heightMeters: heightMeters,
      verticalOffsetMeters: verticalOffsetMeters,
      materialId: materialId,
      assemblyId: assemblyId,
      roofType: roofType,
    );
    _setLastCreatedElementId(ids.isEmpty ? null : ids.first);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> detectRooms() async {
    _api.detectRooms(_requireHandle());
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createFloorSystemForRoom({
    required int roomId,
    required int assemblyId,
  }) async {
    _api.createFloorSystemForRoom(_requireHandle(), roomId, assemblyId);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> createCeilingSystemForRoom({
    required int roomId,
    required int assemblyId,
    required double heightOffsetMeters,
  }) async {
    _api.createCeilingSystemForRoom(
      _requireHandle(),
      roomId,
      assemblyId,
      heightOffsetMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setElementAssembly({
    required int elementId,
    required int assemblyId,
  }) async {
    _api.setElementAssembly(_requireHandle(), elementId, assemblyId);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setElementFamilyReference({
    required int elementId,
    required String familyAssetId,
    required String familyName,
    required String familyTypeId,
    required String familyTypeName,
    required String familyCategory,
    String familyAssetPath = '',
    String familyParameterDefinitionsJson = '',
    String familyParameterValuesJson = '',
    String familyPlanSvg = '',
  }) async {
    _api.setElementFamilyReference(
      _requireHandle(),
      elementId: elementId,
      familyAssetId: familyAssetId,
      familyName: familyName,
      familyTypeId: familyTypeId,
      familyTypeName: familyTypeName,
      familyCategory: familyCategory,
      familyAssetPath: familyAssetPath,
      familyParameterDefinitionsJson: familyParameterDefinitionsJson,
      familyParameterValuesJson: familyParameterValuesJson,
      familyPlanSvg: familyPlanSvg,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> updateFamilyInstance({
    required int elementId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    required List<RenderScenePoint> vertices,
    required List<int> indices,
  }) async {
    _api.updateFamilyInstance(
      _requireHandle(),
      elementId: elementId,
      x: position.x,
      y: position.y,
      widthMeters: widthMeters,
      depthMeters: depthMeters,
      heightMeters: heightMeters,
      vertices: vertices,
      indices: indices,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  }) async {
    _api.updateRoofProperties(
      _requireHandle(),
      roofId: roofId,
      roofType: roofType,
      slopeDegrees: slopeDegrees,
      overhangMeters: overhangMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setStructuralWallCut({
    required int wallId,
    required int cutterId,
    required bool enabled,
    double clearanceMeters = 0.0,
  }) async {
    _api.setStructuralWallCut(
      _requireHandle(),
      wallId: wallId,
      cutterId: cutterId,
      enabled: enabled,
      clearanceMeters: clearanceMeters,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> setBeamColumnJoin({
    required int beamId,
    required int columnId,
    required bool enabled,
  }) async {
    _api.setBeamColumnJoin(
      _requireHandle(),
      beamId: beamId,
      columnId: columnId,
      enabled: enabled,
    );
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> deleteElement({required int elementId}) async {
    _api.deleteElement(_requireHandle(), elementId);
    return _afterMutation();
  }

  Future<RenderSceneLoadResult> _afterMutation() async {
    await _warmSnapshot();
    return _refresh();
  }

  ffi.Pointer<ffi.Void> _requireHandle() {
    final handle = _handle();
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    return handle;
  }
}
