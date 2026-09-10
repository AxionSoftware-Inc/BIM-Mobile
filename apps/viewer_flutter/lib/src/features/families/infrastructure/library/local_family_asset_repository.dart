import '../../application/library/family_asset_file.dart';
import '../../application/library/family_asset_repository.dart';
import '../../domain/document/family_document.dart';
import 'family_file_store.dart';

/// Local app-owned Family Library implementation of the application storage port.
final class LocalFamilyAssetRepository implements FamilyAssetRepository {
  const LocalFamilyAssetRepository();

  @override
  Future<List<FamilyAssetFile>> listStored() => FamilyFileStore.listStored();

  @override
  Future<String?> save(FamilyDocument document) => FamilyFileStore.save(document);

  @override
  Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  }) =>
      FamilyFileStore.saveAsset(document, existingPath: existingPath);
}
