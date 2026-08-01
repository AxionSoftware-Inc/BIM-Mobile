import 'render_scene_models.dart';
import 'viewer_authoring_gateway.dart';
import 'viewer_engine_contracts.dart';

/// Engine-first Inspector mutations. A command either returns a new
/// authoritative snapshot or an error; widgets never mutate local geometry.
class AuthoringCommandService {
  AuthoringCommandService({
    required ViewerAuthoringGateway? Function() repository,
    required bool Function() engineEnabled,
  })  : _repository = repository,
        _engineEnabled = engineEnabled;

  final ViewerAuthoringGateway? Function() _repository;
  final bool Function() _engineEnabled;

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
    final repository = _requireRepository();
    await repository.moveHostedOpening(
        openingId: id, offsetMeters: offsetMeters);
    return repository.resizeOpening(
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

  ViewerAuthoringGateway _requireRepository() {
    final repository = _repository();
    if (!_engineEnabled() || repository == null) {
      throw TbeApiException('Authoritative engine is required for this edit');
    }
    return repository;
  }
}
