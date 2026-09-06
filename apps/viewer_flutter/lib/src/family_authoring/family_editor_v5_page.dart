import 'dart:async';
import 'dart:math' as math;

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

/// Direct-manipulation Family Editor.
///
/// The production project viewport remains the only 3D viewport. V5 changes
/// authoring semantics: tools are modal commands with live preview, viewport
/// picking, direct gizmos and explicit Apply/Cancel boundaries. The feature
/// graph is kept as optional history rather than being the primary interface.
class FamilyEditorV5Page extends StatefulWidget {
  const FamilyEditorV5Page({
    super.key,
    this.initialAsset,
  });

  final FamilyAssetFile? initialAsset;

  @override
  State<FamilyEditorV5Page> createState() => _FamilyEditorV5PageState();
}

enum _Tool {
  select,
  sketch,
  extrude,
  revolve,
  move,
  rotate,
  scale,
  union,
  subtract,
}

enum _CloseAction { save, discard }

final class _TransformSnapshot {
  const _TransformSnapshot({
    required this.x,
    required this.y,
    required this.z,
    required this.rotation,
    required this.scale,
  });

  final double x;
  final double y;
  final double z;
  final double rotation;
  final double scale;
}

class _FamilyEditorV5PageState extends State<FamilyEditorV5Page> {
  late FamilyDocument _document;
  late final TextEditingController _nameController;

  String? _assetPath;
  String? _selectedTypeId;
  String? _selectedFeatureId;
  String? _activeSketchId;
  _Tool _tool = _Tool.select;
  bool _dirty = false;
  bool _showHistory = false;
  bool _showAdvancedSketch = false;
  String? _status;

  final List<FamilyDocument> _undo = <FamilyDocument>[];
  final List<FamilyDocument> _redo = <FamilyDocument>[];
  FamilyDocument? _operationBaseDocument;
  bool _operationBaseDirty = false;

  String? _draftFeatureId;
  String? _profileId;
  String? _transformSourceId;
  String? _booleanBaseId;
  String? _booleanToolId;
  String _extrudeDepth = '1.0';
  String _revolveAngle = '360';
  String _tx = '0';
  String _ty = '0';
  String _tz = '0';
  String _rotation = '0';
  String _scale = '1';
  _TransformSnapshot? _gizmoStart;

  String? _previewKey;
  Future<FamilyEvaluatedMesh>? _previewFuture;

