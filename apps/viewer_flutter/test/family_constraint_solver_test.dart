import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('schema v2 remains readable and authoring edit upgrades to v3', () {
    final legacyJson = FamilyDocument.starter().toJson()
      ..['schema_version'] = 2;
    final legacy = FamilyDocument.fromJson(legacyJson);
    expect(legacy, isNotNull);
    expect(legacy!.schemaVersion, 2);
    expect(legacy.referencePlanes, isEmpty);
    expect(legacy.constraints, isEmpty);

    final edited = legacy.copyWith(name: 'Schema 3 family');
    expect(edited.schemaVersion, 3);
    expect(edited.schemaVersion, FamilyDocument.currentSchemaVersion);
  });

  test('reference planes and equality constraints solve a parametric rectangle', () {
    final document = _rectangleFamily();
    final type = document.types.single;
    final solution = FamilyConstraintSolver.solveSketch(
      document,
      type,
      document.sketches.single,
    );

    expect(solution.referencePlaneOffsets['left'], closeTo(-2.0, 1e-9));
    expect(solution.referencePlaneOffsets['right'], closeTo(2.0, 1e-9));
    expect(solution.referencePlaneOffsets['bottom'], closeTo(0.0, 1e-9));
    expect(solution.referencePlaneOffsets['top'], closeTo(3.0, 1e-9));

    final points = solution.sketch.points;
    expect(points[0].x, closeTo(-2.0, 1e-9));
    expect(points[0].y, closeTo(0.0, 1e-9));
    expect(points[1].x, closeTo(2.0, 1e-9));
    expect(points[1].y, closeTo(0.0, 1e-9));
    expect(points[2].x, closeTo(2.0, 1e-9));
    expect(points[2].y, closeTo(3.0, 1e-9));
    expect(points[3].x, closeTo(-2.0, 1e-9));
    expect(points[3].y, closeTo(3.0, 1e-9));
  });

  test('geometry evaluator consumes the solved profile instead of raw points', () {
    final document = _rectangleFamily();
    final shape = FamilyGeometryEvaluator.evaluate(
      document,
      document.types.single,
    );

    expect(shape.profile[0].x, closeTo(-2.0, 1e-9));
    expect(shape.profile[1].x, closeTo(2.0, 1e-9));
    expect(shape.profile[2].y, closeTo(3.0, 1e-9));
    expect(shape.profile[3].y, closeTo(3.0, 1e-9));
  });

  test('type dimensions immediately move formula-driven reference planes', () {
    final source = _rectangleFamily();
    final wideType = source.types.single.copyWith(values: <String, Object?>{
      ...source.types.single.values,
      'width': 8.0,
      'height': 2.0,
    });
    final document = source.copyWith(types: <FamilyTypeDefinition>[wideType]);
    final solution = FamilyConstraintSolver.solveSketch(
      document,
      wideType,
      document.sketches.single,
    );

    expect(solution.sketch.points[0].x, closeTo(-4.0, 1e-9));
    expect(solution.sketch.points[1].x, closeTo(4.0, 1e-9));
    expect(solution.sketch.points[2].y, closeTo(2.0, 1e-9));
  });

  test('conflicting reference-plane pins are rejected as over-constrained', () {
    final source = _rectangleFamily();
    final conflict = source.copyWith(
      referencePlanes: <FamilyReferencePlane>[
        ...source.referencePlanes,
        const FamilyReferencePlane(
          id: 'conflict-x',
          name: 'Conflicting X',
          sketchId: 'profile',
          axis: FamilyReferencePlaneAxis.x,
          expression: '0',
        ),
      ],
      constraints: <FamilySketchConstraint>[
        ...source.constraints,
        const FamilySketchConstraint(
          id: 'conflict-pin',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.pointOnReferencePlane,
          pointAIndex: 0,
          referencePlaneId: 'conflict-x',
        ),
      ],
    );

    final validation = FamilyDocumentValidator.validate(conflict);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('Over-constrained')),
      isTrue,
    );
  });

  test('constraint references cannot escape their sketch', () {
    final source = _rectangleFamily();
    final invalid = source.copyWith(
      constraints: <FamilySketchConstraint>[
        ...source.constraints,
        const FamilySketchConstraint(
          id: 'bad-point',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.vertical,
          pointAIndex: 0,
          pointBIndex: 99,
        ),
      ],
    );
    expect(FamilyDocumentValidator.validate(invalid).isValid, isFalse);
  });
}

