import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/documentation/application/document_models.dart';
import 'package:viewer_flutter/src/features/documentation/presentation/sheet_workspace_controller.dart';
import 'package:viewer_flutter/src/features/viewer/domain/view/view_configuration.dart';

void main() {
  group('SheetWorkspaceController', () {
    test('creates deterministic sheet numbers and activates new sheet', () {
      final controller = SheetWorkspaceController();

      final first = controller.createSheet(title: 'Ground Floor');
      final second = controller.createSheet(title: 'Roof');

      expect(first.number, 'A101');
      expect(second.number, 'A102');
      expect(controller.activeSheetId, second.id);
      expect(controller.sheets, hasLength(2));
    });

    test('places each semantic view at most once on an active sheet', () {
      final controller = SheetWorkspaceController();
      controller.createSheet();
      final view = SheetViewReference(
        id: 'view-ground',
        label: 'Ground Floor',
        kind: SheetViewKind.floorPlan,
        projectionMode: RenderSceneProjectionMode.topDown,
        levelId: 1,
      );

      expect(
        controller.placeView(view: view, centerX: 0.5, centerY: 0.5),
        isTrue,
      );
      expect(
        controller.placeView(view: view, centerX: 0.5, centerY: 0.5),
        isFalse,
      );
      expect(controller.activeSheet!.placements, hasLength(1));
      expect(controller.activeSheet!.placements.single.width, 0.52);
      expect(controller.activeSheet!.placements.single.height, 0.60);
    });

    test('updates stored view presentation without changing semantic identity', () {
      final controller = SheetWorkspaceController();
      controller.createSheet();
      final view = SheetViewReference(
        id: 'view-3d',
        label: '3D',
        kind: SheetViewKind.threeD,
        projectionMode: RenderSceneProjectionMode.isometric,
      );
      controller.placeView(view: view, centerX: 0.5, centerY: 0.5);

      controller.updateViewPresentation(
        view.id,
        displayStyle: RenderSceneDisplayStyle.wireframe,
        shadowsEnabled: true,
        orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
      );

      final updated = controller.activeSheet!.placements.single.view;
      expect(updated.id, view.id);
      expect(updated.displayStyle, RenderSceneDisplayStyle.wireframe);
      expect(updated.shadowsEnabled, isTrue);
      expect(
        updated.orbitProjectionStyle,
        RenderSceneOrbitProjectionStyle.orthographic,
      );
    });
  });

  test('sheet document settings keep a filesystem-safe PDF name', () {
    final settings = SheetDocumentSettings(
      projectName: ' Tower / A ',
      author: 'Team',
      sheetPrefix: 'A',
      scaleDenominator: 50,
      scope: DocumentationScope.currentFloorPlan,
      generatedAt: DateTime.utc(2026, 9, 10),
    );

    expect(settings.safeFileName, 'Tower_A_documentation.pdf');
  });
}
