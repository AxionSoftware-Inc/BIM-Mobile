import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';

enum RenderSceneAxis {
  x,
  y,
  z,
}

@immutable
class RenderScenePlanarDescriptor {
  const RenderScenePlanarDescriptor({
    required this.horizontalAxis,
    required this.verticalAxis,
    required this.depthAxis,
    this.horizontalSign = 1.0,
    this.verticalSign = 1.0,
    this.depthSign = 1.0,
  });

  final RenderSceneAxis horizontalAxis;
  final RenderSceneAxis verticalAxis;
  final RenderSceneAxis depthAxis;
  final double horizontalSign;
  final double verticalSign;
  final double depthSign;

  bool get isElevation => verticalAxis == RenderSceneAxis.z;

  double axisValue(RenderScenePoint point, RenderSceneAxis axis) {
    return switch (axis) {
      RenderSceneAxis.x => point.x,
      RenderSceneAxis.y => point.y,
      RenderSceneAxis.z => point.z,
    };
  }

  RenderScenePoint copyPointWithAxis(
    RenderScenePoint point,
    RenderSceneAxis axis,
    double value,
  ) {
    return switch (axis) {
      RenderSceneAxis.x => RenderScenePoint(x: value, y: point.y, z: point.z),
      RenderSceneAxis.y => RenderScenePoint(x: point.x, y: value, z: point.z),
      RenderSceneAxis.z => RenderScenePoint(x: point.x, y: point.y, z: value),
    };
  }

  RenderScenePoint planarPan(
    RenderScenePoint center,
    Offset delta,
    double zoom,
  ) {
    final horizontalValue =
        axisValue(center, horizontalAxis) - delta.dx / (zoom * horizontalSign);
    final verticalValue =
        axisValue(center, verticalAxis) + delta.dy / (zoom * verticalSign);
    return copyPointWithAxis(
      copyPointWithAxis(center, horizontalAxis, horizontalValue),
      verticalAxis,
      verticalValue,
    );
  }

  RenderScenePoint screenToModel({
    required Offset localPosition,
    required Offset viewportCenter,
    required RenderScenePlanCameraState cameraState,
  }) {
    final horizontalValue = axisValue(cameraState.center, horizontalAxis) +
        (localPosition.dx - viewportCenter.dx) /
            (cameraState.zoom * horizontalSign);
    final verticalValue = axisValue(cameraState.center, verticalAxis) -
        (localPosition.dy - viewportCenter.dy) /
            (cameraState.zoom * verticalSign);
    return copyPointWithAxis(
      copyPointWithAxis(
        cameraState.center,
        horizontalAxis,
        horizontalValue,
      ),
      verticalAxis,
      verticalValue,
    );
  }

  Offset modelToScreen({
    required RenderScenePoint point,
    required Offset viewportCenter,
    required RenderScenePlanCameraState cameraState,
  }) {
    return Offset(
      viewportCenter.dx +
          (axisValue(point, horizontalAxis) -
                  axisValue(cameraState.center, horizontalAxis)) *
              cameraState.zoom *
              horizontalSign,
      viewportCenter.dy -
          (axisValue(point, verticalAxis) -
                  axisValue(cameraState.center, verticalAxis)) *
              cameraState.zoom *
              verticalSign,
    );
  }

  double projectDepth(RenderScenePoint point) {
    return axisValue(point, depthAxis) * depthSign;
  }

  double boundsWidth(RenderSceneBounds bounds) {
    return _axisSpan(bounds, horizontalAxis);
  }

  double boundsHeight(RenderSceneBounds bounds) {
    return _axisSpan(bounds, verticalAxis);
  }

  double _axisSpan(RenderSceneBounds bounds, RenderSceneAxis axis) {
    return switch (axis) {
      RenderSceneAxis.x => bounds.width,
      RenderSceneAxis.y => bounds.depth,
      RenderSceneAxis.z => bounds.height,
    };
  }

