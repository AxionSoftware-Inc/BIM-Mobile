import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/viewer/application/viewport/viewer_viewport_scene_policy.dart';
import 'package:viewer_flutter/src/features/viewer/domain/view/view_configuration.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

RenderScene _scene() {
  final result = parseRenderSceneJson(
    '''{
      "scene_version": 1,
      "objects": [],
      "levels": [
        {"level_id": 10, "name": "Ground", "elevation_meters": 0.0, "default_wall_height_meters": 3.1},
        {"level_id": 20, "name": "Level 2", "elevation_meters": 3.4, "default_wall_height_meters": 3.0},
        {"level_id": 30, "name": "Roof", "elevation_meters": 7.0, "default_wall_height_meters": 2.8}
      ],
      "materials": [],
      "sections": []
    }''',
    source: 'viewport policy test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}

void main() {
  test('level resolution preserves a valid preferred level', () {
    final scene = _scene();
    const policy = ViewerViewportScenePolicy(
      projectionMode: RenderSceneProjectionMode.topDown,
      activeLevelId: 20,
    );

    expect(policy.resolveInitialLevelId(scene, preferred: 30), 30);
    expect(policy.resolveInitialLevelId(scene, preferred: 999), 10);
    expect(policy.activeLevel(scene)?.levelId, 20);
    expect(policy.activeLevelElevation(scene), 3.4);
    expect(
      policy.activeLevelDefaultWallHeight(scene, fallbackMeters: 9.0),
      3.0,
    );
  });

  test('nextHigherLevel follows elevation instead of list position', () {
    final scene = _scene();
    const policy = ViewerViewportScenePolicy(
      projectionMode: RenderSceneProjectionMode.topDown,
      activeLevelId: 10,
    );

    expect(policy.nextHigherLevel(scene, 10)?.levelId, 20);
    expect(policy.nextHigherLevel(scene, 20)?.levelId, 30);
    expect(policy.nextHigherLevel(scene, 30), isNull);
    expect(policy.nextHigherLevel(scene, 999), isNull);
  });

  test('plan/elevation views can resolve a nearby level by model elevation', () {
    final scene = _scene();
    const planPolicy = ViewerViewportScenePolicy(
      projectionMode: RenderSceneProjectionMode.topDown,
      activeLevelId: 10,
    );
    const orbitPolicy = ViewerViewportScenePolicy(
      projectionMode: RenderSceneProjectionMode.isometric,
      activeLevelId: 10,
    );
    const point = RenderScenePoint(x: 0.0, y: 0.0, z: 3.35);

    expect(
      planPolicy.pickLevelAtElevation(
        scene,
        point,
        toleranceMeters: 0.2,
      )?.levelId,
      20,
    );
    expect(
      orbitPolicy.pickLevelAtElevation(
        scene,
        point,
        toleranceMeters: 0.2,
      ),
      isNull,
    );
  });
}
