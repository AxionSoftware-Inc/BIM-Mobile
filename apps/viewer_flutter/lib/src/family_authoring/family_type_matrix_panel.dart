import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_parameter_authoring.dart';

/// Spreadsheet-like Family Type editor for tablet authoring.
///
/// Rows are named Family Types and columns are editable, non-formula
/// parameters. Every mutation is delegated to [FamilyParameterAuthoring], so
/// the matrix cannot bypass the semantic validator or stable-id rules.
class FamilyTypeMatrixPanel extends StatefulWidget {
  const FamilyTypeMatrixPanel({
    super.key,
    required this.document,
    required this.currentTypeId,
    required this.onChanged,
    required this.onStatus,
  });

  final FamilyDocument document;
  final String currentTypeId;
  final ValueChanged<FamilyDocument> onChanged;
  final ValueChanged<String> onStatus;

  @override
  State<FamilyTypeMatrixPanel> createState() => _FamilyTypeMatrixPanelState();
}

class _FamilyTypeMatrixPanelState extends State<FamilyTypeMatrixPanel> {
  bool _showAllParameters = false;

  List<FamilyParameterDefinition> get _editableParameters {
    final parameters = widget.document.parameters
        .where((parameter) => !parameter.hasFormula)
        .toList(growable: false);
    if (_showAllParameters) return parameters;
    return parameters
        .where(
          (parameter) => FamilyParameterAuthoring.protectedCoreParameterIds
              .contains(parameter.id),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final parameters = _editableParameters;
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
                        'Family Type matrix',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.document.types.length} types · tap a value to edit',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  selected: _showAllParameters,
                  label: Text(_showAllParameters ? 'All parameters' : 'Core dimensions'),
                  onSelected: (selected) {
                    setState(() => _showAllParameters = selected);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (parameters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No editable parameters in this view.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 8,
                  columns: <DataColumn>[
                    const DataColumn(label: Text('Type')),
                    for (final parameter in parameters)
                      DataColumn(label: Text(parameter.label)),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: <DataRow>[
                    for (final type in widget.document.types)
                      DataRow(
                        selected: type.id == widget.currentTypeId,
                        cells: <DataCell>[
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (type.id == widget.currentTypeId) ...<Widget>[
                                  const Icon(Icons.visibility_outlined, size: 16),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  type.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          for (final parameter in parameters)
                            DataCell(
                              Text(
                                _displayValue(
                                  type.values.containsKey(parameter.id)
                                      ? type.values[parameter.id]
                                      : parameter.defaultValue,
                                  parameter.kind,
                                ),
                              ),
                              onTap: () => _editValue(type, parameter),
                            ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Duplicate ${type.name}',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _duplicateType(type),
                                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Rename ${type.name}',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _renameType(type),
                                  icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Delete ${type.name}',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: widget.document.types.length <= 1
                                      ? null
                                      : () => _deleteType(type),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editValue(
    FamilyTypeDefinition type,
    FamilyParameterDefinition parameter,
  ) async {
    final current = type.values.containsKey(parameter.id)
        ? type.values[parameter.id]
        : parameter.defaultValue;
    final controller = TextEditingController(text: _rawValue(current));
    try {
      final raw = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${type.name} · ${parameter.label}'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: _numericKind(parameter.kind)
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              decoration: InputDecoration(
                helperText: _helper(parameter.kind),
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
      if (!mounted || raw == null) return;
      final value = _parse(parameter.kind, raw);
      _run(
        () => FamilyParameterAuthoring.setTypeValue(
          widget.document,
          typeId: type.id,
          parameterId: parameter.id,
          value: value,
        ),
        '${type.name} · ${parameter.label} updated.',
      );
    } catch (error) {
      widget.onStatus(_errorText(error));
    } finally {
      controller.dispose();
    }
  }

  Future<void> _duplicateType(FamilyTypeDefinition type) async {
    final name = await _textDialog(
      title: 'Duplicate Family Type',
      initialValue: '${type.name} Copy',
      helper: 'The new type copies every explicit value from ${type.name}.',
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    _run(
      () => FamilyParameterAuthoring.duplicateType(
        widget.document,
        sourceTypeId: type.id,
        name: name,
      ),
      'Family Type ${name.trim()} created.',
    );
  }

  Future<void> _renameType(FamilyTypeDefinition type) async {
    final name = await _textDialog(
      title: 'Rename Family Type',
      initialValue: type.name,
      helper: 'The stable type id does not change.',
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    _run(
      () => FamilyParameterAuthoring.renameType(
        widget.document,
        typeId: type.id,
        name: name,
      ),
      'Family Type renamed to ${name.trim()}.',
    );
  }

  Future<void> _deleteType(FamilyTypeDefinition type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Family Type ${type.name}?'),
        content: const Text(
          'The type is removed from this family. External nested-family references must be updated separately.',
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
    if (!mounted || confirmed != true) return;
    _run(
      () => FamilyParameterAuthoring.removeType(widget.document, type.id),
      'Family Type ${type.name} deleted.',
    );
  }

  Future<String?> _textDialog({
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

  void _run(FamilyDocument Function() command, String success) {
    try {
      widget.onChanged(command());
      widget.onStatus(success);
    } catch (error) {
      widget.onStatus(_errorText(error));
    }
  }

  static Object _parse(FamilyParameterKind kind, String raw) {
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

  static bool _numericKind(FamilyParameterKind kind) =>
      kind == FamilyParameterKind.length ||
      kind == FamilyParameterKind.number ||
      kind == FamilyParameterKind.angle;

  static String _rawValue(Object? value) {
    if (value is double) {
      return value.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return '$value';
  }

  static String _displayValue(Object? value, FamilyParameterKind kind) {
    final raw = _rawValue(value);
    return switch (kind) {
      FamilyParameterKind.length => '$raw m',
      FamilyParameterKind.angle => '$raw°',
      _ => raw,
    };
  }

  static String _helper(FamilyParameterKind kind) => switch (kind) {
        FamilyParameterKind.length => 'Length in meters.',
        FamilyParameterKind.number => 'Finite numeric value.',
        FamilyParameterKind.angle => 'Angle in degrees.',
        FamilyParameterKind.material => 'Material token/name.',
        FamilyParameterKind.text => 'Non-empty text.',
        FamilyParameterKind.boolean => 'Enter true or false.',
      };

  static String _errorText(Object error) =>
      error is FormatException ? error.message : '$error';
}
