import 'package:flutter/material.dart';

import 'family_document.dart';

/// Selects and edits real nodes in the Family feature graph.
///
/// The workbench never owns geometry state: it returns a complete candidate
/// [FamilyDocument] to the parent editor, so the existing validator and CSG
/// evaluator remain the single authority.
class FamilyFeatureWorkbench extends StatelessWidget {
  const FamilyFeatureWorkbench({
    super.key,
    required this.document,
    required this.selectedFeatureId,
    required this.onSelected,
    required this.onChanged,
    required this.onStatus,
    this.onEditNestedFamily,
  });

  final FamilyDocument document;
  final String? selectedFeatureId;
  final ValueChanged<String> onSelected;
  final void Function(FamilyDocument document, String status) onChanged;
  final ValueChanged<String> onStatus;
  final Future<void> Function(FamilyFeature feature)? onEditNestedFamily;

  FamilyFeature? get _selected {
    for (final feature in document.features) {
      if (feature.id == selectedFeatureId) return feature;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 160,
          child: ListView.separated(
            itemCount: document.features.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final feature = document.features[index];
              final active = feature.id == selectedFeatureId;
              return Material(
                color: active
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  selected: active,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(_icon(feature.kind), size: 20),
                  title: Text(_label(feature)),
                  subtitle: Text(
                    _summary(feature),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('${index + 1}'),
                  onTap: () => onSelected(feature.id),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (selected == null)
          const Text('Select a feature to edit its geometry inputs.')
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(_icon(selected.kind)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _label(selected),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (selected.kind == FamilyFeatureKind.nestedFamily &&
                        onEditNestedFamily != null)
                      TextButton.icon(
                        onPressed: () => onEditNestedFamily!(selected),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Child'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: () => _edit(context, selected),
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text('Edit'),
                    ),
                    IconButton(
                      tooltip: 'Delete feature',
                      onPressed: () => _delete(context, selected),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_details(selected)),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, FamilyFeature feature) async {
    final replacement = await showDialog<FamilyFeature>(
      context: context,
      builder: (_) => _FeatureEditDialog(document: document, feature: feature),
    );
    if (!context.mounted || replacement == null) return;
    onChanged(
      document.copyWith(
        features: <FamilyFeature>[
          for (final current in document.features)
            current.id == feature.id ? replacement : current,
        ],
      ),
      '${_label(replacement)} updated',
    );
  }

  Future<void> _delete(BuildContext context, FamilyFeature feature) async {
    if (document.features.length <= 1) {
      onStatus('A family must keep at least one feature.');
      return;
    }
    final users = document.features.where(
      (candidate) =>
          candidate.id != feature.id && candidate.inputs.contains(feature.id),
    );
    if (users.isNotEmpty) {
      onStatus(
        '${_label(feature)} is used by ${users.map(_label).join(', ')}. Change those inputs first.',
      );
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_label(feature)}?'),
        content: const Text(
          'The feature is removed from this family graph. Parameters and sketches are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete feature'),
          ),
        ],
      ),
    );
    if (!context.mounted || remove != true) return;
    onChanged(
      document.copyWith(
        features: <FamilyFeature>[
          for (final current in document.features)
            if (current.id != feature.id) current,
        ],
      ),
      '${_label(feature)} deleted',
    );
  }
}

class _FeatureEditDialog extends StatefulWidget {
  const _FeatureEditDialog({required this.document, required this.feature});

  final FamilyDocument document;
  final FamilyFeature feature;

  @override
  State<_FeatureEditDialog> createState() => _FeatureEditDialogState();
}

class _FeatureEditDialogState extends State<_FeatureEditDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _depth;
  late final TextEditingController _angle;
  late final TextEditingController _tx;
  late final TextEditingController _ty;
  late final TextEditingController _tz;
  late final TextEditingController _rotation;
  late final TextEditingController _scale;
  String? _profileId;
  String? _sourceId;
  String? _leftId;
  String? _rightId;

