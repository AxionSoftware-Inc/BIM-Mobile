import 'package:flutter/material.dart';

import 'family_constraint_models.dart';
import 'family_constraint_solver.dart';
import 'family_document.dart';
import 'family_validation.dart';

/// Tablet-friendly authoring surface for Stage-1 geometric constraints.
///
/// This widget only commits documents that pass the same semantic validator as
/// save/placement. Reference-plane expressions are therefore live geometry,
/// not decorative metadata.
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
                    onPressed: () => _quickRectangle(context, sketch),
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
    final draft = await showDialog<_ConstraintDraft>(
      context: context,
      builder: (_) => _ConstraintDialog(
        sketch: sketch,
        planes: _planes,
      ),
    );
    if (draft == null) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    _commit(
      document.copyWith(
        constraints: <FamilySketchConstraint>[
          ...document.constraints,
          FamilySketchConstraint(
            id: 'constraint-$stamp',
            sketchId: sketch.id,
            kind: draft.kind,
            pointAIndex: draft.pointA,
            pointBIndex: draft.pointB,
            referencePlaneId: draft.referencePlaneId,
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

  void _quickRectangle(BuildContext context, FamilySketch sketch) {
    final ownedPlaneIds = document.referencePlanes
        .where((plane) => plane.sketchId == sketch.id)
        .map((plane) => plane.id)
        .toSet();
    final cleaned = document.copyWith(
      referencePlanes: <FamilyReferencePlane>[
        for (final plane in document.referencePlanes)
          if (plane.sketchId != sketch.id) plane,
      ],
      constraints: <FamilySketchConstraint>[
        for (final constraint in document.constraints)
          if (constraint.sketchId != sketch.id &&
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
        sketchId: sketch.id,
        axis: FamilyReferencePlaneAxis.x,
        expression: '-width / 2',
      ),
      FamilyReferencePlane(
        id: right,
        name: 'Right',
        sketchId: sketch.id,
        axis: FamilyReferencePlaneAxis.x,
        expression: 'width / 2',
      ),
      FamilyReferencePlane(
        id: bottom,
        name: 'Bottom',
        sketchId: sketch.id,
        axis: FamilyReferencePlaneAxis.y,
        expression: '0',
      ),
      FamilyReferencePlane(
        id: top,
        name: 'Top',
        sketchId: sketch.id,
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
          sketchId: sketch.id,
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: point,
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
    if (constraint.kind ==
        FamilySketchConstraintKind.pointOnReferencePlane) {
      final plane = _planes.where((item) => item.id == constraint.referencePlaneId);
      final planeName = plane.isEmpty ? 'missing plane' : plane.first.name;
      return 'Point ${constraint.pointAIndex + 1} → $planeName';
    }
    return 'Point ${constraint.pointAIndex + 1} ↔ Point ${(constraint.pointBIndex ?? -1) + 1}';
  }

  static String _constraintTitle(FamilySketchConstraintKind kind) =>
      switch (kind) {
        FamilySketchConstraintKind.horizontal => 'Horizontal',
        FamilySketchConstraintKind.vertical => 'Vertical',
        FamilySketchConstraintKind.coincident => 'Coincident',
        FamilySketchConstraintKind.pointOnReferencePlane => 'Point on plane',
      };

  static IconData _constraintIcon(FamilySketchConstraintKind kind) =>
      switch (kind) {
        FamilySketchConstraintKind.horizontal => Icons.horizontal_rule,
        FamilySketchConstraintKind.vertical => Icons.more_vert,
        FamilySketchConstraintKind.coincident => Icons.center_focus_strong,
        FamilySketchConstraintKind.pointOnReferencePlane => Icons.vertical_align_center,
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
        title: Text(widget.plane == null ? 'Add reference plane' : 'Edit reference plane'),
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
                  helperText: 'Uses the same safe numeric language as parameter formulas.',
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
    this.referencePlaneId,
  });

  final FamilySketchConstraintKind kind;
  final int pointA;
  final int? pointB;
  final String? referencePlaneId;
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
  String? _planeId;

  @override
  void initState() {
    super.initState();
    _pointB = widget.sketch.points.length > 1 ? 1 : 0;
    _planeId = widget.planes.isEmpty ? null : widget.planes.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final usesPlane = _kind == FamilySketchConstraintKind.pointOnReferencePlane;
    return AlertDialog(
      title: const Text('Add sketch constraint'),
      content: SizedBox(
        width: 440,
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
                if (kind != null) setState(() => _kind = kind);
              },
            ),
            const SizedBox(height: 8),
            _pointPicker(
              label: 'Point A',
              value: _pointA,
              onChanged: (value) => setState(() => _pointA = value),
            ),
            const SizedBox(height: 8),
            if (usesPlane)
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
                        child: Text('${plane.name} · ${plane.axis.name.toUpperCase()}'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _planeId = value),
              )
            else
              _pointPicker(
                label: 'Point B',
                value: _pointB,
                onChanged: (value) => setState(() => _pointB = value),
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
          onPressed: usesPlane && _planeId == null
              ? null
              : () {
                  if (!usesPlane && _pointA == _pointB) return;
                  Navigator.of(context).pop(
                    _ConstraintDraft(
                      kind: _kind,
                      pointA: _pointA,
                      pointB: usesPlane ? null : _pointB,
                      referencePlaneId: usesPlane ? _planeId : null,
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
