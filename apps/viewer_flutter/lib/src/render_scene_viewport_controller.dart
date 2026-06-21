import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

class RenderSceneViewportController extends RenderSceneViewportActions {
  RenderSceneViewportController({
    Set<String>? visibleKinds,
    RenderSceneViewportBackend backend = RenderSceneViewportBackend.fallback,
  })  : _visibleKinds = visibleKinds ?? kDefaultVisibleSceneKinds.toSet(),
        _backend = backend;

  static const double _planPadding = 48;

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
  Size _viewportSize = Size.zero;
  bool _viewportRefitScheduled = false;

  RenderScenePoint _orbitCenter = RenderScenePoint.zero();
  double _orbitYawRadians = math.pi / 4;
  double _orbitPitchRadians = math.pi / 5;
  double _orbitDistance = 24.0;
  double _orbitZoomScale = 1.0;

  RenderScenePlanCameraState _planCamera = const RenderScenePlanCameraState(
    center: RenderScenePoint(x: 0, y: 0, z: 0),
    zoom: 1.0,
  );

  RenderScenePoint? _draftWallStart;
  RenderScenePoint? _draftWallEnd;
  RenderSceneOpeningDraft? _draftOpening;
  RenderSceneSurfaceDraft? _draftSurface;

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
  RenderScenePlanCameraState get planCamera => _planCamera;

  @override
  RenderSceneCameraState get camera => RenderSceneCameraState(
        center: _orbitCenter,
        distance: _orbitDistance,
        yawRadians: _orbitYawRadians,
        pitchRadians: _orbitPitchRadians,
        zoomScale: _orbitZoomScale,
      );

  @override
  RenderScenePoint? get draftWallStart => _draftWallStart;

  @override
  RenderScenePoint? get draftWallEnd => _draftWallEnd;

  @override
  RenderSceneOpeningDraft? get draftOpening => _draftOpening;