  FamilyFeature get feature => widget.feature;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: feature.label);
    _depth = TextEditingController(
      text: '${feature.parameters['depth'] ?? 'extrusionDepth'}',
    );
    _angle = TextEditingController(
      text: '${feature.parameters['angle'] ?? 'revolveAngle'}',
    );
    _tx = TextEditingController(
      text: '${feature.parameters['translationX'] ?? 0}',
    );
    _ty = TextEditingController(
      text: '${feature.parameters['translationY'] ?? 0}',
    );
    _tz = TextEditingController(
      text: '${feature.parameters['translationZ'] ?? 0}',
    );
    _rotation = TextEditingController(
      text: '${feature.parameters['rotationZ'] ?? 0}',
    );
    _scale = TextEditingController(
      text: '${feature.parameters['scale'] ?? 1}',
    );
    _profileId = feature.parameters['profileId']?.toString();
    if (!_validSketch(_profileId)) {
      _profileId = widget.document.sketches.isEmpty
          ? null
          : widget.document.sketches.first.id;
    }
    final inputs = feature.inputs;
    _sourceId = inputs.isEmpty ? null : inputs.first;
    _leftId = inputs.isEmpty ? null : inputs.first;
    _rightId = inputs.length < 2 ? null : inputs[1];
    final solids = _earlierSolids;
    if (!_validSolid(_sourceId)) {
      _sourceId = solids.isEmpty ? null : solids.last.id;
    }
    if (!_validSolid(_leftId)) {
      _leftId = solids.isEmpty
          ? null
          : solids.length >= 2
              ? solids[solids.length - 2].id
              : solids.first.id;
    }
    if (!_validSolid(_rightId) || _rightId == _leftId) {
      final alternatives = solids.where((item) => item.id != _leftId).toList();
      _rightId = alternatives.isEmpty ? null : alternatives.last.id;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _depth.dispose();
    _angle.dispose();
    _tx.dispose();
    _ty.dispose();
    _tz.dispose();
    _rotation.dispose();
    _scale.dispose();
    super.dispose();
  }

  List<FamilyFeature> get _earlierSolids {
    final index = widget.document.features.indexWhere((item) => item.id == feature.id);
    if (index <= 0) return const <FamilyFeature>[];
    return widget.document.features
        .take(index)
        .where(_solid)
        .toList(growable: false);
  }

  bool _validSketch(String? id) => id != null &&
      widget.document.sketches.any((candidate) => candidate.id == id);

  bool _validSolid(String? id) =>
      id != null && _earlierSolids.any((candidate) => candidate.id == id);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${_label(feature)}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Feature label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ..._fields(),
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
          onPressed: _apply,
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }

  List<Widget> _fields() {
    switch (feature.kind) {
      case FamilyFeatureKind.box:
        return const <Widget>[
          Text('Box dimensions are driven by the active Family Type.'),
        ];
      case FamilyFeatureKind.profile:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          const Text('Move profile points in the sketch canvas.'),
        ];
      case FamilyFeatureKind.extrude:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          _text(_depth, 'Extrusion depth', '1.0 or extrusionDepth'),
        ];
      case FamilyFeatureKind.revolve:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          _text(_angle, 'Revolve angle (°)', '360 or revolveAngle'),
        ];
      case FamilyFeatureKind.transform:
        return <Widget>[
          _solidPicker(
            value: _sourceId,
            label: 'Source solid',
            onChanged: (value) => setState(() => _sourceId = value),
          ),
          const SizedBox(height: 10),
          _transformFields(),
        ];
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _solidPicker(
                  value: _leftId,
                  label: 'Base / left',
                  onChanged: (value) => setState(() => _leftId = value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Swap operands',
                onPressed: _leftId == null || _rightId == null
                    ? null
                    : () => setState(() {
                          final current = _leftId;
                          _leftId = _rightId;
                          _rightId = current;
                        }),
                icon: const Icon(Icons.swap_horiz),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _solidPicker(
                  value: _rightId,
                  label: 'Tool / right',
                  onChanged: (value) => setState(() => _rightId = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feature.kind == FamilyFeatureKind.booleanSubtract
                ? 'Subtract is order-sensitive: base − tool.'
                : 'Union combines both closed solids.',
          ),
        ];
      case FamilyFeatureKind.freeformMesh:
        final vertices = feature.parameters['vertices'];
        final faces = feature.parameters['faces'];
        return <Widget>[
          Text(
            'Imported topology · ${vertices is List ? vertices.length : 0} vertices · ${faces is List ? faces.length : 0} faces. Add a Transform node to move/rotate/scale it.',
          ),
        ];
      case FamilyFeatureKind.nestedFamily:
        return <Widget>[
          Text(
            'Child ${feature.parameters['familyId'] ?? '—'} · type ${feature.parameters['typeId'] ?? '—'}',
          ),
          const SizedBox(height: 10),
          _transformFields(),
          const SizedBox(height: 8),
          const Text('Use Child in the workbench to replace the Library family/type.'),
        ];
    }
  }

  Widget _profilePicker() => DropdownButtonFormField<String>(
        initialValue: _profileId,
        decoration: const InputDecoration(
          labelText: 'Profile',
          prefixIcon: Icon(Icons.polyline_outlined),
          border: OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<String>>[
          for (final sketch in widget.document.sketches)
            DropdownMenuItem<String>(
              value: sketch.id,
              child: Text('${sketch.name}${sketch.closed ? '' : ' · open'}'),
            ),
        ],
        onChanged: (value) => setState(() => _profileId = value),
      );

  Widget _solidPicker({
    required String? value,
    required String label,
    required ValueChanged<String?> onChanged,
  }) =>
      DropdownButtonFormField<String>(
        initialValue: _validSolid(value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<String>>[
          for (final candidate in _earlierSolids)
            DropdownMenuItem<String>(
              value: candidate.id,
              child: Text(_label(candidate)),
            ),
        ],
        onChanged: onChanged,
      );

  Widget _transformFields() => Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _text(_tx, 'X', '0')),
              const SizedBox(width: 8),
              Expanded(child: _text(_ty, 'Y', '0')),
              const SizedBox(width: 8),
              Expanded(child: _text(_tz, 'Z', '0')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _text(_rotation, 'Rotation Z (°)', '0')),
              const SizedBox(width: 8),
              Expanded(child: _text(_scale, 'Uniform scale', '1')),
            ],
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Numbers or Family Type expressions are accepted.'),
          ),
        ],
      );

  Widget _text(TextEditingController controller, String label, String hint) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  void _apply() {
    final parameters = <String, Object?>{...feature.parameters};
    var inputs = List<String>.of(feature.inputs);

    switch (feature.kind) {
      case FamilyFeatureKind.box:
        break;
      case FamilyFeatureKind.profile:
        final profileId = _profileId;
        if (profileId == null) return;
        parameters['profileId'] = profileId;
        inputs = <String>[profileId];
        break;
      case FamilyFeatureKind.extrude:
        final profileId = _profileId;
        final depth = _depth.text.trim();
        if (profileId == null || depth.isEmpty) return;
        parameters['profileId'] = profileId;
        parameters['depth'] = depth;
        inputs = <String>[profileId];
        break;
      case FamilyFeatureKind.revolve:
        final profileId = _profileId;
        final angle = _angle.text.trim();
        if (profileId == null || angle.isEmpty) return;
        parameters['profileId'] = profileId;
        parameters['angle'] = angle;
        inputs = <String>[profileId];
        break;
      case FamilyFeatureKind.transform:
        final source = _sourceId;
        if (source == null || !_writeTransform(parameters)) return;
        inputs = <String>[source];
        break;
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
        final left = _leftId;
        final right = _rightId;
        if (left == null || right == null || left == right) return;
        inputs = <String>[left, right];
        parameters['operation'] = feature.kind.name;
        break;
      case FamilyFeatureKind.freeformMesh:
        break;
      case FamilyFeatureKind.nestedFamily:
        if (!_writeTransform(parameters)) return;
        break;
    }

    Navigator.of(context).pop(
      FamilyFeature(
        id: feature.id,
        kind: feature.kind,
        label: _labelController.text.trim(),
        inputs: List<String>.unmodifiable(inputs),
        parameters: Map<String, Object?>.unmodifiable(parameters),
      ),
    );
  }

  bool _writeTransform(Map<String, Object?> parameters) {
    final values = <String, String>{
      'translationX': _tx.text.trim(),
      'translationY': _ty.text.trim(),
      'translationZ': _tz.text.trim(),
      'rotationZ': _rotation.text.trim(),
      'scale': _scale.text.trim(),
    };
    if (values.values.any((value) => value.isEmpty)) return false;
    parameters.addAll(values);
    return true;
  }
}

