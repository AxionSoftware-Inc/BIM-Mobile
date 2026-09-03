part of 'render_scene_viewport_controller.dart';

extension _RenderSceneViewportCamera on RenderSceneViewportController {
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
    if (bounds.width <= 1e-6 && bounds.depth <= 1e-6) {
      // The zoom is derived from the actual post-layout viewport size.
      _planCamera = RenderScenePlanCameraState(
        center: const RenderScenePoint(x: 0, y: 0, z: 0),
        zoom: RenderSceneViewportController._emptyPlanZoomForViewport(
            _viewportSize),
      );
      return;
    }
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
    if (viewportSize.width <= RenderSceneViewportController._planPadding * 2 ||
        viewportSize.height <= RenderSceneViewportController._planPadding * 2) {
      return 1.0;
    }

    final usableWidth = math.max(
        viewportSize.width - RenderSceneViewportController._planPadding * 2,
        1.0);
    final usableHeight = math.max(
        viewportSize.height - RenderSceneViewportController._planPadding * 2,
        1.0);
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

  void _scheduleViewportRefit() {
    if (_viewportRefitScheduled) {
      return;
    }
    // The first layout of a newly opened project can schedule a refit while
    // the user is already drawing its first wall. Do not apply that stale
    // callback to a newer authoritative scene: it changes the plan zoom under
    // the finger and makes the next chained wall start at a different model
    // point than the one visible on screen.
    final scheduledSceneRevision = _sceneRevision;
    _viewportRefitScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _viewportRefitScheduled = false;
      if (_viewportSize == Size.zero ||
          _sceneRevision != scheduledSceneRevision) {
        return;
      }
      _resetPlanForBounds(_scene?.bounds ?? _sceneBounds);
      _notifyViewportListeners();
      _scheduleNativeCameraSync();
    });
  }

  void _scheduleNativeCameraSync() {
    if (_nativeCameraSyncScheduled) {
      return;
    }
    _nativeCameraSyncScheduled = true;
    // Pointer events can arrive several times before Flutter presents the
    // next frame. Send only the newest camera state once per frame; otherwise
    // MethodChannel calls queue up and make planar tablet navigation visibly
    // lag behind the finger.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _nativeCameraSyncScheduled = false;
      unawaited(_invoke('setCamera', _nativeCameraPayload()));
    });
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
    if (channel == null || _backend != RenderSceneViewportBackend.native) {
      return;
    }

    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _switchToFallback('Native viewport method "$method" is unavailable.');
    } on PlatformException {
      _switchToFallback('Native viewport method "$method" failed.');
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
