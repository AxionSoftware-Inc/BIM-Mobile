import 'package:flutter/material.dart';

import 'render_scene_models.dart';

const List<String> kDefaultVisibleSceneKinds = <String>[];

enum RenderSceneProjectionMode {
  topDown,
  isometric,
}

enum RenderSceneDisplayStyle {
  solid,
  wireframe,
}

enum RenderSceneOrbitProjectionStyle {
  perspective,
  orthographic,
}

enum RenderSceneViewportBackend {
  auto,
  native,
  fallback,
}

enum RenderSceneInteractionMode {
  select,
  addWall,
  addDoor,
  addWindow,
  moveWall,
  moveOpening,
  addFloor,
  addCeiling,
}

@immutable
class RenderSceneTapDetails {
  const RenderSceneTapDetails({
    required this.screenPosition,
    required this.globalPosition,
    required this.modelPoint,
    required this.pickedObject,
  });

  final Offset screenPosition;
  final Offset globalPosition;
  final RenderScenePoint? modelPoint;
  final RenderSceneObject? pickedObject;
}

@immutable
class RenderSceneWallDraft {
  const RenderSceneWallDraft({
    required this.start,
    required this.end,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
}

@immutable
class RenderSceneOpeningDraft {
  const RenderSceneOpeningDraft({
    required this.kind,
    required this.hostWallId,
    required this.offsetMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.valid,
    required this.message,
  });

  final String kind;
  final int? hostWallId;
  final double offsetMeters;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final bool valid;
  final String message;
}

@immutable
class RenderSceneSurfaceDraft {
  const RenderSceneSurfaceDraft({
    required this.kind,
    required this.start,
    required this.end,
  });

  final String kind;
  final RenderScenePoint start;
  final RenderScenePoint end;
}

@immutable
class RenderSceneCameraState {
  const RenderSceneCameraState({
    required this.center,
    required this.distance,
    required this.yawRadians,
    required this.pitchRadians,
    required this.zoomScale,
  });

  final RenderScenePoint center;
  final double distance;
  final double yawRadians;
  final double pitchRadians;
  final double zoomScale;
}

@immutable
class RenderScenePlanCameraState {
  const RenderScenePlanCameraState({
    required this.center,
    required this.zoom,
  });

  final RenderScenePoint center;
  final double zoom;

  RenderScenePlanCameraState copyWith({
    RenderScenePoint? center,
    double? zoom,
  }) {
    return RenderScenePlanCameraState(
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }
}

abstract class RenderSceneViewportActions extends ChangeNotifier {
  RenderScene? get scene;
  Set<String> get visibleKinds;
  String? get selectedElementId;
  String? get highlightedElementId;
  int get fitRevision;
  int get sceneRevision;
  RenderSceneProjectionMode get projectionMode;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle;
  RenderSceneDisplayStyle get displayStyle;
  RenderSceneViewportBackend get backend;
  RenderSceneInteractionMode get interactionMode;
  RenderScenePlanCameraState get planCamera;
  RenderSceneCameraState get camera;
  RenderScenePoint? get draftWallStart;
  RenderScenePoint? get draftWallEnd;
  RenderSceneOpeningDraft? get draftOpening;
  RenderSceneSurfaceDraft? get draftSurface;

  Future<void> loadRenderScene(RenderScene scene);
  Future<void> clearScene();
  Future<void> fitCamera();
  Future<void> setVisibleKinds(Set<String> kinds);
  Future<void> setProjectionMode(RenderSceneProjectionMode mode);
  Future<void> setOrbitProjectionStyle(RenderSceneOrbitProjectionStyle style);
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style);
  Future<void> setBackend(RenderSceneViewportBackend backend);
  Future<void> setInteractionMode(RenderSceneInteractionMode mode);
  void setWallDraft(RenderScenePoint? start, RenderScenePoint? end);
  void setOpeningDraft(RenderSceneOpeningDraft? draft);
  void setSurfaceDraft(RenderSceneSurfaceDraft? draft);
  void clearDraft();
  void setViewportSize(Size size);
  void panPlanBy(Offset delta);
  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  });
  void orbitBy(Offset delta, Size viewportSize);
  void panOrbitBy(Offset delta, Size viewportSize);
  void zoomOrbit(double scaleDelta);
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize);
  Future<void> selectElement(String? elementId);
  Future<void> highlightElement(String? elementId);
}
