import '../render_scene_editor.dart';
import '../render_scene_models.dart';
import '../render_scene_viewport_types.dart';
import 'plan_sketch_geometry.dart';

/// Pure profile rules shared by floor, ceiling and roof authoring.
///
/// The viewport only owns gesture routing. Rectangle/polyline/picked-wall
/// profiles and their validation live here so a sheet, section or future
/// authoring host can reuse exactly the same footprint rules.
final class SurfaceAuthoringGeometry {
  const SurfaceAuthoringGeometry._();

  static List<RenderScenePoint> previewPoints({
    required RenderSceneSurfaceDrawMode mode,
    RenderScenePoint? start,
    RenderScenePoint? end,
    List<RenderScenePoint> points = const <RenderScenePoint>[],
  }) {
    switch (mode) {
      case RenderSceneSurfaceDrawMode.rectangle:
      case RenderSceneSurfaceDrawMode.pickWalls:
        if (start == null || end == null) {
          return const <RenderScenePoint>[];
        }
        return PlanSketchGeometry.rectangle(start, end);
      case RenderSceneSurfaceDrawMode.polyline:
        return List<RenderScenePoint>.from(points);
      case RenderSceneSurfaceDrawMode.autoRoom:
        return const <RenderScenePoint>[];
    }
  }

  static bool previewIsClosed({
    required RenderSceneSurfaceDrawMode mode,
    required List<RenderScenePoint> points,
  }) {
    return mode != RenderSceneSurfaceDrawMode.polyline || points.length >= 3;
  }

  static List<RenderScenePoint> profilePoints({
    required RenderSceneSurfaceDrawMode mode,
    RenderScenePoint? start,
    RenderScenePoint? end,
    List<RenderScenePoint> points = const <RenderScenePoint>[],
  }) {
    switch (mode) {
      case RenderSceneSurfaceDrawMode.rectangle:
        return start == null || end == null
            ? const <RenderScenePoint>[]
            : <RenderScenePoint>[start, end];
      case RenderSceneSurfaceDrawMode.polyline:
        return List<RenderScenePoint>.from(points);
      case RenderSceneSurfaceDrawMode.pickWalls:
      case RenderSceneSurfaceDrawMode.autoRoom:
        return const <RenderScenePoint>[];
    }
  }

  static bool isUsableRectangle(
    RenderScenePoint? start,
    RenderScenePoint? end,
  ) {
    if (start == null || end == null) return false;
    return (end.x - start.x).abs() >= 0.1 && (end.y - start.y).abs() >= 0.1;
  }

  static RenderSceneBounds? rectangleBounds(
    RenderScenePoint? start,
    RenderScenePoint? end,
  ) {
    if (!isUsableRectangle(start, end)) return null;
    return RenderSceneBounds.normalized(
      min: RenderScenePoint(
        x: start!.x < end!.x ? start.x : end.x,
        y: start.y < end.y ? start.y : end.y,
        z: 0,
      ),
      max: RenderScenePoint(
        x: start.x > end.x ? start.x : end.x,
        y: start.y > end.y ? start.y : end.y,
        z: 0,
      ),
    );
  }

  static List<RenderScenePoint>? wallBoundaryPolygon(
    RenderScene scene,
    Iterable<int> wallIds, {
    double toleranceMeters = 0.45,
  }) {
    final walls = scene.objects
        .where((object) => wallIds.contains(object.elementId))
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    return RenderSceneEditor.surfacePolygonForWalls(
      walls,
      toleranceMeters: toleranceMeters,
    );
  }
}
