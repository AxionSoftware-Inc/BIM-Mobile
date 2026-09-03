import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed roof instance values. Shape and slope are roof-owned, not Inspector
/// metadata guessed by the common property surface.
final class RoofElementParameters {
  const RoofElementParameters({
    required this.assemblyId,
    required this.levelId,
    required this.roofType,
    required this.slopeDegrees,
    required this.overhangMeters,
  });

  factory RoofElementParameters.fromObject(RenderSceneObject object) {
    final roofTypeName = elementParameterText(object, 'roof_type');
    final roofType = roofTypeName == 'SimpleGable'
        ? 1
        : roofTypeName == 'AutoFootprint'
            ? 2
            : 0;
    return RoofElementParameters(
      assemblyId: elementParameterInt(object, 'assembly_id') ?? 0,
      levelId: object.levelId,
      roofType: roofType,
      slopeDegrees: elementParameterDouble(object, 'slope_degrees'),
      overhangMeters: elementParameterDouble(object, 'overhang_meters'),
    );
  }

  final int assemblyId;
  final int? levelId;
  final int roofType;
  final double? slopeDegrees;
  final double? overhangMeters;
}
