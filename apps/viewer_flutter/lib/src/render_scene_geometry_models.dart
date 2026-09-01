part of 'render_scene_models.dart';

@immutable
class RenderScenePoint {
  const RenderScenePoint({
    required this.x,
    required this.y,
    required this.z,
  });

  final double x;
  final double y;
  final double z;

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y, 'z': z};

  static RenderScenePoint zero() => const RenderScenePoint(x: 0, y: 0, z: 0);

  static RenderScenePoint? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x = _toFiniteDouble(value['x']);
    final y = _toFiniteDouble(value['y']);
    final z = _toFiniteDouble(value['z']);
    if (x == null || y == null || z == null) {
      return null;
    }
    return RenderScenePoint(x: x, y: y, z: z);
  }

  RenderScenePoint operator +(RenderScenePoint other) {
    return RenderScenePoint(x: x + other.x, y: y + other.y, z: z + other.z);
  }

  RenderScenePoint operator -(RenderScenePoint other) {
    return RenderScenePoint(x: x - other.x, y: y - other.y, z: z - other.z);
  }

  RenderScenePoint scale(double factor) {
    return RenderScenePoint(x: x * factor, y: y * factor, z: z * factor);
  }

  double distanceTo(RenderScenePoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

/// A semantic visual segment authored by the BIM engine. Viewports may project
/// it, but must not recreate opening contours by inspecting mesh triangles.
@immutable
class RenderSceneFeatureEdge {
  const RenderSceneFeatureEdge({
    required this.start,
    required this.end,
    required this.role,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
  final String role;

  bool get isFinite => start.isFinite && end.isFinite;

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role,
        'start': start.toJson(),
        'end': end.toJson(),
      };

  static RenderSceneFeatureEdge? fromJson(Object? value) {
    if (value is! Map) return null;
    final start = RenderScenePoint.fromJson(value['start']);
    final end = RenderScenePoint.fromJson(value['end']);
    if (start == null || end == null) return null;
    return RenderSceneFeatureEdge(
      start: start,
      end: end,
      role: toSceneString(value['role'], fallback: 'silhouette'),
    );
  }
}

@immutable
class RenderSceneBounds {
  const RenderSceneBounds({
    required this.min,
    required this.max,
  });

  final RenderScenePoint min;
  final RenderScenePoint max;

  RenderScenePoint get center => RenderScenePoint(
        x: (min.x + max.x) * 0.5,
        y: (min.y + max.y) * 0.5,
        z: (min.z + max.z) * 0.5,
      );

  double get width => (max.x - min.x).abs();
  double get depth => (max.y - min.y).abs();
  double get height => (max.z - min.z).abs();

  bool get isFinite => <double>[
        min.x,
        min.y,
        min.z,
        max.x,
        max.y,
        max.z,
      ].every((value) => value.isFinite);

  Map<String, Object?> toJson() => <String, Object?>{
        'min': min.toJson(),
        'max': max.toJson(),
      };

  static RenderSceneBounds zero() => RenderSceneBounds(
        min: RenderScenePoint.zero(),
        max: RenderScenePoint.zero(),
      );

  static RenderSceneBounds normalized({
    required RenderScenePoint min,
    required RenderScenePoint max,
  }) {
    return RenderSceneBounds(
      min: RenderScenePoint(
        x: min.x <= max.x ? min.x : max.x,
        y: min.y <= max.y ? min.y : max.y,
        z: min.z <= max.z ? min.z : max.z,
      ),
      max: RenderScenePoint(
        x: min.x >= max.x ? min.x : max.x,
        y: min.y >= max.y ? min.y : max.y,
        z: min.z >= max.z ? min.z : max.z,
      ),
    );
  }

  static RenderSceneBounds? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final min = RenderScenePoint.fromJson(value['min']);
    final max = RenderScenePoint.fromJson(value['max']);
    if (min == null || max == null) {
      return null;
    }
    return RenderSceneBounds(min: min, max: max);
  }

  RenderSceneBounds include(RenderScenePoint point) {
    final minX = point.x < min.x ? point.x : min.x;
    final minY = point.y < min.y ? point.y : min.y;
    final minZ = point.z < min.z ? point.z : min.z;
    final maxX = point.x > max.x ? point.x : max.x;
    final maxY = point.y > max.y ? point.y : max.y;
    final maxZ = point.z > max.z ? point.z : max.z;
    return RenderSceneBounds(
      min: RenderScenePoint(x: minX, y: minY, z: minZ),
      max: RenderScenePoint(x: maxX, y: maxY, z: maxZ),
    );
  }

  static RenderSceneBounds union(
    Iterable<RenderSceneBounds> bounds, {
    RenderSceneBounds? fallback,
  }) {
    final iterator = bounds.iterator;
    if (!iterator.moveNext()) {
      return fallback ?? zero();
    }
    var current = iterator.current;
    while (iterator.moveNext()) {
      current = current._union(iterator.current);
    }
    return current;
  }

  RenderSceneBounds _union(RenderSceneBounds other) {
    return RenderSceneBounds(
      min: RenderScenePoint(
        x: min.x < other.min.x ? min.x : other.min.x,
        y: min.y < other.min.y ? min.y : other.min.y,
        z: min.z < other.min.z ? min.z : other.min.z,
      ),
      max: RenderScenePoint(
        x: max.x > other.max.x ? max.x : other.max.x,
        y: max.y > other.max.y ? max.y : other.max.y,
        z: max.z > other.max.z ? max.z : other.max.z,
      ),
    );
  }
}

@immutable
class RenderSceneMesh {
  const RenderSceneMesh({
    required this.positions,
    required this.indices,
    required this.normals,
    this.triangleMaterialIds = const <int>[],
    this.invalidIndexCount = 0,
  });

  final List<RenderScenePoint> positions;
  final List<int> indices;
  final List<RenderScenePoint>? normals;
  final List<int> triangleMaterialIds;
  final int invalidIndexCount;

  int get triangleCount => indices.length ~/ 3;

  bool get hasGeometry => positions.isNotEmpty && indices.length >= 3;

  Map<String, Object?> toJson() => <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': indices,
        if (triangleMaterialIds.isNotEmpty)
          'triangle_material_ids': triangleMaterialIds,
        if (invalidIndexCount > 0) 'invalid_index_count': invalidIndexCount,
        if (normals != null)
          'normals': normals!.map((point) => point.toJson()).toList(),
      };

  static RenderSceneMesh empty() => const RenderSceneMesh(
        positions: <RenderScenePoint>[],
        indices: <int>[],
        normals: null,
        triangleMaterialIds: <int>[],
        invalidIndexCount: 0,
      );

  static RenderSceneMesh fromJson(Object? value, List<String> warnings) {
    if (value is! Map) {
      warnings.add('Mesh payload is missing or invalid.');
      return RenderSceneMesh.empty();
    }
    final positions = <RenderScenePoint>[];
    final rawPositions = value['positions'];
    if (rawPositions is List) {
      for (final entry in rawPositions) {
        final point = RenderScenePoint.fromJson(entry);
        if (point != null) {
          positions.add(point);
        }
      }
    } else {
      warnings.add('Mesh positions were missing.');
    }

    final indices = <int>[];
    var invalidIndexCount = 0;
    final rawIndices = value['indices'];
    if (rawIndices is List) {
      for (final entry in rawIndices) {
        final parsed = _toFiniteDouble(entry);
        if (parsed != null) {
          indices.add(parsed.floor());
        } else {
          invalidIndexCount += 1;
        }
      }
    } else {
      warnings.add('Mesh indices were missing.');
    }

    List<RenderScenePoint>? normals;
    final rawNormals = value['normals'];
    if (rawNormals is List) {
      final parsedNormals = <RenderScenePoint>[];
      for (final entry in rawNormals) {
        final point = RenderScenePoint.fromJson(entry);
        if (point != null) {
          parsedNormals.add(point);
        }
      }
      normals = parsedNormals.isEmpty ? null : parsedNormals;
    }
    final triangleMaterialIds = <int>[];
    final rawMaterialIds = value['triangle_material_ids'];
    if (rawMaterialIds is List) {
      for (final entry in rawMaterialIds) {
        final parsed = _toFiniteDouble(entry);
        if (parsed != null) {
          triangleMaterialIds.add(parsed.floor());
        }
      }
    }
    return RenderSceneMesh(
      positions: positions,
      indices: indices,
      normals: normals,
      triangleMaterialIds: triangleMaterialIds,
      invalidIndexCount: invalidIndexCount,
    );
  }
}
