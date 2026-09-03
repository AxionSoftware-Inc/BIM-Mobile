import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed hosted-opening values shared by door and window Inspector adapters.
final class OpeningElementParameters {
  const OpeningElementParameters({
    required this.hostWallId,
    required this.levelId,
    required this.offsetMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.levelOffsetMeters,
    required this.levelLocked,
  });

  factory OpeningElementParameters.fromObject(RenderSceneObject object) =>
      OpeningElementParameters(
        hostWallId: elementParameterInt(object, 'host_wall_id'),
        levelId: object.levelId,
        offsetMeters: elementParameterDouble(object, 'offset_meters'),
        widthMeters: elementParameterDouble(object, 'width_meters'),
        heightMeters: elementParameterDouble(object, 'height_meters'),
        sillHeightMeters: elementParameterDouble(object, 'sill_height_meters'),
        levelOffsetMeters:
            elementParameterDouble(object, 'level_offset_meters') ?? 0,
        levelLocked:
            elementParameterBool(object, 'level_locked', fallback: true),
      );

  final int? hostWallId;
  final int? levelId;
  final double? offsetMeters;
  final double? widthMeters;
  final double? heightMeters;
  final double? sillHeightMeters;
  final double levelOffsetMeters;
  final bool levelLocked;
}
