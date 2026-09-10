import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/authoring/application/roof/automatic_flat_roof_planner.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

RenderScene _scene({bool withRoof = false, bool explicitTopLevels = true}) {
  final result = parseRenderSceneJson(
    '''{
      "scene_version": 1,
      "objects": [
        {
          "element_id": 1,
          "kind": "Wall",
          "level_id": 10,
          "bounds": {"min": [0,0,0], "max": [4,0.3,3]},
          "mesh": {"positions": [], "indices": []},
          "metadata": {"base_level_id": 10${explicitTopLevels ? ', "top_level_id": 20' : ''}}
        },
        {
          "element_id": 2,
          "kind": "Wall",
          "level_id": 10,
          "bounds": {"min": [0,0,0], "max": [0.3,4,3]},
          "mesh": {"positions": [], "indices": []},
          "metadata": {"base_level_id": 10${explicitTopLevels ? ', "top_level_id": 20' : ''}}
        },
        {
          "element_id": 3,
          "kind": "Wall",
          "level_id": 10,
          "bounds": {"min": [0,0,0], "max": [4,0.3,6]},
          "mesh": {"positions": [], "indices": []},
          "metadata": {"base_level_id": 10${explicitTopLevels ? ', "top_level_id": 30' : ''}}
        }
        ${withRoof ? ', {"element_id": 9, "kind": "Roof", "level_id": 30, "bounds": {"min": [0,0,6], "max": [4,4,6.3]}, "mesh": {"positions": [], "indices": []}}' : ''}
      ],
      "levels": [
        {"level_id": 10, "name": "Ground", "elevation_meters": 0.0, "default_wall_height_meters": 3.0},
        {"level_id": 20, "name": "Level 2", "elevation_meters": 3.0, "default_wall_height_meters": 3.0},
        {"level_id": 30, "name": "Roof", "elevation_meters": 6.0, "default_wall_height_meters": 3.0}
      ],
      "materials": [],
      "sections": []
    }''',
    source: 'automatic roof planner test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}

void main() {
  test('explicit wall constraints choose the highest authored top level', () {
    final plan = AutomaticFlatRoofPlanner.plan(
      scene: _scene(),
      baseLevelId: 10,
    );

    expect(plan, isNotNull);
    expect(plan!.roofLevelId, 30);
    expect(plan.boundWalls.map((wall) => wall.elementId), <int?>[3]);
    expect(plan.existingRoof, isFalse);
  });

  test('duplicate roof is reported without changing wall selection', () {
    final plan = AutomaticFlatRoofPlanner.plan(
      scene: _scene(withRoof: true),
      baseLevelId: 10,
    );

    expect(plan, isNotNull);
    expect(plan!.roofLevelId, 30);
    expect(plan.existingRoof, isTrue);
    expect(plan.boundWalls.map((wall) => wall.elementId), <int?>[3]);
  });

  test('without explicit wall tops the nearest higher level is the target', () {
    final plan = AutomaticFlatRoofPlanner.plan(
      scene: _scene(explicitTopLevels: false),
      baseLevelId: 10,
    );

    expect(plan, isNotNull);
    expect(plan!.roofLevelId, 20);
    // Preserve the current workflow contract: automatic footprint geometry
    // still requires walls explicitly bound to the chosen top level.
    expect(plan.boundWalls, isEmpty);
  });

  test('topmost base level has no automatic roof target', () {
    final plan = AutomaticFlatRoofPlanner.plan(
      scene: _scene(),
      baseLevelId: 30,
    );

    expect(plan, isNull);
  });
}
