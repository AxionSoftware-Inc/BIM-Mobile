part of 'render_scene_models.dart';

/// The renderer-neutral coordinate contract accepted by BIM-Mobile v0.1.
///
/// Keeping this value object next to [RenderScene] gives every adapter one
/// answer to the otherwise easy-to-miss questions of unit, axes and supported
/// payload version. UI code must project this contract; it must not convert or
/// reinterpret model coordinates on its own.
final class RenderSceneCoordinateContract {
  const RenderSceneCoordinateContract._();

  static const int minimumSupportedSceneVersion = 1;
  static const int currentSceneVersion = 2;
  static const String units = 'meters';
  static const String coordinateSystem = 'X/Y plan, Z up';

  static List<String> issuesFor({
    required int sceneVersion,
    required String sceneUnits,
    required String sceneCoordinateSystem,
  }) {
    final issues = <String>[];
    if (sceneVersion < minimumSupportedSceneVersion ||
        sceneVersion > currentSceneVersion) {
      issues.add(
        'Unsupported RenderScene version $sceneVersion; supported versions are '
        '$minimumSupportedSceneVersion through $currentSceneVersion.',
      );
    }
    if (sceneUnits != units) {
      issues.add(
        'Unsupported RenderScene units "$sceneUnits"; BIM-Mobile v0.1 requires $units.',
      );
    }
    if (sceneCoordinateSystem != coordinateSystem) {
      issues.add(
        'Unsupported RenderScene coordinate system "$sceneCoordinateSystem"; '
        'BIM-Mobile v0.1 requires "$coordinateSystem".',
      );
    }
    return List<String>.unmodifiable(issues);
  }

  static List<String> issuesForScene(RenderScene scene) => issuesFor(
        sceneVersion: scene.sceneVersion,
        sceneUnits: scene.units,
        sceneCoordinateSystem: scene.coordinateSystem,
      );
}
