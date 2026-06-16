import 'dart:convert';

import 'package:flutter/foundation.dart';

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
}

@immutable
class RenderSceneBounds {
  const RenderSceneBounds({
    required this.min,
    required this.max,
  });

  final RenderScenePoint min;
  final RenderScenePoint max;

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
  });

  final List<RenderScenePoint> positions;
  final List<int> indices;
  final List<RenderScenePoint>? normals;

  int get triangleCount => indices.length ~/ 3;

  bool get hasGeometry => positions.isNotEmpty && indices.length >= 3;

  Map<String, Object?> toJson() => <String, Object?>{
        'positions': positions.map((point) => point.toJson()).toList(),
        'indices': indices,
        if (normals != null)
          'normals': normals!.map((point) => point.toJson()).toList(),
      };

  static RenderSceneMesh empty() => const RenderSceneMesh(
        positions: <RenderScenePoint>[],
        indices: <int>[],
        normals: null,
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
    final rawIndices = value['indices'];
    if (rawIndices is List) {
      for (final entry in rawIndices) {
        final parsed = _toFiniteDouble(entry);
        if (parsed != null) {
          indices.add(parsed.floor());
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
    return RenderSceneMesh(
      positions: positions,
      indices: indices,
      normals: normals,
    );
  }
}

@immutable
class RenderSceneObject {
  const RenderSceneObject({
    required this.elementId,
    required this.kind,
    required this.levelId,
    required this.selectable,
    required this.visibleByDefault,
    required this.revision,
    required this.bounds,
    required this.mesh,
    required this.materialCategory,
  });

  final int? elementId;
  final String kind;
  final int? levelId;
  final bool selectable;
  final bool visibleByDefault;
  final int revision;
  final RenderSceneBounds bounds;
  final RenderSceneMesh mesh;
  final String materialCategory;

  String get kindKey => normalizeSceneKind(kind);

  Map<String, Object?> toJson() => <String, Object?>{
        if (elementId != null) 'element_id': elementId,
        'kind': kind,
        if (levelId != null) 'level_id': levelId,
        'selectable': selectable,
        'visible_by_default': visibleByDefault,
        'revision': revision,
        'bounds': bounds.toJson(),
        'mesh': mesh.toJson(),
        'material_category': materialCategory,
      };

  static RenderSceneObject fromJson(
    Object? value,
    List<String> warnings,
    List<String> errors,
  ) {
    if (value is! Map) {
      errors.add('Encountered a malformed render object.');
      return RenderSceneObject(
        elementId: null,
        kind: 'Unknown',
        levelId: null,
        selectable: false,
        visibleByDefault: false,
        revision: 0,
        bounds: RenderSceneBounds(
          min: RenderScenePoint.zero(),
          max: RenderScenePoint.zero(),
        ),
        mesh: RenderSceneMesh.empty(),
        materialCategory: 'generic',
      );
    }
    final mesh = RenderSceneMesh.fromJson(value['mesh'], warnings);
    final explicitBounds = RenderSceneBounds.fromJson(value['bounds']);
    final derivedBounds = _boundsFromPositions(mesh.positions);
    final bounds = explicitBounds ?? derivedBounds;
    if (explicitBounds == null && mesh.positions.isEmpty) {
      warnings.add(
          'Render object ${value['kind'] ?? 'Unknown'} has no valid bounds or mesh.');
    }
    if (!bounds.isFinite) {
      warnings.add(
          'Render object ${value['kind'] ?? 'Unknown'} has non-finite bounds; zeroing them.');
    }
    return RenderSceneObject(
      elementId: _toNullableInt(value['element_id']),
      kind: toSceneString(value['kind'], fallback: 'Unknown'),
      levelId: _toNullableInt(value['level_id']),
      selectable: value['selectable'] != false,
      visibleByDefault: value['visible_by_default'] != false,
      revision: _toNullableInt(value['revision']) ?? 0,
      bounds: bounds.isFinite ? bounds : RenderSceneBounds.zero(),
      mesh: mesh,
      materialCategory:
          toSceneString(value['material_category'], fallback: 'generic'),
    );
  }
}

@immutable
class RenderSceneDiagnostics {
  const RenderSceneDiagnostics({
    required this.source,
    required this.objectCount,
    required this.selectableObjectCount,
    required this.visibleObjectCount,
    required this.vertexCount,
    required this.indexCount,
    required this.triangleCount,
    required this.levelCount,
    required this.missingGeometryCount,
    required this.invalidBoundsCount,
    required this.kindCounts,
    required this.warnings,
    required this.errors,
  });

  final String source;
  final int objectCount;
  final int selectableObjectCount;
  final int visibleObjectCount;
  final int vertexCount;
  final int indexCount;
  final int triangleCount;
  final int levelCount;
  final int missingGeometryCount;
  final int invalidBoundsCount;
  final Map<String, int> kindCounts;
  final List<String> warnings;
  final List<String> errors;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source,
        'objectCount': objectCount,
        'selectableObjectCount': selectableObjectCount,
        'visibleObjectCount': visibleObjectCount,
        'vertexCount': vertexCount,
        'indexCount': indexCount,
        'triangleCount': triangleCount,
        'levelCount': levelCount,
        'missingGeometryCount': missingGeometryCount,
        'invalidBoundsCount': invalidBoundsCount,
        'kindCounts': kindCounts,
        'warnings': warnings,
        'errors': errors,
      };
}

@immutable
class RenderScene {
  const RenderScene({
    required this.sceneVersion,
    required this.units,
    required this.coordinateSystem,
    required this.objectCount,
    required this.vertexCount,
    required this.indexCount,
    required this.bounds,
    required this.objects,
    required this.source,
    required this.diagnostics,
  });

  final int sceneVersion;
  final String units;
  final String coordinateSystem;
  final int objectCount;
  final int vertexCount;
  final int indexCount;
  final RenderSceneBounds bounds;
  final List<RenderSceneObject> objects;
  final String source;
  final RenderSceneDiagnostics diagnostics;

  int get triangleCount => indexCount ~/ 3;

  Map<String, int> get kindCounts => diagnostics.kindCounts;

  List<RenderSceneObject> objectsForKinds(Set<String> visibleKinds) {
    if (visibleKinds.isEmpty) {
      return objects;
    }
    return objects
        .where((object) => visibleKinds.contains(object.kindKey))
        .toList();
  }

  RenderSceneObject? objectById(int? elementId) {
    if (elementId == null) {
      return null;
    }
    for (final object in objects) {
      if (object.elementId == elementId) {
        return object;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'scene_version': sceneVersion,
        'units': units,
        'coordinate_system': coordinateSystem,
        'object_count': objectCount,
        'vertex_count': vertexCount,
        'index_count': indexCount,
        'bounds': bounds.toJson(),
        'objects': objects.map((object) => object.toJson()).toList(),
      };
}

@immutable
class RenderSceneLoadResult {
  const RenderSceneLoadResult({
    required this.scene,
    required this.warnings,
    required this.errors,
  });

  final RenderScene? scene;
  final List<String> warnings;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty || scene == null;
}

RenderSceneLoadResult parseRenderSceneJson(
  String text, {
  String source = 'render_scene.json',
}) {
  final warnings = <String>[];
  final errors = <String>[];
  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (error) {
    return RenderSceneLoadResult(
      scene: null,
      warnings: const <String>[],
      errors: <String>['Unable to parse RenderScene JSON from $source: $error'],
    );
  }
  if (decoded is! Map) {
    return RenderSceneLoadResult(
      scene: null,
      warnings: warnings,
      errors: <String>[
        'RenderScene payload from $source must be a JSON object.'
      ],
    );
  }

  final rawObjects = decoded['objects'];
  final objects = <RenderSceneObject>[];
  if (rawObjects is List) {
    for (final entry in rawObjects) {
      objects.add(RenderSceneObject.fromJson(entry, warnings, errors));
    }
  } else {
    warnings.add('RenderScene payload from $source had no object list.');
  }

  final derivedBounds = RenderSceneBounds.union(
    objects.map((object) => object.bounds),
    fallback: RenderSceneBounds.zero(),
  );
  final kindCounts = <String, int>{};
  var selectableObjectCount = 0;
  var visibleObjectCount = 0;
  var missingGeometryCount = 0;
  var invalidBoundsCount = 0;
  final levelIds = <int>{};
  var vertexCount = 0;
  var indexCount = 0;
  for (final object in objects) {
    kindCounts[object.kindKey] = (kindCounts[object.kindKey] ?? 0) + 1;
    if (object.selectable) {
      selectableObjectCount += 1;
    }
    if (object.visibleByDefault) {
      visibleObjectCount += 1;
    }
    if (!object.mesh.hasGeometry) {
      missingGeometryCount += 1;
    }
    if (!object.bounds.isFinite) {
      invalidBoundsCount += 1;
    }
    if (object.levelId != null) {
      levelIds.add(object.levelId!);
    }
    vertexCount += object.mesh.positions.length;
    indexCount += object.mesh.indices.length;
  }

  final sceneVersion = _toNullableInt(decoded['scene_version']) ??
      _toNullableInt(decoded['sceneVersion']) ??
      1;
  final objectCount = _toNullableInt(decoded['object_count']) ??
      _toNullableInt(decoded['objectCount']) ??
      objects.length;
  final rawVertexCount = _toNullableInt(decoded['vertex_count']) ??
      _toNullableInt(decoded['vertexCount']) ??
      vertexCount;
  final rawIndexCount = _toNullableInt(decoded['index_count']) ??
      _toNullableInt(decoded['indexCount']) ??
      indexCount;
  final units = toSceneString(decoded['units'], fallback: 'meters');
  final coordinateSystem = toSceneString(
    decoded['coordinate_system'] ?? decoded['coordinateSystem'],
    fallback: 'X/Y plan, Z up',
  );

  if (objectCount != objects.length) {
    warnings.add(
      'Scene object_count header ($objectCount) differs from parsed object count (${objects.length}) in $source.',
    );
  }
  if (rawVertexCount != vertexCount) {
    warnings.add(
      'Scene vertex_count header ($rawVertexCount) differs from derived vertex count ($vertexCount) in $source.',
    );
  }
  if (rawIndexCount != indexCount) {
    warnings.add(
      'Scene index_count header ($rawIndexCount) differs from derived index count ($indexCount) in $source.',
    );
  }

  final diagnostics = RenderSceneDiagnostics(
    source: source,
    objectCount: objects.length,
    selectableObjectCount: selectableObjectCount,
    visibleObjectCount: visibleObjectCount,
    vertexCount: vertexCount,
    indexCount: indexCount,
    triangleCount: indexCount ~/ 3,
    levelCount: levelIds.length,
    missingGeometryCount: missingGeometryCount,
    invalidBoundsCount: invalidBoundsCount,
    kindCounts: kindCounts,
    warnings: warnings,
    errors: errors,
  );

  return RenderSceneLoadResult(
    scene: RenderScene(
      sceneVersion: sceneVersion,
      units: units,
      coordinateSystem: coordinateSystem,
      objectCount: objects.length,
      vertexCount: vertexCount,
      indexCount: indexCount,
      bounds: derivedBounds,
      objects: objects,
      source: source,
      diagnostics: diagnostics,
    ),
    warnings: warnings,
    errors: errors,
  );
}

String normalizeSceneKind(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return 'unknown';
  }
  if (trimmed == 'floorsystem') {
    return 'floor';
  }
  if (trimmed == 'ceilingsystem') {
    return 'ceiling';
  }
  if (trimmed == 'opening') {
    return 'door';
  }
  return trimmed;
}

String prettySceneKind(String value) {
  final normalized = normalizeSceneKind(value);
  switch (normalized) {
    case 'wall':
      return 'Wall';
    case 'door':
      return 'Door';
    case 'window':
      return 'Window';
    case 'slab':
      return 'Slab';
    case 'floor':
      return 'Floor';
    case 'ceiling':
      return 'Ceiling';
    case 'roof':
      return 'Roof';
    case 'column':
      return 'Column';
    case 'beam':
      return 'Beam';
    case 'stair':
      return 'Stair';
    case 'room':
      return 'Room';
    default:
      return value.isEmpty ? 'Unknown' : value;
  }
}

String toSceneString(Object? value, {required String fallback}) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return fallback;
}

int? _toNullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _toFiniteDouble(Object? value) {
  if (value is double && value.isFinite) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

RenderSceneBounds _boundsFromPositions(List<RenderScenePoint> points) {
  if (points.isEmpty) {
    return RenderSceneBounds.zero();
  }
  var minX = points.first.x;
  var minY = points.first.y;
  var minZ = points.first.z;
  var maxX = points.first.x;
  var maxY = points.first.y;
  var maxZ = points.first.z;
  for (final point in points.skip(1)) {
    if (point.x < minX) minX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.z < minZ) minZ = point.z;
    if (point.x > maxX) maxX = point.x;
    if (point.y > maxY) maxY = point.y;
    if (point.z > maxZ) maxZ = point.z;
  }
  return RenderSceneBounds(
    min: RenderScenePoint(x: minX, y: minY, z: minZ),
    max: RenderScenePoint(x: maxX, y: maxY, z: maxZ),
  );
}
