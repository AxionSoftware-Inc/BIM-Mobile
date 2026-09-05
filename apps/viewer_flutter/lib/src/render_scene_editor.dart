import 'dart:convert';
import 'dart:math' as math;

import 'elements/bim_element_registry.dart';
import 'elements/wall_type_catalog.dart';
import 'render_scene_level_binding.dart';
import 'render_scene_models.dart';
import 'tools/wall_authoring_geometry.dart';

part 'render_scene_editor_scene_helpers.dart';
part 'render_scene_editor_support.dart';
part 'render_scene_editor_geometry.dart';
part 'render_scene_editor_authoring_helpers.dart';
part 'render_scene_editor_authoring_openings.dart';
part 'render_scene_editor_authoring_walls.dart';
part 'render_scene_editor_authoring_rooms.dart';
part 'render_scene_editor_queries.dart';

class RenderSceneEditor {
  const RenderSceneEditor._();

  static const double defaultWallThicknessMeters = 0.30;
  static const double defaultWallHeightMeters = 3.0;

  static List<RenderSceneLevel> levels(RenderScene scene) => scene.levels;

  static RenderSceneLevel? levelById(RenderScene scene, int? levelId) {
    return scene.levelById(levelId);
  }

  static bool isElementLevelLocked(RenderSceneObject object) {
    final value = object.metadata['level_locked'];
    if (value is bool) {
      return value;
    }
    final module = BimElementRegistry.standard.forKind(object.kindKey);
    return module != null &&
        module.isLevelHosted &&
        module.levelLockedByDefault;
  }

  static bool isGlassWall(RenderScene scene, RenderSceneObject wall) {
    return RenderSceneQueries.isGlassWall(scene, wall);
  }

  static RenderScene setElementLevelLock({
    required RenderScene scene,
    required RenderSceneObject object,
    required bool locked,
  }) {
    final elementId = object.elementId;
    if (elementId == null) {
      return scene;
    }
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    for (final entry in objects) {
      final objectId =
          _toInt(entry['element_id']) ?? _toInt(entry['elementId']);
      if (objectId != elementId) {
        continue;
      }
      final metadata = entry['metadata'] is Map
          ? Map<String, Object?>.from(
              (entry['metadata'] as Map).cast<String, Object?>())
          : <String, Object?>{};
      metadata['level_locked'] = locked;
      entry['metadata'] = metadata;
      break;
    }
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ level lock');
  }