  RenderScenePoint pointOnPlane({
    required RenderSceneBounds bounds,
    required double horizontalValue,
    required double verticalValue,
    double? depthValue,
  }) {
    final center = bounds.center;
    final resolvedDepth = depthValue ?? axisValue(center, depthAxis);
    return copyPointWithAxis(
      copyPointWithAxis(
        copyPointWithAxis(center, horizontalAxis, horizontalValue),
        verticalAxis,
        verticalValue,
      ),
      depthAxis,
      resolvedDepth,
    );
  }

  double minAxis(RenderSceneBounds bounds, RenderSceneAxis axis) {
    return switch (axis) {
      RenderSceneAxis.x => bounds.min.x,
      RenderSceneAxis.y => bounds.min.y,
      RenderSceneAxis.z => bounds.min.z,
    };
  }

  double maxAxis(RenderSceneBounds bounds, RenderSceneAxis axis) {
    return switch (axis) {
      RenderSceneAxis.x => bounds.max.x,
      RenderSceneAxis.y => bounds.max.y,
      RenderSceneAxis.z => bounds.max.z,
    };
  }
}

@immutable
class RenderSceneProjectionSpec {
  const RenderSceneProjectionSpec({
    required this.mode,
    required this.shortLabel,
    required this.statusLabel,
    required this.fitLabel,
    required this.modeLabel,
    required this.is3D,
    this.planarDescriptor,
    this.orbitYawRadians,
    this.orbitPitchRadians,
    this.viewDirection,
    this.showGrid = false,
    this.showAxes = false,
    this.showLevelsOverlay = false,
    this.useBoundsCenterLabelAnchor = false,
    this.useProjectedBoundsOutline = false,
  });

  final RenderSceneProjectionMode mode;
  final String shortLabel;
  final String statusLabel;
  final String fitLabel;
  final String modeLabel;
  final bool is3D;
  final RenderScenePlanarDescriptor? planarDescriptor;
  final double? orbitYawRadians;
  final double? orbitPitchRadians;
  final RenderScenePoint? viewDirection;
  final bool showGrid;
  final bool showAxes;
  final bool showLevelsOverlay;
  final bool useBoundsCenterLabelAnchor;
  final bool useProjectedBoundsOutline;

  bool get isPlanar => planarDescriptor != null;
  bool get isElevation => planarDescriptor?.isElevation ?? false;
}

