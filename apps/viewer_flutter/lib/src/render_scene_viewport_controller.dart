import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'async_serial_queue.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

part 'render_scene_viewport_camera.dart';
part 'render_scene_viewport_native.dart';

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
  // Blank projects have no geometry yet. Do not treat their zero-sized bounds
  // as a one-metre object: that makes the first wall fill the tablet and
  // leaves no comfortable working area for subsequent segments.
  static const double _emptyPlanMeters = 30.0;

  RenderScene? _scene;
  Set<String> _visibleKinds;
  Set<String> _selectedElementIds = <String>{};
  String? _activeElementId;
  int? _selectedLevelId;
  String? _highlightedElementId;

  int _fitRevision = 0;
  int _sceneRevision = 0;
  bool _nativeCameraSyncScheduled = false;
  bool _nativeCameraSyncPending = false;
  bool _nativeCameraSyncSending = false;
  bool _cameraNotificationScheduled = false;
  bool _draftNotificationScheduled = false;
  bool _objectMoveBridgeScheduled = false;
  bool _objectMoveBridgePending = false;
  bool _objectMoveBridgeSending = false;
  RenderSceneObjectMoveDraft? _pendingObjectMoveBridgeDraft;
  bool _selectionRectangleBridgeScheduled = false;
  bool _selectionRectangleBridgePending = false;
  bool _selectionRectangleBridgeSending = false;
  Map<String, Object?>? _pendingSelectionRectanglePayload;
  bool _disposed = false;
  // When true, Filament owns all large geometry through a validated
  // `.bimcache`; Flutter retains only the compact semantic envelope.
  bool _nativeGeometryActive = false;
  // Keep the last cache request so a PlatformView recreation can restore the
  // native geometry without asking Dart to resend a large JSON mesh payload.
  Map<String, Object?>? _nativeCacheRequest;
  bool _nativeCacheNeedsReplay = false;

  RenderSceneProjectionMode _projectionMode = kDefaultPlanProjectionMode;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.orthographic;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneViewportTheme _viewportTheme = RenderSceneViewportTheme.light;
  bool _shadowsEnabled = false;
  bool _hdriVisible = false;
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
  RenderSceneWallArcDraft? _draftWallArc;
  RenderSceneOpeningDraft? _draftOpening;
  RenderSceneSurfaceDraft? _draftSurface;
  RenderSceneObjectMoveDraft? _draftObjectMove;
  Rect? _selectionRectangle;
  bool _selectionRectangleCrossing = false;

  MethodChannel? _channel;
  // Every native command, including camera/selection updates, must share one
  // FIFO lane. MethodChannel calls can otherwise overlap while the Android
  // renderer is rebuilding a scene, leaving old transforms or selection
  // overlays visible over a newer model state.
  final AsyncSerialQueue _nativeBridgeQueue = AsyncSerialQueue();
  Completer<void>? _nativeBridgeReady;
  String? _nativeBridgeError;

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
  RenderSceneViewportTheme get viewportTheme => _viewportTheme;

  @override
  bool get shadowsEnabled => _shadowsEnabled;

  @override
  bool get hdriVisible => _hdriVisible;

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
  RenderSceneWallArcDraft? get draftWallArc => _draftWallArc;

  @override
  RenderSceneOpeningDraft? get draftOpening => _draftOpening;

  @override
  RenderSceneSurfaceDraft? get draftSurface => _draftSurface;

  @override
  RenderSceneObjectMoveDraft? get draftObjectMove => _draftObjectMove;

  Rect? get selectionRectangle => _selectionRectangle;
  bool get selectionRectangleCrossing => _selectionRectangleCrossing;

  bool get hasNativeBridge => _channel != null;

  /// Non-null only after the Android bridge failed and the controller moved
  /// to the Flutter renderer. The workspace can surface this diagnostic while
  /// still keeping the model interactive.
  String? get nativeBridgeError => _nativeBridgeError;

  void _switchToFallback(String message) {
    if (_backend != RenderSceneViewportBackend.native ||
        defaultTargetPlatform != TargetPlatform.android ||
        _disposed) {
      return;
    }
    _nativeGeometryActive = false;
    _nativeBridgeError = message;
    _backend = RenderSceneViewportBackend.fallback;
    notifyListeners();
  }

  /// True while the live Android viewport owns the IFC mesh through the
  /// engine-backed `.bimcache`. Navigation must not replace that geometry
  /// with the legacy JSON scene just to change projection or scope.
  bool get hasNativeGeometry => _nativeGeometryActive;

  /// Waits for the PlatformView channel created after a lightweight loading
  /// scene has mounted.  IFC import starts from the start screen, where the
  /// native view does not exist yet; this lets the native-first cache path
  /// begin without ever serializing a full mesh scene to Dart first.
  Future<bool> waitForNativeBridge({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_channel != null) return true;
    final ready = _nativeBridgeReady ??= Completer<void>();
    try {
      await ready.future.timeout(timeout);
    } on TimeoutException {
      _switchToFallback('Native viewport bridge timed out.');
      return false;
    }
    return _channel != null;
  }

  RenderSceneBounds get sceneBounds => _scene?.bounds ?? _sceneBounds;
  RenderSceneBounds? get sectionBox => _sectionBox;
  bool get hasSectionBox => _sectionBox != null;
  bool get hasSectionView => _sectionView != null;

  /// Flutter owns planar section/elevation gestures so the model, levels and
  /// hit testing all use the same [RenderScenePlanarDescriptor]. Native keeps
  /// interaction for the 3D Section Box, whose handles live in Filament.
  bool get nativeOwnsClipGestures =>
      _sectionBox != null && _projectionMode.is3D;

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

  /// Replaces the Android renderer's JSON mesh payload with a validated
  /// engine-owned IFC cache. Flutter keeps the semantic/2D scene authority;
  /// only the large 3D vertex and index buffers bypass Dart.
  Future<void> loadNativeBimCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    _nativeCacheRequest = <String, Object?>{
      'sourceIfcPath': sourceIfcPath,
      'cachePath': cachePath,
    };
    _nativeCacheNeedsReplay = true;
    _nativeGeometryActive = false;
    await _loadRememberedNativeBimCache();
  }

  /// Validates/reopens a cache, or compiles it natively on a background
  /// Android thread. The returned scene contains element metadata and bounds
  /// only; all mesh buffers remain native DirectByteBuffers for Filament.
  Future<Map<Object?, Object?>?> prepareNativeBimCache({
    required String sourceIfcPath,
    required String cachePath,
  }) async {
    _nativeCacheRequest = <String, Object?>{
      'sourceIfcPath': sourceIfcPath,
      'cachePath': cachePath,
    };
    _nativeCacheNeedsReplay = true;
    _nativeGeometryActive = false;
    return _runNativeBridgeBatch<Map<Object?, Object?>?>(() async {
      final channel = _channel;
      if (channel == null) return null;
      try {
        final result = await channel.invokeMapMethod<Object?, Object?>(
          'prepareNativeBimCache',
          <String, Object?>{
            'sourceIfcPath': sourceIfcPath,
            'cachePath': cachePath,
          },
        );
        if (result != null) {
          _nativeGeometryActive = true;
          _nativeCacheNeedsReplay = false;
        } else {
          _nativeCacheNeedsReplay = false;
        }
        return result;
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    });
  }

  Future<void> attachNativeBridge(int viewId) async {
    _channel = MethodChannel('tbe/render_scene_view_$viewId');
    _channel!.setMethodCallHandler(_handleNativeCallback);
    final ready = _nativeBridgeReady;
    if (ready != null && !ready.isCompleted) ready.complete();
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
    // The Android PlatformView may be recreated while the Flutter controller
    // survives (for example after a route/lifecycle transition). Its native
    // scene is gone with the old view, so replay the remembered cache request
    // when the new channel attaches.
    _nativeGeometryActive = false;
    _nativeCacheNeedsReplay = _nativeCacheRequest != null;
    _nativeBridgeReady = null;
  }

  @override
  Future<void> loadRenderScene(RenderScene scene) async {
    await updateRenderScene(scene, resetView: true);
  }

  Future<void> updateRenderScene(
    RenderScene scene, {
    bool resetView = false,
    bool preserveNativeGeometry = false,
    Set<String>? visibleKinds,
  }) async {
    final contractIssues = RenderSceneCoordinateContract.issuesForScene(scene);
    if (contractIssues.isNotEmpty) {
      throw ArgumentError.value(
        scene,
        'scene',
        'RenderScene contract rejected: ${contractIssues.join(' ')}',
      );
    }
    if (!preserveNativeGeometry) {
      _nativeGeometryActive = false;
      _nativeCacheRequest = null;
      _nativeCacheNeedsReplay = false;
    }
    if (visibleKinds != null) {
      _visibleKinds = visibleKinds.toSet();
    }
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

    // Apply the category policy and scene in one native transaction. Without
    // this boundary, a visibility/camera/selection command from another
    // gesture could land between the scene load and its state synchronization,
    // producing a mixed frame where some elements move and others appear
    // frozen.
    await _runNativeBridgeBatch<void>(() async {
      if (_backend != RenderSceneViewportBackend.native) return;
      await _loadRememberedNativeBimCacheNow();
      if (visibleKinds != null) {
        await _invokeNow('setVisibleKinds', _visibleKinds.toList());
      }
      if (!_nativeGeometryActive) {
        await _invokeNow(
          'loadRenderSceneJson',
          jsonEncode(_nativeScenePayload(scene)),
        );
      }
      // The authoritative scene was just sent above. The remaining bridge
      // synchronization is state-only; sending the same JSON again here made
      // every authoring commit enter the native scene loader twice.
      await _syncNativeBridgeStateNow(
        includeScene: false,
        includeVisibleKinds: visibleKinds == null,
      );
    });
  }

  Future<void> loadNativeSceneSummary(RenderScene scene) =>
      updateRenderScene(scene, resetView: true, preserveNativeGeometry: true);

  @override
  Future<void> clearScene() async {
    _nativeGeometryActive = false;
    _nativeCacheRequest = null;
    _nativeCacheNeedsReplay = false;
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
    _draftObjectMove = null;
    _pendingObjectMoveBridgeDraft = null;
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
    // Native fit uses renderable bounds and is only a surface-level fallback.
    // Re-apply Flutter's plan camera after it so a floor plan cannot open with
    // the native 3D framing and require a gesture to recover.
    _scheduleNativeCameraSync();
  }

  static double _emptyPlanZoomForViewport(Size viewportSize) {
    if (viewportSize.height <= _planPadding * 2) {
      // The first scene update can happen before PlatformView layout. The
      // post-layout refit replaces this provisional value with the exact
      // 30-metre viewport scale.
      return 40.0;
    }
    final usableHeight = math.max(viewportSize.height - _planPadding * 2, 1.0);
    return usableHeight / _emptyPlanMeters;
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

  @override
  Future<void> setViewportTheme(RenderSceneViewportTheme theme) async {
    if (_viewportTheme == theme) return;
    _viewportTheme = theme;
    notifyListeners();
    await _invoke('setViewportTheme', theme.name);
  }

  @override
  Future<void> setHdriVisible(bool visible) async {
    if (_hdriVisible == visible) return;
    _hdriVisible = visible;
    notifyListeners();
    await _invoke('setHdriVisible', visible);
  }

  @override
  Future<void> setShadowsEnabled(bool enabled) async {
    if (_shadowsEnabled == enabled) return;
    _shadowsEnabled = enabled;
    notifyListeners();
    await _invoke('setShadowsEnabled', enabled);
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
    if (backend == RenderSceneViewportBackend.native) {
      _nativeBridgeError = null;
      _nativeCacheNeedsReplay = _nativeCacheRequest != null;
    }
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
    _draftWallArc = null;
    _scheduleDraftNotification();
  }

  @override
  void setWallArcDraft(RenderSceneWallArcDraft? draft) {
    _draftWallArc = draft;
    if (draft != null) {
      _draftWallStart = null;
      _draftWallEnd = null;
    }
    _scheduleDraftNotification();
  }

  @override
  void setOpeningDraft(RenderSceneOpeningDraft? draft) {
    _draftOpening = draft;
    _scheduleDraftNotification();
  }

  @override
  void setSurfaceDraft(RenderSceneSurfaceDraft? draft) {
    _draftSurface = draft;
    _scheduleDraftNotification();
  }

  @override
  void setObjectMoveDraft(RenderSceneObjectMoveDraft? draft) {
    _draftObjectMove = draft;
    _scheduleDraftNotification();
    _pendingObjectMoveBridgeDraft = draft;
    _objectMoveBridgePending = true;
    _scheduleObjectMoveBridge();
  }

  @override
  void clearDraft() {
    _draftWallStart = null;
    _draftWallEnd = null;
    _draftWallArc = null;
    _draftOpening = null;
    _draftSurface = null;
    setObjectMoveDraft(null);
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
    _pendingSelectionRectanglePayload = <String, Object?>{
      'left': rectangle?.left,
      'top': rectangle?.top,
      'right': rectangle?.right,
      'bottom': rectangle?.bottom,
      'crossing': _selectionRectangleCrossing,
    };
    _selectionRectangleBridgePending = true;
    _scheduleSelectionRectangleBridge();
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
    } else {
      // Android's TextureView fits itself when its physical size changes.
      // Re-send Flutter's authoritative plan camera after that resize so the
      // first frame cannot use the stale pre-layout zoom.
      _scheduleNativeCameraSync();
    }
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
    _scheduleCameraNotification();
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
    // Match the Android renderer's lower orthographic half-height.  Keeping
    // the two cameras on the same final zoom value prevents the native wall
    // contour and Flutter authoring overlays from landing on different pixels
    // when the user holds the pinch at its maximum.
    const minimumPlanHalfHeight = 0.50;
    final maximumPlanZoom = math.max(
      targetSize.height / (2.0 * minimumPlanHalfHeight),
      1.0,
    );
    final nextZoom =
        (oldZoom * scaleDelta).clamp(0.1, maximumPlanZoom).toDouble();
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
    _scheduleCameraNotification();
    _scheduleNativeCameraSync();
  }

  @override
  void orbitBy(Offset delta, Size viewportSize) {
    if (!_projectionMode.is3D) {
      return;
    }

    final minDimension =
        math.max(math.min(viewportSize.width, viewportSize.height), 1.0);
    // Horizontal orbit follows the finger. Keep this sign aligned with the
    // native Android gesture path so tablet and fallback input feel identical.
    _orbitYawRadians += delta.dx / minDimension * math.pi * 1.25;
    _orbitPitchRadians =
        (_orbitPitchRadians + delta.dy / minDimension * math.pi * 0.95)
            .clamp(-math.pi / 2.0 + 0.12, math.pi / 2.0 - 0.12);
    _clampOrbitZoomToSceneBounds();
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
    _clampOrbitZoomToSceneBounds();
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  @override
  void zoomOrbit(double scaleDelta) {
    if (!_projectionMode.is3D) {
      return;
    }

    // Close inspection is intentional, but do not allow the orbit eye to
    // enter the model envelope. Once the eye crosses a wall/roof, perspective
    // near-clipping and coplanar BIM faces produce the familiar mobile
    // viewport shimmer. Native Android applies the same direction-aware limit.
    _orbitZoomScale = math.max(_orbitZoomScale * scaleDelta, 0.005);
    _clampOrbitZoomToSceneBounds();
    notifyListeners();
    _scheduleNativeCameraSync();
  }

  void _clampOrbitZoomToSceneBounds() {
    final minimumDistance = _minimumOrbitDistanceForScene();
    final maximumScale = math.max(_orbitDistance / minimumDistance, 0.005);
    _orbitZoomScale = math.min(_orbitZoomScale, maximumScale);
  }

  double _minimumOrbitDistanceForScene() {
    final bounds = _sceneBounds;
    final sceneSpan = math.max(
      bounds.width,
      math.max(bounds.height, bounds.depth),
    );
    if (!sceneSpan.isFinite || sceneSpan <= 1e-6) return 0.12;

    final direction = RenderScenePoint(
      x: math.cos(_orbitPitchRadians) * math.cos(_orbitYawRadians),
      y: math.sin(_orbitPitchRadians),
      z: math.cos(_orbitPitchRadians) * math.sin(_orbitYawRadians),
    );
    final margin = math.max(sceneSpan * 0.02, 0.20);
    var entry = -double.infinity;
    var exit = double.infinity;

    bool updateSlab(
        double component, double minimum, double maximum, double origin) {
      final slabMin = minimum - margin;
      final slabMax = maximum + margin;
      if (component.abs() <= 1e-9) {
        return origin >= slabMin && origin <= slabMax;
      }
      final first = (slabMin - origin) / component;
      final second = (slabMax - origin) / component;
      entry = math.max(entry, math.min(first, second));
      exit = math.min(exit, math.max(first, second));
      return true;
    }

    if (!updateSlab(direction.x, bounds.min.x, bounds.max.x, _orbitCenter.x) ||
        !updateSlab(direction.y, bounds.min.y, bounds.max.y, _orbitCenter.y) ||
        !updateSlab(direction.z, bounds.min.z, bounds.max.z, _orbitCenter.z)) {
      return 0.12;
    }
    if (exit < math.max(entry, 0.0)) return 0.12;
    final hitDistance = entry > 0 ? entry : exit;
    return math.max(
      0.12,
      hitDistance.isFinite && hitDistance > 0 ? hitDistance : 0.12,
    );
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
    final stableFallback = normalized.toList()..sort();
    final resolvedActive =
        activeElementId != null && normalized.contains(activeElementId)
            ? activeElementId
            : normalized.isEmpty
                ? null
                : normalized.contains(_activeElementId)
                    ? _activeElementId
                    : stableFallback.last;
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

  void _notifyViewportListeners() {
    notifyListeners();
  }

  /// Coalesce high-frequency pan/pinch samples to the display frame rate.
  ///
  /// Pointer events can arrive faster than Flutter can paint. Notifying every
  /// sample rebuilt the viewport and its Android platform-view wrapper several
  /// times per frame, which made planar navigation feel sticky on tablets.
  void _scheduleCameraNotification() {
    if (_cameraNotificationScheduled || _disposed) return;
    _cameraNotificationScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _cameraNotificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cameraNotificationScheduled = false;
    _draftNotificationScheduled = false;
    _objectMoveBridgeScheduled = false;
    _objectMoveBridgePending = false;
    _selectionRectangleBridgeScheduled = false;
    _selectionRectangleBridgePending = false;
    _nativeCameraSyncPending = false;
    super.dispose();
  }

  void _scheduleDraftNotification() {
    if (_draftNotificationScheduled || _disposed) return;
    _draftNotificationScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _draftNotificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Method-channel calls are asynchronous. Sending one call for every
  /// pointer sample lets Android queue stale transforms behind the newest
  /// one, which is perceived as lag even when the renderer itself is idle.
  /// Keep one in flight and retain only the latest frame-sized sample.
  void _scheduleObjectMoveBridge() {
    if (_objectMoveBridgeScheduled || _disposed) return;
    _objectMoveBridgeScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _objectMoveBridgeScheduled = false;
      if (!_disposed && _objectMoveBridgePending) {
        _flushObjectMoveBridge();
      }
    });
  }

  void _flushObjectMoveBridge() {
    if (_disposed || !_objectMoveBridgePending || _objectMoveBridgeSending) {
      return;
    }
    _objectMoveBridgePending = false;
    final pending = _pendingObjectMoveBridgeDraft;
    _objectMoveBridgeSending = true;
    unawaited(
      _invoke('setObjectMovePreview', <String, Object?>{
        'elementId': pending?.object.elementId,
        'deltaX': pending?.delta.x ?? 0.0,
        'deltaY': pending?.delta.y ?? 0.0,
      }).whenComplete(() {
        _objectMoveBridgeSending = false;
        if (_objectMoveBridgePending && !_disposed) {
          _scheduleObjectMoveBridge();
        }
      }),
    );
  }

  void _scheduleSelectionRectangleBridge() {
    if (_selectionRectangleBridgeScheduled || _disposed) return;
    _selectionRectangleBridgeScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _selectionRectangleBridgeScheduled = false;
      if (!_disposed && _selectionRectangleBridgePending) {
        _flushSelectionRectangleBridge();
      }
    });
  }

  void _flushSelectionRectangleBridge() {
    if (_disposed ||
        !_selectionRectangleBridgePending ||
        _selectionRectangleBridgeSending) {
      return;
    }
    _selectionRectangleBridgePending = false;
    final payload = _pendingSelectionRectanglePayload;
    _selectionRectangleBridgeSending = true;
    unawaited(
      _invoke('setSelectionRectangle', payload).whenComplete(() {
        _selectionRectangleBridgeSending = false;
        if (_selectionRectangleBridgePending && !_disposed) {
          _scheduleSelectionRectangleBridge();
        }
      }),
    );
  }
}
