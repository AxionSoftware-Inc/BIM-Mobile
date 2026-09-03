// ignore_for_file: unused_element

part of 'tbe_ffi.dart';

extension _TbeViewerApiMethods on TbeViewerApi {
  ffi.Pointer<ffi.Void> createSession() {
    final handle = _engineCreate();
    if (handle == ffi.nullptr) {
      throw TbeApiException('Failed to create engine session');
    }
    return handle;
  }

  void destroySession(ffi.Pointer<ffi.Void> handle) => _engineDestroy(handle);

  String _readOwnedString(
    ffi.Pointer<ffi.Void> handle,
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<Utf8>>) fn,
  ) {
    final out = calloc<ffi.Pointer<Utf8>>();
    try {
      _check(handle, fn(handle, out));
      final value = out.value.toDartString();
      _freeString(out.value);
      return value;
    } finally {
      calloc.free(out);
    }
  }

  String getEngineVersion(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _getEngineVersion);
  String getApiVersion(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _getApiVersion);
  String getRenderSceneJson(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _getRenderSceneJson);
  String getRenderSceneJsonNearLevel(
    ffi.Pointer<ffi.Void> handle,
    int activeLevelId, {
    int adjacentLevelCount = 1,
  }) {
    final out = calloc<ffi.Pointer<Utf8>>();
    try {
      _check(
        handle,
        _getRenderSceneJsonNearLevel(
          handle,
          activeLevelId,
          adjacentLevelCount,
          out,
        ),
      );
      final value = out.value.toDartString();
      _freeString(out.value);
      return value;
    } finally {
      calloc.free(out);
    }
  }

  String getRenderSceneJsonPrimary(
    ffi.Pointer<ffi.Void> handle,
    int activeLevelId,
  ) {
    final out = calloc<ffi.Pointer<Utf8>>();
    try {
      _check(
        handle,
        _getRenderSceneJsonPrimary(handle, activeLevelId, out),
      );
      final value = out.value.toDartString();
      _freeString(out.value);
      return value;
    } finally {
      calloc.free(out);
    }
  }

  String getSectionSceneJson(
    ffi.Pointer<ffi.Void> handle,
    RenderScenePoint start,
    RenderScenePoint end,
  ) {
    final out = calloc<ffi.Pointer<Utf8>>();
    final startValue = calloc<TbeVec2>();
    final endValue = calloc<TbeVec2>();
    try {
      startValue.ref
        ..x = start.x
        ..y = start.y;
      endValue.ref
        ..x = end.x
        ..y = end.y;
      _check(
        handle,
        _getSectionSceneJson(
          handle,
          startValue.ref,
          endValue.ref,
          out,
        ),
      );
      final value = out.value.toDartString();
      _freeString(out.value);
      return value;
    } finally {
      calloc.free(out);
      calloc.free(startValue);
      calloc.free(endValue);
    }
  }

  String saveProjectJson(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _projectSaveJson);

  void configureInteractiveSession(ffi.Pointer<ffi.Void> handle) {
    // C++ enum order: BatterySaver=0, InteractivePreview=0.
    _check(handle, _setPerformanceProfile(handle, 0));
    _check(handle, _setComputeMode(handle, 0));
  }

  int createResidentialTemplate(
    ffi.Pointer<ffi.Void> handle, {
    required int buildingCount,
    required int storyCount,
  }) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createResidentialTemplate(handle, buildingCount, storyCount, out),
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int createShowcaseTemplate(
    ffi.Pointer<ffi.Void> handle, {
    required int templateKind,
  }) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createShowcaseTemplate(handle, templateKind, out),
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int getSchemaVersion(ffi.Pointer<ffi.Void> handle) {
    final out = calloc<ffi.Int32>();
    try {
      _check(handle, _getSchemaVersion(handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void loadProjectJson(ffi.Pointer<ffi.Void> handle, String json) {
    final jsonPtr = json.toNativeUtf8();
    try {
      _check(handle, _projectLoadJson(handle, jsonPtr));
    } finally {
      calloc.free(jsonPtr);
    }
  }

  void newProject(ffi.Pointer<ffi.Void> handle, String projectName) {
    final namePtr = projectName.toNativeUtf8();
    try {
      _check(handle, _projectNew(handle, namePtr));
    } finally {
      calloc.free(namePtr);
    }
  }

  int createLevel(
    ffi.Pointer<ffi.Void> handle,
    String name,
    double elevationMeters,
    double defaultWallHeightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createLevel(
          handle,
          namePtr,
          elevationMeters,
          defaultWallHeightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  void updateLevel(
    ffi.Pointer<ffi.Void> handle,
    int levelId, {
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) {
    final namePtr = (name ?? '').toNativeUtf8();
    try {
      _check(
        handle,
        _updateLevel(
          handle,
          levelId,
          namePtr,
          elevationMeters ?? 0.0,
          defaultWallHeightMeters ?? 0.0,
          elevationMeters == null ? 0 : 1,
          defaultWallHeightMeters == null ? 0 : 1,
        ),
      );
    } finally {
      calloc.free(namePtr);
    }
  }

  void moveLevelElevation(
    ffi.Pointer<ffi.Void> handle,
    int levelId,
    double elevationMeters,
  ) {
    _check(handle, _moveLevelElevation(handle, levelId, elevationMeters));
  }

  void setWallType(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required int wallTypeId,
  }) {
    _check(handle, _setWallType(handle, wallId, wallTypeId));
  }

  int createWallType(
    ffi.Pointer<ffi.Void> handle, {
    required WallTypeCategory category,
    required String name,
    required List<WallTypeLayerDefinition> layers,
    int coreStartLayer = -1,
    int coreEndLayer = -1,
  }) {
    if (layers.isEmpty) {
      throw TbeApiException('Wall type must contain at least one layer');
    }
    final namePtr = name.toNativeUtf8();
    final materialIds = calloc<ffi.Uint64>(layers.length);
    final thicknesses = calloc<ffi.Double>(layers.length);
    final functions = calloc<ffi.Int32>(layers.length);
    final priorities = calloc<ffi.Int32>(layers.length);
    final structural = calloc<ffi.Int32>(layers.length);
    final sides = calloc<ffi.Int32>(layers.length);
    final wrapsOpenings = calloc<ffi.Int32>(layers.length);
    final wrapsEnds = calloc<ffi.Int32>(layers.length);
    final out = calloc<ffi.Uint64>();
    for (var index = 0; index < layers.length; index += 1) {
      final layer = layers[index];
      materialIds[index] = layer.materialId;
      thicknesses[index] = layer.thicknessMeters;
      functions[index] = layer.function.index;
      priorities[index] = layer.priority;
      structural[index] = layer.structural ? 1 : 0;
      sides[index] = layer.side.index;
      wrapsOpenings[index] = layer.wrapsOpenings ? 1 : 0;
      wrapsEnds[index] = layer.wrapsEnds ? 1 : 0;
    }
    try {
      _check(
        handle,
        _createWallType(
          handle,
          category.index,
          namePtr,
          materialIds,
          thicknesses,
          functions,
          priorities,
          structural,
          sides,
          wrapsOpenings,
          wrapsEnds,
          layers.length,
          coreStartLayer,
          coreEndLayer,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(materialIds);
      calloc.free(thicknesses);
      calloc.free(functions);
      calloc.free(priorities);
      calloc.free(structural);
      calloc.free(sides);
      calloc.free(wrapsOpenings);
      calloc.free(wrapsEnds);
      calloc.free(out);
    }
  }

  void setWallLevelConstraints(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required int baseLevelId,
    required int topLevelId,
    required double baseOffsetMeters,
    required double topOffsetMeters,
    required int heightMode,
  }) {
    _check(
      handle,
      _setWallLevelConstraints(
        handle,
        wallId,
        baseLevelId,
        topLevelId,
        baseOffsetMeters,
        topOffsetMeters,
        heightMode,
      ),
    );
  }

  void setWallAxis(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) {
    final start = calloc<TbeVec2>();
    final end = calloc<TbeVec2>();
    start.ref
      ..x = startX
      ..y = startY;
    end.ref
      ..x = endX
      ..y = endY;
    try {
      _check(handle, _setWallAxis(handle, wallId, start.ref, end.ref));
    } finally {
      calloc.free(start);
      calloc.free(end);
    }
  }

  void autoJoinWalls(ffi.Pointer<ffi.Void> handle) {
    _check(handle, _autoJoinWalls(handle));
  }

  void trimExtendWalls(
    ffi.Pointer<ffi.Void> handle, {
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  }) {
    _check(
      handle,
      _trimExtendWalls(
        handle,
        firstWallId,
        firstUsesStart ? 1 : 0,
        secondWallId,
        secondUsesStart ? 1 : 0,
      ),
    );
  }

  void setElementAssembly(
      ffi.Pointer<ffi.Void> handle, int elementId, int assemblyId) {
    _check(handle, _setElementAssembly(handle, elementId, assemblyId));
  }

  void updateRoofProperties(
    ffi.Pointer<ffi.Void> handle, {
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  }) {
    _check(
        handle,
        _updateRoofProperties(
            handle,
            roofId,
            roofType,
            slopeDegrees == null ? 0 : 1,
            slopeDegrees ?? 0.0,
            overhangMeters == null ? 0 : 1,
            overhangMeters ?? 0.0));
  }

  void setStructuralWallCut(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required int cutterId,
    required bool enabled,
    double clearanceMeters = 0.0,
  }) =>
      _check(
          handle,
          _setStructuralWallCut(
              handle, wallId, cutterId, enabled ? 1 : 0, clearanceMeters));

  void setBeamColumnJoin(
    ffi.Pointer<ffi.Void> handle, {
    required int beamId,
    required int columnId,
    required bool enabled,
  }) =>
      _check(handle,
          _setBeamColumnJoin(handle, beamId, columnId, enabled ? 1 : 0));

  void resizeDoor(ffi.Pointer<ffi.Void> handle,
      {required int doorId,
      required double widthMeters,
      required double heightMeters}) {
    _check(handle, _resizeDoor(handle, doorId, widthMeters, heightMeters));
  }

  void resizeWindow(ffi.Pointer<ffi.Void> handle,
      {required int windowId,
      required double widthMeters,
      required double heightMeters,
      required double sillHeightMeters}) {
    _check(
        handle,
        _resizeWindow(
            handle, windowId, widthMeters, heightMeters, sillHeightMeters));
  }

  int createWall(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int levelId,
    double startX,
    double startY,
    double endX,
    double endY,
    double thicknessMeters,
    double heightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    final start = calloc<TbeVec2>();
    final end = calloc<TbeVec2>();
    start.ref
      ..x = startX
      ..y = startY;
    end.ref
      ..x = endX
      ..y = endY;
    try {
      _check(
        handle,
        _createWall(
          handle,
          namePtr,
          levelId,
          start.ref,
          end.ref,
          thicknessMeters,
          heightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(start);
      calloc.free(end);
      calloc.free(out);
    }
  }

  int createStair(
    ffi.Pointer<ffi.Void> handle, {
    required int baseLevelId,
    required int topLevelId,
    required double startX,
    required double startY,
    required double directionX,
    required double directionY,
    required double widthMeters,
    required double totalRiseMeters,
    required double totalRunMeters,
    required int riserCount,
    required int treadCount,
  }) {
    final out = calloc<ffi.Uint64>();
    final start = calloc<TbeVec2>();
    final direction = calloc<TbeVec2>();
    start.ref
      ..x = startX
      ..y = startY;
    direction.ref
      ..x = directionX
      ..y = directionY;
    try {
      _check(
          handle,
          _createStair(
              handle,
              baseLevelId,
              topLevelId,
              start.ref,
              direction.ref,
              widthMeters,
              totalRiseMeters,
              totalRunMeters,
              riserCount,
              treadCount,
              out));
      return out.value;
    } finally {
      calloc.free(start);
      calloc.free(direction);
      calloc.free(out);
    }
  }

  int createDoor(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int hostWallId,
    double offsetMeters,
    double widthMeters,
    double heightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createDoor(
          handle,
          namePtr,
          hostWallId,
          offsetMeters,
          widthMeters,
          heightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  int createWindow(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int hostWallId,
    double offsetMeters,
    double widthMeters,
    double heightMeters,
    double sillHeightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createWindow(
          handle,
          namePtr,
          hostWallId,
          offsetMeters,
          widthMeters,
          heightMeters,
          sillHeightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  void setOpeningLevelLock(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    bool locked,
  ) {
    _check(handle, _setOpeningLevelLock(handle, openingId, locked ? 1 : 0));
  }

  void setOpeningLevel(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    int levelId,
  ) {
    _check(handle, _setOpeningLevel(handle, openingId, levelId));
  }

  void setOpeningLevelConstraint(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    int levelId,
    double levelOffsetMeters,
  ) {
    _check(
      handle,
      _setOpeningLevelConstraint(handle, openingId, levelId, levelOffsetMeters),
    );
  }

  void moveHostedOpening(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    double offsetMeters,
  ) {
    _check(handle, _moveHostedOpening(handle, openingId, offsetMeters));
  }

  /// Applies the complete opening edit in one native session transaction.
  void updateHostedOpening(
    ffi.Pointer<ffi.Void> handle, {
    required int openingId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) {
    _check(
      handle,
      _updateHostedOpening(
        handle,
        openingId,
        offsetMeters,
        widthMeters,
        heightMeters,
        sillHeightMeters,
      ),
    );
  }

  List<int> createProfile(
    ffi.Pointer<ffi.Void> handle, {
    required int targetKind,
    required int draftMode,
    required int levelId,
    required List<RenderScenePoint> points,
    required List<int> wallIds,
    required bool closed,
    required double thicknessMeters,
    required double heightMeters,
    required double verticalOffsetMeters,
    required int materialId,
    required int assemblyId,
    required int roofType,
  }) {
    final pointBuffer = calloc<TbeVec2>(points.length);
    for (var i = 0; i < points.length; i += 1) {
      pointBuffer[i]
        ..x = points[i].x
        ..y = points[i].y;
    }
    final wallBuffer = calloc<ffi.Uint64>(wallIds.length);
    for (var i = 0; i < wallIds.length; i += 1) {
      wallBuffer[i] = wallIds[i];
    }
    final firstId = calloc<ffi.Uint64>();
    final count = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createProfile(
          handle,
          targetKind,
          draftMode,
          levelId,
          pointBuffer,
          points.length,
          wallBuffer,
          wallIds.length,
          closed ? 1 : 0,
          thicknessMeters,
          heightMeters,
          verticalOffsetMeters,
          materialId,
          assemblyId,
          roofType,
          firstId,
          count,
        ),
      );
      if (count.value == 0) {
        return const <int>[];
      }
      return <int>[firstId.value];
    } finally {
      calloc.free(pointBuffer);
      calloc.free(wallBuffer);
      calloc.free(firstId);
      calloc.free(count);
    }
  }

  int createFloorSystemForRoom(
    ffi.Pointer<ffi.Void> handle,
    int roomId,
    int assemblyId,
  ) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(
          handle, _createFloorSystemForRoom(handle, roomId, assemblyId, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int createCeilingSystemForRoom(
    ffi.Pointer<ffi.Void> handle,
    int roomId,
    int assemblyId,
    double heightOffsetMeters,
  ) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createCeilingSystemForRoom(
          handle,
          roomId,
          assemblyId,
          heightOffsetMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int detectRooms(ffi.Pointer<ffi.Void> handle) {
    final count = calloc<ffi.Uint64>();
    try {
      _check(handle, _detectRooms(handle, count));
      return count.value;
    } finally {
      calloc.free(count);
    }
  }

  void deleteElement(ffi.Pointer<ffi.Void> handle, int elementId) {
    _check(handle, _deleteElement(handle, elementId));
  }

  void undo(ffi.Pointer<ffi.Void> handle) {
    _check(handle, _undo(handle));
  }

  void redo(ffi.Pointer<ffi.Void> handle) {
    _check(handle, _redo(handle));
  }

  ({int undoCount, int redoCount}) historyCounts(
    ffi.Pointer<ffi.Void> handle,
  ) {
    final undoCount = calloc<ffi.Uint64>();
    final redoCount = calloc<ffi.Uint64>();
    try {
      _check(handle, _getHistoryCounts(handle, undoCount, redoCount));
      return (undoCount: undoCount.value, redoCount: redoCount.value);
    } finally {
      calloc.free(undoCount);
      calloc.free(redoCount);
    }
  }

  void importProjectPackage(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _importProjectPackage(handle, pathPtr, 2));
    } finally {
      calloc.free(pathPtr);
    }
  }

  void importIfc(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _importIfc(handle, pathPtr, 2));
    } finally {
      calloc.free(pathPtr);
    }
  }

  BimRuntimeCacheStats compileBimCache(
    ffi.Pointer<ffi.Void> handle, {
    required String sourceIfcPath,
    required String cachePath,
  }) =>
      _runBimCacheOperation(
        handle,
        sourceIfcPath: sourceIfcPath,
        cachePath: cachePath,
        operation: _compileBimCache,
      );

  BimRuntimeCacheStats inspectBimCache(
    ffi.Pointer<ffi.Void> handle, {
    required String sourceIfcPath,
    required String cachePath,
  }) =>
      _runBimCacheOperation(
        handle,
        sourceIfcPath: sourceIfcPath,
        cachePath: cachePath,
        operation: _inspectBimCache,
      );

  BimRuntimeCacheStats _runBimCacheOperation(
    ffi.Pointer<ffi.Void> handle, {
    required String sourceIfcPath,
    required String cachePath,
    required _BimCacheDart operation,
  }) {
    final sourcePtr = sourceIfcPath.toNativeUtf8();
    final cachePtr = cachePath.toNativeUtf8();
    final stats = calloc<TbeBimCacheStats>();
    try {
      _check(handle, operation(handle, sourcePtr, cachePtr, stats));
      return BimRuntimeCacheStats(
        formatVersion: stats.ref.formatVersion,
        sourceValid: stats.ref.sourceValid != 0,
        sourceObjectCount: stats.ref.sourceObjectCount,
        sourceTriangleCount: stats.ref.sourceTriangleCount,
        chunkCount: stats.ref.chunkCount,
        primitiveCount: stats.ref.primitiveCount,
        bvhNodeCount: stats.ref.bvhNodeCount,
        byteSize: stats.ref.byteSize,
      );
    } finally {
      calloc.free(sourcePtr);
      calloc.free(cachePtr);
      calloc.free(stats);
    }
  }

  void exportIfc(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _exportIfc(handle, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  Map<String, dynamic> getUnitSettings(ffi.Pointer<ffi.Void> handle) {
    final json = _readOwnedString(handle, _getUnitSettings);
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw TbeApiException('Invalid unit settings response');
    }
    return decoded.cast<String, dynamic>();
  }

  void setUnitSettings(
    ffi.Pointer<ffi.Void> handle, {
    required String system,
    required String length,
    required String angle,
  }) {
    final systemPtr = system.toNativeUtf8();
    final lengthPtr = length.toNativeUtf8();
    final anglePtr = angle.toNativeUtf8();
    try {
      _check(handle, _setUnitSettings(handle, systemPtr, lengthPtr, anglePtr));
    } finally {
      calloc.free(systemPtr);
      calloc.free(lengthPtr);
      calloc.free(anglePtr);
    }
  }

  ValidationSummary validate(ffi.Pointer<ffi.Void> handle) {
    final summary = calloc<TbeValidationSummary>();
    try {
      _check(handle, _validate(handle, summary));
      return ValidationSummary(
        issueCount: summary.ref.issueCount,
        warningCount: summary.ref.warningCount,
        errorCount: summary.ref.errorCount,
      );
    } finally {
      calloc.free(summary);
    }
  }

  ScheduleSummary schedules(ffi.Pointer<ffi.Void> handle) {
    final summary = calloc<TbeScheduleSummary>();
    try {
      _check(handle, _generateSchedules(handle, summary));
      return ScheduleSummary(
        wallRows: summary.ref.wallRows,
        openingRows: summary.ref.openingRows,
        roomRows: summary.ref.roomRows,
        slabRows: summary.ref.slabRows,
        roofRows: summary.ref.roofRows,
        columnRows: summary.ref.columnRows,
        beamRows: summary.ref.beamRows,
        stairRows: summary.ref.stairRows,
        floorRows: summary.ref.floorRows,
        ceilingRows: summary.ref.ceilingRows,
        materialTakeoffRows: summary.ref.materialTakeoffRows,
      );
    } finally {
      calloc.free(summary);
    }
  }

  void exportSvg(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _exportSvg(handle, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  void exportPackage(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _exportPackage(handle, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  List<HitCandidateView> hitTestCandidates(
    ffi.Pointer<ffi.Void> handle,
    int levelId,
    double x,
    double y, {
    double toleranceMeters = 0.25,
  }) {
    final result = calloc<TbeHitTestCandidatesResult>();
    final point = calloc<TbeVec2>();
    point.ref
      ..x = x
      ..y = y;
    try {
      _check(
          handle,
          _hitTestCandidates(
              handle, levelId, point.ref, toleranceMeters, result));
      final count = result.ref.candidateCount;
      final views = <HitCandidateView>[];
      for (var index = 0; index < count; index += 1) {
        final candidate = result.ref.candidates[index];
        views.add(
          HitCandidateView(
            elementId: candidate.elementId,
            elementKind: candidate.elementKind,
            hitKind: candidate.hitKind,
            distanceMeters: candidate.distanceMeters,
            priority: candidate.priority,
          ),
        );
      }
      return views;
    } finally {
      if (result.ref.candidates != ffi.nullptr) {
        _freeMemory(result.ref.candidates.cast());
      }
      calloc.free(result);
      calloc.free(point);
    }
  }

  List<int> queryRect(
    ffi.Pointer<ffi.Void> handle,
    int levelId, {
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
  }) {
    final result = calloc<TbeElementIdListResult>();
    final bounds = calloc<TbeRect2>();
    bounds.ref
      ..minX = minX
      ..minY = minY
      ..maxX = maxX
      ..maxY = maxY;
    try {
      _check(handle, _queryRect(handle, levelId, bounds.ref, result));
      return <int>[
        for (var index = 0; index < result.ref.count; index += 1)
          result.ref.elementIds[index],
      ];
    } finally {
      if (result.ref.elementIds != ffi.nullptr) {
        _freeMemory(result.ref.elementIds.cast());
      }
      calloc.free(result);
      calloc.free(bounds);
    }
  }

  String lastError(ffi.Pointer<ffi.Void> handle) =>
      _lastError(handle).toDartString();

  void _check(ffi.Pointer<ffi.Void> handle, int status) {
    if (status != 0) {
      throw TbeApiException(lastError(handle));
    }
  }
}
