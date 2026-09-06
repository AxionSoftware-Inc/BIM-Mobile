import 'family_document.dart';
import 'family_parameter_resolver.dart';

final class FamilyValidationResult {
  const FamilyValidationResult(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Validates family assets before they cross the file/project boundary.
///
/// Validation is deliberately stricter than JSON parsing. A syntactically
/// valid external file must not be allowed to create a different preview,
/// placement or persisted instance depending on which code path reads it.
abstract final class FamilyDocumentValidator {
  static FamilyValidationResult validate(FamilyDocument document) {
    final errors = <String>[];
    final seenErrors = <String>{};
    void add(String message) {
      if (seenErrors.add(message)) errors.add(message);
    }

    if (document.schemaVersion < FamilyDocument.minimumSupportedSchemaVersion ||
        document.schemaVersion > FamilyDocument.currentSchemaVersion) {
      add('Unsupported family schema version ${document.schemaVersion}');
    }
    if (document.name.trim().isEmpty) add('Family name is required');
    if (document.types.isEmpty) add('At least one family type is required');
    if (document.features.isEmpty) add('At least one feature is required');

    _checkUniqueIds(
      document.parameters.map((parameter) => parameter.id),
      'parameter',
      add,
    );
    _checkUniqueIds(
      document.types.map((type) => type.id),
      'type',
      add,
    );
    _checkUniqueIds(
      document.features.map((feature) => feature.id),
      'feature',
      add,
    );
    _checkUniqueIds(
      document.sketches.map((sketch) => sketch.id),
      'sketch',
      add,
    );
    _checkUniqueNames(
      document.types.map((type) => type.name),
      'family type',
      add,
    );

    final parameterIds =
        document.parameters.map((parameter) => parameter.id).toSet();
    for (final parameter in document.parameters) {
      if (parameter.label.trim().isEmpty) {
        add('Parameter ${parameter.id} needs a label');
      }
      if (parameter.minimum != null && !parameter.minimum!.isFinite) {
        add('Parameter ${parameter.label} has a non-finite minimum');
      }
      if (parameter.maximum != null && !parameter.maximum!.isFinite) {
        add('Parameter ${parameter.label} has a non-finite maximum');
      }
      if (parameter.minimum != null &&
          parameter.maximum != null &&
          parameter.minimum! > parameter.maximum!) {
        add('Parameter ${parameter.label} has an invalid range');
      }
      final numeric = _isNumericKind(parameter.kind);
      if (!numeric &&
          (parameter.minimum != null || parameter.maximum != null)) {
        add('Non-numeric parameter ${parameter.label} cannot have a range');
      }
      if (parameter.hasFormula && !numeric) {
        add('Formula parameter ${parameter.label} must be numeric');
      }
      if (!parameter.hasFormula) {
        final error = _valueError(parameter, parameter.defaultValue);
        if (error != null) add('Default ${parameter.label}: $error');
      }
    }

    for (final type in document.types) {
      if (type.name.trim().isEmpty) add('Family type name is required');
      for (final key in type.values.keys) {
        if (!parameterIds.contains(key)) {
          add('Type ${type.name} references unknown parameter $key');
        }
      }
      final resolver = FamilyParameterResolver(document, type);
      for (final parameter in document.parameters) {
        // Formula-driven parameters intentionally ignore their own stored type
        // value. Validate all other explicit values before resolving chains.
        if (!parameter.hasFormula && type.values.containsKey(parameter.id)) {
          final error = _valueError(parameter, type.values[parameter.id]);
          if (error != null) {
            add('Type ${type.name} · ${parameter.label}: $error');
          }
        }
        try {
          resolver.resolve(parameter);
        } on FormatException catch (error) {
          add('Type ${type.name}: ${error.message}');
        } catch (error) {
          add('Type ${type.name}: $error');
        }
      }
    }

    final sketchIds = document.sketches.map((sketch) => sketch.id).toSet();
    final featureIndex = <String, int>{
      for (var index = 0; index < document.features.length; index++)
        document.features[index].id: index,
    };
    for (var index = 0; index < document.features.length; index++) {
      final feature = document.features[index];
      for (final input in feature.inputs) {
        final inputFeatureIndex = featureIndex[input];
        if (!sketchIds.contains(input) && inputFeatureIndex == null) {
          add('Feature ${feature.id} references unknown input $input');
          continue;
        }
        if (inputFeatureIndex != null && inputFeatureIndex >= index) {
          add('Feature ${feature.id} must reference an earlier feature: $input');
        }
        if ((feature.kind == FamilyFeatureKind.transform ||
                feature.kind == FamilyFeatureKind.booleanUnion ||
                feature.kind == FamilyFeatureKind.booleanSubtract) &&
            inputFeatureIndex != null &&
            !_isSolidFeature(document.features[inputFeatureIndex])) {
          add('Feature ${feature.id} requires solid input $input');
        }
      }

      final profileId = feature.parameters['profileId']?.toString();
      if (profileId != null && !sketchIds.contains(profileId)) {
        add('Feature ${feature.id} references unknown profile $profileId');
      }
      if (feature.kind == FamilyFeatureKind.extrude ||
          feature.kind == FamilyFeatureKind.revolve) {
        final sketch = _findSketch(document.sketches, profileId);
        if (sketch == null || !sketch.isValid) {
          add('${feature.kind.name} requires a closed profile');
        }
      }
      if (feature.kind == FamilyFeatureKind.freeformMesh) {
        _checkFreeformMesh(feature, add);
      }
    }

    return FamilyValidationResult(List<String>.unmodifiable(errors));
  }

  static void _checkUniqueIds(
    Iterable<String> ids,
    String kind,
    void Function(String) add,
  ) {
    final seen = <String>{};
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty) {
        add('$kind id is required');
      } else if (!seen.add(id)) {
        add('Duplicate $kind id: $id');
      }
    }
  }

