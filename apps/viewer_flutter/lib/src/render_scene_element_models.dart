part of 'render_scene_models.dart';

@immutable
class RenderSceneLevel {
  const RenderSceneLevel({
    required this.levelId,
    required this.name,
    required this.elevationMeters,
    required this.defaultWallHeightMeters,
  });

  final int levelId;
  final String name;
  final double elevationMeters;
  final double defaultWallHeightMeters;

  Map<String, Object?> toJson() => <String, Object?>{
        'level_id': levelId,
        'name': name,
        'elevation_meters': elevationMeters,
        'default_wall_height_meters': defaultWallHeightMeters,
      };

  static RenderSceneLevel? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final levelId = _toNullableInt(value['level_id'] ?? value['levelId']);
    if (levelId == null) {
      return null;
    }
    return RenderSceneLevel(
      levelId: levelId,
      name: toSceneString(
        value['name'],
        fallback: 'Level $levelId',
      ),
      elevationMeters: _toFiniteDouble(
            value['elevation_meters'] ?? value['elevationMeters'],
          ) ??
          0.0,
      defaultWallHeightMeters: _toFiniteDouble(
            value['default_wall_height_meters'] ??
                value['defaultWallHeightMeters'],
          ) ??
          3.0,
    );
  }
}

@immutable
class RenderSceneSection {
  const RenderSceneSection({
    required this.name,
    required this.start,
    required this.end,
  });

  final String name;
  final RenderScenePoint start;
  final RenderScenePoint end;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'start': start.toJson(),
        'end': end.toJson(),
      };

  static RenderSceneSection? fromJson(Object? value) {
    if (value is! Map) return null;
    final start = RenderScenePoint.fromJson(value['start']);
    final end = RenderScenePoint.fromJson(value['end']);
    if (start == null || end == null) return null;
    return RenderSceneSection(
      name: toSceneString(value['name'], fallback: 'Section'),
      start: start,
      end: end,
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
    this.metadata = const <String, Object?>{},
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
  final Map<String, Object?> metadata;

  String get kindKey => normalizeSceneKind(kind);
  String? get elementIdRaw => elementId?.toString();

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
        if (metadata.isNotEmpty) 'metadata': metadata,
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
        metadata: const <String, Object?>{},
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
      metadata: value['metadata'] is Map
          ? Map<String, Object?>.from(
              (value['metadata'] as Map).cast<String, Object?>(),
            )
          : const <String, Object?>{},
    );
  }
}

@immutable
class RenderSceneMaterial {
  const RenderSceneMaterial({
    required this.id,
    required this.name,
    required this.category,
    required this.displayColor,
  });

  final int id;
  final String name;
  final String category;
  final String displayColor;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'category': category,
        'display_color': displayColor,
      };

  static RenderSceneMaterial? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = _toNullableInt(value['id'] ?? value['material_id']);
    if (id == null || id == 0) return null;
    return RenderSceneMaterial(
      id: id,
      name: toSceneString(value['name'], fallback: 'Material $id'),
      category: toSceneString(value['category'], fallback: 'generic'),
      displayColor: toSceneString(value['display_color'], fallback: '#B0B7C3'),
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
    required this.invalidIndexCount,
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
  final int invalidIndexCount;
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
        'invalidIndexCount': invalidIndexCount,
        'kindCounts': kindCounts,
        'warnings': warnings,
        'errors': errors,
      };
}
