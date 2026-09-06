import 'dart:math' as math;

import 'family_constraint_models.dart';
import 'family_document.dart';
import 'family_parameter_resolver.dart';

export 'family_constraint_models.dart';

final class FamilyConstraintSolution {
  const FamilyConstraintSolution({
    required this.sketch,
    required this.referencePlaneOffsets,
  });

  final FamilySketch sketch;
  final Map<String, double> referencePlaneOffsets;
}

/// Deterministic 2D geometric constraint solver used by Family Authoring.
///
/// Stage-1 equality constraints are solved exactly as coordinate groups.
/// Stage-2 dimensional/segment constraints are then projected iteratively and
/// Stage-1 is re-applied after every pass. A conflicting system must converge
/// within a strict residual budget or it is rejected as over-constrained.
abstract final class FamilyConstraintSolver {
  static const double _tolerance = 1.0e-8;
  static const double _stage2Tolerance = 1.0e-6;
  static const int _stage2Iterations = 64;

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
        case FamilySketchConstraintKind.distance:
        case FamilySketchConstraintKind.parallel:
        case FamilySketchConstraintKind.perpendicular:
        case FamilySketchConstraintKind.equalLength:
        case FamilySketchConstraintKind.angle:
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

    var points = _projectStage1(sketch.points, x, y);
    final stage2 = constraints.where(_isStage2).toList(growable: false);
    if (stage2.isNotEmpty) {
      final targets = <String, double>{};
      for (final constraint in stage2) {
        _validateStage2Shape(sketch, constraint);
        if (constraint.kind == FamilySketchConstraintKind.distance ||
            constraint.kind == FamilySketchConstraintKind.angle) {
          final expression = constraint.expression?.trim();
          if (expression == null || expression.isEmpty) {
            throw FormatException(
              'Constraint ${constraint.id} requires a numeric expression.',
            );
          }
          final target = resolver.resolveExpression(expression);
          if (!target.isFinite) {
            throw FormatException(
              'Constraint ${constraint.id} resolved to a non-finite target.',
            );
          }
          if (constraint.kind == FamilySketchConstraintKind.distance &&
              target <= 0.0) {
            throw FormatException(
              'Distance constraint ${constraint.id} must be positive.',
            );
          }
          if (constraint.kind == FamilySketchConstraintKind.angle &&
              (target < 0.0 || target > 180.0)) {
            throw FormatException(
              'Angle constraint ${constraint.id} must be between 0 and 180 degrees.',
            );
          }
          targets[constraint.id] = target;
        }
      }
      points = _solveStage2(points, stage2, targets, x, y);
    }

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

  static List<FamilySketchPoint> _projectStage1(
    List<FamilySketchPoint> points,
    _CoordinateSystem x,
    _CoordinateSystem y,
  ) {
    final solvedX = x.solve(points.map((point) => point.x).toList());
    final solvedY = y.solve(points.map((point) => point.y).toList());
    return <FamilySketchPoint>[
      for (var index = 0; index < points.length; index++)
        FamilySketchPoint(x: solvedX[index], y: solvedY[index]),
    ];
  }

  static List<FamilySketchPoint> _solveStage2(
    List<FamilySketchPoint> initial,
    List<FamilySketchConstraint> constraints,
    Map<String, double> targets,
    _CoordinateSystem x,
    _CoordinateSystem y,
  ) {
    var points = <FamilySketchPoint>[...initial];
    for (var iteration = 0; iteration < _stage2Iterations; iteration++) {
      for (final constraint in constraints) {
        _applyStage2(points, constraint, targets[constraint.id]);
      }
      points = _projectStage1(points, x, y);
      var maxResidual = 0.0;
      for (final constraint in constraints) {
        maxResidual = math.max(
          maxResidual,
          _stage2Residual(points, constraint, targets[constraint.id]),
        );
      }
      if (maxResidual <= _stage2Tolerance) return points;
    }
    throw const FormatException(
      'Over-constrained sketch: dimensional constraints did not converge.',
    );
  }

  static void _applyStage2(
    List<FamilySketchPoint> points,
    FamilySketchConstraint constraint,
    double? target,
  ) {
    final a = points[constraint.pointAIndex];
    final bIndex = constraint.pointBIndex!;
    final b = points[bIndex];
    switch (constraint.kind) {
      case FamilySketchConstraintKind.distance:
        final desired = target!;
        final direction = _direction(a, b, fallback: const _Vec2(1, 0));
        points[bIndex] = FamilySketchPoint(
          x: a.x + direction.x * desired,
          y: a.y + direction.y * desired,
        );
        return;
      case FamilySketchConstraintKind.parallel:
      case FamilySketchConstraintKind.perpendicular:
      case FamilySketchConstraintKind.equalLength:
      case FamilySketchConstraintKind.angle:
        final cIndex = constraint.pointCIndex!;
        final dIndex = constraint.pointDIndex!;
        final c = points[cIndex];
        final d = points[dIndex];
        final ab = _vector(a, b);
        final cd = _vector(c, d);
        final abLength = ab.length;
        if (abLength <= _tolerance) {
          throw FormatException(
            'Constraint ${constraint.id} uses a zero-length source segment.',
          );
        }
        final source = ab * (1.0 / abLength);
        final cdLength = cd.length;
        final current = cdLength <= _tolerance
            ? source
            : cd * (1.0 / cdLength);
        final length = constraint.kind == FamilySketchConstraintKind.equalLength
            ? abLength
            : (cdLength <= _tolerance ? abLength : cdLength);
        final _Vec2 desiredDirection;
        if (constraint.kind == FamilySketchConstraintKind.parallel) {
          desiredDirection = source.dot(current) < 0.0 ? source * -1.0 : source;
        } else if (constraint.kind ==
            FamilySketchConstraintKind.perpendicular) {
          final plus = _Vec2(-source.y, source.x);
          final minus = plus * -1.0;
          desiredDirection =
              plus.dot(current) >= minus.dot(current) ? plus : minus;
        } else if (constraint.kind == FamilySketchConstraintKind.equalLength) {
          desiredDirection = current;
        } else {
          final radians = target! * math.pi / 180.0;
          final sourceAngle = math.atan2(source.y, source.x);
          final plus = _Vec2(
            math.cos(sourceAngle + radians),
            math.sin(sourceAngle + radians),
          );
          final minus = _Vec2(
            math.cos(sourceAngle - radians),
            math.sin(sourceAngle - radians),
          );
          desiredDirection =
              plus.dot(current) >= minus.dot(current) ? plus : minus;
        }
        points[dIndex] = FamilySketchPoint(
          x: c.x + desiredDirection.x * length,
          y: c.y + desiredDirection.y * length,
        );
        return;
      case FamilySketchConstraintKind.horizontal:
      case FamilySketchConstraintKind.vertical:
      case FamilySketchConstraintKind.coincident:
      case FamilySketchConstraintKind.pointOnReferencePlane:
        return;
    }
  }

