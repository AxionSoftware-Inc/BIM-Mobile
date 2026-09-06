import 'family_constraint_models.dart';
import 'family_document.dart';
import 'family_parameter_resolver.dart';

final class FamilyConstraintSolution {
  const FamilyConstraintSolution({
    required this.sketch,
    required this.referencePlaneOffsets,
  });

  final FamilySketch sketch;
  final Map<String, double> referencePlaneOffsets;
}

/// Stage-1 geometric constraint solver.
///
/// X and Y are solved independently as equality graphs. Horizontal/vertical
/// and coincident constraints merge coordinate groups; point-on-reference-plane
/// constraints pin a group to a formula-driven value. Conflicting pins are
/// reported as over-constraints instead of being averaged or silently ignored.
abstract final class FamilyConstraintSolver {
  static const double _tolerance = 1.0e-8;

  static FamilyConstraintSolution solveSketch(
    FamilyDocument document,
    FamilyTypeDefinition type,
    FamilySketch sketch,
  ) {
    final constraints = document.constraints
        .where((constraint) => constraint.sketchId == sketch.id)
        .toList(growable: false);
    final planes = <String, FamilyReferencePlane>{
      for (final plane in document.referencePlanes)
        if (plane.sketchId == sketch.id) plane.id: plane,
    };
    if (constraints.isEmpty && planes.isEmpty) {
      return FamilyConstraintSolution(
        sketch: sketch,
        referencePlaneOffsets: const <String, double>{},
      );
    }

    final count = sketch.points.length;
    if (count == 0 && constraints.isNotEmpty) {
      throw FormatException('Sketch ${sketch.name} has constraints but no points.');
    }

    final x = _CoordinateSystem(count);
    final y = _CoordinateSystem(count);
    for (final constraint in constraints) {
      _requirePoint(sketch, constraint.pointAIndex, constraint.id);
      switch (constraint.kind) {
        case FamilySketchConstraintKind.horizontal:
          final b = _requireSecondPoint(sketch, constraint);
          y.union(constraint.pointAIndex, b);
          break;
        case FamilySketchConstraintKind.vertical:
          final b = _requireSecondPoint(sketch, constraint);
          x.union(constraint.pointAIndex, b);
          break;
        case FamilySketchConstraintKind.coincident:
          final b = _requireSecondPoint(sketch, constraint);
          x.union(constraint.pointAIndex, b);
          y.union(constraint.pointAIndex, b);
          break;
        case FamilySketchConstraintKind.pointOnReferencePlane:
          // Applied after all equality groups are built.
          break;
      }
    }

    final resolver = FamilyParameterResolver(document, type);
    final planeOffsets = <String, double>{};
    for (final plane in planes.values) {
      final value = resolver.resolveExpression(plane.expression);
      if (!value.isFinite) {
        throw FormatException(
          'Reference plane ${plane.name} resolved to a non-finite offset.',
        );
      }
      planeOffsets[plane.id] = value;
    }

    for (final constraint in constraints) {
      if (constraint.kind !=
          FamilySketchConstraintKind.pointOnReferencePlane) {
        continue;
      }
      final planeId = constraint.referencePlaneId;
      final plane = planeId == null ? null : planes[planeId];
      if (plane == null) {
        throw FormatException(
          'Constraint ${constraint.id} references an unavailable reference plane.',
        );
      }
      final offset = planeOffsets[plane.id]!;
      if (plane.axis == FamilyReferencePlaneAxis.x) {
        x.fix(
          constraint.pointAIndex,
          offset,
          source: plane.name,
          tolerance: _tolerance,
        );
      } else {
        y.fix(
          constraint.pointAIndex,
          offset,
          source: plane.name,
          tolerance: _tolerance,
        );
      }
    }

    final originalX = sketch.points.map((point) => point.x).toList();
    final originalY = sketch.points.map((point) => point.y).toList();
    final solvedX = x.solve(originalX);
    final solvedY = y.solve(originalY);
    final points = <FamilySketchPoint>[
      for (var index = 0; index < count; index++)
        FamilySketchPoint(x: solvedX[index], y: solvedY[index]),
    ];
    return FamilyConstraintSolution(
      sketch: sketch.copyWith(points: points),
      referencePlaneOffsets: Map<String, double>.unmodifiable(planeOffsets),
    );
  }

