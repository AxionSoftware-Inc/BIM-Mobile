import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'render_scene_editor.dart';
import 'render_scene_models.dart';

const List<String> kDefaultVisibleSceneKinds = <String>[];

enum RenderSceneProjectionMode {
  topDown,
  isometric,
}

enum RenderSceneDisplayStyle {
  solid,
  wireframe,
}

enum RenderSceneOrbitProjectionStyle {
  perspective,
  orthographic,
}

enum RenderSceneViewportBackend {
  auto,
  native,
  fallback,
}

enum RenderSceneInteractionMode {
  select,
  addWall,
  addDoor,
  addWindow,
}

@immutable
class RenderSceneTapDetails {
  const RenderSceneTapDetails({
    required this.screenPosition,
    required this.modelPoint,
    required this.pickedObject,
  });

  final Offset screenPosition;
  final RenderScenePoint? modelPoint;
  final RenderSceneObject? pickedObject;
}

@immutable
class RenderSceneWallDraft {
  const RenderSceneWallDraft({
    required this.start,
    required this.end,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
}

@immutable
class RenderSceneOpeningDraft {
  const RenderSceneOpeningDraft({
    required this.kind,
    required this.hostWallId,
    required this.offsetMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.valid,
    required this.message,
  });

  final String kind;
  final int? hostWallId;
  final double offsetMeters;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final bool valid;
  final String message;
}

@immutable
class RenderSceneCameraState {
  const RenderSceneCameraState({
    required this.center,
    required this.distance,
    required this.yawRadians,
    required this.pitchRadians,
  });

  final RenderScenePoint center;
  final double distance;
  final double yawRadians;
  final double pitchRadians;
}

abstract class RenderSceneViewportActions extends ChangeNotifier {
  RenderScene? get scene;
  Set<String> get visibleKinds;
  String? get selectedElementId;
  String? get highlightedElementId;
  int get fitRevision;
  int get sceneRevision;
  RenderSceneProjectionMode get projectionMode;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle;
  RenderSceneDisplayStyle get displayStyle;
  RenderSceneViewportBackend get backend;
  RenderSceneInteractionMode get interactionMode;
  Offset get planPanOffset;
  double get planZoom;
  RenderSceneCameraState get camera;
  RenderScenePoint? get draftWallStart;
  RenderScenePoint? get draftWallEnd;
  RenderSceneOpeningDraft? get draftOpening;

  Future<void> loadRenderScene(RenderScene scene);
  Future<void> clearScene();
  Future<void> fitCamera();
  Future<void> setVisibleKinds(Set<String> kinds);
  Future<void> setProjectionMode(RenderSceneProjectionMode mode);
  Future<void> setOrbitProjectionStyle(RenderSceneOrbitProjectionStyle style);
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style);
  Future<void> setBackend(RenderSceneViewportBackend backend);
  Future<void> setInteractionMode(RenderSceneInteractionMode mode);
  void setWallDraft(RenderScenePoint? start, RenderScenePoint? end);
  void setOpeningDraft(RenderSceneOpeningDraft? draft);
  void clearDraft();
  void panPlanBy(Offset delta);
  void zoomPlanBy(double scaleDelta, {Offset? focalPoint});
  void orbitBy(Offset delta, Size viewportSize);
  void panOrbitBy(Offset delta, Size viewportSize);
  void zoomOrbit(double scaleDelta);
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize);
  Future<void> selectElement(String? elementId);
  Future<void> highlightElement(String? elementId);
}

class RenderSceneViewportController extends RenderSceneViewportActions {
  RenderSceneViewportController({
    Set<String>? visibleKinds,
    RenderSceneViewportBackend backend = RenderSceneViewportBackend.fallback,
  })  : _visibleKinds = visibleKinds ?? kDefaultVisibleSceneKinds.toSet(),
        _backend = backend;

  RenderScene? _scene;
  Set<String> _visibleKinds;
  String? _selectedElementId;
  String? _highlightedElementId;

  int _fitRevision = 0;
  int _sceneRevision = 0;

  RenderSceneProjectionMode _projectionMode = RenderSceneProjectionMode.topDown;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.orthographic;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneViewportBackend _backend;
  RenderSceneInteractionMode _interactionMode =
      RenderSceneInteractionMode.select;

  RenderSceneBounds _sceneBounds = RenderSceneBounds.zero();

  RenderScenePoint _orbitCenter = RenderScenePoint.zero();
  double _orbitYawRadians = math.pi / 4;
  double _orbitPitchRadians = math.pi / 5;
  double _orbitDistance = 24.0;

  Offset _planPanOffset = Offset.zero;
  double _planZoom = 1.0;

  RenderScenePoint? _draftWallStart;
  RenderScenePoint? _draftWallEnd;
  RenderSceneOpeningDraft? _draftOpening;

  MethodChannel? _channel;

  @override
  RenderScene? get scene => _scene;

  @override
  Set<String> get visibleKinds => _visibleKinds;

  @override
  String? get selectedElementId => _selectedElementId;

  @override
  String? get highlightedElementId => _highlightedElementId;

  @override
  int get fitRevision => _fitRevision;

