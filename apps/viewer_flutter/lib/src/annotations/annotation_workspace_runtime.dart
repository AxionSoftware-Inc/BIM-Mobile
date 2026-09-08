import '../render_scene_models.dart';
import 'annotation_document_controller.dart';

/// Workspace-level annotation session.
///
/// This is intentionally small and contains no render geometry. The persistent
/// document remains a packed AnnotationStore; the only transient state is the
/// first point of a two-step dimension/detail command.
abstract final class AnnotationWorkspaceRuntime {
  static final AnnotationDocumentController document =
      AnnotationDocumentController();

  static AnnotationDraftPoint? dimensionStart;

  static void cancelDraft() {
    dimensionStart = null;
  }

  static void resetProject() {
    cancelDraft();
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