FamilyDocument _rectangleFamily() {
  final starter = FamilyDocument.starter();
  const sketch = FamilySketch(
    id: 'profile',
    name: 'Constrained rectangle',
    plane: FamilySketchPlane.xy,
    closed: true,
    // Intentionally crooked/raw. Constraints must produce the rectangle.
    points: <FamilySketchPoint>[
      FamilySketchPoint(x: -0.7, y: 0.4),
      FamilySketchPoint(x: 1.1, y: -0.2),
      FamilySketchPoint(x: 1.6, y: 1.4),
      FamilySketchPoint(x: -1.4, y: 2.2),
    ],
  );
  return starter.copyWith(
    types: <FamilyTypeDefinition>[
      starter.types.single.copyWith(values: <String, Object?>{
        ...starter.types.single.values,
        'width': 4.0,
        'height': 3.0,
        'depth': 1.0,
      }),
    ],
    sketches: const <FamilySketch>[sketch],
    referencePlanes: const <FamilyReferencePlane>[
      FamilyReferencePlane(
        id: 'left',
        name: 'Left',
        sketchId: 'profile',
        axis: FamilyReferencePlaneAxis.x,
        expression: '-width / 2',
      ),
      FamilyReferencePlane(
        id: 'right',
        name: 'Right',
        sketchId: 'profile',
        axis: FamilyReferencePlaneAxis.x,
        expression: 'width / 2',
      ),
      FamilyReferencePlane(
        id: 'bottom',
        name: 'Bottom',
        sketchId: 'profile',
        axis: FamilyReferencePlaneAxis.y,
        expression: '0',
      ),
      FamilyReferencePlane(
        id: 'top',
        name: 'Top',
        sketchId: 'profile',
        axis: FamilyReferencePlaneAxis.y,
        expression: 'height',
      ),
    ],
    constraints: const <FamilySketchConstraint>[
      FamilySketchConstraint(
        id: 'p0-left',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 0,
        referencePlaneId: 'left',
      ),
      FamilySketchConstraint(
        id: 'p3-left',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 3,
        referencePlaneId: 'left',
      ),
      FamilySketchConstraint(
        id: 'p1-right',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 1,
        referencePlaneId: 'right',
      ),
      FamilySketchConstraint(
        id: 'p2-right',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 2,
        referencePlaneId: 'right',
      ),
      FamilySketchConstraint(
        id: 'p0-bottom',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 0,
        referencePlaneId: 'bottom',
      ),
      FamilySketchConstraint(
        id: 'p1-bottom',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 1,
        referencePlaneId: 'bottom',
      ),
      FamilySketchConstraint(
        id: 'p2-top',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 2,
        referencePlaneId: 'top',
      ),
      FamilySketchConstraint(
        id: 'p3-top',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.pointOnReferencePlane,
        pointAIndex: 3,
        referencePlaneId: 'top',
      ),
      FamilySketchConstraint(
        id: 'bottom-horizontal',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.horizontal,
        pointAIndex: 0,
        pointBIndex: 1,
      ),
      FamilySketchConstraint(
        id: 'right-vertical',
        sketchId: 'profile',
        kind: FamilySketchConstraintKind.vertical,
        pointAIndex: 1,
        pointBIndex: 2,
      ),
    ],
    features: const <FamilyFeature>[
      FamilyFeature(
        id: 'profile-feature',
        kind: FamilyFeatureKind.profile,
        inputs: <String>['profile'],
        parameters: <String, Object?>{'profileId': 'profile'},
      ),
      FamilyFeature(
        id: 'extrude-feature',
        kind: FamilyFeatureKind.extrude,
        inputs: <String>['profile'],
        parameters: <String, Object?>{
          'profileId': 'profile',
          'depth': 'depth',
        },
      ),
    ],
  );
}
