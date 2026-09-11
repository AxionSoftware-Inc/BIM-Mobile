part of 'render_scene_editor.dart';

Map<String, Object?> _sceneMap(RenderScene scene) {
  return Map<String, Object?>.from(scene.toJson());
}

List<Map<String, Object?>> _levelsFromSceneMap(Map<String, Object?> map) {
  final rawLevels = map['levels'];
  if (rawLevels is! List) {
    return <Map<String, Object?>>[];
  }
  return rawLevels
      .whereType<Map>()
      .map(
        (entry) => Map<String, Object?>.from(entry.cast<String, Object?>()),
      )
      .toList(growable: true);
}

List<Map<String, Object?>> _objectsFromSceneMap(Map<String, Object?> map) {
  final rawObjects = map['objects'];
  if (rawObjects is! List) {
    return <Map<String, Object?>>[];
  }

  return rawObjects
      .whereType<Map>()
      .map((entry) => Map<String, Object?>.from(entry.cast<String, Object?>()))
      .toList(growable: true);
}

int _nextLevelId(List<Map<String, Object?>> levels) {
  var nextId = 1;
  for (final level in levels) {
    final id = _toInt(level['level_id']) ?? _toInt(level['levelId']);
    if (id != null && id >= nextId) {
      nextId = id + 1;
    }
  }
  return nextId;
}

int _nextElementId(List<Map<String, Object?>> objects) {
  var nextId = 1;
  for (final object in objects) {
    final id = _toInt(object['element_id']) ?? _toInt(object['elementId']);
    if (id != null && id >= nextId) {
      nextId = id + 1;
    }
  }
  return nextId;
}

int? _primaryLevelId(RenderScene scene) {
  if (scene.levels.isNotEmpty) {
    return scene.levels.first.levelId;
  }
  final counts = <int, int>{};
  for (final object in scene.objects) {
    final levelId = object.levelId;
    if (levelId == null) {
      continue;
    }
    counts[levelId] = (counts[levelId] ?? 0) + 1;
  }

  if (counts.isEmpty) {
    return null;
  }

  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

double _levelElevation(RenderScene scene, int? levelId) {
  return scene.levelById(levelId)?.elevationMeters ?? 0.0;
}

bool _samePlanPoint(
  RenderScenePoint a,
  RenderScenePoint b,
  double toleranceMeters,
) {
  return (a.x - b.x).abs() <= toleranceMeters &&
      (a.y - b.y).abs() <= toleranceMeters;
}

double _planDistance2(RenderScenePoint first, RenderScenePoint second) {
  final dx = first.x - second.x;
  final dy = first.y - second.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _polygonArea2d(List<RenderScenePoint> polygon) {
  if (polygon.length < 3) {
    return 0.0;
  }
  var twiceArea = 0.0;
  for (var i = 0; i < polygon.length; i += 1) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    twiceArea += a.x * b.y - b.x * a.y;
  }
  return twiceArea * 0.5;
}

RenderScenePoint? _planLineIntersection(
  RenderScenePoint firstStart,
  RenderScenePoint firstEnd,
  RenderScenePoint secondStart,
  RenderScenePoint secondEnd,
) {
  final firstDelta = firstEnd - firstStart;
  final secondDelta = secondEnd - secondStart;
  final denominator =
      firstDelta.x * secondDelta.y - firstDelta.y * secondDelta.x;
  if (denominator.abs() <= 1e-9) return null;
  final offset = secondStart - firstStart;
  final t = (offset.x * secondDelta.y - offset.y * secondDelta.x) / denominator;
  return RenderScenePoint(
    x: firstStart.x + firstDelta.x * t,
    y: firstStart.y + firstDelta.y * t,
    z: firstStart.z,
  );
}

bool _pointOnPlanSegment(
  RenderScenePoint point,
  RenderScenePoint start,
  RenderScenePoint end, {
  required double toleranceMeters,
}) {
  return point.x >= math.min(start.x, end.x) - toleranceMeters &&
      point.x <= math.max(start.x, end.x) + toleranceMeters &&
      point.y >= math.min(start.y, end.y) - toleranceMeters &&
      point.y <= math.max(start.y, end.y) + toleranceMeters;
}

double _levelDefaultWallHeightMeters(RenderScene scene, int? levelId) {
  final level = scene.levelById(levelId);
  return level?.defaultWallHeightMeters ??
      RenderSceneEditor.defaultWallHeightMeters;
}

RenderScene _parseSceneMap(Map<String, Object?> map, {required String source}) {
  final result = parseRenderSceneJson(jsonEncode(map), source: source);
  return result.scene ??
      RenderScene(
        sceneVersion: RenderSceneCoordinateContract.currentSceneVersion,
        units: RenderSceneCoordinateContract.units,
        coordinateSystem: RenderSceneCoordinateContract.coordinateSystem,
        objectCount: 0,
        vertexCount: 0,
        indexCount: 0,
        bounds: RenderSceneBounds.zero(),
        objects: const <RenderSceneObject>[],
        levels: const <RenderSceneLevel>[
          RenderSceneLevel(
            levelId: 1,
            name: 'Level 1',
            elevationMeters: 0.0,
            defaultWallHeightMeters: RenderSceneEditor.defaultWallHeightMeters,
          ),
        ],
        materials: const <RenderSceneMaterial>[],
        sections: const <RenderSceneSection>[],
        source: source,
        diagnostics: const RenderSceneDiagnostics(
          source: 'editor',
          objectCount: 0,
          selectableObjectCount: 0,
          visibleObjectCount: 0,
          vertexCount: 0,
          indexCount: 0,
          triangleCount: 0,
          levelCount: 0,
          missingGeometryCount: 0,
          invalidBoundsCount: 0,
          invalidIndexCount: 0,
          kindCounts: <String, int>{},
          warnings: <String>[],
          errors: <String>[],
        ),
      );
}
