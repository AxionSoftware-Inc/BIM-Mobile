import 'package:flutter/material.dart';

import 'family_document.dart';

/// Interactive feature-graph workbench for Family Editor V2.
///
/// Feature topology stays in [FamilyDocument]. This widget only edits one node
/// at a time and returns a complete candidate document to the editor, where the
/// existing validator/evaluator remains the final authority.
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
    final id = selectedFeatureId;
    if (id == null) return null;
    for (final feature in document.features) {
      if (feature.id == id) return feature;
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
          height: 150,
          child: ListView.separated(
            itemCount: document.features.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final feature = document.features[index];
              final isSelected = feature.id == selectedFeatureId;
              return Material(
                color: isSelected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  selected: isSelected,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(_featureIcon(feature.kind), size: 20),
                  title: Text(_featureLabel(feature)),
                  subtitle: Text(
                    _featureSummary(feature),
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
          _SelectedFeatureCard(
            document: document,
            feature: selected,
            onEdit: () => _edit(context, selected),
            onDelete: () => _delete(context, selected),
            onEditNestedFamily: selected.kind == FamilyFeatureKind.nestedFamily
                ? onEditNestedFamily == null
                    ? null
                    : () => onEditNestedFamily!(selected)
                : null,
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, FamilyFeature feature) async {
    final replacement = await showDialog<FamilyFeature>(
      context: context,
      builder: (_) => _FeatureEditDialog(
        document: document,
        feature: feature,
      ),
    );
    if (!context.mounted || replacement == null) return;
    final candidate = document.copyWith(
      features: <FamilyFeature>[
        for (final current in document.features)
          current.id == feature.id ? replacement : current,
      ],
    );
    onChanged(candidate, '${_featureLabel(replacement)} updated');
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
        '${_featureLabel(feature)} is used by ${users.map(_featureLabel).join(', ')}. Change those inputs first.',
      );
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_featureLabel(feature)}?'),
        content: const Text(
          'The feature is removed from this family graph. Family Type parameters and reusable sketches are kept.',
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
    final candidate = document.copyWith(
      features: <FamilyFeature>[
        for (final current in document.features)
          if (current.id != feature.id) current,
      ],
    );
    onChanged(candidate, '${_featureLabel(feature)} deleted');
  }
}

class _SelectedFeatureCard extends StatelessWidget {
  const _SelectedFeatureCard({
    required this.document,
    required this.feature,
    required this.onEdit,
    required this.onDelete,
    this.onEditNestedFamily,
  });

  final FamilyDocument document;
  final FamilyFeature feature;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onEditNestedFamily;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_featureIcon(feature.kind), color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _featureLabel(feature),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(feature.kind.name),
                  ],
                ),
              ),
              if (onEditNestedFamily != null)
                TextButton.icon(
                  onPressed: onEditNestedFamily,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Child'),
                ),
              FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_outlined),
                label: const Text('Edit'),
              ),
              IconButton(
                tooltip: 'Delete feature',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_featureDetails(document, feature)),
        ],
      ),
    );
  }
}

class _FeatureEditDialog extends StatefulWidget {
  const _FeatureEditDialog({
    required this.document,
    required this.feature,
  });

  final FamilyDocument document;
  final FamilyFeature feature;

  @override
  State<_FeatureEditDialog> createState() => _FeatureEditDialogState();
}

class _FeatureEditDialogState extends State<_FeatureEditDialog> {
  late final TextEditingController _label;
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
    _label = TextEditingController(text: feature.label);
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
    final solids = _earlierSolidFeatures;
    if (!_validSolid(_sourceId)) _sourceId = solids.isEmpty ? null : solids.last.id;
    if (!_validSolid(_leftId)) {
      _leftId = solids.length >= 2 ? solids[solids.length - 2].id : solids.firstOrNull?.id;
    }
    if (!_validSolid(_rightId) || _rightId == _leftId) {
      _rightId = solids.where((item) => item.id != _leftId).lastOrNull?.id;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _depth.dispose();
    _angle.dispose();
    _tx.dispose();
    _ty.dispose();
    _tz.dispose();
    _rotation.dispose();
    _scale.dispose();
    super.dispose();
  }

  List<FamilyFeature> get _earlierSolidFeatures {
    final index = widget.document.features.indexWhere((item) => item.id == feature.id);
    if (index <= 0) return const <FamilyFeature>[];
    return widget.document.features
        .take(index)
        .where(_isSolidFeature)
        .toList(growable: false);
  }

  bool _validSketch(String? id) =>
      id != null && widget.document.sketches.any((sketch) => sketch.id == id);

  bool _validSolid(String? id) =>
      id != null && _earlierSolidFeatures.any((candidate) => candidate.id == id);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${_featureLabel(feature)}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Feature label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ..._specificFields(context),
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

