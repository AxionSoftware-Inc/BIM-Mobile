import '../../application/dependencies/family_dependency_resolver.dart';
import '../../domain/document/family_document.dart';
import 'family_file_store.dart';

/// Infrastructure adapter that resolves nested families against app-owned
/// library storage, then delegates all dependency semantics to the pure
/// application resolver.
abstract final class FamilyLibraryDependencyResolver {
  static Future<FamilyDocument> resolve(
    FamilyDocument root,
    FamilyTypeDefinition rootType,
  ) async {
    final stored = await FamilyFileStore.listStored();
    return FamilyDependencyResolver.resolve(
      root,
      rootType,
      availableDocuments: <FamilyDocument>[
        root,
        for (final asset in stored) asset.document,
      ],
    );
  }
}
