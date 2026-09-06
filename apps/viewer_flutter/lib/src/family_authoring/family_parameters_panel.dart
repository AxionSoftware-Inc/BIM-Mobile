import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_parameter_authoring.dart';
import 'family_parameter_resolver.dart';

/// Reusable UI for Family parameter definitions and named Family Types.
///
/// All mutations go through [FamilyParameterAuthoring], so this panel never
/// owns a second set of validation/migration rules.
class FamilyParametersPanel extends StatelessWidget {
  const FamilyParametersPanel({
    super.key,
    required this.document,
    required this.type,
    required this.onChanged,
    required this.onStatus,
  });

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final ValueChanged<FamilyDocument> onChanged;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolver = FamilyParameterResolver(document, type);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Family parameters',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${type.name} · ${document.parameters.length} parameters · ${document.types.length} types',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Add parameter',
                  onPressed: () => _addParameter(context),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _duplicateType(context),
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Duplicate type'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _renameType(context),
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('Rename type'),
                ),
                OutlinedButton.icon(
                  onPressed: document.types.length <= 1
                      ? null
                      : () => _removeType(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete type'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final parameter in document.parameters)
              _parameterTile(context, parameter, resolver),
          ],
        ),
      ),
    );
  }

  Widget _parameterTile(
    BuildContext context,
    FamilyParameterDefinition parameter,
    FamilyParameterResolver resolver,
  ) {
    final protected = FamilyParameterAuthoring.protectedCoreParameterIds
        .contains(parameter.id);
    Object? resolved;
    String? error;
    try {
      resolved = resolver.resolve(parameter);
    } catch (caught) {
      error = _errorText(caught);
    }
    final formula = parameter.formula?.trim();
    final summary = <String>[
      parameter.id,
      _kindLabel(parameter.kind),
      if (formula?.isNotEmpty == true) '= $formula',
      if (formula?.isNotEmpty != true && error == null)
        '${_displayValue(resolved)}${_unit(parameter.kind)}',
      if (error != null) error,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(_kindIcon(parameter.kind), size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        parameter.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (protected) ...<Widget>[
                      const SizedBox(width: 5),
                      const Tooltip(
                        message: 'Core Family sizing parameter',
                        child: Icon(Icons.lock_outline, size: 14),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: error == null
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ),
          ),
          if (!parameter.hasFormula)
            IconButton(
              tooltip: 'Edit ${type.name} value',
              visualDensity: VisualDensity.compact,
              onPressed: () => _editTypeValue(context, parameter),
              icon: const Icon(Icons.tune_outlined, size: 19),
            ),
          IconButton(
            tooltip: 'Edit parameter',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editParameter(context, parameter),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          if (!protected)
            IconButton(
              tooltip: 'Delete parameter',
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeParameter(context, parameter),
              icon: const Icon(Icons.delete_outline, size: 19),
            ),
        ],
      ),
    );
  }

  Future<void> _addParameter(BuildContext context) async {
    final draft = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => const _ParameterDialog(),
    );
    if (draft == null) return;
    _run(
      () => FamilyParameterAuthoring.addParameter(
        document,
        label: draft.label,
        kind: draft.kind,
        defaultValue: draft.defaultValue,
        formula: draft.formula,
        minimum: draft.minimum,
        maximum: draft.maximum,
      ),
      'Parameter ${draft.label} added.',
    );
  }

  Future<void> _editParameter(
    BuildContext context,
    FamilyParameterDefinition parameter,
  ) async {
    final draft = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => _ParameterDialog(parameter: parameter),
    );
    if (draft == null) return;
    _run(
      () => FamilyParameterAuthoring.updateParameter(
        document,
        parameterId: parameter.id,
        label: draft.label,
        defaultValue: draft.defaultValue,
        formula: draft.formula,
        clearFormula: draft.formula.trim().isEmpty,
        minimum: draft.minimum,
        maximum: draft.maximum,
      ),
      'Parameter ${draft.label} updated.',
    );
  }

  Future<void> _removeParameter(
    BuildContext context,
    FamilyParameterDefinition parameter,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${parameter.label}?'),
        content: const Text(
          'Deletion is allowed only when no formula, feature, reference plane or constraint still uses this parameter.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _run(
      () => FamilyParameterAuthoring.removeParameter(document, parameter.id),
      'Parameter ${parameter.label} deleted.',
    );
  }

  Future<void> _editTypeValue(
    BuildContext context,
    FamilyParameterDefinition parameter,
  ) async {
    final current = type.values.containsKey(parameter.id)
        ? type.values[parameter.id]
        : parameter.defaultValue;
    final raw = await _valueDialog(
      context,
      title: '${type.name} · ${parameter.label}',
      initialValue: _displayValue(current),
      helper: _valueHelper(parameter.kind),
    );
    if (raw == null) return;
    Object? value;
    try {
      value = _parseValue(parameter.kind, raw);
    } catch (error) {
      onStatus(_errorText(error));
      return;
    }
    _run(
      () => FamilyParameterAuthoring.setTypeValue(
        document,
        typeId: type.id,
        parameterId: parameter.id,
        value: value,
      ),
      '${type.name} · ${parameter.label} updated.',
    );
  }

  Future<void> _duplicateType(BuildContext context) async {
    final name = await _valueDialog(
      context,
      title: 'Duplicate Family Type',
      initialValue: '${type.name} Copy',
      helper: 'The new type copies every explicit value from ${type.name}.',
    );
    if (name == null || name.trim().isEmpty) return;
    _run(
      () => FamilyParameterAuthoring.duplicateType(
        document,
        sourceTypeId: type.id,
        name: name,
      ),
      'Family Type ${name.trim()} created.',
    );
  }

  Future<void> _renameType(BuildContext context) async {
    final name = await _valueDialog(
      context,
      title: 'Rename Family Type',
      initialValue: type.name,
      helper: 'Type id stays stable; nested-family references are not rewritten.',
    );
    if (name == null || name.trim().isEmpty) return;
    _run(
      () => FamilyParameterAuthoring.renameType(
        document,
        typeId: type.id,
        name: name,
      ),
      'Family Type renamed to ${name.trim()}.',
    );
  }

  Future<void> _removeType(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Family Type ${type.name}?'),
        content: const Text(
          'This removes the type from this family. Any external nested-family dependency that points to this type must be updated separately.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete type'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _run(
      () => FamilyParameterAuthoring.removeType(document, type.id),
      'Family Type ${type.name} deleted.',
    );
  }

  void _run(FamilyDocument Function() command, String success) {
    try {
      onChanged(command());
      onStatus(success);
    } catch (error) {
      onStatus(_errorText(error));
    }
  }

  static Future<String?> _valueDialog(
    BuildContext context, {
    required String title,
    required String initialValue,
    required String helper,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                helperText: helper,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  static Object _parseValue(FamilyParameterKind kind, String raw) {
    final value = raw.trim();
    switch (kind) {
      case FamilyParameterKind.boolean:
        if (value.toLowerCase() == 'true') return true;
        if (value.toLowerCase() == 'false') return false;
        throw const FormatException('Boolean value must be true or false.');
      case FamilyParameterKind.text:
      case FamilyParameterKind.material:
        if (value.isEmpty) {
          throw const FormatException('Text/material value cannot be empty.');
        }
        return value;
      case FamilyParameterKind.length:
      case FamilyParameterKind.number:
      case FamilyParameterKind.angle:
        final number = double.tryParse(value.replaceAll(',', '.'));
        if (number == null || !number.isFinite) {
          throw const FormatException('Numeric value must be finite.');
        }
        return number;
    }
  }

  static String _displayValue(Object? value) {
    if (value is double) {
      final fixed = value.toStringAsFixed(4);
      return fixed
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '$value';
  }

  static String _unit(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => ' m',
        FamilyParameterKind.angle => '°',
        _ => '',
      };

  static String _valueHelper(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => 'Length in meters.',
        FamilyParameterKind.number => 'Finite numeric value.',
        FamilyParameterKind.angle => 'Angle in degrees.',
        FamilyParameterKind.material => 'Material token/name.',
        FamilyParameterKind.text => 'Non-empty text.',
        FamilyParameterKind.boolean => 'Enter true or false.',
      };

  static String _kindLabel(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => 'Length',
        FamilyParameterKind.number => 'Number',
        FamilyParameterKind.angle => 'Angle',
        FamilyParameterKind.material => 'Material',
        FamilyParameterKind.text => 'Text',
        FamilyParameterKind.boolean => 'Yes/No',
      };

  static IconData _kindIcon(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => Icons.straighten,
        FamilyParameterKind.number => Icons.numbers,
        FamilyParameterKind.angle => Icons.architecture,
        FamilyParameterKind.material => Icons.texture,
        FamilyParameterKind.text => Icons.text_fields,
        FamilyParameterKind.boolean => Icons.toggle_on_outlined,
      };

  static String _errorText(Object error) =>
      error is FormatException ? error.message : '$error';
}

final class _ParameterDraft {
  const _ParameterDraft({
    required this.label,
    required this.kind,
    required this.defaultValue,
    required this.formula,
    this.minimum,
    this.maximum,
  });

  final String label;
  final FamilyParameterKind kind;
  final Object defaultValue;
  final String formula;
  final double? minimum;
  final double? maximum;
}

class _ParameterDialog extends StatefulWidget {
  const _ParameterDialog({this.parameter});

  final FamilyParameterDefinition? parameter;

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  late final TextEditingController _label;
  late final TextEditingController _defaultValue;
  late final TextEditingController _formula;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late FamilyParameterKind _kind;
  String? _error;

  bool get _editing => widget.parameter != null;
  bool get _numeric => _kind == FamilyParameterKind.length ||
      _kind == FamilyParameterKind.number ||
      _kind == FamilyParameterKind.angle;

  @override
  void initState() {
    super.initState();
    final parameter = widget.parameter;
    _kind = parameter?.kind ?? FamilyParameterKind.length;
    _label = TextEditingController(text: parameter?.label ?? '');
    _defaultValue = TextEditingController(
      text: parameter == null
          ? _defaultText(_kind)
          : FamilyParametersPanel._displayValue(parameter.defaultValue),
    );
    _formula = TextEditingController(text: parameter?.formula ?? '');
    _minimum = TextEditingController(text: parameter?.minimum?.toString() ?? '');
    _maximum = TextEditingController(text: parameter?.maximum?.toString() ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    _defaultValue.dispose();
    _formula.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit Family parameter' : 'Add Family parameter'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _label,
                autofocus: !_editing,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<FamilyParameterKind>(
                initialValue: _kind,
                decoration: InputDecoration(
                  labelText: 'Kind',
                  helperText: _editing
                      ? 'Kind is stable after creation; make a new parameter to change semantics.'
                      : null,
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<FamilyParameterKind>>[
                  for (final kind in FamilyParameterKind.values)
                    DropdownMenuItem<FamilyParameterKind>(
                      value: kind,
                      child: Text(FamilyParametersPanel._kindLabel(kind)),
                    ),
                ],
                onChanged: _editing
                    ? null
                    : (kind) {
                        if (kind == null) return;
                        setState(() {
                          _kind = kind;
                          _defaultValue.text = _defaultText(kind);
                          if (!_numeric) {
                            _formula.clear();
                            _minimum.clear();
                            _maximum.clear();
                          }
                        });
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _defaultValue,
                decoration: InputDecoration(
                  labelText: 'Default value',
                  helperText: FamilyParametersPanel._valueHelper(_kind),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_numeric) ...<Widget>[
                const SizedBox(height: 8),
                TextField(
                  controller: _formula,
                  decoration: const InputDecoration(
                    labelText: 'Formula · optional',
                    hintText: 'width / 2',
                    helperText:
                        'Formula-driven parameters ignore per-type overrides.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _minimum,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Minimum · optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maximum,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Maximum · optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_editing ? 'Apply' : 'Add'),
        ),
      ],
    );
  }

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Parameter name is required.');
      return;
    }
    Object defaultValue;
    try {
      defaultValue = FamilyParametersPanel._parseValue(
        _kind,
        _defaultValue.text,
      );
    } catch (error) {
      setState(() => _error = FamilyParametersPanel._errorText(error));
      return;
    }
    double? parseOptional(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        throw const FormatException('Minimum/maximum must be finite numbers.');
      }
      return value;
    }

    try {
      final minimum = _numeric ? parseOptional(_minimum) : null;
      final maximum = _numeric ? parseOptional(_maximum) : null;
      Navigator.of(context).pop(
        _ParameterDraft(
          label: label,
          kind: _kind,
          defaultValue: defaultValue,
          formula: _numeric ? _formula.text.trim() : '',
          minimum: minimum,
          maximum: maximum,
        ),
      );
    } catch (error) {
      setState(() => _error = FamilyParametersPanel._errorText(error));
    }
  }

  static String _defaultText(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => '1.0',
        FamilyParameterKind.number => '0',
        FamilyParameterKind.angle => '0',
        FamilyParameterKind.material => 'Default',
        FamilyParameterKind.text => 'Value',
        FamilyParameterKind.boolean => 'false',
      };
}
