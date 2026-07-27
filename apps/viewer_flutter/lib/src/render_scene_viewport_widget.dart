import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'render_scene_editor.dart';
import 'render_scene_level_overlay.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_painter.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'viewport_interaction.dart';

class RenderSceneViewport extends StatefulWidget {
  const RenderSceneViewport({
    super.key,
    required this.controller,
    this.interactionMode = RenderSceneInteractionMode.select,
    this.onSceneTap,
    this.onSceneDragStart,
    this.onSceneDragUpdate,
    this.onSceneDragEnd,
    this.onSceneSecondaryTap,
    this.onSceneHover,
    this.onLevelElevationSubmitted,
    this.draftWallThicknessMeters =
        RenderSceneEditor.defaultWallThicknessMeters,
    this.draftWallHeightMeters = RenderSceneEditor.defaultWallHeightMeters,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragUpdate;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragEnd;
  final ValueChanged<RenderSceneTapDetails>? onSceneSecondaryTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneHover;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onLevelElevationSubmitted;
  final double draftWallThicknessMeters;
  final double draftWallHeightMeters;

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
      onSceneDragStart: widget.onSceneDragStart,
      onSceneDragUpdate: widget.onSceneDragUpdate,
      onSceneDragEnd: widget.onSceneDragEnd,
      onSceneSecondaryTap: widget.onSceneSecondaryTap,
      onSceneHover: widget.onSceneHover,
      onLevelElevationSubmitted: widget.onLevelElevationSubmitted,
      draftWallThicknessMeters: widget.draftWallThicknessMeters,
      draftWallHeightMeters: widget.draftWallHeightMeters,
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
      if (scene != null) 'renderScene': scene.toJson(),
      'visibleKinds': controller.visibleKinds.toList(),
      'selectedElementIds': controller.selectedElementIds.toList(),
      'activeElementId': controller.activeElementId,
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
    required this.onSceneDragStart,
    required this.onSceneDragUpdate,
    required this.onSceneDragEnd,
    required this.onSceneSecondaryTap,
    required this.onSceneHover,
    required this.onLevelElevationSubmitted,
    required this.draftWallThicknessMeters,
    required this.draftWallHeightMeters,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragUpdate;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragEnd;
  final ValueChanged<RenderSceneTapDetails>? onSceneSecondaryTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneHover;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onLevelElevationSubmitted;
  final double draftWallThicknessMeters;
  final double draftWallHeightMeters;

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
  bool _sceneDragStarted = false;
  Timer? _longPressTimer;
  bool _touchRectangleArmed = false;
  final ViewportInteractionController _interaction =
      ViewportInteractionController();
  Rect? _selectionRect;

  ViewportSelectionModifiers _selectionModifiers() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return ViewportSelectionModifiers.fromKeyboard(
      control: keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight) ||
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight),
      shift: keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight),
    );
  }

  double _tapDistanceThreshold(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return controller.projectionMode == RenderSceneProjectionMode.isometric
          ? 22.0
          : 18.0;
    }
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return 12.0;
    }
    return 8.0;
  }

  bool _usesTouchNavigation(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch;

  void _scheduleTouchRectangleSelect(PointerDownEvent event) {
    _longPressTimer?.cancel();
    _touchRectangleArmed = false;
    if (!_usesTouchNavigation(event) ||
        widget.interactionMode != RenderSceneInteractionMode.select) {
      return;
    }
    _longPressTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted ||
          _activePointer != event.pointer ||
          _activePointerCount != 1) {
        return;
      }
      _interaction.armRectangleSelect();
      _touchRectangleArmed =
          _interaction.intent == ViewportDragIntent.rectangleSelect;
      if (_touchRectangleArmed) {
        setState(() {});
      }
    });
  }

  RenderSceneLevel? _pickLevelAtPosition(
    RenderScene scene,
    Size size,
    Offset localPosition,
  ) {
    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: FallbackRenderScenePainter.padding,
    );
    return pickLevelOverlayAt(
      scene: scene,
      projectionMode: controller.projectionMode,
      projection: projection,
      localPosition: localPosition,
    );
  }

  Iterable<MapEntry<String, Rect>> _selectionCandidates(
    RenderScene scene,
    Size size,
  ) sync* {
    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      padding: FallbackRenderScenePainter.padding,
    );
    for (final object in scene.objectsForKinds(controller.visibleKinds)) {
      final id = object.elementId?.toString();
      if (id == null) continue;
      final b = object.bounds;
      final points = <Offset>[
        for (final x in <double>[b.min.x, b.max.x])
          for (final y in <double>[b.min.y, b.max.y])
            for (final z in <double>[b.min.z, b.max.z])
              projection.project(RenderScenePoint(x: x, y: y, z: z)).screen,
      ];
      final minX =
          points.map((point) => point.dx).reduce((a, b) => a < b ? a : b);
      final minY =
          points.map((point) => point.dy).reduce((a, b) => a < b ? a : b);
      final maxX =
          points.map((point) => point.dx).reduce((a, b) => a > b ? a : b);
      final maxY =
          points.map((point) => point.dy).reduce((a, b) => a > b ? a : b);
      yield MapEntry<String, Rect>(id, Rect.fromLTRB(minX, minY, maxX, maxY));
    }
  }

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
        RenderSceneLevel? inlineLevel;
        Offset? inlineLevelOrigin;
        if (controller.selectedLevelId != null &&
            controller.projectionMode.isElevation) {
          final projection = RenderSceneProjection(
            sceneBounds: scene.bounds,
            canvasSize: size,
            projectionMode: controller.projectionMode,
            orbitProjectionStyle: controller.orbitProjectionStyle,
            planCamera: controller.planCamera,
            camera: controller.camera,
            padding: FallbackRenderScenePainter.padding,
          );
          for (final overlay in buildLevelOverlayEntries(
            scene: scene,
            projectionMode: controller.projectionMode,
            projection: projection,
          )) {
            if (overlay.level.levelId == controller.selectedLevelId) {
              inlineLevel = overlay.level;
              inlineLevelOrigin = overlay.labelOrigin + const Offset(0, 16);
              break;
            }
          }
        }

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

            _longPressTimer?.cancel();
            _touchRectangleArmed = false;

            final previousFocal =
                _gesturePreviousFocalPoint ?? details.localFocalPoint;
            final focalDelta = details.localFocalPoint - previousFocal;
            final scaleDelta =
                (details.scale / _gesturePreviousScale).clamp(0.5, 1.5);

            if (controller.projectionMode.isPlanar) {
              if (focalDelta.distanceSquared > 0.0) {
                controller.panPlanBy(focalDelta);
              }
              controller.zoomPlanBy(
                scaleDelta,
                focalPoint: details.localFocalPoint,
                viewportSize: size,
              );
            } else {
              // Tablet two-finger gesture: pan the target and zoom together.
              if (focalDelta.distanceSquared > 0.0) {
                controller.panOrbitBy(focalDelta, size);
              }
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
              if (controller.projectionMode.isPlanar) {
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
              _sceneDragStarted = false;
              _scheduleTouchRectangleSelect(event);
              if (!_isSecondaryDrag &&
                  widget.interactionMode == RenderSceneInteractionMode.select) {
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
                _interaction.begin(
                  position: event.localPosition,
                  elementId: picked?.elementId?.toString(),
                  modifiers: _selectionModifiers(),
                  allowObjectDrag: !controller.projectionMode.is3D,
                  requireRectangleArm: _usesTouchNavigation(event),
                );
              }
              if (!_isSecondaryDrag &&
                  widget.interactionMode != RenderSceneInteractionMode.select &&
                  (widget.interactionMode ==
                          RenderSceneInteractionMode.moveWall ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveLevel ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveOpening)) {
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
                final pickedLevel =
                    _pickLevelAtPosition(scene, size, event.localPosition);
                final details = RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  globalPosition: event.position,
                  modelPoint: modelPoint,
                  pickedObject: pickedLevel != null ? null : picked,
                  pickedLevel: pickedLevel,
                );
                widget.onSceneDragStart?.call(details);
                _sceneDragStarted = true;
              }
            },
            onPointerPanZoomStart: (_) {
              _trackpadPreviousScale = 1.0;
            },
            onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
              if (controller.projectionMode.isPlanar) {
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
            onPointerHover: (PointerHoverEvent event) {
              _emitHover(scene, size, event.localPosition, event.position);
            },
            onPointerMove: (PointerMoveEvent event) {
              if (_activePointer != event.pointer) {
                return;
              }
              if (_activePointerCount > 1) {
                _longPressTimer?.cancel();
                _touchRectangleArmed = false;
                _lastPointerPosition = event.localPosition;
                return;
              }

              final last = _lastPointerPosition;
              if (last == null) {
                _lastPointerPosition = event.localPosition;
                return;
              }

              final delta = event.localPosition - last;
              if (widget.interactionMode == RenderSceneInteractionMode.select &&
                  !_isSecondaryDrag) {
                final rectangle = _interaction.update(event.localPosition);
                if (_interaction.intent == ViewportDragIntent.rectangleSelect) {
                  setState(() => _selectionRect = rectangle);
                  _lastPointerPosition = event.localPosition;
                  return;
                }
              }
              final movedFromDown = _pointerDownPosition == null
                  ? 0.0
                  : (event.localPosition - _pointerDownPosition!).distance;
              if (_usesTouchNavigation(event) &&
                  movedFromDown > _tapDistanceThreshold(event)) {
                _longPressTimer?.cancel();
                _touchRectangleArmed = false;
              }
              if (!_sceneDragStarted &&
                  widget.interactionMode == RenderSceneInteractionMode.select &&
                  !controller.projectionMode.is3D &&
                  _pointerDownPosition != null &&
                  (event.localPosition - _pointerDownPosition!).distance >
                      _tapDistanceThreshold(event)) {
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
                final pickedLevel =
                    _pickLevelAtPosition(scene, size, event.localPosition);
                widget.onSceneDragStart?.call(RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  globalPosition: event.position,
                  modelPoint: modelPoint,
                  pickedObject: pickedLevel == null ? picked : null,
                  pickedLevel: pickedLevel,
                ));
                _sceneDragStarted = true;
              }
              if (_sceneDragStarted &&
                  (widget.interactionMode ==
                          RenderSceneInteractionMode.select ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveWall ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveLevel ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveOpening)) {
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
                  globalPosition: event.position,
                  modelPoint: modelPoint,
                  pickedObject: picked,
                );
                widget.onSceneDragUpdate?.call(details);
              } else if (widget.interactionMode !=
                  RenderSceneInteractionMode.select) {
                _emitHover(scene, size, event.localPosition, event.position);
              } else if (_isSecondaryDrag) {
                controller.panOrbitBy(delta, size);
              } else if (widget.interactionMode ==
                      RenderSceneInteractionMode.select &&
                  _usesTouchNavigation(event) &&
                  !_sceneDragStarted) {
                // One finger on empty tablet space navigates the view. Objects
                // retain direct manipulation in plan/elevation through the
                // branch above.
                if (controller.projectionMode.is3D) {
                  controller.orbitBy(delta, size);
                } else {
                  controller.panPlanBy(delta);
                }
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
              if (widget.interactionMode == RenderSceneInteractionMode.select &&
                  _interaction.intent == ViewportDragIntent.rectangleSelect &&
                  _selectionRect != null) {
                final rectangle = _selectionRect!;
                // Clear the visual overlay before the controller notification.
                // Otherwise the notification schedules a frame with the old blue
                // rectangle and it appears as if the selection did not commit.
                setState(() => _selectionRect = null);
                final ids = _interaction.resolveRectangle(
                  current: ViewportSelectionState(
                    selectedElementIds: controller.selectedElementIds,
                    activeElementId: controller.activeElementId,
                  ),
                  candidates: _selectionCandidates(scene, size),
                  rect: rectangle,
                );
                await controller.selectElements(
                  ids,
                  activeElementId: ids.isEmpty ? null : ids.last,
                );
                await controller.highlightElement(controller.activeElementId);
                _clearPointerState();
                return;
              }
              if (_sceneDragStarted &&
                  (widget.interactionMode ==
                          RenderSceneInteractionMode.select ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveWall ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveLevel ||
                      widget.interactionMode ==
                          RenderSceneInteractionMode.moveOpening)) {
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
                final pickedLevel =
                    _pickLevelAtPosition(scene, size, event.localPosition);
                final details = RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  globalPosition: event.position,
                  modelPoint: modelPoint,
                  pickedObject: pickedLevel != null ? null : picked,
                  pickedLevel: pickedLevel,
                );
                widget.onSceneDragEnd?.call(details);
                _sceneDragStarted = false;
                _clearPointerState();
                return;
              }
              if (widget.interactionMode ==
                      RenderSceneInteractionMode.addWall &&
                  moved >= _tapDistanceThreshold(event)) {
                // First tap establishes the start; each following drag-release
                // produces one wall segment and continues from its endpoint.
                final details = RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  globalPosition: event.position,
                  modelPoint:
                      controller.screenToModelPlan(event.localPosition, size),
                  pickedObject: null,
                  pickedLevel:
                      _pickLevelAtPosition(scene, size, event.localPosition),
                );
                widget.onSceneTap?.call(details);
                _clearPointerState();
                return;
              }
              if (moved < _tapDistanceThreshold(event)) {
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
                final pickedLevel =
                    _pickLevelAtPosition(scene, size, event.localPosition);
                final details = RenderSceneTapDetails(
                  screenPosition: event.localPosition,
                  globalPosition: event.position,
                  modelPoint: modelPoint,
                  pickedObject: pickedLevel != null ? null : picked,
                  pickedLevel: pickedLevel,
                );

                if (_isSecondaryDrag) {
                  widget.onSceneSecondaryTap?.call(details);
                  _clearPointerState();
                  return;
                }

                if (widget.interactionMode ==
                    RenderSceneInteractionMode.select) {
                  final id = picked?.elementId?.toString();
                  final ids = _interaction.resolveClick(
                    current: ViewportSelectionState(
                      selectedElementIds: controller.selectedElementIds,
                      activeElementId: controller.activeElementId,
                      selectedLevelId: controller.selectedLevelId,
                    ),
                    elementId: id,
                  );
                  await controller.selectElements(
                    ids,
                    activeElementId: id != null && ids.contains(id)
                        ? id
                        : (ids.isEmpty ? null : ids.last),
                  );
                  await controller.highlightElement(controller.activeElementId);
                  widget.onSceneTap?.call(details);
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
                      selectedElementIds: controller.selectedElementIds,
                      activeElementId: controller.activeElementId,
                      selectedLevelId: controller.selectedLevelId,
                      selectionRect: _selectionRect,
                      highlightedElementId: controller.highlightedElementId,
                      projectionMode: controller.projectionMode,
                      orbitProjectionStyle: controller.orbitProjectionStyle,
                      displayStyle: controller.displayStyle,
                      camera: controller.camera,
                      planCamera: controller.planCamera,
                      draftWallStart: controller.draftWallStart,
                      draftWallEnd: controller.draftWallEnd,
                      draftOpening: controller.draftOpening,
                      draftSurface: controller.draftSurface,
                      draftWallThicknessMeters: widget.draftWallThicknessMeters,
                      draftWallHeightMeters: widget.draftWallHeightMeters,
                    ),
                    size: Size.infinite,
                  ),
                ),
                if (inlineLevel != null && inlineLevelOrigin != null)
                  Positioned(
                    left: inlineLevelOrigin.dx.clamp(8.0, size.width - 132.0),
                    top: inlineLevelOrigin.dy.clamp(8.0, size.height - 42.0),
                    child: _InlineLevelElevationField(
                      key: ValueKey<int>(inlineLevel.levelId),
                      level: inlineLevel,
                      onSubmitted: widget.onLevelElevationSubmitted,
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

  void _emitHover(
    RenderScene scene,
    Size size,
    Offset localPosition,
    Offset globalPosition,
  ) {
    final picked = pickObjectAt(
      scene: scene,
      size: size,
      localPosition: localPosition,
      projectionMode: controller.projectionMode,
      orbitProjectionStyle: controller.orbitProjectionStyle,
      planCamera: controller.planCamera,
      camera: controller.camera,
      visibleKinds: controller.visibleKinds,
      padding: FallbackRenderScenePainter.padding,
    );
    final details = RenderSceneTapDetails(
      screenPosition: localPosition,
      globalPosition: globalPosition,
      modelPoint: controller.screenToModelPlan(localPosition, size),
      pickedObject: picked,
    );
    widget.onSceneHover?.call(details);
  }

  String _viewportHintText() {
    switch (widget.interactionMode) {
      case RenderSceneInteractionMode.select:
        return defaultTargetPlatform == TargetPlatform.android
            ? 'Tablet: tap object to select; drag empty space to navigate; hold empty space then drag for window select; two fingers pan + zoom.'
            : controller.projectionMode.isPlanar
                ? '2D/Elevation: drag to pan, pinch/scroll to zoom, tap to select.'
                : '3D: drag to orbit, pinch to zoom, right drag to pan, touchpad 2-finger orbit.';
      case RenderSceneInteractionMode.addWall:
        return defaultTargetPlatform == TargetPlatform.android
            ? 'Wall: tap start, then press-drag and release at the endpoint. Snap/ortho preview is live.'
            : 'Add wall: tap start point, then tap end point.';
      case RenderSceneInteractionMode.addLevel:
        return 'Add level: elevation view’da ikki marta bosib level line yarating.';
      case RenderSceneInteractionMode.moveLevel:
        return 'Move level: elevation line yaqinidan ushlab vertikal suring.';
      case RenderSceneInteractionMode.addDoor:
        return 'Add door: tap a wall to place immediately with current size.';
      case RenderSceneInteractionMode.addWindow:
        return 'Add window: tap a wall to place immediately with current size.';
      case RenderSceneInteractionMode.moveWall:
        return 'Move wall: select a wall, tap to start preview, move cursor, then confirm.';
      case RenderSceneInteractionMode.moveOpening:
        return 'Move opening: select a door/window, tap to start preview, move cursor, then confirm.';
      case RenderSceneInteractionMode.addFloor:
        return 'Add floor: tap a room for instant floor, or draw/select walls.';
      case RenderSceneInteractionMode.addCeiling:
        return 'Add ceiling: tap a room for instant ceiling, or draw/select walls.';
      case RenderSceneInteractionMode.addRoof:
        return 'Add roof: draw rectangle/polyline or pick wall loop, then confirm.';
    }
  }

  void _clearPointerState() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _touchRectangleArmed = false;
    _activePointer = null;
    _pointerDownPosition = null;
    _lastPointerPosition = null;
    _isSecondaryDrag = false;
    _activePointerCount = 0;
    _gesturePreviousScale = 1.0;
    _gesturePreviousFocalPoint = null;
    _sceneDragStarted = false;
    _selectionRect = null;
    _interaction.reset();
  }
}

