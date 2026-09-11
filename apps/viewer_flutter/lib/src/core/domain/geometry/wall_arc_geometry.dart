import 'dart:math' as math;

import '../render_scene/render_scene_geometry.dart';

/// Renderer- and UI-neutral circular wall geometry shared by engine ports and
/// authoring use-cases.
///
/// The sampled [points] are a preview/polyline representation. Authoritative
/// native mutations use the semantic center/radius/sweep fields instead of
/// treating those samples as independent wall segments.
class WallArcGeometry {
  const WallArcGeometry({
    required this.center,
    required this.start,
    required this.end,
    required this.radiusMeters,
    required this.sweepRadians,
    required this.points,
  });

  final RenderScenePoint center;
  final RenderScenePoint start;
  final RenderScenePoint end;
  final double radiusMeters;
  final double sweepRadians;
  final List<RenderScenePoint> points;

  double get sweepDegrees => sweepRadians * 180.0 / math.pi;
}
