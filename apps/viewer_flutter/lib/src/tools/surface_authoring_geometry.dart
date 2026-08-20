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
    RenderScenePoint? cursor,
    bool boundaryClosed = false,
  }) {
    switch (mode) {
      case RenderSceneSurfaceDrawMode.rectangle:
      case RenderSceneSurfaceDrawMode.pickWalls:
        if (start == null || end == null) {
          return const <RenderScenePoint>[];
        }
        return PlanSketchGeometry.rectangle(start, end);
      case RenderSceneSurfaceDrawMode.polyline:
        final preview = List<RenderScenePoint>.from(points);
        if (!boundaryClosed &&
            cursor != null &&
            (preview.isEmpty || preview.last != cursor)) {
          preview.add(cursor);
        }
        return preview;
      case RenderSceneSurfaceDrawMode.autoRoom:
        return const <RenderScenePoint>[];
    }
  }

  static bool previewIsClosed({
    required RenderSceneSurfaceDrawMode mode,
    required List<RenderScenePoint> points,
    bool boundaryClosed = false,
  }) {
    return mode != RenderSceneSurfaceDrawMode.polyline || boundaryClosed;
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

  /// The boundary tool is intentionally explicit: a polygon is not ready to
  /// commit merely because it has three points. It must be closed, have a
  /// useful area, and contain no crossing segments. Keeping these rules in a
  /// pure geometry module makes the same validation available to the Flutter
  /// viewport, tests and future sheet/sketch hosts.
  static bool isValidBoundary(
    List<RenderScenePoint> points, {
    required bool closed,
    double minimumSegmentMeters = PlanSketchGeometry.minimumSegmentMeters,
  }) {
    if (!closed || points.length < 3) return false;
    for (var index = 0; index < points.length; index += 1) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      if (!current.x.isFinite ||
          !current.y.isFinite ||
          !next.x.isFinite ||
          !next.y.isFinite ||
          PlanSketchGeometry.planDistance(current, next) <
              minimumSegmentMeters) {
        return false;
      }
    }

    final area = signedArea(points).abs();
    if (area < minimumSegmentMeters * minimumSegmentMeters * 0.25) {
      return false;
    }

    for (var first = 0; first < points.length; first += 1) {
      final firstNext = (first + 1) % points.length;
      for (var second = first + 1; second < points.length; second += 1) {
        final secondNext = (second + 1) % points.length;
        // Adjacent edges share a vertex by design. The closing edge and the
        // first edge are adjacent as well, so they are skipped here.
        if (first == second || firstNext == second || secondNext == first) {
          continue;
        }
        if (segmentsIntersect(
          points[first],
          points[firstNext],
          points[second],
          points[secondNext],
        )) {
          return false;
        }
      }
    }
    return true;
  }

  static String boundaryValidationMessage(
    List<RenderScenePoint> points, {
    required bool closed,
  }) {
    if (points.length < 3) {
      return 'Kamida 3 ta boundary nuqta kerak.';
    }
    if (!closed) {
      if (!isValidBoundary(points, closed: true)) {
        return 'Konturda kesishgan yoki juda qisqa segment bor.';
      }
      return 'Avval Close contour bosing.';
    }
    if (!isValidBoundary(points, closed: true)) {
      return 'Konturda kesishgan yoki juda qisqa segment bor.';
    }
    return 'Kontur Finish uchun tayyor.';
  }

  static bool isNearFirstPoint(
    List<RenderScenePoint> points,
    RenderScenePoint point, {
    double toleranceMeters = 0.45,
  }) {
    final first = points.firstOrNull;
    return first != null &&
        PlanSketchGeometry.planDistance(first, point) <= toleranceMeters;
  }

  static double signedArea(List<RenderScenePoint> points) {
    var sum = 0.0;
    for (var index = 0; index < points.length; index += 1) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      sum += current.x * next.y - next.x * current.y;
    }
    return sum * 0.5;
  }

  static bool segmentsIntersect(
    RenderScenePoint firstStart,
    RenderScenePoint firstEnd,
    RenderScenePoint secondStart,
    RenderScenePoint secondEnd,
  ) {
    const epsilon = 1e-8;
    final firstOrientation = _orientation(
      firstStart,
      firstEnd,
      secondStart,
    );
    final secondOrientation = _orientation(
      firstStart,
      firstEnd,
      secondEnd,
    );
    final thirdOrientation = _orientation(
      secondStart,
      secondEnd,
      firstStart,
    );
    final fourthOrientation = _orientation(
      secondStart,
      secondEnd,
      firstEnd,
    );

    if (((firstOrientation > epsilon && secondOrientation < -epsilon) ||
            (firstOrientation < -epsilon && secondOrientation > epsilon)) &&
        ((thirdOrientation > epsilon && fourthOrientation < -epsilon) ||
            (thirdOrientation < -epsilon && fourthOrientation > epsilon))) {
      return true;
    }
    return firstOrientation.abs() <= epsilon &&
            _onSegment(firstStart, secondStart, firstEnd) ||
        secondOrientation.abs() <= epsilon &&
            _onSegment(firstStart, secondEnd, firstEnd) ||
        thirdOrientation.abs() <= epsilon &&
            _onSegment(secondStart, firstStart, secondEnd) ||
        fourthOrientation.abs() <= epsilon &&
            _onSegment(secondStart, firstEnd, secondEnd);
  }

  static double _orientation(
    RenderScenePoint first,
    RenderScenePoint second,
    RenderScenePoint third,
  ) {
    return (second.x - first.x) * (third.y - first.y) -
        (second.y - first.y) * (third.x - first.x);
  }

  static bool _onSegment(
    RenderScenePoint start,
    RenderScenePoint point,
    RenderScenePoint end,
  ) {
    const epsilon = 1e-8;
    return point.x >= (start.x < end.x ? start.x : end.x) - epsilon &&
        point.x <= (start.x > end.x ? start.x : end.x) + epsilon &&
        point.y >= (start.y < end.y ? start.y : end.y) - epsilon &&
        point.y <= (start.y > end.y ? start.y : end.y) + epsilon;
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
