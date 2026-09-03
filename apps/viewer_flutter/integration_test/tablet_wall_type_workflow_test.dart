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
      expect(
          initial.wallTypes.map((type) => type.name),
          containsAll(<String>[
            'Exterior Glass Wall',
            'Interior Glass Partition',
            'Concrete Core Wall',
          ]));
      expect(
        initial.materials.any((material) => material.name == 'Glass'),
        isTrue,
      );

      final opening = initial.objects.firstWhere(
        (object) =>
            (object.kindKey == 'door' || object.kindKey == 'window') &&
            object.metadata.containsKey('host_wall_id'),
      );
      final hostWallId = int.parse(opening.metadata['host_wall_id'].toString());
      final wall = initial.objectById(hostWallId)!;
      for (final wallType in initial.wallTypes) {
        final changedResult = await repository.setWallType(
          wallId: wall.elementId!,
          wallTypeId: wallType.id,
        );
        final changed = changedResult.scene!;
        final changedWall = changed.objectById(wall.elementId)!;
        expect(changedWall.metadata['wall_type_id'], wallType.id.toString());
        expect(changedWall.metadata['layer_profile'], isNotEmpty);
        expect(changed.objects, hasLength(initial.objects.length));
        expect(
          changed.objectById(opening.elementId)?.metadata['host_wall_id'],
          hostWallId.toString(),
        );
        expect(changed.diagnostics.missingGeometryCount, 0);
      }
    },
  );
}