  @override
  int get sceneRevision => _sceneRevision;

  @override
  RenderSceneProjectionMode get projectionMode => _projectionMode;

  @override
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle =>
      _orbitProjectionStyle;

  @override
  RenderSceneDisplayStyle get displayStyle => _displayStyle;

  @override
  RenderSceneViewportBackend get backend => _backend;

  @override
  RenderSceneInteractionMode get interactionMode => _interactionMode;

  @override
  Offset get planPanOffset => _planPanOffset;

  @override
  double get planZoom => _planZoom;

  @override
  RenderSceneCameraState get camera => RenderSceneCameraState(
        center: _orbitCenter,
        distance: _orbitDistance,
        yawRadians: _orbitYawRadians,
        pitchRadians: _orbitPitchRadians,
      );

  @override
  RenderScenePoint? get draftWallStart => _draftWallStart;

  @override
  RenderScenePoint? get draftWallEnd => _draftWallEnd;

  @override
  RenderSceneOpeningDraft? get draftOpening => _draftOpening;

  bool get hasNativeBridge => _channel != null;

  Future<void> attachNativeBridge(int viewId) async {
    _channel = MethodChannel('tbe/render_scene_view_$viewId');
    await _syncNativeBridge();

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
        return _syncNativeBridge();
      }),
    );
  }

  void detachNativeBridge() {
    _channel = null;
  }

  @override
  Future<void> loadRenderScene(RenderScene scene) async {
    await updateRenderScene(scene, resetView: true);
  }

  Future<void> updateRenderScene(
    RenderScene scene, {
    bool resetView = false,
  }) async {
    _scene = scene;
    _sceneBounds = scene.bounds;
    _sceneRevision += 1;
    _fitRevision += 1;

    if (resetView) {
      _resetCameraForBounds(scene.bounds);
      _resetPlanForBounds(scene.bounds);
    }

    notifyListeners();

    await _invoke('loadRenderSceneJson', jsonEncode(scene.toJson()));
    await _syncNativeBridge();
  }

  @override
  Future<void> clearScene() async {
    _scene = null;
    _selectedElementId = null;
    _highlightedElementId = null;
    _sceneBounds = RenderSceneBounds.zero();
    _sceneRevision += 1;
    _fitRevision += 1;
    _planPanOffset = Offset.zero;
    _planZoom = 1.0;
    _orbitCenter = RenderScenePoint.zero();
    _orbitDistance = 24.0;
    _draftWallStart = null;
    _draftWallEnd = null;
    _draftOpening = null;

    notifyListeners();

    await _invoke('clearScene');
  }

  @override
  Future<void> fitCamera() async {
    final bounds = _scene?.bounds ?? _sceneBounds;
    _resetCameraForBounds(bounds);
    _resetPlanForBounds(bounds);
    _fitRevision += 1;

    notifyListeners();

    await _invoke('fitCamera');
  }

  void _resetCameraForBounds(RenderSceneBounds bounds) {
    final width = math.max(bounds.width, 0.001);
    final depth = math.max(bounds.depth, 0.001);
    final height = math.max(bounds.height, 0.001);
    final maxExtent = math.max(width, math.max(depth, height));

    _orbitCenter = RenderScenePoint(
      x: (bounds.min.x + bounds.max.x) * 0.5,
      y: (bounds.min.y + bounds.max.y) * 0.5,
      z: (bounds.min.z + bounds.max.z) * 0.5,
    );

    _orbitYawRadians = math.pi / 4;
    _orbitPitchRadians = math.pi / 5.2;
    _orbitDistance = math.max(maxExtent * 2.4, 10.0);
  }

  void _resetPlanForBounds(RenderSceneBounds bounds) {
    _planPanOffset = Offset.zero;
    _planZoom = 1.0;

    if (!bounds.width.isFinite || !bounds.depth.isFinite) {
      return;
    }
  }

  @override
  Future<void> setVisibleKinds(Set<String> kinds) async {
    _visibleKinds = kinds;
    notifyListeners();
    await _invoke('setVisibleKinds', kinds.toList());
  }

  @override
  Future<void> setProjectionMode(RenderSceneProjectionMode mode) async {
    if (_projectionMode == mode) {
      return;
    }

    _projectionMode = mode;

    if (mode == RenderSceneProjectionMode.topDown) {
      _planPanOffset = Offset.zero;
      _planZoom = 1.0;
    }

    notifyListeners();

    await _syncNativeBridge();
  }

  @override
  Future<void> setOrbitProjectionStyle(
    RenderSceneOrbitProjectionStyle style,
  ) async {
    if (_orbitProjectionStyle == style) {
      return;
    }

    _orbitProjectionStyle = style;
    notifyListeners();

    await _syncNativeBridge();
  }

  @override
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style) async {
    if (_displayStyle == style) {
      return;
    }

    _displayStyle = style;
    notifyListeners();

    await _invoke('setDisplayStyle', style.name);
  }

  @override
  Future<void> setBackend(RenderSceneViewportBackend backend) async {
    if (_backend == backend) {
      return;
    }

    _backend = backend;
    notifyListeners();
  }

  @override
  Future<void> setInteractionMode(RenderSceneInteractionMode mode) async {
    if (_interactionMode == mode) {
      return;
    }

    _interactionMode = mode;

    if (mode != RenderSceneInteractionMode.select &&
        _projectionMode != RenderSceneProjectionMode.topDown) {
      _projectionMode = RenderSceneProjectionMode.topDown;
      _planPanOffset = Offset.zero;
      _planZoom = 1.0;
    }

    notifyListeners();
  }

  @override
  void setWallDraft(RenderScenePoint? start, RenderScenePoint? end) {
    _draftWallStart = start;
    _draftWallEnd = end;
    notifyListeners();
  }

  @override
  void setOpeningDraft(RenderSceneOpeningDraft? draft) {
    _draftOpening = draft;
    notifyListeners();
  }

  @override
  void clearDraft() {
    _draftWallStart = null;
    _draftWallEnd = null;
    _draftOpening = null;
    notifyListeners();
  }

  @override
  void panPlanBy(Offset delta) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }

    _planPanOffset += delta;
    notifyListeners();
  }

  @override
  void zoomPlanBy(double scaleDelta, {Offset? focalPoint}) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }

    final oldZoom = _planZoom;
    final nextZoom = (_planZoom * scaleDelta).clamp(0.05, 80.0);

    if ((nextZoom - oldZoom).abs() < 1e-9) {
      return;
    }

    if (focalPoint != null) {
      final factor = nextZoom / oldZoom;
      _planPanOffset = focalPoint - (focalPoint - _planPanOffset) * factor;
    }

    _planZoom = nextZoom;
    notifyListeners();
  }

  @override
  void orbitBy(Offset delta, Size viewportSize) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }

    final minDimension =
        math.max(math.min(viewportSize.width, viewportSize.height), 1.0);

    _orbitYawRadians += delta.dx / minDimension * math.pi * 1.25;
    _orbitPitchRadians =
        (_orbitPitchRadians + delta.dy / minDimension * math.pi * 0.95)
            .clamp(-math.pi / 2.0 + 0.12, math.pi / 2.0 - 0.12);

    notifyListeners();
  }

  @override
  void panOrbitBy(Offset delta, Size viewportSize) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }

    final basis = _cameraBasis();
    final minDimension =
        math.max(math.min(viewportSize.width, viewportSize.height), 1.0);
    final worldScale = _orbitDistance / minDimension * 1.35;

    final moveRight = _scalePoint(basis.right, -delta.dx * worldScale);
    final moveUp = _scalePoint(basis.up, delta.dy * worldScale);
    final movement = _addPoint(moveRight, moveUp);

    _orbitCenter = _addPoint(_orbitCenter, movement);
    notifyListeners();
  }

  @override
  void zoomOrbit(double scaleDelta) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }

    _orbitDistance = (_orbitDistance / scaleDelta).clamp(1.0, 5000.0);
    notifyListeners();
  }

  @override
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return null;
    }

    final projection = _SceneProjection(
      sceneBounds: _sceneBounds,
      canvasSize: viewportSize,
      projectionMode: _projectionMode,
      orbitProjectionStyle: _orbitProjectionStyle,
      camera: camera,
      planPanOffset: _planPanOffset,
      planZoom: _planZoom,
      padding: _FallbackRenderScenePainter._padding,
    );

    return projection.unprojectPlan(localPosition);
  }

  @override
  Future<void> selectElement(String? elementId) async {
    if (_selectedElementId == elementId) {
      return;
    }

    _selectedElementId = elementId;
    notifyListeners();

    await _invoke('selectElement', elementId);
  }

  @override
  Future<void> highlightElement(String? elementId) async {
    if (_highlightedElementId == elementId) {
      return;
    }

    _highlightedElementId = elementId;
    notifyListeners();

    await _invoke('highlightElement', elementId);
  }

  Future<void> _syncNativeBridge() async {
    final scene = _scene;
    if (scene != null) {
      await _invoke('loadRenderSceneJson', jsonEncode(scene.toJson()));
    }

    await _invoke('setVisibleKinds', _visibleKinds.toList());
    await _invoke('setDisplayStyle', _displayStyle.name);
    await _invoke('selectElement', _selectedElementId);
    await _invoke('highlightElement', _highlightedElementId);
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Native bridge is intentionally optional.
    } on PlatformException {
      // Keep fallback viewport alive even if native renderer fails.
    }
  }

  _CameraBasis _cameraBasis() {
    return _buildCameraBasis(
      center: _orbitCenter,
      yawRadians: _orbitYawRadians,
      pitchRadians: _orbitPitchRadians,
      distance: _orbitDistance,
    );
  }
}

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
  Offset? _lastPointerPosition;
  Offset? _pointerDownPosition;
  int? _activePointer;
  bool _isSecondaryDrag = false;

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
      onPointerStateChanged: _setPointerState,
    );
  }

  void _setPointerState({
    Offset? lastPointerPosition,
    Offset? pointerDownPosition,
    int? activePointer,
    bool? isSecondaryDrag,
    bool clear = false,
  }) {
    if (clear) {
      _lastPointerPosition = null;
      _pointerDownPosition = null;
      _activePointer = null;
      _isSecondaryDrag = false;
      return;
    }

    _lastPointerPosition = lastPointerPosition ?? _lastPointerPosition;
    _pointerDownPosition = pointerDownPosition ?? _pointerDownPosition;
    _activePointer = activePointer ?? _activePointer;
    _isSecondaryDrag = isSecondaryDrag ?? _isSecondaryDrag;
  }

  Offset? get lastPointerPosition => _lastPointerPosition;
  Offset? get pointerDownPosition => _pointerDownPosition;
  int? get activePointer => _activePointer;
  bool get isSecondaryDrag => _isSecondaryDrag;
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
    required this.onPointerStateChanged,
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final void Function({
    Offset? lastPointerPosition,
    Offset? pointerDownPosition,
    int? activePointer,
    bool? isSecondaryDrag,
    bool clear,
  }) onPointerStateChanged;

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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleUpdate: (ScaleUpdateDetails details) {
            if (details.pointerCount < 2) {
              return;
            }

            if (controller.projectionMode ==
                RenderSceneProjectionMode.topDown) {
              controller.zoomPlanBy(details.scale,
                  focalPoint: details.localFocalPoint);
            } else {
              controller.zoomOrbit(details.scale);
            }
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
                controller.zoomPlanBy(scaleDelta,
                    focalPoint: event.localPosition);
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
              widget.onPointerStateChanged(
                activePointer: event.pointer,
                pointerDownPosition: event.localPosition,
                lastPointerPosition: event.localPosition,
                isSecondaryDrag: _isSecondaryDrag,
              );
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
              widget.onPointerStateChanged(
                  lastPointerPosition: event.localPosition);
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
                final picked = _pickObjectAt(
                  scene: scene,
                  size: size,
                  localPosition: event.localPosition,
                  projectionMode: controller.projectionMode,
                  orbitProjectionStyle: controller.orbitProjectionStyle,
                  camera: controller.camera,
                  visibleKinds: controller.visibleKinds,
                  planPanOffset: controller.planPanOffset,
                  planZoom: controller.planZoom,
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
            onPointerCancel: (_) {
              _activePointerCount = math.max(0, _activePointerCount - 1);
              _clearPointerState();
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _FallbackRenderScenePainter(
                      scene: scene,
                      visibleKinds: controller.visibleKinds,
                      selectedElementId: controller.selectedElementId,
                      highlightedElementId: controller.highlightedElementId,
                      projectionMode: controller.projectionMode,
                      orbitProjectionStyle: controller.orbitProjectionStyle,
                      displayStyle: controller.displayStyle,
                      camera: controller.camera,
                      planPanOffset: controller.planPanOffset,
                      planZoom: controller.planZoom,
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
            ? '2D: drag to pan, scroll/pinch to zoom, tap to select.'
            : '3D: drag to orbit, middle/right drag to pan, scroll to zoom.';
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
    widget.onPointerStateChanged(clear: true);
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

class _ProjectedPoint {
  const _ProjectedPoint({
    required this.screen,
    required this.depth,
  });

  final Offset screen;
  final double depth;
}

class _CameraBasis {
  const _CameraBasis({
    required this.eye,
    required this.forward,
    required this.right,
    required this.up,
  });

  final RenderScenePoint eye;
  final RenderScenePoint forward;
  final RenderScenePoint right;
  final RenderScenePoint up;
}

class _TriangleRender {
  const _TriangleRender({
    required this.a,
    required this.b,
    required this.c,
    required this.depth,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  final Offset a;
  final Offset b;
  final Offset c;
  final double depth;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
}

class _FallbackRenderScenePainter extends CustomPainter {
  _FallbackRenderScenePainter({
    required this.scene,
    required this.visibleKinds,
    required this.selectedElementId,
    required this.highlightedElementId,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.displayStyle,
    required this.camera,
    required this.planPanOffset,
    required this.planZoom,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftOpening,
  });

  final RenderScene scene;
  final Set<String> visibleKinds;
  final String? selectedElementId;
  final String? highlightedElementId;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneDisplayStyle displayStyle;
  final RenderSceneCameraState camera;
  final Offset planPanOffset;
  final double planZoom;
  final RenderScenePoint? draftWallStart;
  final RenderScenePoint? draftWallEnd;
  final RenderSceneOpeningDraft? draftOpening;

  static const double _padding = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF5F8F6);
    canvas.drawRect(Offset.zero & size, background);

    if (size.width <= 1 || size.height <= 1) {
      return;
    }

    final projection = _SceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      camera: camera,
      planPanOffset: planPanOffset,
      planZoom: planZoom,
      padding: _padding,
    );

    _drawGrid(canvas, projection);
    _drawAxes(canvas, projection);

    final triangles = <_TriangleRender>[];
    final filteredObjects = scene.objectsForKinds(visibleKinds);

    for (final object in filteredObjects) {
      final isSelected = object.elementId?.toString() == selectedElementId &&
          selectedElementId != null;
      final isHighlighted =
          object.elementId?.toString() == highlightedElementId &&
              highlightedElementId != null;

      final baseColor = _kindColor(object.kindKey);
      final objectColor = isSelected
          ? const Color(0xFF2563EB)
          : isHighlighted
              ? const Color(0xFFDC2626)
              : baseColor;

      final strokeWidth = isSelected || isHighlighted
          ? 2.2
          : displayStyle == RenderSceneDisplayStyle.wireframe
              ? 1.0
              : 0.8;

      final fillAlpha = displayStyle == RenderSceneDisplayStyle.wireframe
          ? 0.0
          : isSelected || isHighlighted
              ? 0.62
              : 0.82;

      triangles.addAll(
        _buildObjectTriangles(
          object: object,
          projection: projection,
          fillColor: objectColor.withValues(alpha: fillAlpha),
          strokeColor: objectColor.withValues(alpha: 0.96),
          strokeWidth: strokeWidth,
        ),
      );
    }

    triangles.sort((a, b) => b.depth.compareTo(a.depth));

    for (final triangle in triangles) {
      final path = Path()
        ..moveTo(triangle.a.dx, triangle.a.dy)
        ..lineTo(triangle.b.dx, triangle.b.dy)
        ..lineTo(triangle.c.dx, triangle.c.dy)
        ..close();

      if (displayStyle == RenderSceneDisplayStyle.solid) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = triangle.fillColor,
        );
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = triangle.strokeWidth
          ..color = triangle.strokeColor,
      );
    }

    _drawLabels(canvas, projection, filteredObjects);
    _drawDraftOverlay(canvas, projection);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFCBD5E1),
    );
  }

  void _drawDraftOverlay(Canvas canvas, _SceneProjection projection) {
    final wallStart = draftWallStart;
    final wallEnd = draftWallEnd;
    final opening = draftOpening;

    if (wallStart != null && wallEnd != null) {
      final a = projection.project(wallStart).screen;
      final b = projection.project(wallEnd).screen;
      final paint = Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, paint);
      canvas.drawCircle(a, 5, Paint()..color = const Color(0xFFEF4444));
      canvas.drawCircle(b, 5, Paint()..color = const Color(0xFFEF4444));
    }

    if (opening != null && opening.hostWallId != null) {
      final host = scene.objectById(opening.hostWallId);
      if (host != null) {
        final wallStart = RenderSceneEditor.wallStartPoint(host);
        final wallEnd = RenderSceneEditor.wallEndPoint(host);
        final wallThickness = RenderSceneEditor.wallThickness(host);
        if (wallStart != null && wallEnd != null && wallThickness != null) {
          final axis = wallEnd - wallStart;
          final axisLength = wallStart.distanceTo(wallEnd);
          if (axisLength > 1e-9) {
            final axisUnit = axis.scale(1.0 / axisLength);
            final normal = RenderScenePoint(
              x: -axisUnit.y,
              y: axisUnit.x,
              z: 0,
            );
            final halfWidth = opening.widthMeters * 0.5;
            final center = wallStart + axisUnit.scale(opening.offsetMeters);
            final startPoint = center - axisUnit.scale(halfWidth);
            final endPoint = center + axisUnit.scale(halfWidth);
            final halfThickness = wallThickness * 0.5;
            final lower = opening.sillHeightMeters;
            final upper = lower + opening.heightMeters;
            final corners = <RenderScenePoint>[
              startPoint + normal.scale(halfThickness),
              endPoint + normal.scale(halfThickness),
              endPoint - normal.scale(halfThickness),
              startPoint - normal.scale(halfThickness),
              RenderScenePoint(
                x: startPoint.x + normal.x * halfThickness,
                y: startPoint.y + normal.y * halfThickness,
                z: upper,
              ),
              RenderScenePoint(
                x: endPoint.x + normal.x * halfThickness,
                y: endPoint.y + normal.y * halfThickness,
                z: upper,
              ),
              RenderScenePoint(
                x: endPoint.x - normal.x * halfThickness,
                y: endPoint.y - normal.y * halfThickness,
                z: upper,
              ),
              RenderScenePoint(
                x: startPoint.x - normal.x * halfThickness,
                y: startPoint.y - normal.y * halfThickness,
                z: upper,
              ),
            ];
            final projectedCorners = corners
                .map((point) => projection.project(point).screen)
                .toList(growable: false);
            final rect = Rect.fromPoints(
              projectedCorners.first,
              projectedCorners[2],
            );
            final fill = Paint()
              ..color = opening.valid
                  ? const Color(0xFF22C55E).withValues(alpha: 0.24)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.28)
              ..style = PaintingStyle.fill;
            final stroke = Paint()
              ..color = opening.valid
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFD97706)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2;
            canvas.drawRect(rect, fill);
            canvas.drawRect(rect, stroke);
            final messagePainter = TextPainter(
              text: TextSpan(
                text: opening.message,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 2,
            )..layout(maxWidth: 160);
            messagePainter.paint(canvas, rect.topLeft + const Offset(4, -18));
          }
        }
      }
    }
  }

  List<_TriangleRender> _buildObjectTriangles({
    required RenderSceneObject object,
    required _SceneProjection projection,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) {
    final rawTriangles = <List<RenderScenePoint>>[];
    final mesh = object.mesh;

    if (mesh.hasGeometry) {
      for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
        final a = _safeMeshPoint(mesh.positions, mesh.indices[i]);
        final b = _safeMeshPoint(mesh.positions, mesh.indices[i + 1]);
        final c = _safeMeshPoint(mesh.positions, mesh.indices[i + 2]);

        if (a != null && b != null && c != null) {
          rawTriangles.add(<RenderScenePoint>[a, b, c]);
        }
      }
    }

    if (rawTriangles.isEmpty) {
      rawTriangles.addAll(_fallbackBoxTriangles(object.bounds));
    }

    final rendered = <_TriangleRender>[];

    for (final triangle in rawTriangles) {
      final a = projection.project(triangle[0]);
      final b = projection.project(triangle[1]);
      final c = projection.project(triangle[2]);

      final area = _triangleArea(a.screen, b.screen, c.screen).abs();
      if (area < 0.25) {
        continue;
      }

      rendered.add(
        _TriangleRender(
          a: a.screen,
          b: b.screen,
          c: c.screen,
          depth: (a.depth + b.depth + c.depth) / 3.0,
          fillColor: fillColor,
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
        ),
      );
    }

    return rendered;
  }

  void _drawLabels(
    Canvas canvas,
    _SceneProjection projection,
    List<RenderSceneObject> objects,
  ) {
    if (objects.length > 220) {
      return;
    }

    for (final object in objects) {
      final isSelected = object.elementId?.toString() == selectedElementId &&
          selectedElementId != null;
      final isHighlighted =
          object.elementId?.toString() == highlightedElementId &&
              highlightedElementId != null;

      if (!isSelected && !isHighlighted && objects.length > 80) {
        continue;
      }

      final projected = projection.project(object.bounds.max);
      final label = '${prettySceneKind(object.kind)} ${object.elementId ?? ''}';

      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isSelected || isHighlighted
                ? const Color(0xFF111827)
                : const Color(0xFF374151),
            fontSize: isSelected || isHighlighted ? 11 : 9,
            fontWeight:
                isSelected || isHighlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 160);

      painter.paint(canvas, projected.screen + const Offset(5, -16));
    }
  }

  void _drawGrid(Canvas canvas, _SceneProjection projection) {
    final bounds = scene.bounds;
    final width = math.max(bounds.width, 0.001);
    final depth = math.max(bounds.depth, 0.001);
    final maxExtent = math.max(width, depth);

    final spacing = _niceGridSpacing(maxExtent);
    final minX = (bounds.min.x / spacing).floor() * spacing;
    final maxX = (bounds.max.x / spacing).ceil() * spacing;
    final minY = (bounds.min.y / spacing).floor() * spacing;
    final maxY = (bounds.max.y / spacing).ceil() * spacing;

    final paint = Paint()
      ..color = const Color(0xFFD1D5DB).withValues(alpha: 0.75)
      ..strokeWidth = 0.7;

    for (var x = minX; x <= maxX; x += spacing) {
      final a = projection.project(RenderScenePoint(x: x, y: minY, z: 0));
      final b = projection.project(RenderScenePoint(x: x, y: maxY, z: 0));
      canvas.drawLine(a.screen, b.screen, paint);
    }

    for (var y = minY; y <= maxY; y += spacing) {
      final a = projection.project(RenderScenePoint(x: minX, y: y, z: 0));
      final b = projection.project(RenderScenePoint(x: maxX, y: y, z: 0));
      canvas.drawLine(a.screen, b.screen, paint);
    }
  }

  void _drawAxes(Canvas canvas, _SceneProjection projection) {
    final origin = projection.project(const RenderScenePoint(x: 0, y: 0, z: 0));
    final xAxis = projection.project(const RenderScenePoint(x: 1, y: 0, z: 0));
    final yAxis = projection.project(const RenderScenePoint(x: 0, y: 1, z: 0));
    final zAxis = projection.project(const RenderScenePoint(x: 0, y: 0, z: 1));

    canvas.drawLine(
      origin.screen,
      xAxis.screen,
      Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      origin.screen,
      yAxis.screen,
      Paint()
        ..color = const Color(0xFF16A34A)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      origin.screen,
      zAxis.screen,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2,
    );
  }

  double _niceGridSpacing(double maxExtent) {
    if (maxExtent <= 10) return 1;
    if (maxExtent <= 30) return 2;
    if (maxExtent <= 80) return 5;
    if (maxExtent <= 180) return 10;
    if (maxExtent <= 400) return 20;
    return 50;
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'wall':
        return const Color(0xFF7C9885);
      case 'door':
        return const Color(0xFF8D6E63);
      case 'window':
        return const Color(0xFF4C8BF5);
      case 'slab':
      case 'floor':
        return const Color(0xFF94A3B8);
      case 'ceiling':
        return const Color(0xFFCBD5E1);
      case 'roof':
        return const Color(0xFFB45309);
      case 'column':
        return const Color(0xFF6B7280);
      case 'beam':
        return const Color(0xFF4B5563);
      case 'stair':
        return const Color(0xFF7E57C2);
      case 'room':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackRenderScenePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.visibleKinds != visibleKinds ||
        oldDelegate.selectedElementId != selectedElementId ||
        oldDelegate.highlightedElementId != highlightedElementId ||
        oldDelegate.projectionMode != projectionMode ||
        oldDelegate.orbitProjectionStyle != orbitProjectionStyle ||
        oldDelegate.displayStyle != displayStyle ||
        oldDelegate.camera != camera ||
        oldDelegate.planPanOffset != planPanOffset ||
        oldDelegate.planZoom != planZoom ||
        oldDelegate.draftWallStart != draftWallStart ||
        oldDelegate.draftWallEnd != draftWallEnd ||
        oldDelegate.draftOpening != draftOpening;
  }
}

