import 'dart:async';

import 'package:flutter/material.dart';

import 'authoring_command_service.dart';
import 'elements/bim_element_registry.dart';
import 'elements/bim_element_module.dart';
import 'elements/inspector_registry.dart';
import 'elements/linear_parameters.dart';
import 'elements/opening_type_catalog.dart';
import 'elements/opening_parameters.dart';
import 'elements/roof_parameters.dart';
import 'elements/stair_parameters.dart';
import 'elements/surface_parameters.dart';
import 'elements/wall_type_catalog.dart';
import 'elements/wall_parameters.dart';
import 'inspector_controller.dart';
import 'project_unit_settings.dart';
import 'render_scene_models.dart';

part 'elements/inspectors/object_inspector_router.dart';
part 'elements/inspectors/floor_inspector.dart';
part 'elements/inspectors/wall_inspector.dart';
part 'elements/inspectors/opening_inspector.dart';
part 'elements/inspectors/roof_inspector.dart';
part 'elements/inspectors/stair_inspector.dart';
part 'elements/inspectors/ceiling_inspector.dart';
part 'elements/inspectors/linear_inspector.dart';
part 'elements/inspectors/generic_inspector.dart';

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
    required this.units,
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
  final ProjectUnitSettings units;
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
          units: units,
          commands: commands,
          onApplied: onApplied,
        ),
      InspectorTargetKind.object => Column(
          key: ValueKey<String>('object-${target.object!.elementId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ObjectInspectorRouter(
              object: target.object!,
              scene: scene,
              levels: scene.levels,
              units: units,
              commands: commands,
              onApplied: onApplied,
            ),
          ],
        ),
    };
    final sections = <Widget>[properties];
    if (showPlanViewRange &&
        target.kind != InspectorTargetKind.object &&
        target.kind != InspectorTargetKind.multiple) {
      sections
        ..add(const SizedBox(height: 8))
        ..add(
          _PlanViewRangeSection(
            level: activePlanLevel,
            units: units,
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
    required this.units,
    required this.value,
    required this.onChanged,
  });

  final RenderSceneLevel? level;
  final ProjectUnitSettings units;
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
    _controller = TextEditingController(
      text: _number(widget.value, units: widget.units, withUnit: false),
    );
  }

  @override
  void didUpdateWidget(covariant _PlanViewRangeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy &&
        (oldWidget.value != widget.value || oldWidget.units != widget.units)) {
      _controller.text =
          _number(widget.value, units: widget.units, withUnit: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final displayValue = double.tryParse(_controller.text.trim());
    final value =
        displayValue == null ? null : widget.units.toMeters(displayValue);
    if (value == null || !value.isFinite || value <= 0.05 || value > 20.0) {
      _controller.text =
          _number(widget.value, units: widget.units, withUnit: false);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onChanged(value);
    } catch (_) {
      if (mounted) {
        _controller.text =
            _number(widget.value, units: widget.units, withUnit: false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: 'View range · ${widget.level?.name ?? 'Active level'}',
        icon: Icons.height,
        children: <Widget>[
          _field('Cut height (${widget.units.lengthSymbol})', _controller,
              numeric: true, onEditingComplete: _save),
        ],
      );
}

class _LevelPropertiesSection extends StatefulWidget {
  const _LevelPropertiesSection({
    super.key,
    required this.level,
    required this.units,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneLevel level;
  final ProjectUnitSettings units;
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
    _elevation = TextEditingController(
        text: _number(widget.level.elevationMeters,
            units: widget.units, withUnit: false));
    _height = TextEditingController(
        text: _number(widget.level.defaultWallHeightMeters,
            units: widget.units, withUnit: false));
  }

  @override
  void didUpdateWidget(covariant _LevelPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldElevation = _number(
      oldWidget.level.elevationMeters,
      units: oldWidget.units,
      withUnit: false,
    );
    final oldHeight = _number(
      oldWidget.level.defaultWallHeightMeters,
      units: oldWidget.units,
      withUnit: false,
    );
    if (oldWidget.units != widget.units || _elevation.text == oldElevation) {
      _elevation.text = _number(widget.level.elevationMeters,
          units: widget.units, withUnit: false);
    }
    if (oldWidget.units != widget.units || _height.text == oldHeight) {
      _height.text = _number(widget.level.defaultWallHeightMeters,
          units: widget.units, withUnit: false);
    }
    if (_name.text == oldWidget.level.name) _name.text = widget.level.name;
  }

  @override
  void dispose() {
    _name.dispose();
    _elevation.dispose();
    _height.dispose();
    super.dispose();
  }

  void _restoreFromLevel() {
    _name.text = widget.level.name;
    _elevation.text = _number(widget.level.elevationMeters,
        units: widget.units, withUnit: false);
    _height.text = _number(widget.level.defaultWallHeightMeters,
        units: widget.units, withUnit: false);
  }

  Future<void> _save() async {
    if (_busy) return;
    final displayElevation = double.tryParse(_elevation.text.trim());
    final displayHeight = double.tryParse(_height.text.trim());
    final elevation = displayElevation == null
        ? null
        : widget.units.toMeters(displayElevation);
    final height =
        displayHeight == null ? null : widget.units.toMeters(displayHeight);
    if (elevation == null ||
        height == null ||
        !elevation.isFinite ||
        !height.isFinite ||
        height <= 0 ||
        _name.text.trim().isEmpty) {
      _restoreFromLevel();
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
      if (result.scene == null) {
        if (mounted) _restoreFromLevel();
        return;
      }
      await widget.onApplied(result, '${_name.text.trim()} updated.');
    } catch (_) {
      if (mounted) _restoreFromLevel();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: widget.level.name,
        icon: Icons.straighten,
        children: <Widget>[
          _field('Name', _name, onEditingComplete: _save),
          _fieldPair(
            'Elevation (${widget.units.lengthSymbol})',
            _elevation,
            'Default wall height (${widget.units.lengthSymbol})',
            _height,
            numeric: true,
            onEditingComplete: _save,
          ),
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

Widget _field(
  String label,
  TextEditingController controller, {
  bool numeric = false,
  ValueChanged<String>? onChanged,
  VoidCallback? onEditingComplete,
}) =>
    Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
            controller: controller,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            onEditingComplete: onEditingComplete,
            onTapOutside:
                onEditingComplete == null ? null : (_) => onEditingComplete(),
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
  VoidCallback? onEditingComplete,
}) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
            child: _field(firstLabel, firstController,
                numeric: numeric, onEditingComplete: onEditingComplete)),
        const SizedBox(width: 8),
        Expanded(
            child: _field(secondLabel, secondController,
                numeric: numeric, onEditingComplete: onEditingComplete)),
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
  required ValueChanged<bool>? onChanged,
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
String _number(
  double value, {
  ProjectUnitSettings? units,
  bool withUnit = false,
}) =>
    units == null
        ? value.toStringAsFixed(2)
        : units.formatLength(value, withUnit: withUnit);
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
