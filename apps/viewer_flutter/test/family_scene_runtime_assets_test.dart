import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_runtime/family_2d_asset_library.dart';
import 'package:viewer_flutter/src/family_runtime/family_scene_runtime_compiler.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

void main() {
  test('scene compiles one shared 2D asset for repeated family instances', () {
    const svg = '<svg><path d="M -0.3 -0.3 H 0.3 V 0.3 H -0.3 Z"/></svg>';
    final scene = _scene(<Map<String, Object?>>[
      _familyObject(id: 101, x: 2, svg: svg),
      _familyObject(id: 102, x: 8, svg: svg),
    ]);

    final runtime = FamilySceneRuntimeCompiler.compileRuntime(scene);

    expect(runtime.store.length, 2);
    expect(runtime.store.geometryVariants, hasLength(1));
    expect(runtime.twoDimensionalAssets.length, 1);

    final variant = runtime.store.geometryVariants.single;
    final descriptor = variant.representations.plan;
    expect(descriptor, isNotNull);
    final asset = runtime.twoDimensionalAssets[descriptor!.assetKey];
    expect(asset, isNotNull);
    expect(asset!.paths, hasLength(1));
    expect(asset.paths.single.opcodes, <int>[
      Family2dPathOpcode.moveTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.close,
    ]);
  });

  test('unsupported SVG stays out of compiled library without losing instance', () {
    const svg = '<svg><path d="M0 0 C1 0 1 1 2 1"/></svg>';
    final scene = _scene(<Map<String, Object?>>[
      _familyObject(id: 201, x: 2, svg: svg),
    ]);

    final runtime = FamilySceneRuntimeCompiler.compileRuntime(scene);

    expect(runtime.store.length, 1);
    expect(runtime.twoDimensionalAssets.isEmpty, isTrue);
    // The representation descriptor remains view-scoped. The viewport sees a
    // cache miss and deliberately uses its cheap generated/bounds fallback;
    // it never loads the detailed 3D family mesh just to draw this plan.
    expect(runtime.store.geometryVariants.single.representations.plan, isNotNull);
  });
}

RenderScene _scene(List<Map<String, Object?>> objects) {
  final result = parseRenderSceneJson(
    jsonEncode(<String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': objects.length,
      'vertex_count': 0,
      'index_count': 0,
      'bounds': _bounds(0, 0, 0, 12, 4, 3),
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
    source: 'family scene runtime asset test',
  );
  expect(result.errors, isEmpty);
  return result.scene!;
}

Map<String, Object?> _familyObject({
  required int id,
  required double x,
  required String svg,
}) =>
    <String, Object?>{
      'element_id': id,
      'kind': 'Proxy',
      'level_id': 1,
      'selectable': true,
      'visible_by_default': true,
      'revision': 1,
      'bounds': _bounds(x - 0.3, 1.7, 0, x + 0.3, 2.3, 0.9),
      'mesh': <String, Object?>{
        'positions': const <Object?>[],
        'indices': const <Object?>[],
      },
      'material_category': 'furniture',
      'metadata': <String, Object?>{
        'family_asset_id': 'builtin:chair',
        'family_type_id': 'Chair 600',
        'family_category': 'furniture',
        'family_parameter_values_json': '{"width":0.6,"depth":0.6}',
        'family_plan_svg': svg,
      },
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