  static RenderScene setLevelElevation({
    required RenderScene scene,
    required int levelId,
    required double elevationMeters,
  }) {
    final level = scene.levelById(levelId);
    if (level == null) {
      return scene;
    }
    final delta = elevationMeters - level.elevationMeters;
    if (!delta.isFinite || delta.abs() <= 1e-9) {
      return scene;
    }

    final map = _sceneMap(scene);
    final levels = _levelsFromSceneMap(map);
    if (!RenderSceneLevelBinding.canUseElevation(
      levels: levels,
      targetLevelId: levelId,
      elevationMeters: elevationMeters,
    )) {
      return scene;
    }
    final elevations = <int, double>{
      for (final entry in levels)
        if (RenderSceneLevelBinding.levelId(entry) != null)
          RenderSceneLevelBinding.levelId(entry)!:
              RenderSceneLevelBinding.levelElevation(entry),
    };
    elevations[levelId] = elevationMeters;
    final initialObjects = _objectsFromSceneMap(map);
    for (final object in initialObjects) {
      final metadata = RenderSceneLevelBinding.metadataOf(object);
      if (RenderSceneLevelBinding.kindKey(object) == 'wall' &&
          (metadata['height_mode']?.toString().toLowerCase() == 'toplevel' ||
              RenderSceneLevelBinding.toInt(metadata['top_level_id']) !=
                  null)) {
        final baseId =
            RenderSceneLevelBinding.toInt(metadata['base_level_id']) ??
                RenderSceneLevelBinding.levelId(object);
        final topId = RenderSceneLevelBinding.toInt(metadata['top_level_id']);
        if (baseId != null &&
            topId != null &&
            elevations.containsKey(baseId) &&
            elevations.containsKey(topId)) {
          final baseOffset = RenderSceneLevelBinding.toDouble(
                metadata['base_offset_meters'],
              ) ??
              0.0;
          final topOffset = RenderSceneLevelBinding.toDouble(
                metadata['top_offset_meters'],
              ) ??
              0.0;
          if (elevations[topId]! + topOffset <=
              elevations[baseId]! + baseOffset + 1e-6) {
            return scene;
          }
        }
      }
      if (RenderSceneLevelBinding.kindKey(object) == 'stair') {
        final baseId =
            RenderSceneLevelBinding.toInt(metadata['base_level_id']) ??
                RenderSceneLevelBinding.levelId(object);
        final topId = RenderSceneLevelBinding.toInt(metadata['top_level_id']);
        if (baseId != null &&
            topId != null &&
            topId != baseId &&
            elevations.containsKey(baseId) &&
            elevations.containsKey(topId) &&
            elevations[topId]! <= elevations[baseId]! + 1e-6) {
          return scene;
        }
      }
    }
    for (final entry in levels) {
      final entryLevelId =
          _toInt(entry['level_id']) ?? _toInt(entry['levelId']);
      if (entryLevelId == levelId) {
        entry['elevation_meters'] = elevationMeters;
        break;
      }
    }
    map['levels'] = levels;

    final objects = _objectsFromSceneMap(map);
    RenderSceneLevelBinding.normalizeObjects(objects, levels);
    final wallBaseLevelById = <int, int>{
      for (final wall in objects)
        if (RenderSceneLevelBinding.kindKey(wall) == 'wall')
          if ((_toInt(wall['element_id']) ?? _toInt(wall['elementId'])) != null)
            (_toInt(wall['element_id']) ?? _toInt(wall['elementId']))!:
                _toInt((wall['metadata'] as Map?)?['base_level_id']) ??
                    _toInt(wall['level_id']) ??
                    0,
    };
    final hostBaseLevelByOpeningId = <int, int>{
      for (final opening in objects)
        if (<String>{'door', 'window'}.contains(
          (opening['kind']?.toString() ?? '').toLowerCase(),
        ))
          if ((_toInt(opening['element_id']) ?? _toInt(opening['elementId'])) !=
              null)
            (_toInt(opening['element_id']) ??
                _toInt(opening['elementId']))!: wallBaseLevelById[
                    _toInt((opening['metadata'] as Map?)?['host_wall_id'])] ??
                0,
    };
    for (var index = 0; index < objects.length; index += 1) {
      final object = objects[index];
      final objectLevelId =
          _toInt(object['level_id']) ?? _toInt(object['levelId']);
      final parsedObject = RenderSceneObject.fromJson(
        object,
        <String>[],
        <String>[],
      );

      final kind = RenderSceneLevelBinding.kindKey(object);
      if (kind == 'wall') {
        if (!RenderSceneLevelBinding.isLevelLocked(object)) {
          continue;
        }
        final geometry = _wallGeometryFromMap(object);
        if (geometry == null) {
          continue;
        }
        final metadataMap =
            object['metadata'] is Map ? object['metadata'] as Map : null;
        final baseLevelId =
            _toInt(metadataMap?['base_level_id']) ?? objectLevelId;
        final topLevelId = _toInt(metadataMap?['top_level_id']) ?? 0;
        if (baseLevelId != levelId && topLevelId != levelId) {
          continue;
        }
        var heightMeters =
            _toDouble(metadataMap?['height_meters']) ?? defaultWallHeightMeters;
        // Base follows its level. Top-level walls retain an absolute top when
        // only the base moves, and resize when only the top moves.
        final baseDelta = baseLevelId == levelId ? delta : 0.0;
        if (topLevelId == levelId) {
          heightMeters += delta;
        }
        if (baseLevelId == levelId && topLevelId != levelId) {
          heightMeters -= delta;
        }
        heightMeters = math.max(0.01, heightMeters);
        final thicknessMeters = geometry.thickness.isFinite
            ? geometry.thickness
            : defaultWallThicknessMeters;
        final shiftedStart = RenderScenePoint(
          x: geometry.start.x,
          y: geometry.start.y,
          z: geometry.start.z + baseDelta,
        );
        final shiftedEnd = RenderScenePoint(
          x: geometry.end.x,
          y: geometry.end.y,
          z: geometry.end.z + baseDelta,
        );
        final rebuilt = _buildWallObject(
          elementId: parsedObject.elementId ?? 0,
          start: shiftedStart,
          end: shiftedEnd,
          heightMeters: heightMeters,
          thicknessMeters: thicknessMeters,
          levelId: baseLevelId,
          metadata: <String, Object?>{
            if (metadataMap != null)
              ...Map<String, Object?>.from(metadataMap.cast<String, Object?>()),
            'base_level_id': baseLevelId,
            if (topLevelId != 0) 'top_level_id': topLevelId,
            if (topLevelId != 0) 'height_mode': 'TopLevel',
            if (topLevelId == 0) 'height_mode': 'Unconnected',
          },
          revision: _toInt(object['revision']) ?? parsedObject.revision,
          materialCategory: object['material_category']?.toString() ??
              parsedObject.materialCategory,
        );
        objects[index] = rebuilt;
        continue;
      }

      if (objectLevelId != levelId ||
          !RenderSceneLevelBinding.isLevelLocked(object)) {
        continue;
      }

      if (kind == 'door' || kind == 'window') {
        final id = parsedObject.elementId;
        if (id != null && hostBaseLevelByOpeningId[id] == levelId) {
          _shiftObjectZInPlace(object, delta);
        }
        continue;
      }
      if (kind == 'room') {
        continue;
      }

      _shiftObjectZInPlace(object, delta);
    }

    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ level');
  }