class _InlineLevelElevationField extends StatefulWidget {
  const _InlineLevelElevationField({
    super.key,
    required this.level,
    required this.onSubmitted,
  });

  final RenderSceneLevel level;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onSubmitted;

  @override
  State<_InlineLevelElevationField> createState() =>
      _InlineLevelElevationFieldState();
}

class _InlineLevelElevationFieldState
    extends State<_InlineLevelElevationField> {
  late final TextEditingController _controller;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.level.elevationMeters.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InlineLevelElevationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.level.elevationMeters - widget.level.elevationMeters).abs() >
        1e-6) {
      _controller.text = widget.level.elevationMeters.toStringAsFixed(2);
    }
  }

  Future<void> _commit() async {
    if (_isCommitting) {
      return;
    }
    final value = _controller.text.trim();
    if (value.isEmpty || double.tryParse(value) == null) {
      return;
    }
    setState(() => _isCommitting = true);
    try {
      await widget.onSubmitted?.call(widget.level, value);
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      child: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        textInputAction: TextInputAction.done,
        onTap: () => _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        decoration: InputDecoration(
          isDense: true,
          suffixText: 'm',
          suffixIcon: IconButton(
            tooltip: 'Apply elevation',
            onPressed: _isCommitting ? null : _commit,
            icon: _isCommitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: const OutlineInputBorder(),
        ),
      ),
    );
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
