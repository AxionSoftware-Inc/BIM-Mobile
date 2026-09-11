import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/view_workspace_store.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/opened_view_tab.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/workspace/workspace_chrome.dart';

void main() {
  test('workspace seeds plan and canonical 3D navigation tabs together', () {
    final store = ViewWorkspaceStore.standard();
    store.resetForScene(_sceneWithLevel());

    expect(store.activeTabId, ViewWorkspaceStore.floorPlanId(1));
    expect(
      store.tabs.map((tab) => tab.kind),
      <OpenedViewKind>[OpenedViewKind.floorPlan, OpenedViewKind.threeD],
    );
    expect(store.tabById(ViewWorkspaceStore.threeDViewId), isNotNull);

    store.setActiveTab(ViewWorkspaceStore.threeDViewId);
    expect(store.activeTabId, ViewWorkspaceStore.threeDViewId);
  });

  testWidgets('viewport deck exposes one dynamic 2D/3D destination button',
      (tester) async {
    RenderSceneProjectionMode? requestedMode;

    Future<void> pump(RenderSceneProjectionMode mode) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ViewportControlDeck(
                hasScene: true,
                projectionMode: mode,
                displayStyle: RenderSceneDisplayStyle.solid,
                orbitStyle: RenderSceneOrbitProjectionStyle.perspective,
                onProjectionChanged: (value) => requestedMode = value,
                onDisplayStyleChanged: (_) {},
                shadowsEnabled: false,
                onShadowsChanged: (_) {},
                hdriVisible: false,
                onHdriChanged: (_) {},
                onOrbitStyleChanged: (_) {},
                onFit: () {},
                hasSectionBox: false,
                onSectionBox: () {},
              ),
            ),
          ),
        ),
      );
    }

    await pump(RenderSceneProjectionMode.northElevation);
    expect(find.text('3D'), findsOneWidget);
    expect(find.text('2D'), findsNothing);
    await tester.tap(find.text('3D'));
    expect(requestedMode, RenderSceneProjectionMode.isometric);

    requestedMode = null;
    await pump(RenderSceneProjectionMode.isometric);
    expect(find.text('2D'), findsOneWidget);
    expect(find.text('3D'), findsNothing);
    await tester.tap(find.text('2D'));
    expect(requestedMode, RenderSceneProjectionMode.topDown);
  });
}

RenderScene _sceneWithLevel() => const RenderScene(
      sceneVersion: 1,
      units: 'm',
      coordinateSystem: 'x-east,y-north,z-up',
      objectCount: 0,
      vertexCount: 0,
      indexCount: 0,
      bounds: RenderSceneBounds(
        min: RenderScenePoint(x: 0, y: 0, z: 0),
        max: RenderScenePoint(x: 10, y: 10, z: 3),
      ),
      objects: <RenderSceneObject>[],
      levels: <RenderSceneLevel>[
        RenderSceneLevel(
          levelId: 1,
          name: 'Level 1',
          elevationMeters: 0,
          defaultWallHeightMeters: 3,
        ),
      ],
      materials: <RenderSceneMaterial>[],
      sections: <RenderSceneSection>[],
      source: 'test',
      diagnostics: RenderSceneDiagnostics(
        source: 'test',
        objectCount: 0,
        selectableObjectCount: 0,
        visibleObjectCount: 0,
        vertexCount: 0,
        indexCount: 0,
        triangleCount: 0,
        levelCount: 1,
        missingGeometryCount: 0,
        invalidBoundsCount: 0,
        invalidIndexCount: 0,
        kindCounts: <String, int>{},
        warnings: <String>[],
        errors: <String>[],
      ),
    );
