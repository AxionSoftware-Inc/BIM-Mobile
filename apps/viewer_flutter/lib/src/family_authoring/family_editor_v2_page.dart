import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_constraint_solver.dart';
import 'family_constraints_panel.dart';
import 'family_dependency_resolver.dart';
import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_import_units_dialog.dart';
import 'family_mesh_importer.dart';
import 'family_nested_feature_dialog.dart';
import 'family_parameter_resolver.dart';
import 'family_sketch_canvas.dart';
import 'family_validation.dart';

/// Production Family Editor.
///
/// The editor owns reusable family content only. It never mutates a project
/// scene directly. New families and existing library assets use the same page,
/// which prevents a second, weaker edit path from drifting away from creation.
class FamilyEditorV2Page extends StatefulWidget {
  const FamilyEditorV2Page({
    super.key,
    this.initialAsset,
  });

  final FamilyAssetFile? initialAsset;

  @override
  State<FamilyEditorV2Page> createState() => _FamilyEditorV2PageState();
}

enum _FamilyEditorMode { simple, advanced }
enum _CloseAction { save, discard }

class _FamilyEditorV2PageState extends State<FamilyEditorV2Page> {
  late FamilyDocument _document;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _assetPath;
  String? _selectedTypeId;
  String? _selectedSketchId;
  _FamilyEditorMode _mode = _FamilyEditorMode.simple;
  String? _status;
  bool _dirty = false;
  final List<FamilyDocument> _undo = <FamilyDocument>[];
  final List<FamilyDocument> _redo = <FamilyDocument>[];
  String? _nestedPreviewKey;
  Future<FamilyEvaluatedMesh>? _nestedPreviewFuture;

  @override
  void initState() {
    super.initState();
    final asset = widget.initialAsset;
    _document = asset?.document ?? FamilyDocument.starter();
    _assetPath = asset?.path;
    _selectedTypeId = asset?.preferredTypeId ?? _document.types.first.id;
    _selectedSketchId =
        _document.sketches.isEmpty ? null : _document.sketches.first.id;
    _nameController = TextEditingController(text: _document.name);
    _descriptionController = TextEditingController(text: _document.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  FamilyTypeDefinition get _selectedType => _document.types.firstWhere(
        (type) => type.id == _selectedTypeId,
        orElse: () => _document.types.first,
      );

  bool get _hasNestedFamily => _document.features.any(
        (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
      );

  FamilySketch? get _selectedSketch {
    final id = _selectedSketchId;
    if (id == null) return null;
    for (final sketch in _document.sketches) {
      if (sketch.id == id) return sketch;
    }
    return null;
  }

  FamilySketch? get _solvedSelectedSketch {
    final sketch = _selectedSketch;
    if (sketch == null) return null;
    try {
      return FamilyConstraintSolver.solveSketch(
        _document,
        _selectedType,
        sketch,
      ).sketch;
    } catch (_) {
      // The panel/validator surfaces the constraint error. Keep the raw sketch
      // visible while the user fixes an incomplete or over-constrained edit.
      return sketch;
    }
  }

  void _commit(FamilyDocument next, {String? status}) {
    if (identical(next, _document)) return;
    _undo.add(_document);
    _redo.clear();
    _setDocument(next, dirty: true, status: status);
  }

  /// Live text/number fields use this path so a user can type naturally
  /// without creating one undo snapshot per keystroke. Structural operations
  /// (add/delete/type/feature/sketch) still use [_commit].
  void _replaceDraft(FamilyDocument next, {String? status}) {
    _redo.clear();
    _setDocument(next, dirty: true, status: status);
  }

  void _setDocument(
    FamilyDocument next, {
    required bool dirty,
    String? status,
    bool syncMetadataControllers = false,
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
      if (syncMetadataControllers) {
        _nameController.text = _document.name;
        _descriptionController.text = _document.description;
      }
    });
  }

  void _restore(FamilyDocument next) {
    _setDocument(
      next,
      dirty: true,
      syncMetadataControllers: true,
    );
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    _redo.add(_document);
    _restore(_undo.removeLast());
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    _undo.add(_document);
    _restore(_redo.removeLast());
  }

  FamilyDocument _withLiveMetadata(FamilyDocument source) {
    final name = _nameController.text.trim();
    return source.copyWith(
      name: name.isEmpty ? source.name : name,
      description: _descriptionController.text.trim(),
    );
  }

  Object? _effectiveValue(FamilyParameterDefinition parameter) {
    try {
      return FamilyParameterResolver(_document, _selectedType).resolve(parameter);
    } catch (_) {
      return _selectedType.valueFor(parameter);
    }
  }

  void _updateTypeValueDraft(
    FamilyParameterDefinition parameter,
    Object? value,
  ) {
    if (parameter.hasFormula) return;
    if (!_validParameterValue(parameter, value)) return;
    final selected = _selectedType;
    final current = selected.values[parameter.id];
    if (current == value) return;
    final values = <String, Object?>{...selected.values, parameter.id: value};
    _replaceDraft(
      _document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.id == selected.id ? type.copyWith(values: values) : type,
        ],
      ),
    );
  }

