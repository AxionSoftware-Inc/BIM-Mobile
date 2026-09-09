/// User/library preferences for a potentially large Family Library.
///
/// Favorites and recents are application state, not BIM project semantics.
final class FamilyLibraryPreferences {
  const FamilyLibraryPreferences({
    this.favoriteFamilyIds = const <String>{},
    this.recentFamilyIds = const <String>[],
  });

  final Set<String> favoriteFamilyIds;
  final List<String> recentFamilyIds;

  bool isFavorite(String familyId) => favoriteFamilyIds.contains(familyId);

  FamilyLibraryPreferences toggleFavorite(String familyId) {
    final next = <String>{...favoriteFamilyIds};
    if (!next.add(familyId)) next.remove(familyId);
    return FamilyLibraryPreferences(
      favoriteFamilyIds: Set<String>.unmodifiable(next),
      recentFamilyIds: recentFamilyIds,
    );
  }

  FamilyLibraryPreferences recordRecent(String familyId) {
    final next = <String>[
      familyId,
      for (final id in recentFamilyIds)
        if (id != familyId) id,
    ];
    if (next.length > 24) next.removeRange(24, next.length);
    return FamilyLibraryPreferences(
      favoriteFamilyIds: favoriteFamilyIds,
      recentFamilyIds: List<String>.unmodifiable(next),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'favorites': favoriteFamilyIds.toList()..sort(),
        'recent': recentFamilyIds,
      };

  static FamilyLibraryPreferences fromJson(Object? raw) {
    if (raw is! Map) return const FamilyLibraryPreferences();
    final favorites = <String>{};
    final recent = <String>[];
    final rawFavorites = raw['favorites'];
    if (rawFavorites is List) {
      for (final item in rawFavorites) {
        final id = item.toString().trim();
        if (id.isNotEmpty) favorites.add(id);
      }
    }
    final rawRecent = raw['recent'];
    if (rawRecent is List) {
      for (final item in rawRecent) {
        final id = item.toString().trim();
        if (id.isNotEmpty && !recent.contains(id)) recent.add(id);
        if (recent.length >= 24) break;
      }
    }
    return FamilyLibraryPreferences(
      favoriteFamilyIds: Set<String>.unmodifiable(favorites),
      recentFamilyIds: List<String>.unmodifiable(recent),
    );
  }
}
