import 'package:flutter/material.dart';

import 'authoring_command_service.dart';
import 'elements/bim_element_registry.dart';
import 'elements/wall_type_catalog.dart';
import 'inspector_controller.dart';
import 'render_scene_models.dart';
import 'tools/opening_tool_controller.dart';

typedef ApplyInspectorResult = Future<void> Function(
  RenderSceneLoadResult result,
  String message,
);

/// Context-sensitive Revit-style Properties surface. Only properties backed by
/// an engine command are editable; derived data is visibly read-only.
class PropertyEditor extends StatelessWidget {
  const PropertyEditor({
    super.key,
    required this.scene,
    required this.target,
    required this.commands,
    required this.onApplied,
    required this.onClearSelection,
    required this.viewRangeMeters,
    required this.onViewRangeChanged,
    required this.showPlanViewRange,
    required this.activePlanLevel,
  });

  final RenderScene scene;
  final InspectorTarget target;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  final VoidCallback onClearSelection;
  final double viewRangeMeters;
  final Future<void> Function(double value) onViewRangeChanged;
  final bool showPlanViewRange;
  final RenderSceneLevel? activePlanLevel;

  @override
  Widget build(BuildContext context) {
    final properties = switch (target.kind) {
      InspectorTargetKind.empty => const _InspectorCard(
          title: 'Select an element',
          icon: Icons.touch_app_outlined,
          children: <Widget>[
            Text('Tap an element to inspect its properties.'),
          ],
        ),
      InspectorTargetKind.multiple => _InspectorCard(
          title: 'Multiple selection',
          icon: Icons.select_all,
          children: <Widget>[
            Text('${target.objects.length} object(s) selected.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onClearSelection,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear selection'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ),
      InspectorTargetKind.level => _LevelPropertiesSection(
          key: ValueKey<String>('level-${target.level!.levelId}'),
          level: target.level!,
          commands: commands,
          onApplied: onApplied,
        ),
      InspectorTargetKind.object => Column(
          key: ValueKey<String>('object-${target.object!.elementId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ObjectPropertiesSection(
              object: target.object!,
              scene: scene,
              levels: scene.levels,
              commands: commands,
              onApplied: onApplied,
            ),
          ],
        ),
    };
    final sections = <Widget>[properties];
    if (showPlanViewRange) {
      sections
        ..add(const SizedBox(height: 8))
        ..add(
          _PlanViewRangeSection(
            level: activePlanLevel,
            value: viewRangeMeters,
            onChanged: onViewRangeChanged,
          ),
        );
    }
    if (target.kind == InspectorTargetKind.object) {
      sections
        ..add(const SizedBox(height: 8))
        ..add(
          _DeleteElementButton(
            object: target.object!,
            commands: commands,
            onApplied: onApplied,
          ),
        );
    }
    if (sections.length == 1) return properties;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }
}

class _PlanViewRangeSection extends StatefulWidget {
  const _PlanViewRangeSection({
    required this.level,
    required this.value,
    required this.onChanged,
  });

  final RenderSceneLevel? level;
  final double value;
  final Future<void> Function(double value) onChanged;

  @override
  State<_PlanViewRangeSection> createState() => _PlanViewRangeSectionState();
}

class _PlanViewRangeSectionState extends State<_PlanViewRangeSection> {
  late final TextEditingController _controller;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _number(widget.value));
  }

  @override
  void didUpdateWidget(covariant _PlanViewRangeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && oldWidget.value != widget.value) {
      _controller.text = _number(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0.05) return;
    setState(() => _busy = true);
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: 'View range · ${widget.level?.name ?? 'Active level'}',
        icon: Icons.height,
        children: <Widget>[
          _field('Cut height (m)', _controller, numeric: true),
          _applyButton(_busy, _apply),
        ],
      );
}

