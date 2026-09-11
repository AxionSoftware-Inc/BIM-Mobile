import '../../application/library/family_asset_file.dart';
import '../../application/library/family_asset_repository.dart';
import '../../domain/document/family_document.dart';
import '../catalog/built_in_family_catalog.dart';
import 'family_file_store.dart';

/// Local app-owned Family Library implementation of the application storage port.
final class LocalFamilyAssetRepository implements FamilyAssetRepository {
  const LocalFamilyAssetRepository();

  @override
  Future<List<FamilyAssetFile>> listStored() => FamilyFileStore.listStored();

  @override
  Future<FamilyDocument?> resolveDocument({
    required String assetId,
    String assetPath = '',
  }) async {
    final normalizedId = assetId.trim();
    if (normalizedId.isEmpty) return null;

    final normalizedPath = assetPath.trim();
    if (normalizedPath.isNotEmpty) {
      final referenced = await FamilyFileStore.loadPath(normalizedPath);
      if (referenced?.document.id == normalizedId) {
        return referenced!.document;
      }
    }

    for (final asset in await FamilyFileStore.listStored()) {
      if (asset.document.id == normalizedId) return asset.document;
    }
    for (final family in BuiltInFamilyCatalog.families) {
      if (family.id == normalizedId) return family;
    }
    return null;
  }

  @override
  Future<String?> save(FamilyDocument document) => FamilyFileStore.save(document);

  @override
  Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  }) =>
      FamilyFileStore.saveAsset(document, existingPath: existingPath);
}
