import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'render_scene_viewport_types.dart';
import 'render_scene_viewport_planar.dart';

/// Single owner for two-finger, wheel, and trackpad camera navigation.
///
/// The controller contains no widget state, scene picking, or engine calls.
/// It only translates platform gesture deltas into the shared camera target.
/// This prevents section/sheet/native-overlay hosts from reimplementing zoom
/// and pan rules independently.
final class ViewportGestureController {
  double _previousScale = 1.0;
  Offset? _previousFocalPoint;
  double _trackpadPreviousScale = 1.0;

  void handleScaleStart(
    ScaleStartDetails details, {
    required ViewportCameraTarget target,
    required bool nativeOwned,
  }) {
    if (nativeOwned) return;
    _previousScale = 1.0;
    _previousFocalPoint = details.localFocalPoint;
  }

  void handleScaleUpdate(
    ScaleUpdateDetails details, {
    required ViewportCameraTarget target,
    required Size viewportSize,
    required bool nativeOwned,
  }) {
    if (nativeOwned || details.pointerCount < 2) return;

    final previousFocal = _previousFocalPoint ?? details.localFocalPoint;
    final focalDelta = details.localFocalPoint - previousFocal;
    final scaleDelta =
        (details.scale / _previousScale).clamp(0.5, 1.5).toDouble();

    _applyCameraDelta(
      target: target,
      viewportSize: viewportSize,
      focalPoint: details.localFocalPoint,
      focalDelta: focalDelta,
      scaleDelta: scaleDelta,
    );
    _previousScale = details.scale;
    _previousFocalPoint = details.localFocalPoint;
  }

  void handleScaleEnd({required bool nativeOwned}) {
    if (nativeOwned) return;
    _previousScale = 1.0;
    _previousFocalPoint = null;
  }

  void handlePointerSignal(
    PointerSignalEvent event, {
    required ViewportCameraTarget target,
    required Size viewportSize,
    required bool nativeOwned,
  }) {
    if (nativeOwned || event is! PointerScrollEvent) return;

    final scaleDelta = event.scrollDelta.dy > 0 ? 0.90 : 1.10;
    if (target.projectionMode.isPlanar) {
      target.zoomPlanBy(
        scaleDelta,
        focalPoint: event.localPosition,
        viewportSize: viewportSize,
      );
    } else {
      target.zoomOrbit(scaleDelta);
    }
  }

  void handleTrackpadStart({required bool nativeOwned}) {
    if (nativeOwned) return;
    _trackpadPreviousScale = 1.0;
  }

  void handleTrackpadUpdate(
    PointerPanZoomUpdateEvent event, {
    required ViewportCameraTarget target,
    required Size viewportSize,
    required bool nativeOwned,
  }) {
    if (nativeOwned) return;

    if (target.projectionMode.isPlanar) {
      if (event.panDelta.distanceSquared > 0.0) {
        target.panPlanBy(event.panDelta);
      }
      target.zoomPlanBy(
        (event.scale / _trackpadPreviousScale).clamp(0.5, 1.5).toDouble(),
        focalPoint: viewportSize.center(Offset.zero),
        viewportSize: viewportSize,
      );
      _trackpadPreviousScale = event.scale;
      return;
    }

    if (event.panDelta.distanceSquared > 0.0) {
      target.orbitBy(
        Offset(-event.panDelta.dx * 0.9, event.panDelta.dy * 0.9),
        viewportSize,
      );
    }
    target.zoomOrbit(
      (event.scale / _trackpadPreviousScale).clamp(0.5, 1.5).toDouble(),
    );
    _trackpadPreviousScale = event.scale;
  }

  void handleTrackpadEnd({required bool nativeOwned}) {
    if (nativeOwned) return;
    _trackpadPreviousScale = 1.0;
  }

  void handleSecondaryDrag(
    Offset delta, {
    required ViewportCameraTarget target,
    required Size viewportSize,
    required bool nativeOwned,
  }) {
    if (nativeOwned || target.projectionMode.isPlanar) return;
    target.panOrbitBy(delta, viewportSize);
  }

  void reset() {
    _previousScale = 1.0;
    _previousFocalPoint = null;
    _trackpadPreviousScale = 1.0;
  }

  void _applyCameraDelta({
    required ViewportCameraTarget target,
    required Size viewportSize,
    required Offset focalPoint,
    required Offset focalDelta,
    required double scaleDelta,
  }) {
    if (target.projectionMode.isPlanar) {
      if (focalDelta.distanceSquared > 0.0) {
        target.panPlanBy(focalDelta);
      }
      target.zoomPlanBy(
        scaleDelta,
        focalPoint: focalPoint,
        viewportSize: viewportSize,
      );
      return;
    }

    // Two-finger orbit navigation pans the target and zooms together.
    if (focalDelta.distanceSquared > 0.0) {
      target.panOrbitBy(focalDelta, viewportSize);
    }
    target.zoomOrbit(scaleDelta);
  }
}
