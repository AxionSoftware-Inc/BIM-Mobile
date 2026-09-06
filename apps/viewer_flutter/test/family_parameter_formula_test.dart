import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('schema v2 preserves formulas and resolves them into geometry', () {
    final starter = FamilyDocument.starter(name: 'Formula cabinet');
    final document = starter.copyWith(
      parameters: <FamilyParameterDefinition>[
        const FamilyParameterDefinition(
          id: 'width',
          label: 'Width',
          kind: FamilyParameterKind.length,
          defaultValue: 2.4,
          minimum: 0.01,
        ),
        const FamilyParameterDefinition(
          id: 'depth',
          label: 'Depth',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
          minimum: 0.01,
          formula: 'width / 2',
        ),
        const FamilyParameterDefinition(
          id: 'height',
          label: 'Height',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
          minimum: 0.01,
          formula: 'max(depth * 3, 2)',
        ),
      ],
      types: const <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'formula-type',
          name: 'Formula Type',
          values: <String, Object?>{
            'width': 2.4,
            // Formula targets deliberately contain stale snapshots. The
            // resolver must ignore these own-value overrides.
            'depth': 99.0,
            'height': 99.0,
          },
        ),
      ],
    );

    final restored = FamilyDocument.fromJson(document.toJson());
    expect(restored, isNotNull);
    final loaded = restored!;
    expect(loaded.schemaVersion, FamilyDocument.currentSchemaVersion);
    expect(loaded.parameters[1].formula, 'width / 2');
    expect(FamilyDocumentValidator.validate(loaded).isValid, isTrue);

    final resolver = FamilyParameterResolver(loaded, loaded.types.single);
    expect(resolver.resolveNumber('depth'), closeTo(1.2, 1e-9));
    expect(resolver.resolveNumber('height'), closeTo(3.6, 1e-9));

    final mesh = FamilyGeometryEvaluator.evaluateMesh(
      loaded,
      loaded.types.single,
    );
    final xs = mesh.vertices.map((vertex) => vertex.x).toList();
    final ys = mesh.vertices.map((vertex) => vertex.y).toList();
    final zs = mesh.vertices.map((vertex) => vertex.z).toList();
    expect(xs.reduce(_max) - xs.reduce(_min), closeTo(2.4, 1e-9));
    expect(ys.reduce(_max) - ys.reduce(_min), closeTo(3.6, 1e-9));
    expect(zs.reduce(_max) - zs.reduce(_min), closeTo(1.2, 1e-9));
  });

  test('schema v1 remains readable and upgrades on authoring edit', () {
    final legacyJson = FamilyDocument.starter().toJson()
      ..['schema_version'] = 1;
    final legacy = FamilyDocument.fromJson(legacyJson);
    expect(legacy, isNotNull);
    expect(legacy!.schemaVersion, 1);

    final edited = legacy.copyWith(name: 'Edited legacy family');
    expect(edited.schemaVersion, FamilyDocument.currentSchemaVersion);
    expect(FamilyDocumentValidator.validate(edited).isValid, isTrue);
  });

  test('future family schema is rejected instead of guessed', () {
    final futureJson = FamilyDocument.starter().toJson()
      ..['schema_version'] = FamilyDocument.currentSchemaVersion + 1;
    expect(FamilyDocument.fromJson(futureJson), isNull);
  });

  test('formula language supports arithmetic constants and safe functions', () {
    final starter = FamilyDocument.starter();
    final document = starter.copyWith(
      parameters: <FamilyParameterDefinition>[
        ...starter.parameters,
        const FamilyParameterDefinition(
          id: 'angle2',
          label: 'Angle 2',
          kind: FamilyParameterKind.angle,
          defaultValue: 90.0,
          formula: 'clamp(abs(-pi * 20), 10, 180)',
        ),
      ],
    );
    final resolver = FamilyParameterResolver(document, document.types.single);
    expect(resolver.resolveNumber('angle2'), closeTo(62.8318530718, 1e-8));
  });

  test('formula cycles are rejected before save or placement', () {
    final starter = FamilyDocument.starter();
    final document = starter.copyWith(
      parameters: const <FamilyParameterDefinition>[
        FamilyParameterDefinition(
          id: 'width',
          label: 'Width',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
          formula: 'depth + 1',
        ),
        FamilyParameterDefinition(
          id: 'depth',
          label: 'Depth',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
          formula: 'width + 1',
        ),
        FamilyParameterDefinition(
          id: 'height',
          label: 'Height',
          kind: FamilyParameterKind.length,
          defaultValue: 1.0,
        ),
      ],
    );
    final validation = FamilyDocumentValidator.validate(document);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('formula cycle')),
      isTrue,
    );
  });

  test('unknown formula parameters and division by zero are rejected', () {
    final starter = FamilyDocument.starter();
    final unknown = starter.copyWith(
      parameters: <FamilyParameterDefinition>[
        starter.parameters[0].copyWith(formula: 'missing_parameter * 2'),
        ...starter.parameters.skip(1),
      ],
    );
    expect(FamilyDocumentValidator.validate(unknown).isValid, isFalse);

    final divideByZero = starter.copyWith(
      parameters: <FamilyParameterDefinition>[
        starter.parameters[0].copyWith(formula: '1 / (depth - depth)'),
        ...starter.parameters.skip(1),
      ],
    );
    final validation = FamilyDocumentValidator.validate(divideByZero);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('Division by zero')),
      isTrue,
    );
  });

  test('duplicate type names and forward feature references are rejected', () {
    final starter = FamilyDocument.starter();
    final duplicateTypes = starter.copyWith(
      types: <FamilyTypeDefinition>[
        starter.types.single,
        const FamilyTypeDefinition(
          id: 'type-two',
          name: 'default type',
          values: <String, Object?>{
            'width': 1.0,
            'depth': 1.0,
            'height': 1.0,
          },
        ),
      ],
    );
    expect(FamilyDocumentValidator.validate(duplicateTypes).isValid, isFalse);

    final forwardReference = starter.copyWith(
      features: const <FamilyFeature>[
        FamilyFeature(
          id: 'transform-first',
          kind: FamilyFeatureKind.transform,
          inputs: <String>['box-later'],
        ),
        FamilyFeature(
          id: 'box-later',
          kind: FamilyFeatureKind.box,
          parameters: <String, Object?>{
            'width': 'width',
            'depth': 'depth',
            'height': 'height',
          },
        ),
      ],
    );
    final validation = FamilyDocumentValidator.validate(forwardReference);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('earlier feature')),
      isTrue,
    );
  });

  test('plan symbol reads the same formula-resolved dimensions as 3D', () {
    final starter = FamilyDocument.starter();
    final document = starter.copyWith(
      parameters: <FamilyParameterDefinition>[
        starter.parameters[0],
        starter.parameters[1].copyWith(formula: 'width * 0.25'),
        starter.parameters[2],
      ],
      types: <FamilyTypeDefinition>[
        starter.types.single.copyWith(values: <String, Object?>{
          ...starter.types.single.values,
          'width': 4.0,
        }),
      ],
    );
    final svg = FamilyPlanSymbolGenerator.svgFor(
      document,
      document.types.single,
    );
    expect(svg, contains('4.0 1.0'));
  });
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
