import 'package:flutter/material.dart';

import 'render_scene_level_overlay.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

typedef RenderScenePlanPickResolver = RenderSceneObject? Function(
  RenderScenePoint modelPoint,
  Set<String> allowedKinds,
  double toleranceMeters,
);

/// Stateless hit-testing policy shared by the native-backed and fallback
/// viewport. Keeping this outside the widget prevents camera/picking rules
/// from being duplicated in pointer handlers.
class RenderSceneViewportHitTest {
  const RenderSceneViewportHitTest._();

  static const double padding = 48.0;

  static RenderSceneLevel? levelAtPosition({
    required RenderScene scene,
    required RenderSceneViewportController controller,
    required Size size,
    required Offset localPosition,
  }) {
    if (!controller.projectionMode.isElevation) return null;
    final projection = _projection(
      scene: scene,
      controller: controller,
      size: size,
    );
    return pickLevelOverlayAt(
      scene: scene,
      projectionMode: controller.projectionMode,
      projection: projection,
      localPosition: localPosition,
    );
  }

  static Iterable<MapEntry<String, Rect>> selectionCandidates({
    required RenderScene scene,
    required RenderSceneViewportController controller,
    required Size size,
  }) sync* {
    final projection = _projection(
      scene: scene,
      controller: controller,
      size: size,
    );
    for (final object in scene.objectsForKinds(controller.visibleKinds)) {
      final id = object.elementId?.toString();
      if (id == null) continue;
      final bounds = object.bounds;
      final points = <Offset>[
        for (final x in <double>[bounds.min.x, bounds.max.x])
          for (final y in <double>[bounds.min.y, bounds.max.y])
            for (final z in <double>[bounds.min.z, bounds.max.z])
              projection.project(RenderScenePoint(x: x, y: y, z: z)).screen,
      ];
      final minX = points.map((point) => point.dx).reduce(_min);
      final minY = points.map((point) => point.dy).reduce(_min);
      final maxX = points.map((point) => point.dx).reduce(_max);
      final maxY = points.map((point) => point.dy).reduce(_max);
      yield MapEntry<String, Rect>(id, Rect.fromLTRB(minX, minY, maxX, maxY));
    }
  }

  static RenderSceneObject? objectAtPosition({
    required RenderScene scene,
    required RenderSceneViewportController controller,
    required Size size,
    required Offset position,
    required RenderSceneInteractionMode interactionMode,
    required Set<String> authoringPickKinds,
    RenderScenePlanPickResolver? planPickResolver,
    bool touchFriendly = false,
  }) {
    final isPlanAuthoring = controller.projectionMode.isPlanar &&
        interactionMode != RenderSceneInteractionMode.select &&
        authoringPickKinds.isNotEmpty;

    // Authoring uses the same logical-pixel projection as the draft overlay.
    // This avoids a physical PlatformView scale mismatch selecting a nearby
    // wall on large tablet canvases.
    if (isPlanAuthoring) {
      final projected = pickObjectAt(
        scene: scene,
        size: size,
        localPosition: position,
        projectionMode: controller.projectionMode,
        orbitProjectionStyle: controller.orbitProjectionStyle,
        planCamera: controller.planCamera,
        camera: controller.camera,
        visibleKinds: controller.visibleKinds,
        padding: padding,
        allowedKinds: authoringPickKinds,
        additionalHitSlop: touchFriendly ? 24.0 : 16.0,
      );
      if (projected != null) return projected;
    }

    final resolver = planPickResolver;
    if (resolver != null && controller.projectionMode.isPlanar) {
      final modelPoint = controller.screenToModelPlan(position, size);
      if (modelPoint != null) {
        final screenTolerance = touchFriendly ? 24.0 : 10.0;
        final modelTolerance =
            (screenTolerance / controller.planCamera.zoom).clamp(0.12, 0.75);
        return resolver(
          modelPoint,
          interactionMode == RenderSceneInteractionMode.select
              ? const <String>{}
              : authoringPickKinds,
          modelTolerance,
        );
      }
    }

    return pickObjectAt(
      scene: scene,
      size: size,
      localPosition: position,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      visibleKinds: controller.visibleKinds,
      padding: padding,
      allowedKinds: interactionMode == RenderSceneInteractionMode.select
          ? const <String>{}
          : authoringPickKinds,
      additionalHitSlop: touchFriendly ? 10.0 : 0.0,
    );
  }

  static RenderSceneTapDetails details({
    required RenderScene scene,
    required RenderSceneViewportController controller,
    required Size size,
    required Offset localPosition,
    required Offset globalPosition,
    required RenderSceneInteractionMode interactionMode,
    required Set<String> authoringPickKinds,
    RenderScenePlanPickResolver? planPickResolver,
    bool touchFriendly = false,
  }) {
    final picked = objectAtPosition(
      scene: scene,
      controller: controller,
      size: size,
      position: localPosition,
      interactionMode: interactionMode,
      authoringPickKinds: authoringPickKinds,
      planPickResolver: planPickResolver,
      touchFriendly: touchFriendly,
    );
    final pickedLevel = levelAtPosition(
      scene: scene,
      controller: controller,
      size: size,
      localPosition: localPosition,
    );
    return RenderSceneTapDetails(
      screenPosition: localPosition,
      globalPosition: globalPosition,
      modelPoint: controller.screenToModelPlan(localPosition, size),
      pickedObject: pickedLevel == null ? picked : null,
      pickedLevel: pickedLevel,
    );
  }

  static RenderSceneProjection _projection({
    required RenderScene scene,
    required RenderSceneViewportController controller,
    required Size size,
  }) {
    return RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: padding,
    );
  }

  static double _min(double a, double b) => a < b ? a : b;

  static double _max(double a, double b) => a > b ? a : b;
}