  static RenderScene createLevel({
    required RenderScene scene,
    required String name,
    required double elevationMeters,
    double defaultWallHeightMeters = defaultWallHeightMeters,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return scene;
    }
    if (!elevationMeters.isFinite ||
        !defaultWallHeightMeters.isFinite ||
        defaultWallHeightMeters <= 0.0) {
      return scene;
    }
    final map = _sceneMap(scene);
    final levels = _levelsFromSceneMap(map);
    final nextLevelId = _nextLevelId(levels);
    if (!RenderSceneLevelBinding.canUseElevation(
      levels: levels,
      targetLevelId: nextLevelId,
      elevationMeters: elevationMeters,
    )) {
      return scene;
    }
    levels.add(
      <String, Object?>{
        'level_id': nextLevelId,
        'name': trimmedName,
        'elevation_meters': elevationMeters,
        'default_wall_height_meters': defaultWallHeightMeters,
      },
    );
    levels.sort(
      (a, b) => (_toDouble(a['elevation_meters']) ?? 0.0)
          .compareTo(_toDouble(b['elevation_meters']) ?? 0.0),
    );
    map['levels'] = levels;
    return _parseSceneMap(map, source: '${scene.source} + level');
  }

  static RenderScene addWall({
    required RenderScene scene,
    required RenderScenePoint start,
    required RenderScenePoint end,
    double heightMeters = defaultWallHeightMeters,
    double thicknessMeters = defaultWallThicknessMeters,
    int? levelId,
    int? topLevelId,
  }) {
    if (!start.isFinite || !end.isFinite) {
      return scene;
    }

    final length = start.distanceTo(end);
    if (length < 1e-6) {
      return scene;
    }

    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final nextId = _nextElementId(objects);
    final resolvedLevelId = levelId ?? _primaryLevelId(scene);
    if (resolvedLevelId == null || resolvedLevelId <= 0) {
      return scene;
    }
    final resolvedTopLevelId = topLevelId ??
        RenderSceneLevelBinding.nearestHigherLevelId(
          levels: _levelsFromSceneMap(map),
          baseLevelId: resolvedLevelId,
        );
    final resolvedHeight = heightMeters <= 1e-6
        ? _levelDefaultWallHeightMeters(scene, resolvedLevelId)
        : heightMeters;
    final defaultWallType = scene.wallTypes.firstWhere(
      (type) => type.name == 'Basic Wall',
      orElse: () => scene.wallTypes.isEmpty
          ? const WallTypeDefinition(
              id: 0,
              name: 'Basic Wall',
              category: WallTypeCategory.generic,
              totalThicknessMeters: defaultWallThicknessMeters,
              layers: <WallTypeLayerDefinition>[],
              coreStartLayer: -1,
              coreEndLayer: -1,
            )
          : scene.wallTypes.first,
    );
    final wallObject = _buildWallObject(
      elementId: nextId,
      start: start,
      end: end,
      heightMeters: resolvedHeight,
      thicknessMeters: thicknessMeters,
      levelId: resolvedLevelId,
      metadata: <String, Object?>{
        'base_level_id': resolvedLevelId.toString(),
        if (resolvedTopLevelId != null)
          'top_level_id': resolvedTopLevelId.toString(),
        'height_mode': resolvedTopLevelId == null ? 'Unconnected' : 'TopLevel',
        'level_locked': true,
        'wall_type_id': defaultWallType.id.toString(),
        'wall_type_name': defaultWallType.name,
        'wall_type_category': defaultWallType.categoryLabel,
      },
    );
    objects.add(wallObject);
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + wall');
  }

