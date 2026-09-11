import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_2d_asset_library.dart';

void main() {
  test('compiles repeated and relative SVG line commands once', () {
    final paths = Family2dSvgCompiler.compile(
      '<svg><path d="M 0 0 1 0 1 1 l -1 0 z"/></svg>',
    );

    expect(paths.length, 1);
    final path = paths.single;
    expect(path.opcodes, <int>[
      Family2dPathOpcode.moveTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.lineTo,
      Family2dPathOpcode.close,
    ]);
    expect(path.coordinates[0], closeTo(0, 1e-6));
    expect(path.coordinates[1], closeTo(0, 1e-6));
    expect(path.coordinates[2], closeTo(1, 1e-6));
    expect(path.coordinates[3], closeTo(0, 1e-6));
    expect(path.coordinates[6], closeTo(0, 1e-6));
    expect(path.coordinates[7], closeTo(1, 1e-6));
  });

  test('supports horizontal and vertical architectural path commands', () {
    final paths = Family2dSvgCompiler.compile(
      '<svg><path d="M0 0 H2 V3 h-2 Z"/></svg>',
    );

    expect(paths.single.opcodes.length, 5);
    expect(paths.single.coordinates[2], closeTo(2, 1e-6));
    expect(paths.single.coordinates[5], closeTo(3, 1e-6));
    expect(paths.single.coordinates[6], closeTo(0, 1e-6));
    expect(paths.single.coordinates[7], closeTo(3, 1e-6));
  });

  test('unsupported curves stay on cheap generated fallback path', () {
    final paths = Family2dSvgCompiler.compile(
      '<svg><path d="M0 0 C1 0 1 1 2 1"/></svg>',
    );
    expect(paths, isEmpty);
  });

  test('library interns one compiled asset per stable key', () {
    final builder = Family2dAssetLibraryBuilder();
    builder.addSvg(assetKey: 'svg:chair', svg: '<path d="M0 0 L1 0"/>');
    builder.addSvg(assetKey: 'svg:chair', svg: '<path d="M9 9 L10 10"/>');
    final library = builder.build();

    expect(library.length, 1);
    expect(library['svg:chair']?.paths.single.coordinates[0], closeTo(0, 1e-6));
  });
}
