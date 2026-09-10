import 'render_scene_geometry.dart';

/// Renderer-neutral level value exposed by the engine scene contract.
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
    if (value is! Map) return null;
    final levelId = _toNullableInt(value['level_id'] ?? value['levelId']);
    if (levelId == null) return null;
    final rawElevation = value['elevation_meters'] ?? value['elevationMeters'];
    final parsedElevation = _toFiniteDouble(rawElevation);
    if (rawElevation != null && parsedElevation == null) return null;
    return RenderSceneLevel(
      levelId: levelId,
      name: _sceneString(value['name'], fallback: 'Level $levelId'),
      elevationMeters: parsedElevation ?? 0.0,
      defaultWallHeightMeters: _toFiniteDouble(
            value['default_wall_height_meters'] ??
                value['defaultWallHeightMeters'],
          ) ??
          3.0,
    );
  }
}

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
      name: _sceneString(value['name'], fallback: 'Section'),
      start: start,
      end: end,
    );
  }
}

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
      name: _sceneString(value['name'], fallback: 'Material $id'),
      category: _sceneString(value['category'], fallback: 'generic'),
      displayColor:
          _sceneString(value['display_color'], fallback: '#B0B7C3'),
    );
  }
}

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

String _sceneString(Object? value, {required String fallback}) {
  if (value is String && value.isNotEmpty) return value;
  return fallback;
}

int? _toNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _toFiniteDouble(Object? value) {
  if (value is double && value.isFinite) return value;
  if (value is int) return value.toDouble();
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
