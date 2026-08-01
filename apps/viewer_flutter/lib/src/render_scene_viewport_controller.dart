import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

class RenderSceneViewportController extends RenderSceneViewportActions {
  RenderSceneViewportController({
    Set<String>? visibleKinds,
    RenderSceneViewportBackend? backend,
  })  : _visibleKinds = visibleKinds ?? kDefaultVisibleSceneKinds.toSet(),
        // Flutter remains the owner of all interaction overlays. On Android
        // the geometry layer can therefore start in Filament immediately,
        // while macOS/tests keep the canvas fallback.
        _backend = backend ??
            (defaultTargetPlatform == TargetPlatform.android
                ? RenderSceneViewportBackend.native
                : RenderSceneViewportBackend.fallback);

  static const double _planPadding = 48;

  RenderScene? _scene;
  Set<String> _visibleKinds;
  Set<String> _selectedElementIds = <String>{};
  String? _activeElementId;
  int? _selectedLevelId;
  String? _highlightedElementId;

  int _fitRevision = 0;
  int _sceneRevision = 0;

  RenderSceneProjectionMode _projectionMode = kDefaultPlanProjectionMode;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.orthographic;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneViewportBackend _backend;
  RenderSceneInteractionMode _interactionMode =
      RenderSceneInteractionMode.select;

  RenderSceneBounds _sceneBounds = RenderSceneBounds.zero();
  RenderSceneBounds? _sectionBox;
  RenderSceneSection? _sectionView;
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
  Rect? _selectionRectangle;
  bool _selectionRectangleCrossing = false;

  MethodChannel? _channel;

  @override
  RenderScene? get scene => _scene;

  @override
  Set<String> get visibleKinds => _visibleKinds;

  @override
  Set<String> get selectedElementIds =>
      Set<String>.unmodifiable(_selectedElementIds);

  @override
  String? get activeElementId => _activeElementId;

  @override
  int? get selectedLevelId => _selectedLevelId;

  /// Compatibility alias. New code should use [activeElementId].
  @override
  String? get selectedElementId => _activeElementId;

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

  Rect? get selectionRectangle => _selectionRectangle;
  bool get selectionRectangleCrossing => _selectionRectangleCrossing;

  bool get hasNativeBridge => _channel != null;

  RenderSceneBounds get sceneBounds => _scene?.bounds ?? _sceneBounds;
  RenderSceneBounds? get sectionBox => _sectionBox;
  bool get hasSectionBox => _sectionBox != null;
  bool get hasSectionView => _sectionView != null;

