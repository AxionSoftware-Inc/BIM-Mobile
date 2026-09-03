part of 'tbe_ffi.dart';

/// Composition adapter for one native project session.
///
/// The adapter keeps only session lifecycle/state coordination. Read queries,
/// persistence metadata and authoring mutations live in their own services;
/// this class maps those services to the application gateway contracts.
class ViewerRepository
    implements
        ViewerAuthoringGateway,
        ViewerBimRuntimeCacheGateway,
        ViewerEngineSession,
        ViewerSceneGateway,
        ViewerPrimarySceneGateway {
  ViewerRepository(this._api);

  final TbeViewerApi _api;
  final TbeRepositoryState _state = TbeRepositoryState();
  // The native session is mutable and its snapshot is read immediately after
  // each command. Serialize the complete command -> snapshot pair so a wall,
  // door, or assembly update cannot race another authoring operation.
  final AsyncSerialQueue _authoringQueue = AsyncSerialQueue();
  late final TbeProjectPersistenceRepository _persistence =
      TbeProjectPersistenceRepository(api: _api, state: _state);
  late final TbeSceneQueryRepository _sceneQueries = TbeSceneQueryRepository(
    api: _api,
    handle: () => _handle,
    activeLevelId: () => _activeLevelId,
    fullSceneRenderScope: () => _fullSceneRenderScope,
  );
  late final TbeAuthoringMutationRepository _mutations =
      TbeAuthoringMutationRepository(
    api: _api,
    handle: () => _handle,
    refresh: currentRenderScene,
    warmSnapshot: () async {
      final handle = _handle;
      if (handle != null) {
        await _buildSnapshot(handle, _projectName ?? 'Project');
      }
    },
    beforeLevelMove: constrainUnconnectedWallsToNextLevel,
    setLastCreatedElementId: (id) => _lastCreatedElementId = id,
  );

  ffi.Pointer<ffi.Void>? get _handle => _state.handle;
  set _handle(ffi.Pointer<ffi.Void>? value) => _state.handle = value;
  String? get _projectName => _state.projectName;
  set _projectName(String? value) => _state.projectName = value;
  int get _activeLevelId => _state.activeLevelId;
  set _activeLevelId(int value) => _state.activeLevelId = value;
  bool get _fullSceneRenderScope => _state.fullSceneRenderScope;
  set _fullSceneRenderScope(bool value) => _state.fullSceneRenderScope = value;
  String? get _currentJson => _state.currentJson;
  set _currentJson(String? value) => _state.currentJson = value;
  String? get _currentJsonPath => _state.currentJsonPath;
  set _currentJsonPath(String? value) => _state.currentJsonPath = value;
  String? get _currentPackagePath => _state.currentPackagePath;
  set _currentPackagePath(String? value) => _state.currentPackagePath = value;
  int? get _lastCreatedElementId => _state.lastCreatedElementId;
  set _lastCreatedElementId(int? value) => _state.lastCreatedElementId = value;

  @override
  int? get lastCreatedElementId => _lastCreatedElementId;

  @override
  Future<ViewerLoadResult> loadFromJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    _projectName = projectName;
    _currentJson = json;
    _currentJsonPath = sourcePath;
    _currentPackagePath = null;
    _activeLevelId = _persistence.primaryLevelIdFromProjectJson(json);
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _api.loadProjectJson(handle, json);
    final snapshot = await _buildSnapshot(handle, projectName);
    return ViewerLoadResult(
      snapshot: snapshot,
      hitCandidates: const <HitCandidateView>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> createBlankProject({
    String projectName = 'New Project',
  }) async {
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _api.newProject(handle, projectName);
    _projectName = projectName;
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = null;
    _activeLevelId = _api.createLevel(handle, 'Level 1', 0.0, 3.2);
    _api.createLevel(handle, 'Level 2', 3.2, 3.2);
    return currentRenderScene();
  }

  @override
  Future<ViewerLoadResult> loadFromPackage({
    required String packagePath,
  }) async {
    _projectName = packagePath.split(Platform.pathSeparator).last;
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = packagePath;
    _activeLevelId = _persistence.primaryLevelIdFromPackage(packagePath);
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _api.importProjectPackage(handle, packagePath);
    final snapshot = await _buildSnapshot(handle, _projectName!);
    return ViewerLoadResult(
      snapshot: snapshot,
      hitCandidates: const <HitCandidateView>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> createResidentialTemplate({
    required int buildingCount,
    required int storyCount,
  }) async {
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _activeLevelId = _api.createResidentialTemplate(
      handle,
      buildingCount: buildingCount,
      storyCount: storyCount,
    );
    _projectName = buildingCount == 1
        ? '$storyCount Storey Residential Tower'
        : '$buildingCount Building Residential Campus';
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = null;
    await _buildSnapshot(handle, _projectName!);
    return currentRenderScene();
  }

  @override
  Future<RenderSceneLoadResult> createShowcaseTemplate({
    required int templateKind,
  }) async {
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _activeLevelId = _api.createShowcaseTemplate(
      handle,
      templateKind: templateKind,
    );
    _projectName = switch (templateKind) {
      0 => 'Modern Glass Courtyard House',
      1 => 'Modern Glass Residential Tower',
      _ => 'Modern Glass Courtyard Campus',
    };
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = null;
    await _buildSnapshot(handle, _projectName!);
    return currentRenderScene();
  }

  @override
  Future<ViewerLoadResult> reloadCurrent() async {
    final jsonPath = _currentJsonPath;
    if (jsonPath != null) {
      final json = await File(jsonPath).readAsString();
      return loadFromJson(
        projectName: _projectName ?? File(jsonPath).uri.pathSegments.last,
        json: json,
        sourcePath: jsonPath,
      );
    }
    final json = _currentJson;
    if (json != null) {
      return loadFromJson(
        projectName: _projectName ?? 'Reloaded Project',
        json: json,
      );
    }
    final packagePath = _currentPackagePath;
    if (packagePath != null) return loadFromPackage(packagePath: packagePath);
    throw TbeApiException('No current project to reload');
  }

  @override
  Future<String> saveProjectJson() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    final json = _api.saveProjectJson(handle);
    _currentJson = json;
    _currentJsonPath = null;
    _currentPackagePath = null;
    _activeLevelId = _persistence.primaryLevelIdFromProjectJson(json);
    return json;
  }

  @override
  Future<File> saveProjectToDefaultLocation() async {
    final json = await saveProjectJson();
    return _persistence.saveToDefaultLocation(
      json: json,
      projectName: _projectName,
    );
  }

  @override
  Future<ViewerLoadResult> loadFromIfc({required String ifcPath}) async {
    _projectName = File(ifcPath).uri.pathSegments.last;
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = null;
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.configureInteractiveSession(handle);
    _api.importIfc(handle, ifcPath);
    _currentJson = _api.saveProjectJson(handle);
    _activeLevelId = _persistence.primaryLevelIdFromProjectJson(_currentJson!);
    final snapshot = await _buildSnapshot(handle, _projectName!);
    return ViewerLoadResult(
      snapshot: snapshot,
      hitCandidates: const <HitCandidateView>[],
    );
  }

  @override
  Future<void> exportIfc({required String path}) async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    _api.exportIfc(handle, path);
  }

  @override
  Future<Map<String, dynamic>> getUnitSettings() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    return _api.getUnitSettings(handle);
  }

  @override
  Future<void> setUnitSettings({
    required String system,
    required String length,
    required String angle,
  }) async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    _api.setUnitSettings(
      handle,
      system: system,
      length: length,
      angle: angle,
    );
  }

  @override
  Future<RenderSceneLoadResult> undo() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    _api.undo(handle);
    return currentRenderScene();
  }

  @override
  Future<RenderSceneLoadResult> redo() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    _api.redo(handle);
    return currentRenderScene();
  }

  @override
  Future<({int undoCount, int redoCount})> historyCounts() async {
    final handle = _handle;
    if (handle == null) {
      return (undoCount: 0, redoCount: 0);
    }
    return _api.historyCounts(handle);
  }

  @override
  Future<String> snapshotProjectJson() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    final json = _api.saveProjectJson(handle);
    _currentJson = json;
    _activeLevelId = _persistence.primaryLevelIdFromProjectJson(json);
    return json;
  }

  @override
  Future<BimRuntimeCacheStats> compileBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    return _api.compileBimCache(
      handle,
      sourceIfcPath: sourceIfcPath,
      cachePath: cachePath,
    );
  }

  @override
  Future<BimRuntimeCacheStats> inspectBimRuntimeCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    return _api.inspectBimCache(
      handle,
      sourceIfcPath: sourceIfcPath,
      cachePath: cachePath,
    );
  }

  @override
  Future<String> snapshotImportedProjectJson() async {
    final json = _currentJson;
    if (json != null && json.isNotEmpty) return json;
    return snapshotProjectJson();
  }

  Future<ViewerSnapshot> _buildSnapshot(
    ffi.Pointer<ffi.Void> handle,
    String projectName,
  ) async {
    return ViewerSnapshot(
      projectName: _projectName ?? projectName,
      engineVersion: _api.getEngineVersion(handle),
      apiVersion: _api.getApiVersion(handle),
      schemaVersion: _api.getSchemaVersion(handle),
      levelId: _activeLevelId,
      validation:
          ValidationSummary(issueCount: 0, warningCount: 0, errorCount: 0),
      schedule: ScheduleSummary(
        wallRows: 0,
        openingRows: 0,
        roomRows: 0,
        slabRows: 0,
        roofRows: 0,
        columnRows: 0,
        beamRows: 0,
        stairRows: 0,
        floorRows: 0,
        ceilingRows: 0,
        materialTakeoffRows: 0,
      ),
      svgPath: '',
      packagePath: '',
      validationMessages: const <String>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> currentRenderScene() =>
      _sceneQueries.currentRenderScene();

  @override
  Future<RenderSceneLoadResult> currentPrimaryRenderScene() =>
      _sceneQueries.currentPrimaryRenderScene();

  @override
  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  ) =>
      _sceneQueries.sectionScene(start, end);

  @override
  Future<RenderSceneLoadResult> setActiveLevel(int levelId) async {
    _activeLevelId = levelId;
    return currentRenderScene();
  }

  @override
  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled) async {
    _fullSceneRenderScope = enabled;
    return currentRenderScene();
  }

  /// Repairs legacy walls before a level move, preserving the old atomic
  /// behavior while keeping the repair policy outside the mutation service.
  Future<RenderSceneLoadResult> constrainUnconnectedWallsToNextLevel() async {
    final handle = _handle;
    if (handle == null) throw TbeApiException('No loaded project');
    final current = await currentRenderScene();
    final scene = current.scene;
    if (scene == null) return current;
    final levels = [...scene.levels]..sort(
        (left, right) => left.elevationMeters.compareTo(right.elevationMeters));
    var changed = false;
    for (final wall
        in scene.objects.where((object) => object.kindKey == 'wall')) {
      final heightMode = wall.metadata['height_mode']?.toString();
      final baseLevelId = int.tryParse(
            wall.metadata['base_level_id']?.toString() ?? '',
          ) ??
          wall.levelId;
      final topLevelId =
          int.tryParse(wall.metadata['top_level_id']?.toString() ?? '') ?? 0;
      // Only repair genuinely legacy snapshots that have no height-mode
      // metadata. An explicit Unconnected wall is a valid authoring choice
      // and must not be silently converted to a top-level constraint before
      // every level move.
      if (baseLevelId == null ||
          topLevelId != 0 ||
          heightMode?.isNotEmpty == true) {
        continue;
      }
      final base = scene.levelById(baseLevelId);
      if (base == null) continue;
      RenderSceneLevel? top;
      for (final level in levels) {
        if (level.elevationMeters > base.elevationMeters + 1.0e-6) {
          top = level;
          break;
        }
      }
      if (top == null || wall.elementId == null) continue;
      _api.setWallLevelConstraints(
        handle,
        wallId: wall.elementId!,
        baseLevelId: baseLevelId,
        topLevelId: top.levelId,
        baseOffsetMeters: double.tryParse(
              wall.metadata['base_offset_meters']?.toString() ?? '',
            ) ??
            0.0,
        topOffsetMeters: double.tryParse(
              wall.metadata['top_offset_meters']?.toString() ?? '',
            ) ??
            0.0,
        heightMode: 1,
      );
      changed = true;
    }
    if (!changed) return current;
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  @override
  Future<RenderSceneLoadResult> createLevel({
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.createLevel(
          name: name,
          elevationMeters: elevationMeters,
          defaultWallHeightMeters: defaultWallHeightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.moveLevelElevation(
          levelId: levelId,
          elevationMeters: elevationMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.updateLevel(
          levelId: levelId,
          name: name,
          elevationMeters: elevationMeters,
          defaultWallHeightMeters: defaultWallHeightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createWall({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.createWall(
          name: name,
          levelId: levelId,
          start: start,
          end: end,
          thicknessMeters: thicknessMeters,
          heightMeters: heightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setWallType({
    required int wallId,
    required int wallTypeId,
  }) =>
      _authoringQueue.run(
        () => _mutations.setWallType(
          wallId: wallId,
          wallTypeId: wallTypeId,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createWallTypeForWall({
    required int wallId,
    required WallTypeCategory category,
    required String name,
    required List<WallTypeLayerDefinition> layers,
  }) =>
      _authoringQueue.run(
        () => _mutations.createWallTypeForWall(
          wallId: wallId,
          category: category,
          name: name,
          layers: layers,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createWallTransaction({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
    int topLevelId = 0,
    bool autoJoin = false,
  }) =>
      _authoringQueue.run(
        () => _mutations.createWallTransaction(
          name: name,
          levelId: levelId,
          start: start,
          end: end,
          thicknessMeters: thicknessMeters,
          heightMeters: heightMeters,
          topLevelId: topLevelId,
          autoJoin: autoJoin,
        ),
      );

  @override
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
  }) =>
      _authoringQueue.run(
        () => _mutations.createStair(
          baseLevelId: baseLevelId,
          topLevelId: topLevelId,
          start: start,
          direction: direction,
          widthMeters: widthMeters,
          totalRiseMeters: totalRiseMeters,
          totalRunMeters: totalRunMeters,
          riserCount: riserCount,
          treadCount: treadCount,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setWallLevelConstraints({
    required int wallId,
    required int baseLevelId,
    int topLevelId = 0,
    double baseOffsetMeters = 0.0,
    double topOffsetMeters = 0.0,
    int heightMode = 0,
  }) =>
      _authoringQueue.run(
        () => _mutations.setWallLevelConstraints(
          wallId: wallId,
          baseLevelId: baseLevelId,
          topLevelId: topLevelId,
          baseOffsetMeters: baseOffsetMeters,
          topOffsetMeters: topOffsetMeters,
          heightMode: heightMode,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) =>
      _authoringQueue.run(
        () => _mutations.setWallAxis(wallId: wallId, start: start, end: end),
      );

  @override
  Future<RenderSceneLoadResult> autoJoinWalls() =>
      _authoringQueue.run(_mutations.autoJoinWalls);

  @override
  Future<RenderSceneLoadResult> trimExtendWalls({
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  }) =>
      _authoringQueue.run(
        () => _mutations.trimExtendWalls(
          firstWallId: firstWallId,
          firstUsesStart: firstUsesStart,
          secondWallId: secondWallId,
          secondUsesStart: secondUsesStart,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.createDoor(
          name: name,
          hostWallId: hostWallId,
          offsetMeters: offsetMeters,
          widthMeters: widthMeters,
          heightMeters: heightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.createWindow(
          name: name,
          hostWallId: hostWallId,
          offsetMeters: offsetMeters,
          widthMeters: widthMeters,
          heightMeters: heightMeters,
          sillHeightMeters: sillHeightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  }) =>
      _authoringQueue.run(
        () => _mutations.setOpeningLevelLock(
          openingId: openingId,
          locked: locked,
        ),
      );

  Future<RenderSceneLoadResult> setOpeningLevel({
    required int openingId,
    required int levelId,
  }) =>
      _authoringQueue.run(
        () => _mutations.setOpeningLevel(
          openingId: openingId,
          levelId: levelId,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setOpeningLevelConstraint({
    required int openingId,
    required int levelId,
    required double levelOffsetMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.setOpeningLevelConstraint(
          openingId: openingId,
          levelId: levelId,
          levelOffsetMeters: levelOffsetMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> moveHostedOpening({
    required int openingId,
    required double offsetMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.moveHostedOpening(
          openingId: openingId,
          offsetMeters: offsetMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> resizeOpening({
    required int openingId,
    required String kind,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  }) =>
      _authoringQueue.run(
        () => _mutations.resizeOpening(
          openingId: openingId,
          kind: kind,
          widthMeters: widthMeters,
          heightMeters: heightMeters,
          sillHeightMeters: sillHeightMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> updateHostedOpening({
    required int openingId,
    required String kind,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  }) =>
      _authoringQueue.run(
        () => _mutations.updateHostedOpening(
          openingId: openingId,
          kind: kind,
          offsetMeters: offsetMeters,
          widthMeters: widthMeters,
          heightMeters: heightMeters,
          sillHeightMeters: sillHeightMeters,
        ),
      );

  @override
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
  }) =>
      _authoringQueue.run(
        () => _mutations.createProfile(
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
        ),
      );

  @override
  Future<RenderSceneLoadResult> detectRooms() =>
      _authoringQueue.run(_mutations.detectRooms);

  @override
  Future<RenderSceneLoadResult> createFloorSystemForRoom({
    required int roomId,
    required int assemblyId,
  }) =>
      _authoringQueue.run(
        () => _mutations.createFloorSystemForRoom(
          roomId: roomId,
          assemblyId: assemblyId,
        ),
      );

  @override
  Future<RenderSceneLoadResult> createCeilingSystemForRoom({
    required int roomId,
    required int assemblyId,
    required double heightOffsetMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.createCeilingSystemForRoom(
          roomId: roomId,
          assemblyId: assemblyId,
          heightOffsetMeters: heightOffsetMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setElementAssembly({
    required int elementId,
    required int assemblyId,
  }) =>
      _authoringQueue.run(
        () => _mutations.setElementAssembly(
          elementId: elementId,
          assemblyId: assemblyId,
        ),
      );

  @override
  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  }) =>
      _authoringQueue.run(
        () => _mutations.updateRoofProperties(
          roofId: roofId,
          roofType: roofType,
          slopeDegrees: slopeDegrees,
          overhangMeters: overhangMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setStructuralWallCut({
    required int wallId,
    required int cutterId,
    required bool enabled,
    double clearanceMeters = 0.0,
  }) =>
      _authoringQueue.run(
        () => _mutations.setStructuralWallCut(
          wallId: wallId,
          cutterId: cutterId,
          enabled: enabled,
          clearanceMeters: clearanceMeters,
        ),
      );

  @override
  Future<RenderSceneLoadResult> setBeamColumnJoin({
    required int beamId,
    required int columnId,
    required bool enabled,
  }) =>
      _authoringQueue.run(
        () => _mutations.setBeamColumnJoin(
          beamId: beamId,
          columnId: columnId,
          enabled: enabled,
        ),
      );

  @override
  Future<RenderSceneLoadResult> deleteElement({required int elementId}) =>
      _authoringQueue.run(
        () => _mutations.deleteElement(elementId: elementId),
      );

  @override
  List<HitCandidateView> hitTest(
    double modelX,
    double modelY, {
    double toleranceMeters = 0.25,
  }) =>
      _sceneQueries.hitTest(
        modelX,
        modelY,
        toleranceMeters: toleranceMeters,
      );

  @override
  int? defaultAssemblyId(String kind) => _persistence.defaultAssemblyId(kind);

  @override
  void dispose() {
    final handle = _handle;
    if (handle != null) {
      _api.destroySession(handle);
      _handle = null;
    }
  }
}
