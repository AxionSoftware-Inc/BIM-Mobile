import 'dart:async';

import 'package:flutter/material.dart';

import 'family_authoring_viewport.dart';
import 'family_constraints_panel.dart';
import 'family_dependency_resolver.dart';
import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_import_units_dialog.dart';
import 'family_mesh_importer.dart';
import 'family_nested_feature_dialog.dart';
import 'family_sketch_canvas.dart';
import 'family_validation.dart';

/// Task-oriented Family Editor.
///
/// The editor intentionally does not own a 3D camera or renderer. Outside
/// sketch mode it hosts [FamilyAuthoringViewport], which is the production
/// project RenderScene viewport. Authoring is organised around explicit CAD
/// tasks instead of exposing the raw feature graph as the primary UI.
class FamilyEditorV4Page extends StatefulWidget {
  const FamilyEditorV4Page({
    super.key,
    this.initialAsset,
  });

  final FamilyAssetFile? initialAsset;

  @override
  State<FamilyEditorV4Page> createState() => _FamilyEditorV4PageState();
}

enum _FamilyTool {
  select,
  profile,
  extrude,
  revolve,
  transform,
  union,
  subtract,
  more,
}

enum _CloseAction { save, discard }

class _FamilyEditorV4PageState extends State<FamilyEditorV4Page> {
  late FamilyDocument _document;
  late final TextEditingController _nameController;
  late final TextEditingController _extrudeDepthController;
  late final TextEditingController _revolveAngleController;
  late final TextEditingController _txController;
  late final TextEditingController _tyController;
  late final TextEditingController _tzController;
  late final TextEditingController _rotationController;
  late final TextEditingController _scaleController;

  String? _assetPath;
  String? _selectedTypeId;
  String? _selectedFeatureId;
  String? _activeSketchId;
  String? _profileIdForSolid;
  String? _transformSourceId;
  String? _booleanBaseId;
  String? _booleanToolId;
  _FamilyTool _tool = _FamilyTool.select;
  bool _dirty = false;
  String? _status;
  final List<FamilyDocument> _undo = <FamilyDocument>[];
  final List<FamilyDocument> _redo = <FamilyDocument>[];
  String? _previewKey;
  Future<FamilyEvaluatedMesh>? _previewFuture;

