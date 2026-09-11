import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/annotations/application/annotation_document_controller.dart';
import 'package:viewer_flutter/src/features/annotations/domain/annotation_store.dart';

void main() {
  test('move commits one packed translation and remains undoable', () {
    final document = AnnotationDocumentController();
    final id = document.addText(
      viewId: 7,
      levelId: 2,
      x: 1,
      y: 2,
      z: 3,
      value: 'A',
    );
    final beforeMove = document.revision;

    expect(
      document.moveAnnotation(id, dx: 4, dy: -1, dz: 0.5),
      isTrue,
    );
    expect(document.revision, beforeMove + 1);
    expect(document.store.anchors[0], 5);
    expect(document.store.anchors[1], 1);
    expect(document.store.anchors[2], 3.5);

    expect(document.undo(), isTrue);
    expect(document.store.anchors[0], 1);
    expect(document.store.anchors[1], 2);
    expect(document.store.anchors[2], 3);
  });

  test('moving dimension translates anchor and both measured endpoints', () {
    final document = AnnotationDocumentController();
    final id = document.addLinearDimension(
      viewId: 1,
      levelId: 1,
      anchorX: 2,
      anchorY: 3,
      anchorZ: 0,
      startX: 0,
      startY: 0,
      startZ: 0,
      endX: 4,
      endY: 0,
      endZ: 0,
    );

    expect(document.moveAnnotation(id, dx: 10, dy: 20, dz: 1), isTrue);
    expect(document.store.anchors.sublist(0, 3), <double>[12, 23, 1]);
    expect(
      document.store.dimensions.startPoints.sublist(0, 3),
      <double>[10, 20, 1],
    );
    expect(
      document.store.dimensions.endPoints.sublist(0, 3),
      <double>[14, 20, 1],
    );
  });

  test('delete does not renumber surviving persistent annotation ids', () {
    final document = AnnotationDocumentController();
    final first = document.addText(
      viewId: 1,
      levelId: 1,
      x: 0,
      y: 0,
      z: 0,
      value: 'first',
    );
    final second = document.addText(
      viewId: 1,
      levelId: 1,
      x: 1,
      y: 0,
      z: 0,
      value: 'second',
    );

    expect(document.deleteAnnotation(first), isTrue);
    expect(document.store.length, 1);
    expect(document.store.annotationIds.single, second);
    expect(document.undo(), isTrue);
    expect(document.store.annotationIds, <int>[first, second]);
  });

  test('label edit applies only to text/tag and ignores no-op operations', () {
    final document = AnnotationDocumentController();
    final text = document.addText(
      viewId: 1,
      levelId: 1,
      x: 0,
      y: 0,
      z: 0,
      value: 'old',
    );
    final dimension = document.addLinearDimension(
      viewId: 1,
      levelId: 1,
      anchorX: 0,
      anchorY: 0,
      anchorZ: 0,
      startX: 0,
      startY: 0,
      startZ: 0,
      endX: 1,
      endY: 0,
      endZ: 0,
    );

    final revision = document.revision;
    expect(document.replaceAnnotationLabel(text, 'new'), isTrue);
    expect(document.store.strings[document.store.text.stringIds.single], 'new');
    expect(document.revision, revision + 1);

    final afterText = document.revision;
    expect(document.replaceAnnotationLabel(dimension, 'ignored'), isFalse);
    expect(document.revision, afterText);
    expect(document.moveAnnotation(text, dx: 0, dy: 0, dz: 0), isFalse);
    expect(document.deleteAnnotation(999999), isFalse);
    expect(document.revision, afterText);
  });

  test(
      'style change is shared/interpreted without changing annotation identity',
      () {
    final document = AnnotationDocumentController();
    final id = document.addText(
      viewId: 1,
      levelId: 1,
      x: 0,
      y: 0,
      z: 0,
      value: 'note',
    );
    const style = AnnotationStyle(
      name: 'Large Note',
      textHeightMeters: 0.005,
      lineWeight: 2,
    );

    expect(document.replaceAnnotationStyle(id, style), isTrue);
    expect(document.store.annotationIds.single, id);
    expect(document.store.styles[document.store.styleIds.single].name,
        'Large Note');
    expect(document.replaceAnnotationStyle(id, style), isFalse);
  });
}
