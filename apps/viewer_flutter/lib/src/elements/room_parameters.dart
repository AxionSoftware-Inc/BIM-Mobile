import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed derived quantities exposed by room scene instances.
final class RoomElementParameters {
  const RoomElementParameters({
    required this.areaSquareMeters,
    required this.perimeterMeters,
  });

  factory RoomElementParameters.fromObject(RenderSceneObject object) =>
      RoomElementParameters(
        areaSquareMeters: elementParameterDouble(object, 'area_m2'),
        perimeterMeters: elementParameterDouble(object, 'perimeter_m'),
      );

  final double? areaSquareMeters;
  final double? perimeterMeters;
}
