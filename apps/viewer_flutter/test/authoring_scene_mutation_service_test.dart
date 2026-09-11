import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/authoring/application/scene_mutation_service.dart';
import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/wall_authoring_geometry.dart';

void main() {
  test('wall mutation rejects a non-authoritative local fallback', () async {
    final scene = _emptyScene();
    const service = SceneMutationService();

    final outcome = await service.createWall(
      CreateWallRequest(
        scene: scene,
        start: const RenderScenePoint(x: 0, y: 0, z: 0),
        end: const RenderScenePoint(x: 5, y: 0, z: 0),
        baseLevelId: 1,
        topLevelId: 0,
        heightMeters: 3,
        thicknessMeters: 0.2,
      ),
    );

    expect(outcome.success, isFalse);
    expect(outcome.scene, same(scene));
    expect(outcome.createdElementId, isNull);
    expect(outcome.scene!.objects, isEmpty);
    expect(outcome.error, contains('Authoritative engine'));
    expect(
      outcome.trace.any((entry) => entry.contains('mutation rejected')),
      isTrue,
    );
  });

  test('curved wall mutation rejects a non-authoritative local fallback',
      () async {
    final scene = _emptyScene();
    const service = SceneMutationService();
    final geometry = WallAuthoringGeometry.arcFromThreePoints(
      first: const RenderScenePoint(x: 0, y: 0, z: 0),
      second: const RenderScenePoint(x: 4, y: 0, z: 0),
      bend: const RenderScenePoint(x: 2, y: 1, z: 0),
    );
    expect(geometry, isNotNull);

    final outcome = await service.createCurvedWall(
      CreateCurvedWallRequest(
        scene: scene,
        geometry: geometry!,
        baseLevelId: 1,
        topLevelId: 0,
        heightMeters: 3,
        thicknessMeters: 0.2,
      ),
    );

    expect(outcome.success, isFalse);
    expect(outcome.scene, same(scene));
    expect(outcome.createdElementId, isNull);
    expect(outcome.scene!.objects, isEmpty);
    expect(outcome.error, contains('Authoritative engine'));
    expect(
      outcome.trace.any((entry) => entry.contains('mutation rejected')),
      isTrue,
    );
  });
}

RenderScene _emptyScene() {
  final result = parseRenderSceneJson(
    jsonEncode(<String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': 0,
      'vertex_count': 0,
      'index_count': 0,
      'bounds': <String, Object?>{
        'min': <String, double>{'x': -10, 'y': -10, 'z': 0},
        'max': <String, double>{'x': 10, 'y': 10, 'z': 3},
      },
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
      'objects': const <Object?>[],
    }),
    source: 'scene mutation service test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}