  @override
  RenderSceneSurfaceDraft? get draftSurface => _draftSurface;

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
    _planCamera = const RenderScenePlanCameraState(
      center: RenderScenePoint(x: 0, y: 0, z: 0),
      zoom: 1.0,
    );
    _orbitCenter = RenderScenePoint.zero();
    _orbitDistance = 24.0;
    _orbitZoomScale = 1.0;
    _draftWallStart = null;
    _draftWallEnd = null;
    _draftOpening = null;
    _draftSurface = null;

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
    _orbitZoomScale = 1.0;
  }

  void _resetPlanForBounds(RenderSceneBounds bounds) {
    final center = RenderScenePoint(
      x: bounds.center.x,
      y: bounds.center.y,
      z: bounds.center.z,
    );
    _planCamera = RenderScenePlanCameraState(
      center: center,
      zoom: _zoomToFitBounds(bounds, _viewportSize),
    );
  }

  double _zoomToFitBounds(RenderSceneBounds bounds, Size viewportSize) {
    if (viewportSize.width <= _planPadding * 2 ||
        viewportSize.height <= _planPadding * 2) {
      return 1.0;
    }

    final usableWidth = math.max(viewportSize.width - _planPadding * 2, 1.0);
    final usableHeight = math.max(viewportSize.height - _planPadding * 2, 1.0);
    final width = math.max(bounds.width, 1.0);
    final depth = math.max(bounds.depth, 1.0);
    return math
        .min(usableWidth / width, usableHeight / depth)
        .clamp(0.1, 480.0);
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
  void setSurfaceDraft(RenderSceneSurfaceDraft? draft) {
    _draftSurface = draft;
    notifyListeners();
  }

  @override
  void clearDraft() {
    _draftWallStart = null;
    _draftWallEnd = null;
    _draftOpening = null;
    _draftSurface = null;
    notifyListeners();
  }

  @override
  void setViewportSize(Size size) {
    if ((_viewportSize.width - size.width).abs() < 0.5 &&
        (_viewportSize.height - size.height).abs() < 0.5) {
      return;
    }

    final previousSize = _viewportSize;
    final shouldRefit = previousSize == Size.zero && (_scene != null);
    _viewportSize = size;

    if (shouldRefit) {
      _scheduleViewportRefit();
    }
  }

  void _scheduleViewportRefit() {
    if (_viewportRefitScheduled) {
      return;
    }
    _viewportRefitScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportRefitScheduled = false;
      if (_viewportSize == Size.zero) {
        return;
      }
      _resetPlanForBounds(_scene?.bounds ?? _sceneBounds);
      notifyListeners();
    });
  }

  @override
  void panPlanBy(Offset delta) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }

    final zoom = math.max(_planCamera.zoom, 1e-6);
    _planCamera = _planCamera.copyWith(
      center: RenderScenePoint(
        x: _planCamera.center.x - delta.dx / zoom,
        y: _planCamera.center.y + delta.dy / zoom,
        z: _planCamera.center.z,
      ),
    );
    notifyListeners();
  }

  @override
  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  }) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }

    final targetSize = viewportSize ?? _viewportSize;
    if (targetSize.width <= 1 || targetSize.height <= 1) {
      return;
    }

    final oldZoom = _planCamera.zoom;
    final nextZoom = (oldZoom * scaleDelta).clamp(0.1, 1500.0);
    if ((nextZoom - oldZoom).abs() < 1e-9) {
      return;
    }

    var nextCenter = _planCamera.center;
    if (focalPoint != null) {
      final viewportCenter =
          Offset(targetSize.width * 0.5, targetSize.height * 0.5);
      final before = _screenToModelWithCamera(
        localPosition: focalPoint,
        viewportCenter: viewportCenter,
        cameraState: _planCamera,
      );
      final zoomedCamera = _planCamera.copyWith(zoom: nextZoom);
      final after = _screenToModelWithCamera(
        localPosition: focalPoint,
        viewportCenter: viewportCenter,
        cameraState: zoomedCamera,
      );
      nextCenter = RenderScenePoint(
        x: zoomedCamera.center.x + (before.x - after.x),
        y: zoomedCamera.center.y + (before.y - after.y),
        z: zoomedCamera.center.z,
      );
    }

    _planCamera = RenderScenePlanCameraState(
      center: nextCenter,
      zoom: nextZoom,
    );
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
    final worldScale = (_orbitDistance / math.max(_orbitZoomScale, 0.001)) /
        minDimension *
        0.95;
    final moveRight = scalePoint(basis.right, -delta.dx * worldScale);
    final moveUp = scalePoint(basis.up, delta.dy * worldScale);
    _orbitCenter = addPoint(_orbitCenter, addPoint(moveRight, moveUp));
    notifyListeners();
  }

  @override
  void zoomOrbit(double scaleDelta) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }

    _orbitZoomScale = (_orbitZoomScale * scaleDelta).clamp(0.005, 250.0);
    notifyListeners();
  }

  @override
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return null;
    }

    final targetSize = viewportSize == Size.zero ? _viewportSize : viewportSize;
    if (targetSize.width <= 1 || targetSize.height <= 1) {
      return null;
    }

    final projection = RenderSceneProjection(
      sceneBounds: _sceneBounds,
      canvasSize: targetSize,
      projectionMode: _projectionMode,
      orbitProjectionStyle: _orbitProjectionStyle,
      planCamera: _planCamera,
      camera: camera,
      padding: _planPadding,
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
    final currentScene = _scene;
    if (currentScene != null) {
      await _invoke('loadRenderSceneJson', jsonEncode(currentScene.toJson()));
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
      // Native bridge is optional.
    } on PlatformException {
      // Fallback canvas should stay usable even if native renderer fails.
    }
  }

  RenderScenePoint _screenToModelWithCamera({
    required Offset localPosition,
    required Offset viewportCenter,
    required RenderScenePlanCameraState cameraState,
  }) {
    return RenderScenePoint(
      x: cameraState.center.x +
          (localPosition.dx - viewportCenter.dx) / cameraState.zoom,
      y: cameraState.center.y -
          (localPosition.dy - viewportCenter.dy) / cameraState.zoom,
      z: cameraState.center.z,
    );
  }

  RenderSceneCameraBasis _cameraBasis() {
    return buildCameraBasis(
      center: _orbitCenter,
      yawRadians: _orbitYawRadians,
      pitchRadians: _orbitPitchRadians,
      distance: _orbitDistance,
    );
  }
}
