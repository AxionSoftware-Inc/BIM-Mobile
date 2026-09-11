import '../../../core/application/render_scene/render_scene_models.dart';

/// Project-facing capability owned by the independent Family module.
///
/// The core authoring ports intentionally do not know about family assets or
/// family geometry. This contract is the only mutation boundary Family uses
/// to persist an instance into the project document.
abstract interface class FamilyAuthoringGateway {
  int? get lastCreatedElementId;

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
  });

  Future<RenderSceneLoadResult> updateFamilyInstance({
    required int elementId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    required List<RenderScenePoint> vertices,
    required List<int> indices,
  });
}
