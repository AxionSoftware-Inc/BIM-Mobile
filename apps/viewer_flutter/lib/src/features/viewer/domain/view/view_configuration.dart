enum RenderSceneProjectionMode {
  topDown,
  northElevation,
  southElevation,
  eastElevation,
  westElevation,
  isometric,
}

const RenderSceneProjectionMode kDefaultPlanProjectionMode =
    RenderSceneProjectionMode.topDown;
const RenderSceneProjectionMode kDefaultElevationProjectionMode =
    RenderSceneProjectionMode.northElevation;
const List<RenderSceneProjectionMode> kOrthographicProjectionModes =
    <RenderSceneProjectionMode>[
  RenderSceneProjectionMode.topDown,
  RenderSceneProjectionMode.northElevation,
  RenderSceneProjectionMode.southElevation,
  RenderSceneProjectionMode.eastElevation,
  RenderSceneProjectionMode.westElevation,
];

enum RenderSceneDisplayStyle {
  shaded,
  solid,
  wireframe,
}

enum RenderSceneOrbitProjectionStyle {
  perspective,
  orthographic,
}

extension RenderSceneProjectionEditingModeX on RenderSceneProjectionMode {
  bool get supportsPlanFootprintEditing => this == kDefaultPlanProjectionMode;

  bool get isElevationProjection => switch (this) {
        RenderSceneProjectionMode.northElevation ||
        RenderSceneProjectionMode.southElevation ||
        RenderSceneProjectionMode.eastElevation ||
        RenderSceneProjectionMode.westElevation => true,
        _ => false,
      };

  bool get isThreeDimensional => this == RenderSceneProjectionMode.isometric;
}
