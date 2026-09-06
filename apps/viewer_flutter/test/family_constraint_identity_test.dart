import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('schema v4 index constraints migrate to stable point ids', () {
    final starter = FamilyDocument.starter();
    final legacySource = starter.copyWith(
      sketches: const <FamilySketch>[
        FamilySketch(
          id: 'profile',
          name: 'Legacy profile',
          plane: FamilySketchPlane.xy,
          points: <FamilySketchPoint>[
            FamilySketchPoint(x: 0, y: 0),
            FamilySketchPoint(x: 1, y: 0),
          ],
        ),
      ],
      constraints: const <FamilySketchConstraint>[
        FamilySketchConstraint(
          id: 'legacy-distance',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.distance,
          pointAIndex: 0,
          pointBIndex: 1,
          expression: 'width',
        ),
      ],
    );
    final json = legacySource.toJson()..['schema_version'] = 4;
    final loaded = FamilyDocument.fromJson(json);
    expect(loaded, isNotNull);

    final document = loaded!;
    expect(document.schemaVersion, 4);
    expect(document.sketches.single.points[0].id, 'profile:point-0');
    expect(document.sketches.single.points[1].id, 'profile:point-1');
    expect(document.constraints.single.pointAId, 'profile:point-0');
    expect(document.constraints.single.pointBId, 'profile:point-1');

    final edited = document.copyWith(name: 'Migrated');
    expect(edited.schemaVersion, 5);
  });

  test('stable ids keep a constraint attached after point reorder', () {
    final starter = FamilyDocument.starter();
    const sketch = FamilySketch(
      id: 'profile',
      name: 'Reorder profile',
      plane: FamilySketchPlane.xy,
      points: <FamilySketchPoint>[
        FamilySketchPoint(id: 'p2', x: 100, y: 0),
        FamilySketchPoint(id: 'p1', x: 1, y: 0),
        FamilySketchPoint(id: 'p0', x: 0, y: 0),
      ],
    );
    final document = starter.copyWith(
      types: <FamilyTypeDefinition>[
        starter.types.single.copyWith(values: <String, Object?>{
          ...starter.types.single.values,
          'width': 4.0,
        }),
      ],
      sketches: const <FamilySketch>[sketch],
      constraints: const <FamilySketchConstraint>[
        FamilySketchConstraint(
          id: 'distance',
          sketchId: 'profile',
          kind: FamilySketchConstraintKind.distance,
          // These snapshots describe the pre-reorder positions and are now
          // intentionally stale. Stable ids must win.
          pointAIndex: 0,
          pointAId: 'p0',
          pointBIndex: 1,
          pointBId: 'p1',
          expression: 'width',
        ),
      ],
    );

    final solved = FamilyConstraintSolver.solveSketch(
      document,
      document.types.single,
      sketch,
    ).sketch;
    final p0 = solved.points.singleWhere((point) => point.id == 'p0');
    final p1 = solved.points.singleWhere((point) => point.id == 'p1');
    final p2 = solved.points.singleWhere((point) => point.id == 'p2');
    expect(p0.x, closeTo(0, 1e-9));
    expect(p1.x, closeTo(4, 1e-6));
    expect(p2.x, closeTo(100, 1e-9));
  });

  test('duplicate stable point ids are rejected', () {
    final starter = FamilyDocument.starter();
    final invalid = starter.copyWith(
      sketches: const <FamilySketch>[
        FamilySketch(
          id: 'profile',
          name: 'Duplicate ids',
          plane: FamilySketchPlane.xy,
          points: <FamilySketchPoint>[
            FamilySketchPoint(id: 'same', x: 0, y: 0),
            FamilySketchPoint(id: 'same', x: 1, y: 0),
          ],
        ),
      ],
    );
    final validation = FamilyDocumentValidator.validate(invalid);
    expect(validation.isValid, isFalse);
    expect(
      validation.errors.any((error) => error.contains('duplicate point id')),
      isTrue,
    );
  });
}
