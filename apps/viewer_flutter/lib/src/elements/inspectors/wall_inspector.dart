part of '../../property_editor.dart';

class _WallPropertiesSection extends StatefulWidget {
  const _WallPropertiesSection(
      {required this.object,
      required this.scene,
      required this.levels,
      required this.units,
      required this.commands,
      required this.onApplied});
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  @override
  State<_WallPropertiesSection> createState() => _WallPropertiesSectionState();
}

class _WallPropertiesSectionState extends State<_WallPropertiesSection> {
  late int _base;
  late int _top;
  late int _wallTypeId;
  late bool _connected;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final parameters = WallElementParameters.fromObject(widget.object);
    _base = parameters.baseLevelId ??
        widget.object.levelId ??
        (widget.levels.isNotEmpty ? widget.levels.first.levelId : 0);
    _top = parameters.topLevelId ?? 0;
    _wallTypeId = parameters.wallTypeId;
    _connected = parameters.isTopConnected;
  }

  @override
  void didUpdateWidget(covariant _WallPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId == widget.object.elementId &&
        oldWidget.object.revision == widget.object.revision) {
      return;
    }
    final parameters = WallElementParameters.fromObject(widget.object);
    _base = parameters.baseLevelId ??
        widget.object.levelId ??
        (widget.levels.isNotEmpty ? widget.levels.first.levelId : 0);
    _top = parameters.topLevelId ?? 0;
    _wallTypeId = parameters.wallTypeId;
    _connected = parameters.isTopConnected;
  }

  Future<void> _saveWallType(int previousTypeId) async {
    final wallId = widget.object.elementId;
    if (wallId == null) return;
    final selected = widget.scene.wallTypes
        .where((wallType) => wallType.id == _wallTypeId)
        .firstOrNull;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.setWallType(
        wallId: wallId,
        wallTypeId: _wallTypeId,
      );
      if (result.scene == null) {
        if (mounted) setState(() => _wallTypeId = previousTypeId);
        return;
      }
      await widget.onApplied(
        result,
        selected == null
            ? 'Wall type cleared.'
            : '${selected.name} applied to wall.',
      );
    } catch (_) {
      if (mounted) setState(() => _wallTypeId = previousTypeId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _applyWallLayers(
    String name,
    WallTypeCategory category,
    List<WallTypeLayerDefinition> layers,
  ) async {
    final wallId = widget.object.elementId;
    if (wallId == null || layers.isEmpty || _busy) return false;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.createWallTypeForWall(
        wallId: wallId,
        category: category,
        name: name,
        layers: layers,
      );
      if (result.scene == null) return false;
      await widget.onApplied(result, 'Wall layers updated.');
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveConstraints({
    required int previousBase,
    required int previousTop,
    required bool previousConnected,
  }) async {
    if (widget.levels.isEmpty || widget.object.elementId == null) return;
    if (_connected && _top == _base) {
      if (mounted) {
        setState(() {
          _base = previousBase;
          _top = previousTop;
          _connected = previousConnected;
        });
      }
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final parameters = WallElementParameters.fromObject(widget.object);
      final top =
          _connected ? (_top == 0 ? widget.levels.last.levelId : _top) : 0;
      final result = await widget.commands.setWallConstraints(
          wallId: widget.object.elementId!,
          baseLevelId: _base,
          topLevelId: top,
          heightMode: _connected ? 1 : 0,
          baseOffsetMeters: parameters.baseOffsetMeters,
          topOffsetMeters: parameters.topOffsetMeters);
      if (result.scene == null) {
        if (mounted) {
          setState(() {
            _base = previousBase;
            _top = previousTop;
            _connected = previousConnected;
          });
        }
        return;
      }
      await widget.onApplied(result, 'Wall constraints updated.');
    } catch (_) {
      if (mounted) {
        setState(() {
          _base = previousBase;
          _top = previousTop;
          _connected = previousConnected;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: 'Wall properties',
        icon: Icons.view_week_outlined,
        children: <Widget>[
          _sectionLabel('Level & constraints'),
          _levelDrop(
            'Base level',
            _base,
            (value) {
              if (_busy) return;
              final previousBase = _base;
              final previousTop = _top;
              final previousConnected = _connected;
              setState(() => _base = value);
              unawaited(_saveConstraints(
                previousBase: previousBase,
                previousTop: previousTop,
                previousConnected: previousConnected,
              ));
            },
          ),
          _compactSwitch(
            label: 'Top level constraint',
            value: _connected,
            onChanged: widget.levels.isEmpty
                ? null
                : (value) {
                    if (_busy) return;
                    final previousBase = _base;
                    final previousTop = _top;
                    final previousConnected = _connected;
                    setState(() => _connected = value);
                    unawaited(_saveConstraints(
                      previousBase: previousBase,
                      previousTop: previousTop,
                      previousConnected: previousConnected,
                    ));
                  },
          ),
          if (_connected && widget.levels.isNotEmpty)
            _levelDrop(
              'Top level',
              _top == 0 ? widget.levels.last.levelId : _top,
              (value) {
                if (_busy) return;
                final previousBase = _base;
                final previousTop = _top;
                final previousConnected = _connected;
                setState(() => _top = value);
                unawaited(_saveConstraints(
                  previousBase: previousBase,
                  previousTop: previousTop,
                  previousConnected: previousConnected,
                ));
              },
            ),
          _sectionLabel('Geometry'),
          _wallGeometryRow(),
          _sectionLabel('Layers'),
          if (widget.scene.wallTypes.isNotEmpty) ...<Widget>[
            _wallTypeDrop(),
            _wallAssemblySummary(),
          ] else
            _row(
              'Wall type',
              WallElementParameters.fromObject(widget.object)
                      .wallTypeCategory ??
                  '-',
            ),
          _row('Layer count', '${_layerCount()} layers'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Edit wall assembly'),
            subtitle: const Text('Advanced type editing'),
            children: <Widget>[
              _WallLayersEditor(
                key: ValueKey<String>(
                  'wall-layers-${widget.object.elementId}-$_wallTypeId',
                ),
                object: widget.object,
                wallType: widget.scene.wallTypes
                    .where((type) => type.id == _wallTypeId)
                    .firstOrNull,
                materials: widget.scene.materials,
                units: widget.units,
                onApply: _applyWallLayers,
                busy: _busy,
              ),
            ],
          ),
        ],
      );

  Widget _wallTypeDrop() {
    final value = widget.scene.wallTypes.any(
      (wallType) => wallType.id == _wallTypeId,
    )
        ? _wallTypeId
        : 0;
    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Wall type',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<int>(
          value: 0,
          child: Text('Unassigned · Generic'),
        ),
        for (final wallType in widget.scene.wallTypes)
          DropdownMenuItem<int>(
            value: wallType.id,
            child: Text(
              '${wallType.name} · ${wallType.categoryLabel}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (next) {
        if (next != null && !_busy) {
          final previous = _wallTypeId;
          setState(() => _wallTypeId = next);
          unawaited(_saveWallType(previous));
        }
      },
    );
  }

  Widget _wallAssemblySummary() {
    final wallType = widget.scene.wallTypes
        .where((candidate) => candidate.id == _wallTypeId)
        .firstOrNull;
    if (wallType == null) return const SizedBox.shrink();
    return _row(
      'Assembly',
      _number(wallType.totalThicknessMeters, units: widget.units),
    );
  }

  Widget _wallGeometryRow() {
    final parameters = WallElementParameters.fromObject(widget.object);
    return _row(
      'Size',
      '${_number(parameters.thicknessMeters, units: widget.units)} thick · '
          '${_number(parameters.lengthMeters, units: widget.units)} long',
    );
  }

  int _layerCount() {
    final parameters = WallElementParameters.fromObject(widget.object);
    if (parameters.layerCount > 0) {
      return parameters.layerCount;
    }
    return widget.scene.wallTypes
            .where((wallType) => wallType.id == _wallTypeId)
            .firstOrNull
            ?.layers
            .length ??
        0;
  }

  Widget _levelDrop(String label, int value, ValueChanged<int> onChanged) =>
      DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: widget.levels.any((level) => level.levelId == value)
              ? value
              : (widget.levels.isNotEmpty ? widget.levels.first.levelId : null),
          decoration: _dropdownDecoration(label),
          items: [
            for (final level in widget.levels)
              DropdownMenuItem(
                  value: level.levelId,
                  child: Text(
                      '${level.name} (${_number(level.elevationMeters, units: widget.units)})'))
          ],
          onChanged: widget.levels.isEmpty
              ? null
              : (next) {
                  if (next != null) onChanged(next);
                });
}

class _WallLayersEditor extends StatefulWidget {
  const _WallLayersEditor({
    super.key,
    required this.object,
    required this.wallType,
    required this.materials,
    required this.units,
    required this.onApply,
    required this.busy,
  });

  final RenderSceneObject object;
  final WallTypeDefinition? wallType;
  final List<RenderSceneMaterial> materials;
  final ProjectUnitSettings units;
  final Future<bool> Function(
    String name,
    WallTypeCategory category,
    List<WallTypeLayerDefinition> layers,
  ) onApply;
  final bool busy;

  @override
  State<_WallLayersEditor> createState() => _WallLayersEditorState();
}

class _WallLayersEditorState extends State<_WallLayersEditor> {
  late final TextEditingController _nameController;
  late String _name;
  late WallTypeCategory _category;
  late List<_EditableWallLayer> _layers;
  String? _error;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _resetFromSource();
  }

  @override
  void didUpdateWidget(covariant _WallLayersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallType?.id != widget.wallType?.id ||
        oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision) {
      _disposeLayers();
      _resetFromSource();
    } else if (oldWidget.units != widget.units) {
      for (final layer in _layers) {
        final displayThickness = double.tryParse(layer.thickness.text.trim());
        if (displayThickness == null) continue;
        layer.thickness.text = widget.units.formatLength(
          oldWidget.units.toMeters(displayThickness),
          withUnit: false,
        );
      }
    }
  }

  void _resetFromSource() {
    final wallType = widget.wallType;
    // Editing creates an isolated copy, so the user explicitly names the
    // result instead of accidentally overwriting the shared source type.
    _name = '';
    _nameController.text = _name;
    _category = wallType?.category ?? WallTypeCategory.generic;
    final sourceLayers = wallType?.layers ?? const <WallTypeLayerDefinition>[];
    if (sourceLayers.isNotEmpty) {
      _layers = sourceLayers
          .map(
              (layer) => _EditableWallLayer.fromDefinition(layer, widget.units))
          .toList();
      return;
    }
    final materialId = widget.materials.firstOrNull?.id ?? 0;
    final parameters = WallElementParameters.fromObject(widget.object);
    _layers = <_EditableWallLayer>[
      _EditableWallLayer(
        materialId: materialId,
        thicknessMeters:
            parameters.thicknessMeters > 0 ? parameters.thicknessMeters : 0.20,
        units: widget.units,
        function: WallLayerFunction.core,
        priority: 100,
        structural: true,
        side: WallLayerSide.unspecified,
        wrapsOpenings: true,
        wrapsEnds: true,
      ),
    ];
  }

  void _disposeLayers() {
    for (final layer in _layers) {
      layer.dispose();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _disposeLayers();
    _nameController.dispose();
    super.dispose();
  }

  void _addLayer() {
    setState(() {
      _error = null;
      _layers.add(
        _EditableWallLayer(
          materialId: widget.materials.firstOrNull?.id ?? 0,
          thicknessMeters: 0.05,
          units: widget.units,
          function: WallLayerFunction.generic,
          priority: 0,
          structural: false,
          side: WallLayerSide.unspecified,
          wrapsOpenings: true,
          wrapsEnds: true,
        ),
      );
    });
    _queueSave(immediate: true);
  }

  void _removeLayer(int index) {
    if (_layers.length <= 1) {
      setState(() => _error = 'A wall type must keep at least one layer.');
      return;
    }
    setState(() {
      _layers.removeAt(index).dispose();
      _error = null;
    });
    _queueSave(immediate: true);
  }

  void _queueSave({bool immediate = false}) {
    _saveTimer?.cancel();
    if (immediate) {
      unawaited(_save());
      return;
    }
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    if (widget.busy) return;
    final name = _name.trim();
    if (name.isEmpty) {
      if (mounted) setState(() => _error = 'Enter a wall type name.');
      return;
    }
    final layers = <WallTypeLayerDefinition>[];
    for (final layer in _layers) {
      final displayThickness = double.tryParse(layer.thickness.text.trim());
      final thickness = displayThickness == null
          ? null
          : widget.units.toMeters(displayThickness);
      if (layer.materialId == 0 || thickness == null || thickness <= 0) {
        if (mounted) {
          setState(() => _error = 'Every layer needs material and thickness.');
        }
        return;
      }
      layers.add(layer.toDefinition(thickness));
    }
    setState(() => _error = null);
    final saved = await widget.onApply(name, _category, layers);
    if (!saved && mounted) {
      _disposeLayers();
      _resetFromSource();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _nameController,
                  maxLines: 1,
                  onChanged: (value) => _name = value,
                  onEditingComplete: () => _queueSave(immediate: true),
                  decoration: _dropdownDecoration(
                    widget.wallType == null
                        ? 'New type name'
                        : 'Isolated type name',
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < _layers.length; index += 1)
          _buildLayerRow(index),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.busy ? null : _addLayer,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add layer'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildLayerRow(int index) {
    final layer = _layers[index];
    final validMaterial = widget.materials.any(
      (material) => material.id == layer.materialId,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: validMaterial ? layer.materialId : null,
                  decoration: _dropdownDecoration('Material'),
                  hint: const Text('Select material'),
                  items: <DropdownMenuItem<int>>[
                    for (final material in widget.materials)
                      DropdownMenuItem<int>(
                        value: material.id,
                        child: Text(
                          material.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => layer.materialId = value);
                            _queueSave(immediate: true);
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: _field(
                  widget.units.lengthSymbol,
                  layer.thickness,
                  numeric: true,
                  onEditingComplete: () => _queueSave(immediate: true),
                ),
              ),
              IconButton(
                tooltip: 'Remove layer',
                onPressed: widget.busy ? null : () => _removeLayer(index),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          DropdownButtonFormField<WallLayerFunction>(
            isExpanded: true,
            initialValue: layer.function,
            decoration: _dropdownDecoration('Function'),
            items: WallLayerFunction.values
                .map(
                  (function) => DropdownMenuItem<WallLayerFunction>(
                    value: function,
                    child: Text(function.label),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => layer.function = value);
                      _queueSave(immediate: true);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _EditableWallLayer {
  _EditableWallLayer({
    required this.materialId,
    required double thicknessMeters,
    required ProjectUnitSettings units,
    required this.function,
    required this.priority,
    required this.structural,
    required this.side,
    required this.wrapsOpenings,
    required this.wrapsEnds,
  }) : thickness = TextEditingController(
          text: units.formatLength(thicknessMeters, withUnit: false),
        );

  factory _EditableWallLayer.fromDefinition(
    WallTypeLayerDefinition layer,
    ProjectUnitSettings units,
  ) {
    return _EditableWallLayer(
      materialId: layer.materialId,
      thicknessMeters: layer.thicknessMeters,
      units: units,
      function: layer.function,
      priority: layer.priority,
      structural: layer.structural,
      side: layer.side,
      wrapsOpenings: layer.wrapsOpenings,
      wrapsEnds: layer.wrapsEnds,
    );
  }

  int materialId;
  final TextEditingController thickness;
  WallLayerFunction function;
  final int priority;
  final bool structural;
  final WallLayerSide side;
  final bool wrapsOpenings;
  final bool wrapsEnds;

  WallTypeLayerDefinition toDefinition(double thicknessMeters) =>
      WallTypeLayerDefinition(
        materialId: materialId,
        thicknessMeters: thicknessMeters,
        function: function,
        priority: priority,
        structural: structural,
        side: side,
        wrapsOpenings: wrapsOpenings,
        wrapsEnds: wrapsEnds,
      );

  void dispose() => thickness.dispose();
}
