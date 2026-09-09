import 'dart:math' as math;
import 'dart:ui';

import '../render_scene_models.dart';
import '../render_scene_viewport_controller.dart';
import '../render_scene_viewport_projection.dart';
import 'annotation_store.dart';

final class AnnotationHit {
  const AnnotationHit({
    required this.annotationIndex,
    required this.annotationId,
    required this.kind,
    required this.distancePixels,
  });

  final int annotationIndex;
  final int annotationId;
  final AnnotationKind kind;
  final double distancePixels;
}

/// Screen-space hit testing for persistent annotations in one active view.
///
/// The view CSR index is the first filter: a sheet with 5k annotations does not
/// scan annotations from 100 other floors. Geometry-specific payload tables are
/// mapped once per hit-test call and only the visible-view rows are evaluated.
abstract final class AnnotationHitTester {
  static AnnotationHit? hitTest({
    required AnnotationStore store,
    required int viewId,
    required RenderSceneViewportController controller,
    required Size canvasSize,
    required Offset screenPoint,
    double tolerancePixels = 14,
  }) {
    if (store.isEmpty || controller.scene == null || tolerancePixels <= 0) {
      return null;
    }
    final visible = store.queryView(viewId);
    if (visible.isEmpty) return null;

    final projection = RenderSceneProjection(
      sceneBounds: controller.sceneBounds,
      canvasSize: canvasSize,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: 48,
    );
    final dimensionRows = _rowMap(store.dimensions.annotationIndices);
    final detailRows = _rowMap(store.detailLines.annotationIndices);

    AnnotationHit? best;
    for (final annotationIndex in visible) {
      if (annotationIndex >= store.length) continue;
      if ((store.flags[annotationIndex] & AnnotationFlags.hidden) != 0) continue;
      final kind = store.kindAt(annotationIndex);
      final distance = switch (kind) {
        AnnotationKind.linearDimension => _dimensionDistance(
            store,
            dimensionRows[annotationIndex],
            projection,
            screenPoint,
          ),
        AnnotationKind.detailLine => _detailLineDistance(
            store,
            detailRows[annotationIndex],
            projection,
            screenPoint,
          ),
        _ => _anchorDistance(store, annotationIndex, projection, screenPoint),
      };
      if (!distance.isFinite || distance > tolerancePixels) continue;
      if (best == null || distance < best.distancePixels) {
        best = AnnotationHit(
          annotationIndex: annotationIndex,
          annotationId: store.annotationIds[annotationIndex],
          kind: kind,
          distancePixels: distance,
        );
      }
    }
    return best;
  }

  static double _anchorDistance(
    AnnotationStore store,
    int annotationIndex,
    RenderSceneProjection projection,
    Offset point,
  ) {
    final p = annotationIndex * 3;
    final screen = projection
        .project(RenderScenePoint(
          x: store.anchors[p],
          y: store.anchors[p + 1],
          z: store.anchors[p + 2],
        ))
        .screen;
    return (screen - point).distance;
  }

  static double _dimensionDistance(
    AnnotationStore store,
    int? row,
    RenderSceneProjection projection,
    Offset point,
  ) {
    if (row == null) return double.infinity;
    final p = row * 3;
    var a = projection
        .project(RenderScenePoint(
          x: store.dimensions.startPoints[p],
          y: store.dimensions.startPoints[p + 1],
          z: store.dimensions.startPoints[p + 2],
        ))
        .screen;
    var b = projection
        .project(RenderScenePoint(
          x: store.dimensions.endPoints[p],
          y: store.dimensions.endPoints[p + 1],
          z: store.dimensions.endPoints[p + 2],
        ))
        .screen;
    final delta = b - a;
    final length = delta.distance;
    if (length > 1e-6) {
      final normal = Offset(-delta.dy / length, delta.dx / length);
      final screenOffset = normal * (18 + store.dimensions.offsets[row] * 10);
      a += screenOffset;
      b += screenOffset;
    }
    return _distanceToSegment(point, a, b);
  }

  static double _detailLineDistance(
    AnnotationStore store,
    int? row,
    RenderSceneProjection projection,
    Offset point,
  ) {
    if (row == null) return double.infinity;
    final p = row * 3;
    final a = projection
        .project(RenderScenePoint(
          x: store.detailLines.startPoints[p],
          y: store.detailLines.startPoints[p + 1],
          z: store.detailLines.startPoints[p + 2],
        ))
        .screen;
    final b = projection
        .project(RenderScenePoint(
          x: store.detailLines.endPoints[p],
          y: store.detailLines.endPoints[p + 1],
          z: store.detailLines.endPoints[p + 2],
        ))
        .screen;
    return _distanceToSegment(point, a, b);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (length2 <= 1e-9) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / length2).clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return math.sqrt(
      math.pow(p.dx - closest.dx, 2) + math.pow(p.dy - closest.dy, 2),
    );
  }

  static Map<int, int> _rowMap(List<int> annotationIndices) {
    final rows = <int, int>{};
    for (var row = 0; row < annotationIndices.length; row++) {
      rows[annotationIndices[row]] = row;
    }
    return rows;
  }
}
