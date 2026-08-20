part of 'tbe_ffi.dart';

/// Composition adapter for one native project session.
///
/// The adapter keeps only session lifecycle/state coordination. Read queries,
/// persistence metadata and authoring mutations live in their own services;
/// this class maps those services to the application gateway contracts.
class ViewerRepository
    implements ViewerAuthoringGateway, ViewerEngineSession, ViewerSceneGateway {
  ViewerRepository(this._api);

  final TbeViewerApi _api;
  final TbeRepositoryState _state = TbeRepositoryState();
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
      if (baseLevelId == null || topLevelId != 0 || heightMode == 'TopLevel') {
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
      _mutations.createLevel(
        name: name,
        elevationMeters: elevationMeters,
        defaultWallHeightMeters: defaultWallHeightMeters,
      );

  @override
  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  }) =>
      _mutations.moveLevelElevation(
        levelId: levelId,
        elevationMeters: elevationMeters,
      );

  @override
  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) =>
      _mutations.updateLevel(
        levelId: levelId,
        name: name,
        elevationMeters: elevationMeters,
        defaultWallHeightMeters: defaultWallHeightMeters,
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
      _mutations.createWall(
        name: name,
        levelId: levelId,
        start: start,
        end: end,
        thicknessMeters: thicknessMeters,
        heightMeters: heightMeters,
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
      _mutations.createStair(
        baseLevelId: baseLevelId,
        topLevelId: topLevelId,
        start: start,
        direction: direction,
        widthMeters: widthMeters,
        totalRiseMeters: totalRiseMeters,
        totalRunMeters: totalRunMeters,
        riserCount: riserCount,
        treadCount: treadCount,
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
      _mutations.setWallLevelConstraints(
        wallId: wallId,
        baseLevelId: baseLevelId,
        topLevelId: topLevelId,
        baseOffsetMeters: baseOffsetMeters,
        topOffsetMeters: topOffsetMeters,
        heightMode: heightMode,
      );

  @override
  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) =>
      _mutations.setWallAxis(wallId: wallId, start: start, end: end);

  @override
  Future<RenderSceneLoadResult> autoJoinWalls() => _mutations.autoJoinWalls();

  @override
  Future<RenderSceneLoadResult> trimExtendWalls({
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  }) =>
      _mutations.trimExtendWalls(
        firstWallId: firstWallId,
        firstUsesStart: firstUsesStart,
        secondWallId: secondWallId,
        secondUsesStart: secondUsesStart,
      );

  @override
  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) =>
      _mutations.createDoor(
        name: name,
        hostWallId: hostWallId,
        offsetMeters: offsetMeters,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
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
      _mutations.createWindow(
        name: name,
        hostWallId: hostWallId,
        offsetMeters: offsetMeters,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
      );

  @override
  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  }) =>
      _mutations.setOpeningLevelLock(openingId: openingId, locked: locked);

  Future<RenderSceneLoadResult> setOpeningLevel({
    required int openingId,
    required int levelId,
  }) =>
      _mutations.setOpeningLevel(openingId: openingId, levelId: levelId);

  @override
  Future<RenderSceneLoadResult> setOpeningLevelConstraint({
    required int openingId,
    required int levelId,
    required double levelOffsetMeters,
  }) =>
      _mutations.setOpeningLevelConstraint(
        openingId: openingId,
        levelId: levelId,
        levelOffsetMeters: levelOffsetMeters,
      );

  @override
  Future<RenderSceneLoadResult> moveHostedOpening({
    required int openingId,
    required double offsetMeters,
  }) =>
      _mutations.moveHostedOpening(
        openingId: openingId,
        offsetMeters: offsetMeters,
      );

  @override
  Future<RenderSceneLoadResult> resizeOpening({
    required int openingId,
    required String kind,
    required double widthMeters,
    required double heightMeters,
    double sillHeightMeters = 0.0,
  }) =>
      _mutations.resizeOpening(
        openingId: openingId,
        kind: kind,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
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
      _mutations.createProfile(
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

  @override
  Future<RenderSceneLoadResult> detectRooms() => _mutations.detectRooms();

  @override
  Future<RenderSceneLoadResult> createFloorSystemForRoom({
    required int roomId,
    required int assemblyId,
  }) =>
      _mutations.createFloorSystemForRoom(
        roomId: roomId,
        assemblyId: assemblyId,
      );

  @override
  Future<RenderSceneLoadResult> createCeilingSystemForRoom({
    required int roomId,
    required int assemblyId,
    required double heightOffsetMeters,
  }) =>
      _mutations.createCeilingSystemForRoom(
        roomId: roomId,
        assemblyId: assemblyId,
        heightOffsetMeters: heightOffsetMeters,
      );

  @override
  Future<RenderSceneLoadResult> setElementAssembly({
    required int elementId,
    required int assemblyId,
  }) =>
      _mutations.setElementAssembly(
          elementId: elementId, assemblyId: assemblyId);

  @override
  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  }) =>
      _mutations.updateRoofProperties(
        roofId: roofId,
        roofType: roofType,
        slopeDegrees: slopeDegrees,
        overhangMeters: overhangMeters,
      );

  @override
  Future<RenderSceneLoadResult> setStructuralWallCut({
    required int wallId,
    required int cutterId,
    required bool enabled,
    double clearanceMeters = 0.0,
  }) =>
      _mutations.setStructuralWallCut(
        wallId: wallId,
        cutterId: cutterId,
        enabled: enabled,
        clearanceMeters: clearanceMeters,
      );

  @override
  Future<RenderSceneLoadResult> setBeamColumnJoin({
    required int beamId,
    required int columnId,
    required bool enabled,
  }) =>
      _mutations.setBeamColumnJoin(
        beamId: beamId,
        columnId: columnId,
        enabled: enabled,
      );

  @override
  Future<RenderSceneLoadResult> deleteElement({required int elementId}) =>
      _mutations.deleteElement(elementId: elementId);

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
