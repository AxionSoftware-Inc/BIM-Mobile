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

  /// Returns the authored wall centerline. Curved walls expose a sampled
  /// centerline for rendering/picking while their model identity remains one
  /// wall object; straight walls simply return their two axis endpoints.
  static List<RenderScenePoint> wallCenterlinePoints(RenderSceneObject wall) {
    final raw = wall.metadata['curve_points'];
    if (raw is String && raw.isNotEmpty) {
      final parsed = <RenderScenePoint>[];
      for (final token in raw.split(';')) {
        final values = token.split(',');
        if (values.length != 2) continue;
        final x = double.tryParse(values[0]);
        final y = double.tryParse(values[1]);
        if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
        parsed.add(RenderScenePoint(x: x, y: y, z: 0));
      }
      if (parsed.length >= 2) {
        return List<RenderScenePoint>.unmodifiable(parsed);
      }
    }
    final start = wallStartPoint(wall);
    final end = wallEndPoint(wall);
    if (start == null || end == null) return const <RenderScenePoint>[];
    return <RenderScenePoint>[start, end];
  }

  /// Returns the editable visual midpoint of a curved wall. The persisted
  /// arc definition is authoritative, while its sampled centerline gives
  /// both fallback and Android overlays the same stable handle location.
  static RenderScenePoint? wallMidpointPoint(RenderSceneObject wall) {
    final centerline = wallCenterlinePoints(wall);
    if (centerline.length <= 2) return null;
    return centerline[centerline.length ~/ 2];
  }

  /// Reads the authoritative circular definition kept in wall metadata.
  /// Centerline samples are retained only as a lightweight control-handle
  /// fallback; edits are committed with center/radius/sweep, never as small
  /// replacement wall segments.
  static WallArcGeometry? wallArcGeometry(RenderSceneObject wall) {
    if (wall.kindKey != 'wall') return null;
    final metadata = wall.metadata;
    if (metadata['curve_kind']?.toString().toLowerCase() != 'arc') {
      return null;
    }
    final start = wallStartPoint(wall);
    final end = wallEndPoint(wall);
    final centerX = _toDouble(
      metadata['curve_center_x'] ?? metadata['curveCenterX'],
    );
    final centerY = _toDouble(
      metadata['curve_center_y'] ?? metadata['curveCenterY'],
    );
    final radius = _toDouble(
      metadata['curve_radius_meters'] ?? metadata['curveRadiusMeters'],
    );
    final sweep = _toDouble(
      metadata['curve_sweep_radians'] ?? metadata['curveSweepRadians'],
    );
    if (start == null ||
        end == null ||
        centerX == null ||
        centerY == null ||
        radius == null ||
        sweep == null ||
        !radius.isFinite ||
        radius <= 1e-6 ||
        !sweep.isFinite ||
        sweep.abs() <= 1e-6 ||
        sweep.abs() > 2.0 * math.pi + 1e-6) {
      return null;
    }
    final center = RenderScenePoint(x: centerX, y: centerY, z: start.z);
    var points = wallCenterlinePoints(wall);
    if (points.length < 3) {
      final startAngle = math.atan2(start.y - center.y, start.x - center.x);
      final count =
          math.max(8, math.min(48, (radius * sweep.abs() / 0.18).ceil()));
      points = <RenderScenePoint>[
        for (var index = 0; index <= count; index += 1)
          RenderScenePoint(
            x: center.x + radius * math.cos(startAngle + sweep * index / count),
            y: center.y + radius * math.sin(startAngle + sweep * index / count),
            z: start.z,
          ),
      ];
      points[0] = start;
      points[points.length - 1] = end;
    }
    return WallArcGeometry(
      center: center,
      start: start,
      end: end,
      radiusMeters: radius,
      sweepRadians: sweep,
      points: List<RenderScenePoint>.unmodifiable(points),
    );
  }

  static double? wallThickness(RenderSceneObject wall) {
    return _wallGeometry(wall)?.thickness;
  }

  static double? wallLength(RenderSceneObject wall) {
    return _wallGeometry(wall)?.length;
  }

  /// Returns the authored wall centerline point at a distance from its start.
  /// Both straight and curved walls use the same arc samples, so hosted
  /// families can resolve their position without duplicating wall geometry.
  static RenderScenePoint? wallPointAtOffset(
    RenderSceneObject wall,
    double offsetMeters,
  ) {
    final points = wallCenterlinePoints(wall);
    if (points.length < 2 || !offsetMeters.isFinite) return null;
    final length = wallLength(wall) ?? _polylineLength(points);
    if (!length.isFinite || length <= 1e-9) return null;
    final target = offsetMeters.clamp(0.0, length).toDouble();
    var accumulated = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      final start = points[index - 1];
      final end = points[index];
      final segmentLength = start.distanceTo(end);
      if (segmentLength <= 1e-9) continue;
      if (target <= accumulated + segmentLength || index == points.length - 1) {
        final fraction =
            ((target - accumulated) / segmentLength).clamp(0.0, 1.0);
        return start + (end - start).scale(fraction);
      }
      accumulated += segmentLength;
    }
    return points.last;
  }

  /// Returns a normalized plan tangent at a wall centerline offset.
  static RenderScenePoint? wallTangentAtOffset(
    RenderSceneObject wall,
    double offsetMeters,
  ) {
    final length = wallLength(wall);
    if (length == null || !length.isFinite || length <= 1e-9) return null;
    final before = wallPointAtOffset(wall, offsetMeters - 0.02);
    final after = wallPointAtOffset(wall, offsetMeters + 0.02);
    if (before == null || after == null) return null;
    final tangent = after - before;
    final tangentLength = tangent.distanceTo(RenderScenePoint.zero());
    if (!tangentLength.isFinite || tangentLength <= 1e-9) return null;
    return tangent.scale(1.0 / tangentLength);
  }

  /// Resolves a hosted opening from the architectural 2D symbol, not only
  /// from the small 3D panel bounds.  Door swings and window glazing lines
  /// are plan graphics, so a plan tap can legitimately land outside the
  /// opening mesh while still being clearly on that opening.
  static RenderSceneObject? openingAtPlanPoint(
    RenderScene scene,
    RenderScenePoint point, {
    double toleranceMeters = 0.45,
  }) {
    RenderSceneObject? best;
    var bestDistance = double.infinity;
    for (final opening in scene.objects) {
      if (opening.kindKey != 'door' && opening.kindKey != 'window') {
        continue;
      }
      final hostId = int.tryParse(
        opening.metadata['host_wall_id']?.toString() ?? '',
      );
      final host = scene.objectById(hostId);
      if (host == null || host.kindKey != 'wall') {
        continue;
      }
      final hostGeometry = _wallGeometry(host);
      final openingStart = RenderScenePoint.fromJson(
        opening.metadata['axis_start'] ?? opening.metadata['axisStart'],
      );
      final openingEnd = RenderScenePoint.fromJson(
        opening.metadata['axis_end'] ?? opening.metadata['axisEnd'],
      );
      final openingPanelThickness =
          _toDouble(opening.metadata['panel_thickness_meters']) ??
              _toDouble(opening.metadata['panelThicknessMeters']);
      final resolvedThickness = hostGeometry?.thickness ??
          (openingPanelThickness == null
              ? null
              : math.max(openingPanelThickness * 2.0, 0.08));
      // Legacy fallback walls may expose only miter-expanded bounds. Hosted
      // openings retain the authored axis, so prefer it for straight walls;
      // curved walls keep the host centerline because endpoints alone lose
      // the arc path needed by the symbol picker.
      final geometry = hostGeometry?.isCurved == true ||
              openingStart == null ||
              openingEnd == null ||
              resolvedThickness == null
          ? hostGeometry
          : _WallGeometry(
              start: openingStart,
              end: openingEnd,
              thickness: resolvedThickness,
              centerline:
                  hostGeometry?.centerline ?? const <RenderScenePoint>[],
            );
      final offset = _toDouble(opening.metadata['offset_meters']);
      final width = _toDouble(opening.metadata['width_meters']);
      if (geometry == null ||
          offset == null ||
          width == null ||
          !offset.isFinite ||
          !width.isFinite ||
          width <= 1e-9) {
        continue;
      }

      final clampedOffset = offset.clamp(0.0, geometry.length);
      final halfWidth = width * 0.5;
      final first = _pointAlongWall(
        geometry,
        clampedOffset - halfWidth,
      );
      final second = _pointAlongWall(
        geometry,
        clampedOffset + halfWidth,
      );
      final tangent = _wallTangentAtOffset(geometry, clampedOffset);
      final normal = RenderScenePoint(x: -tangent.y, y: tangent.x, z: 0);
      final halfThickness = (geometry.thickness * 0.5).clamp(0.04, 0.30);

      final distances = <double>[
        _distanceToPlanSegment(point, first, second),
        _distanceToPlanSegment(
          point,
          first + normal.scale(halfThickness),
          first - normal.scale(halfThickness),
        ),
        _distanceToPlanSegment(
          point,
          second + normal.scale(halfThickness),
          second - normal.scale(halfThickness),
        ),
      ];

      if (opening.kindKey == 'window') {
        final glassOffset = halfThickness * 0.70;
        distances
          ..add(_distanceToPlanSegment(
            point,
            first + normal.scale(glassOffset),
            second + normal.scale(glassOffset),
          ))
          ..add(_distanceToPlanSegment(
            point,
            first - normal.scale(glassOffset),
            second - normal.scale(glassOffset),
          ));
      } else {
        // Match the fallback painter's simple door symbol: a leaf from the
        // near jamb and a circular swing centered on that jamb.
        final openEnd = first + normal.scale(width);
        distances.add(_distanceToPlanSegment(point, first, openEnd));
        final startAngle = math.atan2(
          second.y - first.y,
          second.x - first.x,
        );
        final endAngle = math.atan2(
          openEnd.y - first.y,
          openEnd.x - first.x,
        );
        var sweep = endAngle - startAngle;
        while (sweep > math.pi) {
          sweep -= math.pi * 2.0;
        }
        while (sweep < -math.pi) {
          sweep += math.pi * 2.0;
        }
        var previous = second;
        for (var index = 1; index <= 16; index += 1) {
          final angle = startAngle + sweep * (index / 16.0);
          final current = first +
              RenderScenePoint(
                x: math.cos(angle) * width,
                y: math.sin(angle) * width,
                z: 0,
              );
          distances.add(_distanceToPlanSegment(point, previous, current));
          previous = current;
        }
      }

      final distance = distances.reduce(math.min);
      final hitTolerance = math.max(toleranceMeters, 0.18);
      if (distance <= hitTolerance && distance < bestDistance) {
        bestDistance = distance;
        best = opening;
      }
    }
    return best;
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

  static double _polylineLength(List<RenderScenePoint> points) {
    var length = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      length += points[index - 1].distanceTo(points[index]);
    }
    return length;
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
    final segments = <({
      RenderScenePoint start,
      RenderScenePoint end,
      List<RenderScenePoint> path,
    })>[];
    for (final wall in walls) {
      if (wall.kindKey != 'wall') {
        continue;
      }
      final start = wallStartPoint(wall);
      final end = wallEndPoint(wall);
      if (start == null || end == null || start.distanceTo(end) <= 1e-6) {
        continue;
      }
      final centerline = wallCenterlinePoints(wall);
      final path = centerline.length >= 2
          ? List<RenderScenePoint>.from(centerline)
          : <RenderScenePoint>[start, end];
      // The axis endpoints are authoritative for joins. Metadata from an
      // older scene may have been rounded independently, so pin the sampled
      // curve to the same endpoints used by the loop tracer.
      path[0] = start;
      path[path.length - 1] = end;
      segments.add((
        start: start,
        end: end,
        path: List<RenderScenePoint>.unmodifiable(path),
      ));
    }
    if (segments.length < 3) {
      return null;
    }

    List<RenderScenePoint>? traceFrom(bool reverseFirst) {
      final first = segments.first;
      final oriented = <({
        RenderScenePoint start,
        RenderScenePoint end,
        List<RenderScenePoint> path,
      })>[
        reverseFirst
            ? (
                start: first.end,
                end: first.start,
                path: first.path.reversed.toList(growable: false),
              )
            : (
                start: first.start,
                end: first.end,
                path: first.path,
              ),
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
              ? (
                  start: segment.end,
                  end: segment.start,
                  path: segment.path.reversed.toList(growable: false),
                )
              : (
                  start: segment.start,
                  end: segment.end,
                  path: segment.path,
                ),
        );
        used[bestIndex] = true;
      }

      if (_planDistance2(oriented.last.end, oriented.first.start) >
          toleranceMeters) {
        return null;
      }

      // A curved wall is one semantic edge, not a chain of authored walls.
      // Keep its sampled centerline in the floor/ceiling footprint so the
      // horizontal surface follows the arc instead of closing it with the
      // wall's endpoint chord. Straight-only loops retain the established
      // mitered-corner path below.
      if (oriented.any((segment) => segment.path.length > 2)) {
        final curvedPolygon = <RenderScenePoint>[];
        for (final segment in oriented) {
          for (var pathIndex = 0;
              pathIndex < segment.path.length;
              pathIndex += 1) {
            final point = segment.path[pathIndex];
            if (curvedPolygon.isNotEmpty &&
                pathIndex == 0 &&
                _samePlanPoint(curvedPolygon.last, point, toleranceMeters)) {
              continue;
            }
            curvedPolygon.add(point);
          }
        }
        if (curvedPolygon.length > 1 &&
            _samePlanPoint(
              curvedPolygon.first,
              curvedPolygon.last,
              toleranceMeters,
            )) {
          curvedPolygon.removeLast();
        }
        if (curvedPolygon.length < 3 ||
            _polygonArea2d(curvedPolygon).abs() <= 1e-6) {
          return null;
        }
        return curvedPolygon;
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

  static RenderScene setCurvedWallGeometry({
    required RenderScene scene,
    required RenderSceneObject wall,
    required WallArcGeometry geometry,
  }) {
    if (wall.kindKey != 'wall' ||
        wall.elementId == null ||
        wallArcGeometry(wall) == null ||
        !geometry.start.isFinite ||
        !geometry.end.isFinite ||
        !geometry.center.isFinite ||
        !geometry.radiusMeters.isFinite ||
        geometry.radiusMeters <= 1e-6 ||
        !geometry.sweepRadians.isFinite ||
        geometry.sweepRadians.abs() <= 1e-6 ||
        geometry.sweepRadians.abs() > 2.0 * math.pi + 1e-6) {
      return scene;
    }

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final wallId = wall.elementId!;
    final startAngle = math.atan2(
      geometry.start.y - geometry.center.y,
      geometry.start.x - geometry.center.x,
    );
    for (var index = 0; index < objects.length; index += 1) {
      final objectId = _toInt(objects[index]['element_id']) ??
          _toInt(objects[index]['elementId']);
      final kind = (objects[index]['kind']?.toString() ?? '').toLowerCase();
      if (objectId != wallId || kind != 'wall') continue;
      final metadata = objects[index]['metadata'] is Map
          ? Map<String, Object?>.from(
              (objects[index]['metadata'] as Map).cast<String, Object?>(),
            )
          : <String, Object?>{};
      final bounds = RenderSceneBounds.fromJson(objects[index]['bounds']);
      final heightMeters = _toDouble(metadata['height_meters']) ??
          (bounds == null ? null : bounds.max.z - bounds.min.z) ??
          RenderSceneEditor.defaultWallHeightMeters;
      final thicknessMeters = _wallGeometryFromMap(objects[index])?.thickness ??
          RenderSceneEditor.defaultWallThicknessMeters;
      final levelId = _toInt(objects[index]['level_id']) ??
          _toInt(objects[index]['levelId']);
      objects[index] = _buildCurvedWallObject(
        elementId: wallId,
        start: geometry.start,
        end: geometry.end,
        center: geometry.center,
        radiusMeters: geometry.radiusMeters,
        startAngleRadians: startAngle,
        sweepRadians: geometry.sweepRadians,
        heightMeters: heightMeters,
        thicknessMeters: thicknessMeters,
        levelId: levelId,
        metadata: metadata,
        revision: _toInt(objects[index]['revision']) ?? 1,
        materialCategory:
            objects[index]['material_category']?.toString() ?? 'structural',
      );
      break;
    }
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ curved wall');
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

double _distanceToPlanSegment(
  RenderScenePoint point,
  RenderScenePoint start,
  RenderScenePoint end,
) {
  final axis = end - start;
  final lengthSquared = axis.x * axis.x + axis.y * axis.y;
  if (lengthSquared <= 1e-12) {
    return point.distanceTo(start);
  }
  final toPoint = point - start;
  final t = ((toPoint.x * axis.x) + (toPoint.y * axis.y)) / lengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  final projected = start + axis.scale(clamped);
  return point.distanceTo(projected);
}