  @override
  void initState() {
    super.initState();
    final asset = widget.initialAsset;
    _document = asset?.document ?? FamilyDocument.starter();
    _assetPath = asset?.path;
    _selectedTypeId = asset?.preferredTypeId ?? _document.types.first.id;
    _selectedFeatureId = _lastSolid(_document)?.id;
    _nameController = TextEditingController(text: _document.name);
    _dirty = asset == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  FamilyTypeDefinition get _selectedType {
    for (final type in _document.types) {
      if (type.id == _selectedTypeId) return type;
    }
    return _document.types.first;
  }

  FamilyFeature? get _selectedFeature => _featureById(_selectedFeatureId);

  FamilySketch? get _activeSketch {
    final id = _activeSketchId;
    if (id == null) return null;
    for (final sketch in _document.sketches) {
      if (sketch.id == id) return sketch;
    }
    return null;
  }

  FamilyFeature? _featureById(String? id) {
    if (id == null) return null;
    for (final feature in _document.features) {
      if (feature.id == id) return feature;
    }
    return null;
  }

  void _invalidatePreview() {
    _previewKey = null;
    _previewFuture = null;
  }

  void _setWorkingDocument(FamilyDocument next, {String? status}) {
    setState(() {
      _document = next;
      _dirty = true;
      _status = status;
      _invalidatePreview();
      if (!_document.types.any((type) => type.id == _selectedTypeId)) {
        _selectedTypeId = _document.types.first.id;
      }
      if (!_document.features.any((feature) => feature.id == _selectedFeatureId)) {
        _selectedFeatureId = _lastSolid(_document)?.id;
      }
    });
  }

  void _commitDocument(FamilyDocument next, {String? status}) {
    if (next.toJsonText() == _document.toJsonText()) return;
    _undo.add(_document);
    _redo.clear();
    _setWorkingDocument(next, status: status);
  }

  void _undoChange() {
    if (_undo.isEmpty || _tool != _Tool.select) return;
    _redo.add(_document);
    final previous = _undo.removeLast();
    setState(() {
      _document = previous;
      _dirty = true;
      _nameController.text = previous.name;
      _selectedFeatureId = _lastSolid(previous)?.id;
      _invalidatePreview();
    });
  }

  void _redoChange() {
    if (_redo.isEmpty || _tool != _Tool.select) return;
    _undo.add(_document);
    final next = _redo.removeLast();
    setState(() {
      _document = next;
      _dirty = true;
      _nameController.text = next.name;
      _selectedFeatureId = _lastSolid(next)?.id;
      _invalidatePreview();
    });
  }

  void _beginOperation(_Tool tool) {
    if (_tool != _Tool.select) _cancelTool();
    _operationBaseDocument = _document;
    _operationBaseDirty = _dirty;
    _draftFeatureId = null;
    _status = null;

    switch (tool) {
      case _Tool.sketch:
        _enterSketch();
        return;
      case _Tool.extrude:
        _prepareExtrude();
        break;
      case _Tool.revolve:
        _prepareRevolve();
        break;
      case _Tool.move:
      case _Tool.rotate:
      case _Tool.scale:
        _prepareTransform(tool);
        break;
      case _Tool.union:
      case _Tool.subtract:
        _prepareBoolean(tool);
        break;
      case _Tool.select:
        break;
    }
    setState(() {
      _tool = tool;
      _invalidatePreview();
    });
  }

  void _cancelTool() {
    final base = _operationBaseDocument;
    setState(() {
      if (_tool == _Tool.sketch && base != null) {
        _document = base;
        _dirty = _operationBaseDirty;
      }
      _tool = _Tool.select;
      _operationBaseDocument = null;
      _draftFeatureId = null;
      _activeSketchId = null;
      _profileId = null;
      _transformSourceId = null;
      _booleanBaseId = null;
      _booleanToolId = null;
      _gizmoStart = null;
      _status = null;
      _invalidatePreview();
    });
  }

  void _prepareExtrude() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.extrude) {
      _draftFeatureId = selected!.id;
      _profileId = selected.parameters['profileId']?.toString();
      _extrudeDepth = '${selected.parameters['depth'] ?? 1.0}';
      return;
    }
    _draftFeatureId = 'feature-extrude-${DateTime.now().microsecondsSinceEpoch}';
    _profileId = _lastClosedSketchId();
    _extrudeDepth = '1.0';
  }

  void _prepareRevolve() {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.revolve) {
      _draftFeatureId = selected!.id;
      _profileId = selected.parameters['profileId']?.toString();
      _revolveAngle = '${selected.parameters['angle'] ?? 360}';
      return;
    }
    _draftFeatureId = 'feature-revolve-${DateTime.now().microsecondsSinceEpoch}';
    _profileId = _lastClosedSketchId();
    _revolveAngle = '360';
  }

  void _prepareTransform(_Tool tool) {
    final selected = _selectedFeature;
    if (selected?.kind == FamilyFeatureKind.transform) {
      _draftFeatureId = selected!.id;
      _transformSourceId = selected.inputs.isEmpty ? null : selected.inputs.first;
      _tx = '${selected.parameters['translationX'] ?? 0}';
      _ty = '${selected.parameters['translationY'] ?? 0}';
      _tz = '${selected.parameters['translationZ'] ?? 0}';
      _rotation = '${selected.parameters['rotationZ'] ?? 0}';
      _scale = '${selected.parameters['scale'] ?? 1}';
      return;
    }
    _draftFeatureId = 'feature-transform-${DateTime.now().microsecondsSinceEpoch}';
    _transformSourceId = selected != null && _isSolid(selected.kind)
        ? selected.id
        : null;
    _tx = '0';
    _ty = '0';
    _tz = '0';
    _rotation = '0';
    _scale = '1';
    if (_transformSourceId == null) {
      _status = 'Tap the solid you want to ${_toolVerb(tool)}.';
    }
  }

  void _prepareBoolean(_Tool tool) {
    final expected = tool == _Tool.union
        ? FamilyFeatureKind.booleanUnion
        : FamilyFeatureKind.booleanSubtract;
    final selected = _selectedFeature;
    if (selected?.kind == expected) {
      _draftFeatureId = selected!.id;
      _booleanBaseId = selected.inputs.isEmpty ? null : selected.inputs.first;
      _booleanToolId = selected.inputs.length > 1 ? selected.inputs[1] : null;
      return;
    }
    _draftFeatureId = 'feature-boolean-${DateTime.now().microsecondsSinceEpoch}';
    _booleanBaseId = selected != null && _isSolid(selected.kind)
        ? selected.id
        : null;
    _booleanToolId = null;
    _status = _booleanBaseId == null
        ? '1/2 · Tap the Base solid.'
        : '2/2 · Tap the Tool solid.';
  }

  FamilyDocument get _previewDocument {
    switch (_tool) {
      case _Tool.extrude:
        final profile = _profileId;
        if (profile == null || _extrudeDepth.trim().isEmpty) return _document;
        return _withDraftFeature(
          FamilyFeature(
            id: _draftFeatureId!,
            kind: FamilyFeatureKind.extrude,
            label: _editingLabel(FamilyFeatureKind.extrude, 'Extrude'),
            inputs: <String>[profile],
            parameters: <String, Object?>{
              'profileId': profile,
              'depth': _extrudeDepth.trim(),
            },
          ),
        );
      case _Tool.revolve:
        final profile = _profileId;
        if (profile == null || _revolveAngle.trim().isEmpty) return _document;
        return _withDraftFeature(
          FamilyFeature(
            id: _draftFeatureId!,
            kind: FamilyFeatureKind.revolve,
            label: _editingLabel(FamilyFeatureKind.revolve, 'Revolve'),
            inputs: <String>[profile],
            parameters: <String, Object?>{
              'profileId': profile,
              'angle': _revolveAngle.trim(),
            },
          ),
        );
      case _Tool.move:
      case _Tool.rotate:
      case _Tool.scale:
        final source = _transformSourceId;
        if (source == null) return _document;
        return _withDraftFeature(
          FamilyFeature(
            id: _draftFeatureId!,
            kind: FamilyFeatureKind.transform,
            label: _editingLabel(FamilyFeatureKind.transform, 'Transform'),
            inputs: <String>[source],
            parameters: <String, Object?>{
              'translationX': _tx,
              'translationY': _ty,
              'translationZ': _tz,
              'rotationZ': _rotation,
              'scale': _scale,
            },
          ),
        );
      case _Tool.union:
      case _Tool.subtract:
        final base = _booleanBaseId;
        final tool = _booleanToolId;
        if (base == null || tool == null || base == tool) return _document;
        final kind = _tool == _Tool.union
            ? FamilyFeatureKind.booleanUnion
            : FamilyFeatureKind.booleanSubtract;
        return _withDraftFeature(
          FamilyFeature(
            id: _draftFeatureId!,
            kind: kind,
            label: _editingLabel(
              kind,
              kind == FamilyFeatureKind.booleanUnion ? 'Union' : 'Subtract',
            ),
            inputs: <String>[base, tool],
            parameters: <String, Object?>{'operation': kind.name},
          ),
        );
      case _Tool.select:
      case _Tool.sketch:
        return _document;
    }
  }

  String _editingLabel(FamilyFeatureKind kind, String fallback) {
    final current = _featureById(_draftFeatureId);
    if (current?.kind == kind && current!.label.trim().isNotEmpty) {
      return current.label;
    }
    return fallback;
  }

  FamilyDocument _withDraftFeature(FamilyFeature feature) {
    final index = _document.features.indexWhere((item) => item.id == feature.id);
    if (index < 0) {
      return _document.copyWith(
        features: <FamilyFeature>[..._document.features, feature],
      );
    }
    return _document.copyWith(
      features: <FamilyFeature>[
        for (final current in _document.features)
          current.id == feature.id ? feature : current,
      ],
    );
  }

  Future<FamilyEvaluatedMesh> _previewMesh() {
    final preview = _previewDocument;
    final key = '${_selectedType.id}\u001f${preview.toJsonText()}';
    if (_previewFuture != null && _previewKey == key) return _previewFuture!;
    _previewKey = key;
    _previewFuture = () async {
      FamilyDocument evaluated = preview;
      if (preview.features.any(
        (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
      )) {
        evaluated = await FamilyDependencyResolver.resolveFromLibrary(
          preview,
          _selectedType,
        );
      }
      return FamilyGeometryEvaluator.evaluateMesh(evaluated, _selectedType);
    }();
    return _previewFuture!;
  }

  bool get _isCandidatePickMode {
    if (_tool == _Tool.move || _tool == _Tool.rotate || _tool == _Tool.scale) {
      return _transformSourceId == null;
    }
    if (_tool == _Tool.union || _tool == _Tool.subtract) {
      return _booleanBaseId == null || _booleanToolId == null;
    }
    return false;
  }

  Set<String> get _candidateFeatureIds =>
      _eligibleSolids().map((feature) => feature.id).toSet();

  Set<String> get _pickedFeatureIds => <String>{
        if (_transformSourceId != null) _transformSourceId!,
        if (_booleanBaseId != null) _booleanBaseId!,
        if (_booleanToolId != null) _booleanToolId!,
      };

  String? get _viewportPrompt {
    if (_tool == _Tool.move || _tool == _Tool.rotate || _tool == _Tool.scale) {
      if (_transformSourceId == null) {
        return 'Tap a solid, then drag the ${_toolLabel(_tool)} gizmo.';
      }
      return 'Drag the gizmo on the model · release to commit · Cancel to leave tool.';
    }
    if (_tool == _Tool.union || _tool == _Tool.subtract) {
      if (_booleanBaseId == null) return '1/2 · Tap the Base solid.';
      if (_booleanToolId == null) return '2/2 · Tap the Tool solid.';
      return _tool == _Tool.subtract
          ? 'Preview: Tool is cut from Base · Apply or Cancel.'
          : 'Preview: Base and Tool are joined · Apply or Cancel.';
    }
    if (_tool == _Tool.extrude) {
      return 'Live Extrude preview · change Depth, then Apply.';
    }
    if (_tool == _Tool.revolve) {
      return 'Live Revolve preview · change Angle, then Apply.';
    }
    return null;
  }

  FamilyGizmoMode get _gizmoMode => switch (_tool) {
        _Tool.move => FamilyGizmoMode.move,
        _Tool.rotate => FamilyGizmoMode.rotate,
        _Tool.scale => FamilyGizmoMode.scale,
        _ => FamilyGizmoMode.none,
      };

  void _handleViewportFeature(String? featureId) {
    if (featureId == null) return;
    if (_tool == _Tool.select) {
      setState(() {
        _selectedFeatureId = featureId;
        _status = null;
      });
      return;
    }
    if (_tool == _Tool.move || _tool == _Tool.rotate || _tool == _Tool.scale) {
      if (!_eligibleSolids().any((feature) => feature.id == featureId)) return;
      setState(() {
        _transformSourceId = featureId;
        _status = 'Drag the ${_toolLabel(_tool)} gizmo on the model.';
        _invalidatePreview();
      });
      return;
    }
    if (_tool == _Tool.union || _tool == _Tool.subtract) {
      if (!_eligibleSolids().any((feature) => feature.id == featureId)) return;
      setState(() {
        if (_booleanBaseId == null || _booleanBaseId == featureId) {
          _booleanBaseId = featureId;
          _booleanToolId = _booleanToolId == featureId ? null : _booleanToolId;
          _status = '2/2 · Now tap the Tool solid.';
        } else if (_booleanToolId == null) {
          _booleanToolId = featureId;
          _status = 'Boolean preview ready. Apply when it looks right.';
        }
        _invalidatePreview();
      });
    }
  }

  void _onGizmoBegin(FamilyGizmoAxis axis) {
    _gizmoStart = _TransformSnapshot(
      x: _parse(_tx, 0),
      y: _parse(_ty, 0),
      z: _parse(_tz, 0),
      rotation: _parse(_rotation, 0),
      scale: math.max(0.001, _parse(_scale, 1)),
    );
  }

  void _onGizmoChanged(FamilyGizmoAxis axis, double delta) {
    final start = _gizmoStart;
    if (start == null) return;
    setState(() {
      switch (axis) {
        case FamilyGizmoAxis.x:
          _tx = _format(start.x + delta);
          break;
        case FamilyGizmoAxis.y:
          _ty = _format(start.y + delta);
          break;
        case FamilyGizmoAxis.z:
          _tz = _format(start.z + delta);
          break;
        case FamilyGizmoAxis.rotation:
          _rotation = _format(start.rotation + delta);
          break;
        case FamilyGizmoAxis.scale:
          _scale = _format(math.max(0.001, start.scale * math.exp(delta)));
          break;
      }
      _invalidatePreview();
    });
  }

  void _onGizmoEnd(FamilyGizmoAxis axis) {
    _gizmoStart = null;
    _commitTool(stayInTool: true, status: '${_toolLabel(_tool)} committed.');
  }

  void _commitTool({bool stayInTool = false, String? status}) {
    final candidate = _previewDocument;
    if (candidate.toJsonText() == _document.toJsonText()) {
      setState(() => _status = 'Nothing to apply yet.');
      return;
    }
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return;
    }
    _undo.add(_document);
    _redo.clear();
    final committedFeatureId = _draftFeatureId;
    setState(() {
      _document = candidate;
      _dirty = true;
      _selectedFeatureId = committedFeatureId ?? _selectedFeatureId;
      _status = status ?? '${_toolLabel(_tool)} applied.';
      _invalidatePreview();
      if (stayInTool) {
        _operationBaseDocument = _document;
        _operationBaseDirty = true;
        if (_tool == _Tool.move || _tool == _Tool.rotate || _tool == _Tool.scale) {
          _prepareTransform(_tool);
        }
      } else {
        _tool = _Tool.select;
        _operationBaseDocument = null;
        _draftFeatureId = null;
        _transformSourceId = null;
        _booleanBaseId = null;
        _booleanToolId = null;
      }
    });
  }

  void _enterSketch() {
    final selected = _selectedFeature;
    String? sketchId;
    if (selected?.kind == FamilyFeatureKind.profile) {
      sketchId = selected!.parameters['profileId']?.toString();
    }
    if (sketchId != null &&
        _document.sketches.any((sketch) => sketch.id == sketchId)) {
      setState(() {
        _tool = _Tool.sketch;
        _activeSketchId = sketchId;
        _status = 'Sketch · tap empty space to draw; drag a point to reshape.';
      });
      return;
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
    setState(() {
      _tool = _Tool.sketch;
      _activeSketchId = sketch.id;
      _selectedFeatureId = feature.id;
      _document = _document.copyWith(
        sketches: <FamilySketch>[..._document.sketches, sketch],
        features: <FamilyFeature>[..._document.features, feature],
      );
      _dirty = true;
      _status = 'Sketch · draw points or choose Rectangle/Circle.';
      _invalidatePreview();
    });
  }

  void _updateSketch(FamilySketch next) {
    setState(() {
      _document = _document.copyWith(
        sketches: <FamilySketch>[
          for (final sketch in _document.sketches)
            sketch.id == next.id ? next : sketch,
        ],
      );
      _dirty = true;
      _invalidatePreview();
    });
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
    );
  }

  void _moveSketchPoint(int index, FamilySketchPoint point) {
    final sketch = _activeSketch;
    if (sketch == null || index < 0 || index >= sketch.points.length) return;
    final points = <FamilySketchPoint>[...sketch.points];
    points[index] = point.copyWith(id: points[index].id);
    _updateSketch(sketch.copyWith(points: points));
  }

  void _rectangleSketch() {
    final sketch = _activeSketch;
    if (sketch == null) return;
    final width = _typeNumber('width', 1);
    final height = _typeNumber('height', 1);
    final hw = math.max(0.05, width * 0.5);
    final hh = math.max(0.05, height * 0.5);
    _updateSketch(
      sketch.copyWith(
        points: <FamilySketchPoint>[
          FamilySketchPoint(id: '${sketch.id}:point-0', x: -hw, y: -hh),
          FamilySketchPoint(id: '${sketch.id}:point-1', x: hw, y: -hh),
          FamilySketchPoint(id: '${sketch.id}:point-2', x: hw, y: hh),
          FamilySketchPoint(id: '${sketch.id}:point-3', x: -hw, y: hh),
        ],
        closed: true,
      ),
    );
  }

  void _circleSketch() {
    final sketch = _activeSketch;
    if (sketch == null) return;
    final radius = math.max(
      0.05,
      math.min(_typeNumber('width', 1), _typeNumber('height', 1)) * 0.5,
    );
    const segments = 24;
    _updateSketch(
      sketch.copyWith(
        points: <FamilySketchPoint>[
          for (var index = 0; index < segments; index++)
            FamilySketchPoint(
              id: '${sketch.id}:point-$index',
              x: math.cos(index / segments * math.pi * 2) * radius,
              y: math.sin(index / segments * math.pi * 2) * radius,
            ),
        ],
        closed: true,
      ),
    );
  }

  void _toggleSketchClosed() {
    final sketch = _activeSketch;
    if (sketch == null) return;
    if (!sketch.closed && sketch.points.length < 3) {
      setState(() => _status = 'A closed profile needs at least 3 points.');
      return;
    }
    _updateSketch(sketch.copyWith(closed: !sketch.closed));
  }

  void _finishSketch() {
    final sketch = _activeSketch;
    if (sketch == null || !sketch.isValid) {
      setState(() => _status = 'Close the profile before finishing.');
      return;
    }
    final base = _operationBaseDocument;
    if (base != null && base.toJsonText() != _document.toJsonText()) {
      _undo.add(base);
      _redo.clear();
    }
    setState(() {
      _tool = _Tool.select;
      _profileId = sketch.id;
      _activeSketchId = null;
      _operationBaseDocument = null;
      _status = 'Profile ready · choose Extrude or Revolve.';
    });
  }

  String? _lastClosedSketchId() {
    for (var index = _document.sketches.length - 1; index >= 0; index--) {
      if (_document.sketches[index].isValid) return _document.sketches[index].id;
    }
    return null;
  }

  List<FamilyFeature> _eligibleSolids() {
    final draftId = _draftFeatureId;
    final draftIndex = draftId == null
        ? -1
        : _document.features.indexWhere((feature) => feature.id == draftId);
    final limit = draftIndex >= 0 ? draftIndex : _document.features.length;
    return <FamilyFeature>[
      for (var index = 0; index < limit; index++)
        if (_isSolid(_document.features[index].kind)) _document.features[index],
    ];
  }

  Future<void> _importGltf() async {
    if (_tool != _Tool.select) _cancelTool();
    final unitScale = await FamilyImportUnitsDialog.show(context);
    if (!mounted || unitScale == null) return;
    try {
      final imported = await FamilyMeshImporter.pickGltf(unitScale: unitScale);
      if (!mounted || imported == null) return;
      _undo.add(_document);
      _redo.clear();
      setState(() {
        _document = imported.document;
        _assetPath = null;
        _selectedTypeId = imported.document.types.first.id;
        _selectedFeatureId = imported.document.features.last.id;
        _nameController.text = imported.document.name;
        _dirty = true;
        _status = 'Imported ${imported.vertexCount} vertices · ${imported.faceCount} faces.';
        _invalidatePreview();
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Import failed: $error');
    }
  }

  Future<void> _addNestedFamily() async {
    if (_tool != _Tool.select) _cancelTool();
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
    _commitDocument(candidate, status: '${feature.label} added.');
  }

  Future<void> _deleteSelected() async {
    if (_tool != _Tool.select) return;
    final feature = _selectedFeature;
    if (feature == null || _document.features.length <= 1) return;
    final used = _document.features.any(
      (candidate) =>
          candidate.id != feature.id && candidate.inputs.contains(feature.id),
    );
    if (used) {
      setState(() => _status = 'This feature is used by a later operation. Edit that operation first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${_featureName(feature)}?'),
        content: const Text('This removes the selected operation from the family history.'),
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
    if (!mounted || confirmed != true) return;
    final candidate = _document.copyWith(
      features: <FamilyFeature>[
        for (final current in _document.features)
          if (current.id != feature.id) current,
      ],
    );
    _selectedFeatureId = _lastSolid(candidate)?.id;
    _commitDocument(candidate, status: 'Feature deleted.');
  }

  void _selectType(String? id) {
    if (id == null) return;
    setState(() {
      _selectedTypeId = id;
      _invalidatePreview();
    });
  }

  void _updateDimension(String id, String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value <= 0) {
      setState(() => _status = '$id must be a positive number.');
      return;
    }
    FamilyParameterDefinition? parameter;
    for (final item in _document.parameters) {
      if (item.id == id) {
        parameter = item;
        break;
      }
    }
    if (parameter == null || parameter.hasFormula) return;
    final selected = _selectedType;
    final replacement = selected.copyWith(
      values: <String, Object?>{...selected.values, id: value},
    );
    _commitDocument(
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
    final next = FamilyTypeDefinition(
      id: 'type-${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} Copy',
      values: Map<String, Object?>.from(source.values),
    );
    _selectedTypeId = next.id;
    _commitDocument(
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
    if (_tool != _Tool.select) {
      setState(() => _status = 'Finish or cancel the active tool before saving.');
      return false;
    }
    final name = _nameController.text.trim();
    final candidate = name.isEmpty ? _document : _document.copyWith(name: name);
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      setState(() => _status = validation.errors.first);
      return false;
    }
    setState(() => _status = 'Saving…');
    try {
      await _preflightDependencies(candidate);
      final path = _assetPath == null
          ? await FamilyFileStore.save(candidate)
          : await FamilyFileStore.saveAsset(candidate, existingPath: _assetPath!);
      if (!mounted || path == null) return false;
      setState(() {
        _document = candidate;
        _assetPath = path;
        _dirty = false;
        _status = 'Saved.';
      });
      return true;
    } catch (error) {
      if (mounted) setState(() => _status = 'Save failed: $error');
      return false;
    }
  }

  Future<void> _requestClose() async {
    if (_tool != _Tool.select) {
      _cancelTool();
      return;
    }
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
      canPop: !_dirty && _tool == _Tool.select,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              return Column(
                children: <Widget>[
                  _buildRibbon(),
                  const Divider(height: 1),
                  Expanded(
                    child: wide
                        ? Row(
                            children: <Widget>[
                              Expanded(child: _buildWorkspace()),
                              const VerticalDivider(width: 1),
                              SizedBox(width: 330, child: _buildInspector()),
                            ],
                          )
                        : Column(
                            children: <Widget>[
                              Expanded(child: _buildWorkspace()),
                              const Divider(height: 1),
                              SizedBox(height: 265, child: _buildInspector()),
                            ],
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        tooltip: _tool == _Tool.select ? 'Close family' : 'Cancel tool',
        onPressed: _requestClose,
        icon: Icon(_tool == _Tool.select ? Icons.close : Icons.arrow_back),
      ),
      titleSpacing: 4,
      title: SizedBox(
        width: 300,
        child: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Family name',
          ),
          style: Theme.of(context).textTheme.titleMedium,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Undo',
          onPressed: _undo.isEmpty || _tool != _Tool.select ? null : _undoChange,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: _redo.isEmpty || _tool != _Tool.select ? null : _redoChange,
          icon: const Icon(Icons.redo),
        ),
        IconButton(
          tooltip: 'Model history',
          onPressed: () => setState(() => _showHistory = !_showHistory),
          icon: Icon(_showHistory ? Icons.history_toggle_off : Icons.history),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _tool == _Tool.select ? _save : null,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildRibbon() {
    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: <Widget>[
          _RibbonGroup(
            label: 'CREATE',
            children: <Widget>[
              _ToolAction(
                icon: Icons.polyline_outlined,
                label: 'Sketch',
                selected: _tool == _Tool.sketch,
                onTap: () => _beginOperation(_Tool.sketch),
              ),
              _ToolAction(
                icon: Icons.height,
                label: 'Extrude',
                selected: _tool == _Tool.extrude,
                onTap: () => _beginOperation(_Tool.extrude),
              ),
              _ToolAction(
                icon: Icons.rotate_right_outlined,
                label: 'Revolve',
                selected: _tool == _Tool.revolve,
                onTap: () => _beginOperation(_Tool.revolve),
              ),
            ],
          ),
          _RibbonGroup(
            label: 'MODIFY',
            children: <Widget>[
              _ToolAction(
                icon: Icons.open_with_outlined,
                label: 'Move',
                selected: _tool == _Tool.move,
                onTap: () => _beginOperation(_Tool.move),
              ),
              _ToolAction(
                icon: Icons.rotate_90_degrees_ccw_outlined,
                label: 'Rotate',
                selected: _tool == _Tool.rotate,
                onTap: () => _beginOperation(_Tool.rotate),
              ),
              _ToolAction(
                icon: Icons.open_in_full,
                label: 'Scale',
                selected: _tool == _Tool.scale,
                onTap: () => _beginOperation(_Tool.scale),
              ),
            ],
          ),
          _RibbonGroup(
            label: 'COMBINE',
            children: <Widget>[
              _ToolAction(
                icon: Icons.merge_type_outlined,
                label: 'Union',
                selected: _tool == _Tool.union,
                onTap: () => _beginOperation(_Tool.union),
              ),
              _ToolAction(
                icon: Icons.call_split_outlined,
                label: 'Subtract',
                selected: _tool == _Tool.subtract,
                onTap: () => _beginOperation(_Tool.subtract),
              ),
            ],
          ),
          _RibbonGroup(
            label: 'INSERT',
            children: <Widget>[
              _ToolAction(
                icon: Icons.account_tree_outlined,
                label: 'Nested',
                onTap: _addNestedFamily,
              ),
              _ToolAction(
                icon: Icons.file_upload_outlined,
                label: 'Import',
                onTap: _importGltf,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Column(
      children: <Widget>[
        if (_status != null)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            padding: const EdgeInsets.all(8),
            child: _tool == _Tool.sketch && _activeSketch != null
                ? _buildSketchWorkspace(_activeSketch!)
                : _buildViewport(),
          ),
        ),
        if (_showHistory) _buildHistory(),
      ],
    );
  }

  Widget _buildViewport() {
    return FutureBuilder<FamilyEvaluatedMesh>(
      future: _previewMesh(),
      builder: (context, snapshot) {
        final mesh = snapshot.data;
        if (mesh == null) {
          if (snapshot.hasError) {
            return Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text('Preview error: ${snapshot.error}'),
                ),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return FamilyAuthoringViewport(
          document: _previewDocument,
          type: _selectedType,
          mesh: mesh,
          mode: _isCandidatePickMode
              ? FamilyAuthoringViewportMode.pickFeatures
              : FamilyAuthoringViewportMode.result,
          candidateFeatureIds: _candidateFeatureIds,
          selectedFeatureIds: _pickedFeatureIds,
          gizmoFeatureId: _draftFeatureId,
          gizmoMode: _transformSourceId == null ? FamilyGizmoMode.none : _gizmoMode,
          prompt: _viewportPrompt,
          onFeatureSelected: _handleViewportFeature,
          onGizmoBegin: _onGizmoBegin,
          onGizmoChanged: _onGizmoChanged,
          onGizmoEnd: _onGizmoEnd,
        );
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
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const Text('SKETCH', style: TextStyle(fontWeight: FontWeight.w800)),
                FilledButton.tonalIcon(
                  onPressed: _rectangleSketch,
                  icon: const Icon(Icons.crop_square),
                  label: const Text('Rectangle'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _circleSketch,
                  icon: const Icon(Icons.circle_outlined),
                  label: const Text('Circle'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleSketchClosed,
                  icon: Icon(sketch.closed ? Icons.lock_open : Icons.join_full),
                  label: Text(sketch.closed ? 'Reopen' : 'Close'),
                ),
                TextButton.icon(
                  onPressed: () => _updateSketch(
                    sketch.copyWith(
                      points: const <FamilySketchPoint>[],
                      closed: false,
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear'),
                ),
                OutlinedButton(
                  onPressed: () => setState(
                    () => _showAdvancedSketch = !_showAdvancedSketch,
                  ),
                  child: Text(_showAdvancedSketch ? 'Hide constraints' : 'Constraints'),
                ),
                FilledButton.icon(
                  onPressed: sketch.isValid ? _finishSketch : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Finish'),
                ),
                TextButton(
                  onPressed: _cancelTool,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FamilySketchCanvas(
                    sketch: sketch,
                    onAddPoint: _addSketchPoint,
                    onMovePoint: _moveSketchPoint,
                  ),
                ),
                if (_showAdvancedSketch) ...<Widget>[
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 330,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10),
                      child: FamilyConstraintsPanel(
                        document: _document,
                        type: _selectedType,
                        selectedSketchId: sketch.id,
                        onChanged: (next) => _setWorkingDocument(next),
                        onStatus: (message) => setState(() => _status = message),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return SizedBox(
      height: 70,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemCount: _document.features.length,
          separatorBuilder: (_, __) => const Icon(Icons.chevron_right, size: 17),
          itemBuilder: (context, index) {
            final feature = _document.features[index];
            return ChoiceChip(
              selected: feature.id == _selectedFeatureId,
              avatar: Icon(_featureIcon(feature.kind), size: 16),
              label: Text(_featureName(feature)),
              onSelected: (_) => setState(() {
                _selectedFeatureId = feature.id;
                _tool = _Tool.select;
              }),
            );
          },
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
              _Tool.select => _buildSelectionInspector(),
              _Tool.sketch => _commandCard(
                  title: 'Sketch',
                  subtitle: 'Draw in the large canvas',
                  body: const Text('Use Rectangle/Circle or tap points manually, then Finish.'),
                ),
              _Tool.extrude => _buildExtrudeInspector(),
              _Tool.revolve => _buildRevolveInspector(),
              _Tool.move || _Tool.rotate || _Tool.scale => _buildTransformInspector(),
              _Tool.union || _Tool.subtract => _buildBooleanInspector(),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard() {
    return _commandCard(
      title: 'Family type',
      subtitle: 'Common dimensions',
      body: Column(
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
                  onChanged: _tool == _Tool.select ? _selectType : null,
                ),
              ),
              const SizedBox(width: 5),
              IconButton.filledTonal(
                tooltip: 'Duplicate type',
                onPressed: _tool == _Tool.select ? _duplicateType : null,
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(child: _dimensionField('width')),
              const SizedBox(width: 5),
              Expanded(child: _dimensionField('depth')),
              const SizedBox(width: 5),
              Expanded(child: _dimensionField('height')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dimensionField(String id) {
    FamilyParameterDefinition? parameter;
    for (final item in _document.parameters) {
      if (item.id == id) parameter = item;
    }
    final value = _selectedType.values[id] ?? parameter?.defaultValue ?? 1.0;
    return TextFormField(
      key: ValueKey<String>('${_selectedType.id}:$id:$value'),
      initialValue: '$value',
      enabled: _tool == _Tool.select && parameter?.hasFormula != true,
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

  Widget _buildSelectionInspector() {
    final selected = _selectedFeature;
    return _commandCard(
      title: selected == null ? 'Select' : _featureName(selected),
      subtitle: selected == null
          ? 'Tap the model or choose a tool'
          : selected.kind.name,
      body: selected == null
          ? const Text('Create a sketch, or tap the model to edit the latest solid.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(_featureDescription(selected)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (selected.kind == FamilyFeatureKind.profile)
                      FilledButton.tonal(
                        onPressed: () => _beginOperation(_Tool.sketch),
                        child: const Text('Edit sketch'),
                      ),
                    if (selected.kind == FamilyFeatureKind.extrude)
                      FilledButton.tonal(
                        onPressed: () => _beginOperation(_Tool.extrude),
                        child: const Text('Edit Extrude'),
                      ),
                    if (selected.kind == FamilyFeatureKind.revolve)
                      FilledButton.tonal(
                        onPressed: () => _beginOperation(_Tool.revolve),
                        child: const Text('Edit Revolve'),
                      ),
                    if (_isSolid(selected.kind))
                      OutlinedButton(
                        onPressed: () => _beginOperation(_Tool.move),
                        child: const Text('Move'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildExtrudeInspector() {
    final sketches = _document.sketches.where((sketch) => sketch.isValid).toList();
    return _commandCard(
      title: 'Extrude',
      subtitle: 'Closed profile → solid · live preview',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (sketches.isEmpty)
            FilledButton.icon(
              onPressed: () {
                _cancelTool();
                _beginOperation(_Tool.sketch);
              },
              icon: const Icon(Icons.polyline_outlined),
              label: const Text('Draw profile first'),
            )
          else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(_profileId),
              initialValue: sketches.any((sketch) => sketch.id == _profileId)
                  ? _profileId
                  : sketches.last.id,
              decoration: const InputDecoration(
                labelText: 'Profile',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final sketch in sketches)
                  DropdownMenuItem(value: sketch.id, child: Text(sketch.name)),
              ],
              onChanged: (id) => setState(() {
                _profileId = id;
                _invalidatePreview();
              }),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey<String>('extrude:$_extrudeDepth'),
              initialValue: _extrudeDepth,
              decoration: const InputDecoration(
                labelText: 'Depth',
                suffixText: 'm or parameter',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _extrudeDepth = value;
                _invalidatePreview();
              }),
            ),
            if (double.tryParse(_extrudeDepth) != null)
              Slider(
                value: double.parse(_extrudeDepth).clamp(0.01, 10.0).toDouble(),
                min: 0.01,
                max: 10.0,
                onChanged: (value) => setState(() {
                  _extrudeDepth = _format(value);
                  _invalidatePreview();
                }),
              ),
            _applyCancelRow('Apply Extrude'),
          ],
        ],
      ),
    );
  }

  Widget _buildRevolveInspector() {
    final sketches = _document.sketches.where((sketch) => sketch.isValid).toList();
    return _commandCard(
      title: 'Revolve',
      subtitle: 'Closed profile → revolved solid · live preview',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (sketches.isEmpty)
            FilledButton.icon(
              onPressed: () {
                _cancelTool();
                _beginOperation(_Tool.sketch);
              },
              icon: const Icon(Icons.polyline_outlined),
              label: const Text('Draw profile first'),
            )
          else ...<Widget>[
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(_profileId),
              initialValue: sketches.any((sketch) => sketch.id == _profileId)
                  ? _profileId
                  : sketches.last.id,
              decoration: const InputDecoration(
                labelText: 'Profile',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final sketch in sketches)
                  DropdownMenuItem(value: sketch.id, child: Text(sketch.name)),
              ],
              onChanged: (id) => setState(() {
                _profileId = id;
                _invalidatePreview();
              }),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey<String>('revolve:$_revolveAngle'),
              initialValue: _revolveAngle,
              decoration: const InputDecoration(
                labelText: 'Angle',
                suffixText: '°',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _revolveAngle = value;
                _invalidatePreview();
              }),
            ),
            Slider(
              value: _parse(_revolveAngle, 360).clamp(1.0, 360.0).toDouble(),
              min: 1,
              max: 360,
              onChanged: (value) => setState(() {
                _revolveAngle = _format(value);
                _invalidatePreview();
              }),
            ),
            _applyCancelRow('Apply Revolve'),
          ],
        ],
      ),
    );
  }

  Widget _buildTransformInspector() {
    final source = _featureById(_transformSourceId);
    return _commandCard(
      title: _toolLabel(_tool),
      subtitle: source == null
          ? 'Tap a solid in the viewport'
          : 'Drag the gizmo directly on the model',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (source == null)
            const Text('The viewport is in pick mode. Tap the solid you want to modify.')
          else ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('Source: ${_featureName(source)}')),
                TextButton(
                  onPressed: () => setState(() {
                    _transformSourceId = null;
                    _invalidatePreview();
                  }),
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 7),
            if (_tool == _Tool.move)
              Row(
                children: <Widget>[
                  Expanded(child: _numericDraftField('X', _tx, (v) => _tx = v)),
                  const SizedBox(width: 5),
                  Expanded(child: _numericDraftField('Y', _ty, (v) => _ty = v)),
                  const SizedBox(width: 5),
                  Expanded(child: _numericDraftField('Z', _tz, (v) => _tz = v)),
                ],
              ),
            if (_tool == _Tool.rotate)
              _numericDraftField('Rotation Z°', _rotation, (v) => _rotation = v),
            if (_tool == _Tool.scale)
              _numericDraftField('Scale', _scale, (v) => _scale = v),
            const SizedBox(height: 8),
            const Text('Tip: drag the coloured handles in the viewport. Releasing a gizmo commits one undo step.'),
            const SizedBox(height: 8),
            TextButton(onPressed: _cancelTool, child: const Text('Done / leave tool')),
          ],
        ],
      ),
    );
  }

  Widget _numericDraftField(
    String label,
    String value,
    ValueChanged<String> assign,
  ) {
    return TextFormField(
      key: ValueKey<String>('$label:$value'),
      initialValue: value,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (raw) => setState(() {
        assign(raw);
        _invalidatePreview();
      }),
      onFieldSubmitted: (_) => _commitTool(stayInTool: true),
    );
  }

  Widget _buildBooleanInspector() {
    final subtract = _tool == _Tool.subtract;
    final base = _featureById(_booleanBaseId);
    final tool = _featureById(_booleanToolId);
    return _commandCard(
      title: subtract ? 'Subtract' : 'Union',
      subtitle: subtract ? 'Base − Tool' : 'Base + Tool',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _pickStep(
            number: '1',
            label: 'Base',
            feature: base,
            onChange: () => setState(() {
              _booleanBaseId = null;
              _booleanToolId = null;
              _invalidatePreview();
            }),
          ),
          const SizedBox(height: 7),
          _pickStep(
            number: '2',
            label: 'Tool',
            feature: tool,
            onChange: () => setState(() {
              _booleanToolId = null;
              _invalidatePreview();
            }),
          ),
          const SizedBox(height: 10),
          if (base != null && tool != null)
            _applyCancelRow(subtract ? 'Apply Subtract' : 'Apply Union')
          else
            OutlinedButton(
              onPressed: _cancelTool,
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }

  Widget _pickStep({
    required String number,
    required String label,
    required FamilyFeature? feature,
    required VoidCallback onChange,
  }) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(radius: 13, child: Text(number)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feature == null ? '$label · tap in viewport' : '$label · ${_featureName(feature)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (feature != null)
            TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }

  Widget _applyCancelRow(String applyLabel) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            onPressed: _cancelTool,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _commitTool,
            icon: const Icon(Icons.check),
            label: Text(applyLabel),
          ),
        ),
      ],
    );
  }

  Widget _commandCard({
    required String title,
    required String subtitle,
    required Widget body,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            body,
          ],
        ),
      ),
    );
  }

  double _typeNumber(String id, double fallback) {
    final raw = _selectedType.values[id];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? fallback;
  }

  static double _parse(String raw, double fallback) =>
      double.tryParse(raw.trim().replaceAll(',', '.')) ?? fallback;

  static String _format(double value) {
    final fixed = value.toStringAsFixed(4);
    return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static bool _isSolid(FamilyFeatureKind kind) =>
      kind == FamilyFeatureKind.box ||
      kind == FamilyFeatureKind.extrude ||
      kind == FamilyFeatureKind.revolve ||
      kind == FamilyFeatureKind.booleanUnion ||
      kind == FamilyFeatureKind.booleanSubtract ||
      kind == FamilyFeatureKind.transform ||
      kind == FamilyFeatureKind.freeformMesh ||
      kind == FamilyFeatureKind.nestedFamily;

  static FamilyFeature? _lastSolid(FamilyDocument document) {
    for (var index = document.features.length - 1; index >= 0; index--) {
      if (_isSolid(document.features[index].kind)) return document.features[index];
    }
    return null;
  }

  static String _featureName(FamilyFeature feature) =>
      feature.label.trim().isEmpty ? _kindLabel(feature.kind) : feature.label.trim();

  static String _kindLabel(FamilyFeatureKind kind) => switch (kind) {
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

  static IconData _featureIcon(FamilyFeatureKind kind) => switch (kind) {
        FamilyFeatureKind.box => Icons.view_in_ar_outlined,
        FamilyFeatureKind.profile => Icons.polyline_outlined,
        FamilyFeatureKind.extrude => Icons.height,
        FamilyFeatureKind.revolve => Icons.rotate_right_outlined,
        FamilyFeatureKind.booleanUnion => Icons.merge_type_outlined,
        FamilyFeatureKind.booleanSubtract => Icons.call_split_outlined,
        FamilyFeatureKind.transform => Icons.open_with_outlined,
        FamilyFeatureKind.freeformMesh => Icons.category_outlined,
        FamilyFeatureKind.nestedFamily => Icons.account_tree_outlined,
      };

  static String _featureDescription(FamilyFeature feature) => switch (feature.kind) {
        FamilyFeatureKind.box => 'Base parametric solid.',
        FamilyFeatureKind.profile => '2D sketch used by solid features.',
        FamilyFeatureKind.extrude => 'Closed profile extruded into a solid.',
        FamilyFeatureKind.revolve => 'Closed profile revolved around its axis.',
        FamilyFeatureKind.booleanUnion => 'Two solids joined into one result.',
        FamilyFeatureKind.booleanSubtract => 'Tool solid cut from the Base solid.',
        FamilyFeatureKind.transform => 'Moved, rotated or scaled result.',
        FamilyFeatureKind.freeformMesh => 'Imported render-ready mesh.',
        FamilyFeatureKind.nestedFamily => 'Reusable child family instance.',
      };

  static String _dimensionLabel(String id) => switch (id) {
        'width' => 'W',
        'depth' => 'D',
        'height' => 'H',
        _ => id,
      };

  static String _toolLabel(_Tool tool) => switch (tool) {
        _Tool.select => 'Select',
        _Tool.sketch => 'Sketch',
        _Tool.extrude => 'Extrude',
        _Tool.revolve => 'Revolve',
        _Tool.move => 'Move',
        _Tool.rotate => 'Rotate',
        _Tool.scale => 'Scale',
        _Tool.union => 'Union',
        _Tool.subtract => 'Subtract',
      };

  static String _toolVerb(_Tool tool) => switch (tool) {
        _Tool.move => 'move',
        _Tool.rotate => 'rotate',
        _Tool.scale => 'scale',
        _ => 'modify',
      };
}

class _RibbonGroup extends StatelessWidget {
  const _RibbonGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: <Widget>[
          Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: children)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ToolAction extends StatelessWidget {
  const _ToolAction({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 67,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 23),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
