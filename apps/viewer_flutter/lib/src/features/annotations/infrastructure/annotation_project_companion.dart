import 'dart:io';

import '../../../annotations/annotation_sidecar_store.dart';
import '../../../annotations/annotation_workspace_runtime.dart';
import '../../project/application/project_companion_document.dart';

/// Annotation feature adapter for the project companion-document lifecycle.
///
/// Project services know only `ProjectCompanionDocument`; annotation runtime,
/// sidecar format and transient selection/draft state remain owned here.
final class AnnotationProjectCompanion implements ProjectCompanionDocument {
  const AnnotationProjectCompanion({
    this.sidecar = const AnnotationSidecarStore(),
  });

  final AnnotationSidecarStore sidecar;

  @override
  String get key => 'annotations';

  @override
  Future<void> resetForNewProject() async {
    AnnotationWorkspaceRuntime.resetProject();
  }

  @override
  Future<void> restoreForProjectPath(String? projectPath) async {
    AnnotationWorkspaceRuntime.cancelDraft();
    if (projectPath == null || projectPath.trim().isEmpty) {
      AnnotationWorkspaceRuntime.document.reset();
      return;
    }
    try {
      final store = await sidecar.load(File(projectPath));
      if (store == null) {
        AnnotationWorkspaceRuntime.document.reset();
      } else {
        AnnotationWorkspaceRuntime.document.replaceStore(store);
      }
    } catch (_) {
      // Companion corruption must never make the authoritative BIM project
      // unopenable. Start with an empty annotation document instead.
      AnnotationWorkspaceRuntime.document.reset();
    }
  }

  @override
  Future<void> saveForProjectPath(String projectPath) async {
    await sidecar.save(
      projectFile: File(projectPath),
      store: AnnotationWorkspaceRuntime.document.store,
    );
  }
}
