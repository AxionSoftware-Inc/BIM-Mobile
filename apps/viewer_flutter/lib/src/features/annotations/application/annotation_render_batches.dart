import 'dart:typed_data';

import '../domain/annotation_store.dart';

final class AnnotationRenderBatch {
  const AnnotationRenderBatch({
    required this.kind,
    required this.styleId,
    required this.annotationIndices,
  });

  final AnnotationKind kind;
  final int styleId;
  final Uint32List annotationIndices;
}

final class AnnotationRenderPlan {
  const AnnotationRenderPlan({
    required this.viewId,
    required this.batches,
    required this.visibleAnnotationCount,
  });

  final int viewId;
  final List<AnnotationRenderBatch> batches;
  final int visibleAnnotationCount;
}

/// Active-view annotation batching.
///
/// NEXT NATIVE RENDERER CONTRACT:
/// - Text batches resolve [AnnotationStore.text] through a shared glyph atlas;
/// - dimension/detail-line batches become one line/arrow buffer per style;
/// - tags resolve target values before batching, but reuse the same text atlas;
/// - only this plan crosses into the active viewport. Other sheets/floors stay
///   in the compact store and create zero render entities.
abstract final class AnnotationRenderPlanner {
  static AnnotationRenderPlan forView(AnnotationStore store, int viewId) {
    final visible = store.queryView(viewId);
    if (visible.isEmpty) {
      return AnnotationRenderPlan(
        viewId: viewId,
        batches: const <AnnotationRenderBatch>[],
        visibleAnnotationCount: 0,
      );
    }

    final groups = <int, List<int>>{};
    var count = 0;
    for (final annotationIndex in visible) {
      if (annotationIndex >= store.length) continue;
      if ((store.flags[annotationIndex] & AnnotationFlags.hidden) != 0) {
        continue;
      }
      final kind = store.kindAt(annotationIndex);
      final styleId = store.styleIds[annotationIndex];
      // Pack kind + style into one integer key. Number of kinds is tiny and
      // styles are shared, so the retained render object count stays small.
      final key = (kind.index << 24) | (styleId & 0x00FFFFFF);
      (groups[key] ??= <int>[]).add(annotationIndex);
      count++;
    }

    final batches = <AnnotationRenderBatch>[];
    for (final entry in groups.entries) {
      final kind = AnnotationKind.values[(entry.key >> 24) & 0xFF];
      final styleId = entry.key & 0x00FFFFFF;
      batches.add(
        AnnotationRenderBatch(
          kind: kind,
          styleId: styleId,
          annotationIndices: Uint32List.fromList(entry.value),
        ),
      );
    }
    batches.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      return byKind != 0 ? byKind : a.styleId.compareTo(b.styleId);
    });

    return AnnotationRenderPlan(
      viewId: viewId,
      batches: List.unmodifiable(batches),
      visibleAnnotationCount: count,
    );
  }
}
