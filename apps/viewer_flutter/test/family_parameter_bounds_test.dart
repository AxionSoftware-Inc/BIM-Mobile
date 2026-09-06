import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('parameter metadata update preserves omitted bounds', () {
    var document = FamilyDocument.starter(name: 'Bounds preserve');
    document = FamilyParameterAuthoring.addParameter(
      document,
      label: 'Seat Height',
      kind: FamilyParameterKind.length,
      defaultValue: 0.45,
      minimum: 0.2,
      maximum: 1.2,
    );
    final id = document.parameters.last.id;

    final renamed = FamilyParameterAuthoring.updateParameter(
      document,
      parameterId: id,
      label: 'Seat Elevation',
    );
    final parameter = renamed.parameters.last;
    expect(parameter.minimum, 0.2);
    expect(parameter.maximum, 1.2);
  });

  test('parameter bounds can be cleared intentionally', () {
    var document = FamilyDocument.starter(name: 'Bounds clear');
    document = FamilyParameterAuthoring.addParameter(
      document,
      label: 'Offset',
      kind: FamilyParameterKind.number,
      defaultValue: 0.5,
      minimum: -1.0,
      maximum: 2.0,
    );
    final id = document.parameters.last.id;

    final cleared = FamilyParameterAuthoring.updateParameter(
      document,
      parameterId: id,
      clearMinimum: true,
      clearMaximum: true,
    );
    final parameter = cleared.parameters.last;
    expect(parameter.minimum, isNull);
    expect(parameter.maximum, isNull);
    expect(FamilyDocumentValidator.validate(cleared).isValid, true);
  });

  test('one update cannot both set and clear the same bound', () {
    final document = FamilyDocument.starter(name: 'Bounds conflict');
    expect(
      () => FamilyParameterAuthoring.updateParameter(
        document,
        parameterId: 'width',
        minimum: 0.5,
        clearMinimum: true,
      ),
      throwsFormatException,
    );
  });
}