  List<Widget> _specificFields(BuildContext context) {
    switch (feature.kind) {
      case FamilyFeatureKind.box:
        return const <Widget>[
          Text(
            'Box width, depth and height are driven by the selected Family Type. Edit those values in the Family Types section.',
          ),
        ];
      case FamilyFeatureKind.profile:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          const Text('Edit profile points directly in the sketch canvas.'),
        ];
      case FamilyFeatureKind.extrude:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          _expressionField(
            _depth,
            label: 'Extrusion depth',
            hint: '1.0 or extrusionDepth',
          ),
        ];
      case FamilyFeatureKind.revolve:
        return <Widget>[
          _profilePicker(),
          const SizedBox(height: 8),
          _expressionField(
            _angle,
            label: 'Revolve angle (°)',
            hint: '360 or revolveAngle',
          ),
        ];
      case FamilyFeatureKind.transform:
        return <Widget>[
          _sourcePicker('Source solid'),
          const SizedBox(height: 10),
          _transformFields(),
        ];
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _booleanPicker(left: true)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Swap boolean operands',
                onPressed: _leftId == null || _rightId == null
                    ? null
                    : () => setState(() {
                          final value = _leftId;
                          _leftId = _rightId;
                          _rightId = value;
                        }),
                icon: const Icon(Icons.swap_horiz),
              ),
              const SizedBox(width: 8),
              Expanded(child: _booleanPicker(left: false)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feature.kind == FamilyFeatureKind.booleanUnion
                ? 'Union combines both closed solids.'
                : 'Subtract removes the right solid from the left solid. Operand order matters.',
          ),
        ];
      case FamilyFeatureKind.freeformMesh:
        final vertices = feature.parameters['vertices'];
        final faces = feature.parameters['faces'];
        return <Widget>[
          Text(
            'Imported/freeform mesh · ${vertices is List ? vertices.length : 0} vertices · ${faces is List ? faces.length : 0} faces. Use Transform to reposition it without rewriting source topology.',
          ),
        ];
      case FamilyFeatureKind.nestedFamily:
        return <Widget>[
          Text(
            'Child: ${feature.parameters['familyId'] ?? 'unknown'} · Type: ${feature.parameters['typeId'] ?? 'unknown'}',
          ),
          const SizedBox(height: 10),
          _transformFields(),
          const SizedBox(height: 8),
          const Text(
            'Use the Child button outside this dialog to replace the nested family/type from the Library.',
          ),
        ];
    }
  }

  Widget _profilePicker() {
    return DropdownButtonFormField<String>(
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
  }

  Widget _sourcePicker(String label) {
    return DropdownButtonFormField<String>(
      initialValue: _sourceId,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.input_outlined),
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        for (final candidate in _earlierSolidFeatures)
          DropdownMenuItem<String>(
            value: candidate.id,
            child: Text(_featureLabel(candidate)),
          ),
      ],
      onChanged: (value) => setState(() => _sourceId = value),
    );
  }

  Widget _booleanPicker({required bool left}) {
    final current = left ? _leftId : _rightId;
    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: InputDecoration(
        labelText: left ? 'Left / base solid' : 'Right / tool solid',
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<String>>[
        for (final candidate in _earlierSolidFeatures)
          DropdownMenuItem<String>(
            value: candidate.id,
            child: Text(_featureLabel(candidate)),
          ),
      ],
      onChanged: (value) => setState(() {
        if (left) {
          _leftId = value;
        } else {
          _rightId = value;
        }
      }),
    );
  }

  Widget _transformFields() {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _expressionField(_tx, label: 'X', hint: '0')),
            const SizedBox(width: 8),
            Expanded(child: _expressionField(_ty, label: 'Y', hint: '0')),
            const SizedBox(width: 8),
            Expanded(child: _expressionField(_tz, label: 'Z', hint: '0')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _expressionField(
                _rotation,
                label: 'Rotation Z (°)',
                hint: '0',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _expressionField(
                _scale,
                label: 'Uniform scale',
                hint: '1',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Numbers and Family Type expressions are accepted, e.g. width / 2.',
          ),
        ),
      ],
    );
  }

  Widget _expressionField(
    TextEditingController controller, {
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  void _apply() {
    final label = _label.text.trim();
    var inputs = feature.inputs;
    final parameters = <String, Object?>{...feature.parameters};
    switch (feature.kind) {
      case FamilyFeatureKind.box:
        break;
      case FamilyFeatureKind.profile:
        final profileId = _profileId;
        if (profileId == null) return;
        parameters['profileId'] = profileId;
        inputs = <String>[profileId];
      case FamilyFeatureKind.extrude:
        final profileId = _profileId;
        final depth = _depth.text.trim();
        if (profileId == null || depth.isEmpty) return;
        parameters['profileId'] = profileId;
        parameters['depth'] = depth;
        inputs = <String>[profileId];
      case FamilyFeatureKind.revolve:
        final profileId = _profileId;
        final angle = _angle.text.trim();
        if (profileId == null || angle.isEmpty) return;
        parameters['profileId'] = profileId;
        parameters['angle'] = angle;
        inputs = <String>[profileId];
      case FamilyFeatureKind.transform:
        final source = _sourceId;
        if (source == null || !_writeTransform(parameters)) return;
        inputs = <String>[source];
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
        final left = _leftId;
        final right = _rightId;
        if (left == null || right == null || left == right) return;
        inputs = <String>[left, right];
        parameters['operation'] = feature.kind.name;
      case FamilyFeatureKind.freeformMesh:
        break;
      case FamilyFeatureKind.nestedFamily:
        if (!_writeTransform(parameters)) return;
    }
    Navigator.of(context).pop(
      FamilyFeature(
        id: feature.id,
        kind: feature.kind,
        label: label,
        inputs: List<String>.unmodifiable(inputs),
        parameters: Map<String, Object?>.unmodifiable(parameters),
      ),
    );
  }

  bool _writeTransform(Map<String, Object?> parameters) {
    final tx = _tx.text.trim();
    final ty = _ty.text.trim();
    final tz = _tz.text.trim();
    final rotation = _rotation.text.trim();
    final scale = _scale.text.trim();
    if (tx.isEmpty || ty.isEmpty || tz.isEmpty || rotation.isEmpty || scale.isEmpty) {
      return false;
    }
    parameters['translationX'] = tx;
    parameters['translationY'] = ty;
    parameters['translationZ'] = tz;
    parameters['rotationZ'] = rotation;
    parameters['scale'] = scale;
    return true;
  }
}

bool _isSolidFeature(FamilyFeature feature) =>
    feature.kind == FamilyFeatureKind.box ||
    feature.kind == FamilyFeatureKind.extrude ||
    feature.kind == FamilyFeatureKind.revolve ||
    feature.kind == FamilyFeatureKind.booleanUnion ||
    feature.kind == FamilyFeatureKind.booleanSubtract ||
    feature.kind == FamilyFeatureKind.transform ||
    feature.kind == FamilyFeatureKind.freeformMesh ||
    feature.kind == FamilyFeatureKind.nestedFamily;

String _featureLabel(FamilyFeature feature) {
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

String _featureSummary(FamilyFeature feature) => switch (feature.kind) {
      FamilyFeatureKind.box => 'Family Type dimensions',
      FamilyFeatureKind.profile =>
        'Sketch: ${feature.parameters['profileId'] ?? feature.inputs.firstOrNull ?? 'none'}',
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

String _featureDetails(FamilyDocument document, FamilyFeature feature) {
  switch (feature.kind) {
    case FamilyFeatureKind.box:
      return 'Parametric base solid. Width, depth and height follow the active Family Type.';
    case FamilyFeatureKind.profile:
      return 'Profile sketch: ${feature.parameters['profileId'] ?? feature.inputs.firstOrNull ?? 'not selected'}';
    case FamilyFeatureKind.extrude:
      return 'Profile ${feature.parameters['profileId'] ?? '—'} · depth ${feature.parameters['depth'] ?? '—'}';
    case FamilyFeatureKind.revolve:
      return 'Profile ${feature.parameters['profileId'] ?? '—'} · angle ${feature.parameters['angle'] ?? '—'}°';
    case FamilyFeatureKind.booleanUnion:
      return 'Exact CSG union when both inputs are closed manifold solids. Inputs: ${feature.inputs.join(' + ')}';
    case FamilyFeatureKind.booleanSubtract:
      return 'Exact CSG subtract when both inputs are closed manifold solids. Base − tool: ${feature.inputs.join(' − ')}';
    case FamilyFeatureKind.transform:
      return 'Source ${feature.inputs.firstOrNull ?? 'previous solid'} · X ${feature.parameters['translationX'] ?? 0} · Y ${feature.parameters['translationY'] ?? 0} · Z ${feature.parameters['translationZ'] ?? 0} · R ${feature.parameters['rotationZ'] ?? 0}° · S ${feature.parameters['scale'] ?? 1}';
    case FamilyFeatureKind.freeformMesh:
      final vertices = feature.parameters['vertices'];
      final faces = feature.parameters['faces'];
      return '${vertices is List ? vertices.length : 0} vertices · ${faces is List ? faces.length : 0} faces';
    case FamilyFeatureKind.nestedFamily:
      return 'Child ${feature.parameters['familyId'] ?? '—'} · type ${feature.parameters['typeId'] ?? '—'} · X ${feature.parameters['translationX'] ?? 0} · Y ${feature.parameters['translationY'] ?? 0} · Z ${feature.parameters['translationZ'] ?? 0} · R ${feature.parameters['rotationZ'] ?? 0}° · S ${feature.parameters['scale'] ?? 1}';
  }
}

IconData _featureIcon(FamilyFeatureKind kind) => switch (kind) {
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
