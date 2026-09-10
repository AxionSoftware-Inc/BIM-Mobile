import '../../domain/document/family_document.dart';
import 'family_asset_file.dart';

/// Storage port used by Family application services.
///
/// Local disk, cloud/team libraries and test doubles can implement the same
/// contract. Application code must not import dart:io, file_selector or the
/// concrete FamilyFileStore implementation.
abstract interface class FamilyAssetRepository {
  Future<List<FamilyAssetFile>> listStored();

  Future<String?> save(FamilyDocument document);

  Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  });
}