  static void _checkUniqueNames(
    Iterable<String> names,
    String kind,
    void Function(String) add,
  ) {
    final seen = <String>{};
    for (final rawName in names) {
      final name = rawName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) add('Duplicate $kind name: $name');
    }
  }

  static String? _valueError(
    FamilyParameterDefinition parameter,
    Object? value,
  ) {
    switch (parameter.kind) {
      case FamilyParameterKind.boolean:
        return value is bool ? null : 'must be true or false';
      case FamilyParameterKind.text:
      case FamilyParameterKind.material:
        return value is String && value.trim().isNotEmpty
            ? null
            : 'must be non-empty text';
      case FamilyParameterKind.length:
      case FamilyParameterKind.number:
      case FamilyParameterKind.angle:
        final number = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (number == null || !number.isFinite) return 'must be a finite number';
        if (parameter.kind == FamilyParameterKind.length && number <= 0.0) {
          return 'must be positive';
        }
        if (parameter.minimum != null && number < parameter.minimum!) {
          return 'is below minimum ${parameter.minimum}';
        }
        if (parameter.maximum != null && number > parameter.maximum!) {
          return 'is above maximum ${parameter.maximum}';
        }
        return null;
    }
  }

  static bool _isNumericKind(FamilyParameterKind kind) =>
      kind == FamilyParameterKind.length ||
      kind == FamilyParameterKind.number ||
      kind == FamilyParameterKind.angle;

  static bool _isSolidFeature(FamilyFeature feature) =>
      feature.kind == FamilyFeatureKind.box ||
      feature.kind == FamilyFeatureKind.extrude ||
      feature.kind == FamilyFeatureKind.revolve ||
      feature.kind == FamilyFeatureKind.booleanUnion ||
      feature.kind == FamilyFeatureKind.booleanSubtract ||
      feature.kind == FamilyFeatureKind.transform ||
      feature.kind == FamilyFeatureKind.freeformMesh;

  static FamilySketch? _findSketch(
    Iterable<FamilySketch> sketches,
    String? id,
  ) {
    if (id == null) return null;
    for (final sketch in sketches) {
      if (sketch.id == id) return sketch;
    }
    return null;
  }

  static void _checkFreeformMesh(
    FamilyFeature feature,
    void Function(String) add,
  ) {
    const maxVertices = 200000;
    const maxFaces = 200000;
    final rawVertices = feature.parameters['vertices'];
    final rawFaces = feature.parameters['faces'];
    if (rawVertices is! List || rawFaces is! List) {
      add('Freeform mesh ${feature.id} needs vertices and faces');
      return;
    }
    if (rawVertices.isEmpty || rawFaces.isEmpty) {
      add('Freeform mesh ${feature.id} cannot be empty');
      return;
    }
    if (rawVertices.length > maxVertices) {
      add('Freeform mesh ${feature.id} has too many vertices');
    }
    if (rawFaces.length > maxFaces) {
      add('Freeform mesh ${feature.id} has too many faces');
    }
    for (final rawVertex in rawVertices) {
      final values = rawVertex is List && rawVertex.length >= 3
          ? rawVertex
          : rawVertex is Map
              ? <Object?>[rawVertex['x'], rawVertex['y'], rawVertex['z']]
              : const <Object?>[];
      if (values.length < 3 ||
          values.take(3).any((value) => !_finiteNumber(value))) {
        add('Freeform mesh ${feature.id} has an invalid vertex');
        break;
      }
    }
    for (final rawFace in rawFaces) {
      if (rawFace is! List || rawFace.length < 3) {
        add('Freeform mesh ${feature.id} has an invalid face');
        break;
      }
      for (final rawIndex in rawFace) {
        final index =
            rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString());
        if (index == null || index < 0 || index >= rawVertices.length) {
          add('Freeform mesh ${feature.id} has an out-of-range face index');
          return;
        }
      }
    }
  }

  static bool _finiteNumber(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number != null && number.isFinite;
  }
}
