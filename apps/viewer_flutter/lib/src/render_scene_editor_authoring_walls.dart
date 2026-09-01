part of 'render_scene_editor.dart';

Map<String, Object?> _buildWallObject({
  required int elementId,
  required RenderScenePoint start,
  required RenderScenePoint end,
  required double heightMeters,
  required double thicknessMeters,
  required int? levelId,
  Map<String, Object?> metadata = const <String, Object?>{},
  int revision = 1,
  String materialCategory = 'structural',
}) {
  final axis = end - start;
  final length = start.distanceTo(end);
  final baseZ =
      ((start.z + end.z) * 0.5).isFinite ? (start.z + end.z) * 0.5 : 0.0;
  final axisUnit = axis.scale(1.0 / math.max(length, 1e-9));
  final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
  final halfThickness = thicknessMeters * 0.5;
  final lower0 = start + normal.scale(halfThickness);
  final lower1 = end + normal.scale(halfThickness);
  final lower2 = end - normal.scale(halfThickness);
  final lower3 = start - normal.scale(halfThickness);
  final upper0 =
      RenderScenePoint(x: lower0.x, y: lower0.y, z: baseZ + heightMeters);
  final upper1 =
      RenderScenePoint(x: lower1.x, y: lower1.y, z: baseZ + heightMeters);
  final upper2 =
      RenderScenePoint(x: lower2.x, y: lower2.y, z: baseZ + heightMeters);
  final upper3 =
      RenderScenePoint(x: lower3.x, y: lower3.y, z: baseZ + heightMeters);
  final positions = <RenderScenePoint>[
    RenderScenePoint(x: lower0.x, y: lower0.y, z: baseZ),
    RenderScenePoint(x: lower1.x, y: lower1.y, z: baseZ),
    RenderScenePoint(x: lower2.x, y: lower2.y, z: baseZ),
    RenderScenePoint(x: lower3.x, y: lower3.y, z: baseZ),
    upper0,
    upper1,
    upper2,
    upper3,
  ];

  final bounds = RenderSceneBounds.union(
    <RenderSceneBounds>[
      for (final point in positions)
        RenderSceneBounds.normalized(min: point, max: point),
    ],
  );

  final mergedMetadata = <String, Object?>{
    ...metadata,
    'axis_start': start.toJson(),
    'axis_end': end.toJson(),
    'start_x': start.x,
    'start_y': start.y,
    'end_x': end.x,
    'end_y': end.y,
    'height_meters': heightMeters,
    'thickness_meters': thicknessMeters,
    'level_locked': metadata['level_locked'] ?? true,
    'kind': 'wall',
  };

  return <String, Object?>{
    'element_id': elementId,
    'kind': 'Wall',
    'level_id': levelId,
    'selectable': true,
    'visible_by_default': true,
    'revision': revision,
    'bounds': bounds.toJson(),
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
    'metadata': mergedMetadata,
  };
}

List<Map<String, Object?>> _openingContourFeatureEdges(
  _WallGeometry geometry,
  List<_OpeningCutSpec> openings,
) {
  final axis = geometry.end - geometry.start;
  final planLength = math.sqrt((axis.x * axis.x) + (axis.y * axis.y));
  if (!planLength.isFinite || planLength <= 1e-9) {
    return const <Map<String, Object?>>[];
  }
  final direction = RenderScenePoint(
    x: axis.x / planLength,
    y: axis.y / planLength,
    z: 0.0,
  );
  final normal = RenderScenePoint(x: -direction.y, y: direction.x, z: 0.0);
  final baseZ = (geometry.start.z + geometry.end.z) * 0.5;
  final halfThickness = geometry.thickness * 0.5;
  final edges = <Map<String, Object?>>[];

  Map<String, Object?> edge(RenderScenePoint start, RenderScenePoint end) =>
      <String, Object?>{
        'role': 'opening_contour',
        'start': start.toJson(),
        'end': end.toJson(),
      };

  for (final opening in openings) {
    for (final faceSign in <double>[-1.0, 1.0]) {
      RenderScenePoint pointAt(double offset, double elevation) {
        final plan = geometry.start +
            direction.scale(offset) +
            normal.scale(halfThickness * faceSign);
        return RenderScenePoint(x: plan.x, y: plan.y, z: baseZ + elevation);
      }

      final lowerLeft = pointAt(opening.startOffset, opening.bottomZ);
      final lowerRight = pointAt(opening.endOffset, opening.bottomZ);
      final upperRight = pointAt(opening.endOffset, opening.topZ);
      final upperLeft = pointAt(opening.startOffset, opening.topZ);
      edges.addAll(<Map<String, Object?>>[
        edge(lowerLeft, lowerRight),
        edge(lowerRight, upperRight),
        edge(upperRight, upperLeft),
        edge(upperLeft, lowerLeft),
      ]);
    }
  }
  return edges;
}

