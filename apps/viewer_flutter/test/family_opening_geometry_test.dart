import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String, ({String familyId, String defaultTypeId})>{
    'assets/families/door_single_flush.bimfamily': (
      familyId: 'builtin-door-single-flush-v1',
      defaultTypeId: 'builtin-door-single-flush-v1-type',
    ),
    'assets/families/door_double_glazed.bimfamily': (
      familyId: 'builtin-door-double-glazed-v1',
      defaultTypeId: 'builtin-door-double-glazed-v1-type',
    ),
    'assets/families/window_single_casement.bimfamily': (
      familyId: 'builtin-window-single-casement-v1',
      defaultTypeId: 'builtin-window-single-casement-v1-type',
    ),
    'assets/families/window_wide_picture.bimfamily': (
      familyId: 'builtin-window-wide-picture-v1',
      defaultTypeId: 'builtin-window-wide-picture-v1-type',
    ),
  };

  for (final entry in assets.entries) {
    test('${entry.value.familyId} ships real authored opening geometry', () async {
      final text = await rootBundle.loadString(entry.key);
      final document = FamilyBundledCatalog.decodeAsset(entry.key, text);

      expect(document.id, entry.value.familyId);
      expect(document.types.first.id, entry.value.defaultTypeId);
      expect(document.types.length, greaterThanOrEqualTo(3));
      expect(
        document.features.any((feature) => feature.kind == FamilyFeatureKind.box),
        isFalse,
        reason: 'Opening families must never regress to an envelope box.',
      );

      final meshFeature = document.features.singleWhere(
        (feature) => feature.kind == FamilyFeatureKind.freeformMesh,
      );
      final vertices = meshFeature.parameters['vertices'];
      final faces = meshFeature.parameters['faces'];
      expect(vertices, isA<List>());
      expect(faces, isA<List>());
      expect((vertices! as List).length, greaterThanOrEqualTo(64));
      expect((faces! as List).length, greaterThanOrEqualTo(48));

      final mesh = FamilyGeometryEvaluator.evaluateMesh(
        document,
        document.types.first,
      );
      expect(mesh.vertices.length, greaterThanOrEqualTo(64));
      expect(mesh.faces.length, greaterThanOrEqualTo(48));
      expect(mesh.isApproximate, isFalse);
      expect(FamilyDocumentValidator.validate(document).isValid, isTrue);
    });
  }
}