  static RenderScene addCurvedWall({
    required RenderScene scene,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required RenderScenePoint center,
    required double radiusMeters,
    required double startAngleRadians,
    required double sweepRadians,
    double heightMeters = defaultWallHeightMeters,
    double thicknessMeters = defaultWallThicknessMeters,
    int? levelId,
    int? topLevelId,
  }) {
    if (!start.isFinite ||
        !end.isFinite ||
        !center.isFinite ||
        !radiusMeters.isFinite ||
        radiusMeters <= 1e-6 ||
        !startAngleRadians.isFinite ||
        !sweepRadians.isFinite ||
        sweepRadians.abs() <= 1e-6 ||
        sweepRadians.abs() > 2.0 * math.pi + 1e-6 ||
        heightMeters <= 1e-6 ||
        thicknessMeters <= 1e-6) {
      return scene;
    }
    final resolvedLevelId = levelId ?? _primaryLevelId(scene);
    if (resolvedLevelId == null || resolvedLevelId <= 0) return scene;
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    final resolvedTopLevelId = topLevelId ??
        RenderSceneLevelBinding.nearestHigherLevelId(
          levels: _levelsFromSceneMap(map),
          baseLevelId: resolvedLevelId,
        );
    final defaultWallType = scene.wallTypes.firstWhere(
      (type) => type.name == 'Basic Wall',
      orElse: () => scene.wallTypes.isEmpty
          ? const WallTypeDefinition(
              id: 0,
              name: 'Basic Wall',
              category: WallTypeCategory.generic,
              totalThicknessMeters: defaultWallThicknessMeters,
              layers: <WallTypeLayerDefinition>[],
              coreStartLayer: -1,
              coreEndLayer: -1,
            )
          : scene.wallTypes.first,
    );
    objects.add(
      _buildCurvedWallObject(
        elementId: _nextElementId(objects),
        start: start,
        end: end,
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        sweepRadians: sweepRadians,
        heightMeters: heightMeters,
        thicknessMeters: thicknessMeters,
        levelId: resolvedLevelId,
        metadata: <String, Object?>{
          'base_level_id': resolvedLevelId.toString(),
          if (resolvedTopLevelId != null)
            'top_level_id': resolvedTopLevelId.toString(),
          'height_mode':
              resolvedTopLevelId == null ? 'Unconnected' : 'TopLevel',
          'wall_type_id': defaultWallType.id.toString(),
          'wall_type_name': defaultWallType.name,
          'wall_type_category': defaultWallType.categoryLabel,
        },
      ),
    );
    _rebuildAllWallObjects(objects);
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} + curved wall');
  }

  static RenderScene normalizeSceneGeometry(RenderScene scene) {
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    if (objects.isEmpty) {
      return scene;
    }
    RenderSceneLevelBinding.normalizeObjects(objects, _levelsFromSceneMap(map));
    // RenderScene from the native engine already contains the authoritative
    // joined wall meshes (including mitres and opening cuts). Rebuilding it
    // here from a bounds approximation used to overwrite that topology on
    // every load, which made connected walls look overlapped in plan and
    // removed meaningful interior edge loops in 3D. Local/legacy scenes that
    // lack a usable wall mesh still take the repair path below.
    if (_needsWallGeometryRepair(objects)) {
      _rebuildAllWallObjects(objects);
      _rebuildDetectedRooms(objects);
    }
    map['objects'] = objects;
    return _parseSceneMap(map, source: scene.source);
  }

  /// Rebuilds the lightweight plan-room graph from the current wall geometry.
  ///
  /// Native engine snapshots do not necessarily contain Room objects until a
  /// room mutation has been requested. Authoring tools still need a preview,
  /// so this intentionally creates temporary room objects without changing
  /// the document.
  static RenderScene detectRooms(RenderScene scene) {
    final map = _sceneMap(scene);
    final objects = _objectsFromSceneMap(map);
    if (objects.isEmpty) return scene;
    RenderSceneLevelBinding.normalizeObjects(objects, _levelsFromSceneMap(map));
    _rebuildDetectedRooms(objects);
    map['objects'] = objects;
    return _parseSceneMap(map, source: '${scene.source} ~ detected rooms');
  }

  static List<int> roomBoundaryWallIds(RenderSceneObject room) {
    final raw = room.metadata['boundary_wall_ids'];
    if (raw is List) {
      return raw.map(_toInt).whereType<int>().toSet().toList(growable: false);
    }
    if (raw is String && raw.isNotEmpty) {
      return raw
          .split(',')
          .map((value) => int.tryParse(value.trim()))
          .whereType<int>()
          .toSet()
          .toList(growable: false);
    }
    return const <int>[];
  }

  static List<RenderScenePoint>? roomBoundaryPolygon(
    RenderScene scene,
    RenderSceneObject room, {
    double toleranceMeters = 0.45,
  }) {
    final rawPolygon = room.metadata['boundary_polygon'];
    if (rawPolygon is List) {
      final polygon = rawPolygon
          .map(RenderScenePoint.fromJson)
          .whereType<RenderScenePoint>()
          .toList(growable: false);
      if (polygon.length >= 3 && _polygonArea2d(polygon).abs() > 1e-6) {
        return polygon;
      }
    }
    if (rawPolygon is String && rawPolygon.isNotEmpty) {
      final polygon = rawPolygon
          .split(';')
          .map((entry) {
            final coordinates = entry.split(',');
            if (coordinates.length != 2) return null;
            final x = double.tryParse(coordinates[0].trim());
            final y = double.tryParse(coordinates[1].trim());
            if (x == null || y == null) return null;
            return RenderScenePoint(x: x, y: y, z: room.bounds.min.z);
          })
          .whereType<RenderScenePoint>()
          .toList(growable: false);
      if (polygon.length >= 3 && _polygonArea2d(polygon).abs() > 1e-6) {
        return polygon;
      }
    }
    final ids = roomBoundaryWallIds(room).toSet();
    if (ids.length < 3) return null;
    final walls = scene.objects
        .where((object) => ids.contains(object.elementId))
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    return surfacePolygonForWalls(walls, toleranceMeters: toleranceMeters);
  }

  static bool _needsWallGeometryRepair(List<Map<String, Object?>> objects) {
    for (final object in objects) {
      final kind = (object['kind']?.toString() ?? '').toLowerCase();
      if (kind != 'wall') {
        continue;
      }
      final mesh = object['mesh'];
      if (mesh is! Map) {
        return true;
      }
      final positions = mesh['positions'];
      final indices = mesh['indices'];
      if (positions is! List ||
          positions.length < 4 ||
          indices is! List ||
          indices.length < 3) {
        return true;
      }
    }
    return false;
  }

  static RenderScene addDoor({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required double offsetMeters,
    double widthMeters = 0.9,
    double heightMeters = 2.1,
    int? levelId,
  }) {
    return _addOpening(
      scene: scene,
      hostWall: hostWall,
      offsetMeters: offsetMeters,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: 0.0,
      levelId: levelId,
      kind: 'Door',
      materialCategory: 'generic',
    );
  }

  static RenderScene addWindow({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required double offsetMeters,
    double widthMeters = 1.2,
    double heightMeters = 1.2,
    double sillHeightMeters = 0.9,
    int? levelId,
  }) {
    return _addOpening(
      scene: scene,
      hostWall: hostWall,
      offsetMeters: offsetMeters,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: sillHeightMeters,
      levelId: levelId,
      kind: 'Window',
      materialCategory: 'glass',
    );
  }

  static RenderScene addFloorForRoom({
    required RenderScene scene,
    required RenderSceneObject room,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForRoom(
      scene: scene,
      room: room,
      kind: 'Floor',
      materialCategory: 'floor',
      thicknessMeters: thicknessMeters,
      baseZ: topElevationMeters - thicknessMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingForRoom({
    required RenderScene scene,
    required RenderSceneObject room,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForRoom(
      scene: scene,
      room: room,
      kind: 'Ceiling',
      materialCategory: 'ceiling',
      thicknessMeters: thicknessMeters,
      baseZ: _levelElevation(scene, levelId ?? room.levelId) +
          math.max(heightMeters - thicknessMeters, 0.02),
      levelId: levelId,
    );
  }

  static RenderScene addFloorFromBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForBounds(
      scene: scene,
      bounds: bounds,
      kind: 'Floor',
      materialCategory: 'floor',
      thicknessMeters: thicknessMeters,
      baseZ: topElevationMeters - thicknessMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingFromBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForBounds(
      scene: scene,
      bounds: bounds,
      kind: 'Ceiling',
      materialCategory: 'ceiling',
      thicknessMeters: thicknessMeters,
      baseZ: _levelElevation(scene, levelId) +
          math.max(heightMeters - thicknessMeters, 0.02),
      levelId: levelId,
    );
  }

  static RenderScene addFloorFromWalls({
    required RenderScene scene,
    required List<RenderSceneObject> walls,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    final polygon = surfacePolygonForWalls(walls);
    if (polygon == null) {
      return scene;
    }
    return addFloorFromPolygon(
      scene: scene,
      polygon: polygon,
      thicknessMeters: thicknessMeters,
      topElevationMeters: topElevationMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingFromWalls({
    required RenderScene scene,
    required List<RenderSceneObject> walls,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    final polygon = surfacePolygonForWalls(walls);
    if (polygon == null) {
      return scene;
    }
    return addCeilingFromPolygon(
      scene: scene,
      polygon: polygon,
      thicknessMeters: thicknessMeters,
      heightMeters: heightMeters,
      levelId: levelId,
    );
  }

  static RenderScene addFloorFromPolygon({
    required RenderScene scene,
    required List<RenderScenePoint> polygon,
    double thicknessMeters = 0.18,
    double topElevationMeters = 0.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForPolygon(
      scene: scene,
      polygon: polygon,
      kind: 'Floor',
      materialCategory: 'floor',
      thicknessMeters: thicknessMeters,
      baseZ: topElevationMeters - thicknessMeters,
      levelId: levelId,
    );
  }

  static RenderScene addCeilingFromPolygon({
    required RenderScene scene,
    required List<RenderScenePoint> polygon,
    double thicknessMeters = 0.05,
    double heightMeters = 3.0,
    int? levelId,
  }) {
    return _addHorizontalSystemForPolygon(
      scene: scene,
      polygon: polygon,
      kind: 'Ceiling',
      materialCategory: 'ceiling',
      thicknessMeters: thicknessMeters,
      baseZ: _levelElevation(scene, levelId) +
          math.max(heightMeters - thicknessMeters, 0.02),
      levelId: levelId,
    );
  }

  static RenderScene addRoofFromPolygon({
    required RenderScene scene,
    required List<RenderScenePoint> polygon,
    double thicknessMeters = 0.18,
    double baseElevationMeters = 0.0,
    int? levelId,
    int roofType = 0,
    double? slopeDegrees,
    double overhangMeters = 0.0,
  }) {
    return _addHorizontalSystemForPolygon(
      scene: scene,
      polygon: polygon,
      kind: 'Roof',
      materialCategory: 'roof',
      thicknessMeters: thicknessMeters,
      baseZ: baseElevationMeters,
      levelId: levelId,
      roofType: roofType,
      roofSlopeDegrees: slopeDegrees,
      roofOverhangMeters: overhangMeters,
    );
  }

  static RenderScene addRoofFromBounds({
    required RenderScene scene,
    required RenderSceneBounds bounds,
    double thicknessMeters = 0.18,
    double baseElevationMeters = 0.0,
    int? levelId,
    int roofType = 0,
    double? slopeDegrees,
    double overhangMeters = 0.0,
  }) {
    if (!bounds.isFinite || bounds.width <= 1e-6 || bounds.depth <= 1e-6) {
      return scene;
    }
    return addRoofFromPolygon(
      scene: scene,
      polygon: <RenderScenePoint>[
        RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: 0.0),
        RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: 0.0),
        RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: 0.0),
        RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: 0.0),
      ],
      thicknessMeters: thicknessMeters,
      baseElevationMeters: baseElevationMeters,
      levelId: levelId,
      roofType: roofType,
      slopeDegrees: slopeDegrees,
      overhangMeters: overhangMeters,
    );
  }

  static RenderScenePoint? projectModelPointToWallOffset(
    RenderSceneObject hostWall,
    RenderScenePoint point,
  ) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final axis = geometry.end - geometry.start;
    final axisLength = geometry.length;
    if (axisLength <= 1e-9) {
      return null;
    }

    final toPoint = point - geometry.start;
    final t = _dot(toPoint, axis) / (axisLength * axisLength);
    final projected = geometry.start + axis.scale(t.clamp(0.0, 1.0));
    return projected;
  }

  static double? wallOffsetMeters(
      RenderSceneObject hostWall, RenderScenePoint point) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final axis = geometry.end - geometry.start;
    final axisLength = geometry.length;
    if (axisLength <= 1e-9) {
      return null;
    }

    final toPoint = point - geometry.start;
    final t = (_dot(toPoint, axis) / (axisLength * axisLength)).clamp(0.0, 1.0);
    return axisLength * t;
  }

  static RenderSceneObject? hostWallForOpening(
    RenderScene scene,
    RenderScenePoint point, {
    double toleranceMeters = 0.35,
  }) {
    RenderSceneObject? bestWall;
    var bestDistance = double.infinity;

    for (final object in scene.objects) {
      if (object.kindKey != 'wall') {
        continue;
      }

      final geometry = _wallGeometry(object);
      if (geometry == null) {
        continue;
      }

      final projected =
          _projectPointToSegment(point, geometry.start, geometry.end);
      final distance = point.distanceTo(projected);
      if (distance < bestDistance && distance <= toleranceMeters) {
        bestDistance = distance;
        bestWall = object;
      }
    }

    return bestWall;
  }

  static RenderSceneObject? roomContainingPoint(
    RenderScene scene,
    RenderScenePoint point, {
    int? levelId,
  }) {
    RenderSceneObject? bestRoom;
    var bestArea = double.infinity;

    for (final object in scene.objects) {
      if (object.kindKey != 'room') {
        continue;
      }
      if (levelId != null && object.levelId != levelId) {
        continue;
      }

      final bounds = object.bounds;
      if (!bounds.isFinite) {
        continue;
      }

      final insideX = point.x >= bounds.min.x && point.x <= bounds.max.x;
      final insideY = point.y >= bounds.min.y && point.y <= bounds.max.y;
      if (!insideX || !insideY) {
        continue;
      }

      final polygon = roomBoundaryPolygon(scene, object);
      if (polygon != null && !_pointInPlanPolygon(point, polygon)) {
        continue;
      }
      final area = polygon == null
          ? bounds.width * bounds.depth
          : _polygonArea2d(polygon).abs();
      if (area < bestArea) {
        bestArea = area;
        bestRoom = object;
      }
    }

    return bestRoom;
  }

  static RenderScenePoint? openingCenterPoint({
    required RenderSceneObject hostWall,
    required double offsetMeters,
  }) {
    final geometry = _wallGeometry(hostWall);
    if (geometry == null) {
      return null;
    }

    final length = geometry.length;
    if (length <= 1e-9) {
      return null;
    }

    final clamped = offsetMeters.clamp(0.0, length);
    final axis = geometry.end - geometry.start;
    return geometry.start + axis.scale(clamped / length);
  }

  static RenderSceneObject? objectByStableId(RenderScene scene, String? id) =>
      RenderSceneQueries.objectByStableId(scene, id);

  static RenderSceneObject? objectById(RenderScene scene, int? id) =>
      RenderSceneQueries.objectById(scene, id);

  static RenderScenePoint? wallStartPoint(RenderSceneObject wall) =>
      RenderSceneQueries.wallStartPoint(wall);

  static RenderScenePoint? wallEndPoint(RenderSceneObject wall) =>
      RenderSceneQueries.wallEndPoint(wall);

  static List<RenderScenePoint> wallCenterlinePoints(RenderSceneObject wall) =>
      RenderSceneQueries.wallCenterlinePoints(wall);

  static RenderScenePoint? wallMidpointPoint(RenderSceneObject wall) =>
      RenderSceneQueries.wallMidpointPoint(wall);

  static WallArcGeometry? wallArcGeometry(RenderSceneObject wall) =>
      RenderSceneQueries.wallArcGeometry(wall);

  static double? wallThickness(RenderSceneObject wall) =>
      RenderSceneQueries.wallThickness(wall);

  static double? wallLength(RenderSceneObject wall) =>
      RenderSceneQueries.wallLength(wall);

  static int? wallLevelId(RenderSceneObject wall) =>
      RenderSceneQueries.wallLevelId(wall);

  static RenderScenePoint? wallAxisDirection(RenderSceneObject wall) =>
      RenderSceneQueries.wallAxisDirection(wall);

  static RenderScenePoint? wallPerpendicularDirection(RenderSceneObject wall) =>
      RenderSceneQueries.wallPerpendicularDirection(wall);

  static RenderScenePoint? wallCenterPoint(RenderSceneObject wall) =>
      RenderSceneQueries.wallCenterPoint(wall);

  static RenderSceneBounds sceneBoundsForObjects(
          List<RenderSceneObject> objects) =>
      RenderSceneQueries.sceneBoundsForObjects(objects);

  static List<RenderScenePoint> wallSnapPoints(RenderScene scene) =>
      RenderSceneQueries.wallSnapPoints(scene);

  static RenderSceneBounds? surfaceBoundsForWalls(
          List<RenderSceneObject> walls) =>
      RenderSceneQueries.surfaceBoundsForWalls(walls);

  static List<RenderScenePoint>? surfacePolygonForWalls(
    List<RenderSceneObject> walls, {
    double toleranceMeters = 0.45,
  }) =>
      RenderSceneQueries.surfacePolygonForWalls(
        walls,
        toleranceMeters: toleranceMeters,
      );

  static RenderScene deleteObject({
    required RenderScene scene,
    required RenderSceneObject target,
  }) =>
      RenderSceneQueries.deleteObject(scene: scene, target: target);

  static RenderScene setWallAxis({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) =>
      RenderSceneQueries.setWallAxis(
        scene: scene,
        wall: wall,
        start: start,
        end: end,
      );

  static RenderScene setCurvedWallGeometry({
    required RenderScene scene,
    required RenderSceneObject wall,
    required WallArcGeometry geometry,
  }) =>
      RenderSceneQueries.setCurvedWallGeometry(
        scene: scene,
        wall: wall,
        geometry: geometry,
      );

  static Map<int, ({RenderScenePoint start, RenderScenePoint end})>
      wallAxisUpdatesForJoin({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint start,
    required RenderScenePoint end,
    double toleranceMeters = 0.15,
  }) =>
          RenderSceneQueries.wallAxisUpdatesForJoin(
            scene: scene,
            wall: wall,
            start: start,
            end: end,
            toleranceMeters: toleranceMeters,
          );

  static RenderScene moveOpening({
    required RenderScene scene,
    required RenderSceneObject opening,
    required double offsetMeters,
  }) =>
      RenderSceneQueries.moveOpening(
        scene: scene,
        opening: opening,
        offsetMeters: offsetMeters,
      );

  static RenderScene synchronizeAutoRoomSurfaces({
    required RenderScene scene,
    bool includeFloors = true,
    bool includeCeilings = true,
    double floorThicknessMeters = 0.18,
    double floorTopElevationMeters = 0.0,
    double ceilingThicknessMeters = 0.05,
    double ceilingHeightMeters = 3.0,
  }) =>
      RenderSceneQueries.synchronizeAutoRoomSurfaces(
        scene: scene,
        includeFloors: includeFloors,
        includeCeilings: includeCeilings,
        floorThicknessMeters: floorThicknessMeters,
        floorTopElevationMeters: floorTopElevationMeters,
        ceilingThicknessMeters: ceilingThicknessMeters,
        ceilingHeightMeters: ceilingHeightMeters,
      );
}
