import 'dart:convert';

import 'family_constraint_models.dart';

/// Independent family authoring document.
///
/// A family file is intentionally not a project scene. It describes a
/// reusable parametric definition and can be created, versioned and loaded
/// without opening a BIM project.
enum FamilyCategory {
  genericModel,
  column,
  door,
  window,
  wallSweep,
  furniture,
  casework,
  stair,
  structural,
}

enum FamilyParameterKind {
  length,
  number,
  angle,
  material,
  text,
  boolean,
}

enum FamilyFeatureKind {
  box,
  profile,
  extrude,
  revolve,
  booleanUnion,
  booleanSubtract,
  transform,
  freeformMesh,

  /// References another reusable family by stable family/type ids. The child
  /// document is not embedded in this document; an external dependency resolver
  /// prepares its evaluated mesh before geometry evaluation.
  nestedFamily,
}

enum FamilySketchPlane { xy, xz, yz }

final class FamilySketchPoint {
  const FamilySketchPoint({this.id = '', required this.x, required this.y});

  /// Stable authoring identity. Empty ids are accepted only for legacy or
  /// transient points; file loading and constraint authoring hydrate them.
  final String id;
  final double x;
  final double y;

  FamilySketchPoint copyWith({String? id, double? x, double? y}) {
    return FamilySketchPoint(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (id.trim().isNotEmpty) 'id': id.trim(),
        'x': x,
        'y': y,
      };

  static FamilySketchPoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = _asDouble(raw['x']);
    final y = _asDouble(raw['y']);
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return FamilySketchPoint(
      id: raw['id']?.toString().trim() ?? '',
      x: x,
      y: y,
    );
  }
}

final class FamilySketch {
  const FamilySketch({
    required this.id,
    required this.name,
    required this.plane,
    this.points = const <FamilySketchPoint>[],
    this.closed = false,
  });

  final String id;
  final String name;
  final FamilySketchPlane plane;
  final List<FamilySketchPoint> points;
  final bool closed;

  bool get isValid => closed && points.length >= 3;

  FamilySketch copyWith({
    String? name,
    FamilySketchPlane? plane,
    List<FamilySketchPoint>? points,
    bool? closed,
  }) {
    final requested = points ?? this.points;
    final normalized = <FamilySketchPoint>[
      for (var index = 0; index < requested.length; index++)
        requested[index].id.trim().isNotEmpty
            ? requested[index]
            : index < this.points.length &&
                    this.points[index].id.trim().isNotEmpty
                ? requested[index].copyWith(id: this.points[index].id)
                : requested[index],
    ];
    return FamilySketch(
      id: id,
      name: name ?? this.name,
      plane: plane ?? this.plane,
      points: List<FamilySketchPoint>.unmodifiable(normalized),
      closed: closed ?? this.closed,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'plane': plane.name,
        'closed': closed,
        'points': points.map((point) => point.toJson()).toList(),
      };

  static FamilySketch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final plane = _enumFromName(
      FamilySketchPlane.values,
      raw['plane']?.toString(),
    );
    if (id.isEmpty || name.isEmpty || plane == null) return null;
    final points = <FamilySketchPoint>[];
    final rawPoints = raw['points'];
    if (rawPoints is List) {
      for (var index = 0; index < rawPoints.length; index++) {
        final point = FamilySketchPoint.fromJson(rawPoints[index]);
        if (point == null) continue;
        points.add(
          point.id.trim().isEmpty
              ? point.copyWith(id: '$id:point-$index')
              : point,
        );
      }
    }
    return FamilySketch(
      id: id,
      name: name,
      plane: plane,
      points: List<FamilySketchPoint>.unmodifiable(points),
      closed: raw['closed'] == true,
    );
  }
}

final class FamilyParameterDefinition {
  const FamilyParameterDefinition({
    required this.id,
    required this.label,
    required this.kind,
    required this.defaultValue,
    this.minimum,
    this.maximum,
    this.formula,
  });

