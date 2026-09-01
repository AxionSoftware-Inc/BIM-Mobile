import 'package:flutter/material.dart';

import 'authoring_command_service.dart';
import 'elements/bim_element_registry.dart';
import 'inspector_controller.dart';
import 'render_scene_models.dart';

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
          viewRangeMeters: viewRangeMeters,
          onViewRangeChanged: onViewRangeChanged,
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
            const SizedBox(height: 8),
            _DeleteElementButton(
              object: target.object!,
              commands: commands,
              onApplied: onApplied,
            ),
          ],
        ),
    };
    if (!showPlanViewRange || target.kind == InspectorTargetKind.level) {
      return properties;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PlanViewRangeSection(
          level: activePlanLevel,
          value: viewRangeMeters,
          onChanged: onViewRangeChanged,
        ),
        const SizedBox(height: 8),
        properties,
      ],
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
    required this.viewRangeMeters,
    required this.onViewRangeChanged,
  });
  final RenderSceneLevel level;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  final double viewRangeMeters;
  final Future<void> Function(double value) onViewRangeChanged;

  @override
  State<_LevelPropertiesSection> createState() =>
      _LevelPropertiesSectionState();
}

class _LevelPropertiesSectionState extends State<_LevelPropertiesSection> {
  late final TextEditingController _name;
  late final TextEditingController _elevation;
  late final TextEditingController _height;
  late final TextEditingController _viewRange;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.level.name);
    _elevation =
        TextEditingController(text: _number(widget.level.elevationMeters));
    _height = TextEditingController(
        text: _number(widget.level.defaultWallHeightMeters));
    _viewRange = TextEditingController(text: _number(widget.viewRangeMeters));
  }

  @override
  void dispose() {
    _name.dispose();
    _elevation.dispose();
    _height.dispose();
    _viewRange.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final elevation = double.tryParse(_elevation.text.trim());
    final height = double.tryParse(_height.text.trim());
    final viewRange = double.tryParse(_viewRange.text.trim());
    if (elevation == null ||
        height == null ||
        viewRange == null ||
        height <= 0 ||
        viewRange <= 0.05 ||
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
      await widget.onViewRangeChanged(viewRange);
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
          _field('Plan view range / cut height (m)', _viewRange, numeric: true),
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
          if (widget.scene.wallTypes.isNotEmpty) ...<Widget>[
            _wallTypeDrop(),
            _wallAssemblySummary(),
            _applyButton(_busy, _applyWallType, label: 'Apply type'),
          ] else
            _row('Wall type', _meta(widget.object, 'wall_type_category')),
          _row('Layer count', '${_layerCount()} layers'),
          _sectionLabel('Geometry'),
          _row(
            'Size',
            '${_meta(widget.object, 'thickness_meters')} m thick · '
                '${_meta(widget.object, 'length_meters')} m long',
          ),
          _sectionLabel('Constraints'),
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
  late final TextEditingController _offset;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _sill;
  late final TextEditingController _levelOffset;
  late int _levelId;
  bool _locked = true;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final object = widget.object;
    _offset = TextEditingController(text: _meta(object, 'offset_meters'));
    _width = TextEditingController(text: _meta(object, 'width_meters'));
    _height = TextEditingController(text: _meta(object, 'height_meters'));
    _sill = TextEditingController(text: _meta(object, 'sill_height_meters'));
    _levelOffset = TextEditingController(
        text: _meta(object, 'level_offset_meters') == '-'
            ? '0.00'
            : _meta(object, 'level_offset_meters'));
    _levelId = object.levelId ?? widget.levels.first.levelId;
    _locked = _meta(object, 'level_locked') != 'false';
  }

  @override
  void dispose() {
    _offset.dispose();
    _width.dispose();
    _height.dispose();
    _sill.dispose();
    _levelOffset.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final offset = double.tryParse(_offset.text);
    final width = double.tryParse(_width.text);
    final height = double.tryParse(_height.text);
    final sill = double.tryParse(_sill.text) ?? 0;
    final id = widget.object.elementId;
    if (offset == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        id == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final levelOffset = double.tryParse(_levelOffset.text) ?? 0;
      await widget.commands.setOpeningLevelConstraint(
        openingId: id,
        levelId: _levelId,
        levelOffsetMeters: levelOffset,
      );
      await widget.commands.setOpeningLevelLock(openingId: id, locked: _locked);
      final result = await widget.commands.updateOpening(
          object: widget.object,
          offsetMeters: offset,
          widthMeters: width,
          heightMeters: height,
          sillHeightMeters: sill);
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
            _sectionLabel('Placement & size'),
            _openingLevelDrop(),
            _fieldPair(
              'Offset (m)',
              _offset,
              'Level offset (m)',
              _levelOffset,
              numeric: true,
            ),
            _fieldPair(
              'Width (m)',
              _width,
              'Height (m)',
              _height,
              numeric: true,
            ),
            if (widget.object.kindKey == 'window')
              _field('Sill height (m)', _sill, numeric: true),
            _compactSwitch(
              label: 'Lock to level',
              value: _locked,
              onChanged: (value) => setState(() => _locked = value),
            ),
            _applyButton(_busy, _apply),
          ]);

  Widget _openingLevelDrop() => DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: widget.levels.any((level) => level.levelId == _levelId)
            ? _levelId
            : widget.levels.first.levelId,
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
        onChanged: (value) {
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
          ]);
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
