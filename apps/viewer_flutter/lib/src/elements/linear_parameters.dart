import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed parameters for simple linear instances such as columns and beams.
final class LinearElementParameters {
  const LinearElementParameters({
    required this.heightMeters,
    required this.lengthMeters,
    this.widthMeters,
    this.depthMeters,
  });

  factory LinearElementParameters.fromObject(RenderSceneObject object) =>
      LinearElementParameters(
        heightMeters: elementParameterDouble(object, 'height_meters'),
        lengthMeters: elementParameterDouble(object, 'length_meters'),
        widthMeters: elementParameterDouble(object, 'width_meters'),
        depthMeters: elementParameterDouble(object, 'depth_meters'),
      );

  final double? heightMeters;
  final double? lengthMeters;
  final double? widthMeters;
  final double? depthMeters;
}
