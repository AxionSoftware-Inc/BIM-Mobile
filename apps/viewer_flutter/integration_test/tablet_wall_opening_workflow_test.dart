import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:viewer_flutter/src/authoring_command_service.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/tbe_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tablet wall opening workflow keeps a host cut and an unrelated wall isolated',
    (_) async {
      final repository = ViewerRepository(TbeViewerApi.load());
      addTearDown(repository.dispose);
      final commands = AuthoringCommandService(
        repository: () => repository,
        creationGateway: () => repository,
        engineEnabled: () => true,
      );

      final blank = await repository.createBlankProject(
        projectName: 'Tablet wall opening smoke',
      );
      final levelId = blank.scene!.levels.first.levelId;
      await repository.createWall(
        name: 'Host wall',
        levelId: levelId,
        start: const RenderScenePoint(x: 0, y: 0, z: 0),
        end: const RenderScenePoint(x: 8, y: 0, z: 0),
        thicknessMeters: 0.2,
        heightMeters: 3.0,
      );
      final hostId = repository.lastCreatedElementId!;
      await repository.createWall(
        name: 'Isolated wall',
        levelId: levelId,
        start: const RenderScenePoint(x: 0, y: 4, z: 0),
        end: const RenderScenePoint(x: 8, y: 4, z: 0),
        thicknessMeters: 0.2,
        heightMeters: 3.0,
      );
      final unrelatedId = repository.lastCreatedElementId!;
      await commands.createWindow(
        name: 'Tablet window',
        hostWallId: hostId,
        offsetMeters: 4.0,
        widthMeters: 1.2,
        heightMeters: 1.0,
        sillHeightMeters: 0.9,
      );
      final windowId = repository.lastCreatedElementId!;

      final before = (await repository.currentRenderScene()).scene!;
      final unrelatedMesh = before.objectById(unrelatedId)!.mesh.toJson();
      expect(
        before
            .objectById(hostId)!
            .featureEdges
            .where((edge) => edge.role == 'opening_contour'),
        hasLength(8),
      );
      expect(before.objectById(hostId)!.metadata.containsKey('opening_profile'),
          isFalse);

      await commands.updateOpening(
        object: before.objectById(windowId)!,
        offsetMeters: 4.5,
        widthMeters: 1.4,
        heightMeters: 1.1,
        sillHeightMeters: 1.0,
      );
      final after = (await repository.currentRenderScene()).scene!;
      expect(
        double.parse(
          after.objectById(windowId)!.metadata['offset_meters'].toString(),
        ),
        closeTo(4.5, 1e-6),
      );
      final updatedHost = after.objectById(hostId)!;
      expect(updatedHost.metadata.containsKey('opening_profile'), isFalse);
      expect(
        updatedHost.featureEdges.where(
          (edge) =>
              edge.role == 'opening_contour' &&
              (edge.start.z - edge.end.z).abs() <= 1e-6 &&
              ((edge.start.x - 3.8).abs() <= 1e-6 &&
                      (edge.end.x - 5.2).abs() <= 1e-6 ||
                  (edge.start.x - 5.2).abs() <= 1e-6 &&
                      (edge.end.x - 3.8).abs() <= 1e-6),
        ),
        hasLength(4),
      );
      expect(after.objectById(unrelatedId)!.mesh.toJson(), unrelatedMesh);
    },
  );
}
