import 'package:flutter/material.dart';

/// Explicit source-unit selection for glTF/GLB import.
///
/// glTF itself does not guarantee the source DCC unit convention. Returning
/// metres-per-source-unit keeps the importer deterministic and makes millimetre
/// and centimetre Blender exports safe to reuse as BIM content.
abstract final class FamilyImportUnitsDialog {
  static Future<double?> show(BuildContext context) {
    return showDialog<double>(
      context: context,
      builder: (_) => const _ImportUnitsDialog(),
    );
  }
}

enum _ImportUnitPreset { metres, centimetres, millimetres, custom }

class _ImportUnitsDialog extends StatefulWidget {
  const _ImportUnitsDialog();

  @override
  State<_ImportUnitsDialog> createState() => _ImportUnitsDialogState();
}

class _ImportUnitsDialogState extends State<_ImportUnitsDialog> {
  _ImportUnitPreset _preset = _ImportUnitPreset.metres;
  final TextEditingController _custom = TextEditingController(text: '1.0');

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  double? get _scale {
    switch (_preset) {
      case _ImportUnitPreset.metres:
        return 1.0;
      case _ImportUnitPreset.centimetres:
        return 0.01;
      case _ImportUnitPreset.millimetres:
        return 0.001;
      case _ImportUnitPreset.custom:
        final value = double.tryParse(_custom.text.trim().replaceAll(',', '.'));
        return value != null && value.isFinite && value > 0 ? value : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Source model units'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<_ImportUnitPreset>(
              initialValue: _preset,
              decoration: const InputDecoration(
                labelText: 'GLB/glTF source units',
                prefixIcon: Icon(Icons.straighten),
                border: OutlineInputBorder(),
              ),
              items: const <DropdownMenuItem<_ImportUnitPreset>>[
                DropdownMenuItem(
                  value: _ImportUnitPreset.metres,
                  child: Text('Metres (1 source unit = 1 m)'),
                ),
                DropdownMenuItem(
                  value: _ImportUnitPreset.centimetres,
                  child: Text('Centimetres (1 source unit = 0.01 m)'),
                ),
                DropdownMenuItem(
                  value: _ImportUnitPreset.millimetres,
                  child: Text('Millimetres (1 source unit = 0.001 m)'),
                ),
                DropdownMenuItem(
                  value: _ImportUnitPreset.custom,
                  child: Text('Custom scale'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _preset = value);
              },
            ),
            if (_preset == _ImportUnitPreset.custom) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _custom,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Metres per source unit',
                  hintText: '0.001',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Choose the unit convention used when the model was authored/exported. The family will be stored in real metres.',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _scale == null
              ? null
              : () => Navigator.of(context).pop(_scale),
          child: const Text('Continue import'),
        ),
      ],
    );
  }
}
