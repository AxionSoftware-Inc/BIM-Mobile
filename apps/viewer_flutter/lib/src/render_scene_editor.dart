import 'dart:convert';
import 'dart:math' as math;

import 'render_scene_models.dart';

class RenderSceneEditor {
  const RenderSceneEditor._();

  static const double defaultWallThicknessMeters = 0.30;
  static const double defaultWallHeightMeters = 3.0;

  static List<RenderSceneLevel> levels(RenderScene scene) => scene.levels;

  static RenderSceneLevel? levelById(RenderScene scene, int? levelId) {
    return scene.levelById(levelId);
  }

  static bool isElementLevelLocked(RenderSceneObject object) {
    final value = object.metadata['level_locked'];
    if (value is bool) {
      return value;
    }
    return object.kindKey == 'wall' ||
        object.kindKey == 'door' ||
        object.kindKey == 'window' ||
        object.kindKey == 'floor' ||
        object.kindKey == 'ceiling';
  }

  static RenderScene setElementLevelLock({
    required RenderScene scene,
    required RenderSceneObject object,
    required bool locked,
  }) {
    final elementId = object.elementId;
    if (elementId == null) {
      return scene;
    }
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    for (final entry in objects) {
      final objectId = _toInt(entry['element_id']) ?? _toInt(entry['elementId']);
      if (objectId != elementId) {
        continue;
      }
      final metadata = entry['metadata'] is Map
          ? Map<String, Object?>.from((entry['metadata'] as Map).cast<String, Object?>())
          : <String, Object?>{};
      metadata['level_locked'] = locked;
      entry['metadata'] = metadata;
      break;
    }
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ level lock');
  }

