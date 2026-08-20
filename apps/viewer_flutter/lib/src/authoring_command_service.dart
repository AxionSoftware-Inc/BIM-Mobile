import 'render_scene_models.dart';
import 'viewer_authoring_gateway.dart';
import 'viewer_element_creation_gateway.dart';
import 'viewer_engine_contracts.dart';

/// Engine-first Inspector mutations. A command either returns a new
/// authoritative snapshot or an error; widgets never mutate local geometry.
class AuthoringCommandService {
  AuthoringCommandService({
    required ViewerAuthoringGateway? Function() repository,
    required ViewerElementCreationGateway? Function() creationGateway,
    required bool Function() engineEnabled,
  })  : _repository = repository,
        _creationGateway = creationGateway,
        _engineEnabled = engineEnabled;

  final ViewerAuthoringGateway? Function() _repository;
  final ViewerElementCreationGateway? Function() _creationGateway;
  final bool Function() _engineEnabled;

  int? get lastCreatedElementId =>
      _requireCreationGateway().lastCreatedElementId;

  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  }) =>
      _requireRepository().updateLevel(
        levelId: levelId,
        name: name,
        elevationMeters: elevationMeters,
        defaultWallHeightMeters: defaultWallHeightMeters,
      );

  Future<RenderSceneLoadResult> setWallConstraints({
    required int wallId,
    required int baseLevelId,
    required int topLevelId,
    required int heightMode,
    double baseOffsetMeters = 0,
    double topOffsetMeters = 0,
  }) =>
      _requireRepository().setWallLevelConstraints(
        wallId: wallId,
        baseLevelId: baseLevelId,
        topLevelId: topLevelId,
        heightMode: heightMode,
        baseOffsetMeters: baseOffsetMeters,
        topOffsetMeters: topOffsetMeters,
      );

  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) =>
      _requireRepository().setWallAxis(
        wallId: wallId,
        start: start,
        end: end,
      );

  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  }) =>
      _requireRepository().moveLevelElevation(
        levelId: levelId,
        elevationMeters: elevationMeters,
      );

  Future<RenderSceneLoadResult> moveOpening({
    required int openingId,
    required double offsetMeters,
  }) =>
      _requireRepository().moveHostedOpening(
        openingId: openingId,
        offsetMeters: offsetMeters,
      );

  Future<RenderSceneLoadResult> resizeHostedOpening({
    required int openingId,
    required String kind,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) =>
      _requireRepository().resizeOpening(
        openingId: openingId,
        kind: kind,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
      );

  Future<RenderSceneLoadResult> trimExtendWalls({
    required int firstWallId,
    required bool firstUsesStart,
    required int secondWallId,
    required bool secondUsesStart,
  }) =>
      _requireRepository().trimExtendWalls(
        firstWallId: firstWallId,
        firstUsesStart: firstUsesStart,
        secondWallId: secondWallId,
        secondUsesStart: secondUsesStart,
      );

  Future<RenderSceneLoadResult> updateOpening({
    required RenderSceneObject object,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) async {
    final id = object.elementId;
    if (id == null) throw TbeApiException('Opening has no stable element ID');
    await moveOpening(openingId: id, offsetMeters: offsetMeters);
    return resizeHostedOpening(
      openingId: id,
      kind: object.kindKey,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: sillHeightMeters,
    );
  }

  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  }) =>
      _requireRepository().setOpeningLevelLock(
        openingId: openingId,
        locked: locked,
      );

  Future<RenderSceneLoadResult> setOpeningLevelConstraint({
    required int openingId,
    required int levelId,
    required double levelOffsetMeters,
  }) =>
      _requireRepository().setOpeningLevelConstraint(
        openingId: openingId,
        levelId: levelId,
        levelOffsetMeters: levelOffsetMeters,
      );

  Future<RenderSceneLoadResult> updateRoofProperties({
    required int roofId,
    required int roofType,
    double? slopeDegrees,
    double? overhangMeters,
  }) =>
      _requireRepository().updateRoofProperties(
        roofId: roofId,
        roofType: roofType,
        slopeDegrees: slopeDegrees,
        overhangMeters: overhangMeters,
      );

  Future<RenderSceneLoadResult> deleteElement(int elementId) =>
      _requireRepository().deleteElement(elementId: elementId);

  Future<RenderSceneLoadResult> createLevel({
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  }) =>
      _requireCreationGateway().createLevel(
        name: name,
        elevationMeters: elevationMeters,
        defaultWallHeightMeters: defaultWallHeightMeters,
      );

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
      _requireCreationGateway().createStair(
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

  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) =>
      _requireCreationGateway().createDoor(
        name: name,
        hostWallId: hostWallId,
        offsetMeters: offsetMeters,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
      );

  Future<RenderSceneLoadResult> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) =>
      _requireCreationGateway().createWindow(
        name: name,
        hostWallId: hostWallId,
        offsetMeters: offsetMeters,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
      );

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
    int assemblyId = 0,
  }) =>
      _requireCreationGateway().createProfile(
        targetKind: targetKind,
        draftMode: draftMode,
        levelId: levelId,
        points: points,
        wallIds: wallIds,
        closed: closed,
        thicknessMeters: thicknessMeters,
        heightMeters: heightMeters,
        verticalOffsetMeters: verticalOffsetMeters,
        assemblyId: assemblyId,
      );

  Future<RenderSceneLoadResult> detectRooms() =>
      _requireCreationGateway().detectRooms();

  int? defaultAssemblyId(String kind) =>
      _requireCreationGateway().defaultAssemblyId(kind);

  ViewerAuthoringGateway _requireRepository() {
    final repository = _repository();
    if (!_engineEnabled() || repository == null) {
      throw TbeApiException('Authoritative engine is required for this edit');
    }
    return repository;
  }

  ViewerElementCreationGateway _requireCreationGateway() {
    final gateway = _creationGateway();
    if (!_engineEnabled() || gateway == null) {
      throw TbeApiException('Authoritative engine is required for this edit');
    }
    return gateway;
  }
}
