import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('bundled Family shadows legacy definition with the same stable id', () {
    final legacy = _family(name: 'Legacy', width: 1.0);
    final bundled = _family(name: 'Bundled', width: 2.0);

    final seeds = FamilyFileStore.composeSeedCatalog(
      legacy: <FamilyDocument>[legacy],
      bundled: <FamilyDocument>[bundled],
    );

    expect(seeds, hasLength(1));
    expect(seeds.single.name, 'Bundled');
    expect(seeds.single.types.single.values['width'], 2.0);
  });

  test('conflicting duplicate bundled ids are rejected', () {
    final first = _family(name: 'First bundle', width: 1.0);
    final second = _family(name: 'Second bundle', width: 1.5);

    expect(
      () => FamilyFileStore.composeSeedCatalog(
        legacy: const <FamilyDocument>[],
        bundled: <FamilyDocument>[first, second],
      ),
      throwsFormatException,
    );
  });
}

FamilyDocument _family({required String name, required double width}) {
  return FamilyDocument(
    id: 'shared-family-id',
    name: name,
    category: FamilyCategory.genericModel,
    parameters: <FamilyParameterDefinition>[
      FamilyParameterDefinition(
        id: 'width',
        label: 'Width',
        kind: FamilyParameterKind.length,
        defaultValue: width,
        minimum: 0.01,
      ),
      const FamilyParameterDefinition(
        id: 'depth',
        label: 'Depth',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      ),
      const FamilyParameterDefinition(
        id: 'height',
        label: 'Height',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      ),
    ],
    types: <FamilyTypeDefinition>[
      FamilyTypeDefinition(
        id: 'type-default',
        name: 'Default',
        values: <String, Object?>{
          'width': width,
          'depth': 1.0,
          'height': 1.0,
        },
      ),
    ],
    features: const <FamilyFeature>[
      FamilyFeature(
        id: 'feature-box',
        kind: FamilyFeatureKind.box,
        parameters: <String, Object?>{
          'width': 'width',
          'depth': 'depth',
          'height': 'height',
        },
      ),
    ],
  );
}
