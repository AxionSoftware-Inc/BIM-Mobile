part of '../../property_editor.dart';

Widget _buildFamilyInspector(_ObjectInspectorContext context) {
  final familyId = elementParameterText(
    context.object,
    'property.family_asset_id',
  );
  if (familyId == null) return _buildGenericInspector(context);
  return _FamilyPropertiesSection(
    object: context.object,
    scene: context.scene,
    levels: context.levels,
    units: context.units,
    commands: context.commands,
    onApplied: context.onApplied,
  );
}

/// Small offline instance contract cached on the native project element.
/// The authoring feature graph remains in the .bimfamily asset.
final class _FamilyInstanceStateData {
  const _FamilyInstanceStateData({
    required this.assetId,
    required this.assetPath,
    required this.name,
    required this.typeId,
    required this.typeName,
    required this.category,
    required this.definitions,
    required this.values,
  });

  final String assetId;
  final String assetPath;
  final String name;
  final String typeId;
  final String typeName;
  final String category;
  final List<FamilyParameterDefinition> definitions;
  final Map<String, Object?> values;

  static _FamilyInstanceStateData? fromObject(RenderSceneObject object) {
    final assetId = elementParameterText(object, 'property.family_asset_id');
    final name = elementParameterText(object, 'property.family_name');
    final typeId = elementParameterText(object, 'property.family_type_id');
    final typeName = elementParameterText(object, 'property.family_type_name');
    final category =
        elementParameterText(object, 'property.family_category') ?? '';
    if (assetId == null || name == null || typeId == null || typeName == null) {
      return null;
    }

    final definitions = <FamilyParameterDefinition>[];
    final rawDefinitions = _decodeJson(
      elementParameterText(
        object,
        'property.family_parameter_definitions_json',
      ),
    );
    if (rawDefinitions is List) {
      for (final item in rawDefinitions) {
        final definition = FamilyParameterDefinition.fromJson(item);
        if (definition != null) definitions.add(definition);
      }
    }

    final values = <String, Object?>{};
    final rawValues = _decodeJson(
      elementParameterText(object, 'property.family_parameter_values_json'),
    );
    if (rawValues is Map) {
      for (final entry in rawValues.entries) {
        values[entry.key.toString()] = entry.value;
      }
    }

    return _FamilyInstanceStateData(
      assetId: assetId,
      assetPath:
          elementParameterText(object, 'property.family_asset_path') ?? '',
      name: name,
      typeId: typeId,
      typeName: typeName,
      category: category,
      definitions: List<FamilyParameterDefinition>.unmodifiable(definitions),
      values: Map<String, Object?>.unmodifiable(values),
    );
  }

  static Object? _decodeJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

class _FamilyPropertiesSection extends StatefulWidget {
  const _FamilyPropertiesSection({
    required this.object,
    required this.scene,
    required this.levels,
    required this.units,
    required this.commands,
    required this.onApplied,
  });

  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_FamilyPropertiesSection> createState() =>
      _FamilyPropertiesSectionState();
}

class _FamilyPropertiesSectionState extends State<_FamilyPropertiesSection> {
  _FamilyInstanceStateData? _instance;
  FamilyDocument? _document;
  late Map<String, Object?> _values;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  bool _loading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resetFromObject(widget.object);
  }

