part of 'render_scene_editor.dart';

void _rebuildDetectedRooms(List<Map<String, Object?>> objects) {
  objects.removeWhere(
    (object) => (object['kind']?.toString() ?? '').toLowerCase() == 'room',
  );

  final wallsByLevel = <int?, List<_WallEntry>>{};
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
    final metadataMap =
        object['metadata'] is Map ? object['metadata'] as Map : null;
    final boundsMap = object['bounds'] is Map ? object['bounds'] as Map : null;
    Map? boundsMax;
    final rawBoundsMax = boundsMap == null ? null : boundsMap['max'];
    if (rawBoundsMax is Map) {
      boundsMax = rawBoundsMax;
    }
    final heightMeters = _toDouble(metadataMap?['height_meters']) ??
        _toDouble(boundsMax?['z']) ??
        RenderSceneEditor.defaultWallHeightMeters;
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

    // Flood fill needs a real exterior cell. With only the wall-axis
    // coordinates, a simple four-wall room consists of one boundary cell
    // and was incorrectly seeded as "outside". Add a cheap envelope around
    // the storey so closed cells remain enclosed and open cells still leak
    // to the exterior through missing walls.
    final xPadding = math.max(1.0, (xs.last - xs.first).abs() * 0.05);
    final yPadding = math.max(1.0, (ys.last - ys.first).abs() * 0.05);
    xs
      ..insert(0, xs.first - xPadding)
      ..add(xs.last + xPadding);
    ys
      ..insert(0, ys.first - yPadding)
      ..add(ys.last + yPadding);

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
            _blockingWallsVertical(walls, xs[i + 1], ys[j], ys[j + 1])
                .isNotEmpty,
          );
          tryRoom(
            i,
            j - 1,
            _blockingWallsHorizontal(walls, ys[j], xs[i], xs[i + 1]).isNotEmpty,
          );
          tryRoom(
            i,
            j + 1,
            _blockingWallsHorizontal(walls, ys[j + 1], xs[i], xs[i + 1])
                .isNotEmpty,
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

Map<String, Object?>? _buildRoomObjectFromCells({
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
  final boundaryPolygon = _roomBoundaryPolygonFromCells(cells, xs, ys)
      .map((point) => RenderScenePoint(x: point.x, y: point.y, z: baseZ))
      .toList(growable: false);
  if (boundaryPolygon.length < 3) {
    return null;
  }
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
      'boundary_polygon':
          boundaryPolygon.map((point) => point.toJson()).toList(),
      'cell_count': cells.length,
      'level_locked': true,
    },
  };
}

List<RenderScenePoint> _roomBoundaryPolygonFromCells(
  List<_GridCell> cells,
  List<double> xs,
  List<double> ys,
) {
  final edges = <String, ({int si, int sj, int ei, int ej})>{};
  String key(int si, int sj, int ei, int ej) => '$si:$sj>$ei:$ej';
  void addEdge(int si, int sj, int ei, int ej) {
    final reverse = key(ei, ej, si, sj);
    if (edges.remove(reverse) != null) return;
    edges[key(si, sj, ei, ej)] = (si: si, sj: sj, ei: ei, ej: ej);
  }

  for (final cell in cells) {
    addEdge(cell.i, cell.j, cell.i + 1, cell.j);
    addEdge(cell.i + 1, cell.j, cell.i + 1, cell.j + 1);
    addEdge(cell.i + 1, cell.j + 1, cell.i, cell.j + 1);
    addEdge(cell.i, cell.j + 1, cell.i, cell.j);
  }
  if (edges.length < 3) return const <RenderScenePoint>[];

  final byStart = <String, List<({int si, int sj, int ei, int ej})>>{};
  for (final edge in edges.values) {
    byStart.putIfAbsent('${edge.si}:${edge.sj}', () => []).add(edge);
  }
  final start = edges.values.reduce((left, right) {
    if (right.sj != left.sj) return right.sj < left.sj ? right : left;
    return right.si < left.si ? right : left;
  });
  final polygon = <RenderScenePoint>[];
  var current = start;
  final visited = <String>{};
  while (visited.length < edges.length) {
    final currentKey = key(current.si, current.sj, current.ei, current.ej);
    if (!visited.add(currentKey)) break;
    polygon.add(RenderScenePoint(
      x: xs[current.si],
      y: ys[current.sj],
      z: 0,
    ));
    if (current.ei == start.si && current.ej == start.sj) break;
    final candidates = byStart['${current.ei}:${current.ej}'];
    if (candidates == null) return const <RenderScenePoint>[];
    ({int si, int sj, int ei, int ej})? next;
    for (final candidate in candidates) {
      if (!visited.contains(
          key(candidate.si, candidate.sj, candidate.ei, candidate.ej))) {
        next = candidate;
        break;
      }
    }
    if (next == null) return const <RenderScenePoint>[];
    current = next;
  }

  final simplified = <RenderScenePoint>[];
  for (var index = 0; index < polygon.length; index += 1) {
    final previous = polygon[(index - 1 + polygon.length) % polygon.length];
    final point = polygon[index];
    final next = polygon[(index + 1) % polygon.length];
    final cross = (point.x - previous.x) * (next.y - point.y) -
        (point.y - previous.y) * (next.x - point.x);
    if (cross.abs() > 1e-9) simplified.add(point);
  }
  return simplified;
}

bool _pointInPlanPolygon(
  RenderScenePoint point,
  List<RenderScenePoint> polygon,
) {
  var inside = false;
  for (var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++) {
    final a = polygon[index];
    final b = polygon[previous];
    final crosses = (a.y > point.y) != (b.y > point.y);
    if (crosses &&
        point.x <
            (b.x - a.x) *
                    (point.y - a.y) /
                    ((b.y - a.y).abs() <= 1e-12 ? 1e-12 : b.y - a.y) +
                a.x) {
      inside = !inside;
    }
  }
  return inside;
}
