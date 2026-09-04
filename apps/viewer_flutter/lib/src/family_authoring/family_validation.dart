import 'family_document.dart';

final class FamilyValidationResult {
  const FamilyValidationResult(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Validates family assets before they cross the file boundary.
///
/// This validator is intentionally independent from project validation. A
/// family can be authored and checked without opening a project or touching
/// the project scene graph.
abstract final class FamilyDocumentValidator {
  static FamilyValidationResult validate(FamilyDocument document) {
    final errors = <String>[];
    if (document.name.trim().isEmpty) {
      errors.add('Family name is required');
    }
    if (document.types.isEmpty) {
      errors.add('At least one family type is required');
    }
    if (document.features.isEmpty) {
      errors.add('At least one feature is required');
    }

    _checkUniqueIds(
      document.parameters.map((parameter) => parameter.id),
      'parameter',
      errors,
    );
    _checkUniqueIds(
      document.types.map((type) => type.id),
      'type',
      errors,
    );
    _checkUniqueIds(
      document.features.map((feature) => feature.id),
      'feature',
      errors,
    );
    _checkUniqueIds(
      document.sketches.map((sketch) => sketch.id),
      'sketch',
      errors,
    );

    final parameterIds =
        document.parameters.map((parameter) => parameter.id).toSet();
    for (final parameter in document.parameters) {
      if (parameter.minimum != null &&
          parameter.maximum != null &&
          parameter.minimum! > parameter.maximum!) {
        errors.add('Parameter ${parameter.label} has an invalid range');
      }
    }
    for (final type in document.types) {
      for (final key in type.values.keys) {
        if (!parameterIds.contains(key)) {
          errors.add('Type ${type.name} references unknown parameter $key');
        }
      }
      for (final parameter in document.parameters) {
        final value = type.values[parameter.id];
        if (value is! num) continue;
        if (parameter.minimum != null && value < parameter.minimum!) {
          errors.add('Type ${type.name} sets ${parameter.label} below minimum');
        }
        if (parameter.maximum != null && value > parameter.maximum!) {
          errors.add('Type ${type.name} sets ${parameter.label} above maximum');
        }
      }
    }

    final sketchIds = document.sketches.map((sketch) => sketch.id).toSet();
    final featureIds = document.features.map((feature) => feature.id).toSet();
    for (final feature in document.features) {
      for (final input in feature.inputs) {
        if (!sketchIds.contains(input) && !featureIds.contains(input)) {
          errors.add('Feature ${feature.id} references unknown input $input');
        }
      }
      final profileId = feature.parameters['profileId']?.toString();
      if (profileId != null && !sketchIds.contains(profileId)) {
        errors
            .add('Feature ${feature.id} references unknown profile $profileId');
      }
      if (feature.kind == FamilyFeatureKind.extrude ||
          feature.kind == FamilyFeatureKind.revolve) {
        final sketch = _findSketch(document.sketches, profileId);
        if (sketch == null || !sketch.isValid) {
          errors.add('${feature.kind.name} requires a closed profile');
        }
      }
    }
    return FamilyValidationResult(List<String>.unmodifiable(errors));
  }

  static void _checkUniqueIds(
    Iterable<String> ids,
    String kind,
    List<String> errors,
  ) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty) {
        errors.add('$kind id is required');
      } else if (!seen.add(id)) {
        errors.add('Duplicate $kind id: $id');
      }
    }
  }

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
}
