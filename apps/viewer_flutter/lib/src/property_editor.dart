import 'package:flutter/material.dart';

import 'authoring_command_service.dart';
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
  });

  final RenderScene scene;
  final InspectorTarget target;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return switch (target.kind) {
      InspectorTargetKind.empty => const _InspectorCard(
          title: 'Properties',
          icon: Icons.tune,
          children: <Widget>[
            Text(
                'Obyektni tanlang. Properties faqat active selection uchun chiqadi.'),
          ],
        ),
      InspectorTargetKind.multiple => _InspectorCard(
          title: 'Multiple selection',
          icon: Icons.select_all,
          children: <Widget>[
            Text('${target.objects.length} ta obyekt tanlangan.'),
            const SizedBox(height: 8),
            const Text(
                'Batch edit faqat umumiy va xavfsiz propertylar uchun keyingi qatlamda ochiladi.'),
            TextButton.icon(
              onPressed: onClearSelection,
              icon: const Icon(Icons.clear),
              label: const Text('Clear selection'),
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
  }
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
          _field('Elevation (m)', _elevation, numeric: true),
          _field('Default wall height (m)', _height, numeric: true),
          _applyButton(_busy, _apply),
        ],
      );
}

class _ObjectPropertiesSection extends StatelessWidget {
  const _ObjectPropertiesSection({
    required this.object,
    required this.levels,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final List<RenderSceneLevel> levels;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  Widget build(BuildContext context) {
    return switch (object.kindKey) {
      'wall' => _WallPropertiesSection(
          object: object,
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
              'Run (m)': _meta(object, 'total_run_meters'),
              'Rise (m)': _meta(object, 'total_rise_meters'),
              'Treads / risers':
                  '${_meta(object, 'tread_count')} / ${_meta(object, 'riser_count')}',
            }),
      'floor' || 'ceiling' || 'roof' || 'slab' => _ReadOnlyObjectSection(
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

class _WallPropertiesSection extends StatefulWidget {
  const _WallPropertiesSection(
      {required this.object,
      required this.levels,
      required this.commands,
      required this.onApplied});
  final RenderSceneObject object;
  final List<RenderSceneLevel> levels;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  @override
  State<_WallPropertiesSection> createState() => _WallPropertiesSectionState();
}

class _WallPropertiesSectionState extends State<_WallPropertiesSection> {
  late int _base;
  late int _top;
  late bool _connected;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _base = _metaInt(widget.object, 'base_level_id') ??
        widget.object.levelId ??
        widget.levels.first.levelId;
    _top = _metaInt(widget.object, 'top_level_id') ?? 0;
    _connected = _top != 0;
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
            _row('Thickness', '${_meta(widget.object, 'thickness_meters')} m'),
            _row('Length', '${_meta(widget.object, 'length_meters')} m'),
            _levelDrop(
                'Base level', _base, (value) => setState(() => _base = value)),
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Top level constraint'),
                value: _connected,
                onChanged: (value) => setState(() => _connected = value)),
            if (_connected)
              _levelDrop(
                  'Top level',
                  _top == 0 ? widget.levels.last.levelId : _top,
                  (value) => setState(() => _top = value)),
            _applyButton(_busy, _apply),
          ]);
  Widget _levelDrop(String label, int value, ValueChanged<int> onChanged) =>
      DropdownButtonFormField<int>(
          initialValue: widget.levels.any((level) => level.levelId == value)
              ? value
              : widget.levels.first.levelId,
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
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
          title: '${_label(widget.object)} properties',
          icon: widget.object.kindKey == 'door'
              ? Icons.door_front_door_outlined
              : Icons.window_outlined,
          children: <Widget>[
            _row('Host wall', _meta(widget.object, 'host_wall_id')),
            DropdownButtonFormField<int>(
              initialValue: _levelId,
              decoration: const InputDecoration(
                  labelText: 'Base level',
                  isDense: true,
                  border: OutlineInputBorder()),
              items: <DropdownMenuItem<int>>[
                for (final level in widget.levels)
                  DropdownMenuItem<int>(
                    value: level.levelId,
                    child: Text(
                        '${level.name} (${_number(level.elevationMeters)} m)'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _levelId = value);
                }
              },
            ),
            const SizedBox(height: 8),
            _field('Level offset (m)', _levelOffset, numeric: true),
            _field('Offset (m)', _offset, numeric: true),
            _field('Width (m)', _width, numeric: true),
            _field('Height (m)', _height, numeric: true),
            if (widget.object.kindKey == 'window')
              _field('Sill height (m)', _sill, numeric: true),
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lock to level'),
                value: _locked,
                onChanged: (value) => setState(() => _locked = value)),
            _applyButton(_busy, _apply),
          ]);
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
            const SizedBox(height: 4),
            const Text(
                'Bu propertylar engine snapshotidan keladi. Tahrirlash commandi hali ochilmagan, shuning uchun noto‘g‘ri local edit yo‘q.'),
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
            foregroundColor: Theme.of(context).colorScheme.error),
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
      elevation: 0,
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(title,
                          style: Theme.of(context).textTheme.titleSmall))
                ]),
                const SizedBox(height: 12),
                ...children
              ])));
}

Widget _field(String label, TextEditingController controller,
        {bool numeric = false}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
            controller: controller,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border: const OutlineInputBorder())));
Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
    ]));
Widget _applyButton(bool busy, VoidCallback onPressed) => FilledButton.icon(
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox.square(
            dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.check),
    label: const Text('Apply'));
String _number(double value) => value.toStringAsFixed(2);
String _meta(RenderSceneObject object, String key) =>
    object.metadata[key]?.toString() ?? '-';
int? _metaInt(RenderSceneObject object, String key) =>
    int.tryParse(_meta(object, key));
double? _metaDouble(RenderSceneObject object, String key) =>
    double.tryParse(_meta(object, key));
String _label(RenderSceneObject object) => object.kindKey.isEmpty
    ? 'Object'
    : '${object.kindKey[0].toUpperCase()}${object.kindKey.substring(1)}';
IconData _icon(String kind) => switch (kind) {
      'stair' => Icons.stairs_outlined,
      'roof' => Icons.roofing_outlined,
      'floor' || 'ceiling' || 'slab' => Icons.layers_outlined,
      'column' => Icons.view_column_outlined,
      'beam' => Icons.horizontal_rule,
      _ => Icons.category_outlined
    };
