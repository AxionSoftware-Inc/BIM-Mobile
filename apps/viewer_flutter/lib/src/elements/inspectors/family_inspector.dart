part of '../../property_editor.dart';

Widget _buildFamilyInspector(_ObjectInspectorContext context) {
  final familyId = elementParameterText(
    context.object,
    'property.family_asset_id',
  );
  if (familyId == null) return _buildGenericInspector(context);
  return _FamilyPropertiesSection(
    object: context.object,
    levels: context.levels,
    units: context.units,
    commands: context.commands,
    onApplied: context.onApplied,
  );
}

/// The small instance contract stored on the native element. The family
/// feature graph stays in the independent .bimfamily file; only definitions
/// and current values are cached here so Inspector remains usable offline.
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
    required this.levels,
    required this.units,
    required this.commands,
    required this.onApplied,
  });

  final RenderSceneObject object;
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
    unawaited(_loadDocument(object));
  }

  Future<void> _loadDocument(RenderSceneObject object) async {
    final instance = _instance;
    if (instance == null) return;
    if (mounted) setState(() => _loading = true);
    FamilyDocument? document;
    if (instance.assetPath.isNotEmpty) {
      document = (await FamilyFileStore.loadPath(instance.assetPath))?.document;
    }
    document ??= _findBuiltIn(instance.assetId);
    if (!mounted || _instance?.assetId != instance.assetId) return;
    if (document != null) {
      final merged = <String, Object?>{..._values};
      for (final parameter in document.parameters) {
        merged.putIfAbsent(parameter.id, () => parameter.defaultValue);
      }
      setState(() {
        _document = document;
        _values = merged;
        _syncControllers();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  FamilyDocument? _findBuiltIn(String id) {
    for (final family in BuiltInFamilyCatalog.families) {
      if (family.id == id) return family;
    }
    return null;
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

  List<FamilyParameterDefinition> get _definitions =>
      _document?.parameters.isNotEmpty == true
          ? _document!.parameters
          : (_instance?.definitions ?? const <FamilyParameterDefinition>[]);

  Object? _valueFor(FamilyParameterDefinition parameter) =>
      _values[parameter.id] ?? parameter.defaultValue;

  String _displayValue(FamilyParameterDefinition parameter) {
    final value = _valueFor(parameter);
    if (parameter.kind == FamilyParameterKind.length && value is num) {
      return widget.units.formatLength(value.toDouble(), withUnit: false);
    }
    if (value is double) return value.toStringAsFixed(3);
    return value?.toString() ?? '';
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
    if (_busy || _instance == null) return;
    final previous = _valueFor(parameter);
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
        setState(() => _values[parameter.id] = previous);
        _controllers[parameter.id]?.text = _displayValue(parameter);
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
    if (value is num) {
      if (!value.isFinite) return false;
      if (parameter.minimum != null && value < parameter.minimum!) return false;
      if (parameter.maximum != null && value > parameter.maximum!) return false;
    }
    return parameter.kind != FamilyParameterKind.text &&
            parameter.kind != FamilyParameterKind.material ||
        value.toString().trim().isNotEmpty;
  }

  Future<RenderSceneLoadResult> _applyValues() async {
    final instance = _instance!;
    final document = _document ?? _findBuiltIn(instance.assetId);
    if (document == null) {
      throw const FormatException('Family asset is unavailable.');
    }
    final sourceType = document.types.firstWhere(
      (type) => type.id == instance.typeId,
      orElse: () => document.types.first,
    );
    final type = sourceType.copyWith(values: <String, Object?>{
      ...sourceType.values,
      ..._values,
    });
    final object = widget.object;
    if (object.kindKey == 'door' || object.kindKey == 'window') {
      final opening = OpeningElementParameters.fromObject(object);
      final offset = _lengthValue('offset') ?? opening.offsetMeters;
      final width = _lengthValue('width') ?? opening.widthMeters;
      final height = _lengthValue('height') ?? opening.heightMeters;
      final sill =
          _lengthValue('sillHeight') ?? opening.sillHeightMeters ?? 0.0;
      if (object.elementId == null ||
          offset == null ||
          width == null ||
          height == null) {
        throw const FormatException(
            'Opening instance has incomplete geometry.');
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
      final position = RenderScenePoint(
        x: elementParameterDouble(object, 'property.position_x') ??
            object.bounds.center.x,
        y: elementParameterDouble(object, 'property.position_y') ??
            object.bounds.center.y,
        z: 0.0,
      );
      final mesh = FamilyGeometryEvaluator.evaluateMesh(document, type);
      final vertices = FamilyInstanceAdapter.projectVertices(mesh, position);
      final indices = FamilyInstanceAdapter.triangleIndices(mesh);
      if (object.elementId == null || vertices.isEmpty || indices.isEmpty) {
        throw const FormatException(
            'Family instance has no renderable geometry.');
      }
      await widget.commands.updateFamilyInstance(
        elementId: object.elementId!,
        position: position,
        widthMeters: FamilyInstanceAdapter.lengthValue(
          document,
          type,
          'width',
          fallback: object.bounds.width,
        ),
        depthMeters: FamilyInstanceAdapter.lengthValue(
          document,
          type,
          'depth',
          fallback: object.bounds.depth,
        ),
        heightMeters: FamilyInstanceAdapter.lengthValue(
          document,
          type,
          'height',
          fallback: object.bounds.height,
        ),
        vertices: vertices,
        indices: indices,
      );
    }
    return widget.commands.setElementFamilyReference(
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
      familyParameterValuesJson: jsonEncode(_values),
      familyPlanSvg: FamilyPlanSymbolGenerator.svgFor(document, type),
    );
  }

  double? _lengthValue(String id) {
    for (final parameter in _definitions) {
      if (parameter.id != id || parameter.kind != FamilyParameterKind.length) {
        continue;
      }
      final value = _valueFor(parameter);
      final parsed =
          value is num ? value.toDouble() : double.tryParse('$value');
      if (parsed != null && parsed.isFinite && parsed > 0.0) return parsed;
    }
    return null;
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
        _row('Category', instance.category),
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
    if (parameter.kind == FamilyParameterKind.boolean) {
      return _compactSwitch(
        label: parameter.label,
        value: value == true || value.toString() == 'true',
        onChanged:
            _busy ? null : (next) => unawaited(_saveParameter(parameter, next)),
      );
    }
    final controller = _controllers[parameter.id] ??=
        TextEditingController(text: _displayValue(parameter));
    final numeric = parameter.kind != FamilyParameterKind.text &&
        parameter.kind != FamilyParameterKind.material;
    final suffix = parameter.kind == FamilyParameterKind.length
        ? ' (${widget.units.lengthSymbol})'
        : parameter.kind == FamilyParameterKind.angle
            ? ' (°)'
            : '';
    return _field(
      '${parameter.label}$suffix',
      controller,
      numeric: numeric,
      onEditingComplete: () => unawaited(
        _saveParameter(parameter, controller.text),
      ),
    );
  }
}