  Future<Map<Object?, Object?>?> nativeDiagnostics() async {
    final channel = _channel;
    if (channel == null) return null;
    try {
      return await channel.invokeMapMethod<Object?, Object?>('getDiagnostics');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> attachNativeBridge(int viewId) async {
    _channel = MethodChannel('tbe/render_scene_view_$viewId');
    _channel!.setMethodCallHandler(_handleNativeCallback);
    await _syncNativeBridge();

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
        return _syncNativeBridge();
      }),
    );
  }

  void detachNativeBridge() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  /// Android Filament owns its live orbit camera, so its hit-test is the only
  /// picker that exactly matches what the user sees after native navigation.
  /// Keep the resulting selection in this controller so Flutter, Inspector
  /// and the renderer continue to share one selection authority.
  Future<Object?> _handleNativeCallback(MethodCall call) async {
    if (call.method != 'objectTapped') {
      return null;
    }
    final payload = call.arguments as Map<Object?, Object?>?;
    final elementId = payload?['elementId']?.toString();
    await selectElement(elementId);
    await highlightElement(elementId);
    return null;
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
      _sectionBox = null;
      _sectionView = null;
    }

    notifyListeners();

    await _invoke('loadRenderSceneJson', jsonEncode(scene.toJson()));
    await _syncNativeBridge();
  }

  @override
  Future<void> clearScene() async {
    _scene = null;
    _selectedElementIds = <String>{};
    _activeElementId = null;
    _selectedLevelId = null;
    _highlightedElementId = null;
    _sceneBounds = RenderSceneBounds.zero();
    _sectionBox = null;
    _sectionView = null;
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
    _selectionRectangle = null;
    _selectionRectangleCrossing = false;

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
    final descriptor = _projectionMode.planarDescriptor;
    final width = descriptor != null
        ? math.max(descriptor.boundsWidth(bounds), 1.0)
        : math.max(bounds.width, 1.0);
    final height = descriptor != null
        ? math.max(descriptor.boundsHeight(bounds), 1.0)
        : math.max(bounds.depth, 1.0);
    return math
        .min(usableWidth / width, usableHeight / height)
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

    final previousMode = _projectionMode;
    _projectionMode = mode;
    if (mode.is3D && previousMode.isElevation) {
      final sourceSpec = previousMode.spec;
      if (sourceSpec.orbitYawRadians != null) {
        _orbitYawRadians = sourceSpec.orbitYawRadians!;
      }
      if (sourceSpec.orbitPitchRadians != null) {
        _orbitPitchRadians = sourceSpec.orbitPitchRadians!;
      }
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

  /// Native ClipVolume for the live 3D viewport. It clips render triangles
  /// only; the document and quantity model remain whole and authoritative.
  Future<void> setSectionBox(RenderSceneBounds? bounds) async {
    _sectionBox = bounds;
    if (bounds != null) _sectionView = null;
    notifyListeners();
    await _invoke('setSectionBox', <String, Object?>{
      'enabled': bounds != null,
      if (bounds != null) 'min': bounds.min.toJson(),
      if (bounds != null) 'max': bounds.max.toJson(),
    });
  }

  /// Activates an architectural section on the authoritative full scene.
  /// Android uses the same native ClipVolume implementation as Section Box.
  Future<void> setSectionView(RenderSceneSection? section) async {
    _sectionView = section;
    if (section != null) _sectionBox = null;
    notifyListeners();
    await _invoke('setSectionView', <String, Object?>{
      'enabled': section != null,
      if (section != null) 'start': section.start.toJson(),
      if (section != null) 'end': section.end.toJson(),
    });
  }

  @override
  Future<void> setBackend(RenderSceneViewportBackend backend) async {
    if (_backend == backend) {
      return;
    }

    _backend = backend;
    notifyListeners();
    await _syncNativeBridge();
  }

  @override
  Future<void> setInteractionMode(RenderSceneInteractionMode mode) async {
    if (_interactionMode == mode) {
      return;
    }

    _interactionMode = mode;
    if (mode.requiresPlanProjection &&
        _projectionMode != kDefaultPlanProjectionMode) {
      _projectionMode = kDefaultPlanProjectionMode;
    }

    notifyListeners();
    await _syncNativeBridge();
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

  /// Shared transient state for the Flutter painter and the Android renderer.
  /// Selection decisions stay in [ViewportInteractionController].
  void setSelectionRectangle(Rect? rectangle, {bool crossing = false}) {
    if (_selectionRectangle == rectangle &&
        _selectionRectangleCrossing == crossing) {
      return;
    }
    _selectionRectangle = rectangle;
    _selectionRectangleCrossing = rectangle == null ? false : crossing;
    notifyListeners();
    unawaited(_invoke('setSelectionRectangle', <String, Object?>{
      'left': rectangle?.left,
      'top': rectangle?.top,
      'right': rectangle?.right,
      'bottom': rectangle?.bottom,
      'crossing': _selectionRectangleCrossing,
    }));
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
    final descriptor = _projectionMode.planarDescriptor;
    if (descriptor == null) {
      return;
    }

    final zoom = math.max(_planCamera.zoom, 1e-6);
    _planCamera = _planCamera.copyWith(
      center: descriptor.planarPan(_planCamera.center, delta, zoom),
    );
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  @override
  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  }) {
    if (!_projectionMode.isPlanar) {
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
      nextCenter = addPoint(
        zoomedCamera.center,
        subtractPoint(before, after),
      );
    }

    _planCamera = RenderScenePlanCameraState(
      center: nextCenter,
      zoom: nextZoom,
    );
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  @override
  void orbitBy(Offset delta, Size viewportSize) {
    if (!_projectionMode.is3D) {
      return;
    }

    final minDimension =
        math.max(math.min(viewportSize.width, viewportSize.height), 1.0);
    // Dragging left must turn the model left. Pitch intentionally keeps its
    // existing sign because vertical tablet motion already matches expectation.
    _orbitYawRadians -= delta.dx / minDimension * math.pi * 1.25;
    _orbitPitchRadians =
        (_orbitPitchRadians + delta.dy / minDimension * math.pi * 0.95)
            .clamp(-math.pi / 2.0 + 0.12, math.pi / 2.0 - 0.12);
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  @override
  void panOrbitBy(Offset delta, Size viewportSize) {
    if (!_projectionMode.is3D) {
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
    _scheduleNativeCameraSync();
  }

  @override
  void zoomOrbit(double scaleDelta) {
    if (!_projectionMode.is3D) {
      return;
    }

    // Zooming an orbit camera through its target makes an entire storey
    // disappear behind the near clip plane. Keep a model-relative stand-off
    // distance instead; direct object inspection remains available through
    // selection/Inspector and later section tools.
    final maxExtent = math.max(
      _sceneBounds.width,
      math.max(_sceneBounds.depth, _sceneBounds.height),
    );
    // Keep enough stand-off for a stable depth buffer, while still allowing a
    // normal house/storey to fill the viewport for authoring.
    final minimumDistance = math.max(maxExtent * 0.30, 1.75);
    final maximumZoom = _orbitDistance / minimumDistance;
    _orbitZoomScale =
        (_orbitZoomScale * scaleDelta).clamp(0.005, math.max(maximumZoom, 1.0));
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  @override
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize) {
    if (!_projectionMode.isPlanar) {
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
    await selectElements(
      elementId == null ? <String>{} : <String>{elementId},
      activeElementId: elementId,
    );
  }

  @override
  Future<void> selectElements(
    Set<String> elementIds, {
    String? activeElementId,
  }) async {
    final normalized = Set<String>.from(elementIds);
    final resolvedActive =
        activeElementId != null && normalized.contains(activeElementId)
            ? activeElementId
            : (normalized.isEmpty ? null : normalized.last);
    if (setEquals(_selectedElementIds, normalized) &&
        _activeElementId == resolvedActive) {
      return;
    }
    _selectedElementIds = normalized;
    _activeElementId = resolvedActive;
    _selectedLevelId = null;
    notifyListeners();
    await _invoke('setSelection', <String, Object?>{
      'ids': normalized.toList(),
      'activeId': resolvedActive,
    });
    setSelectionRectangle(null);
  }

  @override
  Future<void> selectLevel(int? levelId) async {
    if (_selectedLevelId == levelId &&
        (levelId != null || _selectedElementIds.isEmpty)) {
      return;
    }
    final nativeHighlightMustClear = _highlightedElementId != null;
    _selectedLevelId = levelId;
    _selectedElementIds = <String>{};
    _activeElementId = null;
    _highlightedElementId = null;
    notifyListeners();
    await _invoke('setSelection', <String, Object?>{
      'ids': const <String>[],
      'activeId': null,
      'levelId': levelId,
    });
    // `setSelection` clears the selection tint but intentionally does not
    // own hover/preview tint. Clear that native state explicitly before the
    // local null value makes [highlightElement] a no-op.
    if (nativeHighlightMustClear) {
      await _invoke('highlightElement', null);
    }
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

  /// Delegates a 3D tap to Filament after keeping its coordinates independent
  /// of Android's physical-pixel and rotation transforms.
  Future<void> pickNativeAt(Offset localPosition, Size viewportSize) async {
    if (_projectionMode.is3D == false || viewportSize.isEmpty) {
      return;
    }
    await _invoke('pickNormalized', <String, double>{
      'x': (localPosition.dx / viewportSize.width).clamp(0.0, 1.0),
      'y': (localPosition.dy / viewportSize.height).clamp(0.0, 1.0),
    });
  }

  Future<void> _syncNativeBridge() async {
    final currentScene = _scene;
    if (currentScene != null) {
      await _invoke('loadRenderSceneJson', jsonEncode(currentScene.toJson()));
    }

    await _invoke('setVisibleKinds', _visibleKinds.toList());
    final sectionBox = _sectionBox;
    await _invoke('setSectionBox', <String, Object?>{
      'enabled': sectionBox != null,
      if (sectionBox != null) 'min': sectionBox.min.toJson(),
      if (sectionBox != null) 'max': sectionBox.max.toJson(),
    });
    await _invoke('setDisplayStyle', _displayStyle.name);
    await _invoke('setProjectionMode', _projectionMode.name);
    await _invoke('setOrbitProjectionStyle', _orbitProjectionStyle.name);
    await _invoke('setCamera', _nativeCameraPayload());
    final sectionView = _sectionView;
    await _invoke('setSectionView', <String, Object?>{
      'enabled': sectionView != null,
      if (sectionView != null) 'start': sectionView.start.toJson(),
      if (sectionView != null) 'end': sectionView.end.toJson(),
    });
    await _invoke('setSelection', <String, Object?>{
      'ids': _selectedElementIds.toList(),
      'activeId': _activeElementId,
    });
    await _invoke('highlightElement', _highlightedElementId);
    final rectangle = _selectionRectangle;
    await _invoke('setSelectionRectangle', <String, Object?>{
      'left': rectangle?.left,
      'top': rectangle?.top,
      'right': rectangle?.right,
      'bottom': rectangle?.bottom,
      'crossing': _selectionRectangleCrossing,
    });
  }

  void _scheduleNativeCameraSync() {
    unawaited(_invoke('setCamera', _nativeCameraPayload()));
  }

  Map<String, Object?> _nativeCameraPayload() {
    final orbitCenter = _orbitCenter;
    final planCenter = _planCamera.center;
    return <String, Object?>{
      'orbitCenter': <String, double>{
        'x': orbitCenter.x,
        'y': orbitCenter.y,
        'z': orbitCenter.z,
      },
      'orbitYawRadians': _orbitYawRadians,
      'orbitPitchRadians': _orbitPitchRadians,
      'orbitDistance': _orbitDistance,
      'orbitZoomScale': _orbitZoomScale,
      'planCenter': <String, double>{
        'x': planCenter.x,
        'y': planCenter.y,
        'z': planCenter.z,
      },
      'planZoom': _planCamera.zoom,
      // `planZoom` is expressed in Flutter logical pixels per metre.  The
      // Android PlatformView is measured in physical pixels, so it must not
      // infer a world-space orthographic size from a fixed pixel constant.
      'planViewportHeight': _viewportSize.height,
    };
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
    final descriptor = _projectionMode.planarDescriptor;
    if (descriptor == null) {
      return cameraState.center;
    }
    return descriptor.screenToModel(
      localPosition: localPosition,
      viewportCenter: viewportCenter,
      cameraState: cameraState,
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
