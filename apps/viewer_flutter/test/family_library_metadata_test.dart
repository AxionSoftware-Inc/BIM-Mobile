import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('starter Family reports deterministic parametric metadata', () {
    final document = FamilyDocument.starter(name: 'Starter');
    final metadata = FamilyLibraryMetadata.fromDocument(document);

    expect(metadata.typeCount, 1);
    expect(metadata.parameterCount, 3);
    expect(metadata.featureCount, 1);
    expect(metadata.parametricFeatureCount, 1);
    expect(metadata.hasFreeformMesh, isFalse);
    expect(metadata.isParametric, isTrue);
    expect(metadata.capabilityLabels, <String>['1 type', 'Parametric']);
  });

  test('metadata summarizes formulas constraints nested booleans and meshes', () {
    final base = FamilyDocument.starter(name: 'Capabilities');
    final formula = FamilyParameterDefinition(
      id: 'half_width',
      label: 'Half width',
      kind: FamilyParameterKind.length,
      defaultValue: 0.5,
      formula: 'width / 2',
    );
    final document = base.copyWith(
      parameters: <FamilyParameterDefinition>[...base.parameters, formula],
      types: <FamilyTypeDefinition>[
        ...base.types,
        FamilyTypeDefinition(
          id: 'type-2',
          name: 'Second',
          values: Map<String, Object?>.from(base.types.single.values),
        ),
      ],
      features: <FamilyFeature>[
        ...base.features,
        const FamilyFeature(
          id: 'mesh',
          kind: FamilyFeatureKind.freeformMesh,
          parameters: <String, Object?>{
            'vertices': <List<double>>[
              <double>[0, 0, 0],
              <double>[1, 0, 0],
              <double>[0, 1, 0],
            ],
            'faces': <List<int>>[
              <int>[0, 1, 2],
            ],
          },
        ),
        const FamilyFeature(
          id: 'union',
          kind: FamilyFeatureKind.booleanUnion,
          inputs: <String>['feature-1', 'mesh'],
        ),
        const FamilyFeature(
          id: 'nested',
          kind: FamilyFeatureKind.nestedFamily,
          parameters: <String, Object?>{
            'familyId': 'child-family',
            'typeId': 'child-type',
          },
        ),
      ],
    );

    final metadata = FamilyLibraryMetadata.fromDocument(document);
    expect(metadata.typeCount, 2);
    expect(metadata.formulaCount, 1);
    expect(metadata.freeformMeshCount, 1);
    expect(metadata.booleanCount, 1);
    expect(metadata.nestedFamilyCount, 1);
    expect(
      metadata.capabilityLabels,
      containsAll(<String>['2 types', 'Multi-type', '1 formula', 'Nested', 'Boolean', 'Mesh']),
    );
  });
}
