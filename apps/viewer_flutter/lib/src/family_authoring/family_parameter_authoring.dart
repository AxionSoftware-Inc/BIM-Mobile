import 'family_document.dart';
import 'family_validation.dart';

/// Domain commands for editing Family parameters and named types.
///
/// UI surfaces must use this class instead of manually mutating parameter/type
/// lists. Every command preserves stable ids, migrates type value maps and runs
/// the same semantic validator used by save/import/placement.
abstract final class FamilyParameterAuthoring {
  static const Set<String> protectedCoreParameterIds = <String>{
    'width',
    'depth',
    'height',
  };

  static FamilyDocument addParameter(
    FamilyDocument document, {
    required String label,
    required FamilyParameterKind kind,
    Object? defaultValue,
    String? formula,
    double? minimum,
    double? maximum,
    String? preferredId,
  }) {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      throw const FormatException('Parameter name is required.');
    }
    final id = _uniqueParameterId(
      document,
      preferredId?.trim().isNotEmpty == true ? preferredId! : trimmedLabel,
    );
    final normalizedFormula = formula?.trim();
    if (normalizedFormula?.isNotEmpty == true && !_isNumericKind(kind)) {
      throw const FormatException(
        'Only length, number and angle parameters can use formulas.',
      );
    }
    if ((minimum != null || maximum != null) && !_isNumericKind(kind)) {
      throw const FormatException(
        'Minimum and maximum are only valid for numeric parameters.',
      );
    }
    if (minimum != null && maximum != null && minimum > maximum) {
      throw const FormatException('Parameter minimum cannot exceed maximum.');
    }

