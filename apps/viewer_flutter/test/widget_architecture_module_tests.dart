part of 'widget_test.dart';

void registerArchitectureModuleTests() {
  test('viewport gesture module owns shared two-finger camera rules', () {
    final target = _RecordingCameraTarget();
    final gestures = ViewportGestureController();

    gestures.handleScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(40, 40)),
      target: target,
      nativeOwned: false,
    );
    gestures.handleScaleUpdate(
      ScaleUpdateDetails(
        scale: 1.5,
        localFocalPoint: const Offset(50, 45),
        pointerCount: 2,
      ),
      target: target,
      viewportSize: const Size(400, 300),
      nativeOwned: false,
    );

    expect(target.planPan, const Offset(10, 5));
    expect(target.planZoom, 1.5);
    expect(target.planZoomFocalPoint, const Offset(50, 45));
    expect(target.planZoomViewport, const Size(400, 300));

    final previousPanCount = target.panCount;
    gestures.handleScaleUpdate(
      ScaleUpdateDetails(
        scale: 2.0,
        localFocalPoint: const Offset(65, 55),
        pointerCount: 1,
      ),
      target: target,
      viewportSize: const Size(400, 300),
      nativeOwned: false,
    );
    expect(target.panCount, previousPanCount);
  });

  test('view workspace store keeps presentation metadata by view id', () {
    final store = ViewWorkspaceStore.standard();
    final tab = OpenedViewTab(
      id: 'floor-plan-1',
      label: 'Level 1 plan',
      kind: OpenedViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: 1,
    );

    expect(store.addTab(tab), isTrue);
    expect(store.tabById(tab.id), same(tab));
    expect(
      store.savePresentation(
        tab.id,
        displayStyle: RenderSceneDisplayStyle.shaded,
        shadowsEnabled: true,
      ),
      isTrue,
    );

    final reopened = store.withSavedPresentation(tab);
    expect(reopened.displayStyle, RenderSceneDisplayStyle.shaded);
    expect(reopened.shadowsEnabled, isTrue);
    expect(store.savedPresentations.keys, contains(tab.id));
    expect(store.removeTab(tab.id), isTrue);
    expect(store.tabById(tab.id), isNull);
    expect(store.savedPresentations, isEmpty);
  });
}

final class _RecordingCameraTarget implements ViewportCameraTarget {
  @override
  RenderSceneProjectionMode projectionMode = RenderSceneProjectionMode.topDown;

  Offset? planPan;
  double? planZoom;
  Offset? planZoomFocalPoint;
  Size? planZoomViewport;
  int panCount = 0;

  @override
  void panPlanBy(Offset delta) {
    planPan = delta;
    panCount += 1;
  }

  @override
  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  }) {
    planZoom = scaleDelta;
    planZoomFocalPoint = focalPoint;
    planZoomViewport = viewportSize;
  }

  @override
  void orbitBy(Offset delta, Size viewportSize) {}

  @override
  void panOrbitBy(Offset delta, Size viewportSize) {}

  @override
  void zoomOrbit(double scaleDelta) {}
}
