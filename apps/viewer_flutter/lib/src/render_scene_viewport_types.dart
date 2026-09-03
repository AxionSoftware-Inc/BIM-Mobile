import 'package:flutter/material.dart';

import 'render_scene_models.dart';

const List<String> kDefaultVisibleSceneKinds = <String>[];

enum RenderSceneProjectionMode {
  topDown,
  northElevation,
  southElevation,
  eastElevation,
  westElevation,
  isometric,
}

const RenderSceneProjectionMode kDefaultPlanProjectionMode =
    RenderSceneProjectionMode.topDown;
const RenderSceneProjectionMode kDefaultElevationProjectionMode =
    RenderSceneProjectionMode.northElevation;
const List<RenderSceneProjectionMode> kOrthographicProjectionModes =
    <RenderSceneProjectionMode>[
  RenderSceneProjectionMode.topDown,
  RenderSceneProjectionMode.northElevation,
  RenderSceneProjectionMode.southElevation,
  RenderSceneProjectionMode.eastElevation,
  RenderSceneProjectionMode.westElevation,
];

enum RenderSceneDisplayStyle {
  shaded,
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

enum RenderSceneViewportTheme {
  light,
  standardDark,
  amoledBlack,
}

extension RenderSceneViewportThemeX on RenderSceneViewportTheme {
  String get label => switch (this) {
        RenderSceneViewportTheme.light => 'Light viewport',
        RenderSceneViewportTheme.standardDark => 'Standard dark viewport',
        RenderSceneViewportTheme.amoledBlack => 'AMOLED black viewport',
      };

  String get description => switch (this) {
        RenderSceneViewportTheme.light => 'White modelling canvas',
        RenderSceneViewportTheme.standardDark => 'Revit-style dark grey canvas',
        RenderSceneViewportTheme.amoledBlack => 'Pure black modelling canvas',
      };

  IconData get icon => switch (this) {
        RenderSceneViewportTheme.light => Icons.wb_sunny_outlined,
        RenderSceneViewportTheme.standardDark => Icons.view_in_ar_outlined,
        RenderSceneViewportTheme.amoledBlack => Icons.brightness_2_outlined,
      };
}

enum RenderSceneInteractionMode {
  select,
  addWall,
  addLevel,
  moveLevel,
  addDoor,
  addWindow,
  moveWall,
  moveOpening,
  trimExtend,
  addFloor,
  addCeiling,
  addRoof,
  addStair,
}

enum RenderSceneSurfaceDrawMode {
  rectangle,
  polyline,
  pickWalls,
  autoRoom,
}

extension RenderSceneInteractionModeX on RenderSceneInteractionMode {
  String get authoringLabel => switch (this) {
        RenderSceneInteractionMode.select => 'Select',
        RenderSceneInteractionMode.addWall => 'Wall',
        RenderSceneInteractionMode.addLevel => 'Level',
        RenderSceneInteractionMode.moveLevel => 'Move level',
        RenderSceneInteractionMode.addDoor => 'Door',
        RenderSceneInteractionMode.addWindow => 'Window',
        RenderSceneInteractionMode.moveWall => 'Move wall',
        RenderSceneInteractionMode.moveOpening => 'Move opening',
        RenderSceneInteractionMode.trimExtend => 'Trim / Extend',
        RenderSceneInteractionMode.addFloor => 'Floor',
        RenderSceneInteractionMode.addCeiling => 'Ceiling',
        RenderSceneInteractionMode.addRoof => 'Roof',
        RenderSceneInteractionMode.addStair => 'Stair',
      };

  bool get requiresPlanProjection => switch (this) {
        RenderSceneInteractionMode.addWall => true,
        RenderSceneInteractionMode.addDoor => true,
        RenderSceneInteractionMode.addWindow => true,
        RenderSceneInteractionMode.moveWall => true,
        RenderSceneInteractionMode.trimExtend => true,
        // Inspector property editing must not force a 3D selection into plan.
        // The numeric commit is view-independent; direct placement remains a
        // separate gesture path.
        RenderSceneInteractionMode.moveOpening => false,
        RenderSceneInteractionMode.addFloor => true,
        RenderSceneInteractionMode.addCeiling => true,
        RenderSceneInteractionMode.addRoof => true,
        RenderSceneInteractionMode.addStair => true,
        RenderSceneInteractionMode.select => false,
        RenderSceneInteractionMode.addLevel => false,
        RenderSceneInteractionMode.moveLevel => false,
      };

  bool get prefersElevationProjection => switch (this) {
        RenderSceneInteractionMode.addLevel => true,
        RenderSceneInteractionMode.moveLevel => true,
        _ => false,
      };
}

extension RenderSceneProjectionEditingModeX on RenderSceneProjectionMode {
  bool get supportsPlanFootprintEditing => this == kDefaultPlanProjectionMode;
}

/// Camera-only contract shared by fallback canvas, native overlays, sheets,
/// sections, and any future viewport host.
///
/// Authoring and selection are deliberately absent. A new viewport can reuse
/// this module without inheriting wall/floor/editor behavior.
abstract interface class ViewportCameraTarget {
  RenderSceneProjectionMode get projectionMode;