    final fallback = defaultValue ?? _defaultForKind(kind);
    final definition = FamilyParameterDefinition(
      id: id,
      label: trimmedLabel,
      kind: kind,
      defaultValue: fallback,
      minimum: minimum,
      maximum: maximum,
      formula: normalizedFormula?.isEmpty == true ? null : normalizedFormula,
    );
    final hasFormula = definition.hasFormula;
    final candidate = document.copyWith(
      parameters: <FamilyParameterDefinition>[
        ...document.parameters,
        definition,
      ],
      types: <FamilyTypeDefinition>[
        for (final type in document.types)
          type.copyWith(
            values: <String, Object?>{
              ...type.values,
              if (!hasFormula) id: fallback,
            },
          ),
      ],
    );
    return _validated(candidate);
  }

  /// Updates metadata/formula while retaining the stable parameter id.
  ///
  /// A parameter id is part of formulas, constraints and feature expressions,
  /// so renaming the id is deliberately not supported. Rename [label] instead.
  static FamilyDocument updateParameter(
    FamilyDocument document, {
    required String parameterId,
    String? label,
    FamilyParameterKind? kind,
    Object? defaultValue,
    double? minimum,
    double? maximum,
    String? formula,
    bool clearFormula = false,
  }) {
    final index = document.parameters.indexWhere(
      (parameter) => parameter.id == parameterId,
    );
    if (index < 0) {
      throw FormatException('Unknown Family parameter: $parameterId');
    }
    final current = document.parameters[index];
    final nextKind = kind ?? current.kind;
    final nextLabel = label?.trim() ?? current.label;
    if (nextLabel.isEmpty) {
      throw const FormatException('Parameter name is required.');
    }
    final requestedFormula = clearFormula ? null : (formula ?? current.formula);
    final normalizedFormula = requestedFormula?.trim();
    if (normalizedFormula?.isNotEmpty == true && !_isNumericKind(nextKind)) {
      throw const FormatException(
        'Only length, number and angle parameters can use formulas.',
      );
    }
    final nextMinimum = minimum ?? current.minimum;
    final nextMaximum = maximum ?? current.maximum;
    if ((nextMinimum != null || nextMaximum != null) &&
        !_isNumericKind(nextKind)) {
      throw const FormatException(
        'Minimum and maximum are only valid for numeric parameters.',
      );
    }
    if (nextMinimum != null &&
        nextMaximum != null &&
        nextMinimum > nextMaximum) {
      throw const FormatException('Parameter minimum cannot exceed maximum.');
    }

    final nextDefault = defaultValue ?? current.defaultValue;
    final replacement = FamilyParameterDefinition(
      id: current.id,
      label: nextLabel,
      kind: nextKind,
      defaultValue: nextDefault,
      minimum: nextMinimum,
      maximum: nextMaximum,
      formula: normalizedFormula?.isEmpty == true ? null : normalizedFormula,
    );
    final enteringFormula = !current.hasFormula && replacement.hasFormula;
    final leavingFormula = current.hasFormula && !replacement.hasFormula;
    final candidate = document.copyWith(
      parameters: <FamilyParameterDefinition>[
        for (var cursor = 0; cursor < document.parameters.length; cursor++)
          cursor == index ? replacement : document.parameters[cursor],
      ],
      types: <FamilyTypeDefinition>[
        for (final type in document.types)
          type.copyWith(
            values: <String, Object?>{
              for (final entry in type.values.entries)
                if (!(enteringFormula && entry.key == current.id))
                  entry.key: entry.value,
              if (leavingFormula && !type.values.containsKey(current.id))
                current.id: nextDefault,
            },
          ),
      ],
    );
    return _validated(candidate);
  }

  static FamilyDocument removeParameter(
    FamilyDocument document,
    String parameterId,
  ) {
    if (protectedCoreParameterIds.contains(parameterId)) {
      throw FormatException(
        '$parameterId is part of the stable Family sizing contract and cannot be removed.',
      );
    }
    final parameter = _parameter(document, parameterId);
    if (parameter == null) {
      throw FormatException('Unknown Family parameter: $parameterId');
    }
    final reference = firstReferenceTo(document, parameterId);
    if (reference != null) {
      throw FormatException(
        'Parameter ${parameter.label} is still used by $reference.',
      );
    }

    final candidate = document.copyWith(
      parameters: <FamilyParameterDefinition>[
        for (final current in document.parameters)
          if (current.id != parameterId) current,
      ],
      types: <FamilyTypeDefinition>[
        for (final type in document.types)
          type.copyWith(
            values: <String, Object?>{
              for (final entry in type.values.entries)
                if (entry.key != parameterId) entry.key: entry.value,
            },
          ),
      ],
    );
    return _validated(candidate);
  }

  static FamilyDocument setTypeValue(
    FamilyDocument document, {
    required String typeId,
    required String parameterId,
    required Object? value,
  }) {
    final parameter = _parameter(document, parameterId);
    if (parameter == null) {
      throw FormatException('Unknown Family parameter: $parameterId');
    }
    if (parameter.hasFormula) {
      throw FormatException(
        '${parameter.label} is formula-driven and cannot be overridden by a Family Type.',
      );
    }
    if (!document.types.any((type) => type.id == typeId)) {
      throw FormatException('Unknown Family Type: $typeId');
    }
    final candidate = document.copyWith(
      types: <FamilyTypeDefinition>[
        for (final type in document.types)
          type.id == typeId
              ? type.copyWith(
                  values: <String, Object?>{
                    ...type.values,
                    parameterId: value,
                  },
                )
              : type,
      ],
    );
    return _validated(candidate);
  }

  static FamilyDocument duplicateType(
    FamilyDocument document, {
    required String sourceTypeId,
    String? name,
  }) {
    final source = _type(document, sourceTypeId);
    if (source == null) {
      throw FormatException('Unknown Family Type: $sourceTypeId');
    }
    final requestedName = name?.trim();
    final nextName = _uniqueTypeName(
      document,
      requestedName?.isNotEmpty == true ? requestedName! : '${source.name} Copy',
    );
    final nextId = _uniqueTypeId(document, '${source.id}-copy');
    final candidate = document.copyWith(
      types: <FamilyTypeDefinition>[
        ...document.types,
        FamilyTypeDefinition(
          id: nextId,
          name: nextName,
          values: Map<String, Object?>.from(source.values),
        ),
      ],
    );
    return _validated(candidate);
  }

  static FamilyDocument renameType(
    FamilyDocument document, {
    required String typeId,
    required String name,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('Family Type name is required.');
    final type = _type(document, typeId);
    if (type == null) throw FormatException('Unknown Family Type: $typeId');
    final duplicate = document.types.any(
      (candidate) =>
          candidate.id != typeId &&
          candidate.name.trim().toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) throw FormatException('Family Type "$trimmed" already exists.');
    return _validated(
      document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final current in document.types)
            current.id == typeId ? current.copyWith(name: trimmed) : current,
        ],
      ),
    );
  }

  static FamilyDocument removeType(
    FamilyDocument document,
    String typeId,
  ) {
    if (document.types.length <= 1) {
      throw const FormatException('A Family must keep at least one Family Type.');
    }
    if (!document.types.any((type) => type.id == typeId)) {
      throw FormatException('Unknown Family Type: $typeId');
    }
    return _validated(
      document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in document.types)
            if (type.id != typeId) type,
        ],
      ),
    );
  }

  /// Returns a human-readable first reference that blocks safe removal.
  static String? firstReferenceTo(FamilyDocument document, String parameterId) {
    for (final parameter in document.parameters) {
      if (parameter.id == parameterId) continue;
      if (_objectReferencesParameter(parameter.formula, parameterId)) {
        return 'parameter formula "${parameter.label}"';
      }
    }
    for (final plane in document.referencePlanes) {
      if (_objectReferencesParameter(plane.expression, parameterId)) {
        return 'reference plane "${plane.name}"';
      }
    }
    for (final constraint in document.constraints) {
      if (_objectReferencesParameter(constraint.expression, parameterId)) {
        return 'constraint "${constraint.id}"';
      }
    }
    for (final feature in document.features) {
      if (_objectReferencesParameter(feature.parameters, parameterId)) {
        final label = feature.label.trim().isEmpty ? feature.id : feature.label.trim();
        return 'feature "$label"';
      }
    }
    return null;
  }

  static FamilyDocument _validated(FamilyDocument candidate) {
    final result = FamilyDocumentValidator.validate(candidate);
    if (!result.isValid) throw FormatException(result.errors.first);
    return candidate;
  }

  static FamilyParameterDefinition? _parameter(
    FamilyDocument document,
    String id,
  ) {
    for (final parameter in document.parameters) {
      if (parameter.id == id) return parameter;
    }
    return null;
  }

  static FamilyTypeDefinition? _type(FamilyDocument document, String id) {
    for (final type in document.types) {
      if (type.id == id) return type;
    }
    return null;
  }

  static String _uniqueParameterId(FamilyDocument document, String seed) {
    final base = _slug(seed, fallback: 'parameter');
    final used = document.parameters.map((parameter) => parameter.id).toSet();
    if (!used.contains(base)) return base;
    for (var suffix = 2; suffix < 1000000; suffix++) {
      final candidate = '$base$suffix';
      if (!used.contains(candidate)) return candidate;
    }
    throw const FormatException('Unable to allocate a unique parameter id.');
  }

  static String _uniqueTypeId(FamilyDocument document, String seed) {
    final base = _slug(seed, fallback: 'type');
    final used = document.types.map((type) => type.id).toSet();
    if (!used.contains(base)) return base;
    for (var suffix = 2; suffix < 1000000; suffix++) {
      final candidate = '$base$suffix';
      if (!used.contains(candidate)) return candidate;
    }
    throw const FormatException('Unable to allocate a unique Family Type id.');
  }

  static String _uniqueTypeName(FamilyDocument document, String seed) {
    final base = seed.trim().isEmpty ? 'Family Type' : seed.trim();
    final used = document.types
        .map((type) => type.name.trim().toLowerCase())
        .toSet();
    if (!used.contains(base.toLowerCase())) return base;
    for (var suffix = 2; suffix < 1000000; suffix++) {
      final candidate = '$base $suffix';
      if (!used.contains(candidate.toLowerCase())) return candidate;
    }
    throw const FormatException('Unable to allocate a unique Family Type name.');
  }

  static String _slug(String raw, {required String fallback}) {
    final lower = raw.trim().toLowerCase();
    final buffer = StringBuffer();
    var pendingSeparator = false;
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final code = rune;
      final isAsciiLetter = code >= 97 && code <= 122;
      final isDigit = code >= 48 && code <= 57;
      if (isAsciiLetter || isDigit) {
        if (pendingSeparator && buffer.isNotEmpty) buffer.write('_');
        buffer.write(char);
        pendingSeparator = false;
      } else {
        pendingSeparator = true;
      }
    }
    var result = buffer.toString();
    if (result.isEmpty) result = fallback;
    if (result.codeUnitAt(0) >= 48 && result.codeUnitAt(0) <= 57) {
      result = '${fallback}_$result';
    }
    return result;
  }

  static Object _defaultForKind(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => 1.0,
        FamilyParameterKind.number => 0.0,
        FamilyParameterKind.angle => 0.0,
        FamilyParameterKind.material => 'Default',
        FamilyParameterKind.text => 'Value',
        FamilyParameterKind.boolean => false,
      };

  static bool _isNumericKind(FamilyParameterKind kind) =>
      kind == FamilyParameterKind.length ||
      kind == FamilyParameterKind.number ||
      kind == FamilyParameterKind.angle;

  static bool _objectReferencesParameter(Object? value, String parameterId) {
    if (value is String) {
      final matches = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(value);
      return matches.any((match) => match.group(0) == parameterId);
    }
    if (value is Map) {
      return value.values.any(
        (item) => _objectReferencesParameter(item, parameterId),
      );
    }
    if (value is Iterable) {
      return value.any((item) => _objectReferencesParameter(item, parameterId));
    }
    return false;
  }
}
