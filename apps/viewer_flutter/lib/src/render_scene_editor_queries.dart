part of 'render_scene_editor.dart';

/// Read-only scene queries shared by viewport, authoring and documentation.
///
/// [RenderSceneEditor] keeps compatibility forwarding methods, while this
/// class is the actual query owner for wall, room and surface inspection.
class RenderSceneQueries {
  static const String glassWallOpeningMessage =
      'Glass walls cannot host doors or windows. Select a solid wall.';

  /// Returns the same semantic answer used by opening authoring and the
  /// fallback renderer.  Native scenes expose a layer profile; older cached
  /// scenes may only expose the wall/material metadata, so keep all of those
  /// representations compatible here rather than duplicating the rule in
  /// each tool.
  static bool isGlassWall(RenderScene scene, RenderSceneObject wall) {
    if (wall.kindKey != 'wall') {
      return false;
    }

    final semanticValues = <String>[
      wall.materialCategory,
      wall.metadata['wall_type_name']?.toString() ?? '',
      wall.metadata['wall_type_category']?.toString() ?? '',
    ];
    if (semanticValues.any((value) => value.toLowerCase().contains('glass'))) {
      return true;
    }

    final profile = wall.metadata['layer_profile'];
    if (profile is! String || profile.isEmpty) {
      return false;
    }
    for (final layer in profile.split(';')) {
      final parts = layer.split(':');
      if (parts.length != 2) {
        continue;
      }
      final material = scene.materialById(int.tryParse(parts.first));
      if (material == null) {
        continue;
      }
      if (material.category.toLowerCase().contains('glass')) {
        return true;
      }
    }
    return false;
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

  static RenderSceneBounds? surfaceBoundsForWalls(
      List<RenderSceneObject> walls) {
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

  static List<RenderScenePoint>? surfacePolygonForWalls(
    List<RenderSceneObject> walls, {
    double toleranceMeters = 0.45,
  }) {
    final segments = <({RenderScenePoint start, RenderScenePoint end})>[];
    for (final wall in walls) {
      if (wall.kindKey != 'wall') {
        continue;
      }
      final start = wallStartPoint(wall);
      final end = wallEndPoint(wall);
      if (start == null || end == null || start.distanceTo(end) <= 1e-6) {
        continue;
      }
      segments.add((start: start, end: end));
    }
    if (segments.length < 3) {
      return null;
    }

    List<RenderScenePoint>? traceFrom(bool reverseFirst) {
      final first = segments.first;
      final oriented = <({RenderScenePoint start, RenderScenePoint end})>[
        reverseFirst
            ? (start: first.end, end: first.start)
            : (start: first.start, end: first.end),
      ];
      final used = <bool>[...List<bool>.filled(segments.length, false)];
      used[0] = true;

      while (oriented.length < segments.length) {
        final current = oriented.last.end;
        var bestIndex = -1;
        var bestDistance = double.infinity;
        var reverse = false;
        for (var index = 1; index < segments.length; index += 1) {
          if (used[index]) continue;
          final segment = segments[index];
          final startDistance = _planDistance2(segment.start, current);
          final endDistance = _planDistance2(segment.end, current);
          final candidateDistance = math.min(startDistance, endDistance);
          if (candidateDistance <= toleranceMeters &&
              candidateDistance < bestDistance) {
            bestIndex = index;
            bestDistance = candidateDistance;
            reverse = endDistance < startDistance;
          }
        }
        if (bestIndex < 0) return null;
        final segment = segments[bestIndex];
        oriented.add(
          reverse
              ? (start: segment.end, end: segment.start)
              : (start: segment.start, end: segment.end),
        );
        used[bestIndex] = true;
      }

      if (_planDistance2(oriented.last.end, oriented.first.start) >
          toleranceMeters) {
        return null;
      }

      final polygon = <RenderScenePoint>[];
      for (var index = 0; index < oriented.length; index += 1) {
        final previous =
            oriented[(index - 1 + oriented.length) % oriented.length];
        final current = oriented[index];
        final intersection = _planLineIntersection(
          previous.start,
          previous.end,
          current.start,
          current.end,
        );
        final corner = intersection != null &&
                _planDistance2(intersection, previous.end) <=
                    toleranceMeters * 4.0 &&
                _planDistance2(intersection, current.start) <=
                    toleranceMeters * 4.0
            ? intersection
            : RenderScenePoint(
                x: (previous.end.x + current.start.x) * 0.5,
                y: (previous.end.y + current.start.y) * 0.5,
                z: current.start.z,
              );
        polygon.add(corner);
      }

      final simplified = <RenderScenePoint>[];
      for (final point in polygon) {
        if (simplified.isEmpty ||
            !_samePlanPoint(simplified.last, point, toleranceMeters)) {
          simplified.add(point);
        }
      }
      if (simplified.length >= 2 &&
          _samePlanPoint(simplified.first, simplified.last, toleranceMeters)) {
        simplified.removeLast();
      }
      if (simplified.length < 3 || _polygonArea2d(simplified).abs() <= 1e-6) {
        return null;
      }
      return simplified;
    }

    return traceFrom(false) ?? traceFrom(true);
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
      final objectId =
          _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (objectId == targetId) {
        return true;
      }
      if (target.kindKey == 'wall') {
        final metadata = object['metadata'];
        if (metadata is Map) {
          final hostId =
              _toInt(metadata['host_wall_id'] ?? metadata['hostWallId']);
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
    final updates = wallAxisUpdatesForJoin(
      scene: scene,
      wall: wall,
      start: start,
      end: end,
    );

    for (var index = 0; index < objects.length; index += 1) {
      final objectId = _toInt(objects[index]['element_id']) ??
          _toInt(objects[index]['elementId']);
      final kind = (objects[index]['kind']?.toString() ?? '').toLowerCase();
      if (objectId == null || kind != 'wall') {
        continue;
      }
      final geometry = _wallGeometryFromMap(objects[index]);
      final metadataMap = objects[index]['metadata'] is Map
          ? objects[index]['metadata'] as Map
          : null;
      final boundsMap = objects[index]['bounds'] is Map
          ? objects[index]['bounds'] as Map
          : null;
      Map? boundsMax;
      final rawBoundsMax = boundsMap == null ? null : boundsMap['max'];
      if (rawBoundsMax is Map) {
        boundsMax = rawBoundsMax;
      }
      final heightMeters = _toDouble(metadataMap?['height_meters']) ??
          _toDouble(boundsMax?['z']) ??
          RenderSceneEditor.defaultWallHeightMeters;
      final thicknessMeters =
          geometry?.thickness ?? RenderSceneEditor.defaultWallThicknessMeters;
      final levelId = _toInt(objects[index]['level_id']) ??
          _toInt(objects[index]['levelId']);
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
        metadata: metadataMap == null
            ? const <String, Object?>{}
            : Map<String, Object?>.from(metadataMap.cast<String, Object?>()),
        revision: _toInt(objects[index]['revision']) ?? 1,
        materialCategory:
            objects[index]['material_category']?.toString() ?? 'structural',
      );
    }
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ wall');
  }

  /// Returns the selected wall axis and, for a rigid body translation, only
  /// the immediately connected wall endpoints that must follow it.
  ///
  /// Endpoint-handle edits deliberately remain local. Walking the complete
  /// endpoint graph here used to let one drag move an entire storey of walls.
  static Map<int, ({RenderScenePoint start, RenderScenePoint end})>
      wallAxisUpdatesForJoin({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint start,
    required RenderScenePoint end,
    // Native scenes carry exact semantic axes. Legacy scenes may only have
    // miter-expanded bounds, so allow half a typical wall thickness while
    // still limiting propagation to immediate neighbours.
    double toleranceMeters = 0.15,
  }) {
    if (wall.kindKey != 'wall' || wall.elementId == null) {
      return const <int, ({RenderScenePoint start, RenderScenePoint end})>{};
    }
    final originalStart = wallStartPoint(wall);
    final originalEnd = wallEndPoint(wall);
    if (originalStart == null || originalEnd == null) {
      return const <int, ({RenderScenePoint start, RenderScenePoint end})>{};
    }
    final updates = <int, ({RenderScenePoint start, RenderScenePoint end})>{
      wall.elementId!: (start: start, end: end),
    };
    final startDelta = start - originalStart;
    final endDelta = end - originalEnd;
    final isRigidTranslation = (startDelta.x - endDelta.x).abs() <= 1e-6 &&
        (startDelta.y - endDelta.y).abs() <= 1e-6;
    if (!isRigidTranslation) {
      return updates;
    }

    for (final other in scene.objects) {
      final otherId = other.elementId;
      if (other.kindKey != 'wall' ||
          otherId == null ||
          otherId == wall.elementId) {
        continue;
      }
      final otherStart = wallStartPoint(other);
      final otherEnd = wallEndPoint(other);
      if (otherStart == null || otherEnd == null) continue;
      var nextStart = otherStart;
      var nextEnd = otherEnd;
      var changed = false;
      if (_samePoint2(otherStart, originalStart, toleranceMeters) ||
          _samePoint2(otherStart, originalEnd, toleranceMeters)) {
        nextStart = otherStart + startDelta;
        changed = true;
      }
      if (_samePoint2(otherEnd, originalStart, toleranceMeters) ||
          _samePoint2(otherEnd, originalEnd, toleranceMeters)) {
        nextEnd = otherEnd + startDelta;
        changed = true;
      }
      // An immediately attached T branch has its endpoint on the selected
      // wall's *middle*, not on either selected endpoint. Carry only that
      // endpoint during a rigid body move. The host wall stays straight and
      // no unrelated branch is traversed beyond this direct attachment.
      final intersection = _planLineIntersection(
        originalStart,
        originalEnd,
        otherStart,
        otherEnd,
      );
      if (intersection != null &&
          _pointOnPlanSegment(intersection, originalStart, originalEnd,
              toleranceMeters: toleranceMeters) &&
          _pointOnPlanSegment(intersection, otherStart, otherEnd,
              toleranceMeters: toleranceMeters)) {
        final startAtJoin = _samePoint2(
          otherStart,
          intersection,
          toleranceMeters,
        );
        final endAtJoin = _samePoint2(
          otherEnd,
          intersection,
          toleranceMeters,
        );
        if (startAtJoin && !endAtJoin) {
          nextStart = otherStart + startDelta;
          changed = true;
        } else if (endAtJoin && !startAtJoin) {
          nextEnd = otherEnd + startDelta;
          changed = true;
        }
      }
      if (changed) {
        updates[otherId] = (start: nextStart, end: nextEnd);
      }
    }
    return updates;
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
      final objectId =
          _toInt(object['element_id']) ?? _toInt(object['elementId']);
      if (objectId != openingId) {
        continue;
      }
      final metadata = object['metadata'] is Map
          ? Map<String, Object?>.from(
              (object['metadata'] as Map).cast<String, Object?>())
          : <String, Object?>{};
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
        .where((object) =>
            (object['kind']?.toString() ?? '').toLowerCase() == 'room')
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
        nextScene = RenderSceneEditor.addFloorForRoom(
          scene: nextScene,
          room: room,
          thicknessMeters: floorThicknessMeters,
          topElevationMeters: room.bounds.min.z + floorTopElevationMeters,
        );
      }
      if (includeCeilings) {
        nextScene = RenderSceneEditor.addCeilingForRoom(
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
      final metadata = object['metadata'] is Map
          ? Map<String, Object?>.from(
              (object['metadata'] as Map).cast<String, Object?>())
          : <String, Object?>{};
      if (metadata.containsKey('source_room_id')) {
        metadata['auto_generated_from_room'] = true;
        object['metadata'] = metadata;
      }
    }
    nextMap['objects'] = nextObjects;
    return _parseSceneMap(nextMap, source: '${scene.source} ~ auto surfaces');
  }
}
