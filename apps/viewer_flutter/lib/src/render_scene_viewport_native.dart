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
    await _invoke('setShadowsEnabled', _shadowsEnabled);
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
}
