import '../../../core/application/signals/application_notifier.dart';
import '../domain/annotation_store.dart';
import 'annotation_store_editor.dart';

/// Mutable command boundary over the immutable packed annotation store.
///
/// RUNTIME CONTRACT:
/// - renderers only ever observe immutable typed-array snapshots;
/// - UI draft objects never become the document model;
/// - annotation undo/redo is independent from BIM geometry history, so a text
///   edit cannot rebuild walls or invalidate the native BIM cache;
/// - history retains immutable snapshots and rebuilds the write-side builder
///   only when undo/redo or a committed packed rewrite actually happens.
final class AnnotationDocumentController extends ApplicationChangeNotifier {
  AnnotationStoreBuilder _builder = AnnotationStoreBuilder();
  AnnotationStore _store = AnnotationStore.empty();
  final List<AnnotationStore> _undo = <AnnotationStore>[];
  final List<AnnotationStore> _redo = <AnnotationStore>[];
  int _revision = 0;

  static const int maxHistoryEntries = 64;

  AnnotationStore get store => _store;
  int get revision => _revision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void reset({bool clearHistory = true}) {
    _builder = AnnotationStoreBuilder();
    _store = AnnotationStore.empty();
    if (clearHistory) {
      _undo.clear();
      _redo.clear();
    }
    _revision++;
    notifyListeners();
  }