bool _solid(FamilyFeature feature) =>
    feature.kind == FamilyFeatureKind.box ||
    feature.kind == FamilyFeatureKind.extrude ||
    feature.kind == FamilyFeatureKind.revolve ||
    feature.kind == FamilyFeatureKind.booleanUnion ||
    feature.kind == FamilyFeatureKind.booleanSubtract ||
    feature.kind == FamilyFeatureKind.transform ||
    feature.kind == FamilyFeatureKind.freeformMesh ||
    feature.kind == FamilyFeatureKind.nestedFamily;

String _input(FamilyFeature feature, int index, String fallback) =>
    feature.inputs.length > index ? feature.inputs[index] : fallback;

String _label(FamilyFeature feature) {
  if (feature.label.trim().isNotEmpty) return feature.label.trim();
  return switch (feature.kind) {
    FamilyFeatureKind.box => 'Box solid',
    FamilyFeatureKind.profile => 'Profile',
    FamilyFeatureKind.extrude => 'Extrude',
    FamilyFeatureKind.revolve => 'Revolve',
    FamilyFeatureKind.booleanUnion => 'Boolean union',
    FamilyFeatureKind.booleanSubtract => 'Boolean subtract',
    FamilyFeatureKind.transform => 'Transform',
    FamilyFeatureKind.freeformMesh => 'Freeform mesh',
    FamilyFeatureKind.nestedFamily => 'Nested family',
  };
}

