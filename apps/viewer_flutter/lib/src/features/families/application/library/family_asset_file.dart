import '../../domain/document/family_document.dart';

/// One validated Family asset address plus the type selected by the library UI.
///
/// The path is an infrastructure locator carried across the existing placement
/// boundary. The Family document remains the semantic source of truth.
final class FamilyAssetFile {
  const FamilyAssetFile({
    required this.document,
    required this.path,
    this.preferredTypeId,
  });

  final FamilyDocument document;
  final String path;
  final String? preferredTypeId;

  FamilyTypeDefinition get preferredType {
    final preferred = preferredTypeId;
    if (preferred != null) {
      for (final type in document.types) {
        if (type.id == preferred) return type;
      }
    }
    return document.types.first;
  }

  /// Compatibility behavior for placement callers that still read
  /// `document.types.first`. The persisted document is never reordered.
  FamilyAssetFile withPreferredType(FamilyTypeDefinition type) {
    if (!document.types.any((candidate) => candidate.id == type.id)) {
      throw ArgumentError.value(
        type.id,
        'type',
        'Type does not belong to family',
      );
    }
    final ordered = <FamilyTypeDefinition>[
      type,
      for (final candidate in document.types)
        if (candidate.id != type.id) candidate,
    ];
    return FamilyAssetFile(
      document: document.copyWith(types: ordered),
      path: path,
      preferredTypeId: type.id,
    );
  }
}
