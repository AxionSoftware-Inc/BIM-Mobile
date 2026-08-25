part of 'render_scene_models.dart';

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
    required this.levels,
    required this.materials,
    required this.sections,
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
  final List<RenderSceneLevel> levels;
  final List<RenderSceneMaterial> materials;
  final List<RenderSceneSection> sections;
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

  RenderSceneObject? objectByStableId(String? elementId) {
    if (elementId == null || elementId.isEmpty) {
      return null;
    }
    for (final object in objects) {
      if (object.elementId?.toString() == elementId) {
        return object;
      }
    }
    return null;
  }

  RenderSceneMaterial? materialById(int? materialId) {
    if (materialId == null) return null;
    for (final material in materials) {
      if (material.id == materialId) return material;
    }
    return null;
  }

  RenderSceneLevel? levelById(int? levelId) {
    if (levelId == null) {
      return null;
    }
    for (final level in levels) {
      if (level.levelId == levelId) {
        return level;
      }
    }
    return null;
  }

  RenderScene filteredByLevel(
    int? levelId, {
    bool includeUnassigned = false,
  }) {
    if (levelId == null) {
      return this;
    }
    final filteredObjects = objects
        .where(
          (object) =>
              object.levelId == levelId ||
              (includeUnassigned && object.levelId == null),
        )
        .toList(growable: false);
    final vertexCount = filteredObjects.fold<int>(
        0, (sum, object) => sum + object.mesh.positions.length);
    final indexCount = filteredObjects.fold<int>(
        0, (sum, object) => sum + object.mesh.indices.length);
    final result = parseRenderSceneJson(
      jsonEncode(
        <String, Object?>{
          ...toJson(),
          'object_count': filteredObjects.length,
          'vertex_count': vertexCount,
          'index_count': indexCount,
          'objects': filteredObjects.map((object) => object.toJson()).toList(),
        },
      ),
      source: '$source @ level $levelId',
    );
    return result.scene ?? this;
  }

  /// Non-destructive plan view range. The semantic project remains complete;
  /// this only restricts the viewport to objects crossing the active level's
  /// cut band, so upper-storey content cannot leak into a floor plan.
  RenderScene filteredByVerticalRange({
    required int activeLevelId,
    required double bottomMeters,
    required double topMeters,
  }) {
    const tolerance = 1e-6;
    final filteredObjects = objects.where(
      (object) {
        // A roof is a separate top-level object, not part of a storey floor
        // plan. Its footprint at the roof level used to leak into the active
        // plan range and add a second set of heavy perimeter lines.
        if (object.kindKey == 'roof') return false;
        // Beams are overhead framing in the floor-plan convention. Their
        // legacy meshes can be authored at local Z=0, so bounds alone
        // would incorrectly draw them through a 2 m plan cut.
        if (object.kindKey == 'beam') return false;
        // Use an open interval at the next level. A Level 1 wall ending
        // at 3.20 m must not be shown again in the Level 2 plan merely
        // because its top coincides with that level's elevation.
        final crossesCutBand = object.bounds.max.z > bottomMeters + tolerance &&
            object.bounds.min.z < topMeters - tolerance;
        // Slabs/floors may sit exactly at their owning level elevation;
        // retain those base-level objects without admitting geometry
        // owned by the storey below.
        final isActiveLevelBaseObject = object.levelId == activeLevelId &&
            object.bounds.min.z <= bottomMeters + tolerance &&
            object.bounds.max.z >= bottomMeters - tolerance;
        return crossesCutBand || isActiveLevelBaseObject;
      },
    ).toList(growable: false);
    final vertexCount = filteredObjects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.positions.length,
    );
    final indexCount = filteredObjects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.indices.length,
    );
    final result = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        ...toJson(),
        'object_count': filteredObjects.length,
        'vertex_count': vertexCount,
        'index_count': indexCount,
        'objects': filteredObjects.map((object) => object.toJson()).toList(),
      }),
      source: '$source @ view range',
    );
    return result.scene ?? this;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'scene_version': sceneVersion,
        'units': units,
        'coordinate_system': coordinateSystem,
        'object_count': objectCount,
        'vertex_count': vertexCount,
        'index_count': indexCount,
        'bounds': bounds.toJson(),
        'levels': levels.map((level) => level.toJson()).toList(),
        'materials': materials.map((material) => material.toJson()).toList(),
        'sections': sections.map((section) => section.toJson()).toList(),
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