String _summary(FamilyFeature feature) => switch (feature.kind) {
      FamilyFeatureKind.box => 'Family Type dimensions',
      FamilyFeatureKind.profile =>
        'Sketch ${feature.parameters['profileId'] ?? _input(feature, 0, 'none')}',
      FamilyFeatureKind.extrude =>
        'Depth ${feature.parameters['depth'] ?? '1'} · ${feature.parameters['profileId'] ?? 'profile'}',
      FamilyFeatureKind.revolve =>
        'Angle ${feature.parameters['angle'] ?? 360}° · ${feature.parameters['profileId'] ?? 'profile'}',
      FamilyFeatureKind.booleanUnion => 'Union ${feature.inputs.join(' + ')}',
      FamilyFeatureKind.booleanSubtract => 'Subtract ${feature.inputs.join(' − ')}',
      FamilyFeatureKind.transform =>
        'Move (${feature.parameters['translationX'] ?? 0}, ${feature.parameters['translationY'] ?? 0}, ${feature.parameters['translationZ'] ?? 0}) · scale ${feature.parameters['scale'] ?? 1}',
      FamilyFeatureKind.freeformMesh => 'Imported/freeform topology',
      FamilyFeatureKind.nestedFamily =>
        '${feature.parameters['familyId'] ?? 'child'} · ${feature.parameters['typeId'] ?? 'type'}',
    };

String _details(FamilyFeature feature) => switch (feature.kind) {
      FamilyFeatureKind.box =>
        'Parametric base solid. Width, depth and height follow the active Family Type.',
      FamilyFeatureKind.profile =>
        'Profile sketch ${feature.parameters['profileId'] ?? _input(feature, 0, '—')}.',
      FamilyFeatureKind.extrude =>
        'Profile ${feature.parameters['profileId'] ?? '—'} · depth ${feature.parameters['depth'] ?? '—'}.',
      FamilyFeatureKind.revolve =>
        'Profile ${feature.parameters['profileId'] ?? '—'} · angle ${feature.parameters['angle'] ?? '—'}°.',
      FamilyFeatureKind.booleanUnion =>
        'Exact CSG union for closed manifold solids · ${feature.inputs.join(' + ')}.',
      FamilyFeatureKind.booleanSubtract =>
        'Exact CSG subtract for closed manifold solids · ${feature.inputs.join(' − ')}.',
      FamilyFeatureKind.transform =>
        'Source ${_input(feature, 0, 'previous solid')} · X ${feature.parameters['translationX'] ?? 0} · Y ${feature.parameters['translationY'] ?? 0} · Z ${feature.parameters['translationZ'] ?? 0} · R ${feature.parameters['rotationZ'] ?? 0}° · S ${feature.parameters['scale'] ?? 1}.',
      FamilyFeatureKind.freeformMesh =>
        'Imported/freeform topology. Add Transform to manipulate it non-destructively.',
      FamilyFeatureKind.nestedFamily =>
        'Child ${feature.parameters['familyId'] ?? '—'} · type ${feature.parameters['typeId'] ?? '—'} · X ${feature.parameters['translationX'] ?? 0} · Y ${feature.parameters['translationY'] ?? 0} · Z ${feature.parameters['translationZ'] ?? 0} · R ${feature.parameters['rotationZ'] ?? 0}° · S ${feature.parameters['scale'] ?? 1}.',
    };

IconData _icon(FamilyFeatureKind kind) => switch (kind) {
      FamilyFeatureKind.box => Icons.crop_square_outlined,
      FamilyFeatureKind.profile => Icons.polyline_outlined,
      FamilyFeatureKind.extrude => Icons.height,
      FamilyFeatureKind.revolve => Icons.rotate_right_outlined,
      FamilyFeatureKind.booleanUnion => Icons.merge_type_outlined,
      FamilyFeatureKind.booleanSubtract => Icons.call_split_outlined,
      FamilyFeatureKind.transform => Icons.open_with_outlined,
      FamilyFeatureKind.freeformMesh => Icons.grid_4x4_outlined,
      FamilyFeatureKind.nestedFamily => Icons.account_tree_outlined,
    };
