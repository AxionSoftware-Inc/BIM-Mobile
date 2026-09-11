import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/families/application/editor/family_editor_save_service.dart';
import 'package:viewer_flutter/src/features/families/application/library/family_asset_file.dart';
import 'package:viewer_flutter/src/features/families/application/library/family_asset_repository.dart';
import 'package:viewer_flutter/src/features/families/domain/document/family_document.dart';

void main() {
  test('first save validates and delegates to repository save', () async {
    final repository = _FakeFamilyAssetRepository();
    final service = FamilyEditorSaveService(repository);
    final document = FamilyDocument.starter(name: 'Desk');

    final result = await service.save(document);

    expect(result.document, same(document));
    expect(result.path, '/families/Desk.bimfamily');
    expect(repository.saved, <String>['Desk']);
    expect(repository.savedExisting, isEmpty);
  });

  test('existing asset uses saveAsset with the known locator', () async {
    final repository = _FakeFamilyAssetRepository();
    final service = FamilyEditorSaveService(repository);
    final document = FamilyDocument.starter(name: 'Chair');

    final result = await service.save(
      document,
      existingPath: '/families/original.bimfamily',
    );

    expect(result.path, '/families/original.bimfamily');
    expect(
      repository.savedExisting,
      <String>['Chair@/families/original.bimfamily'],
    );
  });

  test('invalid document is rejected before repository mutation', () async {
    final repository = _FakeFamilyAssetRepository();
    final service = FamilyEditorSaveService(repository);
    final invalid = FamilyDocument.starter().copyWith(name: '');

    await expectLater(service.save(invalid), throwsFormatException);
    expect(repository.saved, isEmpty);
    expect(repository.savedExisting, isEmpty);
  });

  test('missing nested dependency fails preflight before save', () async {
    final repository = _FakeFamilyAssetRepository();
    final service = FamilyEditorSaveService(repository);
    final base = FamilyDocument.starter(name: 'Parent');
    final nested = base.copyWith(
      features: <FamilyFeature>[
        ...base.features,
        const FamilyFeature(
          id: 'nested-1',
          kind: FamilyFeatureKind.nestedFamily,
          parameters: <String, Object?>{
            'familyId': 'missing-child',
            'typeId': 'missing-type',
          },
        ),
      ],
    );

    await expectLater(service.save(nested), throwsFormatException);
    expect(repository.saved, isEmpty);
  });
}

final class _FakeFamilyAssetRepository implements FamilyAssetRepository {
  final List<String> saved = <String>[];
  final List<String> savedExisting = <String>[];
  final List<FamilyAssetFile> assets = <FamilyAssetFile>[];

  @override
  Future<List<FamilyAssetFile>> listStored() async =>
      List<FamilyAssetFile>.unmodifiable(assets);

  @override
  Future<FamilyDocument?> resolveDocument({
    required String assetId,
    String assetPath = '',
  }) async {
    for (final asset in assets) {
      if (asset.document.id == assetId) return asset.document;
    }
    return null;
  }

  @override
  Future<String?> save(FamilyDocument document) async {
    saved.add(document.name);
    return '/families/${document.name}.bimfamily';
  }

  @override
  Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  }) async {
    savedExisting.add('${document.name}@$existingPath');
    return existingPath;
  }
}
