import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/annotations/annotation_render_batches.dart';
import 'package:viewer_flutter/src/annotations/annotation_store.dart';

void main() {
  test('repeated text is interned once and views are indexed', () {
    final builder = AnnotationStoreBuilder();
    for (var index = 0; index < 10000; index++) {
      builder.addText(
        viewId: index.isEven ? 10 : 20,
        levelId: 1,
        x: index.toDouble(),
        y: 0,
        z: 0,
        value: 'Kitchen',
      );
    }
    final store = builder.build();

    expect(store.length, 10000);
    expect(store.strings.length, 1);
    expect(store.styles, hasLength(1));
    expect(store.queryView(10), hasLength(5000));
    expect(store.queryView(20), hasLength(5000));
    expect(store.queryView(999), isEmpty);
  });

  test('render planner sends only active visible annotations', () {
    final builder = AnnotationStoreBuilder()
      ..addText(
        viewId: 1,
        levelId: 1,
        x: 0,
        y: 0,
        z: 0,
        value: 'A',
      )
      ..addText(
        viewId: 2,
        levelId: 1,
        x: 1,
        y: 0,
        z: 0,
        value: 'B',
      )
      ..addTag(
        viewId: 1,
        levelId: 1,
        x: 2,
        y: 0,
        z: 0,
        targetElementId: 42,
        label: 'Door 42',
      )
      ..addText(
        viewId: 1,
        levelId: 1,
        x: 3,
        y: 0,
        z: 0,
        value: 'Hidden',
        flags: AnnotationFlags.hidden,
      );
    final store = builder.build();

    final plan = AnnotationRenderPlanner.forView(store, 1);

    expect(plan.visibleAnnotationCount, 2);
    expect(plan.batches, hasLength(2));
    expect(plan.batches.map((batch) => batch.kind).toSet(),
        <AnnotationKind>{AnnotationKind.text, AnnotationKind.tag});
  });

  test('dimension references stay packed and do not duplicate model data', () {
    final builder = AnnotationStoreBuilder();
    builder.addLinearDimension(
      viewId: 7,
      levelId: 3,
      anchorX: 0,
      anchorY: 1,
      anchorZ: 0,
      startX: 0,
      startY: 0,
      startZ: 0,
      endX: 5,
      endY: 0,
      endZ: 0,
      referenceAId: 101,
      referenceBId: 202,
      offsetMeters: 1,
    );
    final store = builder.build();

    expect(store.dimensions.annotationIndices, hasLength(1));
    expect(store.dimensions.referenceAIds.single, 101);
    expect(store.dimensions.referenceBIds.single, 202);
    expect(store.queryView(7), hasLength(1));
  });
}
