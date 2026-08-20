import '../render_scene_editor.dart';
import '../render_scene_models.dart';

/// Result of projecting a door/window gesture onto its host wall.
final class OpeningPlacementPreview {
  const OpeningPlacementPreview({
    required this.offsetMeters,
    required this.wallLengthMeters,
    required this.valid,
  });

  final double offsetMeters;
  final double wallLengthMeters;
  final bool valid;
}

/// Pure host-wall placement rules shared by door, window and move-opening.
final class OpeningAuthoringGeometry {
  const OpeningAuthoringGeometry._();

  static OpeningPlacementPreview? preview({
    required RenderSceneObject hostWall,
    required RenderScenePoint point,
    required double widthMeters,
    bool snapToGrid = true,
    double gridStepMeters = 0.25,
  }) {
    final rawOffset = RenderSceneEditor.wallOffsetMeters(hostWall, point);
    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    if (rawOffset == null || wallLength <= 1e-9) return null;
    final offset = snapToGrid
        ? (rawOffset / gridStepMeters).roundToDouble() * gridStepMeters
        : rawOffset;
    final halfWidth = widthMeters * 0.5;
    return OpeningPlacementPreview(
      offsetMeters: offset,
      wallLengthMeters: wallLength,
      valid: offset >= halfWidth && offset <= wallLength - halfWidth,
    );
  }

  static bool isValid({
    required RenderSceneObject hostWall,
    required double offsetMeters,
    required double widthMeters,
  }) {
    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    final halfWidth = widthMeters * 0.5;
    return wallLength > 1e-9 &&
        offsetMeters >= halfWidth &&
        offsetMeters <= wallLength - halfWidth;
  }
}
