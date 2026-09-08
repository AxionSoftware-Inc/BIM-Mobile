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

  static AnnotationDraftPoint? draftStart;
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
    if (activeViewId != nextViewId) cancelDraft();
    activeWorkspaceViewId = workspaceViewId;
    activeViewId = nextViewId;
    activeLevelId = levelId;
    activeViewAcceptsAnnotations = acceptsAnnotations && nextViewId != 0;
  }

  static void cancelDraft() {
    draftStart = null;
  }

  static void resetProject() {
    cancelDraft();
    activeViewId = 0;
    activeLevelId = 0;
    activeWorkspaceViewId = '';
    activeViewAcceptsAnnotations = false;
    document.reset();
  }
}

final class AnnotationDraftPoint {
  const AnnotationDraftPoint({
    required this.point,
    this.referenceElementId,
  });

  final RenderScenePoint point;
  final int? referenceElementId;
}
