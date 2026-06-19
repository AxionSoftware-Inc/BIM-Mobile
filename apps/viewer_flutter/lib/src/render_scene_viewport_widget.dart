import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_painter.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

class RenderSceneViewport extends StatefulWidget {
  const RenderSceneViewport({
    super.key,
    required this.controller,
    this.interactionMode = RenderSceneInteractionMode.select,
    this.onSceneTap,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;

  @override
  State<RenderSceneViewport> createState() => _RenderSceneViewportState();
}

class _RenderSceneViewportState extends State<RenderSceneViewport> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant RenderSceneViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _shouldUseNativeAndroidView {
    return widget.controller.backend == RenderSceneViewportBackend.native &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.controller.scene;
    if (scene == null) {
      return const Center(
        child: Text('Load a RenderScene sample to preview the viewport.'),
      );
    }

    if (_shouldUseNativeAndroidView) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _AndroidRenderSceneView(controller: widget.controller),
          Positioned(
            left: 12,
            bottom: 12,
            child: _ViewportNoteCard(
              message:
                  'Native Filament viewport. Drag to orbit. Use Fit to recenter.',
              color: Colors.black.withValues(alpha: 0.78),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _ViewportStatsCard(scene: scene, native: true),
          ),
        ],
      );
    }

    return _FallbackRenderSceneView(
      controller: widget.controller,
      interactionMode: widget.interactionMode,
      onSceneTap: widget.onSceneTap,
    );
  }
}

class _AndroidRenderSceneView extends StatelessWidget {
  const _AndroidRenderSceneView({
    required this.controller,
  });

  final RenderSceneViewportController controller;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    final creationParams = <String, Object?>{
      'sceneRevision': controller.sceneRevision,
      if (scene != null) 'renderSceneJson': jsonEncode(scene.toJson()),
      'visibleKinds': controller.visibleKinds.toList(),
      'selectedElementId': controller.selectedElementId,
      'highlightedElementId': controller.highlightedElementId,
      'displayStyle': controller.displayStyle.name,
    };

    return AndroidView(
      key: ValueKey<int>(controller.sceneRevision),
      viewType: 'tbe/render_scene_view',
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: controller.attachNativeBridge,
    );
  }
}