  bool _typeNameExists(String name, {String? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return _document.types.any(
      (type) => type.id != exceptId && type.name.trim().toLowerCase() == normalized,
    );
  }

  Future<void> _addType() async {
    final name = await _askText(
      title: 'Duplicate family type',
      label: 'Type name',
      initialValue: '${_selectedType.name} Copy',
      actionLabel: 'Duplicate',
    );
    if (!mounted || name == null) return;
    if (_typeNameExists(name)) {
      setState(() => _status = 'A family type named "$name" already exists.');
      return;
    }
    final id = 'type-${DateTime.now().microsecondsSinceEpoch}';
    final source = _selectedType;
    final next = FamilyTypeDefinition(
      id: id,
      name: name,
      values: Map<String, Object?>.from(source.values),
    );
    _selectedTypeId = id;
    _commit(
      _document.copyWith(types: <FamilyTypeDefinition>[..._document.types, next]),
      status: 'Type duplicated',
    );
  }

  Future<void> _renameType() async {
    final selected = _selectedType;
    final name = await _askText(
      title: 'Rename family type',
      label: 'Type name',
      initialValue: selected.name,
      actionLabel: 'Rename',
    );
    if (!mounted || name == null || name == selected.name) return;
    if (_typeNameExists(name, exceptId: selected.id)) {
      setState(() => _status = 'A family type named "$name" already exists.');
      return;
    }
    _commit(
      _document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.id == selected.id ? type.copyWith(name: name) : type,
        ],
      ),
      status: 'Type renamed',
    );
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String initialValue,
    required String actionLabel,
  }) async {
    final controller = TextEditingController(text: initialValue);
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
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.of(dialogContext).pop(trimmed);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(dialogContext).pop(trimmed);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteType() async {
    if (_document.types.length <= 1) {
      setState(() => _status = 'A family must keep at least one type');
      return;
    }
    final selected = _selectedType;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${selected.name}?'),
        content: const Text(
          'This removes the type from this family. Existing deployed project instances keep their stored values, but should be migrated before replacing a shared asset.',
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
    if (!mounted || remove != true) return;
    final remaining = <FamilyTypeDefinition>[
      for (final type in _document.types)
        if (type.id != selected.id) type,
    ];
    _selectedTypeId = remaining.first.id;
    _commit(_document.copyWith(types: remaining), status: 'Type deleted');
  }

  Future<void> _addParameter() async {
    final result = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => const _ParameterDialog(),
    );
    if (!mounted || result == null) return;
    final id = _safeParameterId(result.label);
    if (id.isEmpty || _document.parameters.any((parameter) => parameter.id == id)) {
      setState(() => _status = 'Parameter id already exists');
      return;
    }
    final definition = FamilyParameterDefinition(
      id: id,
      label: result.label.trim(),
      kind: result.kind,
      defaultValue: result.defaultValue,
      minimum: result.minimum,
      maximum: result.maximum,
      formula: result.formula,
    );
    final candidate = _document.copyWith(
      parameters: <FamilyParameterDefinition>[..._document.parameters, definition],
      types: <FamilyTypeDefinition>[
        for (final type in _document.types)
          type.copyWith(values: <String, Object?>{
            ...type.values,
            definition.id: definition.defaultValue,
          }),
      ],
    );
    if (!_acceptCandidate(candidate)) return;
    _commit(candidate, status: '${definition.label} parameter added');
  }

  Future<void> _editParameter(FamilyParameterDefinition parameter) async {
    final core = _isCoreDimension(parameter.id);
    final result = await showDialog<_ParameterDraft>(
      context: context,
      builder: (_) => _ParameterDialog(
        parameter: parameter,
        lockKind: core,
      ),
    );
    if (!mounted || result == null) return;
    final replacement = FamilyParameterDefinition(
      id: parameter.id,
      label: result.label.trim(),
      kind: core ? FamilyParameterKind.length : result.kind,
      defaultValue: result.defaultValue,
      minimum: result.minimum,
      maximum: result.maximum,
      formula: result.formula,
    );
    final nextTypes = <FamilyTypeDefinition>[];
    for (final type in _document.types) {
      final raw = type.values[parameter.id] ?? replacement.defaultValue;
      final normalized = _coerceValue(replacement.kind, raw);
      nextTypes.add(
        type.copyWith(values: <String, Object?>{
          ...type.values,
          parameter.id: _validParameterValue(replacement, normalized)
              ? normalized
              : replacement.defaultValue,
        }),
      );
    }
    final candidate = _document.copyWith(
      parameters: <FamilyParameterDefinition>[
        for (final current in _document.parameters)
          current.id == parameter.id ? replacement : current,
      ],
      types: nextTypes,
    );
    if (!_acceptCandidate(candidate)) return;
    _commit(candidate, status: '${replacement.label} updated');
  }

  Future<void> _deleteParameter(FamilyParameterDefinition parameter) async {
    if (_isCoreDimension(parameter.id)) {
      setState(() => _status = 'Core dimensions cannot be removed');
      return;
    }
    if (_parameterUsedByFeature(parameter.id)) {
      setState(() => _status =
          '${parameter.label} is used by the feature graph and cannot be removed');
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${parameter.label}?'),
        content: const Text(
          'The parameter and its value will be removed from every family type.',
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
    if (!mounted || remove != true) return;
    final candidate = _document.copyWith(
      parameters: <FamilyParameterDefinition>[
        for (final current in _document.parameters)
          if (current.id != parameter.id) current,
      ],
      types: <FamilyTypeDefinition>[
        for (final type in _document.types)
          type.copyWith(values: <String, Object?>{
            for (final entry in type.values.entries)
              if (entry.key != parameter.id) entry.key: entry.value,
          }),
      ],
    );
    if (!_acceptCandidate(candidate)) return;
    _commit(candidate, status: '${parameter.label} deleted');
  }

  bool _acceptCandidate(FamilyDocument candidate) {
    final validation = FamilyDocumentValidator.validate(candidate);
    if (validation.isValid) return true;
    setState(() => _status = validation.errors.first);
    return false;
  }

  bool _parameterUsedByFeature(String id) {
    for (final feature in _document.features) {
      for (final value in feature.parameters.values) {
        if (value == id) return true;
      }
    }
    return false;
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
    );
  }

  void _addExtrude() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first');
      return;
    }
    const parameterId = 'extrusionDepth';
    var document = _document;
    if (!document.parameters.any((parameter) => parameter.id == parameterId)) {
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
            type.copyWith(values: <String, Object?>{
              ...type.values,
              parameterId: 1.0,
            }),
        ],
      );
    }
    _commit(
      document.copyWith(
        features: <FamilyFeature>[
          ...document.features,
          FamilyFeature(
            id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
            kind: FamilyFeatureKind.extrude,
            label: 'Extrude ${sketch.name}',
            inputs: <String>[sketch.id],
            parameters: <String, Object?>{
              'profileId': sketch.id,
              'depth': parameterId,
            },
          ),
        ],
      ),
    );
  }

  void _addRevolve() {
    final sketch = _selectedSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close a profile with at least 3 points first');
      return;
    }
    const parameterId = 'revolveAngle';
    var document = _document;
    if (!document.parameters.any((parameter) => parameter.id == parameterId)) {
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
            type.copyWith(values: <String, Object?>{
              ...type.values,
              parameterId: 360.0,
            }),
        ],
      );
    }
    _commit(
      document.copyWith(
        features: <FamilyFeature>[
          ...document.features,
          FamilyFeature(
            id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
            kind: FamilyFeatureKind.revolve,
            label: 'Revolve ${sketch.name}',
            inputs: <String>[sketch.id],
            parameters: <String, Object?>{
              'profileId': sketch.id,
              'angle': parameterId,
            },
          ),
        ],
      ),
    );
  }

  void _addBoolean(FamilyFeatureKind kind) {
    final solids = _document.features.where(_isSolidFeature).toList();
    if (solids.length < 2) {
      setState(() => _status = 'Create two solid features before a boolean');
      return;
    }
    _commit(
      _document.copyWith(
        features: <FamilyFeature>[
          ..._document.features,
          FamilyFeature(
            id: 'feature-${DateTime.now().microsecondsSinceEpoch}',
            kind: kind,
            label: kind == FamilyFeatureKind.booleanUnion
                ? 'Union solids'
                : 'Subtract solids',
            inputs: <String>[solids[solids.length - 2].id, solids.last.id],
            parameters: <String, Object?>{'operation': kind.name},
          ),
        ],
      ),
      status:
          'Boolean feature added · closed manifold solids use exact CSG',
    );
  }

  void _addTransform() {
    final solids = _document.features.where(_isSolidFeature).toList();
    if (solids.isEmpty) {
      setState(() => _status = 'Create a solid before adding a transform');
      return;
    }
    final source = solids.last;
    _commit(
      _document.copyWith(
        features: <FamilyFeature>[
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
        ],
      ),
    );
  }

  Future<void> _addNestedFamily() async {
    final feature = await FamilyNestedFeatureDialog.show(
      context,
      parent: _document,
    );
    if (!mounted || feature == null) return;
    final candidate = _document.copyWith(
      features: <FamilyFeature>[..._document.features, feature],
    );
    if (!_acceptCandidate(candidate)) return;
    _commit(candidate, status: '${feature.label} nested family added');
  }

  Future<void> _importMesh() async {
    if (_dirty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace current family?'),
          content: const Text(
            'Importing a GLB/glTF model starts a new freeform-mesh family. Save current changes first if you need them.',
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
    final unitScale = await FamilyImportUnitsDialog.show(context);
    if (!mounted || unitScale == null) return;
    setState(() => _status = 'Choose a Blender GLB/glTF file...');
    try {
      final imported = await FamilyMeshImporter.pickGltf(unitScale: unitScale);
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
      _nameController.text = imported.document.name;
      _descriptionController.text = imported.document.description;
      _setDocument(
        imported.document,
        dirty: true,
        status:
            'Imported ${imported.vertexCount} vertices · ${imported.faceCount} faces · scale $unitScale m/unit',
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
      setState(() => _status = 'A profile needs at least 3 points');
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

  Future<bool> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final candidate = _withLiveMetadata(_document);
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

  Future<void> _requestClose() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<_CloseAction>(
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
            onPressed: () => Navigator.of(dialogContext).pop(_CloseAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_CloseAction.save),
            child: const Text('Save & close'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == _CloseAction.save) {
      if (await _save() && mounted) Navigator.of(context).pop();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<FamilyEvaluatedMesh> _nestedPreviewFor(
    FamilyTypeDefinition type,
  ) {
    final key = '${type.id}\u001f${_document.toJsonText()}';
    if (_nestedPreviewFuture == null || _nestedPreviewKey != key) {
      _nestedPreviewKey = key;
      _nestedPreviewFuture = () async {
        final resolved = await FamilyDependencyResolver.resolveFromLibrary(
          _document,
          type,
        );
        return FamilyGeometryEvaluator.evaluateMesh(resolved, type);
      }();
    }
    return _nestedPreviewFuture!;
  }

  Widget _buildNestedPreview(
    BuildContext context,
    FamilyTypeDefinition type,
    FamilySketch? sketch,
  ) {
    return FutureBuilder<FamilyEvaluatedMesh>(
      future: _nestedPreviewFor(type),
      builder: (context, snapshot) {
        final mesh = snapshot.data;
        if (mesh != null) return _buildPreview(context, mesh, sketch);
        if (snapshot.hasError) {
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.account_tree_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  const Text('Nested family preview unavailable'),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }
        return const Card(
          margin: EdgeInsets.zero,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = _selectedType;
    final sketch = _solvedSelectedSketch;
    final directMesh = _hasNestedFamily
        ? null
        : FamilyGeometryEvaluator.evaluateMesh(_document, type);
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initialAsset == null ? 'Family Editor' : 'Edit Family'),
          leading: IconButton(
            tooltip: 'Close family',
            onPressed: _requestClose,
            icon: const Icon(Icons.close),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Undo structural change',
              onPressed: _undo.isEmpty ? null : _undoChange,
              icon: const Icon(Icons.undo_outlined),
            ),
            IconButton(
              tooltip: 'Redo structural change',
              onPressed: _redo.isEmpty ? null : _redoChange,
              icon: const Icon(Icons.redo_outlined),
            ),
            const SizedBox(width: 8),
            SegmentedButton<_FamilyEditorMode>(
              segments: const <ButtonSegment<_FamilyEditorMode>>[
                ButtonSegment(
                  value: _FamilyEditorMode.simple,
                  icon: Icon(Icons.tune_outlined),
                  label: Text('Simple'),
                ),
                ButtonSegment(
                  value: _FamilyEditorMode.advanced,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('Advanced'),
                ),
              ],
              selected: <_FamilyEditorMode>{_mode},
              onSelectionChanged: (selection) {
                setState(() => _mode = selection.first);
              },
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
              final editor = _buildEditorPanel(context);
              final preview = directMesh == null
                  ? _buildNestedPreview(context, type, sketch)
                  : _buildPreview(context, directMesh, sketch);
              if (compact) {
                return ListView(
                  padding: const EdgeInsets.all(14),
                  children: <Widget>[
                    editor,
                    const SizedBox(height: 14),
                    SizedBox(height: sketch == null ? 330 : 650, child: preview),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 460,
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

  Widget _buildEditorPanel(BuildContext context) {
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
                color: colors.secondaryContainer.withValues(alpha: 0.5),
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
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Family name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final name = value.trim();
                    if (name.isNotEmpty && name != _document.name) {
                      _replaceDraft(_document.copyWith(name: name));
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
                  items: FamilyCategory.values
                      .map(
                        (category) => DropdownMenuItem<FamilyCategory>(
                          value: category,
                          child: Text(_categoryLabel(category)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (category) {
                    if (category != null) {
                      _commit(_document.copyWith(category: category));
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    if (value.trim() != _document.description) {
                      _replaceDraft(
                        _document.copyWith(description: value.trim()),
                      );
                    }
                  },
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
                        items: _document.types
                            .map(
                              (type) => DropdownMenuItem<String>(
                                value: type.id,
                                child: Text(type.name),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (id) {
                          if (id != null) setState(() => _selectedTypeId = id);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Duplicate type',
                      onPressed: _addType,
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
                      effectiveValue: _effectiveValue(parameter),
                      onChanged: (value) =>
                          _updateTypeValueDraft(parameter, value),
                    ),
                  ),
              ],
            ),
          ),
          if (_mode == _FamilyEditorMode.advanced) ...<Widget>[
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Parameter definitions',
              subtitle: 'Types, limits and deterministic formulas',
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
                  const SizedBox(height: 6),
                  for (final parameter in _orderedParameters(_document.parameters))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_parameterIcon(parameter.kind)),
                      title: Text(parameter.label),
                      subtitle: Text(
                        '${parameter.id} · ${parameter.kind.name}${_rangeText(parameter)}${parameter.hasFormula ? '\n= ${parameter.formula}' : ''}',
                      ),
                      isThreeLine: parameter.hasFormula,
                      trailing: Wrap(
                        spacing: 2,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Edit definition',
                            onPressed: () => _editParameter(parameter),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete parameter',
                            onPressed: _isCoreDimension(parameter.id)
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
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Geometry',
              subtitle: 'Profile, solids, nested content and imported mesh',
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
                        onPressed: _addNestedFamily,
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
                      items: _document.sketches
                          .map(
                            (sketch) => DropdownMenuItem<String>(
                              value: sketch.id,
                              child: Text(
                                '${sketch.name}${sketch.closed ? '' : ' · open'}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (id) => setState(() => _selectedSketchId = id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            FamilyConstraintsPanel(
              document: _document,
              type: _selectedType,
              selectedSketchId: _selectedSketchId,
              onChanged: (next) => _commit(next, status: 'Constraints updated'),
              onStatus: (message) {
                if (mounted) setState(() => _status = message);
              },
            ),
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Feature graph',
              subtitle: '${_document.features.length} nodes',
              child: Column(
                children: <Widget>[
                  for (final feature in _document.features)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_featureIcon(feature.kind)),
                      title: Text(_featureLabel(feature)),
                      subtitle: Text(_featureSummary(feature)),
                      trailing: feature.kind == FamilyFeatureKind.booleanUnion ||
                              feature.kind == FamilyFeatureKind.booleanSubtract
                          ? const Tooltip(
                              message:
                                  'Closed manifold inputs use exact CSG; open/non-manifold inputs stay approximate.',
                              child: Icon(Icons.check_circle_outline),
                            )
                          : const Icon(Icons.check_circle_outline),
                    ),
                ],
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 10),
            _section(
              context,
              title: 'Quick content',
              subtitle: 'Fast path for authored furniture and equipment',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Model in Blender, import GLB/glTF, choose source units, category and type dimensions, then save. The reusable asset is data-driven; no Dart change or app rebuild is required.',
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

  Widget _buildPreview(
    BuildContext context,
    FamilyEvaluatedMesh mesh,
    FamilySketch? sketch,
  ) {
    final colors = Theme.of(context).colorScheme;
    final modelPreview = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _FamilyV2PreviewPainter(
                mesh: mesh,
                lineColor: colors.primary,
                fillColor: colors.primary.withValues(alpha: 0.13),
                background: colors.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _nameController.text.trim().isEmpty
                      ? _document.name
                      : _nameController.text.trim(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text('${_selectedType.name} · ${_categoryLabel(_document.category)}'),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 12,
            child: Text(
              '${mesh.vertices.length} vertices · ${mesh.faces.length} faces${mesh.isApproximate ? ' · approximate preview' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
    if (_mode != _FamilyEditorMode.advanced || sketch == null) {
      return modelPreview;
    }
    return Column(
      children: <Widget>[
        Expanded(child: modelPreview),
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

  Widget _section(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
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
  const _ParameterDialog({
    this.parameter,
    this.lockKind = false,
  });

  final FamilyParameterDefinition? parameter;
  final bool lockKind;

  @override
  State<_ParameterDialog> createState() => _ParameterDialogState();
}

class _ParameterDialogState extends State<_ParameterDialog> {
  late final TextEditingController _label;
  late final TextEditingController _default;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _formula;
  late FamilyParameterKind _kind;

  @override
  void initState() {
    super.initState();
    final parameter = widget.parameter;
    _label = TextEditingController(text: parameter?.label ?? 'New parameter');
    _default = TextEditingController(text: '${parameter?.defaultValue ?? 1.0}');
    _minimum = TextEditingController(text: parameter?.minimum?.toString() ?? '');
    _maximum = TextEditingController(text: parameter?.maximum?.toString() ?? '');
    _formula = TextEditingController(text: parameter?.formula ?? '');
    _kind = parameter?.kind ?? FamilyParameterKind.number;
  }

  @override
  void dispose() {
    _label.dispose();
    _default.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _formula.dispose();
    super.dispose();
  }

  Object? _defaultValue() {
    switch (_kind) {
      case FamilyParameterKind.boolean:
        final text = _default.text.trim().toLowerCase();
        if (<String>{'true', '1', 'yes'}.contains(text)) return true;
        if (<String>{'false', '0', 'no'}.contains(text)) return false;
        return null;
      case FamilyParameterKind.text:
      case FamilyParameterKind.material:
        final text = _default.text.trim();
        return text.isEmpty ? null : text;
      case FamilyParameterKind.length:
      case FamilyParameterKind.number:
      case FamilyParameterKind.angle:
        return double.tryParse(_default.text.trim().replaceAll(',', '.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final numeric = _isNumericKind(_kind);
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
                      ? 'Core dimensions must remain length parameters.'
                      : null,
                ),
                items: FamilyParameterKind.values
                    .map(
                      (kind) => DropdownMenuItem<FamilyParameterKind>(
                        value: kind,
                        child: Text(kind.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: widget.lockKind
                    ? null
                    : (kind) {
                        if (kind != null) setState(() => _kind = kind);
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _default,
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Minimum (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _maximum,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Maximum (optional)',
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
                    helperText:
                        'Supports parameter ids, + − × ÷, parentheses, pi, min, max, abs and clamp.',
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
            final defaultValue = _defaultValue();
            final minimum = _minimum.text.trim().isEmpty
                ? null
                : double.tryParse(_minimum.text.trim().replaceAll(',', '.'));
            final maximum = _maximum.text.trim().isEmpty
                ? null
                : double.tryParse(_maximum.text.trim().replaceAll(',', '.'));
            final formula = numeric ? _formula.text.trim() : '';
            if (label.isEmpty || defaultValue == null) return;
            if (minimum != null && maximum != null && minimum > maximum) return;
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
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayRawValue(widget));
  }

  @override
  void didUpdateWidget(covariant _ParameterValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawValue != widget.rawValue ||
        oldWidget.parameter.formula != widget.parameter.formula) {
      final text = _displayRawValue(widget);
      if (_controller.text != text) _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parameter = widget.parameter;
    if (parameter.hasFormula) {
      return TextFormField(
        initialValue: '${widget.effectiveValue ?? 'invalid'}',
        readOnly: true,
        decoration: InputDecoration(
          labelText: parameter.label,
          helperText: '${parameter.id} = ${parameter.formula}',
          suffixText: _suffix(parameter.kind),
          prefixIcon: const Icon(Icons.functions),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
    }
    if (parameter.kind == FamilyParameterKind.boolean) {
      final checked = widget.rawValue == true ||
          widget.rawValue.toString().toLowerCase() == 'true';
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(parameter.label),
        subtitle: Text(parameter.id),
        value: checked,
        onChanged: widget.onChanged,
      );
    }

    final numeric = _isNumericKind(parameter.kind);
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
        final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
        if (parsed != null && parsed.isFinite) widget.onChanged(parsed);
      },
    );
  }

  static String _displayRawValue(_ParameterValueEditor widget) {
    final value = widget.parameter.hasFormula
        ? widget.effectiveValue
        : widget.rawValue;
    return value?.toString() ?? '';
  }
}

class _FamilyV2PreviewPainter extends CustomPainter {
  const _FamilyV2PreviewPainter({
    required this.mesh,
    required this.lineColor,
    required this.fillColor,
    required this.background,
  });

  final FamilyEvaluatedMesh mesh;
  final Color lineColor;
  final Color fillColor;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
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
          (size.width - 42) / width,
          (size.height - 58) / height,
        ) *
        0.82;
    final center = Offset(size.width * 0.5, size.height * 0.57);
    final modelCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    Offset screen(int index) {
      final point = projected[index];
      return Offset(
        center.dx + (point.dx - modelCenter.dx) * scale,
        center.dy + (point.dy - modelCenter.dy) * scale,
      );
    }

    final outline = Paint()
      ..color = lineColor.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final face in mesh.faces) {
      if (face.indices.length < 3 ||
          !face.indices.every((index) => index >= 0 && index < projected.length)) {
        continue;
      }
      final path = Path();
      final first = screen(face.indices.first);
      path.moveTo(first.dx, first.dy);
      for (final index in face.indices.skip(1)) {
        final point = screen(index);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = fillColor);
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyV2PreviewPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.background != background;
}

bool _validParameterValue(FamilyParameterDefinition parameter, Object? value) {
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
      if (parameter.kind == FamilyParameterKind.length && number <= 0) return false;
      return true;
  }
}

Object? _coerceValue(FamilyParameterKind kind, Object? raw) {
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

String _safeParameterId(String label) {
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

bool _isCoreDimension(String id) =>
    id == 'width' || id == 'depth' || id == 'height';

bool _isNumericKind(FamilyParameterKind kind) =>
    kind == FamilyParameterKind.length ||
    kind == FamilyParameterKind.number ||
    kind == FamilyParameterKind.angle;

bool _isSolidFeature(FamilyFeature feature) =>
    feature.kind == FamilyFeatureKind.box ||
    feature.kind == FamilyFeatureKind.extrude ||
    feature.kind == FamilyFeatureKind.revolve ||
    feature.kind == FamilyFeatureKind.booleanUnion ||
    feature.kind == FamilyFeatureKind.booleanSubtract ||
    feature.kind == FamilyFeatureKind.freeformMesh ||
    feature.kind == FamilyFeatureKind.transform ||
    feature.kind == FamilyFeatureKind.nestedFamily;

String _rangeText(FamilyParameterDefinition parameter) {
  if (parameter.minimum == null && parameter.maximum == null) return '';
  return ' · ${parameter.minimum ?? '−∞'}…${parameter.maximum ?? '∞'}';
}

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
    FamilyFeatureKind.nestedFamily => 'Nested family',
  };
}

String _featureSummary(FamilyFeature feature) => switch (feature.kind) {
      FamilyFeatureKind.box => 'Width × depth × height',
      FamilyFeatureKind.profile => '2D sketch input',
      FamilyFeatureKind.extrude => 'Profile → parametric solid',
      FamilyFeatureKind.revolve => 'Profile → revolved solid',
      FamilyFeatureKind.booleanUnion => 'Exact BSP union for closed manifold solids',
      FamilyFeatureKind.booleanSubtract =>
        'Exact BSP subtraction for closed manifold solids',
      FamilyFeatureKind.transform => 'Move / rotate / scale',
      FamilyFeatureKind.freeformMesh => 'Imported mesh geometry',
      FamilyFeatureKind.nestedFamily =>
        'Library family/type dependency · resolved before geometry evaluation',
    };

String _categoryLabel(FamilyCategory category) => switch (category) {
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
