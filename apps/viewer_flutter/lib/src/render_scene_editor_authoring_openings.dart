part of 'render_scene_editor.dart';

RenderScene _addOpening({
  required RenderScene scene,
  required RenderSceneObject hostWall,
  required double offsetMeters,
  required double widthMeters,
  required double heightMeters,
  required double sillHeightMeters,
  required int? levelId,
  required String kind,
  required String materialCategory,
}) {
  if (RenderSceneQueries.isGlassWall(scene, hostWall)) {
    return scene;
  }

  final geometry = _wallGeometry(hostWall);
  final resolvedLevelId = hostWall.levelId ?? levelId ?? _primaryLevelId(scene);
  if (geometry == null || resolvedLevelId == null || resolvedLevelId <= 0) {
    return scene;
  }

  final axis = geometry.end - geometry.start;
  final axisLength = geometry.length;
  if (axisLength <= 1e-9) {
    return scene;
  }

  final clampedOffset = offsetMeters.clamp(0.0, axisLength);
  final halfWidth = widthMeters * 0.5;
  final alongStart = math.max(0.0, clampedOffset - halfWidth);
  final alongEnd = math.min(axisLength, clampedOffset + halfWidth);

  final axisUnit = axis.scale(1.0 / axisLength);
  final startPoint = geometry.start + axisUnit.scale(alongStart);
  final endPoint = geometry.start + axisUnit.scale(alongEnd);
  final wallNormal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
  final panelThickness = math.min(
    math.max(geometry.thickness * 0.5, 0.05),
    geometry.thickness,
  );
  final halfThickness = panelThickness * 0.5;
  final wallBaseZ = geometry.start.z;
  final lowerZ = wallBaseZ + math.max(0.0, sillHeightMeters);
  final upperZ = lowerZ + heightMeters;

  final bottom0 = startPoint + wallNormal.scale(halfThickness);
  final bottom1 = endPoint + wallNormal.scale(halfThickness);
  final bottom2 = endPoint - wallNormal.scale(halfThickness);
  final bottom3 = startPoint - wallNormal.scale(halfThickness);
  final top0 = RenderScenePoint(x: bottom0.x, y: bottom0.y, z: upperZ);
  final top1 = RenderScenePoint(x: bottom1.x, y: bottom1.y, z: upperZ);
  final top2 = RenderScenePoint(x: bottom2.x, y: bottom2.y, z: upperZ);
  final top3 = RenderScenePoint(x: bottom3.x, y: bottom3.y, z: upperZ);

  final baseOffset = lowerZ;
  final positions = <RenderScenePoint>[
    RenderScenePoint(x: bottom0.x, y: bottom0.y, z: baseOffset),
    RenderScenePoint(x: bottom1.x, y: bottom1.y, z: baseOffset),
    RenderScenePoint(x: bottom2.x, y: bottom2.y, z: baseOffset),
    RenderScenePoint(x: bottom3.x, y: bottom3.y, z: baseOffset),
    top0,
    top1,
    top2,
    top3,
  ];

  final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
  final object = <String, Object?>{
    'element_id': nextId,
    'kind': kind,
    'level_id': resolvedLevelId,
    'selectable': true,
    'visible_by_default': true,
    'revision': 1,
    'bounds': RenderSceneBounds.union(
      <RenderSceneBounds>[
        for (final point in positions)
          RenderSceneBounds.normalized(min: point, max: point),
      ],
    ).toJson(),
    'mesh': <String, Object?>{
      'positions': positions.map((point) => point.toJson()).toList(),
      'indices': <int>[
        0,
        1,
        2,
        0,
        2,
        3,
        4,
        6,
        5,
        4,
        7,
        6,
        0,
        4,
        5,
        0,
        5,
        1,
        1,
        5,
        6,
        1,
        6,
        2,
        2,
        6,
        7,
        2,
        7,
        3,
        3,
        7,
        4,
        3,
        4,
        0,
      ],
    },
    'material_category': materialCategory,
    'metadata': <String, Object?>{
      'host_wall_id': hostWall.elementId ?? hostWall.elementIdRaw,
      'offset_meters': clampedOffset,
      'width_meters': widthMeters,
      'height_meters': heightMeters,
      'sill_height_meters': sillHeightMeters,
      'panel_thickness_meters': panelThickness,
      'axis_start': geometry.start.toJson(),
      'axis_end': geometry.end.toJson(),
      'level_locked': true,
      'base_level_id': resolvedLevelId.toString(),
      'kind': kind.toLowerCase(),
    },
  };

  final map = _sceneMap(scene);
  final objects = _objectsFromSceneMap(map);
  objects.add(object);
  _rebuildAllWallObjects(objects);
  map['objects'] = objects;
  return _parseSceneMap(map, source: '${scene.source} + $kind');
}

