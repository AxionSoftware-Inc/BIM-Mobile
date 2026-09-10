import '../dependencies/family_dependency_resolver.dart';
import '../library/family_asset_repository.dart';
import '../../domain/document/family_document.dart';
import '../../domain/validation/family_validation.dart';

final class FamilyEditorSaveResult {
  const FamilyEditorSaveResult({
    required this.document,
    required this.path,
  });

  final FamilyDocument document;
  final String path;
}

/// Application use-case for validating and persisting one authored Family.
///
/// UI owns the text field and progress/error presentation. This service owns
/// semantic validation, nested dependency preflight for every Family Type and
/// the decision between first save and save-to-existing-asset.
final class FamilyEditorSaveService {
  const FamilyEditorSaveService(this.repository);

  final FamilyAssetRepository repository;

  Future<FamilyEditorSaveResult> save(
    FamilyDocument document, {
    String? existingPath,
  }) async {
    final validation = FamilyDocumentValidator.validate(document);
    if (!validation.isValid) {
      throw FormatException(validation.errors.first);
    }

    await _preflightDependencies(document);

    final normalizedPath = existingPath?.trim();
    final String? path;
    if (normalizedPath == null || normalizedPath.isEmpty) {
      path = await repository.save(document);
    } else {
      path = await repository.saveAsset(
        document,
        existingPath: normalizedPath,
      );
    }
    if (path == null || path.trim().isEmpty) {
      throw const FileSystemException(
        'Family save did not return a persistent asset path.',
      );
    }
    return FamilyEditorSaveResult(document: document, path: path);
  }

  Future<void> _preflightDependencies(FamilyDocument candidate) async {
    if (!candidate.features.any(
      (feature) => feature.kind == FamilyFeatureKind.nestedFamily,
    )) {
      return;
    }

    final assets = await repository.listStored();
    final available = <FamilyDocument>[
      candidate,
      for (final asset in assets)
        if (asset.document.id != candidate.id) asset.document,
    ];
    for (final type in candidate.types) {
      FamilyDependencyResolver.resolve(
        candidate,
        type,
        availableDocuments: available,
      );
    }
  }
}