class _SceneProjection {
  _SceneProjection({
    required this.sceneBounds,
    required this.canvasSize,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.camera,
    required this.planPanOffset,
    required this.planZoom,
    required this.padding,
  }) {
    final bounds = _projectRawBounds(sceneBounds);
    final scaleX =
        (canvasSize.width - padding * 2) / math.max(bounds.width, 1e-6);
    final scaleY =
        (canvasSize.height - padding * 2) / math.max(bounds.height, 1e-6);

    screenScale = math.min(scaleX, scaleY).clamp(0.001, 1e9);
    projectedBounds = bounds;

    screenOffset = Offset(
      padding + (canvasSize.width - bounds.width * screenScale) * 0.5,
      padding + (canvasSize.height - bounds.height * screenScale) * 0.5,
    );
  }

  final RenderSceneBounds sceneBounds;
  final Size canvasSize;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneCameraState camera;
  final Offset planPanOffset;
  final double planZoom;
  final double padding;

  late final Rect projectedBounds;
  late final double screenScale;
  late final Offset screenOffset;

  _ProjectedPoint project(RenderScenePoint point) {
    final raw = _projectRawPoint(point);
    return _ProjectedPoint(
      screen: Offset(
        screenOffset.dx + (raw.screen.dx - projectedBounds.left) * screenScale,
        screenOffset.dy + (raw.screen.dy - projectedBounds.top) * screenScale,
      ),
      depth: raw.depth,
    );
  }

