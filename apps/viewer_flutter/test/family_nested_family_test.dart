import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('nested family resolves child type into real parent geometry', () {
    final child = _boxFamily(
      id: 'child',
      name: 'Child',
      width: 2,
      depth: 1,
      height: 3,
    );
    final parent = _nestedParent(
      childId: child.id,
      childTypeId: child.types.single.id,
    );

    final resolved = FamilyDependencyResolver.resolve(
      parent,
      parent.types.single,
      availableDocuments: <FamilyDocument>[parent, child],
    );

    expect(
      resolved.features.any(
        (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
      ),
      isFalse,
    );
    final nestedMesh = resolved.features.singleWhere(
      (feature) => feature.parameters['sourceFormat'] == 'nestedFamily',
    );
    expect(nestedMesh.kind, FamilyFeatureKind.freeformMesh);
    expect(nestedMesh.parameters['nestedFamilyId'], child.id);
    expect(nestedMesh.parameters['nestedTypeId'], child.types.single.id);

    final mesh = FamilyGeometryEvaluator.evaluateMesh(
      resolved,
      parent.types.single,
    );
    expect(mesh.vertices, isNotEmpty);
    expect(mesh.faces, isNotEmpty);
  });

  test('nested transform can use parent Family Type expressions', () {
    final child = _boxFamily(
      id: 'child-transform',
      name: 'Child transform',
      width: 1,
      depth: 1,
      height: 1,
    );
    final parent = _nestedParent(
      childId: child.id,
      childTypeId: child.types.single.id,
      translationX: 'offset',
      extraParameter: const FamilyParameterDefinition(
        id: 'offset',
        label: 'Offset',
        kind: FamilyParameterKind.number,
        defaultValue: 2.0,
      ),
      extraValue: 2.0,
    );

    final resolved = FamilyDependencyResolver.resolve(
      parent,
      parent.types.single,
      availableDocuments: <FamilyDocument>[parent, child],
    );
    final feature = resolved.features.singleWhere(
      (candidate) => candidate.parameters['sourceFormat'] == 'nestedFamily',
    );
    final vertices = feature.parameters['vertices'] as List;
    final xs = <double>[
      for (final raw in vertices) (raw as List).first as double,
    ];
    expect(xs.reduce((a, b) => a < b ? a : b), greaterThan(1.0));
  });

  test('nested rotation uses the Family vertical axis and transform direction', () {
    final child = _boxFamily(
      id: 'child-rotation',
      name: 'Child rotation',
      width: 2,
      depth: 1,
      height: 3,
    );
    final parent = _nestedParent(
      childId: child.id,
      childTypeId: child.types.single.id,
      rotationZ: 90.0,
    );

    final resolved = FamilyDependencyResolver.resolve(
      parent,
      parent.types.single,
      availableDocuments: <FamilyDocument>[parent, child],
    );
    final feature = resolved.features.singleWhere(
      (candidate) => candidate.parameters['sourceFormat'] == 'nestedFamily',
    );
    final vertices = feature.parameters['vertices'] as List;
    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    for (final raw in vertices) {
      final vertex = raw as List;
      xs.add(vertex[0] as double);
      ys.add(vertex[1] as double);
      zs.add(vertex[2] as double);
    }

    // Y is Family height/vertical and must remain untouched by yaw. The 90°
    // turn swaps the horizontal X/Z extents instead of tipping height into X.
    expect(ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        closeTo(3.0, 1e-9));
    expect(xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
        closeTo(1.0, 1e-9));
    expect(zs.reduce((a, b) => a > b ? a : b) - zs.reduce((a, b) => a < b ? a : b),
        closeTo(2.0, 1e-9));

    // The first source box vertex is (-1, 0, 0). Positive 90° must follow the
    // same yaw convention as Family transform nodes: it lands at (0, 0, 1).
    final first = vertices.first as List;
    expect(first[0] as double, closeTo(0.0, 1e-9));
    expect(first[1] as double, closeTo(0.0, 1e-9));
    expect(first[2] as double, closeTo(1.0, 1e-9));
  });

  test('missing child and missing child type are rejected', () {
    final parent = _nestedParent(childId: 'missing', childTypeId: 'type');
    expect(
      () => FamilyDependencyResolver.resolve(
        parent,
        parent.types.single,
        availableDocuments: <FamilyDocument>[parent],
      ),
      throwsFormatException,
    );

    final child = _boxFamily(
      id: 'known-child',
      name: 'Known child',
      width: 1,
      depth: 1,
      height: 1,
    );
    final wrongTypeParent = _nestedParent(
      childId: child.id,
      childTypeId: 'missing-type',
    );
    expect(
      () => FamilyDependencyResolver.resolve(
        wrongTypeParent,
        wrongTypeParent.types.single,
        availableDocuments: <FamilyDocument>[wrongTypeParent, child],
      ),
      throwsFormatException,
    );
  });

  test('nested dependency cycles are rejected deterministically', () {
    final aBase = FamilyDocument.starter(name: 'A');
    final bBase = FamilyDocument.starter(name: 'B');
    final a = FamilyDocument(
      id: 'a',
      name: 'A',
      category: FamilyCategory.genericModel,
      parameters: aBase.parameters,
      types: aBase.types,
      features: <FamilyFeature>[
        FamilyFeature(
          id: 'a-to-b',
          kind: FamilyFeatureKind.nestedFamily,
          parameters: <String, Object?>{
            'familyId': 'b',
            'typeId': bBase.types.single.id,
          },
        ),
      ],
    );
    final b = FamilyDocument(
      id: 'b',
      name: 'B',
      category: FamilyCategory.genericModel,
      parameters: bBase.parameters,
      types: bBase.types,
      features: <FamilyFeature>[
        FamilyFeature(
          id: 'b-to-a',
          kind: FamilyFeatureKind.nestedFamily,
          parameters: <String, Object?>{
            'familyId': 'a',
            'typeId': a.types.single.id,
          },
        ),
      ],
    );

    expect(
      () => FamilyDependencyResolver.resolve(
        a,
        a.types.single,
        availableDocuments: <FamilyDocument>[a, b],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cycle'),
        ),
      ),
    );
  });
}