class _FallbackRenderSceneView extends StatefulWidget {
  const _FallbackRenderSceneView({
    required this.controller,
    required this.interactionMode,
    required this.onSceneTap,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;

  @override
  State<_FallbackRenderSceneView> createState() =>
      _FallbackRenderSceneViewState();
}

class _FallbackRenderSceneViewState extends State<_FallbackRenderSceneView> {
  Offset? _lastPointerPosition;
  Offset? _pointerDownPosition;
  int? _activePointer;
  bool _isSecondaryDrag = false;
  int _activePointerCount = 0;
  double _gesturePreviousScale = 1.0;
  Offset? _gesturePreviousFocalPoint;
  double _trackpadPreviousScale = 1.0;

  RenderSceneViewportController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final scene = controller.scene;
    if (scene == null) {
      return const Center(
        child: Text('Load a RenderScene sample to preview the viewport.'),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        controller.setViewportSize(size);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (ScaleStartDetails details) {
            _gesturePreviousScale = 1.0;
            _gesturePreviousFocalPoint = details.localFocalPoint;
          },
          onScaleUpdate: (ScaleUpdateDetails details) {
            if (details.pointerCount < 2) {
              return;
            }

            final previousFocal =
                _gesturePreviousFocalPoint ?? details.localFocalPoint;
            final focalDelta = details.localFocalPoint - previousFocal;
            final scaleDelta =
                (details.scale / _gesturePreviousScale).clamp(0.5, 1.5);

            if (controller.projectionMode ==
                RenderSceneProjectionMode.topDown) {
              if (focalDelta.distanceSquared > 0.0) {
                controller.panPlanBy(focalDelta);
              }
              controller.zoomPlanBy(
                scaleDelta,
                focalPoint: details.localFocalPoint,
                viewportSize: size,
              );
            } else {
              // In 3D, pinch should behave like a plain zoom. Mixing focal-point
              // drift into orbit panning makes the camera target jump around and
              // feels like a model-viewer instead of a workspace camera.
              controller.zoomOrbit(scaleDelta);
            }

            _gesturePreviousScale = details.scale;
            _gesturePreviousFocalPoint = details.localFocalPoint;
          },
          onScaleEnd: (_) {
            _gesturePreviousScale = 1.0;
            _gesturePreviousFocalPoint = null;
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (PointerSignalEvent event) {
              if (event is! PointerScrollEvent) {
                return;
              }

              final scaleDelta = event.scrollDelta.dy > 0 ? 0.90 : 1.10;
              if (controller.projectionMode ==
                  RenderSceneProjectionMode.topDown) {
                controller.zoomPlanBy(
                  scaleDelta,
                  focalPoint: event.localPosition,
                  viewportSize: size,
                );
              } else {
                controller.zoomOrbit(scaleDelta);
              }
            },
            onPointerDown: (PointerDownEvent event) {
              _activePointerCount += 1;
              _activePointer = event.pointer;
              _pointerDownPosition = event.localPosition;
              _lastPointerPosition = event.localPosition;
              _isSecondaryDrag = event.buttons == kSecondaryMouseButton ||
                  event.buttons == kMiddleMouseButton;
            },
            onPointerPanZoomStart: (_) {
              _trackpadPreviousScale = 1.0;
            },
            onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
              if (controller.projectionMode ==
                  RenderSceneProjectionMode.topDown) {
                if (event.panDelta.distanceSquared > 0.0) {
                  controller.panPlanBy(event.panDelta);
                }
                final scaleDelta =
                    (event.scale / _trackpadPreviousScale).clamp(0.5, 1.5);
                controller.zoomPlanBy(
                  scaleDelta,
                  focalPoint: size.center(Offset.zero),
                  viewportSize: size,
                );
                _trackpadPreviousScale = event.scale;
                return;
              }

              if (event.panDelta.distanceSquared > 0.0) {
                controller.orbitBy(
                  Offset(-event.panDelta.dx * 0.9, event.panDelta.dy * 0.9),
                  size,
                );
              }
              final scaleDelta =
                  (event.scale / _trackpadPreviousScale).clamp(0.5, 1.5);
              controller.zoomOrbit(scaleDelta);
              _trackpadPreviousScale = event.scale;
            },
            onPointerPanZoomEnd: (_) {
              _trackpadPreviousScale = 1.0;
            },
            onPointerMove: (PointerMoveEvent event) {
              if (_activePointer != event.pointer) {
                return;
              }
              if (_activePointerCount > 1) {
                _lastPointerPosition = event.localPosition;
                return;
              }

              final last = _lastPointerPosition;
              if (last == null) {
                _lastPointerPosition = event.localPosition;
                return;
              }

              final delta = event.localPosition - last;
              if (controller.projectionMode ==
                  RenderSceneProjectionMode.topDown) {
                controller.panPlanBy(delta);
              } else if (_isSecondaryDrag) {
                controller.panOrbitBy(delta, size);
              } else {
                controller.orbitBy(delta, size);
              }

              _lastPointerPosition = event.localPosition;
            },
            onPointerUp: (PointerUpEvent event) async {
              if (_activePointerCount > 0) {
                _activePointerCount -= 1;
              }

              if (_activePointer != event.pointer) {
                if (_activePointerCount <= 0) {
                  _clearPointerState();
                }
                return;
              }
              if (_activePointerCount > 0) {
                return;
              }

              final down = _pointerDownPosition;
              final moved = down == null
                  ? double.infinity
                  : (event.localPosition - down).distance;
              if (moved < 8.0) {
                final picked = pickObjectAt(
                  scene: scene,
                  size: size,
                  localPosition: event.localPosition,
                  projectionMode: controller.projectionMode,
                  orbitProjectionStyle: controller.orbitProjectionStyle,
                  planCamera: controller.planCamera,
                  camera: controller.camera,
                  visibleKinds: controller.visibleKinds,
                  padding: FallbackRenderScenePainter.padding,
                );

                final modelPoint =
                    controller.screenToModelPlan(event.localPosition, size);
                final details = RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  modelPoint: modelPoint,
                  pickedObject: picked,
                );

                if (widget.interactionMode ==
                    RenderSceneInteractionMode.select) {
                  if (picked != null) {
                    final id = picked.elementId?.toString();
                    await controller.selectElement(id);
                    await controller.highlightElement(id);
                  }
                } else {
                  widget.onSceneTap?.call(details);
                }
              }

              _clearPointerState();
            },
            onPointerCancel: (_) => _clearPointerState(),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  child: CustomPaint(
                    painter: FallbackRenderScenePainter(
                      scene: scene,
                      visibleKinds: controller.visibleKinds,
                      selectedElementId: controller.selectedElementId,
                      highlightedElementId: controller.highlightedElementId,
                      projectionMode: controller.projectionMode,
                      orbitProjectionStyle: controller.orbitProjectionStyle,
                      displayStyle: controller.displayStyle,
                      camera: controller.camera,
                      planCamera: controller.planCamera,
                      draftWallStart: controller.draftWallStart,
                      draftWallEnd: controller.draftWallEnd,
                      draftOpening: controller.draftOpening,
                    ),
                    size: Size.infinite,
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: _ViewportNoteCard(
                    message: _viewportHintText(),
                    color: Colors.black.withValues(alpha: 0.78),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: _ViewportStatsCard(scene: scene, native: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _viewportHintText() {
    switch (widget.interactionMode) {
      case RenderSceneInteractionMode.select:
        return controller.projectionMode == RenderSceneProjectionMode.topDown
            ? '2D: drag to pan, pinch/scroll to zoom, tap to select.'
            : '3D: drag to orbit, pinch to zoom, right drag to pan, touchpad 2-finger orbit.';
      case RenderSceneInteractionMode.addWall:
        return 'Add wall: tap start point, then tap end point.';
      case RenderSceneInteractionMode.addDoor:
        return 'Add door: tap a wall to pick host and offset.';
      case RenderSceneInteractionMode.addWindow:
        return 'Add window: tap a wall to pick host and offset.';
    }
  }

  void _clearPointerState() {
    _activePointer = null;
    _pointerDownPosition = null;
    _lastPointerPosition = null;
    _isSecondaryDrag = false;
    _activePointerCount = 0;
    _gesturePreviousScale = 1.0;
    _gesturePreviousFocalPoint = null;
  }
}

class _ViewportNoteCard extends StatelessWidget {
  const _ViewportNoteCard({
    required this.message,
    required this.color,
  });

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _ViewportStatsCard extends StatelessWidget {
  const _ViewportStatsCard({
    required this.scene,
    required this.native,
  });

  final RenderScene scene;
  final bool native;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.90),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                  native ? 'Renderer: Filament' : 'Renderer: Flutter fallback'),
              Text('Objects: ${scene.objectCount}'),
              Text('Vertices: ${scene.vertexCount}'),
              Text('Indices: ${scene.indexCount}'),
              Text('Triangles: ${scene.triangleCount}'),
              Text(
                'Bounds: ${scene.bounds.width.toStringAsFixed(2)} × '
                '${scene.bounds.depth.toStringAsFixed(2)} × '
                '${scene.bounds.height.toStringAsFixed(2)} m',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
