part of 'render_scene_viewport_widget.dart';

/// Android PlatformView wrapper and fallback gesture/authoring surface.
class _AndroidRenderSceneView extends StatelessWidget {
  const _AndroidRenderSceneView({
    required this.controller,
  });

  final RenderSceneViewportController controller;

  @override
  Widget build(BuildContext context) {
    final nativeClipOwnsInteraction = controller.nativeOwnsClipGestures;
    return AndroidView(
      viewType: 'tbe/render_scene_view',
      layoutDirection: TextDirection.ltr,
      // Scene transfer is intentionally deferred to the per-view channel as
      // JSON. StandardMessageCodec creation payloads proved unreliable for
      // deeply nested mesh arrays on several Android devices.
      creationParams: const <String, Object?>{},
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers:
          nativeClipOwnsInteraction || controller.projectionMode.is3D
              ? <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                }
              : const <Factory<OneSequenceGestureRecognizer>>{},
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
    required this.authoringPickKinds,
    required this.directSurfaceDrag,
    required this.planPickResolver,
    required this.onLevelElevationSubmitted,
    required this.draftSurfaceWallIds,
    required this.draftWallThicknessMeters,
    required this.draftWallHeightMeters,
    this.rendererChild,
    this.nativeRenderer = false,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragUpdate;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragEnd;
  final ValueChanged<RenderSceneTapDetails>? onSceneSecondaryTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneHover;
  final Set<String> authoringPickKinds;
  final bool directSurfaceDrag;
  final RenderScenePlanPickResolver? planPickResolver;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onLevelElevationSubmitted;
  final Set<int> draftSurfaceWallIds;
  final double draftWallThicknessMeters;
  final double draftWallHeightMeters;
  final Widget? rendererChild;
  final bool nativeRenderer;

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
  bool _sceneDragStarted = false;
  Timer? _longPressTimer;
  bool _touchRectangleArmed = false;
  final ViewportInteractionController _interaction =
      ViewportInteractionController();
  final ViewportGestureController _gesture = ViewportGestureController();

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
  ) =>
      RenderSceneViewportHitTest.levelAtPosition(
        scene: scene,
        controller: controller,
        size: size,
        localPosition: localPosition,
      );

  Iterable<MapEntry<String, Rect>> _selectionCandidates(
    RenderScene scene,
    Size size,
  ) =>
      RenderSceneViewportHitTest.selectionCandidates(
        scene: scene,
        controller: controller,
        size: size,
      );

  RenderSceneObject? _pickObject(
    RenderScene scene,
    Size size,
    Offset position, {
    bool touchFriendly = false,
  }) =>
      RenderSceneViewportHitTest.objectAtPosition(
        scene: scene,
        controller: controller,
        size: size,
        position: position,
        interactionMode: widget.interactionMode,
        authoringPickKinds: widget.authoringPickKinds,
        planPickResolver: widget.planPickResolver,
        touchFriendly: touchFriendly,
      );

  RenderSceneTapDetails _sceneDetails(
    RenderScene scene,
    Size size,
    Offset localPosition,
    Offset globalPosition, {
    bool touchFriendly = false,
  }) =>
      RenderSceneViewportHitTest.details(
        scene: scene,
        controller: controller,
        size: size,
        localPosition: localPosition,
        globalPosition: globalPosition,
        interactionMode: widget.interactionMode,
        authoringPickKinds: widget.authoringPickKinds,
        planPickResolver: widget.planPickResolver,
        touchFriendly: touchFriendly,
      );

  RenderSceneViewportController get controller => widget.controller;