FamilyDocument _boxFamily({
  required String id,
  required String name,
  required double width,
  required double depth,
  required double height,
}) {
  final starter = FamilyDocument.starter(name: name);
  return FamilyDocument(
    id: id,
    name: name,
    category: FamilyCategory.genericModel,
    parameters: starter.parameters,
    types: <FamilyTypeDefinition>[
      starter.types.single.copyWith(values: <String, Object?>{
        'width': width,
        'depth': depth,
        'height': height,
      }),
    ],
    features: starter.features,
  );
}

FamilyDocument _nestedParent({
  required String childId,
  required String childTypeId,
  Object? translationX,
  Object? rotationZ,
  FamilyParameterDefinition? extraParameter,
  Object? extraValue,
}) {
  final starter = FamilyDocument.starter(name: 'Parent');
  final parameters = <FamilyParameterDefinition>[
    ...starter.parameters,
    if (extraParameter != null) extraParameter,
  ];
  final type = starter.types.single.copyWith(values: <String, Object?>{
    ...starter.types.single.values,
    if (extraParameter != null) extraParameter.id: extraValue,
  });
  return FamilyDocument(
    id: 'parent-${childId.hashCode}-${childTypeId.hashCode}',
    name: 'Parent',
    category: FamilyCategory.genericModel,
    parameters: parameters,
    types: <FamilyTypeDefinition>[type],
    features: <FamilyFeature>[
      FamilyFeature(
        id: 'nested-child',
        kind: FamilyFeatureKind.nestedFamily,
        parameters: <String, Object?>{
          'familyId': childId,
          'typeId': childTypeId,
          if (translationX != null) 'translationX': translationX,
          if (rotationZ != null) 'rotationZ': rotationZ,
        },
      ),
    ],
  );
}