  void panPlanBy(Offset delta);

  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  });

  void orbitBy(Offset delta, Size viewportSize);

  void panOrbitBy(Offset delta, Size viewportSize);

  void zoomOrbit(double scaleDelta);
}

@immutable
class RenderSceneTapDetails {
  const RenderSceneTapDetails({
    required this.screenPosition,
    required this.globalPosition,
    required this.modelPoint,
    required this.pickedObject,
    this.pickedLevel,
    this.pointerCount = 1,
  });

  final Offset screenPosition;
  final Offset globalPosition;
  final RenderScenePoint? modelPoint;
  final RenderSceneObject? pickedObject;
  final RenderSceneLevel? pickedLevel;

  /// Number of active pointers at the time this detail was emitted.
  ///
  /// Authoring handlers use this as a final guard so a second finger cannot
  /// accidentally turn a camera gesture into a committed model point.
  final int pointerCount;
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
class RenderSceneWallArcDraft {
  const RenderSceneWallArcDraft({
    this.start,
    this.end,
    this.control,
    this.center,
    this.points = const <RenderScenePoint>[],
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final RenderScenePoint? control;
  // Derived circle center used only for optional authoring guidance.
  final RenderScenePoint? center;
  final List<RenderScenePoint> points;
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
    required this.points,
    this.closed = true,
    this.boundarySketch = false,
    this.committedPointCount,
  });

  final String kind;
  final List<RenderScenePoint> points;
  final bool closed;

  /// True while the Revit-style Boundary tool is being edited. Boundary
  /// drafts use the pink sketch treatment instead of the final material
  /// colour, and may contain one extra live cursor point.
  final bool boundarySketch;

  /// Number of points confirmed by a tap. When the live cursor is present,
  /// it is drawn as a separate preview segment/handle.
  final int? committedPointCount;
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

abstract class RenderSceneViewportActions extends ChangeNotifier
    implements ViewportCameraTarget {
  RenderScene? get scene;
  Set<String> get visibleKinds;
  Set<String> get selectedElementIds;
  String? get activeElementId;
  int? get selectedLevelId;
  String? get selectedElementId;
  String? get highlightedElementId;
  int get fitRevision;
  int get sceneRevision;
  @override
  RenderSceneProjectionMode get projectionMode;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle;
  RenderSceneDisplayStyle get displayStyle;
  RenderSceneViewportTheme get viewportTheme;
  bool get shadowsEnabled;
  bool get hdriVisible;
  RenderSceneViewportBackend get backend;
  RenderSceneInteractionMode get interactionMode;
  RenderScenePlanCameraState get planCamera;
  RenderSceneCameraState get camera;
  RenderScenePoint? get draftWallStart;
  RenderScenePoint? get draftWallEnd;
  RenderSceneWallArcDraft? get draftWallArc;
  RenderSceneOpeningDraft? get draftOpening;
  RenderSceneSurfaceDraft? get draftSurface;

  Future<void> loadRenderScene(RenderScene scene);
  Future<void> clearScene();
  Future<void> fitCamera();
  Future<void> setVisibleKinds(Set<String> kinds);
  Future<void> setProjectionMode(RenderSceneProjectionMode mode);
  Future<void> setOrbitProjectionStyle(RenderSceneOrbitProjectionStyle style);
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style);
  Future<void> setViewportTheme(RenderSceneViewportTheme theme);
  Future<void> setHdriVisible(bool visible);
  Future<void> setShadowsEnabled(bool enabled);
  Future<void> setBackend(RenderSceneViewportBackend backend);
  Future<void> setInteractionMode(RenderSceneInteractionMode mode);
  void setWallDraft(RenderScenePoint? start, RenderScenePoint? end);
  void setWallArcDraft(RenderSceneWallArcDraft? draft);
  void setOpeningDraft(RenderSceneOpeningDraft? draft);
  void setSurfaceDraft(RenderSceneSurfaceDraft? draft);
  void clearDraft();
  void setViewportSize(Size size);
  @override
  void panPlanBy(Offset delta);
  @override
  void zoomPlanBy(
    double scaleDelta, {
    Offset? focalPoint,
    Size? viewportSize,
  });
  @override
  void orbitBy(Offset delta, Size viewportSize);
  @override
  void panOrbitBy(Offset delta, Size viewportSize);
  @override
  void zoomOrbit(double scaleDelta);
  RenderScenePoint? screenToModelPlan(Offset localPosition, Size viewportSize);
  Future<void> selectElement(String? elementId);
  Future<void> selectElements(Set<String> elementIds,
      {String? activeElementId});
  Future<void> selectLevel(int? levelId);
  Future<void> highlightElement(String? elementId);
}
