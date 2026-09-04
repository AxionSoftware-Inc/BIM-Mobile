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
    required this.layoutKind,
    required this.landingDepthMeters,
    required this.railingEnabled,
    required this.pathPointCount,
    required this.pathPoints,
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
        layoutKind: elementParameterInt(object, 'layout_kind') ?? 0,
        landingDepthMeters:
            elementParameterDouble(object, 'landing_depth_meters') ?? 0.0,
        railingEnabled: elementParameterBool(object, 'railing_enabled'),
        pathPointCount: _pathPointCount(object),
        pathPoints: _pathPoints(object),
      );

  final int? baseLevelId;
  final int? topLevelId;
  final double? widthMeters;
  final double? totalRunMeters;
  final double? totalRiseMeters;
  final int? treadCount;
  final int? riserCount;
  final int layoutKind;
  final double landingDepthMeters;
  final bool railingEnabled;
  final int pathPointCount;
  final List<RenderScenePoint> pathPoints;

  static int _pathPointCount(RenderSceneObject object) {
    final raw = object.metadata['path_points'];
    if (raw is! String || raw.trim().isEmpty) return 0;
    return raw.split(';').where((point) => point.contains(',')).length;
  }

  static List<RenderScenePoint> _pathPoints(RenderSceneObject object) {
    final raw = object.metadata['path_points'];
    if (raw is! String || raw.trim().isEmpty) {
      return const <RenderScenePoint>[];
    }
    final points = <RenderScenePoint>[];
    for (final token in raw.split(';')) {
      final coordinates = token.split(',');
      if (coordinates.length != 2) continue;
      final x = double.tryParse(coordinates[0].trim());
      final y = double.tryParse(coordinates[1].trim());
      if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
      points.add(RenderScenePoint(x: x, y: y, z: 0.0));
    }
    return List<RenderScenePoint>.unmodifiable(points);
  }
}
