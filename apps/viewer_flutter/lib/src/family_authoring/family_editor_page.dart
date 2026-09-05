import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_sketch_canvas.dart';
import 'family_validation.dart';

/// Family Authoring editor.
///
/// The page edits a reusable document, not an object inside a project. Its
/// sketch and feature graph state stays inside this module; the project
/// viewport is not involved until a later family-instance adapter consumes a
/// saved asset.
class FamilyEditorPage extends StatefulWidget {
  const FamilyEditorPage({super.key});

  @override
  State<FamilyEditorPage> createState() => _FamilyEditorPageState();
}

class _FamilyEditorPageState extends State<FamilyEditorPage> {
  late FamilyDocument _document;
  late TextEditingController _widthController;
  late TextEditingController _depthController;
  late TextEditingController _heightController;
  late TextEditingController _extrusionController;
  late TextEditingController _revolveAngleController;
  String? _selectedTypeId;
  String? _selectedSketchId;
  String? _status;
  bool _dirty = false;
  final List<FamilyDocument> _undoStack = <FamilyDocument>[];
  final List<FamilyDocument> _redoStack = <FamilyDocument>[];

  FamilyTypeDefinition get _selectedType {
    return _document.types.firstWhere(
      (type) => type.id == _selectedTypeId,
      orElse: () => _document.types.first,
    );
  }

  FamilySketch? get _selectedSketch {
    for (final sketch in _document.sketches) {
      if (sketch.id == _selectedSketchId) return sketch;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _document = FamilyDocument.starter();
    _selectedTypeId = _document.types.first.id;
    _widthController = TextEditingController(text: '1.00');
    _depthController = TextEditingController(text: '1.00');
    _heightController = TextEditingController(text: '1.00');
    _extrusionController = TextEditingController(text: '1.00');
    _revolveAngleController = TextEditingController(text: '360.00');
  }

  @override
  void dispose() {
    _widthController.dispose();
    _depthController.dispose();
    _heightController.dispose();
    _extrusionController.dispose();
    _revolveAngleController.dispose();
    super.dispose();
  }

  void _updateDocument(FamilyDocument document) {
    _undoStack.add(_document);
    _redoStack.clear();
    setState(() {
      _document = document;
      _dirty = true;
      _status = null;
    });
  }

  void _restoreDocument(FamilyDocument document) {
    setState(() {
      _document = document;
      _dirty = true;
      _status = null;
      if (!_document.types.any((type) => type.id == _selectedTypeId)) {
        _selectedTypeId = _document.types.first.id;
      }
      if (!_document.sketches.any((sketch) => sketch.id == _selectedSketchId)) {
        _selectedSketchId =
            _document.sketches.isEmpty ? null : _document.sketches.last.id;
      }
      _syncTypeControllers();
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_document);
    final previous = _undoStack.removeLast();
    _restoreDocument(previous);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_document);
    final next = _redoStack.removeLast();
    _restoreDocument(next);
  }

  void _syncTypeControllers() {
    final type = _selectedType;
    _setControllerText(_widthController, type.values['width']);
    _setControllerText(_depthController, type.values['depth']);
    _setControllerText(_heightController, type.values['height']);
    _setControllerText(_extrusionController, type.values['extrusionDepth']);
    _setControllerText(
        _revolveAngleController, type.values['revolveAngle'] ?? 360);
  }

  void _updateTypeValue(String parameterId, String rawValue) {
    final value = double.tryParse(rawValue.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0.0) return;
    final definition = _document.parameters.firstWhere(
      (parameter) => parameter.id == parameterId,
      orElse: () => const FamilyParameterDefinition(
        id: '',
        label: '',
        kind: FamilyParameterKind.number,
        defaultValue: null,
      ),
    );
    if (definition.minimum != null && value < definition.minimum!) return;
    if (definition.maximum != null && value > definition.maximum!) return;
    final type = _selectedType;
    final values = <String, Object?>{...type.values, parameterId: value};
    final types = <FamilyTypeDefinition>[
      for (final item in _document.types)
        item.id == type.id ? item.copyWith(values: values) : item,
    ];
    _updateDocument(_document.copyWith(types: types));
  }

  void _updateSketch(FamilySketch sketch) {
    _updateDocument(_document.copyWith(
      sketches: <FamilySketch>[
        for (final item in _document.sketches)
          item.id == sketch.id ? sketch : item,
      ],
    ));
  }

  void _addProfileSketch() {
    final id = 'sketch-${DateTime.now().microsecondsSinceEpoch}';
    final sketch = FamilySketch(
      id: id,
      name: 'Profile ${_document.sketches.length + 1}',
      plane: FamilySketchPlane.xy,
    );
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.profile,
      label: sketch.name,
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{'profileId': sketch.id},
    );
    setState(() => _selectedSketchId = sketch.id);
    _updateDocument(_document.copyWith(
      sketches: <FamilySketch>[..._document.sketches, sketch],
      features: <FamilyFeature>[..._document.features, feature],
    ));
  }

