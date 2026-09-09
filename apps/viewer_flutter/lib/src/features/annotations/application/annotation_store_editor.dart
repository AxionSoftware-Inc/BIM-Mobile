import '../domain/annotation_store.dart';

/// Immutable packed-store rewrite helpers for committed annotation edits.
///
/// PERFORMANCE CONTRACT:
/// - call these only at command commit boundaries (tap Delete, drag end,
///   properties Apply), never on every pointer-move frame;
/// - live move/resize previews belong in a transient overlay/delta layer;
/// - the result is another immutable packed snapshot, which makes annotation
///   undo/redo cheap and keeps documentation edits out of BIM geometry/cache;
/// - if annotation documents eventually reach millions of rows, this boundary
///   can be replaced by chunked pages without changing viewport commands.
abstract final class AnnotationStoreEditor {
  static AnnotationStore deleteById(AnnotationStore store, int annotationId) =>
      _rewrite(store, annotationId: annotationId, deleteTarget: true);

  static AnnotationStore moveById(
    AnnotationStore store,
    int annotationId, {
    required double dx,
    required double dy,
    required double dz,
  }) {
    if (!dx.isFinite || !dy.isFinite || !dz.isFinite) return store;
    if (dx == 0 && dy == 0 && dz == 0) return store;
    return _rewrite(
      store,
      annotationId: annotationId,
      dx: dx,
      dy: dy,
      dz: dz,
    );
  }

  /// Edits visible text for Text and Tag annotations. Other kinds are returned
  /// unchanged because their semantic payload is not a free-form label.
  static AnnotationStore replaceLabelById(
    AnnotationStore store,
    int annotationId,
    String value,
  ) =>
      _rewrite(
        store,
        annotationId: annotationId,
        replacementLabel: value,
      );

  static AnnotationStore replaceStyleById(
    AnnotationStore store,
    int annotationId,
    AnnotationStyle style,
  ) =>
      _rewrite(
        store,
        annotationId: annotationId,
        replacementStyle: style,
      );

  static AnnotationStore _rewrite(
    AnnotationStore store, {
    required int annotationId,
    bool deleteTarget = false,
    double dx = 0,
    double dy = 0,
    double dz = 0,
    String? replacementLabel,
    AnnotationStyle? replacementStyle,
  }) {
    var targetFound = false;
    var targetMutated = false;
    final builder = AnnotationStoreBuilder();

    final textRows = _rowMap(store.text.annotationIndices);
    final dimensionRows = _rowMap(store.dimensions.annotationIndices);
    final tagRows = _rowMap(store.tags.annotationIndices);
    final detailRows = _rowMap(store.detailLines.annotationIndices);
    final symbolRows = _rowMap(store.symbols.annotationIndices);

    for (var annotationIndex = 0;
        annotationIndex < store.length;
        annotationIndex++) {
      final id = store.annotationIds[annotationIndex];
      final target = id == annotationId;
      if (target) targetFound = true;
      if (target && deleteTarget) {
        targetMutated = true;
        continue;
      }

      final anchor = annotationIndex * 3;
      final translateX = target ? dx : 0.0;
      final translateY = target ? dy : 0.0;
      final translateZ = target ? dz : 0.0;
      if (target && (dx != 0 || dy != 0 || dz != 0)) targetMutated = true;

      final currentStyle = store.styles[store.styleIds[annotationIndex]];
      final style = target && replacementStyle != null
          ? replacementStyle
          : currentStyle;
      if (target &&
          replacementStyle != null &&
          replacementStyle.signature != currentStyle.signature) {
        targetMutated = true;
      }
      final common = (
        id: id,
        viewId: store.viewIds[annotationIndex],
        levelId: store.levelIds[annotationIndex],
        x: store.anchors[anchor] + translateX,
        y: store.anchors[anchor + 1] + translateY,
        z: store.anchors[anchor + 2] + translateZ,
        flags: store.flags[annotationIndex],
      );

      switch (store.kindAt(annotationIndex)) {
        case AnnotationKind.text:
          final row = textRows[annotationIndex];
          if (row == null) continue;
          final oldValue = store.strings[store.text.stringIds[row]];
          final value = target && replacementLabel != null
              ? replacementLabel
              : oldValue;
          if (target && replacementLabel != null && value != oldValue) {
            targetMutated = true;
          }
          builder.addText(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            x: common.x,
            y: common.y,
            z: common.z,
            value: value,
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
            startX: store.dimensions.startPoints[p] + translateX,
            startY: store.dimensions.startPoints[p + 1] + translateY,
            startZ: store.dimensions.startPoints[p + 2] + translateZ,
            endX: store.dimensions.endPoints[p] + translateX,
            endY: store.dimensions.endPoints[p + 1] + translateY,
            endZ: store.dimensions.endPoints[p + 2] + translateZ,
            referenceAId: referenceA < 0 ? null : referenceA,
            referenceBId: referenceB < 0 ? null : referenceB,
            offsetMeters: store.dimensions.offsets[row],
            style: style,
            flags: common.flags,
          );
        case AnnotationKind.tag:
          final row = tagRows[annotationIndex];
          if (row == null) continue;
          final oldValue = store.strings[store.tags.labelStringIds[row]];
          final value = target && replacementLabel != null
              ? replacementLabel
              : oldValue;
          if (target && replacementLabel != null && value != oldValue) {
            targetMutated = true;
          }
          builder.addTag(
            annotationId: common.id,
            viewId: common.viewId,
            levelId: common.levelId,
            x: common.x,
            y: common.y,
            z: common.z,
            targetElementId: store.tags.targetElementIds[row],
            label: value,
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
            startX: store.detailLines.startPoints[p] + translateX,
            startY: store.detailLines.startPoints[p + 1] + translateY,
            startZ: store.detailLines.startPoints[p + 2] + translateZ,
            endX: store.detailLines.endPoints[p] + translateX,
            endY: store.detailLines.endPoints[p + 1] + translateY,
            endZ: store.detailLines.endPoints[p + 2] + translateZ,
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

    return targetFound && targetMutated ? builder.build() : store;
  }

  static Map<int, int> _rowMap(List<int> annotationIndices) {
    final result = <int, int>{};
    for (var row = 0; row < annotationIndices.length; row++) {
      result[annotationIndices[row]] = row;
    }
    return result;
  }
}