  static RenderScene setLevelElevation({
    required RenderScene scene,
    required int levelId,
    required double elevationMeters,
  }) {
    final level = scene.levelById(levelId);
    if (level == null) {
      return scene;
    }
    final delta = elevationMeters - level.elevationMeters;
    if (!delta.isFinite || delta.abs() <= 1e-9) {
      return scene;
    }

    final map = _sceneMap(scene);
    final levels = _levelsFromSceneMap(map);
    for (final entry in levels) {
      final entryLevelId = _toInt(entry['level_id']) ?? _toInt(entry['levelId']);
      if (entryLevelId == levelId) {
        entry['elevation_meters'] = elevationMeters;
        break;
      }
    }
    map['levels'] = levels;

    final objects = _objectsFromSceneMap(map);
    for (var index = 0; index < objects.length; index += 1) {
      final object = objects[index];
      final objectLevelId =
          _toInt(object['level_id']) ?? _toInt(object['levelId']);
      if (objectLevelId != levelId) {
        continue;
      }
      final parsedObject = RenderSceneObject.fromJson(
        object,
        <String>[],
        <String>[],
      );
      if (!isElementLevelLocked(parsedObject)) {
        continue;
      }

      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind == 'wall') {
        final geometry = _wallGeometryFromMap(object);
        if (geometry == null) {
          continue;
        }
        final metadataMap =
            object['metadata'] is Map ? object['metadata'] as Map : null;
        final heightMeters =
            _toDouble(metadataMap?['height_meters']) ?? defaultWallHeightMeters;
        final thicknessMeters =
            geometry.thickness.isFinite ? geometry.thickness : defaultWallThicknessMeters;
        final shiftedStart = RenderScenePoint(
          x: geometry.start.x,
          y: geometry.start.y,
          z: geometry.start.z + delta,
        );
        final shiftedEnd = RenderScenePoint(
          x: geometry.end.x,
          y: geometry.end.y,
          z: geometry.end.z + delta,
        );
        final rebuilt = _buildWallObject(
          elementId: parsedObject.elementId ?? 0,
          start: shiftedStart,
          end: shiftedEnd,
          heightMeters: heightMeters,
          thicknessMeters: thicknessMeters,
          levelId: levelId,
        );
        final rebuiltMetadata =
            Map<String, Object?>.from((rebuilt['metadata'] as Map).cast<String, Object?>());
        rebuiltMetadata['level_locked'] = true;
        rebuilt['metadata'] = rebuiltMetadata;
        objects[index] = rebuilt;
        continue;
      }

      if (kind == 'door' || kind == 'window' || kind == 'room') {
        continue;
      }

      _shiftObjectZInPlace(object, delta);
    }

    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ level');
  }

  static RenderScene createLevel({
    required RenderScene scene,
    required String name,
    required double elevationMeters,
    double defaultWallHeightMeters = defaultWallHeightMeters,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return scene;
    }
    final map = _sceneMap(scene);
    final levels = _levelsFromSceneMap(map);
    final nextLevelId = _nextLevelId(levels);
    levels.add(
      <String, Object?>{
        'level_id': nextLevelId,
        'name': trimmedName,
        'elevation_meters': elevationMeters,
        'default_wall_height_meters': defaultWallHeightMeters,
      },
    );
    levels.sort(
      (a, b) => (_toDouble(a['elevation_meters']) ?? 0.0)
          .compareTo(_toDouble(b['elevation_meters']) ?? 0.0),
    );
    map['levels'] = levels;
    return _parseSceneMap(map, source: '${scene.source} + level');
  }

  static RenderScene addWall({
    required RenderScene scene,
    required RenderScenePoint start,
    required RenderScenePoint end,
    double heightMeters = defaultWallHeightMeters,
    double thicknessMeters = defaultWallThicknessMeters,
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
    final resolvedLevelId = levelId ?? _primaryLevelId(scene);
    final resolvedHeight = heightMeters <= 1e-6
        ? _levelDefaultWallHeightMeters(scene, resolvedLevelId)
        : heightMeters;
    final wallObject = _buildWallObject(
      elementId: nextId,
      start: start,
      end: end,
      heightMeters: resolvedHeight,
      thicknessMeters: thicknessMeters,
      levelId: resolvedLevelId,
    );
    objects.add(wallObject);
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + wall');
  }

  static RenderScene normalizeSceneGeometry(RenderScene scene) {
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    if (objects.isEmpty) {
      return scene;
    }
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: scene.source);
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

  static RenderScene addFloorForRoom({
    required RenderScene scene,
    required RenderSceneObject room,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForRoom(
      scene: scene,
      room: room,
      kind: 'Floor',
      materialCategory: 'floor',
      thicknessMeters: thicknessMeters,
      baseZ: topElevationMeters - thicknessMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingForRoom({
    required RenderScene scene,
    required RenderSceneObject room,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForRoom(
      scene: scene,
      room: room,
      kind: 'Ceiling',
      materialCategory: 'ceiling',
      thicknessMeters: thicknessMeters,
      baseZ: room.bounds.min.z + math.max(heightMeters - thicknessMeters, 0.02),
      levelId: levelId,
    );
  }

  static RenderScene addFloorFromBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForBounds(
      scene: scene,
      bounds: bounds,
      kind: 'Floor',
      materialCategory: 'floor',
      thicknessMeters: thicknessMeters,
      baseZ: topElevationMeters - thicknessMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingFromBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForBounds(
      scene: scene,
      bounds: bounds,
      kind: 'Ceiling',
      materialCategory: 'ceiling',
      thicknessMeters: thicknessMeters,
      baseZ: bounds.min.z + math.max(heightMeters - thicknessMeters, 0.02),
      levelId: levelId,
    );
  }

  static RenderScene addFloorFromWalls({
    required RenderScene scene,
    required List<RenderSceneObject> walls,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    final bounds = surfaceBoundsForWalls(walls);
    if (bounds == null) {
      return scene;
    }
    return addFloorFromBounds(
      scene: scene,
      bounds: bounds,
      thicknessMeters: thicknessMeters,
      topElevationMeters: topElevationMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingFromWalls({
    required RenderScene scene,
    required List<RenderSceneObject> walls,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    final bounds = surfaceBoundsForWalls(walls);
    if (bounds == null) {
      return scene;
    }
    return addCeilingFromBounds(
      scene: scene,
      bounds: bounds,
      thicknessMeters: thicknessMeters,
      heightMeters: heightMeters,
      levelId: levelId,
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

  static RenderSceneObject? roomContainingPoint(
    RenderScene scene,
    RenderScenePoint point,
  ) {
    RenderSceneObject? bestRoom;
    var bestArea = double.infinity;

    for (final object in scene.objects) {
      if (object.kindKey != 'room') {
        continue;
      }

      final bounds = object.bounds;
      if (!bounds.isFinite) {
        continue;
      }

      final insideX = point.x >= bounds.min.x && point.x <= bounds.max.x;
      final insideY = point.y >= bounds.min.y && point.y <= bounds.max.y;
      if (!insideX || !insideY) {
        continue;
      }

      final area = bounds.width * bounds.depth;
      if (area < bestArea) {
        bestArea = area;
        bestRoom = object;
      }
    }

    return bestRoom;
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

  static List<RenderScenePoint> wallSnapPoints(RenderScene scene) {
    final points = <RenderScenePoint>[];
    for (final object in scene.objects) {
      if (object.kindKey != 'wall') {
        continue;
      }
      final start = wallStartPoint(object);
      final end = wallEndPoint(object);
      if (start != null) {
        points.add(start);
      }
      if (end != null) {
        points.add(end);
      }
    }
    return points;
  }

  static RenderSceneBounds? surfaceBoundsForWalls(List<RenderSceneObject> walls) {
    final validBounds = <RenderSceneBounds>[
      for (final wall in walls)
        if (wall.kindKey == 'wall' &&
            wall.bounds.isFinite &&
            wall.bounds.width > 1e-6 &&
            wall.bounds.depth > 1e-6)
          wall.bounds,
    ];
    if (validBounds.length < 2) {
      return null;
    }
    final union = RenderSceneBounds.union(validBounds);
    return RenderSceneBounds.normalized(
      min: RenderScenePoint(x: union.min.x, y: union.min.y, z: 0),
      max: RenderScenePoint(x: union.max.x, y: union.max.y, z: 0),
    );
  }

  static RenderScene deleteObject({
    required RenderScene scene,
    required RenderSceneObject target,
  }) {
    final targetId = target.elementId;
    if (targetId == null) {
      return scene;
    }

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final affectedWallIds = <int>{};
    if (target.kindKey == 'door' || target.kindKey == 'window') {
      final hostWallId = _toInt(
        target.metadata['host_wall_id'] ?? target.metadata['hostWallId'],
      );
      if (hostWallId != null) {
        affectedWallIds.add(hostWallId);
      }
    }
    objects.removeWhere((object) {
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (objectId == targetId) {
        return true;
      }
      if (target.kindKey == 'wall') {
        final metadata = object['metadata'];
        if (metadata is Map) {
          final hostId = _toInt(metadata['host_wall_id'] ?? metadata['hostWallId']);
          if (hostId == targetId) {
            return true;
          }
        }
      }
      return false;
    });
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} - ${target.kind}');
  }

  static RenderScene setWallAxis({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) {
    if (wall.kindKey != 'wall') {
      return scene;
    }
    if (!start.isFinite || !end.isFinite || start.distanceTo(end) < 1e-6) {
      return scene;
    }

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final wallId = wall.elementId;
    if (wallId == null) {
      return scene;
    }
    final originalGeometry = _wallGeometry(wall);
    if (originalGeometry == null) {
      return scene;
    }
    final startDelta = start - originalGeometry.start;
    final endDelta = end - originalGeometry.end;

    final updates = <int, _WallGeometry>{};
    for (final object in objects) {
      final objectId =
          _toInt(object['element_id']) ?? _toInt(object['elementId']);
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (objectId == null || kind != 'wall') {
        continue;
      }
      final geometry = _wallGeometryFromMap(object);
      if (geometry == null) {
        continue;
      }
      if (objectId == wallId) {
        updates[objectId] = _WallGeometry(
          start: start,
          end: end,
          thickness: geometry.thickness,
        );
        continue;
      }

      var nextStart = geometry.start;
      var nextEnd = geometry.end;
      var changed = false;
      if (_samePoint2(geometry.start, originalGeometry.start)) {
        nextStart = geometry.start + startDelta;
        changed = true;
      } else if (_samePoint2(geometry.start, originalGeometry.end)) {
        nextStart = geometry.start + endDelta;
        changed = true;
      }
      if (_samePoint2(geometry.end, originalGeometry.start)) {
        nextEnd = geometry.end + startDelta;
        changed = true;
      } else if (_samePoint2(geometry.end, originalGeometry.end)) {
        nextEnd = geometry.end + endDelta;
        changed = true;
      }
      if (changed) {
        updates[objectId] = _WallGeometry(
          start: nextStart,
          end: nextEnd,
          thickness: geometry.thickness,
        );
      }
    }

    for (var index = 0; index < objects.length; index += 1) {
      final objectId =
          _toInt(objects[index]['element_id']) ?? _toInt(objects[index]['elementId']);
      final kind = (objects[index]['kind']?.toString() ?? '').toLowerCase();
      if (objectId == null || kind != 'wall') {
        continue;
      }
      final geometry = _wallGeometryFromMap(objects[index]);
      final metadataMap =
          objects[index]['metadata'] is Map ? objects[index]['metadata'] as Map : null;
      final boundsMap =
          objects[index]['bounds'] is Map ? objects[index]['bounds'] as Map : null;
      Map? boundsMax;
      final rawBoundsMax = boundsMap == null ? null : boundsMap['max'];
      if (rawBoundsMax is Map) {
        boundsMax = rawBoundsMax;
      }
      final heightMeters =
          _toDouble(metadataMap?['height_meters']) ?? _toDouble(boundsMax?['z']) ?? defaultWallHeightMeters;
      final thicknessMeters = geometry?.thickness ?? defaultWallThicknessMeters;
      final levelId =
          _toInt(objects[index]['level_id']) ?? _toInt(objects[index]['levelId']);
      final nextGeometry = updates[objectId];
      if (nextGeometry == null) {
        continue;
      }
      objects[index] = _buildWallObject(
        elementId: objectId,
        start: nextGeometry.start,
        end: nextGeometry.end,
        heightMeters: heightMeters,
        thicknessMeters: thicknessMeters,
        levelId: levelId,
      );
    }
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ wall');
  }

  static RenderScene moveOpening({
    required RenderScene scene,
    required RenderSceneObject opening,
    required double offsetMeters,
  }) {
    if (opening.kindKey != 'door' && opening.kindKey != 'window') {
      return scene;
    }

    final openingId = opening.elementId;
    if (openingId == null) {
      return scene;
    }
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    for (final object in objects) {
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (objectId != openingId) {
        continue;
      }
      final metadata =
          object['metadata'] is Map ? Map<String, Object?>.from((object['metadata'] as Map).cast<String, Object?>()) : <String, Object?>{};
      metadata['offset_meters'] = offsetMeters;
      object['metadata'] = metadata;
      _rebuildAllWallObjects(objects);
      map['objects'] = objects;
      return _parseSceneMap(map, source: '${scene.source} ~ opening');
    }
    return scene;
  }

  static RenderScene synchronizeAutoRoomSurfaces({
    required RenderScene scene,
    bool includeFloors = true,
    bool includeCeilings = true,
    double floorThicknessMeters = 0.18,
    double floorTopElevationMeters = 0.0,
    double ceilingThicknessMeters = 0.05,
    double ceilingHeightMeters = 3.0,
  }) {
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    objects.removeWhere((object) {
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind != 'floor' && kind != 'ceiling') {
        return false;
      }
      final metadata = object['metadata'];
      if (metadata is! Map) {
        return false;
      }
      return metadata['auto_generated_from_room'] == true;
    });

    final rooms = objects
        .where((object) => (object['kind']?.toString() ?? '').toLowerCase() == 'room')
        .map(
          (object) => RenderSceneObject.fromJson(
            object,
            <String>[],
            <String>[],
          ),
        )
        .whereType<RenderSceneObject>()
        .toList(growable: false);
    final baseScene = _parseSceneMap(map, source: scene.source);
    var nextScene = baseScene;
    for (final room in rooms) {
      if (includeFloors) {
        nextScene = addFloorForRoom(
          scene: nextScene,
          room: room,
          thicknessMeters: floorThicknessMeters,
          topElevationMeters: room.bounds.min.z + floorTopElevationMeters,
        );
      }
      if (includeCeilings) {
        nextScene = addCeilingForRoom(
          scene: nextScene,
          room: room,
          thicknessMeters: ceilingThicknessMeters,
          heightMeters: ceilingHeightMeters,
        );
      }
    }

    final nextMap = _sceneMap(nextScene);
    final nextObjects = _objectsFromSceneMap(nextMap);
    for (final object in nextObjects) {
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind != 'floor' && kind != 'ceiling') {
        continue;
      }
      final metadata =
          object['metadata'] is Map ? Map<String, Object?>.from((object['metadata'] as Map).cast<String, Object?>()) : <String, Object?>{};
      if (metadata.containsKey('source_room_id')) {
        metadata['auto_generated_from_room'] = true;
        object['metadata'] = metadata;
      }
    }
    nextMap['objects'] = nextObjects;
    return _parseSceneMap(nextMap, source: '${scene.source} ~ auto surfaces');
  }

  static Map<String, Object?> _sceneMap(RenderScene scene) {
    return Map<String, Object?>.from(scene.toJson());
  }

  static List<Map<String, Object?>> _levelsFromSceneMap(Map<String, Object?> map) {
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

  static int _nextLevelId(List<Map<String, Object?>> levels) {
    var nextId = 1;
    for (final level in levels) {
      final id = _toInt(level['level_id']) ?? _toInt(level['levelId']);
      if (id != null && id >= nextId) {
        nextId = id + 1;
      }
    }
    return nextId;
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

  static double _levelDefaultWallHeightMeters(RenderScene scene, int? levelId) {
    final level = scene.levelById(levelId);
    return level?.defaultWallHeightMeters ?? defaultWallHeightMeters;
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
          levels: const <RenderSceneLevel>[
            RenderSceneLevel(
              levelId: 1,
              name: 'Level 1',
              elevationMeters: 0.0,
              defaultWallHeightMeters: defaultWallHeightMeters,
            ),
          ],
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
    final panelThickness = math.min(
      math.max(geometry.thickness * 0.5, 0.05),
      geometry.thickness,
    );
    final halfThickness = panelThickness * 0.5;
    final wallBaseZ = geometry.start.z;
    final lowerZ = wallBaseZ + math.max(0.0, sillHeightMeters);
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
        'panel_thickness_meters': panelThickness,
        'axis_start': geometry.start.toJson(),
        'axis_end': geometry.end.toJson(),
        'level_locked': true,
        'kind': kind.toLowerCase(),
      },
    };

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    objects.add(object);
    _rebuildAllWallObjects(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + $kind');
  }

  static RenderScene _addHorizontalSystemForRoom({
    required RenderScene scene,
    required RenderSceneObject room,
    required String kind,
    required String materialCategory,
    required double thicknessMeters,
    required double baseZ,
    required int? levelId,
  }) {
    final bounds = room.bounds;
    if (!bounds.isFinite || bounds.width <= 1e-6 || bounds.depth <= 1e-6) {
      return scene;
    }

    final z0 = baseZ;
    final z1 = baseZ + math.max(thicknessMeters, 0.02);
    final positions = <RenderScenePoint>[
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z0),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z0),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z0),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z0),
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z1),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z1),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z1),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z1),
    ];

    final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
    final object = <String, Object?>{
      'element_id': nextId,
      'kind': kind,
      'level_id': levelId ?? room.levelId ?? _primaryLevelId(scene),
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
      'material_category': materialCategory,
      'metadata': <String, Object?>{
        'source_room_id': room.elementId,
        'thickness_meters': thicknessMeters,
        'level_locked': true,
        'kind': kind.toLowerCase(),
      },
    };

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    objects.add(object);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + $kind');
  }

  static RenderScene _addHorizontalSystemForBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    required String kind,
    required String materialCategory,
    required double thicknessMeters,
    required double baseZ,
    required int? levelId,
  }) {
    if (!bounds.isFinite || bounds.width <= 1e-6 || bounds.depth <= 1e-6) {
      return scene;
    }

    final z0 = baseZ;
    final z1 = baseZ + math.max(thicknessMeters, 0.02);
    final positions = <RenderScenePoint>[
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z0),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z0),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z0),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z0),
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z1),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z1),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z1),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z1),
    ];

    final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
    final object = <String, Object?>{
      'element_id': nextId,
      'kind': kind,
      'level_id': levelId ?? _primaryLevelId(scene),
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
          0, 2, 1, 0, 3, 2,
          4, 5, 6, 4, 6, 7,
          0, 1, 5, 0, 5, 4,
          1, 2, 6, 1, 6, 5,
          2, 3, 7, 2, 7, 6,
          3, 0, 4, 3, 4, 7,
        ],
      },
      'material_category': materialCategory,
      'metadata': <String, Object?>{
        'thickness_meters': thicknessMeters,
        'level_locked': true,
        'kind': kind.toLowerCase(),
        'footprint_mode': 'draft_bounds',
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
    final baseZ = ((start.z + end.z) * 0.5).isFinite ? (start.z + end.z) * 0.5 : 0.0;
    final axisUnit = axis.scale(1.0 / math.max(length, 1e-9));
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final halfThickness = thicknessMeters * 0.5;
    final lower0 = start + normal.scale(halfThickness);
    final lower1 = end + normal.scale(halfThickness);
    final lower2 = end - normal.scale(halfThickness);
    final lower3 = start - normal.scale(halfThickness);
    final upper0 =
        RenderScenePoint(x: lower0.x, y: lower0.y, z: baseZ + heightMeters);
    final upper1 =
        RenderScenePoint(x: lower1.x, y: lower1.y, z: baseZ + heightMeters);
    final upper2 =
        RenderScenePoint(x: lower2.x, y: lower2.y, z: baseZ + heightMeters);
    final upper3 =
        RenderScenePoint(x: lower3.x, y: lower3.y, z: baseZ + heightMeters);
    final positions = <RenderScenePoint>[
      RenderScenePoint(x: lower0.x, y: lower0.y, z: baseZ),
      RenderScenePoint(x: lower1.x, y: lower1.y, z: baseZ),
      RenderScenePoint(x: lower2.x, y: lower2.y, z: baseZ),
      RenderScenePoint(x: lower3.x, y: lower3.y, z: baseZ),
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
        'level_locked': true,
        'kind': 'wall',
      },
    };
  }

  static void _rebuildAllWallObjects(List<Map<String, Object?>> objects) {
    final wallEntries = <_WallEntry>[];
    for (final object in objects) {
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (objectId == null || kind != 'wall') {
        continue;
      }
      final geometry = _wallGeometryFromMap(object);
      if (geometry == null) {
        continue;
      }
      final metadataMap =
          object['metadata'] is Map ? object['metadata'] as Map : null;
      final boundsMap =
          object['bounds'] is Map ? object['bounds'] as Map : null;
      Map? boundsMax;
      final rawBoundsMax = boundsMap == null ? null : boundsMap['max'];
      if (rawBoundsMax is Map) {
        boundsMax = rawBoundsMax;
      }
      final heightMeters =
          _toDouble(metadataMap?['height_meters']) ?? _toDouble(boundsMax?['z']) ?? defaultWallHeightMeters;
      wallEntries.add(
        _WallEntry(
          objectId: objectId,
          objectMap: object,
          geometry: geometry,
          heightMeters: heightMeters,
        ),
      );
    }

    final openingSpecs = <int, _ResolvedOpeningSpec>{};
    for (final object in objects) {
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind != 'door' && kind != 'window') {
        continue;
      }
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (objectId == null) {
        continue;
      }
      final spec = _resolveOpeningSpec(
        openingObject: object,
        allWalls: wallEntries,
      );
      if (spec != null) {
        openingSpecs[objectId] = spec;
      }
    }

    for (final wall in wallEntries) {
      final openings = <_OpeningCutSpec>[];
      for (final spec in openingSpecs.values) {
        if (spec.hostWall.objectId == wall.objectId) {
          openings.add(
            _OpeningCutSpec(
              startOffset: math.max(0.0, spec.offsetMeters - (spec.widthMeters * 0.5)),
              endOffset: math.min(
                wall.geometry.length,
                spec.offsetMeters + (spec.widthMeters * 0.5),
              ),
              bottomZ: math.max(0.0, spec.sillHeightMeters),
              topZ: math.min(
                wall.heightMeters,
                spec.sillHeightMeters + spec.heightMeters,
              ),
            ),
          );
        }
      }

      final rebuilt = _buildWallMeshWithOpenings(
        geometry: wall.geometry,
        heightMeters: wall.heightMeters,
        openings: openings,
        profilePolygon: _wallProfilePolygon(wall, wallEntries),
      );
      wall.objectMap['mesh'] = rebuilt.mesh;
      wall.objectMap['bounds'] = rebuilt.bounds.toJson();
    }

    for (final object in objects) {
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind != 'door' && kind != 'window') {
        continue;
      }
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      final spec = objectId == null ? null : openingSpecs[objectId];
      if (spec == null) {
        continue;
      }
      final rebuilt = _buildOpeningMesh(spec);
      object['mesh'] = rebuilt.mesh;
      object['bounds'] = rebuilt.bounds.toJson();
      object['metadata'] = <String, Object?>{
        ...(object['metadata'] is Map
            ? Map<String, Object?>.from(
                (object['metadata'] as Map).cast<String, Object?>(),
              )
            : const <String, Object?>{}),
        'host_wall_id': spec.hostWall.objectId,
        'offset_meters': spec.offsetMeters,
        'width_meters': spec.widthMeters,
        'height_meters': spec.heightMeters,
        'sill_height_meters': spec.sillHeightMeters,
        'panel_thickness_meters': spec.panelThicknessMeters,
        'axis_start': spec.hostWall.geometry.start.toJson(),
        'axis_end': spec.hostWall.geometry.end.toJson(),
        'kind': kind,
      };
    }
  }

  static void _rebuildDetectedRooms(List<Map<String, Object?>> objects) {
    objects.removeWhere(
      (object) => (object['kind']?.toString() ?? '').toLowerCase() == 'room',
    );

    final wallsByLevel = <int?, List<_WallEntry>>{};
    for (final object in objects) {
      final objectId = _toInt(object['element_id']) ?? _toInt(object['elementId']);
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (objectId == null || kind != 'wall') {
        continue;
      }
      final geometry = _wallGeometryFromMap(object);
      if (geometry == null) {
        continue;
      }
      final metadataMap =
          object['metadata'] is Map ? object['metadata'] as Map : null;
      final boundsMap =
          object['bounds'] is Map ? object['bounds'] as Map : null;
      Map? boundsMax;
      final rawBoundsMax = boundsMap == null ? null : boundsMap['max'];
      if (rawBoundsMax is Map) {
        boundsMax = rawBoundsMax;
      }
      final heightMeters = _toDouble(metadataMap?['height_meters']) ??
          _toDouble(boundsMax?['z']) ??
          defaultWallHeightMeters;
      final levelId = _toInt(object['level_id']) ?? _toInt(object['levelId']);
      wallsByLevel.putIfAbsent(levelId, () => <_WallEntry>[]).add(
        _WallEntry(
          objectId: objectId,
          objectMap: object,
          geometry: geometry,
          heightMeters: heightMeters,
        ),
      );
    }
    var nextId = _nextElementId(objects);
    for (final entry in wallsByLevel.entries) {
      final walls = entry.value;
      if (walls.length < 4) {
        continue;
      }

      final xs = <double>{
        for (final wall in walls) wall.geometry.start.x,
        for (final wall in walls) wall.geometry.end.x,
      }.toList()
        ..sort();
      final ys = <double>{
        for (final wall in walls) wall.geometry.start.y,
        for (final wall in walls) wall.geometry.end.y,
      }.toList()
        ..sort();
      if (xs.length < 2 || ys.length < 2) {
        continue;
      }

      final cellColumns = xs.length - 1;
      final cellRows = ys.length - 1;
      final validCell = List<List<bool>>.generate(
        cellColumns,
        (i) => List<bool>.generate(
          cellRows,
          (j) =>
              (xs[i + 1] - xs[i]).abs() > 1e-6 &&
              (ys[j + 1] - ys[j]).abs() > 1e-6,
        ),
      );
      final outside = List<List<bool>>.generate(
        cellColumns,
        (_) => List<bool>.filled(cellRows, false),
      );

      final queue = <_GridCell>[];
      for (var i = 0; i < cellColumns; i += 1) {
        for (var j = 0; j < cellRows; j += 1) {
          if (!validCell[i][j]) {
            continue;
          }
          if (i == 0 || j == 0 || i == cellColumns - 1 || j == cellRows - 1) {
            outside[i][j] = true;
            queue.add(_GridCell(i, j));
          }
        }
      }

      while (queue.isNotEmpty) {
        final cell = queue.removeLast();
        final i = cell.i;
        final j = cell.j;
        void tryVisit(int ni, int nj, bool blocked) {
          if (ni < 0 ||
              nj < 0 ||
              ni >= cellColumns ||
              nj >= cellRows ||
              !validCell[ni][nj] ||
              outside[ni][nj] ||
              blocked) {
            return;
          }
          outside[ni][nj] = true;
          queue.add(_GridCell(ni, nj));
        }

        tryVisit(
          i - 1,
          j,
          _blockingWallsVertical(walls, xs[i], ys[j], ys[j + 1]).isNotEmpty,
        );
        tryVisit(
          i + 1,
          j,
          _blockingWallsVertical(walls, xs[i + 1], ys[j], ys[j + 1]).isNotEmpty,
        );
        tryVisit(
          i,
          j - 1,
          _blockingWallsHorizontal(walls, ys[j], xs[i], xs[i + 1]).isNotEmpty,
        );
        tryVisit(
          i,
          j + 1,
          _blockingWallsHorizontal(walls, ys[j + 1], xs[i], xs[i + 1]).isNotEmpty,
        );
      }

      final visited = List<List<bool>>.generate(
        cellColumns,
        (_) => List<bool>.filled(cellRows, false),
      );
      for (var startI = 0; startI < cellColumns; startI += 1) {
        for (var startJ = 0; startJ < cellRows; startJ += 1) {
          if (!validCell[startI][startJ] ||
              outside[startI][startJ] ||
              visited[startI][startJ]) {
            continue;
          }
          final cluster = <_GridCell>[];
          final roomQueue = <_GridCell>[_GridCell(startI, startJ)];
          visited[startI][startJ] = true;
          while (roomQueue.isNotEmpty) {
            final cell = roomQueue.removeLast();
            cluster.add(cell);
            final i = cell.i;
            final j = cell.j;
            void tryRoom(int ni, int nj, bool blocked) {
              if (ni < 0 ||
                  nj < 0 ||
                  ni >= cellColumns ||
                  nj >= cellRows ||
                  !validCell[ni][nj] ||
                  outside[ni][nj] ||
                  visited[ni][nj] ||
                  blocked) {
                return;
              }
              visited[ni][nj] = true;
              roomQueue.add(_GridCell(ni, nj));
            }

            tryRoom(
              i - 1,
              j,
              _blockingWallsVertical(walls, xs[i], ys[j], ys[j + 1]).isNotEmpty,
            );
            tryRoom(
              i + 1,
              j,
              _blockingWallsVertical(walls, xs[i + 1], ys[j], ys[j + 1]).isNotEmpty,
            );
            tryRoom(
              i,
              j - 1,
              _blockingWallsHorizontal(walls, ys[j], xs[i], xs[i + 1]).isNotEmpty,
            );
            tryRoom(
              i,
              j + 1,
              _blockingWallsHorizontal(walls, ys[j + 1], xs[i], xs[i + 1]).isNotEmpty,
            );
          }

          if (cluster.isEmpty) {
            continue;
          }

          final roomMap = _buildRoomObjectFromCells(
            elementId: nextId++,
            cells: cluster,
            xs: xs,
            ys: ys,
            walls: walls,
          );
          if (roomMap != null) {
            objects.add(roomMap);
          }
        }
      }
    }
  }

  static Map<String, Object?>? _buildRoomObjectFromCells({
    required int elementId,
    required List<_GridCell> cells,
    required List<double> xs,
    required List<double> ys,
    required List<_WallEntry> walls,
  }) {
    if (cells.isEmpty) {
      return null;
    }
    final cellSet = cells.map((cell) => '${cell.i}:${cell.j}').toSet();
    final positions = <RenderScenePoint>[];
    final indices = <int>[];
    final boundaryWallIds = <int>{};
    final levelId =
        walls.isEmpty ? null : _toInt(walls.first.objectMap['level_id']);
    final baseZ = walls.isEmpty ? 0.0 : walls.first.geometry.start.z;
    var area = 0.0;
    var perimeter = 0.0;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final cell in cells) {
      final x0 = xs[cell.i];
      final x1 = xs[cell.i + 1];
      final y0 = ys[cell.j];
      final y1 = ys[cell.j + 1];
      final width = x1 - x0;
      final depth = y1 - y0;
      area += width * depth;
      minX = math.min(minX, x0);
      minY = math.min(minY, y0);
      maxX = math.max(maxX, x1);
      maxY = math.max(maxY, y1);

      final base = positions.length;
      positions.addAll(<RenderScenePoint>[
        RenderScenePoint(x: x0, y: y0, z: baseZ + 0.01),
        RenderScenePoint(x: x1, y: y0, z: baseZ + 0.01),
        RenderScenePoint(x: x1, y: y1, z: baseZ + 0.01),
        RenderScenePoint(x: x0, y: y1, z: baseZ + 0.01),
      ]);
      indices.addAll(<int>[base, base + 2, base + 1, base, base + 3, base + 2]);

      final leftKey = '${cell.i - 1}:${cell.j}';
      if (!cellSet.contains(leftKey)) {
        perimeter += depth;
        boundaryWallIds.addAll(_blockingWallsVertical(walls, x0, y0, y1));
      }
      final rightKey = '${cell.i + 1}:${cell.j}';
      if (!cellSet.contains(rightKey)) {
        perimeter += depth;
        boundaryWallIds.addAll(_blockingWallsVertical(walls, x1, y0, y1));
      }
      final bottomKey = '${cell.i}:${cell.j - 1}';
      if (!cellSet.contains(bottomKey)) {
        perimeter += width;
        boundaryWallIds.addAll(_blockingWallsHorizontal(walls, y0, x0, x1));
      }
      final topKey = '${cell.i}:${cell.j + 1}';
      if (!cellSet.contains(topKey)) {
        perimeter += width;
        boundaryWallIds.addAll(_blockingWallsHorizontal(walls, y1, x0, x1));
      }
    }

    final bounds = RenderSceneBounds.normalized(
      min: RenderScenePoint(x: minX, y: minY, z: baseZ),
      max: RenderScenePoint(x: maxX, y: maxY, z: baseZ + 0.02),
    );
    return <String, Object?>{
      'element_id': elementId,
      'kind': 'Room',
      'level_id': levelId,
      'selectable': true,
      'visible_by_default': true,
      'revision': 1,
      'bounds': bounds.toJson(),
      'mesh': <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': indices,
      },
      'material_category': 'room',
      'metadata': <String, Object?>{
        'area_m2': area,
        'perimeter_m': perimeter,
        'boundary_wall_ids': boundaryWallIds.toList()..sort(),
        'cell_count': cells.length,
        'level_locked': true,
      },
    };
  }

  static void _shiftObjectZInPlace(Map<String, Object?> object, double delta) {
    if (delta.abs() <= 1e-9) {
      return;
    }
    final bounds = _boundsFromMap(object);
    if (bounds != null && bounds.isFinite) {
      object['bounds'] = RenderSceneBounds.normalized(
        min: RenderScenePoint(
          x: bounds.min.x,
          y: bounds.min.y,
          z: bounds.min.z + delta,
        ),
        max: RenderScenePoint(
          x: bounds.max.x,
          y: bounds.max.y,
          z: bounds.max.z + delta,
        ),
      ).toJson();
    }

    final mesh = object['mesh'];
    if (mesh is Map) {
      final rawPositions = mesh['positions'];
      if (rawPositions is List) {
        mesh['positions'] = rawPositions
            .map(
              (entry) => RenderScenePoint.fromJson(entry),
            )
            .whereType<RenderScenePoint>()
            .map(
              (point) => RenderScenePoint(
                x: point.x,
                y: point.y,
                z: point.z + delta,
              ).toJson(),
            )
            .toList(growable: false);
      }
    }
  }

  static List<int> _blockingWallsVertical(
    List<_WallEntry> walls,
    double x,
    double y0,
    double y1,
  ) {
    final ids = <int>[];
    for (final wall in walls) {
      final geometry = wall.geometry;
      if ((geometry.start.x - geometry.end.x).abs() > 1e-6) {
        continue;
      }
      if ((geometry.start.x - x).abs() > 1e-6) {
        continue;
      }
      final wallMinY = math.min(geometry.start.y, geometry.end.y);
      final wallMaxY = math.max(geometry.start.y, geometry.end.y);
      if (wallMinY <= y0 + 1e-6 && wallMaxY >= y1 - 1e-6) {
        ids.add(wall.objectId);
      }
    }
    return ids;
  }

  static List<int> _blockingWallsHorizontal(
    List<_WallEntry> walls,
    double y,
    double x0,
    double x1,
  ) {
    final ids = <int>[];
    for (final wall in walls) {
      final geometry = wall.geometry;
      if ((geometry.start.y - geometry.end.y).abs() > 1e-6) {
        continue;
      }
      if ((geometry.start.y - y).abs() > 1e-6) {
        continue;
      }
      final wallMinX = math.min(geometry.start.x, geometry.end.x);
      final wallMaxX = math.max(geometry.start.x, geometry.end.x);
      if (wallMinX <= x0 + 1e-6 && wallMaxX >= x1 - 1e-6) {
        ids.add(wall.objectId);
      }
    }
    return ids;
  }

  static _ResolvedOpeningSpec? _resolveOpeningSpec({
    required Map<String, Object?> openingObject,
    required List<_WallEntry> allWalls,
  }) {
    final metadata =
        openingObject['metadata'] is Map ? openingObject['metadata'] as Map : null;
    final explicitHostWallId =
        _toInt(metadata?['host_wall_id'] ?? metadata?['hostWallId']);

    final openingBounds = _boundsFromMap(openingObject);
    if (openingBounds == null || !openingBounds.isFinite) {
      return null;
    }

    final openingCenter = openingBounds.center;
    final hostWall = explicitHostWallId != null
        ? _wallEntryById(allWalls, explicitHostWallId)
        : _deriveHostWallForOpening(openingCenter, openingBounds, allWalls);
    if (hostWall == null) {
      return null;
    }

    final offset = _projectOffsetAlongWall(hostWall.geometry, openingCenter);
    if (offset == null) {
      return null;
    }

    final width = _toDouble(metadata?['width_meters']) ??
        _openingWidthAlongWall(hostWall.geometry, openingBounds);
    final height = _toDouble(metadata?['height_meters']) ?? openingBounds.height;
    final sill = _toDouble(metadata?['sill_height_meters']) ??
        (openingBounds.min.z - hostWall.geometry.start.z);
    if (height <= 1e-6 || width <= 1e-6) {
      return null;
    }

    final panelThickness = _toDouble(metadata?['panel_thickness_meters']) ??
        math.min(
          math.max(hostWall.geometry.thickness * 0.5, 0.05),
          hostWall.geometry.thickness,
        );

    return _ResolvedOpeningSpec(
      hostWall: hostWall,
      offsetMeters: offset.clamp(0.0, hostWall.geometry.length).toDouble(),
      widthMeters: width,
      heightMeters: height,
      sillHeightMeters: math.max(0.0, sill),
      panelThicknessMeters: panelThickness,
    );
  }

  static _WallEntry? _deriveHostWallForOpening(
    RenderScenePoint center,
    RenderSceneBounds openingBounds,
    List<_WallEntry> allWalls,
  ) {
    _WallEntry? bestWall;
    var bestDistance = double.infinity;
    for (final wall in allWalls) {
      final offset = _projectOffsetAlongWall(wall.geometry, center);
      if (offset == null || offset < -1e-6 || offset > wall.geometry.length + 1e-6) {
        continue;
      }

      final projected = _pointAlongWall(wall.geometry, offset);
      final distance = projected.distanceTo(
        RenderScenePoint(x: center.x, y: center.y, z: projected.z),
      );
      final tolerance = math.max(wall.geometry.thickness, 0.25);
      final wallBaseZ = wall.geometry.start.z;
      final overlapsHeight =
          openingBounds.min.z < wallBaseZ + wall.heightMeters &&
              openingBounds.max.z > wallBaseZ;
      if (distance <= tolerance && overlapsHeight && distance < bestDistance) {
        bestDistance = distance;
        bestWall = wall;
      }
    }
    return bestWall;
  }

  static _WallEntry? _wallEntryById(List<_WallEntry> walls, int objectId) {
    for (final wall in walls) {
      if (wall.objectId == objectId) {
        return wall;
      }
    }
    return null;
  }

  static double? _projectOffsetAlongWall(
    _WallGeometry wall,
    RenderScenePoint point,
  ) {
    final axis = wall.end - wall.start;
    final lengthSquared = _dot(axis, axis);
    if (lengthSquared <= 1e-9) {
      return null;
    }
    final t = _dot(point - wall.start, axis) / lengthSquared;
    return wall.length * t;
  }

  static RenderScenePoint _pointAlongWall(_WallGeometry wall, double offset) {
    final clamped = offset.clamp(0.0, wall.length);
    final axisUnit = _unit3(wall.end - wall.start);
    return wall.start + axisUnit.scale(clamped);
  }

  static double _openingWidthAlongWall(
    _WallGeometry wall,
    RenderSceneBounds bounds,
  ) {
    final axisUnit = _unit3(wall.end - wall.start);
    final corners = _boundsCorners(bounds);
    var minAlong = double.infinity;
    var maxAlong = double.negativeInfinity;
    for (final corner in corners) {
      final along = _dot(corner - wall.start, axisUnit);
      minAlong = math.min(minAlong, along);
      maxAlong = math.max(maxAlong, along);
    }
    return math.max(maxAlong - minAlong, 0.0);
  }

  static _BuiltMeshResult _buildWallMeshWithOpenings({
    required _WallGeometry geometry,
    required double heightMeters,
    required List<_OpeningCutSpec> openings,
    required List<RenderScenePoint> profilePolygon,
  }) {
    final positions = <RenderScenePoint>[];
    final indices = <int>[];
    final axisUnit = _unit3(geometry.end - geometry.start);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0.0);
    final localProfile = profilePolygon
        .map(
          (point) => RenderScenePoint(
            x: _dot(point - geometry.start, axisUnit),
            y: _dot(point - geometry.start, normal),
            z: 0.0,
          ),
        )
        .toList(growable: false);
    double projectX(RenderScenePoint point) {
      final local = point - geometry.start;
      return _dot(local, axisUnit);
    }

    final projectedXs = profilePolygon.map(projectX).toList(growable: false);
    final minX = projectedXs.reduce(math.min);
    final maxX = projectedXs.reduce(math.max);

    RenderScenePoint worldPoint(double localX, double localY, double localZ) {
      return RenderScenePoint(
        x: geometry.start.x + axisUnit.x * localX + normal.x * localY,
        y: geometry.start.y + axisUnit.y * localX + normal.y * localY,
        z: geometry.start.z + localZ,
      );
    }

    final xBreaks = _sortedUniqueBreaks(<double>[
      minX,
      maxX,
      for (final opening in openings) ...<double>[
        opening.startOffset.clamp(minX, maxX),
        opening.endOffset.clamp(minX, maxX),
      ],
    ]);

    for (var index = 0; index + 1 < xBreaks.length; index += 1) {
      final x0 = xBreaks[index];
      final x1 = xBreaks[index + 1];
      if ((x1 - x0).abs() <= 1e-6) {
        continue;
      }

      final overlappingOpenings = openings
          .where((opening) => opening.startOffset < x1 - 1e-6)
          .where((opening) => opening.endOffset > x0 + 1e-6)
          .toList(growable: false);

      final clippedProfile = _clipPolygonByXRange(localProfile, x0, x1);
      if (clippedProfile.length < 3) {
        continue;
      }

      if (overlappingOpenings.isEmpty) {
        _appendExtrudedPolygonMesh(
          positions: positions,
          indices: indices,
          worldPoint: worldPoint,
          polygon: clippedProfile,
          z0: 0.0,
          z1: heightMeters,
        );
        continue;
      }

      final zBreaks = _sortedUniqueBreaks(<double>[
        0.0,
        heightMeters,
        for (final opening in overlappingOpenings) ...<double>[
          opening.bottomZ.clamp(0.0, heightMeters),
          opening.topZ.clamp(0.0, heightMeters),
        ],
      ]);

      for (var zIndex = 0; zIndex + 1 < zBreaks.length; zIndex += 1) {
        final z0 = zBreaks[zIndex];
        final z1 = zBreaks[zIndex + 1];
        if ((z1 - z0).abs() <= 1e-6) {
          continue;
        }
        final sampleZ = (z0 + z1) * 0.5;
        final blocked = overlappingOpenings.any(
          (opening) =>
              sampleZ > opening.bottomZ + 1e-6 &&
              sampleZ < opening.topZ - 1e-6,
        );
        if (blocked) {
          continue;
        }
        _appendExtrudedPolygonMesh(
          positions: positions,
          indices: indices,
          worldPoint: worldPoint,
          polygon: clippedProfile,
          z0: z0,
          z1: z1,
        );
      }
    }

    final bounds = positions.isEmpty
        ? RenderSceneBounds.zero()
        : RenderSceneBounds.union(
            positions.map(
              (point) => RenderSceneBounds.normalized(min: point, max: point),
            ),
          );
    return _BuiltMeshResult(
      mesh: <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': indices,
      },
      bounds: bounds,
    );
  }

  static _BuiltMeshResult _buildOpeningMesh(_ResolvedOpeningSpec spec) {
    final positions = <RenderScenePoint>[];
    final indices = <int>[];
    final axisUnit = _unit3(spec.hostWall.geometry.end - spec.hostWall.geometry.start);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0.0);

    RenderScenePoint worldPoint(double localX, double localY, double localZ) {
      return RenderScenePoint(
        x: spec.hostWall.geometry.start.x +
            axisUnit.x * localX +
            normal.x * localY,
        y: spec.hostWall.geometry.start.y +
            axisUnit.y * localX +
            normal.y * localY,
        z: localZ,
      );
    }

    _appendBoxMesh(
      positions: positions,
      indices: indices,
      cornerBuilder: worldPoint,
      x0: spec.offsetMeters - spec.widthMeters * 0.5,
      x1: spec.offsetMeters + spec.widthMeters * 0.5,
      y0: -spec.panelThicknessMeters * 0.5,
      y1: spec.panelThicknessMeters * 0.5,
      z0: spec.sillHeightMeters,
      z1: spec.sillHeightMeters + spec.heightMeters,
    );

    final bounds = RenderSceneBounds.union(
      positions.map((point) => RenderSceneBounds.normalized(min: point, max: point)),
    );
    return _BuiltMeshResult(
      mesh: <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': indices,
      },
      bounds: bounds,
    );
  }

  static void _appendBoxMesh({
    required List<RenderScenePoint> positions,
    required List<int> indices,
    required RenderScenePoint Function(double x, double y, double z)
        cornerBuilder,
    required double x0,
    required double x1,
    required double y0,
    required double y1,
    required double z0,
    required double z1,
  }) {
    final baseIndex = positions.length;
    final corners = <RenderScenePoint>[
      cornerBuilder(x0, y0, z0),
      cornerBuilder(x1, y0, z0),
      cornerBuilder(x1, y1, z0),
      cornerBuilder(x0, y1, z0),
      cornerBuilder(x0, y0, z1),
      cornerBuilder(x1, y0, z1),
      cornerBuilder(x1, y1, z1),
      cornerBuilder(x0, y1, z1),
    ];
    positions.addAll(corners);
    indices.addAll(<int>[
      baseIndex + 0, baseIndex + 2, baseIndex + 1,
      baseIndex + 0, baseIndex + 3, baseIndex + 2,
      baseIndex + 4, baseIndex + 5, baseIndex + 6,
      baseIndex + 4, baseIndex + 6, baseIndex + 7,
      baseIndex + 0, baseIndex + 1, baseIndex + 5,
      baseIndex + 0, baseIndex + 5, baseIndex + 4,
      baseIndex + 1, baseIndex + 2, baseIndex + 6,
      baseIndex + 1, baseIndex + 6, baseIndex + 5,
      baseIndex + 2, baseIndex + 3, baseIndex + 7,
      baseIndex + 2, baseIndex + 7, baseIndex + 6,
      baseIndex + 3, baseIndex + 0, baseIndex + 4,
      baseIndex + 3, baseIndex + 4, baseIndex + 7,
    ]);
  }

  static void _appendExtrudedPolygonMesh({
    required List<RenderScenePoint> positions,
    required List<int> indices,
    required RenderScenePoint Function(double x, double y, double z) worldPoint,
    required List<RenderScenePoint> polygon,
    required double z0,
    required double z1,
  }) {
    if (polygon.length < 3) {
      return;
    }

    final baseIndex = positions.length;
    for (final point in polygon) {
      positions.add(worldPoint(point.x, point.y, z0));
    }
    for (final point in polygon) {
      positions.add(worldPoint(point.x, point.y, z1));
    }

    final topBase = baseIndex + polygon.length;
    for (var index = 1; index + 1 < polygon.length; index += 1) {
      indices.addAll(<int>[baseIndex, baseIndex + index + 1, baseIndex + index]);
      indices.addAll(<int>[topBase, topBase + index, topBase + index + 1]);
    }

    for (var index = 0; index < polygon.length; index += 1) {
      final next = (index + 1) % polygon.length;
      final a = baseIndex + index;
      final b = baseIndex + next;
      final c = topBase + next;
      final d = topBase + index;
      indices.addAll(<int>[a, b, c, a, c, d]);
    }
  }

  static List<RenderScenePoint> _clipPolygonByXRange(
    List<RenderScenePoint> polygon,
    double minX,
    double maxX,
  ) {
    final clippedMin = _clipPolygonMinX(polygon, minX);
    if (clippedMin.length < 3) {
      return const <RenderScenePoint>[];
    }
    return _clipPolygonMaxX(clippedMin, maxX);
  }

  static List<RenderScenePoint> _clipPolygonMinX(
    List<RenderScenePoint> polygon,
    double minX,
  ) {
    final result = <RenderScenePoint>[];
    for (var index = 0; index < polygon.length; index += 1) {
      final current = polygon[index];
      final next = polygon[(index + 1) % polygon.length];
      final currentInside = current.x >= minX - 1e-6;
      final nextInside = next.x >= minX - 1e-6;
      if (currentInside && nextInside) {
        result.add(next);
      } else if (currentInside && !nextInside) {
        result.add(_intersectAtX(current, next, minX));
      } else if (!currentInside && nextInside) {
        result.add(_intersectAtX(current, next, minX));
        result.add(next);
      }
    }
    return result;
  }

  static List<RenderScenePoint> _clipPolygonMaxX(
    List<RenderScenePoint> polygon,
    double maxX,
  ) {
    final result = <RenderScenePoint>[];
    for (var index = 0; index < polygon.length; index += 1) {
      final current = polygon[index];
      final next = polygon[(index + 1) % polygon.length];
      final currentInside = current.x <= maxX + 1e-6;
      final nextInside = next.x <= maxX + 1e-6;
      if (currentInside && nextInside) {
        result.add(next);
      } else if (currentInside && !nextInside) {
        result.add(_intersectAtX(current, next, maxX));
      } else if (!currentInside && nextInside) {
        result.add(_intersectAtX(current, next, maxX));
        result.add(next);
      }
    }
    return result;
  }

  static RenderScenePoint _intersectAtX(
    RenderScenePoint a,
    RenderScenePoint b,
    double targetX,
  ) {
    final dx = b.x - a.x;
    if (dx.abs() <= 1e-9) {
      return RenderScenePoint(x: targetX, y: a.y, z: 0.0);
    }
    final t = (targetX - a.x) / dx;
    return RenderScenePoint(
      x: targetX,
      y: a.y + (b.y - a.y) * t,
      z: 0.0,
    );
  }

  static List<RenderScenePoint> _wallProfilePolygon(
    _WallEntry wall,
    List<_WallEntry> allWalls,
  ) {
    final length = wall.geometry.length;
    final halfThickness = wall.geometry.thickness * 0.5;
    var startLowerX = 0.0;
    var startUpperX = 0.0;
    var endLowerX = length;
    var endUpperX = length;
    final direction = _unit2(wall.geometry.end - wall.geometry.start);

    for (final other in allWalls) {
      if (other.objectId == wall.objectId) {
        continue;
      }
      final sharedAtStart = _samePoint2(wall.geometry.start, other.geometry.start) ||
          _samePoint2(wall.geometry.start, other.geometry.end);
      final sharedAtEnd = _samePoint2(wall.geometry.end, other.geometry.start) ||
          _samePoint2(wall.geometry.end, other.geometry.end);
      if (!sharedAtStart && !sharedAtEnd) {
        continue;
      }

      final joinPoint = sharedAtStart ? wall.geometry.start : wall.geometry.end;
      final otherDirection = _directionAwayFrom(joinPoint, other.geometry);
      final turn = _cross2(direction, otherDirection);
      final alignment = _dot2(direction, otherDirection).abs();
      if (turn.abs() <= 1e-9) {
        continue;
      }
      // Restrict miter extension to roughly orthogonal joins.
      // Diagonal/acute joins looked visually "fatter" in top view because
      // the simple profile extender over-expanded the footprint.
      if (alignment > 0.35) {
        continue;
      }

      if (sharedAtEnd) {
        if (turn > 0.0) {
          endUpperX += halfThickness;
        } else {
          endLowerX += halfThickness;
        }
      } else {
        if (turn > 0.0) {
          startLowerX -= halfThickness;
        } else {
          startUpperX -= halfThickness;
        }
      }
    }

    final axisUnit = _unit3(wall.geometry.end - wall.geometry.start);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0.0);
    RenderScenePoint world(double localX, double localY) {
      return RenderScenePoint(
        x: wall.geometry.start.x + axisUnit.x * localX + normal.x * localY,
        y: wall.geometry.start.y + axisUnit.y * localX + normal.y * localY,
        z: 0.0,
      );
    }

    return <RenderScenePoint>[
      world(startLowerX, -halfThickness),
      world(endLowerX, -halfThickness),
      world(endUpperX, halfThickness),
      world(startUpperX, halfThickness),
    ];
  }

  static bool _samePoint2(RenderScenePoint a, RenderScenePoint b) {
    return (a.x - b.x).abs() <= 1e-6 && (a.y - b.y).abs() <= 1e-6;
  }

  static RenderScenePoint _directionAwayFrom(
    RenderScenePoint joinPoint,
    _WallGeometry wall,
  ) {
    final startDistance = joinPoint.distanceTo(wall.start);
    final endDistance = joinPoint.distanceTo(wall.end);
    final away =
        startDistance < endDistance ? (wall.end - wall.start) : (wall.start - wall.end);
    return _unit2(away);
  }

  static double _cross2(RenderScenePoint a, RenderScenePoint b) {
    return (a.x * b.y) - (a.y * b.x);
  }

  static double _dot2(RenderScenePoint a, RenderScenePoint b) {
    return (a.x * b.x) + (a.y * b.y);
  }

  static RenderScenePoint _unit2(RenderScenePoint vector) {
    final length = math.sqrt((vector.x * vector.x) + (vector.y * vector.y));
    if (length <= 1e-9) {
      return const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0);
    }
    return RenderScenePoint(x: vector.x / length, y: vector.y / length, z: 0.0);
  }

  static RenderScenePoint _unit3(RenderScenePoint vector) {
    final length = vector.distanceTo(const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0));
    if (length <= 1e-9) {
      return const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0);
    }
    return RenderScenePoint(
      x: vector.x / length,
      y: vector.y / length,
      z: vector.z / length,
    );
  }

  static List<double> _sortedUniqueBreaks(List<double> values) {
    final sorted = values.where((value) => value.isFinite).toList()..sort();
    final unique = <double>[];
    for (final value in sorted) {
      if (unique.isEmpty || (value - unique.last).abs() > 1e-6) {
        unique.add(value);
      }
    }
    return unique;
  }

  static _WallGeometry? _wallGeometryFromMap(Map<String, Object?> wallObject) {
    final metadata = wallObject['metadata'];
    final metadataMap = metadata is Map ? metadata : null;
    final axisStart = RenderScenePoint.fromJson(
      metadataMap?['axis_start'] ?? metadataMap?['axisStart'],
    );
    final axisEnd = RenderScenePoint.fromJson(
      metadataMap?['axis_end'] ?? metadataMap?['axisEnd'],
    );
    final thickness = _toDouble(
      metadataMap?['thickness_meters'] ?? metadataMap?['thicknessMeters'],
    );
    if (axisStart != null && axisEnd != null && thickness != null) {
      return _WallGeometry(start: axisStart, end: axisEnd, thickness: thickness);
    }

    final bounds = _boundsFromMap(wallObject);
    if (bounds == null || !bounds.isFinite) {
      return null;
    }
    final width = bounds.width;
    final depth = bounds.depth;
    if (width >= depth) {
      return _WallGeometry(
        start: RenderScenePoint(
          x: bounds.min.x,
          y: (bounds.min.y + bounds.max.y) * 0.5,
          z: 0.0,
        ),
        end: RenderScenePoint(
          x: bounds.max.x,
          y: (bounds.min.y + bounds.max.y) * 0.5,
          z: 0.0,
        ),
        thickness: depth,
      );
    }

    return _WallGeometry(
      start: RenderScenePoint(
        x: (bounds.min.x + bounds.max.x) * 0.5,
        y: bounds.min.y,
        z: 0.0,
      ),
      end: RenderScenePoint(
        x: (bounds.min.x + bounds.max.x) * 0.5,
        y: bounds.max.y,
        z: 0.0,
      ),
      thickness: width,
    );
  }

  static RenderSceneBounds? _boundsFromMap(Map<String, Object?> object) {
    final bounds = RenderSceneBounds.fromJson(object['bounds']);
    if (bounds != null) {
      return bounds;
    }
    final mesh = object['mesh'];
    if (mesh is! Map) {
      return null;
    }
    final rawPositions = mesh['positions'];
    if (rawPositions is! List) {
      return null;
    }
    final points = rawPositions
        .map(RenderScenePoint.fromJson)
        .whereType<RenderScenePoint>()
        .toList(growable: false);
    if (points.isEmpty) {
      return null;
    }
    return RenderSceneBounds.union(
      points.map((point) => RenderSceneBounds.normalized(min: point, max: point)),
    );
  }

  static List<RenderScenePoint> _boundsCorners(RenderSceneBounds bounds) {
    return <RenderScenePoint>[
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.max.z),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.max.z),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.max.z),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.max.z),
    ];
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

class _OpeningCutSpec {
  const _OpeningCutSpec({
    required this.startOffset,
    required this.endOffset,
    required this.bottomZ,
    required this.topZ,
  });

  final double startOffset;
  final double endOffset;
  final double bottomZ;
  final double topZ;
}

class _BuiltMeshResult {
  const _BuiltMeshResult({
    required this.mesh,
    required this.bounds,
  });

  final Map<String, Object?> mesh;
  final RenderSceneBounds bounds;
}

class _GridCell {
  const _GridCell(this.i, this.j);

  final int i;
  final int j;
}

class _ResolvedOpeningSpec {
  const _ResolvedOpeningSpec({
    required this.hostWall,
    required this.offsetMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.panelThicknessMeters,
  });

  final _WallEntry hostWall;
  final double offsetMeters;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final double panelThicknessMeters;
}

class _WallEntry {
  const _WallEntry({
    required this.objectId,
    required this.objectMap,
    required this.geometry,
    required this.heightMeters,
  });

  final int objectId;
  final Map<String, Object?> objectMap;
  final _WallGeometry geometry;
  final double heightMeters;
}
