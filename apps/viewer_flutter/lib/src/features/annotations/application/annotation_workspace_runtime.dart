import '../../../core/application/signals/application_notifier.dart';
import '../../../core/domain/scene/render_scene_models.dart';
import '../domain/annotation_view_key.dart';
import 'annotation_document_controller.dart';

/// Workspace-level annotation session.
///
/// BIM geometry stays in RenderScene/native cache, while annotations are
/// view-scoped and can be loaded/saved independently without forcing a geometry
/// rebuild. Observable application state is framework-neutral; Flutter adapts
/// these signals in the presentation layer.
abstract final class AnnotationWorkspaceRuntime {
  static final AnnotationDocumentController document =
      AnnotationDocumentController();

  /// Transient multi-tap command state is observable but never persisted.
  static final ApplicationValueNotifier<AnnotationDraftPoint?> draft =
      ApplicationValueNotifier<AnnotationDraftPoint?>(null);

  /// Selection is transient/view-local and never persisted.
  static final ApplicationValueNotifier<int?> selectedAnnotationId =
      ApplicationValueNotifier<int?>(null);

  /// Touch-safe move command state. Arming Move never rewrites the packed
  /// document; the next valid model tap commits exactly one translation.
  static final ApplicationValueNotifier<bool> moveSelectedArmed =
      ApplicationValueNotifier<bool>(false);

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
/// Keep this independent from WorkspaceToolSelection so annotation command
/// identity is not owned by presentation chrome.
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
