import 'package:flutter/material.dart';

import 'family_constraint_models.dart';
import 'family_constraint_solver.dart';
import 'family_constraints_panel.dart';
import 'family_dependency_resolver.dart';
import 'family_document.dart';
import 'family_feature_workbench.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_import_units_dialog.dart';
import 'family_interactive_preview.dart';
import 'family_mesh_importer.dart';
import 'family_nested_feature_dialog.dart';
import 'family_parameter_resolver.dart';
import 'family_sketch_canvas.dart';
import 'family_validation.dart';

/// Interactive Family Editor shell.
///
/// The document/evaluator/CSG contracts are unchanged from V2. V3 only splits
/// the authoring surface into independent interaction components so orbit,
/// feature editing and future gizmos do not have to live in one monolithic
/// widget.
class FamilyEditorV3Page extends StatefulWidget {
  const FamilyEditorV3Page({
    super.key,
    this.initialAsset,
  });

  final FamilyAssetFile? initialAsset;

  @override
  State<FamilyEditorV3Page> createState() => _FamilyEditorV3PageState();
}

enum _EditorMode { simple, advanced }
enum _CloseChoice { save, discard }

class _FamilyEditorV3PageState extends State<FamilyEditorV3Page> {
  late FamilyDocument _document;
  late final TextEditingController _name;
  late final TextEditingController _description;

  String? _assetPath;
  String? _selectedTypeId;
  String? _selectedSketchId;
  String? _selectedFeatureId;
  String? _status;
  _EditorMode _mode = _EditorMode.simple;
  bool _dirty = false;

  final List<FamilyDocument> _undo = <FamilyDocument>[];
  final List<FamilyDocument> _redo = <FamilyDocument>[];
  String? _nestedPreviewKey;
  Future<FamilyEvaluatedMesh>? _nestedPreview;

  @override
  void initState() {
    super.initState();
    final asset = widget.initialAsset;
    _document = asset?.document ?? FamilyDocument.starter();
    _assetPath = asset?.path;
    _selectedTypeId = asset?.preferredTypeId ?? _document.types.first.id;
    _selectedSketchId =
        _document.sketches.isEmpty ? null : _document.sketches.first.id;
    _selectedFeatureId =
        _document.features.isEmpty ? null : _document.features.last.id;
    _name = TextEditingController(text: _document.name);
    _description = TextEditingController(text: _document.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  FamilyTypeDefinition get _selectedType {
    for (final type in _document.types) {
      if (type.id == _selectedTypeId) return type;
    }
    return _document.types.first;
  }

  FamilySketch? get _selectedSketch {
    for (final sketch in _document.sketches) {
      if (sketch.id == _selectedSketchId) return sketch;
    }
    return null;
  }

  FamilySketch? get _solvedSketch {
    final sketch = _selectedSketch;
    if (sketch == null) return null;
    try {
      return FamilyConstraintSolver.solveSketch(
        _document,
        _selectedType,
        sketch,
      ).sketch;
    } catch (_) {
      return sketch;
    }
  }

  bool get _hasNested => _document.features.any(
        (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
      );

  void _setDocument(
    FamilyDocument next, {
    required bool dirty,
    String? status,
    bool syncText = false,
  }) {
    setState(() {
      _document = next;
      _dirty = dirty;
      _status = status;
      if (!_document.types.any((type) => type.id == _selectedTypeId)) {
        _selectedTypeId = _document.types.first.id;
      }
      if (!_document.sketches.any((sketch) => sketch.id == _selectedSketchId)) {
        _selectedSketchId =
            _document.sketches.isEmpty ? null : _document.sketches.last.id;
      }
      if (!_document.features.any((feature) => feature.id == _selectedFeatureId)) {
        _selectedFeatureId =
            _document.features.isEmpty ? null : _document.features.last.id;
      }
      _nestedPreview = null;
      _nestedPreviewKey = null;
      if (syncText) {
        _name.text = _document.name;
        _description.text = _document.description;
      }
    });
  }

  void _commit(
    FamilyDocument next, {
    String? status,
    String? selectFeatureId,
  }) {
    final validation = FamilyDocumentValidator.validate(next);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return;
    }
    _undo.add(_document);
    _redo.clear();
    if (selectFeatureId != null) _selectedFeatureId = selectFeatureId;
    _setDocument(next, dirty: true, status: status);
  }

  void _replaceDraft(FamilyDocument next, {String? status}) {
    _redo.clear();
    _setDocument(next, dirty: true, status: status);
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    _redo.add(_document);
    _setDocument(
      _undo.removeLast(),
      dirty: true,
      syncText: true,
      status: 'Undo',
    );
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    _undo.add(_document);
    _setDocument(
      _redo.removeLast(),
      dirty: true,
      syncText: true,
      status: 'Redo',
    );
  }

  Object? _effective(FamilyParameterDefinition parameter) {
    try {
      return FamilyParameterResolver(_document, _selectedType).resolve(parameter);
    } catch (_) {
      return _selectedType.valueFor(parameter);
    }
  }

  void _updateTypeValue(
    FamilyParameterDefinition parameter,
    Object? value,
  ) {
    if (parameter.hasFormula || !_parameterValueValid(parameter, value)) return;
    final selected = _selectedType;
    if (selected.values[parameter.id] == value) return;
    _replaceDraft(
      _document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.id == selected.id
                ? type.copyWith(
                    values: <String, Object?>{
                      ...type.values,
                      parameter.id: value,
                    },
                  )
                : type,
        ],
      ),
    );
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String initial,
    required String action,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (raw) {
            final value = raw.trim();
            if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _duplicateType() async {
    final source = _selectedType;
    final name = await _askText(
      title: 'Duplicate family type',
      label: 'Type name',
      initial: '${source.name} Copy',
      action: 'Duplicate',
    );
    if (!mounted || name == null) return;
    if (_document.types.any(
      (type) => type.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => _status = 'A type named "$name" already exists.');
      return;
    }
    final type = FamilyTypeDefinition(
      id: 'type-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      values: Map<String, Object?>.from(source.values),
    );
    _selectedTypeId = type.id;
    _commit(
      _document.copyWith(types: <FamilyTypeDefinition>[..._document.types, type]),
      status: 'Family Type duplicated',
    );
  }

  Future<void> _renameType() async {
    final selected = _selectedType;
    final name = await _askText(
      title: 'Rename family type',
      label: 'Type name',
      initial: selected.name,
      action: 'Rename',
    );
    if (!mounted || name == null || name == selected.name) return;
    if (_document.types.any(
      (type) =>
          type.id != selected.id &&
          type.name.trim().toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => _status = 'A type named "$name" already exists.');
      return;
    }
    _commit(
      _document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.id == selected.id ? type.copyWith(name: name) : type,
        ],
      ),
      status: 'Family Type renamed',
    );
  }

