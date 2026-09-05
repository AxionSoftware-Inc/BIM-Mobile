import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('library preferred type survives handoff without mutating source document', () {
    final source = FamilyDocument.starter().copyWith(
      types: const <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'small',
          name: 'Small',
          values: <String, Object?>{
            'width': 0.6,
            'depth': 0.6,
            'height': 0.8,
          },
        ),
        FamilyTypeDefinition(
          id: 'large',
          name: 'Large',
          values: <String, Object?>{
            'width': 1.2,
            'depth': 0.8,
            'height': 1.0,
          },
        ),
      ],
    );
    final asset = FamilyAssetFile(document: source, path: '/tmp/chair.bimfamily');

    final preferred = asset.withPreferredType(source.types.last);

    expect(preferred.preferredTypeId, 'large');
    expect(preferred.preferredType.id, 'large');
    expect(preferred.document.types.first.id, 'large');
    expect(preferred.document.types.last.id, 'small');
    // The disk/source contract is immutable; only the in-memory placement
    // handoff gets reordered for backward-compatible callers.
    expect(source.types.first.id, 'small');
    expect(source.types.last.id, 'large');
  });

  test('library favorites toggle deterministically', () {
    var preferences = const FamilyLibraryPreferences();

    preferences = preferences.toggleFavorite('chair-a');
    expect(preferences.isFavorite('chair-a'), isTrue);

    preferences = preferences.toggleFavorite('chair-a');
    expect(preferences.isFavorite('chair-a'), isFalse);
  });

  test('recent families are unique, newest first and bounded', () {
    var preferences = const FamilyLibraryPreferences();
    for (var index = 0; index < 30; index++) {
      preferences = preferences.recordRecent('family-$index');
    }
    preferences = preferences.recordRecent('family-20');

    expect(preferences.recentFamilyIds.length, 24);
    expect(preferences.recentFamilyIds.first, 'family-20');
    expect(
      preferences.recentFamilyIds.where((id) => id == 'family-20'),
      hasLength(1),
    );
  });

  test('library preferences JSON is backward-compatible and de-duplicates recent ids', () {
    final restored = FamilyLibraryPreferences.fromJson(<String, Object?>{
      'favorites': <String>['chair-a', 'chair-b', 'chair-a'],
      'recent': <String>['chair-b', 'chair-a', 'chair-b'],
    });

    expect(restored.favoriteFamilyIds, <String>{'chair-a', 'chair-b'});
    expect(restored.recentFamilyIds, <String>['chair-b', 'chair-a']);
  });

  test('preferred type must belong to the selected family', () {
    final source = FamilyDocument.starter();
    final asset = FamilyAssetFile(document: source, path: '/tmp/family.bimfamily');
    const foreign = FamilyTypeDefinition(
      id: 'foreign',
      name: 'Foreign',
    );

    expect(() => asset.withPreferredType(foreign), throwsArgumentError);
  });
}
