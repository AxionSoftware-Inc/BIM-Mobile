/// Geometry-entry mode for floor, ceiling and roof profile authoring.
///
/// This contract is intentionally framework-neutral. Viewports may expose it,
/// but authoring application rules own its semantics.
enum RenderSceneSurfaceDrawMode {
  rectangle,
  polyline,
  pickWalls,
  autoRoom,
}
