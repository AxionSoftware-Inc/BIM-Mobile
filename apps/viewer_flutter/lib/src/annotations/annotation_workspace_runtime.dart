import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';
import 'annotation_document_controller.dart';
import 'annotation_view_key.dart';

/// Workspace-level annotation session.
///
/// This object intentionally owns only documentation state. BIM geometry stays
/// in RenderScene/native cache, while annotations are view-scoped and can be
/// loaded/saved independently without forcing a geometry rebuild.
abstract final class AnnotationWorkspaceRuntime {
  static final AnnotationDocumentController document =
      AnnotationDocumentController();

  /// Transient multi-tap command state is observable but never persisted.
  ///
  /// The first Dimension/Detail-Line point must update viewport controls
  /// immediately (especially Cancel) without forcing a document mutation or a
  /// BIM scene rebuild. A ValueNotifier is deliberately tiny and keeps draft
  /// lifetime separate from the packed annotation document.
  static final ValueNotifier<AnnotationDraftPoint?> draft =
      ValueNotifier<AnnotationDraftPoint?>(null);

  /// Selection is also transient/view-local. Persisting it in the annotation
  /// file would create meaningless document churn on every tap.
  static final ValueNotifier<int?> selectedAnnotationId =
      ValueNotifier<int?>(null);

  static AnnotationDraftPoint? get draftStart => draft.value;
  static set draftStart(AnnotationDraftPoint? value) => draft.value = value;

  static int activeViewId = 0;
  static int activeLevelId = 0;
  static String activeWorkspaceViewId = '';
  static bool activeViewAcceptsAnnotations = false;

  static void activateView({
    required String workspaceViewId,
    required int levelId,
    required bool acceptsAnnotations,
  }) {
    final nextViewId = workspaceViewId.isEmpty
        ? 0
        : AnnotationViewKey.fromWorkspaceId(workspaceViewId);
    if (activeViewId != nextViewId) {
      cancelDraft();
      clearSelection();
    }
    activeWorkspaceViewId = workspaceViewId;
    activeViewId = nextViewId;
    activeLevelId = levelId;
    activeViewAcceptsAnnotations = acceptsAnnotations && nextViewId != 0;
  }

  static void selectAnnotation(int? annotationId) {
    if (selectedAnnotationId.value != annotationId) {
      selectedAnnotationId.value = annotationId;
    }
  }

  static void clearSelection() => selectAnnotation(null);

  static void cancelDraft() {
    if (draft.value != null) draft.value = null;
  }

  static void resetProject() {
    cancelDraft();
    clearSelection();
    activeViewId = 0;
    activeLevelId = 0;
    activeWorkspaceViewId = '';
    activeViewAcceptsAnnotations = false;
    document.reset();
  }
}

/// Identity of a multi-tap annotation command that owns a transient draft.
///
/// Keep this independent from WorkspaceToolSelection: the annotation runtime
/// must remain usable by tests/headless document tooling without importing UI
/// chrome. More importantly, Dimension and Detail Line must never consume one
/// another's first point after the user switches tools mid-command.
enum AnnotationDraftKind { dimension, detailLine }

final class AnnotationDraftPoint {
  const AnnotationDraftPoint({
    required this.kind,
    required this.point,
    this.referenceElementId,
  });

  final AnnotationDraftKind kind;
  final RenderScenePoint point;
  final int? referenceElementId;
}