  RenderScenePoint? unprojectPlan(Offset localPosition) {
    if (projectionMode != RenderSceneProjectionMode.topDown) {
      return null;
    }

    final rawScreen = Offset(
      (localPosition.dx - screenOffset.dx) / screenScale + projectedBounds.left,
      (localPosition.dy - screenOffset.dy) / screenScale + projectedBounds.top,
    );

    final x = (rawScreen.dx - planPanOffset.dx) / planZoom;
    final y = -(rawScreen.dy - planPanOffset.dy) / planZoom;

    return RenderScenePoint(
      x: x,
      y: y,
      z: sceneBounds.center.z,
    );
  }

  Rect _projectRawBounds(RenderSceneBounds bounds) {
    final corners = _boundsCorners(bounds);
    final projected = corners.map(_projectRawPoint).toList(growable: false);

    var minX = projected.first.screen.dx;
    var minY = projected.first.screen.dy;
    var maxX = projected.first.screen.dx;
    var maxY = projected.first.screen.dy;

    for (final point in projected.skip(1)) {
      minX = math.min(minX, point.screen.dx);
      minY = math.min(minY, point.screen.dy);
      maxX = math.max(maxX, point.screen.dx);
      maxY = math.max(maxY, point.screen.dy);
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  _ProjectedPoint _projectRawPoint(RenderScenePoint point) {
    switch (projectionMode) {
      case RenderSceneProjectionMode.topDown:
        return _ProjectedPoint(
          screen:
              Offset(point.x * planZoom, -point.y * planZoom) + planPanOffset,
          depth: point.z,
        );

      case RenderSceneProjectionMode.isometric:
        final basis = _buildCameraBasis(
          center: camera.center,
          yawRadians: camera.yawRadians,
          pitchRadians: camera.pitchRadians,
          distance: camera.distance,
        );

        final relative = _subtractPoint(point, basis.eye);
        final x = _dotPoint(relative, basis.right);
        final y = _dotPoint(relative, basis.up);
        final depth = math.max(0.001, _dotPoint(relative, basis.forward));

        if (orbitProjectionStyle ==
            RenderSceneOrbitProjectionStyle.orthographic) {
          return _ProjectedPoint(screen: Offset(x, -y), depth: depth);
        }

        final perspectiveScale = camera.distance / depth;
        return _ProjectedPoint(
          screen: Offset(x * perspectiveScale, -y * perspectiveScale),
          depth: depth,
        );
    }
  }
}

RenderSceneObject? _pickObjectAt({
  required RenderScene scene,
  required Size size,
  required Offset localPosition,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderSceneCameraState camera,
  required Set<String> visibleKinds,
  required Offset planPanOffset,
  required double planZoom,
}) {
  final objects = scene.objectsForKinds(visibleKinds);
  if (objects.isEmpty) {
    return null;
  }

  final projection = _SceneProjection(
    sceneBounds: scene.bounds,
    canvasSize: size,
    projectionMode: projectionMode,
    orbitProjectionStyle: orbitProjectionStyle,
    camera: camera,
    planPanOffset: planPanOffset,
    planZoom: planZoom,
    padding: _FallbackRenderScenePainter._padding,
  );

  RenderSceneObject? bestObject;
  var bestScore = double.infinity;
  var bestDepth = -double.infinity;

  for (final object in objects) {
    final rect = _projectBoundsRect(object.bounds, projection).inflate(14);
    if (!rect.contains(localPosition)) {
      continue;
    }

    final centerDistance = (rect.center - localPosition).distance;
    final objectDepth = _projectObjectDepth(object.bounds, projection);
    final score = centerDistance - objectDepth * 0.0001;

    if (score < bestScore || (score == bestScore && objectDepth > bestDepth)) {
      bestScore = score;
      bestDepth = objectDepth;
      bestObject = object;
    }
  }

  return bestObject;
}

Rect _projectBoundsRect(RenderSceneBounds bounds, _SceneProjection projection) {
  final corners = _boundsCorners(bounds);
  final projected = corners.map(projection.project).toList(growable: false);

  var minX = projected.first.screen.dx;
  var minY = projected.first.screen.dy;
  var maxX = projected.first.screen.dx;
  var maxY = projected.first.screen.dy;

  for (final point in projected.skip(1)) {
    minX = math.min(minX, point.screen.dx);
    minY = math.min(minY, point.screen.dy);
    maxX = math.max(maxX, point.screen.dx);
    maxY = math.max(maxY, point.screen.dy);
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _projectObjectDepth(
    RenderSceneBounds bounds, _SceneProjection projection) {
  final corners = _boundsCorners(bounds);
  var depth = 0.0;
  for (final corner in corners) {
    depth += projection.project(corner).depth;
  }
  return depth / corners.length;
}

RenderScenePoint? _safeMeshPoint(List<RenderScenePoint> positions, int index) {
  if (index < 0 || index >= positions.length) {
    return null;
  }

  final point = positions[index];
  if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
    return null;
  }

  return point;
}

List<List<RenderScenePoint>> _fallbackBoxTriangles(RenderSceneBounds bounds) {
  final corners = _boundsCorners(bounds);

  return <List<RenderScenePoint>>[
    <RenderScenePoint>[corners[0], corners[1], corners[2]],
    <RenderScenePoint>[corners[0], corners[2], corners[3]],
    <RenderScenePoint>[corners[4], corners[6], corners[5]],
    <RenderScenePoint>[corners[4], corners[7], corners[6]],
    <RenderScenePoint>[corners[0], corners[5], corners[1]],
    <RenderScenePoint>[corners[0], corners[4], corners[5]],
    <RenderScenePoint>[corners[1], corners[6], corners[2]],
    <RenderScenePoint>[corners[1], corners[5], corners[6]],
    <RenderScenePoint>[corners[2], corners[7], corners[3]],
    <RenderScenePoint>[corners[2], corners[6], corners[7]],
    <RenderScenePoint>[corners[3], corners[4], corners[0]],
    <RenderScenePoint>[corners[3], corners[7], corners[4]],
  ];
}

List<RenderScenePoint> _boundsCorners(RenderSceneBounds bounds) {
  return <RenderScenePoint>[
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.max.z),
  ];
}

_CameraBasis _buildCameraBasis({
  required RenderScenePoint center,
  required double yawRadians,
  required double pitchRadians,
  required double distance,
}) {
  final eye = RenderScenePoint(
    x: center.x + distance * math.cos(pitchRadians) * math.cos(yawRadians),
    y: center.y + distance * math.cos(pitchRadians) * math.sin(yawRadians),
    z: center.z + distance * math.sin(pitchRadians),
  );

  final forward = _normalizePoint(_subtractPoint(center, eye));

  const worldUp = RenderScenePoint(x: 0, y: 0, z: 1);
  var right = _crossPoint(forward, worldUp);
  if (_lengthPoint(right) < 1e-8) {
    right = const RenderScenePoint(x: 1, y: 0, z: 0);
  } else {
    right = _normalizePoint(right);
  }

  final up = _normalizePoint(_crossPoint(right, forward));

  return _CameraBasis(
    eye: eye,
    forward: forward,
    right: right,
    up: up,
  );
}

RenderScenePoint _addPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
}

RenderScenePoint _subtractPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z);
}

RenderScenePoint _scalePoint(RenderScenePoint point, double scale) {
  return RenderScenePoint(
    x: point.x * scale,
    y: point.y * scale,
    z: point.z * scale,
  );
}

double _dotPoint(RenderScenePoint a, RenderScenePoint b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

RenderScenePoint _crossPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  );
}

double _lengthPoint(RenderScenePoint point) {
  return math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z);
}

RenderScenePoint _normalizePoint(RenderScenePoint point) {
  final length = _lengthPoint(point);
  if (length <= 1e-9) {
    return const RenderScenePoint(x: 0, y: 0, z: 1);
  }

  return RenderScenePoint(
    x: point.x / length,
    y: point.y / length,
    z: point.z / length,
  );
}

double _triangleArea(Offset a, Offset b, Offset c) {
  return ((b.dx - a.dx) * (c.dy - a.dy)) - ((b.dy - a.dy) * (c.dx - a.dx));
}
