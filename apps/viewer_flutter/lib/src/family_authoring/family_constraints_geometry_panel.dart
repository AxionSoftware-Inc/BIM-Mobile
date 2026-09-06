import 'package:flutter/material.dart';

import 'family_constraint_models.dart';
import 'family_constraint_solver.dart';
import 'family_document.dart';
import 'family_validation.dart';

/// Tablet-friendly authoring surface for geometric constraints.
///
/// This widget only commits documents that pass the same semantic validator as
/// save/placement. Constraint expressions are therefore live geometry, not
/// decorative metadata.
class FamilyConstraintsPanel extends StatelessWidget {
  const FamilyConstraintsPanel({
    super.key,
    required this.document,
    required this.type,
    required this.selectedSketchId,
    required this.onChanged,
    required this.onStatus,
  });

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final String? selectedSketchId;
  final ValueChanged<FamilyDocument> onChanged;
  final ValueChanged<String> onStatus;

  FamilySketch? get _sketch {
    final id = selectedSketchId;
    if (id == null) return null;
    for (final sketch in document.sketches) {
      if (sketch.id == id) return sketch;
    }
    return null;
  }

  List<FamilyReferencePlane> get _planes {
    final sketch = _sketch;
    if (sketch == null) return const <FamilyReferencePlane>[];
    return document.referencePlanes
        .where((plane) => plane.sketchId == sketch.id)
        .toList(growable: false);
  }

