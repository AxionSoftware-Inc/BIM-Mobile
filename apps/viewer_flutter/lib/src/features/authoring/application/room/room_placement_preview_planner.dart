import 'dart:math' as math;

import '../../../../core/application/render_scene/render_scene_models.dart';
import '../scene/render_scene_editor.dart';

final class RoomPlacementPreviewPlan {
  const RoomPlacementPreviewPlan({
    required this.room,
    required this.previewPoints,
    required this.valid,
    required this.areaSquareMeters,
  });

  final RenderSceneObject? room;
  final List<RenderScenePoint> previewPoints;
  final bool valid;
  final double? areaSquareMeters;
}

/// Pure room-preview policy used while the pointer moves inside a plan view.
///
/// Native persistence is deliberately excluded. This planner only derives the
/// candidate room, its boundary/invalid marker and semantic area from the
/// current immutable scene snapshot.
abstract final class RoomPlacementPreviewPlanner {
  static RoomPlacementPreviewPlan plan({
    required RenderScene scene,
    required RenderScenePoint point,
    required int? activeLevelId,
    RenderSceneObject? pickedObject,
  }) {
    final pickedRoom = pickedObject?.kindKey == 'room' ? pickedObject : null;
    final detected = pickedRoom == null ? RenderSceneEditor.detectRooms(scene) : scene;
    final room = pickedRoom ??
        RenderSceneEditor.roomContainingPoint(
          detected,
          point,
          levelId: activeLevelId,
        );
    final polygon = room == null
        ? null
        : RenderSceneEditor.roomBoundaryPolygon(detected, room);
    final valid = room != null &&
        polygon != null &&
        polygon.length >= 3 &&
        RenderSceneEditor.roomBoundaryWallIds(room).length >= 3;

    return RoomPlacementPreviewPlan(
      room: valid ? room : null,
      previewPoints: polygon != null && valid
          ? List<RenderScenePoint>.unmodifiable(polygon)
          : _invalidMarker(scene, point),
      valid: valid,
      areaSquareMeters: valid ? _areaSquareMeters(room) : null,
    );
  }

  static List<RenderScenePoint> _invalidMarker(
    RenderScene scene,
    RenderScenePoint point,
  ) {
    final span = math.max(scene.bounds.width, scene.bounds.depth);
    final half = (span * 0.012).clamp(0.12, 0.35).toDouble();
    return List<RenderScenePoint>.unmodifiable(<RenderScenePoint>[
      RenderScenePoint(x: point.x - half, y: point.y - half, z: point.z + 0.02),
      RenderScenePoint(x: point.x + half, y: point.y - half, z: point.z + 0.02),
      RenderScenePoint(x: point.x + half, y: point.y + half, z: point.z + 0.02),
      RenderScenePoint(x: point.x - half, y: point.y + half, z: point.z + 0.02),
    ]);
  }

  static double? _areaSquareMeters(RenderSceneObject room) {
    final value = room.metadata['area_m2'];
    return value is num ? value.toDouble() : null;
  }
}
