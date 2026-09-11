import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/schedules/application/bim_compact_estimator.dart';
import 'package:viewer_flutter/src/features/viewer/application/runtime/bim_compact_instance_store.dart';
import 'package:viewer_flutter/src/features/schedules/application/render_scene_estimator.dart';
import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';

void main() {
  test('compact store deduplicates repeated wall prototypes', () {
    final scene = _scene();
    final compact = BimCompactInstanceStore.fromScene(scene);

    expect(compact.walls.length, 2);
    expect(
      compact.prototypes
          .where((prototype) => prototype.kind == BimCompactKind.wall),
      hasLength(1),
    );
    expect(compact.instances.bounds.length, compact.instanceCount * 6);
  });

  test('compact estimator matches legacy estimator quantities', () {
    final scene = _scene();
    final legacy = RenderSceneEstimator.summarize(scene);
    final compact = BimCompactEstimator.summarize(
      BimCompactInstanceStore.fromScene(scene),
    );

    expect(compact.roomCount, legacy.roomCount);
    expect(compact.wallCount, legacy.wallCount);
    expect(compact.doorCount, legacy.doorCount);
    expect(compact.windowCount, legacy.windowCount);
    expect(compact.floorCount, legacy.floorCount);
    expect(compact.ceilingCount, legacy.ceilingCount);
    // Compact semantic columns intentionally use Float32 for bounded local BIM
    // dimensions. Allow the documented conversion error when comparing them
    // with the legacy double-backed object graph.
    const compactTolerance = 1e-6;
    expect(
        compact.totalRoomArea, closeTo(legacy.totalRoomArea, compactTolerance));
    expect(compact.wallGrossVolume,
        closeTo(legacy.wallGrossVolume, compactTolerance));
    expect(
        compact.wallNetVolume, closeTo(legacy.wallNetVolume, compactTolerance));
    expect(compact.wallNetArea, closeTo(legacy.wallNetArea, compactTolerance));
    expect(compact.floorArea, closeTo(legacy.floorArea, compactTolerance));
    expect(
      compact.floorConcreteVolume,
      closeTo(legacy.floorConcreteVolume, compactTolerance),
    );
    expect(compact.ceilingArea, closeTo(legacy.ceilingArea, compactTolerance));
    expect(compact.openingArea, closeTo(legacy.openingArea, compactTolerance));
    expect(compact.totalCost, closeTo(legacy.totalCost, compactTolerance));
  });
}

RenderScene _scene() {
  final objects = <Map<String, Object?>>[
    _object(
      id: 1,
      kind: 'Wall',
      level: 1,
      bounds: _bounds(0, 0, 0, 10, 0.2, 3),
      metadata: <String, Object?>{
        'wall_type_id': 7,
        'length_meters': 10.0,
        'thickness_meters': 0.2,
        'height_meters': 3.0,
      },
    ),
    _object(
      id: 2,
      kind: 'Wall',
      level: 1,
      bounds: _bounds(0, 4, 0, 8, 4.2, 3),
      metadata: <String, Object?>{
        'wall_type_id': 7,
        'length_meters': 8.0,
        'thickness_meters': 0.2,
        'height_meters': 3.0,
      },
    ),
    _object(
      id: 3,
      kind: 'Door',
      level: 1,
      bounds: _bounds(2, 0, 0, 3, 0.2, 2.1),
      metadata: <String, Object?>{
        'host_wall_id': 1,
        'width_meters': 1.0,
        'height_meters': 2.1,
      },
    ),
    _object(
      id: 4,
      kind: 'Window',
      level: 1,
      bounds: _bounds(5, 0, 0.9, 6.5, 0.2, 2.1),
      metadata: <String, Object?>{
        'host_wall_id': 1,
        'width_meters': 1.5,
        'height_meters': 1.2,
        'sill_height_meters': 0.9,
      },
    ),
    _object(
      id: 5,
      kind: 'Floor',
      level: 1,
      bounds: _bounds(0, 0, 0, 10, 8, 0.25),
      metadata: <String, Object?>{
        'assembly_id': 4,
        'area_m2': 80.0,
        'thickness_meters': 0.25,
      },
    ),
    _object(
      id: 6,
      kind: 'Ceiling',
      level: 1,
      bounds: _bounds(0, 0, 2.95, 10, 8, 3),
      metadata: <String, Object?>{
        'assembly_id': 5,
        'area_m2': 80.0,
        'thickness_meters': 0.05,
      },
    ),
    _object(
      id: 7,
      kind: 'Room',
      level: 1,
      bounds: _bounds(0, 0, 0, 10, 8, 0.02),
      metadata: <String, Object?>{
        'area_m2': 80.0,
        'perimeter_m': 36.0,
      },
    ),
  ];

  final result = parseRenderSceneJson(
    jsonEncode(<String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': objects.length,
      'vertex_count': 0,
      'index_count': 0,
      'bounds': _bounds(0, 0, 0, 10, 8, 3),
      'levels': <Object?>[
        <String, Object?>{
          'level_id': 1,
          'name': 'Level 1',
          'elevation_meters': 0.0,
          'default_wall_height_meters': 3.0,
        }
      ],
      'materials': const <Object?>[],
      'sections': const <Object?>[],
      'objects': objects,
    }),
    source: 'compact estimator test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}

Map<String, Object?> _object({
  required int id,
  required String kind,
  required int level,
  required Map<String, Object?> bounds,
  required Map<String, Object?> metadata,
}) {
  return <String, Object?>{
    'element_id': id,
    'kind': kind,
    'level_id': level,
    'selectable': true,
    'visible_by_default': true,
    'revision': 1,
    'bounds': bounds,
    'mesh': <String, Object?>{
      'positions': const <Object?>[],
      'indices': const <Object?>[],
    },
    'material_category': 'generic',
    'metadata': metadata,
  };
}

Map<String, Object?> _bounds(
  double minX,
  double minY,
  double minZ,
  double maxX,
  double maxY,
  double maxZ,
) {
  return <String, Object?>{
    'min': <String, double>{'x': minX, 'y': minY, 'z': minZ},
    'max': <String, double>{'x': maxX, 'y': maxY, 'z': maxZ},
  };
}
