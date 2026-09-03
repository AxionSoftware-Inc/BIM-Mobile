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
    double? heightMeters,
    double sillHeightMeters = 0.0,
    bool snapToGrid = true,
    double gridStepMeters = 0.25,
  }) {
    final rawOffset = RenderSceneEditor.wallOffsetMeters(hostWall, point);
    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    if (rawOffset == null ||
        !rawOffset.isFinite ||
        !wallLength.isFinite ||
        wallLength <= 1e-9) {
      return null;
    }
    final offset = snapToGrid
        ? (rawOffset / gridStepMeters).roundToDouble() * gridStepMeters
        : rawOffset;
    return OpeningPlacementPreview(
      offsetMeters: offset,
      wallLengthMeters: wallLength,
      valid: isValid(
        hostWall: hostWall,
        offsetMeters: offset,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        sillHeightMeters: sillHeightMeters,
      ),
    );
  }

  static bool isValid({
    required RenderSceneObject hostWall,
    required double offsetMeters,
    required double widthMeters,
    double? heightMeters,
    double sillHeightMeters = 0.0,
  }) {
    return validationMessage(
          hostWall: hostWall,
          offsetMeters: offsetMeters,
          widthMeters: widthMeters,
          heightMeters: heightMeters,
          sillHeightMeters: sillHeightMeters,
        ) ==
        null;
  }

  /// Returns a short reason when an opening cannot be created.
  ///
  /// `heightMeters` is optional for callers that only need horizontal
  /// placement. Creation and move-opening pass it so the preview uses the
  /// same vertical contract as the native document validator.
  static String? validationMessage({
    required RenderSceneObject hostWall,
    required double offsetMeters,
    required double widthMeters,
    double? heightMeters,
    double sillHeightMeters = 0.0,
  }) {
    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    if (!wallLength.isFinite || wallLength <= 1e-9) {
      return 'Host wall has no valid length.';
    }
    if (!offsetMeters.isFinite || !widthMeters.isFinite || widthMeters <= 0) {
      return 'Width and offset must be positive numbers.';
    }
    if (!sillHeightMeters.isFinite || sillHeightMeters < 0) {
      return 'Sill height must be zero or greater.';
    }
    if (heightMeters != null && (!heightMeters.isFinite || heightMeters <= 0)) {
      return 'Height must be a positive number.';
    }
    final halfWidth = widthMeters * 0.5;
    if (offsetMeters < halfWidth || offsetMeters > wallLength - halfWidth) {
      return 'Opening overlaps the wall edge.';
    }

    if (heightMeters != null) {
      final wallHeight = _wallHeightMeters(hostWall);
      if (wallHeight != null &&
          sillHeightMeters + heightMeters > wallHeight + 1e-6) {
        return 'Opening height and sill exceed the host wall height.';
      }
    }
    return null;
  }

  static double? _wallHeightMeters(RenderSceneObject wall) {
    final metadataHeight =
        double.tryParse(wall.metadata['height_meters']?.toString() ?? '');
    if (metadataHeight != null &&
        metadataHeight.isFinite &&
        metadataHeight > 0) {
      return metadataHeight;
    }
    final boundsHeight = wall.bounds.height;
    return boundsHeight.isFinite && boundsHeight > 0 ? boundsHeight : null;
  }
}
