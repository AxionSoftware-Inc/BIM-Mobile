part of 'render_scene_viewport_controller.dart';

extension _RenderSceneViewportNative on RenderSceneViewportController {
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

  Future<void> _syncNativeBridge({
    bool includeScene = true,
    bool includeVisibleKinds = true,
  }) {
    return _runNativeBridgeBatch<void>(() async {
      await _loadRememberedNativeBimCacheNow();
      await _syncNativeBridgeStateNow(
        includeScene: includeScene,
        includeVisibleKinds: includeVisibleKinds,
      );
    });
  }

  Future<void> _syncNativeBridgeStateNow({
    bool includeScene = true,
    bool includeVisibleKinds = true,
  }) async {
    if (_backend != RenderSceneViewportBackend.native) return;
    final currentScene = _scene;
    if (includeScene && currentScene != null && !_nativeGeometryActive) {
      await _invokeNow(
        'loadRenderSceneJson',
        jsonEncode(_nativeScenePayload(currentScene)),
      );
    }

    if (includeVisibleKinds) {
      await _invokeNow('setVisibleKinds', _visibleKinds.toList());
    }
    final sectionBox = _sectionBox;
    await _invokeNow('setSectionBox', <String, Object?>{
      'enabled': sectionBox != null,
      if (sectionBox != null) 'min': sectionBox.min.toJson(),
      if (sectionBox != null) 'max': sectionBox.max.toJson(),
    });
    await _invokeNow('setDisplayStyle', _displayStyle.name);
    await _invokeNow('setViewportTheme', _viewportTheme.name);
    await _invokeNow('setHdriVisible', _hdriVisible);
    await _invokeNow('setShadowsEnabled', _shadowsEnabled);
    await _invokeNow('setProjectionMode', _projectionMode.name);
    await _invokeNow('setOrbitProjectionStyle', _orbitProjectionStyle.name);
    await _invokeNow('setCamera', _nativeCameraPayload());
    final sectionView = _sectionView;
    await _invokeNow('setSectionView', <String, Object?>{
      'enabled': sectionView != null,
      if (sectionView != null) 'start': sectionView.start.toJson(),
      if (sectionView != null) 'end': sectionView.end.toJson(),
    });
    await _invokeNow('setSelection', <String, Object?>{
      'ids': _selectedElementIds.toList(),
      'activeId': _activeElementId,
    });
    await _invokeNow('highlightElement', _highlightedElementId);
    final rectangle = _selectionRectangle;
    await _invokeNow('setSelectionRectangle', <String, Object?>{
      'left': rectangle?.left,
      'top': rectangle?.top,
      'right': rectangle?.right,
      'bottom': rectangle?.bottom,
      'crossing': _selectionRectangleCrossing,
    });
  }

  /// Keep the Android plan representation semantic and cheap. Family
  /// instances still keep their bounds and metadata for picking, but their
  /// 3D mesh is deliberately omitted while the native projection is 2D. The
  /// selection overlay draws the persisted family plan symbol instead. When
  /// switching to 3D this method returns the authoritative scene unchanged.
  Map<String, Object?> _nativeScenePayload(RenderScene scene) {
    final payload = Map<String, Object?>.from(scene.toJson());
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return payload;
    }

    final objects = <Map<String, Object?>>[];
    var vertexCount = 0;
    var indexCount = 0;
    for (final object in scene.objects) {
      final encoded = Map<String, Object?>.from(object.toJson());
      final assetId = object.metadata['family_asset_id'];
      final isFamilyPlanObject =
          (object.kindKey == 'column' || object.kindKey == 'proxy') &&
              assetId != null &&
              assetId.toString().trim().isNotEmpty;
      if (isFamilyPlanObject) {
        encoded['mesh'] = RenderSceneMesh.empty().toJson();
        encoded.remove('feature_edges');
      } else {
        vertexCount += object.mesh.positions.length;
        indexCount += object.mesh.indices.length;
      }
      objects.add(encoded);
    }
    payload['object_count'] = objects.length;
    payload['vertex_count'] = vertexCount;
    payload['index_count'] = indexCount;
    payload['objects'] = objects;
    return payload;
  }

  Future<void> _loadRememberedNativeBimCache() async {
    await _runNativeBridgeBatch<void>(_loadRememberedNativeBimCacheNow);
  }

  Future<void> _loadRememberedNativeBimCacheNow() async {
    final request = _nativeCacheRequest;
    if (request == null ||
        !_nativeCacheNeedsReplay ||
        _channel == null ||
        _backend != RenderSceneViewportBackend.native ||
        _disposed) {
      return;
    }
    _nativeCacheNeedsReplay = false;
    _nativeGeometryActive = false;
    await _invokeNow('loadNativeBimCache', request);
    if (_backend == RenderSceneViewportBackend.native && _channel != null) {
      _nativeGeometryActive = true;
    }
  }
}
