import '../../../core/application/engine/viewer_engine_contracts.dart';
import '../../../core/application/render_scene/render_scene_models.dart';
import 'family_authoring_gateway.dart';

/// Family-only project mutation commands.
///
/// Keeping this service in the Family feature prevents the general authoring
/// service and the core engine contracts from growing family-specific methods.
final class FamilyCommandService {
  const FamilyCommandService({
    required FamilyAuthoringGateway? Function() gateway,
    required bool Function() engineEnabled,
  })  : _gateway = gateway,
        _engineEnabled = engineEnabled;

  final FamilyAuthoringGateway? Function() _gateway;
  final bool Function() _engineEnabled;

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
  }) =>
      _requireGateway().setElementFamilyReference(
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

  Future<RenderSceneLoadResult> updateFamilyInstance({
    required int elementId,
    required RenderScenePoint position,
    required double widthMeters,
    required double depthMeters,
    required double heightMeters,
    required List<RenderScenePoint> vertices,
    required List<int> indices,
  }) =>
      _requireGateway().updateFamilyInstance(
        elementId: elementId,
        position: position,
        widthMeters: widthMeters,
        depthMeters: depthMeters,
        heightMeters: heightMeters,
        vertices: vertices,
        indices: indices,
      );

  FamilyAuthoringGateway _requireGateway() {
    final gateway = _gateway();
    if (!_engineEnabled() || gateway == null) {
      throw TbeApiException('Authoritative engine is required for Family edit');
    }
    return gateway;
  }
}
