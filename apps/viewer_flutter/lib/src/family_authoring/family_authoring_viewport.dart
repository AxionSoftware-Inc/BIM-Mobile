// COMPATIBILITY ADAPTER.
// REMOVE WHEN: legacy Family Editor imports the canonical viewport and injects
// its candidate-scene loader at the composition root.
import 'package:flutter/widgets.dart';

import '../features/families/domain/document/family_document.dart';
import '../features/families/domain/geometry/family_geometry.dart';
import '../features/families/infrastructure/library/family_library_authoring_scene_builder.dart';
import '../features/families/presentation/viewport/family_authoring_viewport.dart'
    as canonical;

export '../features/families/presentation/viewport/family_authoring_viewport.dart'
    show
        FamilyAuthoringViewportMode,
        FamilyGizmoMode,
        FamilyGizmoAxis,
        FamilyCandidateSceneLoader;

@Deprecated('Import the canonical Family viewport from features/families.')
class FamilyAuthoringViewport extends canonical.FamilyAuthoringViewport {
  const FamilyAuthoringViewport({
    Key? key,
    required FamilyDocument document,
    required FamilyTypeDefinition type,
    required FamilyEvaluatedMesh mesh,
    canonical.FamilyAuthoringViewportMode mode =
        canonical.FamilyAuthoringViewportMode.result,
    Set<String> candidateFeatureIds = const <String>{},
    Set<String> selectedFeatureIds = const <String>{},
    String? gizmoFeatureId,
    canonical.FamilyGizmoMode gizmoMode = canonical.FamilyGizmoMode.none,
    ValueChanged<String?>? onFeatureSelected,
    ValueChanged<String?>? onFinalFeatureSelected,
    ValueChanged<canonical.FamilyGizmoAxis>? onGizmoBegin,
    void Function(canonical.FamilyGizmoAxis axis, double delta)? onGizmoChanged,
    ValueChanged<canonical.FamilyGizmoAxis>? onGizmoEnd,
    ValueChanged<canonical.FamilyGizmoAxis>? onGizmoCancel,
    String? prompt,
    bool showDiagnostics = false,
  }) : super(
          key: key,
          document: document,
          type: type,
          mesh: mesh,
          candidateSceneLoader:
              FamilyLibraryAuthoringSceneBuilder.buildCandidates,
          mode: mode,
          candidateFeatureIds: candidateFeatureIds,
          selectedFeatureIds: selectedFeatureIds,
          gizmoFeatureId: gizmoFeatureId,
          gizmoMode: gizmoMode,
          onFeatureSelected: onFeatureSelected,
          onFinalFeatureSelected: onFinalFeatureSelected,
          onGizmoBegin: onGizmoBegin,
          onGizmoChanged: onGizmoChanged,
          onGizmoEnd: onGizmoEnd,
          onGizmoCancel: onGizmoCancel,
          prompt: prompt,
          showDiagnostics: showDiagnostics,
        );
}
