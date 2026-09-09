// COMPATIBILITY ADAPTER.
// REMOVE WHEN: legacy Family Authoring presentation imports canonical owners.
import '../features/families/application/dependencies/family_dependency_resolver.dart'
    as canonical;
import '../features/families/domain/document/family_document.dart';
import '../features/families/infrastructure/library/family_library_dependency_resolver.dart';

@Deprecated('Import canonical Family dependency owners from features/families.')
abstract final class FamilyDependencyResolver {
  static Future<FamilyDocument> resolveFromLibrary(
    FamilyDocument root,
    FamilyTypeDefinition rootType,
  ) =>
      FamilyLibraryDependencyResolver.resolve(root, rootType);

  static FamilyDocument resolve(
    FamilyDocument root,
    FamilyTypeDefinition rootType, {
    required Iterable<FamilyDocument> availableDocuments,
  }) =>
      canonical.FamilyDependencyResolver.resolve(
        root,
        rootType,
        availableDocuments: availableDocuments,
      );
}