RenderScene _addHorizontalSystemForRoom({
  required RenderScene scene,
  required RenderSceneObject room,
  required String kind,
  required String materialCategory,
  required double thicknessMeters,
  required double baseZ,
  required int? levelId,
}) {
  final bounds = room.bounds;
  final resolvedLevelId = levelId ?? room.levelId ?? _primaryLevelId(scene);
  if (!bounds.isFinite ||
      bounds.width <= 1e-6 ||
      bounds.depth <= 1e-6 ||
      resolvedLevelId == null ||
      resolvedLevelId <= 0) {
    return scene;
  }

  final z0 = baseZ;
  final z1 = baseZ + math.max(thicknessMeters, 0.02);
  final positions = <RenderScenePoint>[
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z0),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z0),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z0),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z0),
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z1),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z1),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z1),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z1),
  ];

  final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
  final object = <String, Object?>{
    'element_id': nextId,
    'kind': kind,
    'level_id': resolvedLevelId,
    'selectable': true,
    'visible_by_default': true,
    'revision': 1,
    'bounds': RenderSceneBounds.union(
      <RenderSceneBounds>[
        for (final point in positions)
          RenderSceneBounds.normalized(min: point, max: point),
      ],
    ).toJson(),
    'mesh': <String, Object?>{
      'positions': positions.map((point) => point.toJson()).toList(),
      'indices': <int>[
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        5,
        6,
        4,
        6,
        7,
        0,
        1,
        5,
        0,
        5,
        4,
        1,
        2,
        6,
        1,
        6,
        5,
        2,
        3,
        7,
        2,
        7,
        6,
        3,
        0,
        4,
        3,
        4,
        7,
      ],
    },
    'material_category': materialCategory,
    'metadata': <String, Object?>{
      'source_room_id': room.elementId,
      'thickness_meters': thicknessMeters,
      'level_locked': true,
      'base_level_id': resolvedLevelId.toString(),
      'kind': kind.toLowerCase(),
    },
  };

  final map = _sceneMap(scene);
  final objects = _objectsFromSceneMap(map);
  objects.add(object);
  map['objects'] = objects;
  return _parseSceneMap(map, source: '${scene.source} + $kind');
}

RenderScene _addHorizontalSystemForBounds({
  required RenderScene scene,
  required RenderSceneBounds bounds,
  required String kind,
  required String materialCategory,
  required double thicknessMeters,
  required double baseZ,
  required int? levelId,
}) {
  final resolvedLevelId = levelId ?? _primaryLevelId(scene);
  if (!bounds.isFinite ||
      bounds.width <= 1e-6 ||
      bounds.depth <= 1e-6 ||
      resolvedLevelId == null ||
      resolvedLevelId <= 0) {
    return scene;
  }

  final z0 = baseZ;
  final z1 = baseZ + math.max(thicknessMeters, 0.02);
  final positions = <RenderScenePoint>[
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z0),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z0),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z0),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z0),
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z1),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z1),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z1),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z1),
  ];

  final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
  final object = <String, Object?>{
    'element_id': nextId,
    'kind': kind,
    'level_id': resolvedLevelId,
    'selectable': true,
    'visible_by_default': true,
    'revision': 1,
    'bounds': RenderSceneBounds.union(
      <RenderSceneBounds>[
        for (final point in positions)
          RenderSceneBounds.normalized(min: point, max: point),
      ],
    ).toJson(),
    'mesh': <String, Object?>{
      'positions': positions.map((point) => point.toJson()).toList(),
      'indices': <int>[
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        5,
        6,
        4,
        6,
        7,
        0,
        1,
        5,
        0,
        5,
        4,
        1,
        2,
        6,
        1,
        6,
        5,
        2,
        3,
        7,
        2,
        7,
        6,
        3,
        0,
        4,
        3,
        4,
        7,
      ],
    },
    'material_category': materialCategory,
    'metadata': <String, Object?>{
      'thickness_meters': thicknessMeters,
      'level_locked': true,
      'base_level_id': resolvedLevelId.toString(),
      'kind': kind.toLowerCase(),
      'footprint_mode': 'draft_bounds',
    },
  };

  final map = _sceneMap(scene);
  final objects = _objectsFromSceneMap(map);
  objects.add(object);
  map['objects'] = objects;
  return _parseSceneMap(map, source: '${scene.source} + $kind');
}

RenderScene _addHorizontalSystemForPolygon({
  required RenderScene scene,
  required List<RenderScenePoint> polygon,
  required String kind,
  required String materialCategory,
  required double thicknessMeters,
  required double baseZ,
  required int? levelId,
}) {
  final resolvedLevelId = levelId ?? _primaryLevelId(scene);
  final footprint = polygon
      .map((point) => RenderScenePoint(x: point.x, y: point.y, z: 0.0))
      .toList(growable: false);
  if (footprint.length < 3 ||
      resolvedLevelId == null ||
      resolvedLevelId <= 0 ||
      _polygonArea2d(footprint).abs() <= 1e-6) {
    return scene;
  }

  final z0 = baseZ;
  final z1 = baseZ + math.max(thicknessMeters, 0.02);
  final positions = <RenderScenePoint>[];
  final indices = <int>[];
  _appendExtrudedPolygonMesh(
    positions: positions,
    indices: indices,
    worldPoint: (x, y, z) => RenderScenePoint(x: x, y: y, z: z),
    polygon: footprint,
    z0: z0,
    z1: z1,
  );
  if (positions.isEmpty || indices.isEmpty) return scene;

  final nextId = _nextElementId(_objectsFromSceneMap(_sceneMap(scene)));
  final object = <String, Object?>{
    'element_id': nextId,
    'kind': kind,
    'level_id': resolvedLevelId,
    'selectable': true,
    'visible_by_default': true,
    'revision': 1,
    'bounds': RenderSceneBounds.union(
      <RenderSceneBounds>[
        for (final point in positions)
          RenderSceneBounds.normalized(min: point, max: point)
      ],
    ).toJson(),
    'mesh': <String, Object?>{
      'positions': positions.map((point) => point.toJson()).toList(),
      'indices': indices,
    },
    'material_category': materialCategory,
    'metadata': <String, Object?>{
      'thickness_meters': thicknessMeters,
      'level_locked': true,
      'base_level_id': resolvedLevelId.toString(),
      'kind': kind.toLowerCase(),
      'footprint_mode': 'picked_wall_polygon',
      'footprint_points': footprint.map((point) => point.toJson()).toList(),
    },
  };

  final map = _sceneMap(scene);
  final objects = _objectsFromSceneMap(map)..add(object);
  map['objects'] = objects;
  return _parseSceneMap(map, source: '${scene.source} + $kind polygon');
}