class _LevelPropertiesSection extends StatefulWidget {
  const _LevelPropertiesSection({
    super.key,
    required this.level,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneLevel level;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_LevelPropertiesSection> createState() =>
      _LevelPropertiesSectionState();
}

class _LevelPropertiesSectionState extends State<_LevelPropertiesSection> {
  late final TextEditingController _name;
  late final TextEditingController _elevation;
  late final TextEditingController _height;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.level.name);
    _elevation =
        TextEditingController(text: _number(widget.level.elevationMeters));
    _height = TextEditingController(
        text: _number(widget.level.defaultWallHeightMeters));
  }

  @override
  void dispose() {
    _name.dispose();
    _elevation.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final elevation = double.tryParse(_elevation.text.trim());
    final height = double.tryParse(_height.text.trim());
    if (elevation == null ||
        height == null ||
        height <= 0 ||
        _name.text.trim().isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.commands.updateLevel(
        levelId: widget.level.levelId,
        name: _name.text.trim(),
        elevationMeters: elevation,
        defaultWallHeightMeters: height,
      );
      await widget.onApplied(result, '${_name.text.trim()} updated.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: widget.level.name,
        icon: Icons.straighten,
        children: <Widget>[
          _field('Name', _name),
          _fieldPair(
            'Elevation (m)',
            _elevation,
            'Default wall height (m)',
            _height,
            numeric: true,
          ),
          _applyButton(_busy, _apply),
        ],
      );
}

class _ObjectPropertiesSection extends StatelessWidget {
  const _ObjectPropertiesSection({
    required this.object,
    required this.scene,
    required this.levels,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  Widget build(BuildContext context) {
    return switch (object.kindKey) {
      'wall' => _WallPropertiesSection(
          object: object,
          scene: scene,
          levels: levels,
          commands: commands,
          onApplied: onApplied),
      'door' || 'window' => _OpeningPropertiesSection(
          object: object,
          levels: levels,
          commands: commands,
          onApplied: onApplied),
      'stair' => _ReadOnlyObjectSection(
            object: object,
            title: 'Stair properties',
            rows: <String, String>{
              'Base level': _meta(object, 'base_level_id'),
              'Top level': _meta(object, 'top_level_id'),
              'Width (m)': _meta(object, 'width_meters'),
              'Run / rise (m)':
                  '${_meta(object, 'total_run_meters')} / ${_meta(object, 'total_rise_meters')}',
              'Treads / risers':
                  '${_meta(object, 'tread_count')} / ${_meta(object, 'riser_count')}',
            }),
      'roof' => _RoofPropertiesSection(
          object: object, commands: commands, onApplied: onApplied),
      'floor' || 'slab' => _FloorPropertiesSection(
          object: object,
          scene: scene,
          onApplied: onApplied,
          commands: commands,
        ),
      'ceiling' => _ReadOnlyObjectSection(
            object: object,
            title: '${_label(object)} properties',
            rows: <String, String>{
              'Level': object.levelId?.toString() ?? '-',
              'Area (m²)': _meta(object, 'area_m2'),
              'Thickness (m)': _meta(object, 'thickness_meters'),
              'Vertical offset (m)': _meta(object, 'vertical_offset_meters'),
            }),
      'column' || 'beam' => _ReadOnlyObjectSection(
            object: object,
            title: '${_label(object)} properties',
            rows: <String, String>{
              'Level': object.levelId?.toString() ?? '-',
              'Height (m)': _meta(object, 'height_meters'),
              'Length (m)': _meta(object, 'length_meters'),
              'Material': object.materialCategory,
            }),
      _ => _ReadOnlyObjectSection(
            object: object,
            title: '${_label(object)} properties',
            rows: <String, String>{
              'Level': object.levelId?.toString() ?? '-',
              'Material': object.materialCategory,
            }),
    };
  }
}

class _FloorPropertiesSection extends StatefulWidget {
  const _FloorPropertiesSection({
    required this.object,
    required this.scene,
    required this.commands,
    required this.onApplied,
  });

  final RenderSceneObject object;
  final RenderScene scene;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_FloorPropertiesSection> createState() =>
      _FloorPropertiesSectionState();
}

class _FloorPropertiesSectionState extends State<_FloorPropertiesSection> {
  late int _assemblyId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assemblyId = _metaInt(widget.object, 'assembly_id') ?? 0;
  }

  @override
  void didUpdateWidget(covariant _FloorPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId) {
      _assemblyId = _metaInt(widget.object, 'assembly_id') ?? 0;
    }
  }

  Future<void> _apply() async {
    final elementId = widget.object.elementId;
    if (elementId == null || _assemblyId == 0) return;
    setState(() => _busy = true);
    try {
      final selected = widget.scene.floorTypes
          .where((floorType) => floorType.id == _assemblyId)
          .firstOrNull;
      final result = await widget.commands.setElementAssembly(
        elementId: elementId,
        assemblyId: _assemblyId,
      );
      await widget.onApplied(
        result,
        selected == null ? 'Floor type applied.' : '${selected.name} applied.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.scene.floorTypes
        .where((floorType) => floorType.id == _assemblyId)
        .firstOrNull;
    return _InspectorCard(
      title: '${_label(widget.object)} properties',
      icon: Icons.layers_outlined,
      children: <Widget>[
        if (widget.scene.floorTypes.isNotEmpty) ...<Widget>[
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: widget.scene.floorTypes.any(
              (floorType) => floorType.id == _assemblyId,
            )
                ? _assemblyId
                : null,
            decoration: _dropdownDecoration('Floor type'),
            hint: const Text('Select floor type'),
            items: [
              for (final floorType in widget.scene.floorTypes)
                DropdownMenuItem<int>(
                  value: floorType.id,
                  child: Text(
                    '${floorType.name} · ${floorType.surfaceLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (next) {
              if (next != null) setState(() => _assemblyId = next);
            },
          ),
          if (current != null)
            _row(
              'Assembly',
              '${current.surfaceLabel} · ${_number(current.totalThicknessMeters)} m · ${current.layers.length} layers',
            ),
          _applyButton(_busy, _apply, label: 'Apply floor type'),
        ] else
          _row('Floor type', _meta(widget.object, 'floor_type_name')),
        _row('Level', widget.object.levelId?.toString() ?? '-'),
        _row('Area (m²)', _meta(widget.object, 'area_m2')),
        _row('Vertical offset (m)',
            _meta(widget.object, 'vertical_offset_meters')),
      ],
    );
  }
}

class _WallPropertiesSection extends StatefulWidget {
  const _WallPropertiesSection(
      {required this.object,
      required this.scene,
      required this.levels,
      required this.commands,
      required this.onApplied});
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
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
    _base = _metaInt(widget.object, 'base_level_id') ??
        widget.object.levelId ??
        widget.levels.first.levelId;
    _top = _metaInt(widget.object, 'top_level_id') ?? 0;
    _wallTypeId = _metaInt(widget.object, 'wall_type_id') ?? 0;
    _connected = _top != 0;
  }

  @override
  void didUpdateWidget(covariant _WallPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId == widget.object.elementId &&
        oldWidget.object.revision == widget.object.revision) {
      return;
    }
    _base = _metaInt(widget.object, 'base_level_id') ??
        widget.object.levelId ??
        widget.levels.first.levelId;
    _top = _metaInt(widget.object, 'top_level_id') ?? 0;
    _wallTypeId = _metaInt(widget.object, 'wall_type_id') ?? 0;
    _connected = _top != 0;
  }

  Future<void> _applyWallType() async {
    final wallId = widget.object.elementId;
    if (wallId == null) return;
    final selected = widget.scene.wallTypes
        .where((wallType) => wallType.id == _wallTypeId)
        .firstOrNull;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.setWallType(
        wallId: wallId,
        wallTypeId: _wallTypeId,
      );
      await widget.onApplied(
        result,
        selected == null
            ? 'Wall type cleared.'
            : '${selected.name} applied to wall.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyWallLayers(
    String name,
    WallTypeCategory category,
    List<WallTypeLayerDefinition> layers,
  ) async {
    final wallId = widget.object.elementId;
    if (wallId == null || layers.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.createWallTypeForWall(
        wallId: wallId,
        category: category,
        name: name,
        layers: layers,
      );
      await widget.onApplied(result, 'Wall layers updated.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_connected && _top == _base) return;
    setState(() => _busy = true);
    try {
      final top =
          _connected ? (_top == 0 ? widget.levels.last.levelId : _top) : 0;
      final result = await widget.commands.setWallConstraints(
          wallId: widget.object.elementId!,
          baseLevelId: _base,
          topLevelId: top,
          heightMode: _connected ? 1 : 0,
          baseOffsetMeters:
              _metaDouble(widget.object, 'base_offset_meters') ?? 0,
          topOffsetMeters:
              _metaDouble(widget.object, 'top_offset_meters') ?? 0);
      await widget.onApplied(result, 'Wall constraints updated.');
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
            (value) => setState(() => _base = value),
          ),
          _compactSwitch(
            label: 'Top level constraint',
            value: _connected,
            onChanged: (value) => setState(() => _connected = value),
          ),
          if (_connected)
            _levelDrop(
              'Top level',
              _top == 0 ? widget.levels.last.levelId : _top,
              (value) => setState(() => _top = value),
            ),
          _applyButton(_busy, _apply, label: 'Apply constraints'),
          _sectionLabel('Geometry'),
          _row(
            'Size',
            '${_meta(widget.object, 'thickness_meters')} m thick · '
                '${_meta(widget.object, 'length_meters')} m long',
          ),
          _sectionLabel('Layers'),
          if (widget.scene.wallTypes.isNotEmpty) ...<Widget>[
            _wallTypeDrop(),
            _wallAssemblySummary(),
          ] else
            _row('Wall type', _meta(widget.object, 'wall_type_category')),
          _row('Layer count', '${_layerCount()} layers'),
          _WallLayersEditor(
            key: ValueKey<String>(
              'wall-layers-${widget.object.elementId}-$_wallTypeId',
            ),
            object: widget.object,
            wallType: widget.scene.wallTypes
                .where((type) => type.id == _wallTypeId)
                .firstOrNull,
            materials: widget.scene.materials,
            onApply: _applyWallLayers,
            busy: _busy,
          ),
          _applyButton(_busy, _applyWallType, label: 'Apply type'),
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
        if (next != null) setState(() => _wallTypeId = next);
      },
    );
  }

  Widget _wallAssemblySummary() {
    final wallType = widget.scene.wallTypes
        .where((candidate) => candidate.id == _wallTypeId)
        .firstOrNull;
    if (wallType == null) return const SizedBox.shrink();
    return _row('Assembly', '${_number(wallType.totalThicknessMeters)} m');
  }

  int _layerCount() {
    final profile = widget.object.metadata['layer_profile']?.toString();
    if (profile != null && profile.isNotEmpty) {
      return profile.split(';').where((layer) => layer.isNotEmpty).length;
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
              : widget.levels.first.levelId,
          decoration: _dropdownDecoration(label),
          items: [
            for (final level in widget.levels)
              DropdownMenuItem(
                  value: level.levelId,
                  child: Text(
                      '${level.name} (${_number(level.elevationMeters)} m)'))
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          });
}

class _WallLayersEditor extends StatefulWidget {
  const _WallLayersEditor({
    super.key,
    required this.object,
    required this.wallType,
    required this.materials,
    required this.onApply,
    required this.busy,
  });

  final RenderSceneObject object;
  final WallTypeDefinition? wallType;
  final List<RenderSceneMaterial> materials;
  final Future<void> Function(
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
        oldWidget.object.elementId != widget.object.elementId) {
      _disposeLayers();
      _resetFromSource();
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
      _layers = sourceLayers.map(_EditableWallLayer.fromDefinition).toList();
      return;
    }
    final materialId = widget.materials.firstOrNull?.id ?? 0;
    _layers = <_EditableWallLayer>[
      _EditableWallLayer(
        materialId: materialId,
        thicknessMeters: _metaDouble(widget.object, 'thickness_meters') ?? 0.20,
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
          function: WallLayerFunction.generic,
          priority: 0,
          structural: false,
          side: WallLayerSide.unspecified,
          wrapsOpenings: true,
          wrapsEnds: true,
        ),
      );
    });
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
  }

  Future<void> _apply() async {
    final name = _name.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a wall type name.');
      return;
    }
    final layers = <WallTypeLayerDefinition>[];
    for (final layer in _layers) {
      final thickness = double.tryParse(layer.thickness.text.trim());
      if (layer.materialId == 0 || thickness == null || thickness <= 0) {
        setState(() => _error = 'Every layer needs material and thickness.');
        return;
      }
      layers.add(layer.toDefinition(thickness));
    }
    setState(() => _error = null);
    await widget.onApply(name, _category, layers);
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
        _applyButton(widget.busy, _apply, label: 'Apply assembly'),
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
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: _field('m', layer.thickness, numeric: true),
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
    required this.function,
    required this.priority,
    required this.structural,
    required this.side,
    required this.wrapsOpenings,
    required this.wrapsEnds,
  }) : thickness = TextEditingController(text: _number(thicknessMeters));

