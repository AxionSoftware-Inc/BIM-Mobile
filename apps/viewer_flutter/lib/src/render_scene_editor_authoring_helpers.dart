part of 'render_scene_editor.dart';

void _shiftObjectZInPlace(Map<String, Object?> object, double delta) {
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

List<int> _blockingWallsVertical(
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

List<int> _blockingWallsHorizontal(
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

_ResolvedOpeningSpec? _resolveOpeningSpec({
  required Map<String, Object?> openingObject,
  required List<_WallEntry> allWalls,
}) {
  final metadata = openingObject['metadata'] is Map
      ? openingObject['metadata'] as Map
      : null;
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

_WallEntry? _deriveHostWallForOpening(
  RenderScenePoint center,
  RenderSceneBounds openingBounds,
  List<_WallEntry> allWalls,
) {
  _WallEntry? bestWall;
  var bestDistance = double.infinity;
  for (final wall in allWalls) {
    final offset = _projectOffsetAlongWall(wall.geometry, center);
    if (offset == null ||
        offset < -1e-6 ||
        offset > wall.geometry.length + 1e-6) {
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

_WallEntry? _wallEntryById(List<_WallEntry> walls, int objectId) {
  for (final wall in walls) {
    if (wall.objectId == objectId) {
      return wall;
    }
  }
  return null;
}

double? _projectOffsetAlongWall(
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

RenderScenePoint _pointAlongWall(_WallGeometry wall, double offset) {
  final clamped = offset.clamp(0.0, wall.length);
  final axisUnit = _unit3(wall.end - wall.start);
  return wall.start + axisUnit.scale(clamped);
}

double _openingWidthAlongWall(
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

_BuiltMeshResult _buildWallMeshWithOpenings({
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
            sampleZ > opening.bottomZ + 1e-6 && sampleZ < opening.topZ - 1e-6,
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

_BuiltMeshResult _buildOpeningMesh(_ResolvedOpeningSpec spec) {
  final positions = <RenderScenePoint>[];
  final indices = <int>[];
  final axisUnit =
      _unit3(spec.hostWall.geometry.end - spec.hostWall.geometry.start);
  final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0.0);

  RenderScenePoint worldPoint(double localX, double localY, double localZ) {
    return RenderScenePoint(
      x: spec.hostWall.geometry.start.x +
          axisUnit.x * localX +
          normal.x * localY,
      y: spec.hostWall.geometry.start.y +
          axisUnit.y * localX +
          normal.y * localY,
      z: spec.hostWall.geometry.start.z + localZ,
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
    positions
        .map((point) => RenderSceneBounds.normalized(min: point, max: point)),
  );
  return _BuiltMeshResult(
    mesh: <String, Object?>{
      'positions': positions.map((point) => point.toJson()).toList(),
      'indices': indices,
    },
    bounds: bounds,
  );
}

void _appendBoxMesh({
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
    baseIndex + 0,
    baseIndex + 2,
    baseIndex + 1,
    baseIndex + 0,
    baseIndex + 3,
    baseIndex + 2,
    baseIndex + 4,
    baseIndex + 5,
    baseIndex + 6,
    baseIndex + 4,
    baseIndex + 6,
    baseIndex + 7,
    baseIndex + 0,
    baseIndex + 1,
    baseIndex + 5,
    baseIndex + 0,
    baseIndex + 5,
    baseIndex + 4,
    baseIndex + 1,
    baseIndex + 2,
    baseIndex + 6,
    baseIndex + 1,
    baseIndex + 6,
    baseIndex + 5,
    baseIndex + 2,
    baseIndex + 3,
    baseIndex + 7,
    baseIndex + 2,
    baseIndex + 7,
    baseIndex + 6,
    baseIndex + 3,
    baseIndex + 0,
    baseIndex + 4,
    baseIndex + 3,
    baseIndex + 4,
    baseIndex + 7,
  ]);
}

void _appendExtrudedPolygonMesh({
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

List<RenderScenePoint> _clipPolygonByXRange(
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

List<RenderScenePoint> _clipPolygonMinX(
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

List<RenderScenePoint> _clipPolygonMaxX(
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

RenderScenePoint _intersectAtX(
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

List<RenderScenePoint> _wallProfilePolygon(
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
  double? startMiterExtension;
  double? startMiterTurn;
  double? endMiterExtension;
  double? endMiterTurn;

  for (final other in allWalls) {
    if (other.objectId == wall.objectId) {
      continue;
    }
    final sharedAtStart =
        _samePoint2(wall.geometry.start, other.geometry.start) ||
            _samePoint2(wall.geometry.start, other.geometry.end);
    final sharedAtEnd = _samePoint2(wall.geometry.end, other.geometry.start) ||
        _samePoint2(wall.geometry.end, other.geometry.end);
    if (!sharedAtStart && !sharedAtEnd) {
      continue;
    }

    final joinPoint = sharedAtStart ? wall.geometry.start : wall.geometry.end;
    final otherDirection = _directionAwayFrom(joinPoint, other.geometry);
    final turn = _cross2(direction, otherDirection);
    final cosine = _dot2(direction, otherDirection);
    final denominator = 1.0 + cosine;
    if (turn.abs() <= 1e-9 || denominator <= 1e-9) {
      continue;
    }
    final extension = halfThickness * turn.abs() / denominator;
    // Do not turn a nearly reversed pair of sketch lines into a very long
    // spike while its endpoint is still being edited.
    if (!extension.isFinite || extension > halfThickness * 4.0) {
      continue;
    }

    // One endpoint has one cap.  Keeping the widest valid candidate avoids
    // adding several mitres together when a fan of walls shares a point.
    if (sharedAtEnd) {
      if (endMiterExtension == null || extension > endMiterExtension) {
        endMiterExtension = extension;
        endMiterTurn = turn;
      }
    } else {
      if (startMiterExtension == null || extension > startMiterExtension) {
        startMiterExtension = extension;
        startMiterTurn = turn;
      }
    }
  }

  if (startMiterExtension != null && startMiterTurn != null) {
    final signedExtension =
        startMiterTurn > 0.0 ? startMiterExtension : -startMiterExtension;
    startLowerX -= signedExtension;
    startUpperX += signedExtension;
  }
  if (endMiterExtension != null && endMiterTurn != null) {
    final signedExtension =
        endMiterTurn > 0.0 ? endMiterExtension : -endMiterExtension;
    endLowerX += signedExtension;
    endUpperX -= signedExtension;
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