  void _addExtrude() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first');
      return;
    }
    final hasDepthParameter = _document.parameters.any(
      (parameter) => parameter.id == 'extrusionDepth',
    );
    final parameters = hasDepthParameter
        ? _document.parameters
        : <FamilyParameterDefinition>[
            ..._document.parameters,
            const FamilyParameterDefinition(
              id: 'extrusionDepth',
              label: 'Extrusion depth',
              kind: FamilyParameterKind.length,
              defaultValue: 1.0,
              minimum: 0.01,
            ),
          ];
    final values = <String, Object?>{
      ..._selectedType.values,
      'extrusionDepth': _selectedType.values['extrusionDepth'] ?? 1.0,
    };
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.extrude,
      label: 'Extrude ${sketch.name}',
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{
        'profileId': sketch.id,
        'depth': 'extrusionDepth',
      },
    );
    final types = <FamilyTypeDefinition>[
      for (final type in _document.types)
        type.id == _selectedType.id ? type.copyWith(values: values) : type,
    ];
    _updateDocument(_document.copyWith(
      parameters: parameters,
      types: types,
      features: <FamilyFeature>[..._document.features, feature],
    ));
  }

  void _addRevolve() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first');
      return;
    }
    final hasAngleParameter = _document.parameters.any(
      (parameter) => parameter.id == 'revolveAngle',
    );
    final parameters = hasAngleParameter
        ? _document.parameters
        : <FamilyParameterDefinition>[
            ..._document.parameters,
            const FamilyParameterDefinition(
              id: 'revolveAngle',
              label: 'Revolve angle',
              kind: FamilyParameterKind.angle,
              defaultValue: 360.0,
              minimum: 1.0,
              maximum: 360.0,
            ),
          ];
    final values = <String, Object?>{
      ..._selectedType.values,
      'revolveAngle': _selectedType.values['revolveAngle'] ?? 360.0,
    };
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.revolve,
      label: 'Revolve ${sketch.name}',
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{
        'profileId': sketch.id,
        'angle': 'revolveAngle',
      },
    );
    final types = <FamilyTypeDefinition>[
      for (final type in _document.types)
        type.id == _selectedType.id ? type.copyWith(values: values) : type,
    ];
    _updateDocument(_document.copyWith(
      parameters: parameters,
      types: types,
      features: <FamilyFeature>[..._document.features, feature],
    ));
  }

  void _addBoolean(FamilyFeatureKind kind) {
    final solids = _document.features.where(_isSolidFeature).toList();
    if (solids.length < 2) {
      setState(() => _status = 'Create two solid features before a boolean');
      return;
    }
    final inputs = <String>[solids[solids.length - 2].id, solids.last.id];
    final union = kind == FamilyFeatureKind.booleanUnion;
    _updateDocument(_document.copyWith(features: <FamilyFeature>[
      ..._document.features,
      FamilyFeature(
        id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        label: union ? 'Union solids' : 'Subtract solids',
        inputs: inputs,
        parameters: <String, Object?>{'operation': kind.name},
      ),
    ]));
  }

  void _addTransform() {
    if (_document.features.where(_isSolidFeature).isEmpty) {
      setState(() => _status = 'Create a solid before adding a transform');
      return;
    }
    final source = _document.features.lastWhere(_isSolidFeature);
    _updateDocument(_document.copyWith(features: <FamilyFeature>[
      ..._document.features,
      FamilyFeature(
        id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
        kind: FamilyFeatureKind.transform,
        label: 'Transform ${_featureLabel(source)}',
        inputs: <String>[source.id],
        parameters: const <String, Object?>{
          'translationX': 0.0,
          'translationY': 0.0,
          'translationZ': 0.0,
          'rotationZ': 0.0,
          'scale': 1.0,
        },
      ),
    ]));
  }

  static bool _isSolidFeature(FamilyFeature feature) {
    return feature.kind == FamilyFeatureKind.box ||
        feature.kind == FamilyFeatureKind.extrude ||
        feature.kind == FamilyFeatureKind.revolve ||
        feature.kind == FamilyFeatureKind.booleanUnion ||
        feature.kind == FamilyFeatureKind.booleanSubtract ||
        feature.kind == FamilyFeatureKind.freeformMesh ||
        feature.kind == FamilyFeatureKind.transform;
  }

  void _addSketchPoint(FamilySketchPoint point) {
    final sketch = _selectedSketch;
    if (sketch == null || sketch.closed) return;
    _updateSketch(sketch.copyWith(points: <FamilySketchPoint>[
      ...sketch.points,
      point,
    ]));
  }

  void _moveSketchPoint(int index, FamilySketchPoint point) {
    final sketch = _selectedSketch;
    if (sketch == null || index < 0 || index >= sketch.points.length) return;
    final points = <FamilySketchPoint>[...sketch.points];
    points[index] = point;
    _updateSketch(sketch.copyWith(points: points));
  }

  void _toggleSketchClosed() {
    final sketch = _selectedSketch;
    if (sketch == null) return;
    if (!sketch.closed && sketch.points.length < 3) {
      setState(() => _status = 'A profile needs at least 3 points');
      return;
    }
    _updateSketch(sketch.copyWith(closed: !sketch.closed));
  }

  void _clearSketch() {
    final sketch = _selectedSketch;
    if (sketch == null) return;
    _updateSketch(
        sketch.copyWith(points: const <FamilySketchPoint>[], closed: false));
  }

  void _selectType(String? id) {
    if (id == null) return;
    final next = _document.types.firstWhere((type) => type.id == id);
    setState(() {
      _selectedTypeId = id;
      _setControllerText(_widthController, next.values['width']);
      _setControllerText(_depthController, next.values['depth']);
      _setControllerText(_heightController, next.values['height']);
      _setControllerText(
        _extrusionController,
        next.values['extrusionDepth'],
      );
      _setControllerText(
        _revolveAngleController,
        next.values['revolveAngle'] ?? 360,
      );
    });
  }

  void _setControllerText(TextEditingController controller, Object? value) {
    final number = value is num ? value.toDouble() : 1.0;
    controller.value = TextEditingValue(
      text: number.toStringAsFixed(2),
      selection:
          TextSelection.collapsed(offset: number.toStringAsFixed(2).length),
    );
  }

  void _addType() {
    final id = 'type-${DateTime.now().microsecondsSinceEpoch}';
    final source = _selectedType;
    final type = FamilyTypeDefinition(
      id: id,
      name: 'Type ${_document.types.length + 1}',
      values: source.values,
    );
    _updateDocument(_document.copyWith(types: <FamilyTypeDefinition>[
      ..._document.types,
      type,
    ]));
    _selectedTypeId = id;
  }

  Future<bool> _save() async {
    final validation = FamilyDocumentValidator.validate(_document);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return false;
    }
    setState(() => _status = 'Saving family...');
    try {
      final path = await FamilyFileStore.save(_document);
      if (!mounted || path == null) return false;
      setState(() {
        _dirty = false;
        _status = 'Saved: ${path.split('/').last}';
      });
      return true;
    } catch (error) {
      if (mounted) setState(() => _status = 'Save failed: $error');
      return false;
    }
  }

  Future<void> _requestClose() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<_FamilyCloseAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved family'),
        content: const Text(
          'Save this family to the library before leaving, or discard the changes?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_FamilyCloseAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_FamilyCloseAction.save),
            child: const Text('Save & close'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == _FamilyCloseAction.save) {
      if (await _save() && mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _dirty = false);
    if (mounted) Navigator.of(context).pop();
  }

  void _showProjectHandoff() {
    final hosted = _document.category == FamilyCategory.door ||
        _document.category == FamilyCategory.window;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use this family in a project'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('1  Save the family to the library.'),
              const SizedBox(height: 8),
              const Text('2  Open or create a project.'),
              const SizedBox(height: 8),
              Text(
                hosted
                    ? '3  Select a solid wall, then open ⋮ → Add family to project.'
                    : '3  Open ⋮ → Add family to project and choose the placement point.',
              ),
              const SizedBox(height: 12),
              Text(
                hosted
                    ? 'Doors and windows become native hosted openings; the family/type reference remains attached to the project element.'
                    : 'The project stores the family/type reference and creates the supported native element.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = _selectedType;
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Family Editor'),
          leading: IconButton(
            tooltip: 'Close family',
            onPressed: _requestClose,
            icon: const Icon(Icons.close),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Undo',
              onPressed: _undoStack.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_outlined),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _redoStack.isEmpty ? null : _redo,
              icon: const Icon(Icons.redo_outlined),
            ),
            OutlinedButton.icon(
              onPressed: _showProjectHandoff,
              icon: const Icon(Icons.output_outlined),
              label: const Text('Use in project'),
            ),
            if (_status != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _status!,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: () => _save(),
              icon: const Icon(Icons.save_outlined),
              label: Text(_dirty ? 'Save to library' : 'Saved'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final editor = _EditorPanel(
                document: _document,
                selectedTypeId: _selectedTypeId,
                selectedSketchId: _selectedSketchId,
                onNameChanged: (value) => _updateDocument(
                  _document.copyWith(
                      name: value.trim().isEmpty ? 'New Family' : value),
                ),
                onCategoryChanged: (value) {
                  if (value != null) {
                    _updateDocument(_document.copyWith(category: value));
                  }
                },
                onTypeChanged: _selectType,
                onAddType: _addType,
                onAddProfile: _addProfileSketch,
                onAddExtrude: _addExtrude,
                onAddRevolve: _addRevolve,
                onAddUnion: () => _addBoolean(FamilyFeatureKind.booleanUnion),
                onAddSubtract: () =>
                    _addBoolean(FamilyFeatureKind.booleanSubtract),
                onAddTransform: _addTransform,
                onSketchChanged: (value) {
                  setState(() => _selectedSketchId = value);
                },
                widthController: _widthController,
                depthController: _depthController,
                heightController: _heightController,
                extrusionController: _extrusionController,
                revolveAngleController: _revolveAngleController,
                onWidthChanged: (value) => _updateTypeValue('width', value),
                onDepthChanged: (value) => _updateTypeValue('depth', value),
                onHeightChanged: (value) => _updateTypeValue('height', value),
                onExtrusionChanged: (value) =>
                    _updateTypeValue('extrusionDepth', value),
                onRevolveAngleChanged: (value) =>
                    _updateTypeValue('revolveAngle', value),
              );
              final shape = FamilyGeometryEvaluator.evaluate(_document, type);
              final mesh =
                  FamilyGeometryEvaluator.evaluateMesh(_document, type);
              final sketch = _selectedSketch;
              final preview = _FamilyPreview(
                name: _document.name,
                category: _document.category,
                shape: shape,
                mesh: mesh,
              );
              final workspacePreview = _FamilyPreviewColumn(
                preview: preview,
                sketch: sketch,
                onAddPoint: _addSketchPoint,
                onMovePoint: _moveSketchPoint,
                onToggleClosed: _toggleSketchClosed,
                onClear: _clearSketch,
              );
              if (compact) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      editor,
                      const SizedBox(height: 16),
                      SizedBox(
                        height: sketch == null ? 280 : 560,
                        child: workspacePreview,
                      ),
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      border: Border(
                        right: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: SizedBox(
                      width: 410,
                      child: SingleChildScrollView(child: editor),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: workspacePreview,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _FamilyCloseAction { save, discard }

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.document,
    required this.selectedTypeId,
    required this.selectedSketchId,
    required this.onNameChanged,
    required this.onCategoryChanged,
    required this.onTypeChanged,
    required this.onAddType,
    required this.onAddProfile,
    required this.onAddExtrude,
    required this.onAddRevolve,
    required this.onAddUnion,
    required this.onAddSubtract,
    required this.onAddTransform,
    required this.onSketchChanged,
    required this.widthController,
    required this.depthController,
    required this.heightController,
    required this.extrusionController,
    required this.revolveAngleController,
    required this.onWidthChanged,
    required this.onDepthChanged,
    required this.onHeightChanged,
    required this.onExtrusionChanged,
    required this.onRevolveAngleChanged,
  });

  final FamilyDocument document;
  final String? selectedTypeId;
  final String? selectedSketchId;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<FamilyCategory?> onCategoryChanged;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onAddType;
  final VoidCallback onAddProfile;
  final VoidCallback onAddExtrude;
  final VoidCallback onAddRevolve;
  final VoidCallback onAddUnion;
  final VoidCallback onAddSubtract;
  final VoidCallback onAddTransform;
  final ValueChanged<String?> onSketchChanged;
  final TextEditingController widthController;
  final TextEditingController depthController;
  final TextEditingController heightController;
  final TextEditingController extrusionController;
  final TextEditingController revolveAngleController;
  final ValueChanged<String> onWidthChanged;
  final ValueChanged<String> onDepthChanged;
  final ValueChanged<String> onHeightChanged;
  final ValueChanged<String> onExtrusionChanged;
  final ValueChanged<String> onRevolveAngleChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FamilyWorkflowCard(category: _categoryLabel(document.category)),
          const SizedBox(height: 12),
          _FamilySection(
            number: '1',
            title: 'Family',
            subtitle: 'Name and category',
            initiallyExpanded: true,
            child: Column(
              children: <Widget>[
                TextFormField(
                  initialValue: document.name,
                  decoration: const InputDecoration(
                    labelText: 'Family name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  onChanged: onNameChanged,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<FamilyCategory>(
                  initialValue: document.category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: FamilyCategory.values
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(_categoryLabel(category)),
                        ),
                      )
                      .toList(),
                  onChanged: onCategoryChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FamilySection(
            number: '2',
            title: 'Type & parameters',
            subtitle:
                '${document.types.length} type${document.types.length == 1 ? '' : 's'} · edit the selected type',
            initiallyExpanded: true,
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String?>(selectedTypeId),
                        initialValue: selectedTypeId,
                        decoration: const InputDecoration(
                          labelText: 'Family type',
                          prefixIcon: Icon(Icons.tune_outlined),
                        ),
                        items: document.types
                            .map((type) => DropdownMenuItem(
                                  value: type.id,
                                  child: Text(type.name),
                                ))
                            .toList(),
                        onChanged: onTypeChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Add family type',
                      onPressed: onAddType,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _ParameterField(
                        label: 'Width',
                        controller: widthController,
                        onChanged: onWidthChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ParameterField(
                        label: 'Depth',
                        controller: depthController,
                        onChanged: onDepthChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ParameterField(
                  label: 'Height',
                  controller: heightController,
                  onChanged: onHeightChanged,
                ),
                if (document.parameters.any(
                  (parameter) => parameter.id == 'extrusionDepth',
                )) ...<Widget>[
                  const SizedBox(height: 8),
                  _ParameterField(
                    label: 'Extrusion depth',
                    controller: extrusionController,
                    onChanged: onExtrusionChanged,
                  ),
                ],
                if (document.parameters.any(
                  (parameter) => parameter.id == 'revolveAngle',
                )) ...<Widget>[
                  const SizedBox(height: 8),
                  _ParameterField(
                    label: 'Revolve angle',
                    controller: revolveAngleController,
                    suffix: '°',
                    onChanged: onRevolveAngleChanged,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FamilySection(
            number: '3',
            title: 'Build geometry',
            subtitle: 'Profile → close → make a solid',
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _FamilyHint(
                  icon: Icons.touch_app_outlined,
                  text:
                      'Start with Profile. Tap points on the canvas, close it, then add Extrude.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onAddProfile,
                      icon: const Icon(Icons.polyline_outlined),
                      label: const Text('Profile'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddExtrude,
                      icon: const Icon(Icons.height),
                      label: const Text('Extrude'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddRevolve,
                      icon: const Icon(Icons.rotate_right_outlined),
                      label: const Text('Revolve'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddUnion,
                      icon: const Icon(Icons.merge_type_outlined),
                      label: const Text('Union'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddSubtract,
                      icon: const Icon(Icons.call_split_outlined),
                      label: const Text('Subtract'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAddTransform,
                      icon: const Icon(Icons.open_with_outlined),
                      label: const Text('Transform'),
                    ),
                  ],
                ),
                if (document.sketches.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(selectedSketchId),
                    initialValue: selectedSketchId,
                    decoration: const InputDecoration(
                      labelText: 'Active profile',
                      prefixIcon: Icon(Icons.edit_note_outlined),
                    ),
                    items: document.sketches
                        .map(
                          (sketch) => DropdownMenuItem(
                            value: sketch.id,
                            child: Text(
                              '${sketch.name}${sketch.closed ? '' : ' · open'}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onSketchChanged,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FamilySection(
            number: '4',
            title: 'Feature graph',
            subtitle:
                '${document.features.length} feature node${document.features.length == 1 ? '' : 's'}',
            initiallyExpanded: false,
            child: Column(
              children: <Widget>[
                for (final feature in document.features)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    child: ListTile(
                      dense: true,
                      leading: Icon(_featureIcon(feature.kind)),
                      title: Text(_featureLabel(feature)),
                      subtitle: Text(_featureSummary(feature)),
                      trailing: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                Text(
                  'The graph is generated from the tools above. Edit profiles on the canvas; the preview updates immediately.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ProjectHandoffCard(category: document.category),
        ],
      ),
    );
  }
}

class _FamilyWorkflowCard extends StatelessWidget {
  const _FamilyWorkflowCard({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.account_tree_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Family workspace',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Define  ·  Build  ·  Save  ·  Use in project',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '$category family · changes stay local until you save it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilySection extends StatelessWidget {
  const _FamilySection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.initiallyExpanded,
  });

  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: Text(number),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(subtitle),
        children: <Widget>[child],
      ),
    );
  }
}

class _FamilyHint extends StatelessWidget {
  const _FamilyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ProjectHandoffCard extends StatelessWidget {
  const _ProjectHandoffCard({required this.category});

  final FamilyCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hosted =
        category == FamilyCategory.door || category == FamilyCategory.window;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.output_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Next: use in project',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  hosted
                      ? 'Save to library → select a solid wall → ⋮ → Add family to project.'
                      : 'Save to library → open a project → ⋮ → Add family to project.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.suffix = 'm',
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        filled: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

class _FamilyPreviewColumn extends StatelessWidget {
  const _FamilyPreviewColumn({
    required this.preview,
    required this.sketch,
    required this.onAddPoint,
    required this.onMovePoint,
    required this.onToggleClosed,
    required this.onClear,
  });

  final Widget preview;
  final FamilySketch? sketch;
  final ValueChanged<FamilySketchPoint> onAddPoint;
  final void Function(int index, FamilySketchPoint point) onMovePoint;
  final VoidCallback onToggleClosed;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final activeSketch = sketch;
    if (activeSketch == null) return preview;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: preview),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${activeSketch.name} · ${activeSketch.points.length} points',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear profile',
                        onPressed: onClear,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                      TextButton.icon(
                        onPressed: activeSketch.closed ||
                                activeSketch.points.length >= 3
                            ? onToggleClosed
                            : null,
                        icon: Icon(
                          activeSketch.closed
                              ? Icons.lock_open_outlined
                              : Icons.check_circle_outline,
                        ),
                        label: Text(activeSketch.closed ? 'Reopen' : 'Close'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    activeSketch.closed
                        ? 'Closed profile · drag points to reshape'
                        : 'Tap to add points · drag a point to reshape',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: FamilySketchCanvas(
                      sketch: activeSketch,
                      onAddPoint: onAddPoint,
                      onMovePoint: onMovePoint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyPreview extends StatelessWidget {
  const _FamilyPreview({
    required this.name,
    required this.category,
    required this.shape,
    required this.mesh,
  });

  final String name;
  final FamilyCategory category;
  final FamilyPreviewShape shape;
  final FamilyEvaluatedMesh mesh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _FamilyPreviewPainter(
                primary: colors.primary,
                secondary: colors.tertiary,
                surface: colors.surfaceContainerHighest,
                mesh: mesh,
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 16,
            child: Text(
              name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 14,
            child: Text(
              '${_categoryLabel(category)} · ${shape.source} · ${mesh.vertices.length}v / ${mesh.faces.length}f${mesh.isApproximate ? ' · preview' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyPreviewPainter extends CustomPainter {
  const _FamilyPreviewPainter({
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.mesh,
  });

  final Color primary;
  final Color secondary;
  final Color surface;
  final FamilyEvaluatedMesh mesh;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = surface.withValues(alpha: 0.35));
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty) return;
    final projected = <Offset>[
      for (final vertex in mesh.vertices)
        Offset(
          vertex.x - vertex.z * 0.48,
          -vertex.y + (vertex.x + vertex.z) * 0.24,
        ),
    ];
    final minX = projected.map((point) => point.dx).reduce(math.min);
    final maxX = projected.map((point) => point.dx).reduce(math.max);
    final minY = projected.map((point) => point.dy).reduce(math.min);
    final maxY = projected.map((point) => point.dy).reduce(math.max);
    final width = math.max(maxX - minX, 0.1);
    final height = math.max(maxY - minY, 0.1);
    final scale = math.min(
          (size.width - 44) / width,
          (size.height - 64) / height,
        ) *
        0.82;
    final center = Offset(size.width * 0.5, size.height * 0.59);
    final modelCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final points = projected
        .map(
          (point) => Offset(
            center.dx + (point.dx - modelCenter.dx) * scale,
            center.dy + (point.dy - modelCenter.dy) * scale,
          ),
        )
        .toList();
    final outline = Paint()
      ..color = primary.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final orderedFaces = <int>[
      for (var index = 0; index < mesh.faces.length; index++)
        if (mesh.faces[index].indices.length >= 3 &&
            mesh.faces[index].indices
                .every((vertex) => vertex >= 0 && vertex < points.length))
          index,
    ]..sort((left, right) {
        final leftDepth = _faceDepth(mesh.faces[left], projected);
        final rightDepth = _faceDepth(mesh.faces[right], projected);
        return rightDepth.compareTo(leftDepth);
      });
    for (final faceIndex in orderedFaces) {
      final face = mesh.faces[faceIndex];
      final path = _closedPath(<Offset>[
        for (final index in face.indices) points[index],
      ]);
      final faceColor = faceIndex.isEven ? primary : secondary;
      canvas.drawPath(path, Paint()..color = faceColor.withValues(alpha: 0.14));
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyPreviewPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.surface != surface ||
      oldDelegate.mesh != mesh;
}

Path _closedPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();
  return path;
}

double _faceDepth(FamilyMeshFace face, List<Offset> projected) {
  var total = 0.0;
  for (final index in face.indices) {
    total += projected[index].dy;
  }
  return total / face.indices.length;
}

IconData _featureIcon(FamilyFeatureKind kind) {
  return switch (kind) {
    FamilyFeatureKind.box => Icons.crop_square_outlined,
    FamilyFeatureKind.profile => Icons.polyline_outlined,
    FamilyFeatureKind.extrude => Icons.height,
    FamilyFeatureKind.revolve => Icons.rotate_right_outlined,
    FamilyFeatureKind.booleanUnion => Icons.merge_type_outlined,
    FamilyFeatureKind.booleanSubtract => Icons.call_split_outlined,
    FamilyFeatureKind.transform => Icons.open_with_outlined,
    FamilyFeatureKind.freeformMesh => Icons.grid_4x4_outlined,
  };
}

String _featureLabel(FamilyFeature feature) {
  if (feature.label.trim().isNotEmpty) return feature.label;
  return switch (feature.kind) {
    FamilyFeatureKind.box => 'Box solid',
    FamilyFeatureKind.profile => 'Profile',
    FamilyFeatureKind.extrude => 'Extrude',
    FamilyFeatureKind.revolve => 'Revolve',
    FamilyFeatureKind.booleanUnion => 'Boolean union',
    FamilyFeatureKind.booleanSubtract => 'Boolean subtract',
    FamilyFeatureKind.transform => 'Transform',
    FamilyFeatureKind.freeformMesh => 'Freeform mesh',
  };
}

String _featureSummary(FamilyFeature feature) {
  return switch (feature.kind) {
    FamilyFeatureKind.box => 'Width × depth × height',
    FamilyFeatureKind.profile => '2D closed sketch input',
    FamilyFeatureKind.extrude => 'Profile → parametric solid',
    FamilyFeatureKind.revolve => 'Profile → revolved solid',
    FamilyFeatureKind.booleanUnion => 'Combine solid inputs',
    FamilyFeatureKind.booleanSubtract => 'Cut solid inputs',
    FamilyFeatureKind.transform => 'Move / rotate / scale',
    FamilyFeatureKind.freeformMesh => 'Editable mesh geometry',
  };
}

String _categoryLabel(FamilyCategory category) {
  return switch (category) {
    FamilyCategory.genericModel => 'Generic model',
    FamilyCategory.column => 'Column',
    FamilyCategory.door => 'Door',
    FamilyCategory.window => 'Window',
    FamilyCategory.furniture => 'Furniture',
    FamilyCategory.structural => 'Structural',
  };
}