  final String id;
  final String label;
  final FamilyParameterKind kind;
  final Object? defaultValue;
  final double? minimum;
  final double? maximum;
  final String? formula;

  bool get hasFormula => formula?.trim().isNotEmpty == true;

  FamilyParameterDefinition copyWith({
    String? label,
    FamilyParameterKind? kind,
    Object? defaultValue,
    double? minimum,
    double? maximum,
    String? formula,
    bool clearFormula = false,
  }) {
    return FamilyParameterDefinition(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      defaultValue: defaultValue ?? this.defaultValue,
      minimum: minimum ?? this.minimum,
      maximum: maximum ?? this.maximum,
      formula: clearFormula ? null : (formula ?? this.formula),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'kind': kind.name,
        'default': defaultValue,
        if (minimum != null) 'minimum': minimum,
        if (maximum != null) 'maximum': maximum,
        if (hasFormula) 'formula': formula!.trim(),
      };

  static FamilyParameterDefinition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final label = raw['label']?.toString().trim() ?? '';
    final kind = _enumFromName(
      FamilyParameterKind.values,
      raw['kind']?.toString(),
    );
    if (id.isEmpty || label.isEmpty || kind == null) return null;
    final formula = raw['formula']?.toString().trim();
    return FamilyParameterDefinition(
      id: id,
      label: label,
      kind: kind,
      defaultValue: raw['default'],
      minimum: _asDouble(raw['minimum']),
      maximum: _asDouble(raw['maximum']),
      formula: formula == null || formula.isEmpty ? null : formula,
    );
  }
}

final class FamilyTypeDefinition {
  const FamilyTypeDefinition({
    required this.id,
    required this.name,
    this.values = const <String, Object?>{},
  });

  final String id;
  final String name;
  final Map<String, Object?> values;

  FamilyTypeDefinition copyWith({
    String? name,
    Map<String, Object?>? values,
  }) {
    return FamilyTypeDefinition(
      id: id,
      name: name ?? this.name,
      values: Map<String, Object?>.unmodifiable(values ?? this.values),
    );
  }

  Object? valueFor(FamilyParameterDefinition parameter) =>
      values[parameter.id] ?? parameter.defaultValue;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'values': values,
      };

  static FamilyTypeDefinition? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final values = <String, Object?>{};
    final rawValues = raw['values'];
    if (rawValues is Map) {
      for (final entry in rawValues.entries) {
        values[entry.key.toString()] = entry.value;
      }
    }
    return FamilyTypeDefinition(
      id: id,
      name: name,
      values: Map<String, Object?>.unmodifiable(values),
    );
  }
}

final class FamilyFeature {
  const FamilyFeature({
    required this.id,
    required this.kind,
    this.label = '',
    this.inputs = const <String>[],
    this.parameters = const <String, Object?>{},
  });

  final String id;
  final FamilyFeatureKind kind;
  final String label;
  final List<String> inputs;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        if (label.isNotEmpty) 'label': label,
        if (inputs.isNotEmpty) 'inputs': inputs,
        'parameters': parameters,
      };

  static FamilyFeature? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final kind = _enumFromName(
      FamilyFeatureKind.values,
      raw['kind']?.toString(),
    );
    if (id.isEmpty || kind == null) return null;
    final inputs = <String>[];
    final rawInputs = raw['inputs'];
    if (rawInputs is List) {
      for (final item in rawInputs) {
        final input = item.toString().trim();
        if (input.isNotEmpty) inputs.add(input);
      }
    }
    final parameters = <String, Object?>{};
    final rawParameters = raw['parameters'];
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        parameters[entry.key.toString()] = entry.value;
      }
    }
    return FamilyFeature(
      id: id,
      kind: kind,
      label: raw['label']?.toString() ?? '',
      inputs: List<String>.unmodifiable(inputs),
      parameters: Map<String, Object?>.unmodifiable(parameters),
    );
  }
}

