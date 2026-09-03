import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed parameters for simple linear instances such as columns and beams.
final class LinearElementParameters {
  const LinearElementParameters({
    required this.heightMeters,
    required this.lengthMeters,
  });

  factory LinearElementParameters.fromObject(RenderSceneObject object) =>
      LinearElementParameters(
        heightMeters: elementParameterDouble(object, 'height_meters'),
        lengthMeters: elementParameterDouble(object, 'length_meters'),
      );

  final double? heightMeters;
  final double? lengthMeters;
}