  @override
  void didUpdateWidget(covariant _FamilyPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision) {
      _resetFromObject(widget.object);
    } else if (oldWidget.units != widget.units) {
      _syncControllers();
    }
  }

  void _resetFromObject(RenderSceneObject object) {
    _instance = _FamilyInstanceStateData.fromObject(object);
    _values = <String, Object?>{...?_instance?.values};
    _document = null;
    _disposeControllers();
    _syncControllers();
    unawaited(_loadDocument());
  }

  Future<void> _loadDocument() async {
    final instance = _instance;
    if (instance == null) return;
    if (mounted) setState(() => _loading = true);

    FamilyDocument? document;
    if (instance.assetPath.isNotEmpty) {
      document = (await FamilyFileStore.loadPath(instance.assetPath))?.document;
    }
    document ??= _findBuiltIn(instance.assetId);
    if (!mounted || _instance?.assetId != instance.assetId) return;

    if (document == null) {
      setState(() => _loading = false);
      return;
    }

    final sourceType = _sourceType(document, instance);
    final merged = <String, Object?>{
      ...sourceType.values,
      ..._values,
    };
    final type = sourceType.copyWith(values: merged);
    try {
      final effective = FamilyInstanceAdapter.resolvedValues(document, type);
      // Preserve private instance placement metadata; it is not a family
      // parameter and therefore must not be dropped by formula resolution.
      for (final entry in _values.entries) {
        if (entry.key.startsWith('_')) effective[entry.key] = entry.value;
      }
      _values = effective;
    } catch (_) {
      // The stored snapshot remains usable for display. Save/edit stays blocked
      // by the real resolver until the asset/formula is repaired.
      for (final parameter in document.parameters) {
        _values.putIfAbsent(parameter.id, () => parameter.defaultValue);
      }
    }

    setState(() {
      _document = document;
      _syncControllers();
    });
  }

  FamilyDocument? _findBuiltIn(String id) {
    for (final family in BuiltInFamilyCatalog.families) {
      if (family.id == id) return family;
    }
    return null;
  }

  FamilyTypeDefinition _sourceType(
    FamilyDocument document,
    _FamilyInstanceStateData instance,
  ) {
    return document.types.firstWhere(
      (type) => type.id == instance.typeId,
      orElse: () => document.types.first,
    );
  }

  FamilyTypeDefinition? _effectiveType() {
    final document = _document;
    final instance = _instance;
    if (document == null || instance == null) return null;
    final source = _sourceType(document, instance);
    return source.copyWith(values: <String, Object?>{
      ...source.values,
      ..._values,
    });
  }

  List<FamilyParameterDefinition> get _definitions =>
      _document?.parameters.isNotEmpty == true
          ? _document!.parameters
          : (_instance?.definitions ?? const <FamilyParameterDefinition>[]);

  Object? _valueFor(FamilyParameterDefinition parameter) {
    if (parameter.hasFormula) {
      final document = _document;
      final type = _effectiveType();
      if (document != null && type != null) {
        try {
          return FamilyInstanceAdapter.resolvedValue(
            document,
            type,
            parameter.id,
          );
        } catch (_) {
          // Fall through to the last persisted effective snapshot.
        }
      }
    }
    return _values[parameter.id] ?? parameter.defaultValue;
  }

  String _displayValue(FamilyParameterDefinition parameter) {
    final value = _valueFor(parameter);
    if (parameter.kind == FamilyParameterKind.length && value is num) {
      return widget.units.formatLength(value.toDouble(), withUnit: false);
    }
    if (value is double) return value.toStringAsFixed(3);
    return value?.toString() ?? '';
  }

  void _syncControllers() {
    final definitions = _definitions;
    for (final key in _controllers.keys.toList()) {
      if (!definitions.any((parameter) => parameter.id == key)) {
        _controllers.remove(key)?.dispose();
      }
    }
    for (final parameter in definitions) {
      final text = _displayValue(parameter);
      final controller = _controllers[parameter.id];
      if (controller == null) {
        _controllers[parameter.id] = TextEditingController(text: text);
      } else if (!_busy) {
        controller.text = text;
      }
    }
    _loading = false;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  Future<void> _saveParameter(
    FamilyParameterDefinition parameter,
    Object? rawValue,
  ) async {
    if (_busy || _loading || _instance == null || parameter.hasFormula) return;
    final previous = <String, Object?>{..._values};
    final parsed = _parseValue(parameter, rawValue);
    if (!_isValid(parameter, parsed)) {
      _controllers[parameter.id]?.text = _displayValue(parameter);
      return;
    }

    setState(() {
      _values[parameter.id] = parsed;
      _busy = true;
    });
    try {
      final result = await _applyValues();
      await widget.onApplied(result, '${_instance!.name} parameter updated.');
    } catch (_) {
      if (mounted) {
        setState(() => _values = previous);
        _syncControllers();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Object? _parseValue(FamilyParameterDefinition parameter, Object? raw) {
    if (parameter.kind == FamilyParameterKind.boolean) {
      return raw == true || raw.toString().toLowerCase() == 'true';
    }
    if (parameter.kind == FamilyParameterKind.text ||
        parameter.kind == FamilyParameterKind.material) {
      return raw?.toString() ?? '';
    }
    final display = raw?.toString().trim() ?? '';
    final parsed = double.tryParse(display);
    if (parsed == null || !parsed.isFinite) return null;
    return parameter.kind == FamilyParameterKind.length
        ? widget.units.toMeters(parsed)
        : parsed;
  }

  bool _isValid(FamilyParameterDefinition parameter, Object? value) {
    if (value == null) return false;
    if (parameter.kind == FamilyParameterKind.boolean) return value is bool;
    if (parameter.kind == FamilyParameterKind.text ||
        parameter.kind == FamilyParameterKind.material) {
      return value is String && value.trim().isNotEmpty;
    }
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) return false;
    if (parameter.kind == FamilyParameterKind.length && number <= 0.0) {
      return false;
    }
    if (parameter.minimum != null && number < parameter.minimum!) return false;
    if (parameter.maximum != null && number > parameter.maximum!) return false;
    return true;
  }

  Future<RenderSceneLoadResult> _applyValues() async {
    final instance = _instance!;
    final document = _document ?? _findBuiltIn(instance.assetId);
    if (document == null) {
      throw const FormatException('Family asset is unavailable.');
    }

    final sourceType = _sourceType(document, instance);
    final type = sourceType.copyWith(values: <String, Object?>{
      ...sourceType.values,
      ..._values,
    });
    final effective = FamilyInstanceAdapter.resolvedValues(document, type);
    final persistedValues = <String, Object?>{...effective};
    for (final entry in _values.entries) {
      if (entry.key.startsWith('_')) persistedValues[entry.key] = entry.value;
    }

    final object = widget.object;
    var planSvg = FamilyPlanSymbolGenerator.svgFor(document, type);
    if (object.kindKey == 'door' || object.kindKey == 'window') {
      final opening = OpeningElementParameters.fromObject(object);
      final offset = _resolvedLength(
            document,
            type,
            'offset',
            fallback: opening.offsetMeters,
          ) ??
          opening.offsetMeters;
      final width = _resolvedLength(
            document,
            type,
            'width',
            fallback: opening.widthMeters,
          ) ??
          opening.widthMeters;
      final height = _resolvedLength(
            document,
            type,
            'height',
            fallback: opening.heightMeters,
          ) ??
          opening.heightMeters;
      final sill = _resolvedLength(
            document,
            type,
            'sillHeight',
            fallback: opening.sillHeightMeters,
          ) ??
          opening.sillHeightMeters ??
          0.0;
      if (object.elementId == null ||
          offset == null ||
          width == null ||
          height == null) {
        throw const FormatException(
          'Opening instance has incomplete geometry.',
        );
      }
      final geometryChanged =
          (width - (opening.widthMeters ?? width)).abs() > 1e-9 ||
              (height - (opening.heightMeters ?? height)).abs() > 1e-9 ||
              (sill - (opening.sillHeightMeters ?? sill)).abs() > 1e-9 ||
              (offset - (opening.offsetMeters ?? offset)).abs() > 1e-9;
      if (geometryChanged) {
        await widget.commands.updateOpening(
          object: object,
          offsetMeters: offset,
          widthMeters: width,
          heightMeters: height,
          sillHeightMeters: sill,
        );
      }
    } else {
      final isWallSweep = instance.category == FamilyCategory.wallSweep.name;
      RenderSceneObject? hostWall;
      var hostOffset = 0.0;
      var position = RenderScenePoint(
        x: elementParameterDouble(object, 'property.position_x') ??
            object.bounds.center.x,
        y: elementParameterDouble(object, 'property.position_y') ??
            object.bounds.center.y,
        z: 0.0,
      );
      if (isWallSweep) {
        final hostId = _intValue(persistedValues['_hostWallId']);
        hostOffset = _numberValue(persistedValues['_hostOffsetMeters']) ??
            (RenderSceneQueries.wallLength(object) ?? 0.0) * 0.5;
        hostWall = RenderSceneQueries.objectById(widget.scene, hostId);
        if (hostWall == null || hostWall.kindKey != 'wall') {
          throw const FormatException('Wall sweep host wall is unavailable.');
        }
        final hostLength = RenderSceneQueries.wallLength(hostWall);
        final sweepWidth = FamilyInstanceAdapter.lengthValue(
          document,
          type,
          'width',
          fallback: object.bounds.width,
        );
        if (hostLength == null ||
            !hostLength.isFinite ||
            sweepWidth > hostLength - 0.02) {
          throw const FormatException(
            'Wall sweep width must fit inside the host wall.',
          );
        }
        position = RenderSceneQueries.wallPointAtOffset(hostWall, hostOffset) ??
            position;
      }

      final mesh = FamilyGeometryEvaluator.evaluateMesh(document, type);
      final vertices = isWallSweep
          ? FamilyInstanceAdapter.projectWallHostedVertices(
              mesh: mesh,
              hostWall: hostWall!,
              offsetMeters: hostOffset,
            )
          : FamilyInstanceAdapter.projectVertices(mesh, position);
      final indices = FamilyInstanceAdapter.triangleIndices(mesh);
      if (object.elementId == null || vertices.isEmpty || indices.isEmpty) {
        throw const FormatException(
          'Family instance has no renderable geometry.',
        );
      }
      final dimensions = isWallSweep
          ? FamilyInstanceAdapter.dimensionsForVertices(vertices)
          : (
              width: FamilyInstanceAdapter.lengthValue(
                document,
                type,
                'width',
                fallback: object.bounds.width,
              ),
              depth: FamilyInstanceAdapter.lengthValue(
                document,
                type,
                'depth',
                fallback: object.bounds.depth,
              ),
              height: FamilyInstanceAdapter.lengthValue(
                document,
                type,
                'height',
                fallback: object.bounds.height,
              ),
            );
      await widget.commands.updateFamilyInstance(
        elementId: object.elementId!,
        position: position,
        widthMeters: dimensions.width,
        depthMeters: dimensions.depth,
        heightMeters: dimensions.height,
        vertices: vertices,
        indices: indices,
      );
      if (isWallSweep) {
        final tangent = RenderSceneQueries.wallTangentAtOffset(
          hostWall!,
          hostOffset,
        );
        planSvg = FamilyPlanSymbolGenerator.svgFor(
          document,
          type,
          rotationRadians:
              tangent == null ? 0.0 : math.atan2(tangent.y, tangent.x),
        );
      }
    }

    final result = await widget.commands.setElementFamilyReference(
      elementId: object.elementId!,
      familyAssetId: instance.assetId,
      familyName: instance.name,
      familyTypeId: instance.typeId,
      familyTypeName: instance.typeName,
      familyCategory: instance.category,
      familyAssetPath: instance.assetPath,
      familyParameterDefinitionsJson: jsonEncode(
        _definitions.map((parameter) => parameter.toJson()).toList(),
      ),
      familyParameterValuesJson: jsonEncode(persistedValues),
      familyPlanSvg: planSvg,
    );

    if (mounted) {
      setState(() => _values = persistedValues);
      _syncControllers();
    }
    return result;
  }

  double? _resolvedLength(
    FamilyDocument document,
    FamilyTypeDefinition type,
    String id, {
    double? fallback,
  }) {
    final exists = document.parameters.any(
      (parameter) =>
          parameter.id == id && parameter.kind == FamilyParameterKind.length,
    );
    if (!exists) return fallback;
    try {
      return FamilyInstanceAdapter.lengthValue(
        document,
        type,
        id,
        fallback: fallback,
      );
    } catch (_) {
      return fallback;
    }
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _numberValue(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  @override
  Widget build(BuildContext context) {
    final instance = _instance;
    if (instance == null) {
      return _ReadOnlyObjectSection(
        object: widget.object,
        title: '${_label(widget.object)} properties',
        rows: <String, String>{
          'Level': widget.object.levelId?.toString() ?? '-',
          'Material': widget.object.materialCategory,
        },
      );
    }
    final definitions = _definitions;
    return _InspectorCard(
      title: instance.name,
      icon: _icon(widget.object.kindKey),
      children: <Widget>[
        _row('Type', instance.typeName),
        _row('Category', _familyInspectorCategoryLabel(instance.category)),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (definitions.isNotEmpty) ...<Widget>[
          _sectionLabel('Type parameters'),
          for (final parameter in definitions) _parameterField(parameter),
        ] else
          const Text(
            'No editable family parameters are defined.',
            style: TextStyle(fontSize: 11.5),
          ),
      ],
    );
  }

  Widget _parameterField(FamilyParameterDefinition parameter) {
    final value = _valueFor(parameter);
    final suffix = parameter.kind == FamilyParameterKind.length
        ? ' (${widget.units.lengthSymbol})'
        : parameter.kind == FamilyParameterKind.angle
            ? ' (°)'
            : '';

    if (parameter.hasFormula) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _row(
                '${parameter.label}$suffix',
                _displayValue(parameter),
              ),
            ),
            Tooltip(
              message: '${parameter.id} = ${parameter.formula}',
              child: const Icon(Icons.functions, size: 16),
            ),
          ],
        ),
      );
    }

    if (parameter.kind == FamilyParameterKind.boolean) {
      return _compactSwitch(
        label: parameter.label,
        value: value == true || value.toString() == 'true',
        onChanged: _busy || _loading
            ? null
            : (next) => unawaited(_saveParameter(parameter, next)),
      );
    }

    final controller = _controllers[parameter.id] ??=
        TextEditingController(text: _displayValue(parameter));
    final numeric = parameter.kind != FamilyParameterKind.text &&
        parameter.kind != FamilyParameterKind.material;
    return _field(
      '${parameter.label}$suffix',
      controller,
      numeric: numeric,
      onEditingComplete: _busy || _loading
          ? null
          : () => unawaited(
                _saveParameter(parameter, controller.text),
              ),
    );
  }

  static String _familyInspectorCategoryLabel(String value) {
    return switch (value) {
      'genericModel' => 'Generic model',
      'column' => 'Column',
      'door' => 'Door',
      'window' => 'Window',
      'wallSweep' => 'Wall sweep',
      'furniture' => 'Furniture',
      'casework' => 'Casework',
      'stair' => 'Stair',
      'structural' => 'Structural',
      _ => value.isEmpty ? 'Family' : value,
    };
  }
}
