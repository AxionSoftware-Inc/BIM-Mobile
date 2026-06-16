import 'dart:convert';
import 'dart:math' as math;

import 'render_scene_models.dart';

class RenderSceneEditor {
  const RenderSceneEditor._();

  static RenderScene addWall({
    required RenderScene scene,
    required RenderScenePoint start,
    required RenderScenePoint end,
    double heightMeters = 3.0,
    double thicknessMeters = 0.2,
    int? levelId,
  }) {
    if (!start.isFinite || !end.isFinite) {
      return scene;
    }

    final length = start.distanceTo(end);
    if (length < 1e-6) {
      return scene;
    }

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final nextId = _nextElementId(objects);
    final wallObject = _buildWallObject(
      elementId: nextId,
      start: start,
      end: end,
      heightMeters: heightMeters,
      thicknessMeters: thicknessMeters,
      levelId: levelId ?? _primaryLevelId(scene),
    );
    objects.add(wallObject);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + wall');
  }

  static RenderScene addDoor({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required double offsetMeters,
    double widthMeters = 0.9,
    double heightMeters = 2.1,
    int? levelId,
  }) {
    return _addOpening(
      scene: scene,
      hostWall: hostWall,
      offsetMeters: offsetMeters,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: 0.0,
      levelId: levelId,
      kind: 'Door',
      materialCategory: 'generic',
    );
  }

  static RenderScene addWindow({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required double offsetMeters,
    double widthMeters = 1.2,
    double heightMeters = 1.2,
    double sillHeightMeters = 0.9,
    int? levelId,
  }) {
    return _addOpening(
      scene: scene,
      hostWall: hostWall,
      offsetMeters: offsetMeters,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: sillHeightMeters,
      levelId: levelId,
      kind: 'Window',
      materialCategory: 'glass',
    );
  }

  static RenderScenePoint? projectModelPointToWallOffset(
    RenderSceneObject hostWall,
    RenderScenePoint point,
  ) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final axis = geometry.end - geometry.start;
    final axisLength = geometry.length;
    if (axisLength <= 1e-9) {
      return null;
    }