final class FamilyDocument {
  const FamilyDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.parameters,
    required this.types,
    required this.features,
    this.sketches = const <FamilySketch>[],
    this.referencePlanes = const <FamilyReferencePlane>[],
    this.constraints = const <FamilySketchConstraint>[],
    this.description = '',
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 6;
  static const int minimumSupportedSchemaVersion = 1;
  static const String fileExtension = 'bimfamily';

  final String id;
  final String name;
  final FamilyCategory category;
  final String description;
  final List<FamilyParameterDefinition> parameters;
  final List<FamilyTypeDefinition> types;
  final List<FamilyFeature> features;
  final List<FamilySketch> sketches;
  final List<FamilyReferencePlane> referencePlanes;
  final List<FamilySketchConstraint> constraints;
  final int schemaVersion;

  factory FamilyDocument.starter({
    String name = 'New Family',
    FamilyCategory category = FamilyCategory.genericModel,
  }) {
    const parameters = <FamilyParameterDefinition>[
      FamilyParameterDefinition(
        id: 'width',
        label: 'Width',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      ),
      FamilyParameterDefinition(
        id: 'depth',
        label: 'Depth',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      ),
      FamilyParameterDefinition(
        id: 'height',
        label: 'Height',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      ),
    ];
    return FamilyDocument(
      id: 'family-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      category: category,
      parameters: parameters,
      types: const <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'type-1',
          name: 'Default Type',
          values: <String, Object?>{
            'width': 1.0,
            'depth': 1.0,
            'height': 1.0,
          },
        ),
      ],
      features: const <FamilyFeature>[
        FamilyFeature(
          id: 'feature-1',
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

  FamilyDocument copyWith({
    String? name,
    FamilyCategory? category,
    String? description,
    List<FamilyParameterDefinition>? parameters,
    List<FamilyTypeDefinition>? types,
    List<FamilyFeature>? features,
    List<FamilySketch>? sketches,
    List<FamilyReferencePlane>? referencePlanes,
    List<FamilySketchConstraint>? constraints,
  }) {
    return FamilyDocument(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      parameters: List<FamilyParameterDefinition>.unmodifiable(
        parameters ?? this.parameters,
      ),
      types: List<FamilyTypeDefinition>.unmodifiable(types ?? this.types),
      features: List<FamilyFeature>.unmodifiable(features ?? this.features),
      sketches: List<FamilySketch>.unmodifiable(sketches ?? this.sketches),
      referencePlanes: List<FamilyReferencePlane>.unmodifiable(
        referencePlanes ?? this.referencePlanes,
      ),
      constraints: List<FamilySketchConstraint>.unmodifiable(
        constraints ?? this.constraints,
      ),
      schemaVersion: currentSchemaVersion,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'format': 'tablet_bim_family',
        'schema_version': schemaVersion,
        'id': id,
        'name': name,
        'category': category.name,
        'description': description,
        'parameters': parameters.map((item) => item.toJson()).toList(),
        'types': types.map((item) => item.toJson()).toList(),
        'features': features.map((item) => item.toJson()).toList(),
        'sketches': sketches.map((item) => item.toJson()).toList(),
        if (referencePlanes.isNotEmpty)
          'reference_planes':
              referencePlanes.map((item) => item.toJson()).toList(),
        if (constraints.isNotEmpty)
          'constraints': constraints.map((item) => item.toJson()).toList(),
      };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  static FamilyDocument? fromJson(Object? raw) {
    if (raw is! Map || raw['format'] != 'tablet_bim_family') return null;
    final schemaVersion = _asInt(raw['schema_version']) ?? 1;
    if (schemaVersion < minimumSupportedSchemaVersion ||
        schemaVersion > currentSchemaVersion) {
      return null;
    }
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final category = _enumFromName(
      FamilyCategory.values,
      raw['category']?.toString(),
    );
    if (id.isEmpty || name.isEmpty || category == null) return null;

    final parameters = <FamilyParameterDefinition>[];
    final rawParameters = raw['parameters'];
    if (rawParameters is List) {
      for (final item in rawParameters) {
        final parameter = FamilyParameterDefinition.fromJson(item);
        if (parameter != null) parameters.add(parameter);
      }
    }
    final types = <FamilyTypeDefinition>[];
    final rawTypes = raw['types'];
    if (rawTypes is List) {
      for (final item in rawTypes) {
        final type = FamilyTypeDefinition.fromJson(item);
        if (type != null) types.add(type);
      }
    }
    final features = <FamilyFeature>[];
    final rawFeatures = raw['features'];
    if (rawFeatures is List) {
      for (final item in rawFeatures) {
        final feature = FamilyFeature.fromJson(item);
        if (feature != null) features.add(feature);
      }
    }
    final sketches = <FamilySketch>[];
    final rawSketches = raw['sketches'];
    if (rawSketches is List) {
      for (final item in rawSketches) {
        final sketch = FamilySketch.fromJson(item);
        if (sketch != null) sketches.add(sketch);
      }
    }
    final referencePlanes = <FamilyReferencePlane>[];
    final rawReferencePlanes = raw['reference_planes'];
    if (rawReferencePlanes is List) {
      for (final item in rawReferencePlanes) {
        final plane = FamilyReferencePlane.fromJson(item);
        if (plane != null) referencePlanes.add(plane);
      }
    }
    final rawConstraints = <FamilySketchConstraint>[];
    final rawConstraintList = raw['constraints'];
    if (rawConstraintList is List) {
      for (final item in rawConstraintList) {
        final constraint = FamilySketchConstraint.fromJson(item);
        if (constraint != null) rawConstraints.add(constraint);
      }
    }
    final sketchById = <String, FamilySketch>{
      for (final sketch in sketches) sketch.id: sketch,
    };
    final constraints = <FamilySketchConstraint>[
      for (final constraint in rawConstraints)
        _hydrateConstraintPointIds(constraint, sketchById[constraint.sketchId]),
    ];

    if (parameters.isEmpty || types.isEmpty || features.isEmpty) return null;
    return FamilyDocument(
      id: id,
      name: name,
      category: category,
      description: raw['description']?.toString() ?? '',
      parameters: List<FamilyParameterDefinition>.unmodifiable(parameters),
      types: List<FamilyTypeDefinition>.unmodifiable(types),
      features: List<FamilyFeature>.unmodifiable(features),
      sketches: List<FamilySketch>.unmodifiable(sketches),
      referencePlanes:
          List<FamilyReferencePlane>.unmodifiable(referencePlanes),
      constraints: List<FamilySketchConstraint>.unmodifiable(constraints),
      schemaVersion: schemaVersion,
    );
  }
}

FamilySketchConstraint _hydrateConstraintPointIds(
  FamilySketchConstraint constraint,
  FamilySketch? sketch,
) {
  String? idAt(int? index, String? existing) {
    if (existing?.trim().isNotEmpty == true) return existing!.trim();
    if (sketch == null || index == null || index < 0 || index >= sketch.points.length) {
      return null;
    }
    final id = sketch.points[index].id.trim();
    return id.isEmpty ? null : id;
  }

  return FamilySketchConstraint(
    id: constraint.id,
    sketchId: constraint.sketchId,
    kind: constraint.kind,
    pointAIndex: constraint.pointAIndex,
    pointAId: idAt(constraint.pointAIndex, constraint.pointAId),
    pointBIndex: constraint.pointBIndex,
    pointBId: idAt(constraint.pointBIndex, constraint.pointBId),
    pointCIndex: constraint.pointCIndex,
    pointCId: idAt(constraint.pointCIndex, constraint.pointCId),
    pointDIndex: constraint.pointDIndex,
    pointDId: idAt(constraint.pointDIndex, constraint.pointDId),
    referencePlaneId: constraint.referencePlaneId,
    expression: constraint.expression,
  );
}

T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
