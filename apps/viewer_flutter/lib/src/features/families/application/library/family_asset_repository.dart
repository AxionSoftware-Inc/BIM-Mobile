import '../../domain/document/family_document.dart';
import 'family_asset_file.dart';

/// Storage port used by Family application services.
///
/// Local disk, cloud/team libraries and test doubles can implement the same
/// contract. Application code must not import dart:io, file_selector or the
/// concrete FamilyFileStore implementation.
abstract interface class FamilyAssetRepository {
  Future<List<FamilyAssetFile>> listStored();

  /// Resolves the semantic Family document referenced by one project element.
  ///
  /// [assetPath] is an opaque infrastructure locator. Implementations may use
  /// it first, then fall back to app-owned or bundled assets identified by
  /// [assetId]. Presentation/application callers never inspect the filesystem.
  Future<FamilyDocument?> resolveDocument({
    required String assetId,
    String assetPath = '',
  });

  Future<String?> save(FamilyDocument document);

  Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  });
}
