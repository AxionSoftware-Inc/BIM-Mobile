import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  group('FamilyParameterAuthoring', () {
    test('adds a normal parameter and seeds every Family Type', () {
      var document = FamilyDocument.starter(name: 'Parameters');
      document = FamilyParameterAuthoring.duplicateType(
        document,
        sourceTypeId: document.types.single.id,
        name: 'Large',
      );

      final next = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Seat Depth',
        kind: FamilyParameterKind.length,
        defaultValue: 0.45,
        minimum: 0.1,
      );

      final parameter = next.parameters.singleWhere(
        (candidate) => candidate.label == 'Seat Depth',
      );
      expect(parameter.id, 'seat_depth');
      expect(parameter.kind, FamilyParameterKind.length);
      expect(parameter.minimum, 0.1);
      for (final type in next.types) {
        expect(type.values[parameter.id], 0.45);
      }
      expect(FamilyDocumentValidator.validate(next).isValid, isTrue);
    });

    test('formula parameter removes stale type overrides and resolves', () {
      var document = FamilyDocument.starter(name: 'Formula');
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Half Width',
        kind: FamilyParameterKind.length,
        defaultValue: 0.5,
      );
      final parameter = document.parameters.singleWhere(
        (candidate) => candidate.label == 'Half Width',
      );
      expect(document.types.single.values.containsKey(parameter.id), isTrue);

      final formulaDocument = FamilyParameterAuthoring.updateParameter(
        document,
        parameterId: parameter.id,
        formula: 'width / 2',
      );
      final formulaParameter = formulaDocument.parameters.singleWhere(
        (candidate) => candidate.id == parameter.id,
      );
      expect(formulaParameter.hasFormula, isTrue);
      expect(
        formulaDocument.types.single.values.containsKey(parameter.id),
        isFalse,
      );
      expect(
        FamilyParameterResolver(
          formulaDocument,
          formulaDocument.types.single,
        ).resolveNumber(parameter.id),
        closeTo(0.5, 1e-9),
      );
    });

    test('clearing a formula restores a concrete default to every type', () {
      var document = FamilyDocument.starter(name: 'Formula clear');
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Derived',
        kind: FamilyParameterKind.number,
        defaultValue: 4.0,
        formula: 'width * 2',
      );
      final id = document.parameters.last.id;
      expect(document.types.single.values.containsKey(id), isFalse);

      final cleared = FamilyParameterAuthoring.updateParameter(
        document,
        parameterId: id,
        clearFormula: true,
        defaultValue: 7.0,
      );
      expect(cleared.parameters.last.hasFormula, isFalse);
      expect(cleared.types.single.values[id], 7.0);
    });

    test('setTypeValue uses semantic validation and rejects formula overrides', () {
      var document = FamilyDocument.starter(name: 'Type values');
      final typeId = document.types.single.id;
      document = FamilyParameterAuthoring.setTypeValue(
        document,
        typeId: typeId,
        parameterId: 'width',
        value: 2.4,
      );
      expect(document.types.single.values['width'], 2.4);

      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Derived Width',
        kind: FamilyParameterKind.length,
        formula: 'width / 2',
      );
      final formulaId = document.parameters.last.id;
      expect(
        () => FamilyParameterAuthoring.setTypeValue(
          document,
          typeId: typeId,
          parameterId: formulaId,
          value: 3.0,
        ),
        throwsFormatException,
      );
    });

    test('referenced parameters and stable core dimensions cannot be removed', () {
      var document = FamilyDocument.starter(name: 'Removal safety');
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Offset',
        kind: FamilyParameterKind.number,
        defaultValue: 0.25,
      );
      final offsetId = document.parameters.last.id;
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Double Offset',
        kind: FamilyParameterKind.number,
        formula: '$offsetId * 2',
      );

      expect(
        () => FamilyParameterAuthoring.removeParameter(document, offsetId),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('parameter formula'),
          ),
        ),
      );
      expect(
        () => FamilyParameterAuthoring.removeParameter(document, 'width'),
        throwsFormatException,
      );
    });

    test('unused parameter removal migrates every type value map', () {
      var document = FamilyDocument.starter(name: 'Remove');
      document = FamilyParameterAuthoring.duplicateType(
        document,
        sourceTypeId: document.types.single.id,
        name: 'Second',
      );
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Unused',
        kind: FamilyParameterKind.number,
        defaultValue: 12,
      );
      final id = document.parameters.last.id;
      expect(document.types.every((type) => type.values.containsKey(id)), isTrue);

      final next = FamilyParameterAuthoring.removeParameter(document, id);
      expect(next.parameters.any((parameter) => parameter.id == id), isFalse);
      expect(next.types.every((type) => !type.values.containsKey(id)), isTrue);
    });

    test('duplicate and rename type preserve stable values and unique names', () {
      var document = FamilyDocument.starter(name: 'Types');
      final source = document.types.single;
      document = FamilyParameterAuthoring.duplicateType(
        document,
        sourceTypeId: source.id,
        name: 'Wide',
      );
      final wide = document.types.singleWhere((type) => type.name == 'Wide');
      expect(wide.id, isNot(source.id));
      expect(wide.values, source.values);

      document = FamilyParameterAuthoring.renameType(
        document,
        typeId: wide.id,
        name: 'Extra Wide',
      );
      expect(
        document.types.singleWhere((type) => type.id == wide.id).name,
        'Extra Wide',
      );
      expect(
        () => FamilyParameterAuthoring.renameType(
          document,
          typeId: wide.id,
          name: source.name,
        ),
        throwsFormatException,
      );
    });

    test('cannot remove the final Family Type', () {
      final document = FamilyDocument.starter(name: 'Last type');
      expect(
        () => FamilyParameterAuthoring.removeType(
          document,
          document.types.single.id,
        ),
        throwsFormatException,
      );
    });

    test('semantic validation catches newly introduced formula cycles', () {
      var document = FamilyDocument.starter(name: 'Cycle');
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Alpha',
        kind: FamilyParameterKind.number,
        defaultValue: 1,
      );
      final alpha = document.parameters.last.id;
      document = FamilyParameterAuthoring.addParameter(
        document,
        label: 'Beta',
        kind: FamilyParameterKind.number,
        formula: '$alpha + 1',
      );
      final beta = document.parameters.last.id;

      expect(
        () => FamilyParameterAuthoring.updateParameter(
          document,
          parameterId: alpha,
          formula: '$beta + 1',
        ),
        throwsFormatException,
      );
    });
  });
}
