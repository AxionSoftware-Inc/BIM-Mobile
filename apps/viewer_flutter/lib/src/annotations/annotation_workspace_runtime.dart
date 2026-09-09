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

  /// Touch-safe move command state. Arming Move never rewrites the packed
  /// document; the next valid model tap commits exactly one translation.
  /// A future live drag preview can reuse this command boundary and still
  /// publish only once on pointer-up.
  static final ValueNotifier<bool> moveSelectedArmed =
      ValueNotifier<bool>(false);

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
      cancelSelectedMove();
      selectedAnnotationId.value = annotationId;
    }
  }

  static void clearSelection() {
    cancelSelectedMove();
    selectAnnotation(null);
  }

  static void armSelectedMove() {
    if (selectedAnnotationId.value == null) return;
    cancelDraft();
    if (!moveSelectedArmed.value) moveSelectedArmed.value = true;
  }

  static void cancelSelectedMove() {
    if (moveSelectedArmed.value) moveSelectedArmed.value = false;
  }

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
