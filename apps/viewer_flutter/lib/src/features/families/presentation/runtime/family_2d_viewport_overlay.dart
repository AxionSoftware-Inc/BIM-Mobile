import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/application/render_scene/render_scene_models.dart';
import '../../../viewer/application/workspace/opened_view_tab.dart';
import '../../../viewer/presentation/viewport/render_scene_viewport_controller.dart';
import '../../../viewer/presentation/viewport/render_scene_viewport_projection.dart';
import '../../../viewer/presentation/viewport/render_scene_viewport_types.dart';
import 'family_2d_asset_library.dart';
import 'family_instance_store.dart';
import 'family_render_batches.dart';
import 'family_representation.dart';
import 'family_runtime_scene_cache.dart';
import '../../application/runtime/family_spatial_streaming.dart';

/// Lightweight family overlay for floor/elevation/section views.
///
/// IMPORTANT RUNTIME CONTRACT:
/// - this path never requests FamilyViewRepresentation.model3d;
/// - view radius follows the actual planar camera, not total project bounds;
/// - Android top-down is already painted by NativeSelectionOverlay, so Flutter
///   must not draw the same family symbol a second time;
/// - SVG is an optional source encoding only. It is compiled once per scene to
///   compact vector commands; camera frames never parse SVG or load 3D family
///   geometry just to paint a plan symbol.
class Family2dViewportOverlay extends StatelessWidget {
  const Family2dViewportOverlay({
    super.key,
    required this.controller,
    required this.activeView,
  });

  final RenderSceneViewportController controller;
  final OpenedViewTab? activeView;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    final view = activeView;
    if (scene == null || view == null || !_isTwoDimensional(view.kind)) {
      return const SizedBox.shrink();
    }

    // The Android native top-down renderer already owns family plan symbols
    // and deliberately suppresses their 3D mesh. Drawing this Flutter overlay
    // on top would double strokes and double per-frame projection work. Keep
    // Flutter as the fallback renderer and as the elevation/section path.
    final nativeAndroidPlan = defaultTargetPlatform == TargetPlatform.android &&
        controller.backend == RenderSceneViewportBackend.native &&
        view.kind == OpenedViewKind.floorPlan;
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
              levelId: view.kind == OpenedViewKind.floorPlan &&
                      view.levelId != null &&
                      view.levelId != 0
                  ? view.levelId
                  : null,
              maxResults: 100000,
            );
            final representation = switch (view.kind) {
              OpenedViewKind.floorPlan => FamilyViewRepresentation.plan2d,
              OpenedViewKind.elevation => FamilyViewRepresentation.elevation2d,
              OpenedViewKind.section => FamilyViewRepresentation.section2d,
              _ => FamilyViewRepresentation.plan2d,
            };
            final plan = FamilyRenderBatchPlanner.plan(
              store: runtime.store,
              visibleInstanceIndices: visible,
              view: representation,
            );
            return CustomPaint(
              size: size,
              painter: _Family2dPainter(
                controller: controller,
                store: runtime.store,
                assets: runtime.twoDimensionalAssets,
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

  bool _isTwoDimensional(OpenedViewKind kind) =>
      kind == OpenedViewKind.floorPlan ||
      kind == OpenedViewKind.elevation ||
      kind == OpenedViewKind.section;
}

final class _Family2dPainter extends CustomPainter {
  _Family2dPainter({
    required this.controller,
    required this.store,
    required this.assets,
    required this.plan,
    required this.color,
  });

  final RenderSceneViewportController controller;
  final FamilyInstanceStore store;
  final Family2dAssetLibrary assets;
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
        _paintInstance(
          canvas,
          projection,
          instanceIndex,
          batch.encoding,
          batch.assetKey,
          paint,
        );
      }
    }
  }

  void _paintInstance(
    Canvas canvas,
    RenderSceneProjection projection,
    int instanceIndex,
    Family2dEncoding encoding,
    String assetKey,
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

    if ((encoding == Family2dEncoding.svg ||
            encoding == Family2dEncoding.compactVector) &&
        _paintCompiledAsset(
          canvas,
          projection,
          instanceIndex,
          assetKey,
          paint,
        )) {
      return;
    }

    // Generated/bounds representations remain deliberately cheap. They do not
    // materialize a 3D family mesh merely because a 2D authored symbol is not
    // available or used an unsupported SVG curve command.
    canvas.drawRect(rect, paint);
    final center = rect.center;
    canvas.drawLine(
      Offset(rect.left, center.dy),
      Offset(rect.right, center.dy),
      paint,
    );
  }

  bool _paintCompiledAsset(
    Canvas canvas,
    RenderSceneProjection projection,
    int instanceIndex,
    String assetKey,
    Paint paint,
  ) {
    final asset = assets[assetKey];
    if (asset == null || asset.paths.isEmpty) return false;

    final position = store.positionAt(instanceIndex);
    final rotationOffset = instanceIndex * 4;
    final scaleOffset = instanceIndex * 3;
    final qz = store.rotations[rotationOffset + 2];
    final qw = store.rotations[rotationOffset + 3];
    final angle = 2.0 * math.atan2(qz, qw);
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    final scaleX = store.scales[scaleOffset];
    final scaleY = store.scales[scaleOffset + 1];

    Offset projectLocal(double localX, double localY) {
      final sx = localX * scaleX;
      final sy = localY * scaleY;
      final worldX = position.x + sx * cosAngle - sy * sinAngle;
      final worldY = position.y + sx * sinAngle + sy * cosAngle;
      return projection
          .project(
            RenderScenePoint(
              x: worldX,
              y: worldY,
              z: position.z,
            ),
          )
          .screen;
    }

    var drewAny = false;
    for (final compiledPath in asset.paths) {
      final path = Path();
      var hasPoint = false;
      for (var commandIndex = 0;
          commandIndex < compiledPath.length;
          commandIndex++) {
        final opcode = compiledPath.opcodes[commandIndex];
        final coordinateOffset = commandIndex * 2;
        switch (opcode) {
          case Family2dPathOpcode.moveTo:
            final point = projectLocal(
              compiledPath.coordinates[coordinateOffset],
              compiledPath.coordinates[coordinateOffset + 1],
            );
            path.moveTo(point.dx, point.dy);
            hasPoint = true;
          case Family2dPathOpcode.lineTo:
            final point = projectLocal(
              compiledPath.coordinates[coordinateOffset],
              compiledPath.coordinates[coordinateOffset + 1],
            );
            if (hasPoint) {
              path.lineTo(point.dx, point.dy);
            } else {
              path.moveTo(point.dx, point.dy);
              hasPoint = true;
            }
          case Family2dPathOpcode.close:
            if (hasPoint) path.close();
        }
      }
      if (!hasPoint) continue;
      canvas.drawPath(path, paint);
      drewAny = true;
    }
    return drewAny;
  }

  @override
  bool shouldRepaint(covariant _Family2dPainter oldDelegate) =>
      oldDelegate.store != store ||
      oldDelegate.assets != assets ||
      oldDelegate.controller.sceneRevision != controller.sceneRevision ||
      oldDelegate.controller.fitRevision != controller.fitRevision ||
      oldDelegate.controller.planCamera != controller.planCamera ||
      oldDelegate.controller.projectionMode != controller.projectionMode ||
      oldDelegate.color != color;
}
