part of 'render_scene_editor.dart';

bool _samePoint2(
  RenderScenePoint a,
  RenderScenePoint b, [
  double toleranceMeters = 0.15,
]) {
  // Authoring points come through touch coordinates and JSON round-trips;
  // an exact floating-point comparison leaves visually connected walls as
  // two overlapping solids. Keep the tolerance well below normal wall
  // thickness while allowing endpoint joins to receive their miter profile.
  return (a.x - b.x).abs() <= toleranceMeters &&
      (a.y - b.y).abs() <= toleranceMeters;
}

RenderScenePoint _directionAwayFrom(
  RenderScenePoint joinPoint,
  _WallGeometry wall,
) {
  final startDistance = joinPoint.distanceTo(wall.start);
  final endDistance = joinPoint.distanceTo(wall.end);
  final away = startDistance < endDistance
      ? (wall.end - wall.start)
      : (wall.start - wall.end);
  return _unit2(away);
}

double _cross2(RenderScenePoint a, RenderScenePoint b) {
  return (a.x * b.y) - (a.y * b.x);
}

double _dot2(RenderScenePoint a, RenderScenePoint b) {
  return (a.x * b.x) + (a.y * b.y);
}

RenderScenePoint _unit2(RenderScenePoint vector) {
  final length = math.sqrt((vector.x * vector.x) + (vector.y * vector.y));
  if (length <= 1e-9) {
    return const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0);
  }
  return RenderScenePoint(x: vector.x / length, y: vector.y / length, z: 0.0);
}

RenderScenePoint _unit3(RenderScenePoint vector) {
  final length =
      vector.distanceTo(const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0));
  if (length <= 1e-9) {
    return const RenderScenePoint(x: 0.0, y: 0.0, z: 0.0);
  }
  return RenderScenePoint(
    x: vector.x / length,
    y: vector.y / length,
    z: vector.z / length,
  );
}

List<double> _sortedUniqueBreaks(List<double> values) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  final unique = <double>[];
  for (final value in sorted) {
    if (unique.isEmpty || (value - unique.last).abs() > 1e-6) {
      unique.add(value);
    }
  }
  return unique;
}

_WallGeometry? _wallGeometryFromMap(Map<String, Object?> wallObject) {
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

  // Native EngineApi serializes wall axes as scalar fields. Respecting them
  // is essential whenever a legacy scene needs repair: deriving an axis
  // from a mitered wall's bounds turns diagonal/connected walls into a
  // different, axis-aligned wall.
  final startX = _toDouble(metadataMap?['start_x'] ?? metadataMap?['startX']);
  final startY = _toDouble(metadataMap?['start_y'] ?? metadataMap?['startY']);
  final endX = _toDouble(metadataMap?['end_x'] ?? metadataMap?['endX']);
  final endY = _toDouble(metadataMap?['end_y'] ?? metadataMap?['endY']);
  if (startX != null &&
      startY != null &&
      endX != null &&
      endY != null &&
      thickness != null) {
    return _WallGeometry(
      start: RenderScenePoint(x: startX, y: startY, z: 0.0),
      end: RenderScenePoint(x: endX, y: endY, z: 0.0),
      thickness: thickness,
    );
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
        z: bounds.min.z,
      ),
      end: RenderScenePoint(
        x: bounds.max.x,
        y: (bounds.min.y + bounds.max.y) * 0.5,
        z: bounds.min.z,
      ),
      thickness: depth,
    );
  }

  return _WallGeometry(
    start: RenderScenePoint(
      x: (bounds.min.x + bounds.max.x) * 0.5,
      y: bounds.min.y,
      z: bounds.min.z,
    ),
    end: RenderScenePoint(
      x: (bounds.min.x + bounds.max.x) * 0.5,
      y: bounds.max.y,
      z: bounds.min.z,
    ),
    thickness: width,
  );
}

RenderSceneBounds? _boundsFromMap(Map<String, Object?> object) {
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

List<RenderScenePoint> _boundsCorners(RenderSceneBounds bounds) {
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

_WallGeometry? _wallGeometry(RenderSceneObject wall) {
  final metadata = wall.metadata;
  final axisStart = RenderScenePoint.fromJson(
      metadata['axis_start'] ?? metadata['axisStart']);
  final axisEnd =
      RenderScenePoint.fromJson(metadata['axis_end'] ?? metadata['axisEnd']);
  final thickness =
      _toDouble(metadata['thickness_meters'] ?? metadata['thicknessMeters']);

  if (axisStart != null && axisEnd != null && thickness != null) {
    return _WallGeometry(start: axisStart, end: axisEnd, thickness: thickness);
  }

  // Native EngineApi serializes the axis as scalar string metadata. Keep
  // this path in sync with _wallGeometryFromMap so read-only queries (used by
  // preview, hit testing and the fallback renderer) preserve the authoritative
  // wall direction too.
  final startX = _toDouble(metadata['start_x'] ?? metadata['startX']);
  final startY = _toDouble(metadata['start_y'] ?? metadata['startY']);
  final endX = _toDouble(metadata['end_x'] ?? metadata['endX']);
  final endY = _toDouble(metadata['end_y'] ?? metadata['endY']);
  if (startX != null &&
      startY != null &&
      endX != null &&
      endY != null &&
      thickness != null) {
    return _WallGeometry(
      start: RenderScenePoint(x: startX, y: startY, z: 0.0),
      end: RenderScenePoint(x: endX, y: endY, z: 0.0),
      thickness: thickness,
    );
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

RenderScenePoint _projectPointToSegment(
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

double _dot(RenderScenePoint a, RenderScenePoint b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

double? _toDouble(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  // Native RenderScene metadata is transported as a string map.  Keeping
  // only numeric JSON values here silently drops the authoritative wall axis
  // (`start_x/start_y/end_x/end_y`) and falls back to bounds, which reverses
  // walls whose stored direction is end-to-start.  That makes a left-side
  // opening preview commit on the right side in the native engine.
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

int? _toInt(Object? value) {
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