void _rebuildAllWallObjects(List<Map<String, Object?>> objects) {
  final wallEntries = <_WallEntry>[];
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
    wallEntries.add(
      _WallEntry(
        objectId: objectId,
        objectMap: object,
        geometry: geometry,
        heightMeters: heightMeters,
      ),
    );
  }

  final openingSpecs = <int, _ResolvedOpeningSpec>{};
  for (final object in objects) {
    final kind = (object['kind']?.toString() ?? '').toLowerCase();
    if (kind != 'door' && kind != 'window') {
      continue;
    }
    final objectId =
        _toInt(object['element_id']) ?? _toInt(object['elementId']);
    if (objectId == null) {
      continue;
    }
    final spec = _resolveOpeningSpec(
      openingObject: object,
      allWalls: wallEntries,
    );
    if (spec != null) {
      openingSpecs[objectId] = spec;
    }
  }

  for (final wall in wallEntries) {
    final openings = <_OpeningCutSpec>[];
    for (final spec in openingSpecs.values) {
      if (spec.hostWall.objectId == wall.objectId) {
        openings.add(
          _OpeningCutSpec(
            startOffset:
                math.max(0.0, spec.offsetMeters - (spec.widthMeters * 0.5)),
            endOffset: math.min(
              wall.geometry.length,
              spec.offsetMeters + (spec.widthMeters * 0.5),
            ),
            bottomZ: math.max(0.0, spec.sillHeightMeters),
            topZ: math.min(
              wall.heightMeters,
              spec.sillHeightMeters + spec.heightMeters,
            ),
          ),
        );
      }
    }

    final rebuilt = _buildWallMeshWithOpenings(
      geometry: wall.geometry,
      heightMeters: wall.heightMeters,
      openings: openings,
      profilePolygon: _wallProfilePolygon(wall, wallEntries),
    );
    wall.objectMap['mesh'] = rebuilt.mesh;
    wall.objectMap['bounds'] = rebuilt.bounds.toJson();
    final existingMetadata = wall.objectMap['metadata'] is Map
        ? Map<String, Object?>.from(
            (wall.objectMap['metadata'] as Map).cast<String, Object?>(),
          )
        : <String, Object?>{};
    // Renderer decoration must consume the same geometry-derived contours as
    // the wall mesh. Drop the old texture hint during an interactive edit.
    existingMetadata.remove('opening_profile');
    wall.objectMap['metadata'] = existingMetadata;
    final preservedEdges = wall.objectMap['feature_edges'] is List
        ? (wall.objectMap['feature_edges'] as List)
            .whereType<Map>()
            .where(
              (edge) =>
                  edge['role']?.toString().toLowerCase() != 'opening_contour',
            )
            .map((edge) => Map<String, Object?>.from(edge))
            .toList()
        : <Map<String, Object?>>[];
    wall.objectMap['feature_edges'] = <Map<String, Object?>>[
      ...preservedEdges,
      ..._openingContourFeatureEdges(wall.geometry, openings),
    ];
  }

  for (final object in objects) {
    final kind = (object['kind']?.toString() ?? '').toLowerCase();
    if (kind != 'door' && kind != 'window') {
      continue;
    }
    final objectId =
        _toInt(object['element_id']) ?? _toInt(object['elementId']);
    final spec = objectId == null ? null : openingSpecs[objectId];
    if (spec == null) {
      continue;
    }
    final rebuilt = _buildOpeningMesh(spec);
    object['mesh'] = rebuilt.mesh;
    object['bounds'] = rebuilt.bounds.toJson();
    object['metadata'] = <String, Object?>{
      ...(object['metadata'] is Map
          ? Map<String, Object?>.from(
              (object['metadata'] as Map).cast<String, Object?>(),
            )
          : const <String, Object?>{}),
      'host_wall_id': spec.hostWall.objectId,
      'offset_meters': spec.offsetMeters,
      'width_meters': spec.widthMeters,
      'height_meters': spec.heightMeters,
      'sill_height_meters': spec.sillHeightMeters,
      'panel_thickness_meters': spec.panelThicknessMeters,
      'axis_start': spec.hostWall.geometry.start.toJson(),
      'axis_end': spec.hostWall.geometry.end.toJson(),
      'kind': kind,
    };
  }
}