    final toPoint = point - geometry.start;
    final t = _dot(toPoint, axis) / (axisLength * axisLength);
    final projected = geometry.start + axis.scale(t.clamp(0.0, 1.0));
    return projected;
  }

  static double? wallOffsetMeters(
      RenderSceneObject hostWall, RenderScenePoint point) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final axis = geometry.end - geometry.start;
    final axisLength = geometry.length;
    if (axisLength <= 1e-9) {
      return null;
    }

    final toPoint = point - geometry.start;
    final t = (_dot(toPoint, axis) / (axisLength * axisLength)).clamp(0.0, 1.0);
    return axisLength * t;
  }

  static RenderSceneObject? hostWallForOpening(
    RenderScene scene,
    RenderScenePoint point, {
    double toleranceMeters = 0.35,
  }) {
    RenderSceneObject? bestWall;
    var bestDistance = double.infinity;

    for (final object in scene.objects) {
      if (object.kindKey != 'wall') {
        continue;
      }

      final geometry = _wallGeometry(object);
      if (geometry == null) {
        continue;
      }

      final projected =
          _projectPointToSegment(point, geometry.start, geometry.end);
      final distance = point.distanceTo(projected);
      if (distance < bestDistance && distance <= toleranceMeters) {
        bestDistance = distance;
        bestWall = object;
      }
    }

    return bestWall;
  }

  static RenderScenePoint? openingCenterPoint({
    required RenderSceneObject hostWall,
    required double offsetMeters,
  }) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final length = geometry.length;
    if (length <= 1e-9) {
      return null;
    }

    final clamped = offsetMeters.clamp(0.0, length);
    final axis = geometry.end - geometry.start;
    return geometry.start + axis.scale(clamped / length);
  }

  static RenderSceneObject? objectByStableId(RenderScene scene, String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }

    return scene.objectByStableId(id);
  }

  static RenderSceneObject? objectById(RenderScene scene, int? id) {
    return scene.objectById(id);
  }

  static RenderScenePoint? wallStartPoint(RenderSceneObject wall) {
    return _wallGeometry(wall)?.start;
  }

  static RenderScenePoint? wallEndPoint(RenderSceneObject wall) {
    return _wallGeometry(wall)?.end;
  }

  static double? wallThickness(RenderSceneObject wall) {
    return _wallGeometry(wall)?.thickness;
  }

  static double? wallLength(RenderSceneObject wall) {
    return _wallGeometry(wall)?.length;
  }

  static int? wallLevelId(RenderSceneObject wall) {
    return wall.levelId;
  }

  static RenderScenePoint? wallAxisDirection(RenderSceneObject wall) {
    final geometry = _wallGeometry(wall);
    if (geometry == null) {
      return null;
    }

    final delta = geometry.end - geometry.start;
    final length = geometry.length;
    if (length <= 1e-9) {
      return null;
    }
    return RenderScenePoint(
      x: delta.x / length,
      y: delta.y / length,
      z: delta.z / length,
    );
  }

  static RenderScenePoint? wallPerpendicularDirection(RenderSceneObject wall) {
    final axis = wallAxisDirection(wall);
    if (axis == null) {
      return null;
    }

    return RenderScenePoint(x: -axis.y, y: axis.x, z: 0);
  }

  static RenderScenePoint? wallCenterPoint(RenderSceneObject wall) {
    final geometry = _wallGeometry(wall);
    if (geometry == null) {
      return null;
    }
    return RenderScenePoint(
      x: (geometry.start.x + geometry.end.x) * 0.5,
      y: (geometry.start.y + geometry.end.y) * 0.5,
      z: (geometry.start.z + geometry.end.z) * 0.5,
    );
  }

  static RenderSceneBounds sceneBoundsForObjects(
      List<RenderSceneObject> objects) {
    return RenderSceneBounds.union(
      objects.map((object) => object.bounds),
      fallback: RenderSceneBounds.zero(),
    );
  }

  static Map<String, Object?> _sceneMap(RenderScene scene) {
    return Map<String, Object?>.from(scene.toJson());
  }

  static List<Map<String, Object?>> _objectsFromSceneMap(
      Map<String, Object?> map) {
    final rawObjects = map['objects'];
    if (rawObjects is! List) {
      return <Map<String, Object?>>[];
    }

    return rawObjects
        .whereType<Map>()
        .map(
            (entry) => Map<String, Object?>.from(entry.cast<String, Object?>()))
        .toList(growable: true);
  }

  static int _nextElementId(List<Map<String, Object?>> objects) {
    var nextId = 1;
    for (final object in objects) {
      final id = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (id != null && id >= nextId) {
        nextId = id + 1;
      }
    }
    return nextId;
  }

  static int? _primaryLevelId(RenderScene scene) {
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

  static RenderScene _parseSceneMap(Map<String, Object?> map,
      {required String source}) {
    final result = parseRenderSceneJson(jsonEncode(map), source: source);
    return result.scene ??
        RenderScene(
          sceneVersion: 1,
          units: 'meters',
          coordinateSystem: 'X/Y plan, Z up',
          objectCount: 0,
          vertexCount: 0,
          indexCount: 0,
          bounds: RenderSceneBounds.zero(),
          objects: const <RenderSceneObject>[],
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

  static RenderScene _addOpening({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
    required int? levelId,
    required String kind,
    required String materialCategory,
  }) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return scene;
    }

    final axis = geometry.end - geometry.start;
    final axisLength = geometry.length;
    if (axisLength <= 1e-9) {
      return scene;
    }

    final clampedOffset = offsetMeters.clamp(0.0, axisLength);
    final halfWidth = widthMeters * 0.5;
    final alongStart = math.max(0.0, clampedOffset - halfWidth);
    final alongEnd = math.min(axisLength, clampedOffset + halfWidth);

    final axisUnit = axis.scale(1.0 / axisLength);
    final startPoint = geometry.start + axisUnit.scale(alongStart);
    final endPoint = geometry.start + axisUnit.scale(alongEnd);
    final wallNormal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final halfThickness = geometry.thickness * 0.5;
    final lowerZ = math.max(0.0, sillHeightMeters);
    final upperZ = lowerZ + heightMeters;

    final bottom0 = startPoint + wallNormal.scale(halfThickness);
    final bottom1 = endPoint + wallNormal.scale(halfThickness);
    final bottom2 = endPoint - wallNormal.scale(halfThickness);
    final bottom3 = startPoint - wallNormal.scale(halfThickness);
    final top0 = RenderScenePoint(x: bottom0.x, y: bottom0.y, z: upperZ);
    final top1 = RenderScenePoint(x: bottom1.x, y: bottom1.y, z: upperZ);
    final top2 = RenderScenePoint(x: bottom2.x, y: bottom2.y, z: upperZ);
    final top3 = RenderScenePoint(x: bottom3.x, y: bottom3.y, z: upperZ);

    final baseOffset = lowerZ;
    final positions = <RenderScenePoint>[
      RenderScenePoint(x: bottom0.x, y: bottom0.y, z: baseOffset),
      RenderScenePoint(x: bottom1.x, y: bottom1.y, z: baseOffset),
      RenderScenePoint(x: bottom2.x, y: bottom2.y, z: baseOffset),
      RenderScenePoint(x: bottom3.x, y: bottom3.y, z: baseOffset),
      top0,
      top1,
      top2,
      top3,
    ];

    final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
    final object = <String, Object?>{
      'element_id': nextId,
      'kind': kind,
      'level_id': levelId ?? hostWall.levelId ?? _primaryLevelId(scene),
      'selectable': true,
      'visible_by_default': true,
      'revision': 1,
      'bounds': RenderSceneBounds.union(
        <RenderSceneBounds>[
          for (final point in positions)
            RenderSceneBounds.normalized(min: point, max: point),
        ],
      ).toJson(),
      'mesh': <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': <int>[
          0,
          1,
          2,
          0,
          2,
          3,
          4,
          6,
          5,
          4,
          7,
          6,
          0,
          4,
          5,
          0,
          5,
          1,
          1,
          5,
          6,
          1,
          6,
          2,
          2,
          6,
          7,
          2,
          7,
          3,
          3,
          7,
          4,
          3,
          4,
          0,
        ],
      },
      'material_category': materialCategory,
      'metadata': <String, Object?>{
        'host_wall_id': hostWall.elementId ?? hostWall.elementIdRaw,
        'offset_meters': clampedOffset,
        'width_meters': widthMeters,
        'height_meters': heightMeters,
        'sill_height_meters': sillHeightMeters,
        'axis_start': geometry.start.toJson(),
        'axis_end': geometry.end.toJson(),
        'kind': kind.toLowerCase(),
      },
    };

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    objects.add(object);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + $kind');
  }

  static Map<String, Object?> _buildWallObject({
    required int elementId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double heightMeters,
    required double thicknessMeters,
    required int? levelId,
  }) {
    final axis = end - start;
    final length = start.distanceTo(end);
    final axisUnit = axis.scale(1.0 / math.max(length, 1e-9));
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final halfThickness = thicknessMeters * 0.5;
    final lower0 = start + normal.scale(halfThickness);
    final lower1 = end + normal.scale(halfThickness);
    final lower2 = end - normal.scale(halfThickness);
    final lower3 = start - normal.scale(halfThickness);
    final upper0 = RenderScenePoint(x: lower0.x, y: lower0.y, z: heightMeters);
    final upper1 = RenderScenePoint(x: lower1.x, y: lower1.y, z: heightMeters);
    final upper2 = RenderScenePoint(x: lower2.x, y: lower2.y, z: heightMeters);
    final upper3 = RenderScenePoint(x: lower3.x, y: lower3.y, z: heightMeters);
    final positions = <RenderScenePoint>[
      RenderScenePoint(x: lower0.x, y: lower0.y, z: 0),
      RenderScenePoint(x: lower1.x, y: lower1.y, z: 0),
      RenderScenePoint(x: lower2.x, y: lower2.y, z: 0),
      RenderScenePoint(x: lower3.x, y: lower3.y, z: 0),
      upper0,
      upper1,
      upper2,
      upper3,
    ];

    final bounds = RenderSceneBounds.union(
      <RenderSceneBounds>[
        for (final point in positions)
          RenderSceneBounds.normalized(min: point, max: point),
      ],
    );

    return <String, Object?>{
      'element_id': elementId,
      'kind': 'Wall',
      'level_id': levelId,
      'selectable': true,
      'visible_by_default': true,
      'revision': 1,
      'bounds': bounds.toJson(),
      'mesh': <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': <int>[
          0,
          2,
          1,
          0,
          3,
          2,
          4,
          5,
          6,
          4,
          6,
          7,
          0,
          1,
          5,
          0,
          5,
          4,
          1,
          2,
          6,
          1,
          6,
          5,
          2,
          3,
          7,
          2,
          7,
          6,
          3,
          0,
          4,
          3,
          4,
          7,
        ],
      },
      'material_category': 'structural',
      'metadata': <String, Object?>{
        'axis_start': start.toJson(),
        'axis_end': end.toJson(),
        'height_meters': heightMeters,
        'thickness_meters': thicknessMeters,
        'kind': 'wall',
      },
    };
  }

  static _WallGeometry? _wallGeometry(RenderSceneObject wall) {
    final metadata = wall.metadata;
    final axisStart = RenderScenePoint.fromJson(
        metadata['axis_start'] ?? metadata['axisStart']);
    final axisEnd =
        RenderScenePoint.fromJson(metadata['axis_end'] ?? metadata['axisEnd']);
    final thickness =
        _toDouble(metadata['thickness_meters'] ?? metadata['thicknessMeters']);

    if (axisStart != null && axisEnd != null && thickness != null) {
      return _WallGeometry(
          start: axisStart, end: axisEnd, thickness: thickness);
    }

    final bounds = wall.bounds;
    if (!bounds.isFinite) {
      return null;
    }

    final width = bounds.width;
    final depth = bounds.depth;

    if (width >= depth) {
      return _WallGeometry(
        start: RenderScenePoint(
            x: bounds.min.x, y: (bounds.min.y + bounds.max.y) * 0.5, z: 0),
        end: RenderScenePoint(
            x: bounds.max.x, y: (bounds.min.y + bounds.max.y) * 0.5, z: 0),
        thickness: depth,
      );
    }

    return _WallGeometry(
      start: RenderScenePoint(
          x: (bounds.min.x + bounds.max.x) * 0.5, y: bounds.min.y, z: 0),
      end: RenderScenePoint(
          x: (bounds.min.x + bounds.max.x) * 0.5, y: bounds.max.y, z: 0),
      thickness: width,
    );
  }

  static RenderScenePoint _projectPointToSegment(
    RenderScenePoint point,
    RenderScenePoint start,
    RenderScenePoint end,
  ) {
    final delta = end - start;
    final lengthSquared = _dot(delta, delta);
    if (lengthSquared <= 1e-9) {
      return start;
    }

    final t = _dot(point - start, delta) / lengthSquared;
    final clamped = t.clamp(0.0, 1.0);
    return start + delta.scale(clamped);
  }

  static double _dot(RenderScenePoint a, RenderScenePoint b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
  }

  static double? _toDouble(Object? value) {
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return null;
  }

  static int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num && value.isFinite) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim());
    }

    return null;
  }
}

class _WallGeometry {
  const _WallGeometry({
    required this.start,
    required this.end,
    required this.thickness,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
  final double thickness;

  double get length => start.distanceTo(end);
}
