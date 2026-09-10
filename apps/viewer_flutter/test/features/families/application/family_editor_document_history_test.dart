import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/families/application/editor/family_editor_document_history.dart';
import 'package:viewer_flutter/src/features/families/domain/document/family_document.dart';

void main() {
  test('record clears redo and undo/redo restore immutable snapshots', () {
    final history = FamilyEditorDocumentHistory();
    final first = FamilyDocument.starter(name: 'First');
    final second = first.copyWith(name: 'Second');
    final third = second.copyWith(name: 'Third');

    history.record(first);
    history.record(second);

    expect(history.undo(third)?.name, 'Second');
    expect(history.undo(second)?.name, 'First');
    expect(history.redo(first)?.name, 'Second');

    history.record(third);
    expect(history.canRedo, isFalse);
  });

  test('history keeps the configured bounded undo window', () {
    final history = FamilyEditorDocumentHistory(limit: 2);
    final base = FamilyDocument.starter(name: '0');

    history.record(base.copyWith(name: '1'));
    history.record(base.copyWith(name: '2'));
    history.record(base.copyWith(name: '3'));

    expect(history.undoCount, 2);
    expect(history.undo(base.copyWith(name: '4'))?.name, '3');
    expect(history.undo(base.copyWith(name: '3'))?.name, '2');
    expect(history.canUndo, isFalse);
  });
}