  factory _EditableWallLayer.fromDefinition(WallTypeLayerDefinition layer) {
    return _EditableWallLayer(
      materialId: layer.materialId,
      thicknessMeters: layer.thicknessMeters,
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

class _OpeningPropertiesSection extends StatefulWidget {
  const _OpeningPropertiesSection(
      {required this.object,
      required this.levels,
      required this.commands,
      required this.onApplied});
  final RenderSceneObject object;
  final List<RenderSceneLevel> levels;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  @override
  State<_OpeningPropertiesSection> createState() =>
      _OpeningPropertiesSectionState();
}

class _OpeningPropertiesSectionState extends State<_OpeningPropertiesSection> {
  late OpeningPreset _preset;
  late int _levelId;
  bool _locked = true;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final object = widget.object;
    _preset = openingPresetForValues(
      kind: object.kindKey,
      widthMeters: _metaDouble(object, 'width_meters') ?? 0.9,
      heightMeters: _metaDouble(object, 'height_meters') ??
          (object.kindKey == 'window' ? 1.2 : 2.1),
      sillHeightMeters: _metaDouble(object, 'sill_height_meters') ??
          (object.kindKey == 'window' ? 0.9 : 0.0),
    );
    _levelId = object.levelId ??
        (widget.levels.isNotEmpty ? widget.levels.first.levelId : 0);
    _locked = _meta(object, 'level_locked') != 'false';
  }

  Future<void> _apply() async {
    final offset = _metaDouble(widget.object, 'offset_meters');
    final id = widget.object.elementId;
    if (offset == null ||
        !offset.isFinite ||
        _preset.widthMeters <= 0 ||
        _preset.heightMeters <= 0 ||
        id == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final levelOffset =
          _metaDouble(widget.object, 'level_offset_meters') ?? 0;
      await widget.commands.setOpeningLevelConstraint(
        openingId: id,
        levelId: _levelId,
        levelOffsetMeters: levelOffset,
      );
      await widget.commands.setOpeningLevelLock(openingId: id, locked: _locked);
      final result = await widget.commands.updateOpening(
          object: widget.object,
          offsetMeters: offset,
          widthMeters: _preset.widthMeters,
          heightMeters: _preset.heightMeters,
          sillHeightMeters: _preset.sillHeightMeters);
      await widget.onApplied(result, '${_label(widget.object)} updated.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
          title: _label(widget.object),
          icon: widget.object.kindKey == 'door'
              ? Icons.door_front_door_outlined
              : Icons.window_outlined,
          children: <Widget>[
            _row('Host wall', _meta(widget.object, 'host_wall_id')),
            _openingPresetDrop(),
            _row('Dimensions', _preset.dimensionsLabel),
            _openingLevelDrop(),
            _compactSwitch(
              label: 'Lock to level',
              value: _locked,
              onChanged: (value) => setState(() => _locked = value),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showAdvancedMetadata(context, widget.object),
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Advanced details'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
            _applyButton(_busy, _apply),
          ]);

  Widget _openingPresetDrop() {
    final presets = openingPresetsForKind(widget.object.kindKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _preset.id,
        decoration: _dropdownDecoration('Type'),
        items: <DropdownMenuItem<String>>[
          for (final preset in presets)
            DropdownMenuItem<String>(
              value: preset.id,
              child: Text(preset.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          setState(() {
            _preset = presets.firstWhere((preset) => preset.id == id);
          });
        },
      ),
    );
  }

  Widget _openingLevelDrop() => DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: widget.levels.any((level) => level.levelId == _levelId)
            ? _levelId
            : (widget.levels.isNotEmpty ? widget.levels.first.levelId : null),
        decoration: _dropdownDecoration('Base level'),
        items: <DropdownMenuItem<int>>[
          for (final level in widget.levels)
            DropdownMenuItem<int>(
              value: level.levelId,
              child: Text(
                '${level.name} (${_number(level.elevationMeters)} m)',
              ),
            ),
        ],
        onChanged: widget.levels.isEmpty
            ? null
            : (value) {
                if (value != null) setState(() => _levelId = value);
              },
      );
}

class _RoofPropertiesSection extends StatefulWidget {
  const _RoofPropertiesSection({
    required this.object,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_RoofPropertiesSection> createState() => _RoofPropertiesSectionState();
}

class _RoofPropertiesSectionState extends State<_RoofPropertiesSection> {
  late int _roofType;
  late final TextEditingController _slope;
  late final TextEditingController _overhang;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final roofType = _meta(widget.object, 'roof_type');
    _roofType = roofType == 'SimpleGable'
        ? 1
        : roofType == 'AutoFootprint'
            ? 2
            : 0;
    _slope = TextEditingController(
        text: _meta(widget.object, 'slope_degrees') == '-'
            ? '25'
            : _meta(widget.object, 'slope_degrees'));
    _overhang = TextEditingController(
        text: _meta(widget.object, 'overhang_meters') == '-'
            ? '0'
            : _meta(widget.object, 'overhang_meters'));
  }

  @override
  void dispose() {
    _slope.dispose();
    _overhang.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final id = widget.object.elementId;
    final slope = double.tryParse(_slope.text.trim());
    final overhang = double.tryParse(_overhang.text.trim());
    if (id == null ||
        overhang == null ||
        (_roofType != 0 && (slope == null || slope <= 0 || slope >= 75))) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.commands.updateRoofProperties(
        roofId: id,
        roofType: _roofType,
        slopeDegrees: _roofType == 0 ? null : slope,
        overhangMeters: overhang,
      );
      await widget.onApplied(result, 'Roof properties updated.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: 'Roof properties',
        icon: Icons.roofing_outlined,
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: _roofType,
            decoration: _dropdownDecoration('Roof shape'),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem(value: 0, child: Text('Flat')),
              DropdownMenuItem(value: 1, child: Text('Simple gable')),
              DropdownMenuItem(value: 2, child: Text('Auto footprint (L/U)')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _roofType = value);
            },
          ),
          if (_roofType != 0)
            _fieldPair(
              'Slope (degrees)',
              _slope,
              'Overhang (m)',
              _overhang,
              numeric: true,
            )
          else
            _field('Overhang (m)', _overhang, numeric: true),
          _applyButton(_busy, _apply),
        ],
      );
}

class _ReadOnlyObjectSection extends StatelessWidget {
  const _ReadOnlyObjectSection(
      {required this.object, required this.title, required this.rows});
  final RenderSceneObject object;
  final String title;
  final Map<String, String> rows;
  @override
  Widget build(BuildContext context) => _InspectorCard(
          title: title,
          icon: _icon(object.kindKey),
          children: <Widget>[
            for (final entry in rows.entries) _row(entry.key, entry.value),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showAdvancedMetadata(context, object),
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Advanced details'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
          ]);
}

Future<void> _showAdvancedMetadata(
  BuildContext context,
  RenderSceneObject object,
) async {
  final entries = <MapEntry<String, String>>[
    MapEntry<String, String>('Element ID', object.elementId?.toString() ?? '-'),
    MapEntry<String, String>('Kind', object.kind),
    MapEntry<String, String>('Level ID', object.levelId?.toString() ?? '-'),
    ...object.metadata.entries.map(
      (entry) => MapEntry<String, String>(entry.key, entry.value.toString()),
    ),
  ];
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Advanced details'),
      content: SizedBox(
        width: 420,
        child: entries.isEmpty
            ? const Text('No additional data.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            entry.value,
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _DeleteElementButton extends StatefulWidget {
  const _DeleteElementButton({
    required this.object,
    required this.commands,
    required this.onApplied,
  });

  final RenderSceneObject object;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_DeleteElementButton> createState() => _DeleteElementButtonState();
}

class _DeleteElementButtonState extends State<_DeleteElementButton> {
  bool _busy = false;

  Future<void> _delete() async {
    final id = widget.object.elementId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.deleteElement(id);
      await widget.onApplied(result, '${_label(widget.object)} deleted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          minimumSize: const Size.fromHeight(38),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _busy ? null : _delete,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_outline),
        label: const Text('Delete element'),
      );
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard(
      {required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.titleSmall))
                ]),
                const SizedBox(height: 10),
                ...children
              ])));
}

Widget _field(String label, TextEditingController controller,
        {bool numeric = false}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
            controller: controller,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(fontSize: 13),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)))));

