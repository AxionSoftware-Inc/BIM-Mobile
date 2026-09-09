// COMPATIBILITY ADAPTER.
// REMOVE WHEN: legacy Family Authoring presentation imports canonical scene builders.
import '../features/families/application/integration/family_authoring_scene_builder.dart'
    as canonical;
import '../features/families/domain/document/family_document.dart';
import '../features/families/infrastructure/library/family_library_authoring_scene_builder.dart';
import '../render_scene_models.dart';

@Deprecated('Import canonical Family scene builders from features/families.')
abstract final class FamilyAuthoringSceneBuilder {
  static int elementIdForFeatureIndex(int index) =>
      canonical.FamilyAuthoringSceneBuilder.elementIdForFeatureIndex(index);

  static Future<RenderScene> buildCandidates(
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required Iterable<String> featureIds,
  }) =>
      FamilyLibraryAuthoringSceneBuilder.buildCandidates(
        document,
        type,
        featureIds: featureIds,
      );

  static String? featureIdForObject(RenderSceneObject? object) =>
      canonical.FamilyAuthoringSceneBuilder.featureIdForObject(object);
}
