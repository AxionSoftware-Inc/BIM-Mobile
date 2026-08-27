import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viewer_flutter/src/tbe_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tablet wall type change keeps hosted openings and solid scene intact',
    (tester) async {
      final repository = ViewerRepository(TbeViewerApi.load());
      addTearDown(repository.dispose);

      final initialResult = await repository.createResidentialTemplate(
        buildingCount: 1,
        storyCount: 3,
      );
      final initial = initialResult.scene!;
      expect(initial.wallTypes.map((type) => type.name), containsAll(<String>[
        'Exterior Glass Wall',
        'Interior Glass Partition',
        'Concrete Core Wall',
      ]));
      expect(
        initial.materials.any((material) => material.name == 'Template Glass'),
        isTrue,
      );

      final opening = initial.objects.firstWhere(
        (object) =>
            (object.kindKey == 'door' || object.kindKey == 'window') &&
            object.metadata.containsKey('host_wall_id'),
      );
      final hostWallId = int.parse(opening.metadata['host_wall_id'].toString());
      final wall = initial.objectById(hostWallId)!;
      final glassType = initial.wallTypes.firstWhere(
        (type) => type.name == 'Exterior Glass Wall',
      );

      final changedResult = await repository.setWallType(
        wallId: wall.elementId!,
        wallTypeId: glassType.id,
      );
      final changed = changedResult.scene!;
      final changedWall = changed.objectById(wall.elementId)!;
      expect(changedWall.metadata['wall_type_id'], glassType.id.toString());
      expect(changedWall.metadata['layer_profile'], contains(':0.12'));
      expect(changed.objects, hasLength(initial.objects.length));
      expect(
        changed.objectById(opening.elementId)?.metadata['host_wall_id'],
        hostWallId.toString(),
      );
      expect(changed.diagnostics.missingGeometryCount, 0);
    },
  );
}