  @override
  void initState() {
    super.initState();
    final asset = widget.initialAsset;
    _document = asset?.document ?? FamilyDocument.starter();
    _assetPath = asset?.path;
    _selectedTypeId = asset?.preferredTypeId ?? _document.types.first.id;
    _selectedFeatureId = _lastSolidFeature(_document)?.id ?? _document.features.last.id;
    _nameController = TextEditingController(text: _document.name);
    _extrudeDepthController = TextEditingController(text: '1.0');
    _revolveAngleController = TextEditingController(text: '360');
    _txController = TextEditingController(text: '0');
    _tyController = TextEditingController(text: '0');
    _tzController = TextEditingController(text: '0');
    _rotationController = TextEditingController(text: '0');
    _scaleController = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _extrudeDepthController.dispose();
    _revolveAngleController.dispose();
    _txController.dispose();
    _tyController.dispose();
    _tzController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  FamilyTypeDefinition get _selectedType => _document.types.firstWhere(
        (type) => type.id == _selectedTypeId,
        orElse: () => _document.types.first,
      );

  FamilyFeature? get _selectedFeature {
    final id = _selectedFeatureId;
    if (id == null) return null;
    for (final feature in _document.features) {
      if (feature.id == id) return feature;
    }
    return null;
  }

  FamilySketch? get _activeSketch {
    final id = _activeSketchId;
    if (id == null) return null;
    for (final sketch in _document.sketches) {
      if (sketch.id == id) return sketch;
    }
    return null;
  }

  bool get _hasNestedFamily => _document.features.any(
        (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
      );

  void _commit(FamilyDocument next, {String? status}) {
    if (identical(next, _document)) return;
    _undo.add(_document);
    _redo.clear();
    _setDocument(next, dirty: true, status: status);
  }

  void _replaceDraft(FamilyDocument next, {String? status}) {
    _redo.clear();
    _setDocument(next, dirty: true, status: status);
  }

  void _setDocument(
    FamilyDocument next, {
    required bool dirty,
    String? status,
    bool syncName = false,
  }) {
    setState(() {
      _document = next;
      _dirty = dirty;
      _status = status;
      _previewKey = null;
      _previewFuture = null;
      if (!_document.types.any((type) => type.id == _selectedTypeId)) {
        _selectedTypeId = _document.types.first.id;
      }
      if (!_document.features.any((feature) => feature.id == _selectedFeatureId)) {
        _selectedFeatureId = _lastSolidFeature(_document)?.id ??
            (_document.features.isEmpty ? null : _document.features.last.id);
      }
      if (!_document.sketches.any((sketch) => sketch.id == _activeSketchId)) {
        _activeSketchId = null;
      }
      if (syncName) _nameController.text = _document.name;
    });
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    _redo.add(_document);
    final previous = _undo.removeLast();
    _setDocument(previous, dirty: true, syncName: true);
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    _undo.add(_document);
    final next = _redo.removeLast();
    _setDocument(next, dirty: true, syncName: true);
  }

  Future<FamilyEvaluatedMesh> _previewMesh() {
    final key = '${_selectedType.id}\u001f${_document.toJsonText()}';
    if (_previewFuture != null && _previewKey == key) return _previewFuture!;
    _previewKey = key;
    _previewFuture = () async {
      if (!_hasNestedFamily) {
        return FamilyGeometryEvaluator.evaluateMesh(_document, _selectedType);
      }
      final resolved = await FamilyDependencyResolver.resolveFromLibrary(
        _document,
        _selectedType,
      );
      return FamilyGeometryEvaluator.evaluateMesh(resolved, _selectedType);
    }();
    return _previewFuture!;
  }

  void _chooseTool(_FamilyTool tool) {
    if (tool == _FamilyTool.profile) {
      _enterProfileMode();
      return;
    }
    setState(() {
      _tool = tool;
      _status = null;
    });
    if (tool == _FamilyTool.extrude) _prepareExtrude();
    if (tool == _FamilyTool.revolve) _prepareRevolve();
    if (tool == _FamilyTool.transform) _prepareTransform();
    if (tool == _FamilyTool.union || tool == _FamilyTool.subtract) {
      _prepareBoolean(tool);
    }
  }

  void _enterProfileMode() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.profile) {
      final sketchId = selected!.parameters['profileId']?.toString() ??
          (selected.inputs.isEmpty ? null : selected.inputs.first);
      if (sketchId != null &&
          _document.sketches.any((sketch) => sketch.id == sketchId)) {
        setState(() {
          _tool = _FamilyTool.profile;
          _activeSketchId = sketchId;
          _status = 'Sketch mode · tap empty space to add points; drag a point to move it.';
        });
        return;
      }
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final sketch = FamilySketch(
      id: 'sketch-$stamp',
      name: 'Profile ${_document.sketches.length + 1}',
      plane: FamilySketchPlane.xy,
    );
    final feature = FamilyFeature(
      id: 'feature-profile-$stamp',
      kind: FamilyFeatureKind.profile,
      label: sketch.name,
      inputs: <String>[sketch.id],
      parameters: <String, Object?>{'profileId': sketch.id},
    );
    _activeSketchId = sketch.id;
    _selectedFeatureId = feature.id;
    _tool = _FamilyTool.profile;
    _commit(
      _document.copyWith(
        sketches: <FamilySketch>[..._document.sketches, sketch],
        features: <FamilyFeature>[..._document.features, feature],
      ),
      status: 'New profile · tap to draw the outline, then Close profile.',
    );
  }

  void _updateSketch(FamilySketch next, {bool structural = false}) {
    final candidate = _document.copyWith(
      sketches: <FamilySketch>[
        for (final sketch in _document.sketches)
          sketch.id == next.id ? next : sketch,
      ],
    );
    if (structural) {
      _commit(candidate);
    } else {
      _replaceDraft(candidate);
    }
  }

  void _addSketchPoint(FamilySketchPoint point) {
    final sketch = _activeSketch;
    if (sketch == null || sketch.closed) return;
    final index = sketch.points.length;
    _updateSketch(
      sketch.copyWith(
        points: <FamilySketchPoint>[
          ...sketch.points,
          point.copyWith(id: '${sketch.id}:point-$index'),
        ],
      ),
      structural: true,
    );
  }

  void _moveSketchPoint(int index, FamilySketchPoint point) {
    final sketch = _activeSketch;
    if (sketch == null || index < 0 || index >= sketch.points.length) return;
    final points = <FamilySketchPoint>[...sketch.points];
    points[index] = point.copyWith(id: points[index].id);
    _updateSketch(sketch.copyWith(points: points));
  }

  void _toggleProfileClosed() {
    final sketch = _activeSketch;
    if (sketch == null) return;
    if (!sketch.closed && sketch.points.length < 3) {
      setState(() => _status = 'Profile needs at least 3 points before it can be closed.');
      return;
    }
    _updateSketch(sketch.copyWith(closed: !sketch.closed), structural: true);
  }

  void _clearProfile() {
    final sketch = _activeSketch;
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
      status: 'Profile cleared.',
    );
  }

  void _finishProfile() {
    final sketch = _activeSketch;
    if (sketch == null) return;
    if (!sketch.isValid) {
      setState(() => _status = 'Close the profile before finishing sketch mode.');
      return;
    }
    setState(() {
      _tool = _FamilyTool.select;
      _profileIdForSolid = sketch.id;
      _status = 'Profile ready. Choose Extrude or Revolve.';
    });
  }