  /// Replaces the whole annotation document after project/sidecar loading.
  /// Loading is a document boundary, not an undoable edit.
  void replaceStore(AnnotationStore value) {
    _store = value;
    _builder = _builderFromStore(value);
    _undo.clear();
    _redo.clear();
    _revision++;
    notifyListeners();
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(_store);
    _store = _undo.removeLast();
    _builder = _builderFromStore(_store);
    _revision++;
    notifyListeners();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_store);
    _store = _redo.removeLast();
    _builder = _builderFromStore(_store);
    _revision++;
    notifyListeners();
    return true;
  }

  int addText({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String value,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Text'),
    double rotationRadians = 0,
  }) {
    _beginMutation();
    final id = _builder.addText(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      value: value,
      style: style,
      rotationRadians: rotationRadians,
    );
    _publish();
    return id;
  }

  int addLinearDimension({
    required int viewId,
    required int levelId,
    required double anchorX,
    required double anchorY,
    required double anchorZ,
    required double startX,
    required double startY,
    required double startZ,
    required double endX,
    required double endY,
    required double endZ,
    int? referenceAId,
    int? referenceBId,
    double offsetMeters = 0,
    AnnotationStyle style =
        const AnnotationStyle(name: 'Default Dimension'),
  }) {
    _beginMutation();
    final id = _builder.addLinearDimension(
      viewId: viewId,
      levelId: levelId,
      anchorX: anchorX,
      anchorY: anchorY,
      anchorZ: anchorZ,
      startX: startX,
      startY: startY,
      startZ: startZ,
      endX: endX,
      endY: endY,
      endZ: endZ,
      referenceAId: referenceAId,
      referenceBId: referenceBId,
      offsetMeters: offsetMeters,
      style: style,
    );
    _publish();
    return id;
  }

  int addTag({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required int targetElementId,
    required String label,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Tag'),
  }) {
    _beginMutation();
    final id = _builder.addTag(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      targetElementId: targetElementId,
      label: label,
      style: style,
    );
    _publish();
    return id;
  }

  int addDetailLine({
    required int viewId,
    required int levelId,
    required double startX,
    required double startY,
    required double startZ,
    required double endX,
    required double endY,
    required double endZ,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Detail Line'),
  }) {
    _beginMutation();
    final id = _builder.addDetailLine(
      viewId: viewId,
      levelId: levelId,
      startX: startX,
      startY: startY,
      startZ: startZ,
      endX: endX,
      endY: endY,
      endZ: endZ,
      style: style,
    );
    _publish();
    return id;
  }

  int addSymbol({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String assetKey,
    double rotationRadians = 0,
    double scale = 1,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Symbol'),
  }) {
    _beginMutation();
    final id = _builder.addSymbol(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      assetKey: assetKey,
      rotationRadians: rotationRadians,
      scale: scale,
      style: style,
    );
    _publish();
    return id;
  }

  /// Deletes one persistent annotation without touching BIM geometry history.
  bool deleteAnnotation(int annotationId) => _commitPackedRewrite(
        AnnotationStoreEditor.deleteById(_store, annotationId),
      );

  /// Commits a translation after a drag preview finishes. Pointer-move frames
  /// must stay transient; rebuilding the immutable packed store on every pixel
  /// would turn a large annotation sheet into an O(N) drag loop.
  bool moveAnnotation(
    int annotationId, {
    required double dx,
    required double dy,
    required double dz,
  }) =>
      _commitPackedRewrite(
        AnnotationStoreEditor.moveById(
          _store,
          annotationId,
          dx: dx,
          dy: dy,
          dz: dz,
        ),
      );

  bool replaceAnnotationLabel(int annotationId, String value) =>
      _commitPackedRewrite(
        AnnotationStoreEditor.replaceLabelById(
          _store,
          annotationId,
          value,
        ),
      );

  bool replaceAnnotationStyle(int annotationId, AnnotationStyle style) =>
      _commitPackedRewrite(
        AnnotationStoreEditor.replaceStyleById(
          _store,
          annotationId,
          style,
        ),
      );

  void _beginMutation() {
    _undo.add(_store);
    if (_undo.length > maxHistoryEntries) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  void _publish() {
    _store = _builder.build();
    _revision++;
    notifyListeners();
  }

  bool _commitPackedRewrite(AnnotationStore next) {
    if (identical(next, _store)) return false;
    _beginMutation();
    _store = next;
    _builder = _builderFromStore(next);
    _revision++;
    notifyListeners();
    return true;
  }

  static AnnotationStoreBuilder _builderFromStore(AnnotationStore store) {
    final builder = AnnotationStoreBuilder();
    final textRows = <int, int>{};
    for (var row = 0; row < store.text.annotationIndices.length; row++) {
      textRows[store.text.annotationIndices[row]] = row;
    }
    final dimensionRows = <int, int>{};
    for (var row = 0; row < store.dimensions.annotationIndices.length; row++) {
      dimensionRows[store.dimensions.annotationIndices[row]] = row;
    }
    final tagRows = <int, int>{};
    for (var row = 0; row < store.tags.annotationIndices.length; row++) {
      tagRows[store.tags.annotationIndices[row]] = row;
    }
    final detailRows = <int, int>{};
    for (var row = 0; row < store.detailLines.annotationIndices.length; row++) {
      detailRows[store.detailLines.annotationIndices[row]] = row;
    }
    final symbolRows = <int, int>{};
    for (var row = 0; row < store.symbols.annotationIndices.length; row++) {
      symbolRows[store.symbols.annotationIndices[row]] = row;
    }

    for (var annotationIndex = 0;
        annotationIndex < store.length;
        annotationIndex++) {
      final anchor = annotationIndex * 3;
      final style = store.styles[store.styleIds[annotationIndex]];
      final common = (
        id: store.annotationIds[annotationIndex],
        viewId: store.viewIds[annotationIndex],
        levelId: store.levelIds[annotationIndex],
        x: store.anchors[anchor],
        y: store.anchors[anchor + 1],
        z: store.anchors[anchor + 2],
        flags: store.flags[annotationIndex],
      );
      switch (store.kindAt(annotationIndex)) {
        case AnnotationKind.text:
          final row = textRows[annotationIndex];
          if (row == null) continue;
          builder.addText(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            x: common.x,
            y: common.y,
            z: common.z,
            value: store.strings[store.text.stringIds[row]],
            style: style,
            rotationRadians: store.text.rotations[row],
            flags: common.flags,
          );
        case AnnotationKind.linearDimension:
          final row = dimensionRows[annotationIndex];
          if (row == null) continue;
          final p = row * 3;
          final referenceA = store.dimensions.referenceAIds[row];
          final referenceB = store.dimensions.referenceBIds[row];
          builder.addLinearDimension(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            anchorX: common.x,
            anchorY: common.y,
            anchorZ: common.z,
            startX: store.dimensions.startPoints[p],
            startY: store.dimensions.startPoints[p + 1],
            startZ: store.dimensions.startPoints[p + 2],
            endX: store.dimensions.endPoints[p],
            endY: store.dimensions.endPoints[p + 1],
            endZ: store.dimensions.endPoints[p + 2],
            referenceAId: referenceA < 0 ? null : referenceA,
            referenceBId: referenceB < 0 ? null : referenceB,
            offsetMeters: store.dimensions.offsets[row],
            style: style,
            flags: common.flags,
          );
        case AnnotationKind.tag:
          final row = tagRows[annotationIndex];
          if (row == null) continue;
          builder.addTag(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            x: common.x,
            y: common.y,
            z: common.z,
            targetElementId: store.tags.targetElementIds[row],
            label: store.strings[store.tags.labelStringIds[row]],
            style: style,
            flags: common.flags,
          );
        case AnnotationKind.detailLine:
          final row = detailRows[annotationIndex];
          if (row == null) continue;
          final p = row * 3;
          builder.addDetailLine(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            startX: store.detailLines.startPoints[p],
            startY: store.detailLines.startPoints[p + 1],
            startZ: store.detailLines.startPoints[p + 2],
            endX: store.detailLines.endPoints[p],
            endY: store.detailLines.endPoints[p + 1],
            endZ: store.detailLines.endPoints[p + 2],
            style: style,
            flags: common.flags,
          );
        case AnnotationKind.symbol:
          final row = symbolRows[annotationIndex];
          if (row == null) continue;
          builder.addSymbol(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            x: common.x,
            y: common.y,
            z: common.z,
            assetKey: store.strings[store.symbols.assetStringIds[row]],
            rotationRadians: store.symbols.rotations[row],
            scale: store.symbols.scales[row],
            style: style,
            flags: common.flags,
          );
      }
    }
    return builder;
  }
}
