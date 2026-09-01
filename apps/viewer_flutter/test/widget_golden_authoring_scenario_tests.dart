part of 'widget_test.dart';

void registerGoldenAuthoringScenarioTests() {
  test('golden wall-opening workflow preserves true voids and isolation',
      () async {
    final repository = ViewerRepository(TbeViewerApi.load());
    addTearDown(repository.dispose);
    final commands = AuthoringCommandService(
      repository: () => repository,
      creationGateway: () => repository,
      engineEnabled: () => true,
    );

    final blank = await repository.createBlankProject(
      projectName: 'Golden wall opening',
    );
    final levelId = blank.scene!.levels.first.levelId;
    final hostResult = await repository.createWall(
      name: 'Opening host',
      levelId: levelId,
      start: const RenderScenePoint(x: 0, y: 0, z: 0),
      end: const RenderScenePoint(x: 8, y: 0, z: 0),
      thicknessMeters: 0.2,
      heightMeters: 3.0,
    );
    final hostId = repository.lastCreatedElementId!;
    await repository.createWall(
      name: 'Unrelated wall',
      levelId: levelId,
      start: const RenderScenePoint(x: 0, y: 4, z: 0),
      end: const RenderScenePoint(x: 8, y: 4, z: 0),
      thicknessMeters: 0.2,
      heightMeters: 3.0,
    );
    final unrelatedId = repository.lastCreatedElementId!;
    expect(hostResult.errors, isEmpty);

    await commands.createDoor(
      name: 'Golden door',
      hostWallId: hostId,
      offsetMeters: 1.5,
      widthMeters: 0.9,
      heightMeters: 2.1,
    );
    final doorId = repository.lastCreatedElementId!;
    await commands.createWindow(
      name: 'Golden window',
      hostWallId: hostId,
      offsetMeters: 4.5,
      widthMeters: 1.2,
      heightMeters: 1.0,
      sillHeightMeters: 0.9,
    );
    final windowId = repository.lastCreatedElementId!;

    final beforeEdit = (await repository.currentRenderScene()).scene!;
    final hostBefore = beforeEdit.objectById(hostId)!;
    final unrelatedBefore = beforeEdit.objectById(unrelatedId)!;
    expect(beforeEdit.sceneVersion,
        RenderSceneCoordinateContract.currentSceneVersion);
    expect(
      hostBefore.featureEdges.where((edge) => edge.role == 'opening_contour'),
      hasLength(16),
    );
    // Brick decoration is clipped by these authoritative coordinates, never
    // by a separately serialized opening/texture profile.
    expect(hostBefore.metadata.containsKey('opening_profile'), isFalse);
    expect(beforeEdit.objectById(doorId)?.metadata['host_wall_id'], '$hostId');
    expect(
        beforeEdit.objectById(windowId)?.metadata['host_wall_id'], '$hostId');

    final historyBeforeEdit = await repository.historyCounts();
    await commands.updateOpening(
      object: beforeEdit.objectById(windowId)!,
      offsetMeters: 5.0,
      widthMeters: 1.4,
      heightMeters: 1.1,
      sillHeightMeters: 1.0,
    );
    final afterEdit = (await repository.currentRenderScene()).scene!;
    final historyAfterEdit = await repository.historyCounts();
    expect(historyAfterEdit.undoCount, historyBeforeEdit.undoCount + 1);
    expect(
      double.parse(
          afterEdit.objectById(windowId)!.metadata['offset_meters'].toString()),
      closeTo(5.0, 1e-6),
    );
    expect(
      double.parse(
          afterEdit.objectById(windowId)!.metadata['width_meters'].toString()),
      closeTo(1.4, 1e-6),
    );
    expect(
      afterEdit
          .objectById(hostId)!
          .featureEdges
          .where((edge) => edge.role == 'opening_contour'),
      hasLength(16),
    );
    final updatedHost = afterEdit.objectById(hostId)!;
    expect(updatedHost.metadata.containsKey('opening_profile'), isFalse);
    final updatedWindowHorizontalContours = updatedHost.featureEdges.where(
      (edge) =>
          edge.role == 'opening_contour' &&
          (edge.start.z - edge.end.z).abs() <= 1e-6 &&
          ((edge.start.x - 4.3).abs() <= 1e-6 &&
                  (edge.end.x - 5.7).abs() <= 1e-6 ||
              (edge.start.x - 5.7).abs() <= 1e-6 &&
                  (edge.end.x - 4.3).abs() <= 1e-6),
    );
    expect(updatedWindowHorizontalContours, hasLength(4));
    expect(afterEdit.objectById(unrelatedId)!.mesh.toJson(),
        unrelatedBefore.mesh.toJson());

    final undone = (await repository.undo()).scene!;
    expect(
      double.parse(
          undone.objectById(windowId)!.metadata['offset_meters'].toString()),
      closeTo(4.5, 1e-6),
    );
    expect(undone.objectById(unrelatedId)!.mesh.toJson(),
        unrelatedBefore.mesh.toJson());

    final redone = (await repository.redo()).scene!;
    expect(
      double.parse(
          redone.objectById(windowId)!.metadata['offset_meters'].toString()),
      closeTo(5.0, 1e-6),
    );
    expect(redone.objectById(unrelatedId)!.mesh.toJson(),
        unrelatedBefore.mesh.toJson());
  });
}
