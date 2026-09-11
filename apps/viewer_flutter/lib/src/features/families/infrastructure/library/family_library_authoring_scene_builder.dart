import '../../../../core/application/render_scene/render_scene_models.dart';
import '../../application/integration/family_authoring_scene_builder.dart';
import '../../domain/document/family_document.dart';
import 'family_file_store.dart';

/// Library-backed adapter for Family authoring candidate scenes.
abstract final class FamilyLibraryAuthoringSceneBuilder {
  static Future<RenderScene> buildCandidates(
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required Iterable<String> featureIds,
  }) async {
    final stored = await FamilyFileStore.listStored();
    return FamilyAuthoringSceneBuilder.buildCandidates(
      document,
      type,
      featureIds: featureIds,
      availableDocuments: <FamilyDocument>[
        document,
        for (final asset in stored) asset.document,
      ],
    );
  }
}
