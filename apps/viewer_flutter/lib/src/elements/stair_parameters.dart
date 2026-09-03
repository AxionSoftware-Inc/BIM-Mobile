import '../render_scene_models.dart';
import 'element_parameter_values.dart';

/// Typed stair instance values used by the stair Inspector adapter.
final class StairElementParameters {
  const StairElementParameters({
    required this.baseLevelId,
    required this.topLevelId,
    required this.widthMeters,
    required this.totalRunMeters,
    required this.totalRiseMeters,
    required this.treadCount,
    required this.riserCount,
  });

  factory StairElementParameters.fromObject(RenderSceneObject object) =>
      StairElementParameters(
        baseLevelId: elementParameterInt(object, 'base_level_id'),
        topLevelId: elementParameterInt(object, 'top_level_id'),
        widthMeters: elementParameterDouble(object, 'width_meters'),
        totalRunMeters: elementParameterDouble(object, 'total_run_meters'),
        totalRiseMeters: elementParameterDouble(object, 'total_rise_meters'),
        treadCount: elementParameterInt(object, 'tread_count'),
        riserCount: elementParameterInt(object, 'riser_count'),
      );

  final int? baseLevelId;
  final int? topLevelId;
  final double? widthMeters;
  final double? totalRunMeters;
  final double? totalRiseMeters;
  final int? treadCount;
  final int? riserCount;
}
