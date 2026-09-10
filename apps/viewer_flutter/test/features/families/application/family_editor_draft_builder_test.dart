import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/families/application/editor/family_editor_draft_builder.dart';
import 'package:viewer_flutter/src/features/families/domain/document/family_document.dart';

void main() {
  test('upsert preserves feature identity and replaces an edited draft', () {
    final base = FamilyDocument.starter();
    final first = FamilyEditorDraftBuilder.extrude(
      base,
      featureId: 'draft-extrude',
      profileId: 'profile-a',
      depth: '2.0',
    );
    final second = FamilyEditorDraftBuilder.extrude(
      first,
      featureId: 'draft-extrude',
      profileId: 'profile-b',
      depth: '3.5',
    );

    expect(second.features.length, first.features.length);
    final feature =
        second.features.singleWhere((item) => item.id == 'draft-extrude');
    expect(feature.parameters['profileId'], 'profile-b');
    expect(feature.parameters['depth'], '3.5');
  });

  test('boolean rejects using the same solid as Base and Tool', () {
    final document = FamilyDocument.starter();
    expect(
      () => FamilyEditorDraftBuilder.boolean(
        document,
        featureId: 'boolean-1',
        baseFeatureId: 'feature-1',
        toolFeatureId: 'feature-1',
        kind: FamilyFeatureKind.booleanSubtract,
      ),
      throwsArgumentError,
    );
  });

  test('eligible solids stop before an existing draft feature', () {
    final base = FamilyDocument.starter();
    final transformed = FamilyEditorDraftBuilder.transform(
      base,
      featureId: 'transform-1',
      sourceFeatureId: 'feature-1',
      translationX: '0',
      translationY: '0',
      translationZ: '0',
      rotation: '0',
      scale: '1',
    );
    final after = transformed.copyWith(
      features: <FamilyFeature>[
        ...transformed.features,
        const FamilyFeature(
          id: 'later-box',
          kind: FamilyFeatureKind.box,
          parameters: <String, Object?>{
            'width': 1,
            'depth': 1,
            'height': 1,
          },
        ),
      ],
    );

    expect(
      FamilyEditorDraftBuilder.eligibleSolids(
        after,
        draftFeatureId: 'transform-1',
      ).map((feature) => feature.id),
      <String>['feature-1'],
    );
  });
}
