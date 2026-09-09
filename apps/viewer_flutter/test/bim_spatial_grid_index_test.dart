import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/bim_compact_instance_store.dart';
import 'package:viewer_flutter/src/bim_spatial_grid_index.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

void main() {
  test('multi-cell instances are returned once from CSR queries', () {
    final store = BimCompactInstanceStore.fromScene(
      _scene(<Map<String, Object?>>[
        _object(1, _bounds(0, 0, 0, 40, 2, 3)),
      ]),
    );
    final index = BimSpatialGridIndex.build(
      store,
      cellSizeX: 10,
      cellSizeY: 10,
      cellSizeZ: 10,
    );

    final result = index.queryAabb(
      minX: -1,
      minY: -1,
      minZ: -1,
      maxX: 41,
      maxY: 3,
      maxZ: 4,
    );

    expect(result, orderedEquals(<int>[0]));
    expect(index.instanceIndices.length, greaterThan(1));
  });

  test('very large proxy-style bounds use only their center cell', () {
    final store = BimCompactInstanceStore.fromScene(
      _scene(<Map<String, Object?>>[
        _object(1, _bounds(-1000, -1000, -100, 1000, 1000, 100)),
      ]),
    );
    final index = BimSpatialGridIndex.build(
      store,
      cellSizeX: 10,
      cellSizeY: 10,
      cellSizeZ: 10,
    );

    expect(index.instanceIndices, hasLength(1));
    expect(
      index.queryAabb(
        minX: -5,
        minY: -5,
        minZ: -5,
        maxX: 5,
        maxY: 5,
        maxZ: 5,
      ),
      orderedEquals(<int>[0]),
    );
    expect(
      index.queryAabb(
        minX: 900,
        minY: 900,
        minZ: 0,
        maxX: 910,
        maxY: 910,
        maxZ: 10,
      ),
      isEmpty,
    );
  });

  test('camera query rejects far rear candidates but keeps near objects', () {
    final store = BimCompactInstanceStore.fromScene(
      _scene(<Map<String, Object?>>[
        _object(1, _bounds(20, 0, 0, 21, 1, 1)),
        _object(2, _bounds(-21, 0, 0, -20, 1, 1)),
        _object(3, _bounds(-2, 0, 0, -1, 1, 1)),
      ]),
    );
    final index = BimSpatialGridIndex.build(
      store,
      cellSizeX: 8,
      cellSizeY: 8,
      cellSizeZ: 8,
    );

    final result = index.queryCameraNeighborhood(
      store,
      cameraX: 0,
      cameraY: 0,
      cameraZ: 0,
      forwardX: 1,
      forwardY: 0,
      forwardZ: 0,
      radiusMeters: 100,
      alwaysKeepMeters: 5,
      rearDotThreshold: -0.12,
    );

    expect(result, contains(0));
    expect(result, isNot(contains(1)));
    expect(result, contains(2));
  });
}

RenderScene _scene(List<Map<String, Object?>> objects) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  var maxZ = double.negativeInfinity;
  for (final object in objects) {
    final bounds = object['bounds']! as Map<String, Object?>;
    final min = bounds['min']! as Map<String, double>;
    final max = bounds['max']! as Map<String, double>;
    if (min['x']! < minX) minX = min['x']!;
    if (min['y']! < minY) minY = min['y']!;
    if (min['z']! < minZ) minZ = min['z']!;
    if (max['x']! > maxX) maxX = max['x']!;
    if (max['y']! > maxY) maxY = max['y']!;
    if (max['z']! > maxZ) maxZ = max['z']!;
  }

  final result = parseRenderSceneJson(
    jsonEncode(<String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': objects.length,
      'vertex_count': 0,
      'index_count': 0,
      'bounds': _bounds(minX, minY, minZ, maxX, maxY, maxZ),
      'levels': <Object?>[
        <String, Object?>{
          'level_id': 1,
          'name': 'Level 1',
          'elevation_meters': 0.0,
          'default_wall_height_meters': 3.0,
        },
      ],
      'materials': const <Object?>[],
      'sections': const <Object?>[],
      'objects': objects,
    }),
    source: 'spatial grid test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}

Map<String, Object?> _object(int id, Map<String, Object?> bounds) =>
    <String, Object?>{
      'element_id': id,
      'kind': 'Proxy',
      'level_id': 1,
      'selectable': true,
      'visible_by_default': true,
      'revision': 1,
      'bounds': bounds,
      'mesh': <String, Object?>{
        'positions': const <Object?>[],
        'indices': const <Object?>[],
      },
      'material_category': 'generic',
      'metadata': const <String, Object?>{},
    };

Map<String, Object?> _bounds(
  double minX,
  double minY,
  double minZ,
  double maxX,
  double maxY,
  double maxZ,
) =>
    <String, Object?>{
      'min': <String, double>{'x': minX, 'y': minY, 'z': minZ},
      'max': <String, double>{'x': maxX, 'y': maxY, 'z': maxZ},
    };
