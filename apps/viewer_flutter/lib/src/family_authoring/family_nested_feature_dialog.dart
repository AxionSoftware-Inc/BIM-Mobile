import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_file_store.dart';

/// Tablet authoring dialog for adding a real nested-family dependency.
///
/// The parent stores stable family/type ids only. Child documents stay in the
/// reusable library and are resolved by FamilyDependencyResolver at preview,
/// save preflight, placement and Inspector regeneration boundaries.
abstract final class FamilyNestedFeatureDialog {
  static Future<FamilyFeature?> show(
    BuildContext context, {
    required FamilyDocument parent,
  }) async {
    final assets = await FamilyFileStore.listStored();
    if (!context.mounted) return null;
    final candidates = <FamilyAssetFile>[
      for (final asset in assets)
        if (asset.document.id != parent.id && asset.document.types.isNotEmpty)
          asset,
    ];
    if (candidates.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No child families available'),
          content: const Text(
            'Save or import another family into the Family Library first. A family cannot nest itself.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }
    return showDialog<FamilyFeature>(
      context: context,
      builder: (_) => _NestedFamilyDialog(
        parent: parent,
        assets: candidates,
      ),
    );
  }
}

class _NestedFamilyDialog extends StatefulWidget {
  const _NestedFamilyDialog({
    required this.parent,
    required this.assets,
  });

  final FamilyDocument parent;
  final List<FamilyAssetFile> assets;

  @override
  State<_NestedFamilyDialog> createState() => _NestedFamilyDialogState();
}

class _NestedFamilyDialogState extends State<_NestedFamilyDialog> {
  late FamilyAssetFile _asset;
  late String _typeId;
  final TextEditingController _tx = TextEditingController(text: '0');
  final TextEditingController _ty = TextEditingController(text: '0');
  final TextEditingController _tz = TextEditingController(text: '0');
  final TextEditingController _rotation = TextEditingController(text: '0');
  final TextEditingController _scale = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _asset = widget.assets.first;
    _typeId = _asset.document.types.first.id;
  }

  @override
  void dispose() {
    _tx.dispose();
    _ty.dispose();
    _tz.dispose();
    _rotation.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = _asset.document.types.firstWhere(
      (candidate) => candidate.id == _typeId,
      orElse: () => _asset.document.types.first,
    );
    return AlertDialog(
      title: const Text('Add nested family'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _asset.document.id,
                decoration: const InputDecoration(
                  labelText: 'Child family',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final asset in widget.assets)
                    DropdownMenuItem<String>(
                      value: asset.document.id,
                      child: Text(asset.document.name),
                    ),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  final next = widget.assets.firstWhere(
                    (asset) => asset.document.id == id,
                  );
                  setState(() {
                    _asset = next;
                    _typeId = next.document.types.first.id;
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_asset.document.id),
                initialValue: type.id,
                decoration: const InputDecoration(
                  labelText: 'Child family type',
                  prefixIcon: Icon(Icons.tune_outlined),
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final candidate in _asset.document.types)
                    DropdownMenuItem<String>(
                      value: candidate.id,
                      child: Text(candidate.name),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) setState(() => _typeId = id);
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Transform',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Values may be numbers or parent Family Type expressions such as width / 2.',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(child: _field(_tx, 'X', '0')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_ty, 'Y · vertical', '0')),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_tz, 'Z', '0')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _field(
                      _rotation,
                      'Rotation · vertical axis (°)',
                      '0',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_scale, 'Uniform scale', '1')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Add child'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint,
  ) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  void _create() {
    final scale = _scale.text.trim();
    if (scale.isEmpty) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    Navigator.of(context).pop(
      FamilyFeature(
        id: 'nested-$stamp',
        kind: FamilyFeatureKind.nestedFamily,
        label: '${_asset.document.name} · ${_selectedType.name}',
        parameters: <String, Object?>{
          'familyId': _asset.document.id,
          'typeId': _selectedType.id,
          'translationX': _token(_tx, '0'),
          'translationY': _token(_ty, '0'),
          'translationZ': _token(_tz, '0'),
          // Persist the established field name for backward compatibility.
          // The resolver interprets it as yaw around Family Y (vertical).
          'rotationZ': _token(_rotation, '0'),
          'scale': scale,
        },
      ),
    );
  }

  FamilyTypeDefinition get _selectedType => _asset.document.types.firstWhere(
        (candidate) => candidate.id == _typeId,
        orElse: () => _asset.document.types.first,
      );

  static String _token(TextEditingController controller, String fallback) {
    final value = controller.text.trim();
    return value.isEmpty ? fallback : value;
  }
}