Widget _fieldPair(
  String firstLabel,
  TextEditingController firstController,
  String secondLabel,
  TextEditingController secondController, {
  bool numeric = false,
}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _field(firstLabel, firstController, numeric: numeric)),
        const SizedBox(width: 8),
        Expanded(
            child: _field(secondLabel, secondController, numeric: numeric)),
      ],
    );

Widget _sectionLabel(String label) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          textBaseline: TextBaseline.alphabetic,
        ),
      ),
    );

Widget _compactSwitch({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) =>
    SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );

InputDecoration _dropdownDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );

Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      )
    ]));
Widget _applyButton(bool busy, VoidCallback onPressed,
        {String label = 'Apply'}) =>
    FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(38),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(label));
String _number(double value) => value.toStringAsFixed(2);
String _meta(RenderSceneObject object, String key) =>
    object.metadata[key]?.toString() ?? '-';
int? _metaInt(RenderSceneObject object, String key) =>
    int.tryParse(_meta(object, key));
double? _metaDouble(RenderSceneObject object, String key) =>
    double.tryParse(_meta(object, key));
String _label(RenderSceneObject object) =>
    BimElementRegistry.standard.displayName(object.kind);
IconData _icon(String kind) => switch (kind) {
      'stair' => Icons.stairs_outlined,
      'roof' => Icons.roofing_outlined,
      'floor' || 'ceiling' || 'slab' => Icons.layers_outlined,
      'column' => Icons.view_column_outlined,
      'beam' => Icons.horizontal_rule,
      _ => Icons.category_outlined
    };
