import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('distance constraint resolves a Family Type expression', () {
    final document = _document(
      points: const <FamilySketchPoint>[
        FamilySketchPoint(x: 0, y: 0),
        FamilySketchPoint(x: 1, y: 0),
      ],
      constraints: const <FamilySketchConstraint>[
        FamilySketchConstraint(
          id: 'distance',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.distance,
          pointAIndex: 0,
          pointBIndex: 1,
          expression: 'width',
        ),
      ],
      width: 3.0,
    );
    final solved = FamilyConstraintSolver.solveSketch(
      document,
      document.types.single,
      document.sketches.single,
    ).sketch;
    expect(solved.points[1].x, closeTo(3.0, 1e-6));
    expect(solved.points[1].y, closeTo(0.0, 1e-6));
  });

  test('parallel, perpendicular and equal-length constraints project segments', () {
    final parallel = _solveOne(
      const FamilySketchConstraint(
        id: 'parallel',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.parallel,
        pointAIndex: 0,
        pointBIndex: 1,
        pointCIndex: 2,
        pointDIndex: 3,
      ),
    );
    final pab = _vector(parallel.points[0], parallel.points[1]);
    final pcd = _vector(parallel.points[2], parallel.points[3]);
    expect(_cross(pab, pcd).abs(), lessThan(1e-6));

    final perpendicular = _solveOne(
      const FamilySketchConstraint(
        id: 'perpendicular',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.perpendicular,
        pointAIndex: 0,
        pointBIndex: 1,
        pointCIndex: 2,
        pointDIndex: 3,
      ),
    );
    final uab = _vector(perpendicular.points[0], perpendicular.points[1]);
    final ucd = _vector(perpendicular.points[2], perpendicular.points[3]);
    expect(_dot(uab, ucd).abs(), lessThan(1e-6));

    final equal = _solveOne(
      const FamilySketchConstraint(
        id: 'equal',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.equalLength,
        pointAIndex: 0,
        pointBIndex: 1,
        pointCIndex: 2,
        pointDIndex: 3,
      ),
    );
    expect(
      _length(_vector(equal.points[0], equal.points[1])),
      closeTo(_length(_vector(equal.points[2], equal.points[3])), 1e-6),
    );
  });

  test('angle constraint resolves degrees from family formula language', () {
    final document = _document(
      points: const <FamilySketchPoint>[
        FamilySketchPoint(x: 0, y: 0),
        FamilySketchPoint(x: 2, y: 0),
        FamilySketchPoint(x: 0, y: 1),
        FamilySketchPoint(x: 0, y: 3),
      ],
      constraints: const <FamilySketchConstraint>[
        FamilySketchConstraint(
          id: 'angle',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.angle,
          pointAIndex: 0,
          pointBIndex: 1,
          pointCIndex: 2,
          pointDIndex: 3,
          expression: '45',
        ),
      ],
    );
    final solved = FamilyConstraintSolver.solveSketch(
      document,
      document.types.single,
      document.sketches.single,
    ).sketch;
    final ab = _vector(solved.points[0], solved.points[1]);
    final cd = _vector(solved.points[2], solved.points[3]);
    final cosine = (_dot(ab, cd) / (_length(ab) * _length(cd)))
        .clamp(-1.0, 1.0)
        .toDouble();
    expect(cosine, closeTo(math.sqrt(0.5), 1e-6));
  });

  test('stage-1 pins make an incompatible distance fail validation', () {
    final source = _document(
      points: const <FamilySketchPoint>[
        FamilySketchPoint(x: 0, y: 0),
        FamilySketchPoint(x: 1, y: 0),
      ],
      constraints: const <FamilySketchConstraint>[],
    );
    final conflict = source.copyWith(
      referencePlanes: const <FamilyReferencePlane>[
        FamilyReferencePlane(
          id: 'x0',
          name: 'X0',
          sketchId: 'profile',
          axis: FamilyReferencePlaneAxis.x,
          expression: '0',
        ),
        FamilyReferencePlane(
          id: 'x1',
          name: 'X1',
          sketchId: 'profile',
          axis: FamilyReferencePlaneAxis.x,
          expression: '1',
        ),
        FamilyReferencePlane(
          id: 'y0',
          name: 'Y0',
          sketchId: 'profile',
          axis: FamilyReferencePlaneAxis.y,
          expression: '0',
        ),
      ],
      constraints: const <FamilySketchConstraint>[
        FamilySketchConstraint(
          id: 'a-x',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: 0,
          referencePlaneId: 'x0',
        ),
        FamilySketchConstraint(
          id: 'a-y',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: 0,
          referencePlaneId: 'y0',
        ),
        FamilySketchConstraint(
          id: 'b-x',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: 1,
          referencePlaneId: 'x1',
        ),
        FamilySketchConstraint(
          id: 'b-y',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: 1,
          referencePlaneId: 'y0',
        ),
        FamilySketchConstraint(
          id: 'too-long',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.distance,
          pointAIndex: 0,
          pointBIndex: 1,
          expression: '3',
        ),
      ],
    );
    final validation = FamilyDocumentValidator.validate(conflict);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('did not converge')),
      isTrue,
    );
  });
}

FamilySketch _solveOne(FamilySketchConstraint constraint) {
  final document = _document(
    points: const <FamilySketchPoint>[
      FamilySketchPoint(x: 0, y: 0),
      FamilySketchPoint(x: 2, y: 0),
      FamilySketchPoint(x: 0, y: 1),
      FamilySketchPoint(x: 1, y: 2),
    ],
    constraints: <FamilySketchConstraint>[constraint],
  );
  return FamilyConstraintSolver.solveSketch(
    document,
    document.types.single,
    document.sketches.single,
  ).sketch;
}

FamilyDocument _document({
  required List<FamilySketchPoint> points,
  required List<FamilySketchConstraint> constraints,
  double width = 2.0,
}) {
  final starter = FamilyDocument.starter();
  return starter.copyWith(
    types: <FamilyTypeDefinition>[
      starter.types.single.copyWith(values: <String, Object?>{
        ...starter.types.single.values,
        'width': width,
      }),
    ],
    sketches: <FamilySketch>[
      FamilySketch(
        id: 'profile',
        name: 'Profile',
        plane: FamilySketchPlane.xy,
        points: points,
      ),
    ],
    constraints: constraints,
  );
}

(double, double) _vector(FamilySketchPoint a, FamilySketchPoint b) =>
    (b.x - a.x, b.y - a.y);

double _dot((double, double) a, (double, double) b) =>
    a.$1 * b.$1 + a.$2 * b.$2;

double _cross((double, double) a, (double, double) b) =>
    a.$1 * b.$2 - a.$2 * b.$1;

double _length((double, double) value) =>
    math.sqrt(value.$1 * value.$1 + value.$2 * value.$2);
