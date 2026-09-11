import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/annotations/application/annotation_render_batches.dart';
import 'package:viewer_flutter/src/features/annotations/domain/annotation_store.dart';

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

  test('detail lines use packed endpoint columns', () {
    final store = (AnnotationStoreBuilder()
          ..addDetailLine(
            viewId: 3,
            levelId: 2,
            startX: 1,
            startY: 2,
            startZ: 0,
            endX: 8,
            endY: 4,
            endZ: 0,
          ))
        .build();

    expect(store.detailLines.annotationIndices, hasLength(1));
    expect(store.detailLines.startPoints, <double>[1, 2, 0]);
    expect(store.detailLines.endPoints, <double>[8, 4, 0]);
    expect(store.kindAt(0), AnnotationKind.detailLine);
  });

  test('symbols intern shared asset keys instead of copying payloads', () {
    final builder = AnnotationStoreBuilder();
    for (var index = 0; index < 1000; index++) {
      builder.addSymbol(
        viewId: 5,
        levelId: 1,
        x: index.toDouble(),
        y: 0,
        z: 0,
        assetKey: 'symbol:north-arrow:v1',
      );
    }
    final store = builder.build();

    expect(store.symbols.annotationIndices, hasLength(1000));
    expect(store.strings.length, 1);
    expect(store.symbols.assetStringIds.toSet(), <int>{0});
    expect(store.queryView(5), hasLength(1000));
  });
}
