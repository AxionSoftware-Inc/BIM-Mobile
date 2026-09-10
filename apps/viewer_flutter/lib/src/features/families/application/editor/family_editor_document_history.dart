import '../../domain/document/family_document.dart';

/// Pure undo/redo history for Family Editor document snapshots.
///
/// The editor UI owns selection/focus/tool state; this class owns only immutable
/// FamilyDocument snapshots. Keeping history outside the widget prevents save,
/// viewport and presentation code from each inventing a different undo model.
final class FamilyEditorDocumentHistory {
  FamilyEditorDocumentHistory({this.limit = 100})
      : assert(limit > 0, 'History limit must be positive.');

  final int limit;
  final List<FamilyDocument> _undo = <FamilyDocument>[];
  final List<FamilyDocument> _redo = <FamilyDocument>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  void record(FamilyDocument previous) {
    _undo.add(previous);
    if (_undo.length > limit) {
      _undo.removeRange(0, _undo.length - limit);
    }
    _redo.clear();
  }

  FamilyDocument? undo(FamilyDocument current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  FamilyDocument? redo(FamilyDocument current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    if (_undo.length > limit) {
      _undo.removeRange(0, _undo.length - limit);
    }
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