  List<FamilySketchConstraint> get _constraints {
    final sketch = _sketch;
    if (sketch == null) return const <FamilySketchConstraint>[];
    return document.constraints
        .where((constraint) => constraint.sketchId == sketch.id)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final sketch = _sketch;
    final theme = Theme.of(context);
    if (sketch == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Create or select a profile to author geometric constraints.'),
        ),
      );
    }

    Map<String, double> offsets = const <String, double>{};
    String? solveError;
    try {
      offsets = FamilyConstraintSolver.solveSketch(document, type, sketch)
          .referencePlaneOffsets;
    } catch (error) {
      solveError = '$error';
    }

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
                        'Reference planes & constraints',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sketch.name} · ${sketch.points.length} points',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (sketch.points.length == 4)
                  TextButton.icon(
                    onPressed: () => _quickRectangle(sketch),
                    icon: const Icon(Icons.crop_square_outlined),
                    label: const Text('Parametric rectangle'),
                  ),
              ],
            ),
            if (solveError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                solveError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _addPlane(context, sketch),
                  icon: const Icon(Icons.vertical_align_center_outlined),
                  label: const Text('Reference plane'),
                ),
                OutlinedButton.icon(
                  onPressed: sketch.points.isEmpty
                      ? null
                      : () => _addConstraint(context, sketch),
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Constraint'),
                ),
              ],
            ),
            if (_planes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('Reference planes', style: theme.textTheme.labelLarge),
              for (final plane in _planes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    plane.axis == FamilyReferencePlaneAxis.x
                        ? Icons.swap_horiz
                        : Icons.swap_vert,
                  ),
                  title: Text(plane.name),
                  subtitle: Text(
                    '${plane.axis.name.toUpperCase()} = ${plane.expression}'
                    '${offsets.containsKey(plane.id) ? '  →  ${_number(offsets[plane.id]!)} m' : ''}',
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Edit reference plane',
                        onPressed: () => _editPlane(context, sketch, plane),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete reference plane',
                        onPressed: () => _deletePlane(plane),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
            if (_constraints.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text('Constraints', style: theme.textTheme.labelLarge),
              for (final constraint in _constraints)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_constraintIcon(constraint.kind)),
                  title: Text(_constraintTitle(constraint.kind)),
                  subtitle: Text(_constraintSummary(constraint)),
                  trailing: IconButton(
                    tooltip: 'Delete constraint',
                    onPressed: () => _deleteConstraint(constraint),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addPlane(BuildContext context, FamilySketch sketch) async {
    final draft = await showDialog<_PlaneDraft>(
      context: context,
      builder: (_) => const _ReferencePlaneDialog(),
    );
    if (draft == null) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    _commit(
      document.copyWith(
        referencePlanes: <FamilyReferencePlane>[
          ...document.referencePlanes,
          FamilyReferencePlane(
            id: 'plane-$stamp',
            name: draft.name,
            sketchId: sketch.id,
            axis: draft.axis,
            expression: draft.expression,
          ),
        ],
      ),
      'Reference plane added',
    );
  }

  Future<void> _editPlane(
    BuildContext context,
    FamilySketch sketch,
    FamilyReferencePlane plane,
  ) async {
    final draft = await showDialog<_PlaneDraft>(
      context: context,
      builder: (_) => _ReferencePlaneDialog(plane: plane),
    );
    if (draft == null) return;
    _commit(
      document.copyWith(
        referencePlanes: <FamilyReferencePlane>[
          for (final current in document.referencePlanes)
            current.id == plane.id
                ? plane.copyWith(
                    name: draft.name,
                    axis: draft.axis,
                    expression: draft.expression,
                  )
                : current,
        ],
      ),
      'Reference plane updated',
    );
  }

  void _deletePlane(FamilyReferencePlane plane) {
    _commit(
      document.copyWith(
        referencePlanes: <FamilyReferencePlane>[
          for (final current in document.referencePlanes)
            if (current.id != plane.id) current,
        ],
        constraints: <FamilySketchConstraint>[
          for (final constraint in document.constraints)
            if (constraint.referencePlaneId != plane.id) constraint,
        ],
      ),
      'Reference plane deleted',
    );
  }

  Future<void> _addConstraint(
    BuildContext context,
    FamilySketch sketch,
  ) async {
    final stableSketch = _stableSketch(sketch);
    final draft = await showDialog<_ConstraintDraft>(
      context: context,
      builder: (_) => _ConstraintDialog(
        sketch: stableSketch,
        planes: _planes,
      ),
    );
    if (draft == null) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final base = _replaceSketch(document, stableSketch);
    String? pointId(int? index) =>
        index == null ? null : stableSketch.points[index].id;
    _commit(
      base.copyWith(
        constraints: <FamilySketchConstraint>[
          ...base.constraints,
          FamilySketchConstraint(
            id: 'constraint-$stamp',
            sketchId: stableSketch.id,
            kind: draft.kind,
            pointAIndex: draft.pointA,
            pointAId: pointId(draft.pointA),
            pointBIndex: draft.pointB,
            pointBId: pointId(draft.pointB),
            pointCIndex: draft.pointC,
            pointCId: pointId(draft.pointC),
            pointDIndex: draft.pointD,
            pointDId: pointId(draft.pointD),
            referencePlaneId: draft.referencePlaneId,
            expression: draft.expression,
          ),
        ],
      ),
      'Constraint added',
    );
  }

  void _deleteConstraint(FamilySketchConstraint constraint) {
    _commit(
      document.copyWith(
        constraints: <FamilySketchConstraint>[
          for (final current in document.constraints)
            if (current.id != constraint.id) current,
        ],
      ),
      'Constraint deleted',
    );
  }

  void _quickRectangle(FamilySketch sketch) {
    final stableSketch = _stableSketch(sketch);
    final stableDocument = _replaceSketch(document, stableSketch);
    final ownedPlaneIds = stableDocument.referencePlanes
        .where((plane) => plane.sketchId == stableSketch.id)
        .map((plane) => plane.id)
        .toSet();
    final cleaned = stableDocument.copyWith(
      referencePlanes: <FamilyReferencePlane>[
        for (final plane in stableDocument.referencePlanes)
          if (plane.sketchId != stableSketch.id) plane,
      ],
      constraints: <FamilySketchConstraint>[
        for (final constraint in stableDocument.constraints)
          if (constraint.sketchId != stableSketch.id &&
              !ownedPlaneIds.contains(constraint.referencePlaneId))
            constraint,
      ],
    );
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final left = 'rect-left-$stamp';
    final right = 'rect-right-$stamp';
    final bottom = 'rect-bottom-$stamp';
    final top = 'rect-top-$stamp';
    final planes = <FamilyReferencePlane>[
      FamilyReferencePlane(
        id: left,
        name: 'Left',
        sketchId: stableSketch.id,
        axis: FamilyReferencePlaneAxis.x,
        expression: '-width / 2',
      ),
      FamilyReferencePlane(
        id: right,
        name: 'Right',
        sketchId: stableSketch.id,
        axis: FamilyReferencePlaneAxis.x,
        expression: 'width / 2',
      ),
      FamilyReferencePlane(
        id: bottom,
        name: 'Bottom',
        sketchId: stableSketch.id,
        axis: FamilyReferencePlaneAxis.y,
        expression: '0',
      ),
      FamilyReferencePlane(
        id: top,
        name: 'Top',
        sketchId: stableSketch.id,
        axis: FamilyReferencePlaneAxis.y,
        expression: 'height',
      ),
    ];
    FamilySketchConstraint pin(
      String suffix,
      int point,
      String planeId,
    ) =>
        FamilySketchConstraint(
          id: 'rect-$suffix-$stamp',
          sketchId: stableSketch.id,
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: point,
          pointAId: stableSketch.points[point].id,
          referencePlaneId: planeId,
        );
    final constraints = <FamilySketchConstraint>[
      pin('p0-left', 0, left),
      pin('p3-left', 3, left),
      pin('p1-right', 1, right),
      pin('p2-right', 2, right),
      pin('p0-bottom', 0, bottom),
      pin('p1-bottom', 1, bottom),
      pin('p2-top', 2, top),
      pin('p3-top', 3, top),
    ];
    _commit(
      cleaned.copyWith(
        referencePlanes: <FamilyReferencePlane>[
          ...cleaned.referencePlanes,
          ...planes,
        ],
        constraints: <FamilySketchConstraint>[
          ...cleaned.constraints,
          ...constraints,
        ],
      ),
      'Parametric rectangle linked to width and height',
    );
  }

  FamilySketch _stableSketch(FamilySketch sketch) => sketch.copyWith(
        points: <FamilySketchPoint>[
          for (var index = 0; index < sketch.points.length; index++)
            sketch.points[index].id.trim().isEmpty
                ? sketch.points[index].copyWith(id: '${sketch.id}:point-$index')
                : sketch.points[index],
        ],
      );

  FamilyDocument _replaceSketch(FamilyDocument source, FamilySketch sketch) =>
      source.copyWith(
        sketches: <FamilySketch>[
          for (final current in source.sketches)
            current.id == sketch.id ? sketch : current,
        ],
      );

  void _commit(FamilyDocument candidate, String success) {
    final validation = FamilyDocumentValidator.validate(candidate);
    if (!validation.isValid) {
      onStatus(validation.errors.first);
      return;
    }
    onChanged(candidate);
    onStatus(success);
  }

  String _constraintSummary(FamilySketchConstraint constraint) {
    final a = _pointNumber(constraint.pointAId, constraint.pointAIndex);
    final b = _pointNumber(constraint.pointBId, constraint.pointBIndex);
    final c = _pointNumber(constraint.pointCId, constraint.pointCIndex);
    final d = _pointNumber(constraint.pointDId, constraint.pointDIndex);
    switch (constraint.kind) {
      case FamilySketchConstraintKind.pointOnReferencePlane:
        final plane =
            _planes.where((item) => item.id == constraint.referencePlaneId);
        final planeName = plane.isEmpty ? 'missing plane' : plane.first.name;
        return 'Point $a → $planeName';
      case FamilySketchConstraintKind.distance:
        return 'Point $a ↔ Point $b = ${constraint.expression}';
      case FamilySketchConstraintKind.parallel:
      case FamilySketchConstraintKind.perpendicular:
      case FamilySketchConstraintKind.equalLength:
        return 'Segment $a–$b ↔ Segment $c–$d';
      case FamilySketchConstraintKind.angle:
        return 'Segment $a–$b ↔ Segment $c–$d = ${constraint.expression}°';
      case FamilySketchConstraintKind.horizontal:
      case FamilySketchConstraintKind.vertical:
      case FamilySketchConstraintKind.coincident:
        return 'Point $a ↔ Point $b';
    }
  }

  String _pointNumber(String? id, int? legacyIndex) {
    final sketch = _sketch;
    if (sketch != null && id?.trim().isNotEmpty == true) {
      final index = sketch.points.indexWhere((point) => point.id == id);
      if (index >= 0) return '${index + 1}';
    }
    return legacyIndex == null ? '?' : '${legacyIndex + 1}';
  }

  static String _constraintTitle(FamilySketchConstraintKind kind) =>
      switch (kind) {
        FamilySketchConstraintKind.horizontal => 'Horizontal',
        FamilySketchConstraintKind.vertical => 'Vertical',
        FamilySketchConstraintKind.coincident => 'Coincident',
        FamilySketchConstraintKind.pointOnReferencePlane => 'Point on plane',
        FamilySketchConstraintKind.distance => 'Distance',
        FamilySketchConstraintKind.parallel => 'Parallel',
        FamilySketchConstraintKind.perpendicular => 'Perpendicular',
        FamilySketchConstraintKind.equalLength => 'Equal length',
        FamilySketchConstraintKind.angle => 'Angle',
      };

  static IconData _constraintIcon(FamilySketchConstraintKind kind) =>
      switch (kind) {
        FamilySketchConstraintKind.horizontal => Icons.horizontal_rule,
        FamilySketchConstraintKind.vertical => Icons.more_vert,
        FamilySketchConstraintKind.coincident => Icons.center_focus_strong,
        FamilySketchConstraintKind.pointOnReferencePlane =>
          Icons.vertical_align_center,
        FamilySketchConstraintKind.distance => Icons.straighten,
        FamilySketchConstraintKind.parallel => Icons.drag_handle,
        FamilySketchConstraintKind.perpendicular => Icons.square_foot,
        FamilySketchConstraintKind.equalLength => Icons.compare_arrows,
        FamilySketchConstraintKind.angle => Icons.architecture,
      };

  static String _number(double value) {
    final rounded = value.toStringAsFixed(4);
    return rounded.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

final class _PlaneDraft {
  const _PlaneDraft(this.name, this.axis, this.expression);

  final String name;
  final FamilyReferencePlaneAxis axis;
  final String expression;
}

class _ReferencePlaneDialog extends StatefulWidget {
  const _ReferencePlaneDialog({this.plane});

  final FamilyReferencePlane? plane;

  @override
  State<_ReferencePlaneDialog> createState() => _ReferencePlaneDialogState();
}

class _ReferencePlaneDialogState extends State<_ReferencePlaneDialog> {
  late final TextEditingController _name;
  late final TextEditingController _expression;
  late FamilyReferencePlaneAxis _axis;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plane?.name ?? 'Reference plane');
    _expression =
        TextEditingController(text: widget.plane?.expression ?? '0');
    _axis = widget.plane?.axis ?? FamilyReferencePlaneAxis.x;
  }

  @override
  void dispose() {
    _name.dispose();
    _expression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.plane == null ? 'Add reference plane' : 'Edit reference plane',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<FamilyReferencePlaneAxis>(
                initialValue: _axis,
                decoration: const InputDecoration(
                  labelText: 'Fixed coordinate',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<FamilyReferencePlaneAxis>>[
                  DropdownMenuItem(
                    value: FamilyReferencePlaneAxis.x,
                    child: Text('X · vertical reference plane'),
                  ),
                  DropdownMenuItem(
                    value: FamilyReferencePlaneAxis.y,
                    child: Text('Y · horizontal reference plane'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _axis = value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _expression,
                decoration: const InputDecoration(
                  labelText: 'Offset expression',
                  hintText: '-width / 2',
                  helperText:
                      'Uses the same safe numeric language as parameter formulas.',
                  border: OutlineInputBorder(),
                ),
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
            onPressed: () {
              final name = _name.text.trim();
              final expression = _expression.text.trim();
              if (name.isEmpty || expression.isEmpty) return;
              Navigator.of(context).pop(_PlaneDraft(name, _axis, expression));
            },
            child: const Text('Apply'),
          ),
        ],
      );
}

final class _ConstraintDraft {
  const _ConstraintDraft({
    required this.kind,
    required this.pointA,
    this.pointB,
    this.pointC,
    this.pointD,
    this.referencePlaneId,
    this.expression,
  });

  final FamilySketchConstraintKind kind;
  final int pointA;
  final int? pointB;
  final int? pointC;
  final int? pointD;
  final String? referencePlaneId;
  final String? expression;
}

class _ConstraintDialog extends StatefulWidget {
  const _ConstraintDialog({required this.sketch, required this.planes});

  final FamilySketch sketch;
  final List<FamilyReferencePlane> planes;

  @override
  State<_ConstraintDialog> createState() => _ConstraintDialogState();
}

class _ConstraintDialogState extends State<_ConstraintDialog> {
  FamilySketchConstraintKind _kind = FamilySketchConstraintKind.horizontal;
  int _pointA = 0;
  int _pointB = 1;
  int _pointC = 2;
  int _pointD = 3;
  String? _planeId;
  final TextEditingController _expression = TextEditingController(text: '1.0');

  @override
  void initState() {
    super.initState();
    final count = widget.sketch.points.length;
    _pointB = count > 1 ? 1 : 0;
    _pointC = count > 2 ? 2 : 0;
    _pointD = count > 3 ? 3 : _pointB;
    _planeId = widget.planes.isEmpty ? null : widget.planes.first.id;
  }

  @override
  void dispose() {
    _expression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesPlane =
        _kind == FamilySketchConstraintKind.pointOnReferencePlane;
    final usesSecondSegment = _kind == FamilySketchConstraintKind.parallel ||
        _kind == FamilySketchConstraintKind.perpendicular ||
        _kind == FamilySketchConstraintKind.equalLength ||
        _kind == FamilySketchConstraintKind.angle;
    final usesExpression = _kind == FamilySketchConstraintKind.distance ||
        _kind == FamilySketchConstraintKind.angle;
    final needsPointB = !usesPlane;
    final enoughPoints = usesSecondSegment
        ? widget.sketch.points.length >= 4
        : usesPlane
            ? widget.sketch.points.isNotEmpty
            : widget.sketch.points.length >= 2;

    return AlertDialog(
      title: const Text('Add sketch constraint'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<FamilySketchConstraintKind>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Constraint',
                  border: OutlineInputBorder(),
                ),
                items: FamilySketchConstraintKind.values
                    .map(
                      (kind) => DropdownMenuItem<FamilySketchConstraintKind>(
                        value: kind,
                        child: Text(FamilyConstraintsPanel._constraintTitle(kind)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (kind) {
                  if (kind == null) return;
                  setState(() {
                    _kind = kind;
                    if (kind == FamilySketchConstraintKind.angle) {
                      _expression.text = '90';
                    } else if (kind == FamilySketchConstraintKind.distance &&
                        _expression.text == '90') {
                      _expression.text = '1.0';
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              _pointPicker(
                label: 'Point A',
                value: _pointA,
                onChanged: (value) => setState(() => _pointA = value),
              ),
              if (needsPointB) ...<Widget>[
                const SizedBox(height: 8),
                _pointPicker(
                  label: 'Point B',
                  value: _pointB,
                  onChanged: (value) => setState(() => _pointB = value),
                ),
              ],
              if (usesPlane) ...<Widget>[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _planeId,
                  decoration: const InputDecoration(
                    labelText: 'Reference plane',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.planes
                      .map(
                        (plane) => DropdownMenuItem<String>(
                          value: plane.id,
                          child: Text(
                            '${plane.name} · ${plane.axis.name.toUpperCase()}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _planeId = value),
                ),
              ],
              if (usesSecondSegment) ...<Widget>[
                const SizedBox(height: 8),
                _pointPicker(
                  label: 'Point C',
                  value: _pointC,
                  onChanged: (value) => setState(() => _pointC = value),
                ),
                const SizedBox(height: 8),
                _pointPicker(
                  label: 'Point D',
                  value: _pointD,
                  onChanged: (value) => setState(() => _pointD = value),
                ),
              ],
              if (usesExpression) ...<Widget>[
                const SizedBox(height: 8),
                TextField(
                  controller: _expression,
                  decoration: InputDecoration(
                    labelText: _kind == FamilySketchConstraintKind.angle
                        ? 'Angle expression (degrees)'
                        : 'Distance expression',
                    hintText: _kind == FamilySketchConstraintKind.angle
                        ? '90 or clamp(angleParam, 0, 180)'
                        : 'width / 2',
                    helperText:
                        'Numeric literals, parameter ids and safe family formula functions are supported.',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              if (!enoughPoints) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  usesSecondSegment
                      ? 'This constraint needs at least four sketch points.'
                      : 'This constraint needs more sketch points.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: !enoughPoints || (usesPlane && _planeId == null)
              ? null
              : () {
                  if (needsPointB && _pointA == _pointB) return;
                  if (usesSecondSegment && _pointC == _pointD) return;
                  final expression =
                      usesExpression ? _expression.text.trim() : null;
                  if (usesExpression && (expression == null || expression.isEmpty)) {
                    return;
                  }
                  Navigator.of(context).pop(
                    _ConstraintDraft(
                      kind: _kind,
                      pointA: _pointA,
                      pointB: needsPointB ? _pointB : null,
                      pointC: usesSecondSegment ? _pointC : null,
                      pointD: usesSecondSegment ? _pointD : null,
                      referencePlaneId: usesPlane ? _planeId : null,
                      expression: expression,
                    ),
                  );
                },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _pointPicker({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<int>>[
          for (var index = 0; index < widget.sketch.points.length; index++)
            DropdownMenuItem<int>(
              value: index,
              child: Text(
                'Point ${index + 1} · (${FamilyConstraintsPanel._number(widget.sketch.points[index].x)}, ${FamilyConstraintsPanel._number(widget.sketch.points[index].y)})',
              ),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );
}
