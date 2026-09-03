import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed parameters for floor/slab and ceiling surface instances.
final class SurfaceElementParameters {
  const SurfaceElementParameters({
    required this.assemblyId,
    required this.levelId,
    required this.areaSquareMeters,
    required this.thicknessMeters,
    required this.verticalOffsetMeters,
    required this.typeName,
  });

  factory SurfaceElementParameters.fromObject(RenderSceneObject object) =>
      SurfaceElementParameters(
        assemblyId: elementParameterInt(object, 'assembly_id') ?? 0,
        levelId: object.levelId,
        areaSquareMeters: elementParameterDouble(object, 'area_m2'),
        thicknessMeters: elementParameterDouble(object, 'thickness_meters'),
        verticalOffsetMeters:
            elementParameterDouble(object, 'vertical_offset_meters'),
        typeName: elementParameterText(object, 'floor_type_name'),
      );

  final int assemblyId;
  final int? levelId;
  final double? areaSquareMeters;
  final double? thicknessMeters;
  final double? verticalOffsetMeters;
  final String? typeName;
}