  /// Returns a transient document whose sketches contain solved coordinates.
  /// Persistent constraint intent remains untouched; this copy is for geometry
  /// evaluation only and is never written back as baked point positions.
  static FamilyDocument solveDocument(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    if (document.constraints.isEmpty && document.referencePlanes.isEmpty) {
      return document;
    }
    return document.copyWith(
      sketches: <FamilySketch>[
        for (final sketch in document.sketches)
          solveSketch(document, type, sketch).sketch,
      ],
    );
  }

  static void validateAll(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    for (final sketch in document.sketches) {
      solveSketch(document, type, sketch);
    }
  }

  static void _requirePoint(
    FamilySketch sketch,
    int index,
    String constraintId,
  ) {
    if (index < 0 || index >= sketch.points.length) {
      throw FormatException(
        'Constraint $constraintId references point $index outside sketch ${sketch.name}.',
      );
    }
  }

  static int _requireSecondPoint(
    FamilySketch sketch,
    FamilySketchConstraint constraint,
  ) {
    final b = constraint.pointBIndex;
    if (b == null) {
      throw FormatException(
        'Constraint ${constraint.id} requires a second sketch point.',
      );
    }
    _requirePoint(sketch, b, constraint.id);
    if (b == constraint.pointAIndex) {
      throw FormatException(
        'Constraint ${constraint.id} must reference two distinct points.',
      );
    }
    return b;
  }
}

final class _CoordinateSystem {
  _CoordinateSystem(int count)
      : _parent = List<int>.generate(count, (index) => index),
        _rank = List<int>.filled(count, 0);

  final List<int> _parent;
  final List<int> _rank;
  final Map<int, _FixedCoordinate> _fixedByRoot = <int, _FixedCoordinate>{};

  int find(int value) {
    final parent = _parent[value];
    if (parent == value) return value;
    return _parent[value] = find(parent);
  }

  void union(int a, int b) {
    var rootA = find(a);
    var rootB = find(b);
    if (rootA == rootB) return;
    if (_rank[rootA] < _rank[rootB]) {
      final swap = rootA;
      rootA = rootB;
      rootB = swap;
    }
    _parent[rootB] = rootA;
    if (_rank[rootA] == _rank[rootB]) _rank[rootA]++;
  }

  void fix(
    int point,
    double value, {
    required String source,
    required double tolerance,
  }) {
    final root = find(point);
    final existing = _fixedByRoot[root];
    if (existing != null && (existing.value - value).abs() > tolerance) {
      throw FormatException(
        'Over-constrained sketch: ${existing.source} fixes a coordinate to '
        '${existing.value}, but $source fixes the same coordinate group to $value.',
      );
    }
    _fixedByRoot[root] = _FixedCoordinate(value, source);
  }

  List<double> solve(List<double> originals) {
    final normalizedFixed = <int, _FixedCoordinate>{};
    for (final entry in _fixedByRoot.entries) {
      normalizedFixed[find(entry.key)] = entry.value;
    }

    final sums = <int, double>{};
    final counts = <int, int>{};
    for (var index = 0; index < originals.length; index++) {
      final root = find(index);
      sums[root] = (sums[root] ?? 0.0) + originals[index];
      counts[root] = (counts[root] ?? 0) + 1;
    }
    final groupValue = <int, double>{};
    for (final entry in sums.entries) {
      final root = entry.key;
      groupValue[root] = normalizedFixed[root]?.value ??
          entry.value / (counts[root] ?? 1);
    }
    return <double>[
      for (var index = 0; index < originals.length; index++)
        groupValue[find(index)]!,
    ];
  }
}

final class _FixedCoordinate {
  const _FixedCoordinate(this.value, this.source);

  final double value;
  final String source;
}