  static double _stage2Residual(
    List<FamilySketchPoint> points,
    FamilySketchConstraint constraint,
    double? target,
  ) {
    final a = points[constraint.pointAIndex];
    final b = points[constraint.pointBIndex!];
    final ab = _vector(a, b);
    switch (constraint.kind) {
      case FamilySketchConstraintKind.distance:
        return (ab.length - target!).abs();
      case FamilySketchConstraintKind.parallel:
      case FamilySketchConstraintKind.perpendicular:
      case FamilySketchConstraintKind.equalLength:
      case FamilySketchConstraintKind.angle:
        final c = points[constraint.pointCIndex!];
        final d = points[constraint.pointDIndex!];
        final cd = _vector(c, d);
        if (ab.length <= _tolerance || cd.length <= _tolerance) {
          return double.infinity;
        }
        final u = ab * (1.0 / ab.length);
        final v = cd * (1.0 / cd.length);
        if (constraint.kind == FamilySketchConstraintKind.parallel) {
          return u.cross(v).abs();
        }
        if (constraint.kind == FamilySketchConstraintKind.perpendicular) {
          return u.dot(v).abs();
        }
        if (constraint.kind == FamilySketchConstraintKind.equalLength) {
          return (ab.length - cd.length).abs();
        }
        final dot = u.dot(v).clamp(-1.0, 1.0).toDouble();
        final angle = math.acos(dot) * 180.0 / math.pi;
        return (angle - target!).abs();
      case FamilySketchConstraintKind.horizontal:
      case FamilySketchConstraintKind.vertical:
      case FamilySketchConstraintKind.coincident:
      case FamilySketchConstraintKind.pointOnReferencePlane:
        return 0.0;
    }
  }

  static bool _isStage2(FamilySketchConstraint constraint) =>
      constraint.kind == FamilySketchConstraintKind.distance ||
      constraint.kind == FamilySketchConstraintKind.parallel ||
      constraint.kind == FamilySketchConstraintKind.perpendicular ||
      constraint.kind == FamilySketchConstraintKind.equalLength ||
      constraint.kind == FamilySketchConstraintKind.angle;

  static void _validateStage2Shape(
    FamilySketch sketch,
    FamilySketchConstraint constraint,
  ) {
    final b = _requireSecondPoint(sketch, constraint);
    if (constraint.kind == FamilySketchConstraintKind.distance) {
      if (constraint.pointCIndex != null || constraint.pointDIndex != null) {
        throw FormatException(
          'Distance constraint ${constraint.id} cannot use a second segment.',
        );
      }
      return;
    }
    final c = constraint.pointCIndex;
    final d = constraint.pointDIndex;
    if (c == null || d == null) {
      throw FormatException(
        'Constraint ${constraint.id} requires two complete segments.',
      );
    }
    _requirePoint(sketch, c, constraint.id);
    _requirePoint(sketch, d, constraint.id);
    if (c == d) {
      throw FormatException(
        'Constraint ${constraint.id} second segment must use distinct points.',
      );
    }
    if (constraint.referencePlaneId != null) {
      throw FormatException(
        'Segment constraint ${constraint.id} cannot reference a plane.',
      );
    }
    if (b == constraint.pointAIndex) {
      throw FormatException(
        'Constraint ${constraint.id} first segment must use distinct points.',
      );
    }
  }

  static _Vec2 _vector(FamilySketchPoint a, FamilySketchPoint b) =>
      _Vec2(b.x - a.x, b.y - a.y);

  static _Vec2 _direction(
    FamilySketchPoint a,
    FamilySketchPoint b, {
    required _Vec2 fallback,
  }) {
    final vector = _vector(a, b);
    final length = vector.length;
    return length <= _tolerance ? fallback : vector * (1.0 / length);
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

final class _Vec2 {
  const _Vec2(this.x, this.y);

  final double x;
  final double y;

  _Vec2 operator * (double value) => _Vec2(x * value, y * value);

  double get length => math.sqrt(x * x + y * y);
  double dot(_Vec2 other) => x * other.x + y * other.y;
  double cross(_Vec2 other) => x * other.y - y * other.x;
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