  bool get _usesDirectAuthoringDrag => switch (widget.interactionMode) {
        RenderSceneInteractionMode.addWall ||
        RenderSceneInteractionMode.addStair ||
        RenderSceneInteractionMode.addDoor ||
        RenderSceneInteractionMode.addWindow =>
          true,
        RenderSceneInteractionMode.addFloor ||
        RenderSceneInteractionMode.addCeiling ||
        RenderSceneInteractionMode.addRoof =>
          widget.directSurfaceDrag,
        _ => false,
      };

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
        final nativeOwnedInteraction = controller.nativeOwnsClipGestures;
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
            _gesture.handleScaleStart(
              details,
              target: controller,
              nativeOwned: nativeOwnedInteraction,
            );
          },
          onScaleUpdate: (ScaleUpdateDetails details) {
            _longPressTimer?.cancel();
            _touchRectangleArmed = false;
            _gesture.handleScaleUpdate(
              details,
              target: controller,
              viewportSize: size,
              nativeOwned: nativeOwnedInteraction,
            );
          },
          onScaleEnd: (_) {
            _gesture.handleScaleEnd(nativeOwned: nativeOwnedInteraction);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (PointerSignalEvent event) {
              _gesture.handlePointerSignal(
                event,
                target: controller,
                viewportSize: size,
                nativeOwned: nativeOwnedInteraction,
              );
            },
            onPointerDown: (PointerDownEvent event) {
              if (nativeOwnedInteraction) {
                // The 3D Section Box stays native, but keep enough pointer
                // state to route a stationary one-finger tap through the
                // shared Flutter picker. Planar section views never enter
                // this branch: Flutter owns their camera gestures.
                _activePointerCount += 1;
                _activePointer = event.pointer;
                _pointerDownPosition = event.localPosition;
                _lastPointerPosition = event.localPosition;
                _isSecondaryDrag = event.buttons == kSecondaryMouseButton ||
                    event.buttons == kMiddleMouseButton;
                return;
              }
              _activePointerCount += 1;
              if (_activePointerCount > 1) {
                // A second finger belongs to pan/zoom navigation. Cancel the
                // active one-finger authoring gesture so lifting the second
                // finger cannot accidentally finish a boundary or rectangle.
                _longPressTimer?.cancel();
                _touchRectangleArmed = false;
                if (_usesDirectAuthoringDrag) {
                  _sceneDragStarted = false;
                }
              }
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
              if (!_isSecondaryDrag && _usesDirectAuthoringDrag) {
                widget.onSceneDragStart?.call(_sceneDetails(
                  scene,
                  size,
                  event.localPosition,
                  event.position,
                  touchFriendly: _usesTouchNavigation(event),
                ));
                _sceneDragStarted = true;
              } else if (!_isSecondaryDrag &&
                  widget.interactionMode != RenderSceneInteractionMode.select) {
                // Touch has no hover state. Resolve the candidate immediately
                // on contact so Pick Wall/Room and hosted openings get the
                // same live preview a mouse user receives before clicking.
                _emitHover(
                  scene,
                  size,
                  event.localPosition,
                  event.position,
                  touchFriendly: _usesTouchNavigation(event),
                );
              }
            },
            onPointerPanZoomStart: (_) {
              _gesture.handleTrackpadStart(
                nativeOwned: nativeOwnedInteraction,
              );
            },
            onPointerPanZoomUpdate: (PointerPanZoomUpdateEvent event) {
              _gesture.handleTrackpadUpdate(
                event,
                target: controller,
                viewportSize: size,
                nativeOwned: nativeOwnedInteraction,
              );
            },
            onPointerPanZoomEnd: (_) {
              _gesture.handleTrackpadEnd(
                nativeOwned: nativeOwnedInteraction,
              );
            },
            onPointerHover: (PointerHoverEvent event) {
              _emitHover(scene, size, event.localPosition, event.position);
            },
            onPointerMove: (PointerMoveEvent event) {
              if (nativeOwnedInteraction) {
                _lastPointerPosition = event.localPosition;
                return;
              }
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
                  controller.setSelectionRectangle(
                    rectangle,
                    crossing: _interaction.isCrossingSelection,
                  );
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
                          RenderSceneInteractionMode.moveOpening ||
                      _usesDirectAuthoringDrag)) {
                widget.onSceneDragUpdate?.call(_sceneDetails(
                  scene,
                  size,
                  event.localPosition,
                  event.position,
                  touchFriendly: _usesTouchNavigation(event),
                ));
              } else if (widget.interactionMode !=
                  RenderSceneInteractionMode.select) {
                _emitHover(
                  scene,
                  size,
                  event.localPosition,
                  event.position,
                  touchFriendly: _usesTouchNavigation(event),
                );
              } else if (_isSecondaryDrag) {
                _gesture.handleSecondaryDrag(
                  delta,
                  target: controller,
                  viewportSize: size,
                  nativeOwned: nativeOwnedInteraction,
                );
              }

              _lastPointerPosition = event.localPosition;
            },
            onPointerUp: (PointerUpEvent event) async {
              if (nativeOwnedInteraction) {
                final down = _pointerDownPosition;
                final moved = down == null
                    ? double.infinity
                    : (event.localPosition - down).distance;
                if (_activePointer == event.pointer &&
                    _activePointerCount <= 1 &&
                    !_isSecondaryDrag &&
                    moved < _tapDistanceThreshold(event)) {
                  widget.onSceneTap?.call(_sceneDetails(
                    scene,
                    size,
                    event.localPosition,
                    event.position,
                    touchFriendly: _usesTouchNavigation(event),
                  ));
                }
                _clearPointerState();
                return;
              }
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
                  controller.selectionRectangle != null) {
                final rectangle = controller.selectionRectangle!;
                // Clear the visual overlay before the controller notification.
                // Otherwise the notification schedules a frame with the old blue
                // rectangle and it appears as if the selection did not commit.
                controller.setSelectionRectangle(null);
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
                          RenderSceneInteractionMode.moveOpening ||
                      _usesDirectAuthoringDrag)) {
                widget.onSceneDragEnd?.call(_sceneDetails(
                  scene,
                  size,
                  event.localPosition,
                  event.position,
                  touchFriendly: _usesTouchNavigation(event),
                ));
                _sceneDragStarted = false;
                _clearPointerState();
                return;
              }
              // The native 3D renderer owns the exact live Filament camera.
              // Its ray picker reports the front-most triangle through the
              // platform channel. A second Flutter projection pick here can
              // overwrite that result with an object behind the touched face.
              if (widget.nativeRenderer && controller.projectionMode.is3D) {
                if (moved < _tapDistanceThreshold(event)) {
                  await controller.pickNativeAt(event.localPosition, size);
                }
                _clearPointerState();
                return;
              }
              if (moved < _tapDistanceThreshold(event)) {
                final picked = _pickObject(
                  scene,
                  size,
                  event.localPosition,
                  touchFriendly: _usesTouchNavigation(event),
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
                widget.rendererChild ??
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: FallbackRenderScenePainter(
                          scene: scene,
                          visibleKinds: controller.visibleKinds,
                          selectedElementIds: controller.selectedElementIds,
                          activeElementId: controller.activeElementId,
                          selectedLevelId: controller.selectedLevelId,
                          selectionRect: controller.selectionRectangle,
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
                          draftWallThicknessMeters:
                              widget.draftWallThicknessMeters,
                          draftWallHeightMeters: widget.draftWallHeightMeters,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                if (widget.nativeRenderer &&
                    controller.projectionMode.isElevation)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: RenderSceneLevelOverlayPainter(
                        scene: scene,
                        projectionMode: controller.projectionMode,
                        orbitProjectionStyle: controller.orbitProjectionStyle,
                        planCamera: controller.planCamera,
                        camera: controller.camera,
                        selectedLevelId: controller.selectedLevelId,
                        padding: FallbackRenderScenePainter.padding,
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
                if (widget.nativeRenderer)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: NativeDraftOverlayPainter(
                        scene: scene,
                        projectionMode: controller.projectionMode,
                        orbitProjectionStyle: controller.orbitProjectionStyle,
                        camera: controller.camera,
                        planCamera: controller.planCamera,
                        draftWallStart: controller.draftWallStart,
                        draftWallEnd: controller.draftWallEnd,
                        draftOpening: controller.draftOpening,
                        draftSurface: controller.draftSurface,
                        pickedWallIds: widget.draftSurfaceWallIds,
                        wallThicknessMeters: widget.draftWallThicknessMeters,
                        activeElementId: controller.activeElementId,
                        selectedLevelId: controller.selectedLevelId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                if (kDebugMode)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _ViewportStatsCard(
                      scene: scene,
                      native: widget.nativeRenderer,
                    ),
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
    Offset globalPosition, {
    bool touchFriendly = false,
  }) {
    final picked = _pickObject(
      scene,
      size,
      localPosition,
      touchFriendly: touchFriendly,
    );
    final details = RenderSceneTapDetails(
      screenPosition: localPosition,
      globalPosition: globalPosition,
      modelPoint: controller.screenToModelPlan(localPosition, size),
      pickedObject: picked,
    );
    widget.onSceneHover?.call(details);
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
    _gesture.reset();
    _sceneDragStarted = false;
    controller.setSelectionRectangle(null);
    _interaction.reset();
  }
}
