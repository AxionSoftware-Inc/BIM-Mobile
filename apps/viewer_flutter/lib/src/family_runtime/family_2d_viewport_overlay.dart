import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../render_scene_models.dart';
import '../render_scene_viewport_controller.dart';
import '../render_scene_viewport_projection.dart';
import '../render_scene_viewport_types.dart';
import '../workspace_view_runtime_context.dart';
import 'family_instance_store.dart';
import 'family_render_batches.dart';
import 'family_representation.dart';
import 'family_runtime_scene_cache.dart';
import 'family_spatial_streaming.dart';

/// Lightweight family overlay for floor/elevation/section views.
///
/// IMPORTANT RUNTIME CONTRACT:
/// - this path never requests FamilyViewRepresentation.model3d;
/// - view radius follows the actual planar camera, not total project bounds;
/// - Android top-down is already painted by NativeSelectionOverlay, so Flutter
///   must not draw the same family symbol a second time;
/// - SVG is an optional source encoding only. Generated/compact-vector/bounds
///   representations use the same batched placement path.
class Family2dViewportOverlay extends StatelessWidget {
  const Family2dViewportOverlay({
    super.key,
    required this.controller,
  });

  final RenderSceneViewportController controller;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    if (scene == null || !WorkspaceViewRuntimeContext.isTwoDimensional) {
      return const SizedBox.shrink();
    }

    // The Android native top-down renderer already owns family plan symbols
    // and deliberately suppresses their 3D mesh. Drawing this Flutter overlay
    // on top would double strokes and double per-frame projection work. Keep
    // Flutter as the fallback renderer and as the elevation/section path.
    final nativeAndroidPlan =
        defaultTargetPlatform == TargetPlatform.android &&
            controller.backend == RenderSceneViewportBackend.native &&
            WorkspaceViewRuntimeContext.kind ==
                WorkspaceRuntimeViewKind.floorPlan;
    if (nativeAndroidPlan) return const SizedBox.shrink();

    final runtime = FamilyRuntimeSceneCache.forScene(scene);
    if (runtime.store.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              constraints.maxWidth.isFinite
                  ? math.max(constraints.maxWidth, 1)
                  : 1,
              constraints.maxHeight.isFinite
                  ? math.max(constraints.maxHeight, 1)
                  : 1,
            );
            final center = controller.planCamera.center;
            final visible = runtime.spatialIndex.queryCamera(
              FamilyStreamingCamera(
                x: center.x,
                y: center.y,
                z: center.z,
                forwardX: 1,
                forwardY: 0,
                forwardZ: 0,
              ),
              // Use the actual screen coverage. A fixed 400 m radius either
              // omitted visible families in a zoomed-out campus or queried far
              // too much data in a close room plan.
              radiusMeters: _queryRadius(size),
              rearDotThreshold: -1,
              levelId: WorkspaceViewRuntimeContext.kind ==
                          WorkspaceRuntimeViewKind.floorPlan &&
                      WorkspaceViewRuntimeContext.levelId != 0
                  ? WorkspaceViewRuntimeContext.levelId
                  : null,
              maxResults: 100000,
            );
            final view = switch (WorkspaceViewRuntimeContext.kind) {
              WorkspaceRuntimeViewKind.floorPlan =>
                FamilyViewRepresentation.plan2d,
              WorkspaceRuntimeViewKind.elevation =>
                FamilyViewRepresentation.elevation2d,
              WorkspaceRuntimeViewKind.section =>
                FamilyViewRepresentation.section2d,
              _ => FamilyViewRepresentation.plan2d,
            };
            final plan = FamilyRenderBatchPlanner.plan(
              store: runtime.store,
              visibleInstanceIndices: visible,
              view: view,
            );
            return CustomPaint(
              size: size,
              painter: _Family2dPainter(
                controller: controller,
                store: runtime.store,
                plan: plan,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          },
        ),
      ),
    );
  }

  double _queryRadius(Size size) {
    final zoom = controller.planCamera.zoom;
    if (!zoom.isFinite || zoom <= 1e-6) return 180.0;
    final halfDiagonalPixels =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.5;
    // 35% margin keeps symbols resident just outside the screen during a pan,
    // avoiding visible pop-in without querying the whole project.
    return math.max(24.0, halfDiagonalPixels / zoom * 1.35).toDouble();
  }
}

final class _Family2dPainter extends CustomPainter {
  _Family2dPainter({
    required this.controller,
    required this.store,
    required this.plan,
    required this.color,
  });

  final RenderSceneViewportController controller;
  final FamilyInstanceStore store;
  final FamilyRenderPlan plan;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.twoDimensionalBatches.isEmpty) return;
    final projection = RenderSceneProjection(
      sceneBounds: controller.sceneBounds,
      canvasSize: size,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: 48,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (final batch in plan.twoDimensionalBatches) {
      for (final instanceIndex in batch.instanceIndices) {
        if (instanceIndex >= store.length) continue;
        _paintInstance(canvas, projection, instanceIndex, batch.encoding, paint);
      }
    }
  }

  void _paintInstance(
    Canvas canvas,
    RenderSceneProjection projection,
    int instanceIndex,
    Family2dEncoding encoding,
    Paint paint,
  ) {
    final position = store.positionAt(instanceIndex);
    final extent = store.halfExtentAt(instanceIndex);
    final min = RenderScenePoint(
      x: position.x - extent.x,
      y: position.y - extent.y,
      z: position.z - extent.z,
    );
    final max = RenderScenePoint(
      x: position.x + extent.x,
      y: position.y + extent.y,
      z: position.z + extent.z,
    );
    final a = projection.project(min).screen;
    final b = projection.project(max).screen;
    final rect = Rect.fromPoints(a, b);
    if (!rect.overlaps(Offset.zero & projection.canvasSize)) return;

    // Runtime asset decoding is deliberately separate from placement rows.
    // Until compact-vector/SVG cache payloads are attached, every encoding has
    // a cheap semantic fallback rather than loading the 3D family mesh.
    switch (encoding) {
      case Family2dEncoding.generated:
      case Family2dEncoding.compactVector:
      case Family2dEncoding.svg:
      case Family2dEncoding.boundsProxy:
        canvas.drawRect(rect, paint);
        final center = rect.center;
        canvas.drawLine(
          Offset(rect.left, center.dy),
          Offset(rect.right, center.dy),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _Family2dPainter oldDelegate) =>
      oldDelegate.store != store ||
      oldDelegate.controller.sceneRevision != controller.sceneRevision ||
      oldDelegate.controller.fitRevision != controller.fitRevision ||
      oldDelegate.controller.planCamera != controller.planCamera ||
      oldDelegate.controller.projectionMode != controller.projectionMode ||
      oldDelegate.color != color;
}