const Map<RenderSceneProjectionMode, RenderSceneProjectionSpec>
    kRenderSceneProjectionSpecs = <RenderSceneProjectionMode,
        RenderSceneProjectionSpec>{
  RenderSceneProjectionMode.topDown: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.topDown,
    shortLabel: '2D',
    statusLabel: '2D plan view',
    fitLabel: 'Fitting 2D plan...',
    modeLabel: 'Plan',
    is3D: false,
    planarDescriptor: RenderScenePlanarDescriptor(
      horizontalAxis: RenderSceneAxis.x,
      verticalAxis: RenderSceneAxis.y,
      depthAxis: RenderSceneAxis.z,
    ),
    orbitPitchRadians: math.pi / 2,
    viewDirection: RenderScenePoint(x: 0, y: 0, z: -1),
    showGrid: true,
    showAxes: true,
    useBoundsCenterLabelAnchor: true,
  ),
  RenderSceneProjectionMode.northElevation: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.northElevation,
    shortLabel: 'North',
    statusLabel: 'North elevation view',
    fitLabel: 'Fitting north elevation...',
    modeLabel: 'North elevation',
    is3D: false,
    planarDescriptor: RenderScenePlanarDescriptor(
      horizontalAxis: RenderSceneAxis.x,
      verticalAxis: RenderSceneAxis.z,
      depthAxis: RenderSceneAxis.y,
    ),
    orbitYawRadians: -math.pi / 2,
    orbitPitchRadians: 0,
    viewDirection: RenderScenePoint(x: 0, y: -1, z: 0),
    showGrid: true,
    showAxes: false,
    showLevelsOverlay: true,
    useBoundsCenterLabelAnchor: true,
    useProjectedBoundsOutline: true,
  ),
  RenderSceneProjectionMode.southElevation: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.southElevation,
    shortLabel: 'South',
    statusLabel: 'South elevation view',
    fitLabel: 'Fitting south elevation...',
    modeLabel: 'South elevation',
    is3D: false,
    planarDescriptor: RenderScenePlanarDescriptor(
      horizontalAxis: RenderSceneAxis.x,
      verticalAxis: RenderSceneAxis.z,
      depthAxis: RenderSceneAxis.y,
      horizontalSign: -1.0,
      depthSign: -1.0,
    ),
    orbitYawRadians: math.pi / 2,
    orbitPitchRadians: 0,
    viewDirection: RenderScenePoint(x: 0, y: 1, z: 0),
    showGrid: true,
    showAxes: false,
    showLevelsOverlay: true,
    useBoundsCenterLabelAnchor: true,
    useProjectedBoundsOutline: true,
  ),
  RenderSceneProjectionMode.eastElevation: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.eastElevation,
    shortLabel: 'East',
    statusLabel: 'East elevation view',
    fitLabel: 'Fitting east elevation...',
    modeLabel: 'East elevation',
    is3D: false,
    planarDescriptor: RenderScenePlanarDescriptor(
      horizontalAxis: RenderSceneAxis.y,
      verticalAxis: RenderSceneAxis.z,
      depthAxis: RenderSceneAxis.x,
    ),
    orbitYawRadians: math.pi,
    orbitPitchRadians: 0,
    viewDirection: RenderScenePoint(x: -1, y: 0, z: 0),
    showGrid: true,
    showAxes: false,
    showLevelsOverlay: true,
    useBoundsCenterLabelAnchor: true,
    useProjectedBoundsOutline: true,
  ),
  RenderSceneProjectionMode.westElevation: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.westElevation,
    shortLabel: 'West',
    statusLabel: 'West elevation view',
    fitLabel: 'Fitting west elevation...',
    modeLabel: 'West elevation',
    is3D: false,
    planarDescriptor: RenderScenePlanarDescriptor(
      horizontalAxis: RenderSceneAxis.y,
      verticalAxis: RenderSceneAxis.z,
      depthAxis: RenderSceneAxis.x,
      horizontalSign: -1.0,
      depthSign: -1.0,
    ),
    orbitYawRadians: 0,
    orbitPitchRadians: 0,
    viewDirection: RenderScenePoint(x: 1, y: 0, z: 0),
    showGrid: true,
    showAxes: false,
    showLevelsOverlay: true,
    useBoundsCenterLabelAnchor: true,
    useProjectedBoundsOutline: true,
  ),
  RenderSceneProjectionMode.isometric: RenderSceneProjectionSpec(
    mode: RenderSceneProjectionMode.isometric,
    shortLabel: '3D',
    statusLabel: '3D isometric view',
    fitLabel: 'Fitting 3D scene...',
    modeLabel: '3D',
    is3D: true,
    showAxes: true,
  ),
};

extension RenderSceneProjectionPlanarDescriptorX on RenderSceneProjectionMode {
  RenderSceneProjectionSpec get spec => kRenderSceneProjectionSpecs[this]!;
  RenderScenePlanarDescriptor? get planarDescriptor => spec.planarDescriptor;
  bool get isPlanar => spec.isPlanar;
  bool get isElevation => spec.isElevation;
  bool get is3D => spec.is3D;
  String get shortLabel => spec.shortLabel;
  String get statusLabel => spec.statusLabel;
  String get fitLabel => spec.fitLabel;
  String get modeLabel => spec.modeLabel;
  bool get showGrid => spec.showGrid;
  bool get showAxes => spec.showAxes;
  bool get showLevelsOverlay => spec.showLevelsOverlay;
  bool get useBoundsCenterLabelAnchor => spec.useBoundsCenterLabelAnchor;
  bool get useProjectedBoundsOutline => spec.useProjectedBoundsOutline;
}
