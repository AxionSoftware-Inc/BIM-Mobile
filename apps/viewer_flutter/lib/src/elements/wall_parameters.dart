import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed authored values owned by the wall element boundary.
final class WallElementParameters {
  const WallElementParameters({
    required this.baseLevelId,
    required this.topLevelId,
    required this.wallTypeId,
    required this.heightMode,
    required this.baseOffsetMeters,
    required this.topOffsetMeters,
    required this.thicknessMeters,
    required this.heightMeters,
    required this.lengthMeters,
    required this.layerProfile,
    required this.wallTypeCategory,
  });

  factory WallElementParameters.fromObject(RenderSceneObject object) =>
      WallElementParameters(
        baseLevelId:
            elementParameterInt(object, 'base_level_id') ?? object.levelId,
        topLevelId: elementParameterInt(object, 'top_level_id'),
        wallTypeId: elementParameterInt(object, 'wall_type_id') ?? 0,
        heightMode: elementParameterText(object, 'height_mode'),
        baseOffsetMeters:
            elementParameterDouble(object, 'base_offset_meters') ?? 0,
        topOffsetMeters:
            elementParameterDouble(object, 'top_offset_meters') ?? 0,
        thicknessMeters:
            elementParameterDouble(object, 'thickness_meters') ?? 0,
        heightMeters: elementParameterDouble(object, 'height_meters'),
        lengthMeters: elementParameterDouble(object, 'length_meters') ?? 0,
        layerProfile: elementParameterText(object, 'layer_profile'),
        wallTypeCategory: elementParameterText(object, 'wall_type_category'),
      );

  final int? baseLevelId;
  final int? topLevelId;
  final int wallTypeId;
  final String? heightMode;
  final double baseOffsetMeters;
  final double topOffsetMeters;
  final double thicknessMeters;
  final double? heightMeters;
  final double lengthMeters;
  final String? layerProfile;
  final String? wallTypeCategory;

  bool get hasExplicitHeightMode => heightMode != null;

  bool get isTopConnected {
    final mode = heightMode?.toLowerCase();
    if (mode == 'unconnected') return false;
    if (mode == 'toplevel') return true;
    return topLevelId != null && topLevelId != 0;
  }

  int get layerCount => layerProfile == null
      ? 0
      : layerProfile!.split(';').where((layer) => layer.isNotEmpty).length;
}