/// Defensive limits for untrusted or accidentally unscoped native payloads.
/// Nearby-level streaming should be used before a scene approaches these
/// limits; rejecting a pathological payload is safer than allocating until
/// Android kills the process.
const int kMaxRenderScenePayloadBytes = 32 * 1024 * 1024;
const int kMaxRenderSceneObjects = 150000;
const int kMaxRenderSceneIndices = 15 * 1000 * 1000;

RenderSceneLoadResult parseRenderSceneJson(
  String text, {
  String source = 'render_scene.json',
}) {
  final warnings = <String>[];
  final errors = <String>[];
  if (text.length > kMaxRenderScenePayloadBytes) {
    return RenderSceneLoadResult(
      scene: null,
      warnings: const <String>[],
      errors: <String>[
        'RenderScene payload from $source exceeds the ${kMaxRenderScenePayloadBytes ~/ (1024 * 1024)} MiB memory guard. Use nearby-level streaming.',
      ],
    );
  }
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
  if (rawObjects is List && rawObjects.length > kMaxRenderSceneObjects) {
    return RenderSceneLoadResult(
      scene: null,
      warnings: const <String>[],
      errors: <String>[
        'RenderScene payload from $source contains ${rawObjects.length} objects, above the $kMaxRenderSceneObjects object memory guard. Use a narrower render scope.',
      ],
    );
  }
  final declaredIndexCount = _toNullableInt(
    decoded['index_count'] ?? decoded['indexCount'],
  );
  if (declaredIndexCount != null && declaredIndexCount > kMaxRenderSceneIndices) {
    return RenderSceneLoadResult(
      scene: null,
      warnings: const <String>[],
      errors: <String>[
        'RenderScene payload from $source declares ${declaredIndexCount ~/ 3} triangles, above the ${kMaxRenderSceneIndices ~/ 3} triangle memory guard.',
      ],
    );
  }
  final objects = <RenderSceneObject>[];
  if (rawObjects is List) {
    for (final entry in rawObjects) {
      objects.add(RenderSceneObject.fromJson(entry, warnings, errors));
    }
  } else {
    warnings.add('RenderScene payload from $source had no object list.');
  }

  final levels = <RenderSceneLevel>[];
  final rawLevels = decoded['levels'];
  if (rawLevels is List) {
    for (final entry in rawLevels) {
      final level = RenderSceneLevel.fromJson(entry);
      if (level != null) {
        levels.add(level);
      }
    }
  }

  final materials = <RenderSceneMaterial>[];
  final rawMaterials = decoded['materials'];
  if (rawMaterials is List) {
    for (final entry in rawMaterials) {
      final material = RenderSceneMaterial.fromJson(entry);
      if (material != null) materials.add(material);
    }
  }

  final sections = <RenderSceneSection>[];
  final rawSections = decoded['sections'];
  if (rawSections is List) {
    for (final entry in rawSections) {
      final section = RenderSceneSection.fromJson(entry);
      if (section != null) sections.add(section);
    }
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
  var invalidIndexCount = 0;
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
    invalidIndexCount += object.mesh.invalidIndexCount;
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
    invalidIndexCount: invalidIndexCount,
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
      levels: levels.isNotEmpty
          ? (levels.toList()
            ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters)))
          : _inferLevelsFromObjects(objects),
      materials: materials,
      sections: sections,
      source: source,
      diagnostics: diagnostics,
    ),
    warnings: warnings,
    errors: errors,
  );
}

List<RenderSceneLevel> _inferLevelsFromObjects(
    List<RenderSceneObject> objects) {
  final levelIds = <int>{};
  for (final object in objects) {
    if (object.levelId != null) {
      levelIds.add(object.levelId!);
    }
  }
  final sorted = levelIds.toList()..sort();
  if (sorted.isEmpty) {
    return const <RenderSceneLevel>[
      RenderSceneLevel(
        levelId: 1,
        name: 'Level 1',
        elevationMeters: 0.0,
        defaultWallHeightMeters: 3.0,
      ),
    ];
  }
  return <RenderSceneLevel>[
    for (final levelId in sorted)
      RenderSceneLevel(
        levelId: levelId,
        name: 'Level $levelId',
        elevationMeters: 0.0,
        defaultWallHeightMeters: 3.0,
      ),
  ];
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
