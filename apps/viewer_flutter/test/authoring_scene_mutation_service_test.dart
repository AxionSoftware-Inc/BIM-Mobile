import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/authoring/application/scene_mutation_service.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/tools/wall_authoring_geometry.dart';

void main() {
  test('local wall mutation returns a verified created element', () async {
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

    expect(outcome.success, isTrue);
    expect(outcome.scene, isNotNull);
    expect(outcome.createdElementId, isNotNull);
    expect(
      outcome.scene!.objectById(outcome.createdElementId!)?.kindKey,
      'wall',
    );
    expect(outcome.trace, isNotEmpty);
  });

  test('local curved wall mutation returns a verified created element',
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

    expect(outcome.success, isTrue);
    expect(outcome.scene, isNotNull);
    expect(outcome.createdElementId, isNotNull);
    expect(
      outcome.scene!.objectById(outcome.createdElementId!)?.kindKey,
      'wall',
    );
    expect(outcome.trace.any((entry) => entry.contains('curved wall')), isTrue);
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