  void _prepareExtrude() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.extrude) {
      _profileIdForSolid = selected!.parameters['profileId']?.toString();
      _extrudeDepthController.text = '${selected.parameters['depth'] ?? 1.0}';
      return;
    }
    _profileIdForSolid = _preferredClosedSketchId();
    _extrudeDepthController.text = '1.0';
  }

  void _prepareRevolve() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.revolve) {
      _profileIdForSolid = selected!.parameters['profileId']?.toString();
      _revolveAngleController.text = '${selected.parameters['angle'] ?? 360}';
      return;
    }
    _profileIdForSolid = _preferredClosedSketchId();
    _revolveAngleController.text = '360';
  }

  String? _preferredClosedSketchId() {
    if (_activeSketchId != null &&
        _document.sketches.any(
          (sketch) => sketch.id == _activeSketchId && sketch.isValid,
        )) {
      return _activeSketchId;
    }
    for (var index = _document.sketches.length - 1; index >= 0; index--) {
      if (_document.sketches[index].isValid) return _document.sketches[index].id;
    }
    return null;
  }

  void _applyExtrude() {
    final profileId = _profileIdForSolid;
    final depth = _extrudeDepthController.text.trim();
    if (profileId == null || depth.isEmpty) {
      setState(() => _status = 'Choose a closed profile and enter an extrusion depth.');
      return;
    }
    final selected = _selectedFeature;
    final editing = selected?.kind == FamilyFeatureKind.extrude;
    final feature = FamilyFeature(
      id: editing ? selected!.id : 'feature-extrude-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.extrude,
      label: editing && selected!.label.trim().isNotEmpty ? selected.label : 'Extrude',
      inputs: <String>[profileId],
      parameters: <String, Object?>{
        'profileId': profileId,
        'depth': depth,
      },
    );
    _upsertFeature(feature, editing: editing, status: editing ? 'Extrude updated.' : 'Extrude created.');
  }

  void _applyRevolve() {
    final profileId = _profileIdForSolid;
    final angle = _revolveAngleController.text.trim();
    if (profileId == null || angle.isEmpty) {
      setState(() => _status = 'Choose a closed profile and enter a revolve angle.');
      return;
    }
    final selected = _selectedFeature;
    final editing = selected?.kind == FamilyFeatureKind.revolve;
    final feature = FamilyFeature(
      id: editing ? selected!.id : 'feature-revolve-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.revolve,
      label: editing && selected!.label.trim().isNotEmpty ? selected.label : 'Revolve',
      inputs: <String>[profileId],
      parameters: <String, Object?>{
        'profileId': profileId,
        'angle': angle,
      },
    );
    _upsertFeature(feature, editing: editing, status: editing ? 'Revolve updated.' : 'Revolve created.');
  }

  void _prepareTransform() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.transform) {
      _transformSourceId = selected!.inputs.isEmpty ? null : selected.inputs.first;
      _txController.text = '${selected.parameters['translationX'] ?? 0}';
      _tyController.text = '${selected.parameters['translationY'] ?? 0}';
      _tzController.text = '${selected.parameters['translationZ'] ?? 0}';
      _rotationController.text = '${selected.parameters['rotationZ'] ?? 0}';
      _scaleController.text = '${selected.parameters['scale'] ?? 1}';
      return;
    }
    _transformSourceId = selected != null && _isLocalSolid(selected)
        ? selected.id
        : _eligibleSolids().lastOrNull?.id;
    _txController.text = '0';
    _tyController.text = '0';
    _tzController.text = '0';
    _rotationController.text = '0';
    _scaleController.text = '1';
  }

  void _applyTransform() {
    final sourceId = _transformSourceId;
    final values = <String>[
      _txController.text.trim(),
      _tyController.text.trim(),
      _tzController.text.trim(),
      _rotationController.text.trim(),
      _scaleController.text.trim(),
    ];
    if (sourceId == null || values.any((value) => value.isEmpty)) {
      setState(() => _status = 'Choose a source solid and complete all transform fields.');
      return;
    }
    final selected = _selectedFeature;
    final editing = selected?.kind == FamilyFeatureKind.transform;
    final feature = FamilyFeature(
      id: editing ? selected!.id : 'feature-transform-${DateTime.now().microsecondsSinceEpoch}',
      kind: FamilyFeatureKind.transform,
      label: editing && selected!.label.trim().isNotEmpty ? selected.label : 'Transform',
      inputs: <String>[sourceId],
      parameters: <String, Object?>{
        'translationX': values[0],
        'translationY': values[1],
        'translationZ': values[2],
        'rotationZ': values[3],
        'scale': values[4],
      },
    );
    _upsertFeature(feature, editing: editing, status: editing ? 'Transform updated.' : 'Transform created.');
  }

  void _prepareBoolean(_FamilyTool tool) {
    final kind = tool == _FamilyTool.union
        ? FamilyFeatureKind.booleanUnion
        : FamilyFeatureKind.booleanSubtract;
    final selected = _selectedFeature;
    if (selected?.kind == kind) {
      _booleanBaseId = selected!.inputs.isEmpty ? null : selected.inputs.first;
      _booleanToolId = selected.inputs.length < 2 ? null : selected.inputs[1];
      return;
    }
    final solids = _eligibleSolids();
    _booleanBaseId = selected != null && _isLocalSolid(selected)
        ? selected.id
        : (solids.isEmpty ? null : solids.last.id);
    _booleanToolId = null;
    for (var index = solids.length - 1; index >= 0; index--) {
      if (solids[index].id != _booleanBaseId) {
        _booleanToolId = solids[index].id;
        break;
      }
    }
  }

  void _applyBoolean(FamilyFeatureKind kind) {
    final baseId = _booleanBaseId;
    final toolId = _booleanToolId;
    if (baseId == null || toolId == null || baseId == toolId) {
      setState(() => _status = 'Choose two different solids: Base and Tool.');
      return;
    }
    final selected = _selectedFeature;
    final editing = selected?.kind == kind;
    final feature = FamilyFeature(
      id: editing ? selected!.id : 'feature-boolean-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      label: editing && selected!.label.trim().isNotEmpty
          ? selected.label
          : kind == FamilyFeatureKind.booleanUnion
              ? 'Union'
              : 'Subtract',
      inputs: <String>[baseId, toolId],
      parameters: <String, Object?>{'operation': kind.name},
    );
    _upsertFeature(
      feature,
      editing: editing,
      status: kind == FamilyFeatureKind.booleanUnion
          ? (editing ? 'Union updated.' : 'Union created.')
          : (editing ? 'Subtract updated.' : 'Subtract created.'),
    );
  }

  void _upsertFeature(
    FamilyFeature feature, {
    required bool editing,
    required String status,
  }) {
    final features = editing
        ? <FamilyFeature>[
            for (final current in _document.features)
              current.id == feature.id ? feature : current,
          ]
        : <FamilyFeature>[..._document.features, feature];
    final candidate = _document.copyWith(features: features);
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return;
    }
    _selectedFeatureId = feature.id;
    _tool = _FamilyTool.select;
    _commit(candidate, status: status);
  }

  List<FamilyFeature> _eligibleSolids() {
    final selected = _selectedFeature;
    final editing = selected != null &&
        ((_tool == _FamilyTool.transform && selected.kind == FamilyFeatureKind.transform) ||
            (_tool == _FamilyTool.union && selected.kind == FamilyFeatureKind.booleanUnion) ||
            (_tool == _FamilyTool.subtract && selected.kind == FamilyFeatureKind.booleanSubtract));
    final limit = editing
        ? _document.features.indexWhere((feature) => feature.id == selected.id)
        : _document.features.length;
    return <FamilyFeature>[
      for (var index = 0; index < limit; index++)
        if (_isLocalSolid(_document.features[index])) _document.features[index],
    ];
  }

  Future<void> _importGltf() async {
    final unitScale = await FamilyImportUnitsDialog.show(context);
    if (!mounted || unitScale == null) return;
    setState(() => _status = 'Choose a GLB/glTF file…');
    try {
      final imported = await FamilyMeshImporter.pickGltf(unitScale: unitScale);
      if (!mounted || imported == null) return;
      _undo.add(_document);
      _redo.clear();
      _assetPath = null;
      _selectedTypeId = imported.document.types.first.id;
      _selectedFeatureId = imported.document.features.last.id;
      _activeSketchId = null;
      _nameController.text = imported.document.name;
      _setDocument(
        imported.document,
        dirty: true,
        status: 'Imported ${imported.vertexCount} vertices · ${imported.faceCount} faces.',
      );
    } catch (error) {
      if (mounted) setState(() => _status = 'Import failed: $error');
    }
  }

  Future<void> _addNestedFamily() async {
    final feature = await FamilyNestedFeatureDialog.show(context, parent: _document);
    if (!mounted || feature == null) return;
    final candidate = _document.copyWith(
      features: <FamilyFeature>[..._document.features, feature],
    );
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return;
    }
    _selectedFeatureId = feature.id;
    _commit(candidate, status: '${feature.label} added.');
  }

  Future<void> _deleteSelectedFeature() async {
    final feature = _selectedFeature;
    if (feature == null) return;
    if (_document.features.length <= 1) {
      setState(() => _status = 'A family must keep at least one feature.');
      return;
    }
    final users = _document.features.where(
      (candidate) =>
          candidate.id != feature.id &&
          (candidate.inputs.contains(feature.id) ||
              candidate.parameters['profileId']?.toString() == feature.id),
    );
    if (users.isNotEmpty) {
      setState(() => _status = '${_featureName(feature)} is used by another feature. Edit that dependency first.');
      return;
    }
    String? sketchId;
    if (feature.kind == FamilyFeatureKind.profile) {
      sketchId = feature.parameters['profileId']?.toString() ??
          (feature.inputs.isEmpty ? null : feature.inputs.first);
      final sketchUsed = _document.features.any(
        (candidate) => candidate.id != feature.id &&
            (candidate.parameters['profileId']?.toString() == sketchId ||
                candidate.inputs.contains(sketchId)),
      );
      if (sketchUsed) {
        setState(() => _status = 'This profile is used by a solid and cannot be deleted yet.');
        return;
      }
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_featureName(feature)}?'),
        content: const Text('This removes the selected feature from the family history.'),
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
      features: <FamilyFeature>[
        for (final current in _document.features)
          if (current.id != feature.id) current,
      ],
      sketches: sketchId == null
          ? _document.sketches
          : <FamilySketch>[
              for (final sketch in _document.sketches)
                if (sketch.id != sketchId) sketch,
            ],
      constraints: sketchId == null
          ? _document.constraints
          : <FamilySketchConstraint>[
              for (final constraint in _document.constraints)
                if (constraint.sketchId != sketchId) constraint,
            ],
    );
    _selectedFeatureId = _lastSolidFeature(candidate)?.id ?? candidate.features.last.id;
    _commit(candidate, status: '${_featureName(feature)} deleted.');
  }

  void _updateDimension(String parameterId, String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => _status = '$parameterId must be a positive number.');
      return;
    }
    FamilyParameterDefinition? parameter;
    for (final candidate in _document.parameters) {
      if (candidate.id == parameterId) {
        parameter = candidate;
        break;
      }
    }
    if (parameter == null || parameter.hasFormula) return;
    if (parameter.minimum != null && value < parameter.minimum! ||
        parameter.maximum != null && value > parameter.maximum!) {
      setState(() => _status = '${parameter!.label} is outside its allowed range.');
      return;
    }
    final selected = _selectedType;
    final replacement = selected.copyWith(
      values: <String, Object?>{...selected.values, parameterId: value},
    );
    _commit(
      _document.copyWith(
        types: <FamilyTypeDefinition>[
          for (final type in _document.types)
            type.id == selected.id ? replacement : type,
        ],
      ),
      status: '${parameter.label} updated.',
    );
  }

  void _duplicateType() {
    final source = _selectedType;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final next = FamilyTypeDefinition(
      id: 'type-$stamp',
      name: '${source.name} Copy',
      values: Map<String, Object?>.from(source.values),
    );
    _selectedTypeId = next.id;
    _commit(
      _document.copyWith(types: <FamilyTypeDefinition>[..._document.types, next]),
      status: 'Family type duplicated.',
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
    final name = _nameController.text.trim();
    final candidate = name.isEmpty ? _document : _document.copyWith(name: name);
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      _setDocument(candidate, dirty: true, status: validation.errors.first);
      return false;
    }
    setState(() => _status = 'Saving family…');
    try {
      await _preflightDependencies(candidate);
      final path = _assetPath == null
          ? await FamilyFileStore.save(candidate)
          : await FamilyFileStore.saveAsset(candidate, existingPath: _assetPath!);
      if (!mounted || path == null) return false;
      _assetPath = path;
      _setDocument(candidate, dirty: false, status: 'Saved.');
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
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              if (wide) {
                return Row(
                  children: <Widget>[
                    _buildToolRail(vertical: true),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildCenterWorkspace()),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 350, child: _buildInspector()),
                  ],
                );
              }
              return Column(
                children: <Widget>[
                  SizedBox(height: 76, child: _buildToolRail(vertical: false)),
                  const Divider(height: 1),
                  Expanded(child: _buildCenterWorkspace()),
                  const Divider(height: 1),
                  SizedBox(height: 300, child: _buildInspector()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'Close family',
        onPressed: _requestClose,
        icon: const Icon(Icons.close),
      ),
      title: Row(
        children: <Widget>[
          const Text('Family Editor'),
          const SizedBox(width: 14),
          SizedBox(
            width: 230,
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'Family name',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final name = value.trim();
                if (name.isNotEmpty && name != _document.name) {
                  _commit(_document.copyWith(name: name));
                }
              },
            ),
          ),
        ],
      ),
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
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_dirty ? 'Save' : 'Saved'),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildToolRail({required bool vertical}) {
    final tools = <(_FamilyTool, IconData, String)>[
      (_FamilyTool.select, Icons.near_me_outlined, 'Select'),
      (_FamilyTool.profile, Icons.polyline_outlined, 'Profile'),
      (_FamilyTool.extrude, Icons.height, 'Extrude'),
      (_FamilyTool.revolve, Icons.rotate_right_outlined, 'Revolve'),
      (_FamilyTool.transform, Icons.open_with_outlined, 'Move'),
      (_FamilyTool.union, Icons.merge_type_outlined, 'Union'),
      (_FamilyTool.subtract, Icons.call_split_outlined, 'Subtract'),
      (_FamilyTool.more, Icons.tune_outlined, 'More'),
    ];
    final buttons = <Widget>[
      for (final item in tools)
        _ToolButton(
          icon: item.$2,
          label: item.$3,
          selected: _tool == item.$1,
          onTap: () => _chooseTool(item.$1),
        ),
      _ToolButton(
        icon: Icons.file_upload_outlined,
        label: 'Import',
        selected: false,
        onTap: _importGltf,
      ),
    ];
    if (vertical) {
      return SizedBox(
        width: 92,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          children: buttons,
        ),
      );
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      children: buttons,
    );
  }

  Widget _buildCenterWorkspace() {
    return Column(
      children: <Widget>[
        if (_status != null)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _status = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _tool == _FamilyTool.profile && _activeSketch != null
                ? _buildSketchWorkspace(_activeSketch!)
                : _buildProjectViewport(),
          ),
        ),
        _buildHistoryStrip(),
      ],
    );
  }

  Widget _buildProjectViewport() {
    return FutureBuilder<FamilyEvaluatedMesh>(
      future: _previewMesh(),
      builder: (context, snapshot) {
        final mesh = snapshot.data;
        if (mesh != null) {
          return FamilyAuthoringViewport(
            document: _document,
            type: _selectedType,
            mesh: mesh,
            onFinalFeatureSelected: (featureId) {
              if (featureId != null &&
                  _document.features.any((feature) => feature.id == featureId)) {
                setState(() {
                  _selectedFeatureId = featureId;
                  _tool = _FamilyTool.select;
                });
              }
            },
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 42,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 10),
                      const Text('Family preview cannot be evaluated yet.'),
                      const SizedBox(height: 6),
                      Text('${snapshot.error}', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildSketchWorkspace(FamilySketch sketch) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.edit_note_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Sketch mode · ${sketch.name}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Text('Tap empty space to add a point. Drag an existing point to move it.'),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearProfile,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: _toggleProfileClosed,
                  icon: Icon(sketch.closed ? Icons.lock_open_outlined : Icons.join_full),
                  label: Text(sketch.closed ? 'Reopen' : 'Close profile'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: sketch.isValid ? _finishProfile : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Finish'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FamilySketchCanvas(
              sketch: sketch,
              onAddPoint: _addSketchPoint,
              onMovePoint: _moveSketchPoint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryStrip() {
    return SizedBox(
      height: 92,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 3),
              child: Text(
                'History · tap a feature to inspect or edit it',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                itemCount: _document.features.length,
                separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 18),
                itemBuilder: (context, index) {
                  final feature = _document.features[index];
                  final selected = feature.id == _selectedFeatureId;
                  return ChoiceChip(
                    selected: selected,
                    avatar: Icon(_featureIcon(feature.kind), size: 17),
                    label: Text(_featureName(feature)),
                    onSelected: (_) {
                      setState(() {
                        _selectedFeatureId = feature.id;
                        _tool = _FamilyTool.select;
                        _status = null;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspector() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildTypeCard(),
            const SizedBox(height: 10),
            switch (_tool) {
              _FamilyTool.select => _buildSelectInspector(),
              _FamilyTool.profile => _buildProfileInspector(),
              _FamilyTool.extrude => _buildExtrudeInspector(),
              _FamilyTool.revolve => _buildRevolveInspector(),
              _FamilyTool.transform => _buildTransformInspector(),
              _FamilyTool.union => _buildBooleanInspector(FamilyFeatureKind.booleanUnion),
              _FamilyTool.subtract => _buildBooleanInspector(FamilyFeatureKind.booleanSubtract),
              _FamilyTool.more => _buildMoreInspector(),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard() {
    return _InspectorCard(
      title: 'Family type',
      subtitle: 'The dimensions you normally change first',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>(_selectedType.id),
                  initialValue: _selectedType.id,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final type in _document.types)
                      DropdownMenuItem<String>(value: type.id, child: Text(type.name)),
                  ],
                  onChanged: (id) {
                    if (id != null) setState(() => _selectedTypeId = id);
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Duplicate type',
                onPressed: _duplicateType,
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final id in const <String>['width', 'depth', 'height']) ...<Widget>[
                if (id != 'width') const SizedBox(width: 6),
                Expanded(child: _dimensionField(id)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dimensionField(String id) {
    FamilyParameterDefinition? parameter;
    for (final candidate in _document.parameters) {
      if (candidate.id == id) {
        parameter = candidate;
        break;
      }
    }
    final value = _selectedType.values[id] ?? parameter?.defaultValue ?? 1.0;
    return TextFormField(
      key: ValueKey<String>('${_selectedType.id}:$id:$value'),
      initialValue: '$value',
      enabled: parameter?.hasFormula != true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _dimensionLabel(id),
        suffixText: 'm',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onFieldSubmitted: (raw) => _updateDimension(id, raw),
    );
  }

  Widget _buildSelectInspector() {
    final selected = _selectedFeature;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _QuickStartCard(
          onProfile: () => _chooseTool(_FamilyTool.profile),
          onExtrude: () => _chooseTool(_FamilyTool.extrude),
        ),
        const SizedBox(height: 10),
        _InspectorCard(
          title: selected == null ? 'Nothing selected' : _featureName(selected),
          subtitle: selected == null ? 'Pick a history feature' : selected.kind.name,
          child: selected == null
              ? const Text('Tap a feature in History or tap the final model in the viewport.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(_featureDescription(selected)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        if (selected.kind == FamilyFeatureKind.profile)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.profile),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit sketch'),
                          ),
                        if (selected.kind == FamilyFeatureKind.extrude)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.extrude),
                            icon: const Icon(Icons.height),
                            label: const Text('Edit extrude'),
                          ),
                        if (selected.kind == FamilyFeatureKind.revolve)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.revolve),
                            icon: const Icon(Icons.rotate_right_outlined),
                            label: const Text('Edit revolve'),
                          ),
                        if (selected.kind == FamilyFeatureKind.transform)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.transform),
                            icon: const Icon(Icons.open_with_outlined),
                            label: const Text('Edit transform'),
                          ),
                        if (selected.kind == FamilyFeatureKind.booleanUnion)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.union),
                            icon: const Icon(Icons.merge_type_outlined),
                            label: const Text('Edit union'),
                          ),
                        if (selected.kind == FamilyFeatureKind.booleanSubtract)
                          FilledButton.tonalIcon(
                            onPressed: () => _chooseTool(_FamilyTool.subtract),
                            icon: const Icon(Icons.call_split_outlined),
                            label: const Text('Edit subtract'),
                          ),
                        if (_isLocalSolid(selected) &&
                            selected.kind != FamilyFeatureKind.transform)
                          OutlinedButton.icon(
                            onPressed: () => _chooseTool(_FamilyTool.transform),
                            icon: const Icon(Icons.open_with_outlined),
                            label: const Text('Move / scale'),
                          ),
                        OutlinedButton.icon(
                          onPressed: _deleteSelectedFeature,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildProfileInspector() {
    final sketch = _activeSketch;
    return _InspectorCard(
      title: 'Profile',
      subtitle: '1 · Draw  2 · Close  3 · Finish',
      child: sketch == null
          ? FilledButton.icon(
              onPressed: _enterProfileMode,
              icon: const Icon(Icons.add),
              label: const Text('New profile'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('${sketch.points.length} points · ${sketch.closed ? 'Closed' : 'Open'}'),
                const SizedBox(height: 8),
                const Text('The large centre canvas is the sketch. Tap to place points; drag points to reshape it.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _toggleProfileClosed,
                  icon: Icon(sketch.closed ? Icons.lock_open_outlined : Icons.join_full),
                  label: Text(sketch.closed ? 'Reopen profile' : 'Close profile'),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: sketch.isValid ? _finishProfile : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Finish profile'),
                ),
              ],
            ),
    );
  }

  Widget _buildExtrudeInspector() {
    final sketches = _document.sketches.where((sketch) => sketch.isValid).toList(growable: false);
    final editing = _selectedFeature?.kind == FamilyFeatureKind.extrude;
    return _InspectorCard(
      title: editing ? 'Edit Extrude' : 'Extrude',
      subtitle: 'Closed profile → solid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (sketches.isEmpty) ...<Widget>[
            const Text('No closed profile exists yet.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _chooseTool(_FamilyTool.profile),
              icon: const Icon(Icons.polyline_outlined),
              label: const Text('Draw profile first'),
            ),
          ] else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(_profileIdForSolid),
              initialValue: sketches.any((sketch) => sketch.id == _profileIdForSolid)
                  ? _profileIdForSolid
                  : sketches.last.id,
              decoration: const InputDecoration(
                labelText: '1 · Profile',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final sketch in sketches)
                  DropdownMenuItem<String>(value: sketch.id, child: Text(sketch.name)),
              ],
              onChanged: (id) => setState(() => _profileIdForSolid = id),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _extrudeDepthController,
              decoration: const InputDecoration(
                labelText: '2 · Depth',
                suffixText: 'm or expression',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _applyExtrude,
              icon: const Icon(Icons.height),
              label: Text(editing ? '3 · Update Extrude' : '3 · Create Extrude'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRevolveInspector() {
    final sketches = _document.sketches.where((sketch) => sketch.isValid).toList(growable: false);
    final editing = _selectedFeature?.kind == FamilyFeatureKind.revolve;
    return _InspectorCard(
      title: editing ? 'Edit Revolve' : 'Revolve',
      subtitle: 'Closed profile → revolved solid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (sketches.isEmpty)
            FilledButton.icon(
              onPressed: () => _chooseTool(_FamilyTool.profile),
              icon: const Icon(Icons.polyline_outlined),
              label: const Text('Draw profile first'),
            )
          else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(_profileIdForSolid),
              initialValue: sketches.any((sketch) => sketch.id == _profileIdForSolid)
                  ? _profileIdForSolid
                  : sketches.last.id,
              decoration: const InputDecoration(
                labelText: '1 · Profile',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final sketch in sketches)
                  DropdownMenuItem<String>(value: sketch.id, child: Text(sketch.name)),
              ],
              onChanged: (id) => setState(() => _profileIdForSolid = id),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _revolveAngleController,
              decoration: const InputDecoration(
                labelText: '2 · Angle',
                suffixText: '° or expression',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _applyRevolve,
              icon: const Icon(Icons.rotate_right_outlined),
              label: Text(editing ? '3 · Update Revolve' : '3 · Create Revolve'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransformInspector() {
    final solids = _eligibleSolids();
    final editing = _selectedFeature?.kind == FamilyFeatureKind.transform;
    return _InspectorCard(
      title: editing ? 'Edit Transform' : 'Move / rotate / scale',
      subtitle: 'Create a transformed result from one solid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (solids.isEmpty)
            const Text('Create a solid first.')
          else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(_transformSourceId),
              initialValue: solids.any((feature) => feature.id == _transformSourceId)
                  ? _transformSourceId
                  : solids.last.id,
              decoration: const InputDecoration(
                labelText: 'Source solid',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final feature in solids)
                  DropdownMenuItem<String>(value: feature.id, child: Text(_featureName(feature))),
              ],
              onChanged: (id) => setState(() => _transformSourceId = id),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(child: _expressionField(_txController, 'X')),
                const SizedBox(width: 5),
                Expanded(child: _expressionField(_tyController, 'Y')),
                const SizedBox(width: 5),
                Expanded(child: _expressionField(_tzController, 'Z')),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: <Widget>[
                Expanded(child: _expressionField(_rotationController, 'Rotation Z°')),
                const SizedBox(width: 5),
                Expanded(child: _expressionField(_scaleController, 'Scale')),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _applyTransform,
              icon: const Icon(Icons.open_with_outlined),
              label: Text(editing ? 'Update Transform' : 'Create Transform'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBooleanInspector(FamilyFeatureKind kind) {
    final solids = _eligibleSolids();
    final editing = _selectedFeature?.kind == kind;
    final subtract = kind == FamilyFeatureKind.booleanSubtract;
    return _InspectorCard(
      title: editing
          ? 'Edit ${subtract ? 'Subtract' : 'Union'}'
          : (subtract ? 'Subtract' : 'Union'),
      subtitle: subtract ? 'Base − Tool' : 'Base + Tool',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (solids.length < 2) ...<Widget>[
            const Text('Boolean needs two solids.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: solids.isEmpty ? null : () => _chooseTool(_FamilyTool.transform),
              icon: const Icon(Icons.open_with_outlined),
              label: const Text('Transform a solid to create another'),
            ),
          ] else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>('base:$_booleanBaseId'),
              initialValue: solids.any((feature) => feature.id == _booleanBaseId)
                  ? _booleanBaseId
                  : solids.first.id,
              decoration: const InputDecoration(
                labelText: '1 · Base solid',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final feature in solids)
                  DropdownMenuItem<String>(value: feature.id, child: Text(_featureName(feature))),
              ],
              onChanged: (id) => setState(() => _booleanBaseId = id),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey<String?>('tool:$_booleanToolId'),
              initialValue: solids.any((feature) => feature.id == _booleanToolId)
                  ? _booleanToolId
                  : solids.last.id,
              decoration: InputDecoration(
                labelText: subtract ? '2 · Tool to remove' : '2 · Second solid',
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final feature in solids)
                  DropdownMenuItem<String>(value: feature.id, child: Text(_featureName(feature))),
              ],
              onChanged: (id) => setState(() => _booleanToolId = id),
            ),
            const SizedBox(height: 8),
            if (subtract)
              const Text('Order matters: the Tool is cut out of the Base.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _applyBoolean(kind),
              icon: Icon(subtract ? Icons.call_split_outlined : Icons.merge_type_outlined),
              label: Text(
                editing
                    ? '3 · Update ${subtract ? 'Subtract' : 'Union'}'
                    : '3 · Create ${subtract ? 'Subtract' : 'Union'}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoreInspector() {
    final activeSketchId = _activeSketchId ?? _selectedProfileSketchId();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InspectorCard(
          title: 'Family settings',
          subtitle: 'Less common authoring controls',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
                      child: Text(_categoryName(category)),
                    ),
                ],
                onChanged: (category) {
                  if (category != null) {
                    _commit(_document.copyWith(category: category));
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addNestedFamily,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Add nested family'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _importGltf,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import GLB/glTF'),
              ),
            ],
          ),
        ),
        if (activeSketchId != null) ...<Widget>[
          const SizedBox(height: 10),
          FamilyConstraintsPanel(
            document: _document,
            type: _selectedType,
            selectedSketchId: activeSketchId,
            onChanged: (next) => _commit(next, status: 'Constraints updated.'),
            onStatus: (message) => setState(() => _status = message),
          ),
        ],
        const SizedBox(height: 10),
        _InspectorCard(
          title: 'Parameters',
          subtitle: 'Definitions remain part of the same .bimfamily document',
          child: Column(
            children: <Widget>[
              for (final parameter in _document.parameters)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_outlined, size: 20),
                  title: Text(parameter.label),
                  subtitle: Text(
                    '${parameter.id} · ${parameter.kind.name}${parameter.hasFormula ? ' · = ${parameter.formula}' : ''}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _expressionField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: '0 or expression',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  String? _selectedProfileSketchId() {
    final feature = _selectedFeature;
    if (feature?.kind != FamilyFeatureKind.profile) return null;
    return feature!.parameters['profileId']?.toString() ??
        (feature.inputs.isEmpty ? null : feature.inputs.first);
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(
            width: 74,
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 23, color: selected ? colors.onSecondaryContainer : null),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({required this.onProfile, required this.onExtrude});

  final VoidCallback onProfile;
  final VoidCallback onExtrude;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Start here',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            const Text('1. Draw a Profile\n2. Close it\n3. Extrude it into a solid'),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onProfile,
                    icon: const Icon(Icons.polyline_outlined),
                    label: const Text('Profile'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExtrude,
                    icon: const Icon(Icons.height),
                    label: const Text('Extrude'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

bool _isLocalSolid(FamilyFeature feature) =>
    feature.kind == FamilyFeatureKind.box ||
    feature.kind == FamilyFeatureKind.extrude ||
    feature.kind == FamilyFeatureKind.revolve ||
    feature.kind == FamilyFeatureKind.booleanUnion ||
    feature.kind == FamilyFeatureKind.booleanSubtract ||
    feature.kind == FamilyFeatureKind.transform ||
    feature.kind == FamilyFeatureKind.freeformMesh;

FamilyFeature? _lastSolidFeature(FamilyDocument document) {
  for (var index = document.features.length - 1; index >= 0; index--) {
    final feature = document.features[index];
    if (_isLocalSolid(feature) || feature.kind == FamilyFeatureKind.nestedFamily) {
      return feature;
    }
  }
  return null;
}

String _featureName(FamilyFeature feature) {
  if (feature.label.trim().isNotEmpty) return feature.label.trim();
  return switch (feature.kind) {
    FamilyFeatureKind.box => 'Box',
    FamilyFeatureKind.profile => 'Profile',
    FamilyFeatureKind.extrude => 'Extrude',
    FamilyFeatureKind.revolve => 'Revolve',
    FamilyFeatureKind.booleanUnion => 'Union',
    FamilyFeatureKind.booleanSubtract => 'Subtract',
    FamilyFeatureKind.transform => 'Transform',
    FamilyFeatureKind.freeformMesh => 'Imported mesh',
    FamilyFeatureKind.nestedFamily => 'Nested family',
  };
}

String _featureDescription(FamilyFeature feature) => switch (feature.kind) {
      FamilyFeatureKind.box => 'Base parametric solid driven by Width, Depth and Height.',
      FamilyFeatureKind.profile => '2D outline used by Extrude or Revolve.',
      FamilyFeatureKind.extrude =>
        'Profile ${feature.parameters['profileId'] ?? '—'} · depth ${feature.parameters['depth'] ?? '—'}',
      FamilyFeatureKind.revolve =>
        'Profile ${feature.parameters['profileId'] ?? '—'} · angle ${feature.parameters['angle'] ?? '—'}°',
      FamilyFeatureKind.booleanUnion => 'Combines ${feature.inputs.join(' + ')}.',
      FamilyFeatureKind.booleanSubtract => 'Cuts ${feature.inputs.length > 1 ? feature.inputs[1] : 'tool'} from ${feature.inputs.isEmpty ? 'base' : feature.inputs.first}.',
      FamilyFeatureKind.transform =>
        'Source ${feature.inputs.isEmpty ? '—' : feature.inputs.first} · X ${feature.parameters['translationX'] ?? 0} · Y ${feature.parameters['translationY'] ?? 0} · Z ${feature.parameters['translationZ'] ?? 0} · R ${feature.parameters['rotationZ'] ?? 0}° · S ${feature.parameters['scale'] ?? 1}',
      FamilyFeatureKind.freeformMesh => 'Imported render-ready mesh geometry.',
      FamilyFeatureKind.nestedFamily =>
        'Child ${feature.parameters['familyId'] ?? '—'} · type ${feature.parameters['typeId'] ?? '—'}',
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

String _dimensionLabel(String id) => switch (id) {
      'width' => 'Width',
      'depth' => 'Depth',
      'height' => 'Height',
      _ => id,
    };

String _categoryName(FamilyCategory category) => switch (category) {
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