  Future<void> _deleteType() async {
    if (_document.types.length <= 1) {
      setState(() => _status = 'A family must keep at least one type.');
      return;
    }
    final selected = _selectedType;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${selected.name}?'),
        content: const Text('This removes this reusable type definition.'),
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
    if (!mounted || remove != true) return;
    final types = <FamilyTypeDefinition>[
      for (final type in _document.types)
        if (type.id != selected.id) type,
    ];
    _selectedTypeId = types.first.id;
    _commit(_document.copyWith(types: types), status: 'Family Type deleted');
  }

  Future<void> _addParameter() async {
    final draft = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => const _ParameterDialog(),
    );
    if (!mounted || draft == null) return;
    final id = _safeId(draft.label);
    if (id.isEmpty || _document.parameters.any((item) => item.id == id)) {
      setState(() => _status = 'Parameter id already exists.');
      return;
    }
    final definition = FamilyParameterDefinition(
      id: id,
      label: draft.label,
      kind: draft.kind,
      defaultValue: draft.defaultValue,
      minimum: draft.minimum,
      maximum: draft.maximum,
      formula: draft.formula,
    );
    _commit(
      _document.copyWith(
        parameters: <FamilyParameterDefinition>[..._document.parameters, definition],
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.copyWith(
              values: <String, Object?>{
                ...type.values,
                id: draft.defaultValue,
              },
            ),
        ],
      ),
      status: '${definition.label} parameter added',
    );
  }

  Future<void> _editParameter(FamilyParameterDefinition parameter) async {
    final draft = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => _ParameterDialog(
        parameter: parameter,
        lockKind: _coreDimension(parameter.id),
      ),
    );
    if (!mounted || draft == null) return;
    final replacement = FamilyParameterDefinition(
      id: parameter.id,
      label: draft.label,
      kind: _coreDimension(parameter.id)
          ? FamilyParameterKind.length
          : draft.kind,
      defaultValue: draft.defaultValue,
      minimum: draft.minimum,
      maximum: draft.maximum,
      formula: draft.formula,
    );
    final types = <FamilyTypeDefinition>[];
    for (final type in _document.types) {
      final raw = type.values[parameter.id] ?? replacement.defaultValue;
      final coerced = _coerce(replacement.kind, raw);
      types.add(
        type.copyWith(
          values: <String, Object?>{
            ...type.values,
            parameter.id: _parameterValueValid(replacement, coerced)
                ? coerced
                : replacement.defaultValue,
          },
        ),
      );
    }
    _commit(
      _document.copyWith(
        parameters: <FamilyParameterDefinition>[
          for (final current in _document.parameters)
            current.id == parameter.id ? replacement : current,
        ],
        types: types,
      ),
      status: '${replacement.label} updated',
    );
  }

  Future<void> _deleteParameter(FamilyParameterDefinition parameter) async {
    if (_coreDimension(parameter.id)) {
      setState(() => _status = 'Core dimensions cannot be removed.');
      return;
    }
    for (final feature in _document.features) {
      if (feature.parameters.values.any((value) => value == parameter.id)) {
        setState(() => _status =
            '${parameter.label} is used by ${feature.label.isEmpty ? feature.kind.name : feature.label}.');
        return;
      }
    }
    _commit(
      _document.copyWith(
        parameters: <FamilyParameterDefinition>[
          for (final item in _document.parameters)
            if (item.id != parameter.id) item,
        ],
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.copyWith(
              values: <String, Object?>{
                for (final entry in type.values.entries)
                  if (entry.key != parameter.id) entry.key: entry.value,
              },
            ),
        ],
      ),
      status: '${parameter.label} deleted',
    );
  }

  void _addProfile() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final sketch = FamilySketch(
      id: 'sketch-$stamp',
      name: 'Profile ${_document.sketches.length + 1}',
      plane: FamilySketchPlane.xy,
    );
    final feature = FamilyFeature(
      id: 'feature-$stamp',
      kind: FamilyFeatureKind.profile,
      label: sketch.name,
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{'profileId': sketch.id},
    );
    _selectedSketchId = sketch.id;
    _commit(
      _document.copyWith(
        sketches: <FamilySketch>[..._document.sketches, sketch],
        features: <FamilyFeature>[..._document.features, feature],
      ),
      status: 'Profile added · draw points in the sketch canvas',
      selectFeatureId: feature.id,
    );
  }

  void _addExtrude() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first.');
      return;
    }
    const parameterId = 'extrusionDepth';
    var document = _document;
    if (!document.parameters.any((item) => item.id == parameterId)) {
      const definition = FamilyParameterDefinition(
        id: parameterId,
        label: 'Extrusion depth',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.01,
      );
      document = document.copyWith(
        parameters: <FamilyParameterDefinition>[...document.parameters, definition],
        types: <FamilyTypeDefinition>[
          for (final type in document.types)
            type.copyWith(
              values: <String, Object?>{...type.values, parameterId: 1.0},
            ),
        ],
      );
    }
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.extrude,
      label: 'Extrude ${sketch.name}',
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{
        'profileId': sketch.id,
        'depth': parameterId,
      },
    );
    _commit(
      document.copyWith(
        features: <FamilyFeature>[...document.features, feature],
      ),
      status: 'Extrude added · select it below to edit depth/profile',
      selectFeatureId: feature.id,
    );
  }

  void _addRevolve() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first.');
      return;
    }
    const parameterId = 'revolveAngle';
    var document = _document;
    if (!document.parameters.any((item) => item.id == parameterId)) {
      const definition = FamilyParameterDefinition(
        id: parameterId,
        label: 'Revolve angle',
        kind: FamilyParameterKind.angle,
        defaultValue: 360.0,
        minimum: 1.0,
        maximum: 360.0,
      );
      document = document.copyWith(
        parameters: <FamilyParameterDefinition>[...document.parameters, definition],
        types: <FamilyTypeDefinition>[
          for (final type in document.types)
            type.copyWith(
              values: <String, Object?>{...type.values, parameterId: 360.0},
            ),
        ],
      );
    }
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.revolve,
      label: 'Revolve ${sketch.name}',
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{
        'profileId': sketch.id,
        'angle': parameterId,
      },
    );
    _commit(
      document.copyWith(
        features: <FamilyFeature>[...document.features, feature],
      ),
      status: 'Revolve added · select it below to edit angle/profile',
      selectFeatureId: feature.id,
    );
  }

  void _addBoolean(FamilyFeatureKind kind) {
    final solids = _document.features.where(_solidFeature).toList();
    if (solids.length < 2) {
      setState(() => _status = 'Create two solids before a Boolean.');
      return;
    }
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      label: kind == FamilyFeatureKind.booleanUnion
          ? 'Union solids'
          : 'Subtract solids',
      inputs: <String>[solids[solids.length - 2].id, solids.last.id],
      parameters: <String, Object?>{'operation': kind.name},
    );
    _commit(
      _document.copyWith(
        features: <FamilyFeature>[..._document.features, feature],
      ),
      status: 'Boolean added · edit operands or swap subtract order below',
      selectFeatureId: feature.id,
    );
  }

  void _addTransform() {
    final solids = _document.features.where(_solidFeature).toList();
    if (solids.isEmpty) {
      setState(() => _status = 'Create a solid before Transform.');
      return;
    }
    final source = solids.last;
    final feature = FamilyFeature(
      id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.transform,
      label: 'Transform ${source.label.isEmpty ? source.kind.name : source.label}',
      inputs: <String>[source.id],
      parameters: const <String, Object?>{
        'translationX': 0.0,
        'translationY': 0.0,
        'translationZ': 0.0,
        'rotationZ': 0.0,
        'scale': 1.0,
      },
    );
    _commit(
      _document.copyWith(
        features: <FamilyFeature>[..._document.features, feature],
      ),
      status: 'Transform added · edit X/Y/Z, rotation and scale below',
      selectFeatureId: feature.id,
    );
  }

  Future<void> _addNested() async {
    final feature = await FamilyNestedFeatureDialog.show(
      context,
      parent: _document,
    );
    if (!mounted || feature == null) return;
    _commit(
      _document.copyWith(
        features: <FamilyFeature>[..._document.features, feature],
      ),
      status: '${feature.label} nested family added',
      selectFeatureId: feature.id,
    );
  }

  Future<void> _importMesh() async {
    if (_dirty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace current family?'),
          content: const Text(
            'GLB/glTF import starts a new freeform family. Save current changes first if needed.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    final scale = await FamilyImportUnitsDialog.show(context);
    if (!mounted || scale == null) return;
    setState(() => _status = 'Choose a Blender GLB/glTF file...');
    try {
      final imported = await FamilyMeshImporter.pickGltf(unitScale: scale);
      if (!mounted || imported == null) return;
      final validation = FamilyDocumentValidator.validate(imported.document);
      if (!validation.isValid) {
        throw FormatException(validation.errors.join('; '));
      }
      _undo.add(_document);
      _redo.clear();
      _assetPath = null;
      _selectedTypeId = imported.document.types.first.id;
      _selectedSketchId = null;
      _selectedFeatureId = imported.document.features.last.id;
      _name.text = imported.document.name;
      _description.text = imported.document.description;
      _setDocument(
        imported.document,
        dirty: true,
        status:
            'Imported ${imported.vertexCount} vertices · ${imported.faceCount} faces · $scale m/unit',
      );
    } catch (error) {
      if (mounted) setState(() => _status = 'Import failed: $error');
    }
  }

  void _updateSketch(FamilySketch next) {
    _commit(
      _document.copyWith(
        sketches: <FamilySketch>[
          for (final sketch in _document.sketches)
            sketch.id == next.id ? next : sketch,
        ],
      ),
      status: 'Profile updated',
    );
  }

  void _addSketchPoint(FamilySketchPoint point) {
    final sketch = _selectedSketch;
    if (sketch == null || sketch.closed) return;
    _updateSketch(
      sketch.copyWith(points: <FamilySketchPoint>[...sketch.points, point]),
    );
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
      setState(() => _status = 'A profile needs at least 3 points.');
      return;
    }
    _updateSketch(sketch.copyWith(closed: !sketch.closed));
  }

  void _clearSketch() {
    final sketch = _selectedSketch;
    if (sketch == null) return;
    _commit(
      _document.copyWith(
        sketches: <FamilySketch>[
          for (final current in _document.sketches)
            current.id == sketch.id
                ? sketch.copyWith(
                    points: const <FamilySketchPoint>[],
                    closed: false,
                  )
                : current,
        ],
        constraints: <FamilySketchConstraint>[
          for (final constraint in _document.constraints)
            if (constraint.sketchId != sketch.id) constraint,
        ],
      ),
      status: 'Profile cleared · point constraints removed',
    );
  }

  Future<void> _preflightDependencies(FamilyDocument candidate) async {
    if (!candidate.features.any(
      (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
    )) {
      return;
    }
    final assets = await FamilyFileStore.listStored();
    final available = <FamilyDocument>[
      candidate,
      for (final asset in assets)
        if (asset.document.id != candidate.id) asset.document,
    ];
    for (final type in candidate.types) {
      FamilyDependencyResolver.resolve(
        candidate,
        type,
        availableDocuments: available,
      );
    }
  }

  FamilyDocument _liveDocument() {
    final name = _name.text.trim();
    return _document.copyWith(
      name: name.isEmpty ? _document.name : name,
      description: _description.text.trim(),
    );
  }

  Future<bool> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final candidate = _liveDocument();
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      _setDocument(
        candidate,
        dirty: true,
        status: validation.errors.first,
      );
      return false;
    }
    setState(() => _status = 'Saving family...');
    try {
      await _preflightDependencies(candidate);
      final path = _assetPath == null
          ? await FamilyFileStore.save(candidate)
          : await FamilyFileStore.saveAsset(
              candidate,
              existingPath: _assetPath!,
            );
      if (!mounted || path == null) return false;
      _assetPath = path;
      _setDocument(
        candidate,
        dirty: false,
        status: 'Saved: ${path.split('/').last}',
      );
      return true;
    } catch (error) {
      if (mounted) setState(() => _status = 'Save failed: $error');
      return false;
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved family'),
        content: const Text('Save this family before leaving?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_CloseChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_CloseChoice.save),
            child: const Text('Save & close'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _CloseChoice.save) {
      if (await _save() && mounted) Navigator.of(context).pop();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<FamilyEvaluatedMesh> _nestedMesh(FamilyTypeDefinition type) {
    final key = '${type.id}\u001f${_document.toJsonText()}';
    if (_nestedPreview == null || _nestedPreviewKey != key) {
      _nestedPreviewKey = key;
      _nestedPreview = () async {
        final resolved = await FamilyDependencyResolver.resolveFromLibrary(
          _document,
          type,
        );
        return FamilyGeometryEvaluator.evaluateMesh(resolved, type);
      }();
    }
    return _nestedPreview!;
  }

  @override
  Widget build(BuildContext context) {
    final type = _selectedType;
    final sketch = _solvedSketch;
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close family',
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.initialAsset == null
              ? 'Family Editor'
              : 'Edit ${_document.name}'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Undo',
              onPressed: _undo.isEmpty ? null : _undoChange,
              icon: const Icon(Icons.undo_outlined),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _redo.isEmpty ? null : _redoChange,
              icon: const Icon(Icons.redo_outlined),
            ),
            const SizedBox(width: 8),
            SegmentedButton<_EditorMode>(
              segments: const <ButtonSegment<_EditorMode>>[
                ButtonSegment(
                  value: _EditorMode.simple,
                  icon: Icon(Icons.tune_outlined),
                  label: Text('Simple'),
                ),
                ButtonSegment(
                  value: _EditorMode.advanced,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('Advanced'),
                ),
              ],
              selected: <_EditorMode>{_mode},
              onSelectionChanged: (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_dirty ? 'Save' : 'Saved'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final editor = _editorPanel(context);
              final preview = _hasNested
                  ? FutureBuilder<FamilyEvaluatedMesh>(
                      future: _nestedMesh(type),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return _previewPanel(
                            context,
                            snapshot.data!,
                            sketch,
                          );
                        }
                        if (snapshot.hasError) {
                          return _previewError(context, snapshot.error);
                        }
                        return const Card(
                          margin: EdgeInsets.zero,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    )
                  : _previewPanel(
                      context,
                      FamilyGeometryEvaluator.evaluateMesh(_document, type),
                      sketch,
                    );
              if (compact) {
                return ListView(
                  padding: const EdgeInsets.all(14),
                  children: <Widget>[
                    editor,
                    const SizedBox(height: 14),
                    SizedBox(height: sketch == null ? 430 : 760, child: preview),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 500,
                    child: SingleChildScrollView(child: editor),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: preview,
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

  Widget _editorPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_status != null) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_status!),
            ),
            const SizedBox(height: 10),
          ],
          _section(
            context,
            title: 'Family',
            subtitle: 'Reusable identity and category',
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Family name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) {
                    final value = raw.trim();
                    if (value.isNotEmpty && value != _document.name) {
                      _replaceDraft(_document.copyWith(name: value));
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<FamilyCategory>(
                  initialValue: _document.category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<FamilyCategory>>[
                    for (final category in FamilyCategory.values)
                      DropdownMenuItem<FamilyCategory>(
                        value: category,
                        child: Text(_category(category)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _commit(
                        _document.copyWith(category: value),
                        status: 'Category changed',
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) => _replaceDraft(
                    _document.copyWith(description: raw.trim()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _section(
            context,
            title: 'Family types',
            subtitle: '${_document.types.length} reusable configuration${_document.types.length == 1 ? '' : 's'}',
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey<String?>(_selectedTypeId),
                        initialValue: _selectedTypeId,
                        decoration: const InputDecoration(
                          labelText: 'Selected type',
                          border: OutlineInputBorder(),
                        ),
                        items: <DropdownMenuItem<String>>[
                          for (final type in _document.types)
                            DropdownMenuItem<String>(
                              value: type.id,
                              child: Text(type.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedTypeId = value;
                              _nestedPreview = null;
                              _nestedPreviewKey = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Duplicate type',
                      onPressed: _duplicateType,
                      icon: const Icon(Icons.content_copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Rename type',
                      onPressed: _renameType,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete type',
                      onPressed: _document.types.length <= 1 ? null : _deleteType,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final parameter in _orderedParameters(_document.parameters))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ParameterValueEditor(
                      key: ValueKey<String>(
                        '${_selectedType.id}:${parameter.id}:${parameter.formula}',
                      ),
                      parameter: parameter,
                      rawValue: _selectedType.valueFor(parameter),
                      effectiveValue: _effective(parameter),
                      onChanged: (value) => _updateTypeValue(parameter, value),
                    ),
                  ),
              ],
            ),
          ),
          if (_mode == _EditorMode.advanced) ...<Widget>[
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Geometry',
              subtitle: 'Create solids, then select/edit graph nodes below',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _importMesh,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Import GLB/glTF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addNested,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Nested family'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addProfile,
                        icon: const Icon(Icons.polyline_outlined),
                        label: const Text('Profile'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addExtrude,
                        icon: const Icon(Icons.height),
                        label: const Text('Extrude'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addRevolve,
                        icon: const Icon(Icons.rotate_right_outlined),
                        label: const Text('Revolve'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _addBoolean(FamilyFeatureKind.booleanUnion),
                        icon: const Icon(Icons.merge_type_outlined),
                        label: const Text('Union'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _addBoolean(FamilyFeatureKind.booleanSubtract),
                        icon: const Icon(Icons.call_split_outlined),
                        label: const Text('Subtract'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addTransform,
                        icon: const Icon(Icons.open_with_outlined),
                        label: const Text('Transform'),
                      ),
                    ],
                  ),
                  if (_document.sketches.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String?>(_selectedSketchId),
                      initialValue: _selectedSketchId,
                      decoration: const InputDecoration(
                        labelText: 'Active profile',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final sketch in _document.sketches)
                          DropdownMenuItem<String>(
                            value: sketch.id,
                            child: Text(
                              '${sketch.name}${sketch.closed ? '' : ' · open'}',
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedSketchId = value),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Feature graph',
              subtitle: 'Tap a node, then edit its real geometry inputs',
              child: FamilyFeatureWorkbench(
                document: _document,
                selectedFeatureId: _selectedFeatureId,
                onSelected: (id) => setState(() => _selectedFeatureId = id),
                onChanged: (next, status) => _commit(
                  next,
                  status: status,
                  selectFeatureId: _selectedFeatureId,
                ),
                onStatus: (message) => setState(() => _status = message),
              ),
            ),
            const SizedBox(height: 10),
            FamilyConstraintsPanel(
              document: _document,
              type: _selectedType,
              selectedSketchId: _selectedSketchId,
              onChanged: (next) =>
                  _commit(next, status: 'Constraints updated'),
              onStatus: (message) => setState(() => _status = message),
            ),
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Parameter definitions',
              subtitle: 'Limits, formulas and reusable type controls',
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _addParameter,
                      icon: const Icon(Icons.add),
                      label: const Text('Add parameter'),
                    ),
                  ),
                  for (final parameter in _orderedParameters(_document.parameters))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_parameterIcon(parameter.kind)),
                      title: Text(parameter.label),
                      subtitle: Text(
                        '${parameter.id} · ${parameter.kind.name}${parameter.hasFormula ? '\n= ${parameter.formula}' : ''}',
                      ),
                      isThreeLine: parameter.hasFormula,
                      trailing: Wrap(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Edit parameter',
                            onPressed: () => _editParameter(parameter),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete parameter',
                            onPressed: _coreDimension(parameter.id)
                                ? null
                                : () => _deleteParameter(parameter),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Quick content',
              subtitle: 'Fast authored furniture/equipment workflow',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Import GLB/glTF, choose source units and category, tune Family Type dimensions, orbit the preview, then save.',
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _importMesh,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import GLB/glTF'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewPanel(
    BuildContext context,
    FamilyEvaluatedMesh mesh,
    FamilySketch? sketch,
  ) {
    final colors = Theme.of(context).colorScheme;
    final model = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FamilyInteractivePreview(
              mesh: mesh,
              lineColor: colors.primary,
              fillColor: colors.primary.withValues(alpha: 0.19),
              background:
                  colors.surfaceContainerHighest.withValues(alpha: 0.30),
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _name.text.trim().isEmpty ? _document.name : _name.text.trim(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text('${_selectedType.name} · ${_category(_document.category)}'),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            child: IgnorePointer(
              child: Text(
                '${mesh.vertices.length} vertices · ${mesh.faces.length} faces${mesh.isApproximate ? ' · approximate' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
    if (_mode != _EditorMode.advanced || sketch == null) return model;
    return Column(
      children: <Widget>[
        Expanded(child: model),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${sketch.name} · ${sketch.points.length} points',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear profile',
                        onPressed: _clearSketch,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                      TextButton.icon(
                        onPressed: sketch.closed || sketch.points.length >= 3
                            ? _toggleSketchClosed
                            : null,
                        icon: Icon(
                          sketch.closed
                              ? Icons.lock_open_outlined
                              : Icons.check_circle_outline,
                        ),
                        label: Text(sketch.closed ? 'Reopen' : 'Close'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FamilySketchCanvas(
                    sketch: sketch,
                    onAddPoint: _addSketchPoint,
                    onMovePoint: _moveSketchPoint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewError(BuildContext context, Object? error) => Card(
        margin: EdgeInsets.zero,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.account_tree_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                const Text('Nested family preview unavailable'),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );

  Widget _section(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

final class _ParameterDraft {
  const _ParameterDraft({
    required this.label,
    required this.kind,
    required this.defaultValue,
    this.minimum,
    this.maximum,
    this.formula,
  });

  final String label;
  final FamilyParameterKind kind;
  final Object? defaultValue;
  final double? minimum;
  final double? maximum;
  final String? formula;
}

class _ParameterDialog extends StatefulWidget {
  const _ParameterDialog({this.parameter, this.lockKind = false});

  final FamilyParameterDefinition? parameter;
  final bool lockKind;

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  late final TextEditingController _label;
  late final TextEditingController _defaultValue;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _formula;
  late FamilyParameterKind _kind;

  @override
  void initState() {
    super.initState();
    final parameter = widget.parameter;
    _label = TextEditingController(text: parameter?.label ?? 'New parameter');
    _defaultValue =
        TextEditingController(text: '${parameter?.defaultValue ?? 1.0}');
    _minimum = TextEditingController(text: parameter?.minimum?.toString() ?? '');
    _maximum = TextEditingController(text: parameter?.maximum?.toString() ?? '');
    _formula = TextEditingController(text: parameter?.formula ?? '');
    _kind = parameter?.kind ?? FamilyParameterKind.number;
  }

  @override
  void dispose() {
    _label.dispose();
    _defaultValue.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _formula.dispose();
    super.dispose();
  }

  Object? _parseDefault() {
    switch (_kind) {
      case FamilyParameterKind.boolean:
        final raw = _defaultValue.text.trim().toLowerCase();
        if (<String>{'true', '1', 'yes'}.contains(raw)) return true;
        if (<String>{'false', '0', 'no'}.contains(raw)) return false;
        return null;
      case FamilyParameterKind.text:
      case FamilyParameterKind.material:
        final raw = _defaultValue.text.trim();
        return raw.isEmpty ? null : raw;
      case FamilyParameterKind.length:
      case FamilyParameterKind.number:
      case FamilyParameterKind.angle:
        return double.tryParse(_defaultValue.text.trim().replaceAll(',', '.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final numeric = _numericKind(_kind);
    return AlertDialog(
      title: Text(widget.parameter == null ? 'Add parameter' : 'Edit parameter'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<FamilyParameterKind>(
                initialValue: _kind,
                decoration: InputDecoration(
                  labelText: 'Kind',
                  border: const OutlineInputBorder(),
                  helperText: widget.lockKind
                      ? 'Core dimensions remain length parameters.'
                      : null,
                ),
                items: <DropdownMenuItem<FamilyParameterKind>>[
                  for (final kind in FamilyParameterKind.values)
                    DropdownMenuItem<FamilyParameterKind>(
                      value: kind,
                      child: Text(kind.name),
                    ),
                ],
                onChanged: widget.lockKind
                    ? null
                    : (value) {
                        if (value != null) setState(() => _kind = value);
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _defaultValue,
                decoration: const InputDecoration(
                  labelText: 'Default value',
                  border: OutlineInputBorder(),
                ),
              ),
              if (numeric) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _minimum,
                        decoration: const InputDecoration(
                          labelText: 'Minimum',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maximum,
                        decoration: const InputDecoration(
                          labelText: 'Maximum',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _formula,
                  decoration: const InputDecoration(
                    labelText: 'Formula (optional)',
                    hintText: 'width / 2  or  max(depth * 3, 2)',
                    border: OutlineInputBorder(),
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
          onPressed: () {
            final label = _label.text.trim();
            final defaultValue = _parseDefault();
            final minimum = _minimum.text.trim().isEmpty
                ? null
                : double.tryParse(_minimum.text.trim().replaceAll(',', '.'));
            final maximum = _maximum.text.trim().isEmpty
                ? null
                : double.tryParse(_maximum.text.trim().replaceAll(',', '.'));
            if (label.isEmpty || defaultValue == null) return;
            if (minimum != null && maximum != null && minimum > maximum) return;
            final formula = numeric ? _formula.text.trim() : '';
            Navigator.of(context).pop(
              _ParameterDraft(
                label: label,
                kind: _kind,
                defaultValue: defaultValue,
                minimum: numeric ? minimum : null,
                maximum: numeric ? maximum : null,
                formula: formula.isEmpty ? null : formula,
              ),
            );
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ParameterValueEditor extends StatefulWidget {
  const _ParameterValueEditor({
    super.key,
    required this.parameter,
    required this.rawValue,
    required this.effectiveValue,
    required this.onChanged,
  });

  final FamilyParameterDefinition parameter;
  final Object? rawValue;
  final Object? effectiveValue;
  final ValueChanged<Object?> onChanged;

  @override
  State<_ParameterValueEditor> createState() => _ParameterValueEditorState();
}

class _ParameterValueEditorState extends State<_ParameterValueEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display());
  }

  @override
  void didUpdateWidget(covariant _ParameterValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawValue != widget.rawValue ||
        oldWidget.parameter.formula != widget.parameter.formula) {
      final next = _display();
      if (_controller.text != next) _controller.text = next;
    }
  }

  String _display() =>
      '${widget.parameter.hasFormula ? widget.effectiveValue ?? '' : widget.rawValue ?? ''}';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parameter = widget.parameter;
    if (parameter.hasFormula) {
      return TextField(
        controller: _controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: parameter.label,
          helperText: '${parameter.id} = ${parameter.formula}',
          prefixIcon: const Icon(Icons.functions),
          suffixText: _suffix(parameter.kind),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }
    if (parameter.kind == FamilyParameterKind.boolean) {
      final value = widget.rawValue == true ||
          widget.rawValue.toString().toLowerCase() == 'true';
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(parameter.label),
        subtitle: Text(parameter.id),
        value: value,
        onChanged: widget.onChanged,
      );
    }
    final numeric = _numericKind(parameter.kind);
    return TextField(
      controller: _controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: parameter.label,
        helperText: parameter.id,
        suffixText: _suffix(parameter.kind),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (raw) {
        if (!numeric) {
          final value = raw.trim();
          if (value.isNotEmpty) widget.onChanged(value);
          return;
        }
        final value = double.tryParse(raw.trim().replaceAll(',', '.'));
        if (value != null && value.isFinite) widget.onChanged(value);
      },
    );
  }
}

bool _parameterValueValid(
  FamilyParameterDefinition parameter,
  Object? value,
) {
  if (value == null) return false;
  switch (parameter.kind) {
    case FamilyParameterKind.text:
    case FamilyParameterKind.material:
      return value is String && value.trim().isNotEmpty;
    case FamilyParameterKind.boolean:
      return value is bool;
    case FamilyParameterKind.length:
    case FamilyParameterKind.number:
    case FamilyParameterKind.angle:
      final number = value is num ? value.toDouble() : double.tryParse('$value');
      if (number == null || !number.isFinite) return false;
      if (parameter.minimum != null && number < parameter.minimum!) return false;
      if (parameter.maximum != null && number > parameter.maximum!) return false;
      if (parameter.kind == FamilyParameterKind.length && number <= 0.0) {
        return false;
      }
      return true;
  }
}

Object? _coerce(FamilyParameterKind kind, Object? raw) {
  switch (kind) {
    case FamilyParameterKind.text:
    case FamilyParameterKind.material:
      return raw?.toString() ?? '';
    case FamilyParameterKind.boolean:
      final text = raw.toString().toLowerCase();
      return raw == true || text == 'true' || text == '1' || text == 'yes';
    case FamilyParameterKind.length:
    case FamilyParameterKind.number:
    case FamilyParameterKind.angle:
      return raw is num ? raw.toDouble() : double.tryParse('$raw');
  }
}

String _safeId(String label) {
  final words = label
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '';
  final first = words.first.toLowerCase();
  final tail = words.skip(1).map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      );
  final id = <String>[first, ...tail].join();
  return RegExp(r'^[A-Za-z_]').hasMatch(id) ? id : 'p$id';
}

List<FamilyParameterDefinition> _orderedParameters(
  List<FamilyParameterDefinition> parameters,
) {
  const core = <String>['width', 'depth', 'height'];
  return <FamilyParameterDefinition>[
    for (final id in core)
      for (final parameter in parameters)
        if (parameter.id == id) parameter,
    for (final parameter in parameters)
      if (!core.contains(parameter.id)) parameter,
  ];
}

bool _coreDimension(String id) =>
    id == 'width' || id == 'depth' || id == 'height';

bool _numericKind(FamilyParameterKind kind) =>
    kind == FamilyParameterKind.length ||
    kind == FamilyParameterKind.number ||
    kind == FamilyParameterKind.angle;

bool _solidFeature(FamilyFeature feature) =>
    feature.kind == FamilyFeatureKind.box ||
    feature.kind == FamilyFeatureKind.extrude ||
    feature.kind == FamilyFeatureKind.revolve ||
    feature.kind == FamilyFeatureKind.booleanUnion ||
    feature.kind == FamilyFeatureKind.booleanSubtract ||
    feature.kind == FamilyFeatureKind.freeformMesh ||
    feature.kind == FamilyFeatureKind.transform ||
    feature.kind == FamilyFeatureKind.nestedFamily;

String? _suffix(FamilyParameterKind kind) => switch (kind) {
      FamilyParameterKind.length => 'm',
      FamilyParameterKind.angle => '°',
      _ => null,
    };

IconData _parameterIcon(FamilyParameterKind kind) => switch (kind) {
      FamilyParameterKind.length => Icons.straighten,
      FamilyParameterKind.number => Icons.numbers,
      FamilyParameterKind.angle => Icons.rotate_right_outlined,
      FamilyParameterKind.material => Icons.palette_outlined,
      FamilyParameterKind.text => Icons.text_fields,
      FamilyParameterKind.boolean => Icons.toggle_on_outlined,
    };

String _category(FamilyCategory category) => switch (category) {
      FamilyCategory.genericModel => 'Generic model',
      FamilyCategory.column => 'Column',
      FamilyCategory.door => 'Door',
      FamilyCategory.window => 'Window',
      FamilyCategory.wallSweep => 'Wall sweep',
      FamilyCategory.furniture => 'Furniture',
      FamilyCategory.casework => 'Casework',
      FamilyCategory.stair => 'Stair',
      FamilyCategory.structural => 'Structural',
    };
