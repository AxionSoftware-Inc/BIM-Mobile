import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_runtime/family_scene_runtime_compiler.dart';
import 'package:viewer_flutter/src/family_runtime/family_representation.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

void main() {
  test('scene family metadata compiles to shared runtime variants', () {
    final scene = parseRenderSceneJson(jsonEncode(<String, Object?>{
      'bounds': <String, Object?>{
        'min': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
        'max': <String, Object?>{'x': 4, 'y': 2, 'z': 1},
      },
      'levels': <Object?>[
        <String, Object?>{
          'level_id': 1,
          'name': 'Level 1',
          'elevation_meters': 0,
          'default_wall_height_meters': 3,
        },
      ],
      'objects': <Object?>[
        _familyObject(
          id: 10,
          minX: 0,
          maxX: 1,
          parameters: '{"width":0.8,"depth":0.8}',
        ),
        _familyObject(
          id: 11,
          minX: 2,
          maxX: 3,
          // Different JSON key order must still intern the same variant.
          parameters: '{"depth":0.8,"width":0.8}',
        ),
      ],
    })).scene!;

    final store = FamilySceneRuntimeCompiler.compile(scene);

    expect(store.length, 2);
    expect(store.definitions, hasLength(1));
    expect(store.types, hasLength(1));
    expect(store.geometryVariants, hasLength(1));
    expect(store.geometryVariantIds.toSet(), <int>{0});
    expect(
      store.geometryVariants.single.representations.model3d?.geometryVariantId,
      0,
    );
    expect(
      store.geometryVariants.single.representations.plan?.encoding,
      Family2dEncoding.svg,
    );
  });

  test('objects without family reference do not enter family runtime', () {
    final scene = parseRenderSceneJson(jsonEncode(<String, Object?>{
      'bounds': <String, Object?>{
        'min': <String, Object?>{'x': 0, 'y': 0, 'z': 0},
        'max': <String, Object?>{'x': 1, 'y': 1, 'z': 1},
      },
      'levels': const <Object?>[],
      'objects': <Object?>[
        <String, Object?>{
          'element_id': 1,
          'kind': 'Wall',
          'level_id': 0,
          'bounds': _bounds(0, 1),
          'mesh': const <String, Object?>{
            'positions': <Object?>[],
            'indices': <Object?>[],
          },
          'material_category': 'wall',
        },
      ],
    })).scene!;

    expect(FamilySceneRuntimeCompiler.compile(scene).isEmpty, isTrue);
  });
}

Map<String, Object?> _familyObject({
  required int id,
  required double minX,
  required double maxX,
  required String parameters,
}) =>
    <String, Object?>{
      'element_id': id,
      'kind': 'GenericModel',
      'level_id': 1,
      'bounds': <String, Object?>{
        'min': <String, Object?>{'x': minX, 'y': 0, 'z': 0},
        'max': <String, Object?>{'x': maxX, 'y': 1, 'z': 1},
      },
      'mesh': const <String, Object?>{
        'positions': <Object?>[],
        'indices': <Object?>[],
      },
      'material_category': 'generic',
      'metadata': <String, Object?>{
        'family_asset_id': 'chair-family',
        'family_type_id': 'chair-800',
        'family_category': 'furniture',
        'family_parameter_values_json': parameters,
        'family_plan_svg': '<svg><path d="M0 0h1v1z"/></svg>',
      },
    };

Map<String, Object?> _bounds(double min, double max) => <String, Object?>{
      'min': <String, Object?>{'x': min, 'y': min, 'z': min},
      'max': <String, Object?>{'x': max, 'y': max, 'z': max},
    };
