import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/annotations/annotation_document_controller.dart';
import 'package:viewer_flutter/src/annotations/annotation_store_codec.dart';

void main() {
  test('annotation undo redo stays independent and lossless', () {
    final controller = AnnotationDocumentController();
    controller.addText(
      viewId: 11,
      levelId: 2,
      x: 1,
      y: 2,
      z: 0,
      value: 'Kitchen',
    );
    controller.addSymbol(
      viewId: 11,
      levelId: 2,
      x: 3,
      y: 4,
      z: 0,
      assetKey: 'builtin:marker',
    );

    expect(controller.store.length, 2);
    expect(controller.canUndo, isTrue);
    expect(controller.undo(), isTrue);
    expect(controller.store.length, 1);
    expect(controller.canRedo, isTrue);
    expect(controller.redo(), isTrue);
    expect(controller.store.length, 2);
  });

  test('editing after undo branches annotation history', () {
    final controller = AnnotationDocumentController();
    controller.addText(
      viewId: 1,
      levelId: 1,
      x: 0,
      y: 0,
      z: 0,
      value: 'A',
    );
    controller.addText(
      viewId: 1,
      levelId: 1,
      x: 1,
      y: 0,
      z: 0,
      value: 'B',
    );
    controller.undo();
    controller.addText(
      viewId: 1,
      levelId: 1,
      x: 2,
      y: 0,
      z: 0,
      value: 'C',
    );

    expect(controller.store.length, 2);
    expect(controller.canRedo, isFalse);
  });

  test('versioned codec round trips all annotation kinds', () {
    final controller = AnnotationDocumentController();
    controller
      ..addText(
        viewId: 7,
        levelId: 3,
        x: 1,
        y: 1,
        z: 0,
        value: 'Note',
      )
      ..addLinearDimension(
        viewId: 7,
        levelId: 3,
        anchorX: 2,
        anchorY: 1,
        anchorZ: 0,
        startX: 0,
        startY: 0,
        startZ: 0,
        endX: 4,
        endY: 0,
        endZ: 0,
        referenceAId: 10,
        referenceBId: 20,
      )
      ..addTag(
        viewId: 7,
        levelId: 3,
        x: 2,
        y: 2,
        z: 0,
        targetElementId: 99,
        label: 'Door 99',
      )
      ..addDetailLine(
        viewId: 7,
        levelId: 3,
        startX: 0,
        startY: 2,
        startZ: 0,
        endX: 4,
        endY: 2,
        endZ: 0,
      )
      ..addSymbol(
        viewId: 7,
        levelId: 3,
        x: 3,
        y: 3,
        z: 0,
        assetKey: 'builtin:north-arrow',
      );

    final encoded = AnnotationStoreCodec.encode(controller.store);
    final decoded = AnnotationStoreCodec.decode(encoded);

    expect(decoded.length, 5);
    expect(decoded.queryView(7), hasLength(5));
    expect(decoded.text.annotationIndices, hasLength(1));
    expect(decoded.dimensions.annotationIndices, hasLength(1));
    expect(decoded.tags.annotationIndices, hasLength(1));
    expect(decoded.detailLines.annotationIndices, hasLength(1));
    expect(decoded.symbols.annotationIndices, hasLength(1));
  });
}
