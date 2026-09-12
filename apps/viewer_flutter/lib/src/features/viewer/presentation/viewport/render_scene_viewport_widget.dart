import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../annotations/application/annotation_snap_service.dart';
import '../../../annotations/presentation/annotation_history_controls.dart';
import '../../../annotations/presentation/annotation_hit_test.dart';
import '../../../annotations/presentation/annotation_interaction_overlay.dart';
import '../../../annotations/presentation/annotation_selection_controls.dart';
import '../../../annotations/domain/annotation_store.dart';
import '../../../families/presentation/runtime/family_2d_viewport_overlay.dart';
import '../../../authoring/application/scene/render_scene_editor.dart';
import 'render_scene_level_overlay.dart';
import '../../../../core/application/render_scene/render_scene_models.dart';
import 'render_scene_native_overlay_painter.dart';
import '../../../../core/domain/units/project_unit_settings.dart';
import 'render_scene_viewport_hit_test.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_painter.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'viewport_interaction.dart';
import 'viewport_gesture_controller.dart';
import '../workspace/workspace_chrome.dart';
import '../../application/workspace/opened_view_tab.dart';

part 'render_scene_viewport_support_widgets.dart';
part 'render_scene_viewport_fallback.dart';

class RenderSceneViewport extends StatefulWidget {
  const RenderSceneViewport({
    super.key,
    required this.controller,
    this.activeView,
    this.interactionMode = RenderSceneInteractionMode.select,
    this.onSceneTap,
    this.onSceneDragStart,
    this.onSceneDragUpdate,
    this.onSceneDragEnd,
    this.onSceneMultiTouchStart,
    this.onSceneSecondaryTap,
    this.onSceneHover,
    this.authoringPickKinds = const <String>{},
    this.directSurfaceDrag = false,
    this.planPickResolver,
    this.onLevelElevationSubmitted,
    this.draftSurfaceWallIds = const <int>{},
    this.draftWallThicknessMeters =
        RenderSceneEditor.defaultWallThicknessMeters,
    this.draftWallHeightMeters = RenderSceneEditor.defaultWallHeightMeters,
    this.draftWallEditElementId,
    this.showDiagnostics = false,
    this.units = const ProjectUnitSettings.defaults(),
  });

  final RenderSceneViewportController controller;
  final OpenedViewTab? activeView;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragUpdate;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragEnd;
  final VoidCallback? onSceneMultiTouchStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneSecondaryTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneHover;
  final Set<String> authoringPickKinds;
  final bool directSurfaceDrag;
  final RenderScenePlanPickResolver? planPickResolver;
  final Future<void> Function(RenderSceneLevel level, String value)?
      onLevelElevationSubmitted;
  final Set<int> draftSurfaceWallIds;
  final double draftWallThicknessMeters;
  final double draftWallHeightMeters;
  final int? draftWallEditElementId;
  final bool showDiagnostics;
  final ProjectUnitSettings units;

  @override
  State<RenderSceneViewport> createState() => _RenderSceneViewportState();
}

class _RenderSceneViewportState extends State<RenderSceneViewport> {
  TextEditingController? _annotationTextController;
  FocusNode? _annotationTextFocusNode;
  Completer<String?>? _annotationTextCompleter;
  String _annotationTextTitle = '';
  String _annotationTextHint = '';
  String _annotationTextActionLabel = 'Place';
  AnnotationSnapResult? _annotationSnapPreview;
  Offset? _annotationDraftStartScreen;
  Offset? _annotationDraftEndScreen;
  Offset? _annotationDragStartScreen;
  Offset? _annotationDragEndScreen;
  int? _annotationDragId;
  RenderScenePoint? _annotationDragOrigin;
  bool _annotationDragMoved = false;
  bool _annotationDraftDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    AnnotationWorkspaceRuntime.document.addListener(_handleAnnotationChanged);
    AnnotationWorkspaceRuntime.selectedAnnotationId
        .addListener(_handleAnnotationChanged);
    AnnotationWorkspaceRuntime.moveSelectedArmed
        .addListener(_handleAnnotationChanged);
    WorkspaceToolSelection.changes.addListener(_handleWorkspaceToolChanged);
  }

  @override
  void didUpdateWidget(covariant RenderSceneViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    final textEditorCompleter = _annotationTextCompleter;
    if (textEditorCompleter != null && !textEditorCompleter.isCompleted) {
      textEditorCompleter.complete(null);
    }
    widget.controller.removeListener(_handleControllerChanged);
    AnnotationWorkspaceRuntime.document
        .removeListener(_handleAnnotationChanged);
    AnnotationWorkspaceRuntime.selectedAnnotationId
        .removeListener(_handleAnnotationChanged);
    AnnotationWorkspaceRuntime.moveSelectedArmed
        .removeListener(_handleAnnotationChanged);
    WorkspaceToolSelection.changes.removeListener(_handleWorkspaceToolChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleAnnotationChanged() {
    if (mounted) setState(() {});
  }

  void _handleWorkspaceToolChanged() {
    _clearAnnotationInteractionPreview();
    if (mounted) setState(() {});
  }

  void _clearAnnotationInteractionPreview() {
    _annotationSnapPreview = null;
    _annotationDraftStartScreen = null;
    _annotationDraftEndScreen = null;
    _annotationDragStartScreen = null;
    _annotationDragEndScreen = null;
    _annotationDragId = null;
    _annotationDragOrigin = null;
    _annotationDragMoved = false;
    _annotationDraftDragging = false;
  }

  bool get _shouldUseNativeAndroidView {
    return widget.controller.backend == RenderSceneViewportBackend.native &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool get _annotationModeActive =>
      WorkspaceToolSelection.tab == WorkspaceToolTab.annotate &&
      AnnotationWorkspaceRuntime.activeViewAcceptsAnnotations &&
      AnnotationWorkspaceRuntime.activeViewId != 0;

  @override
  Widget build(BuildContext context) {
    final viewport = _buildViewport(context);
    final annotationTool = WorkspaceToolSelection.annotationTool;
    final selectedIndex = _selectedAnnotationIndex();
    final selectedKind = selectedIndex == null
        ? null
        : AnnotationWorkspaceRuntime.document.store.kindAt(selectedIndex);
    final canEditSelectedLabel = selectedKind == AnnotationKind.text ||
        selectedKind == AnnotationKind.tag;
    final moveArmed = AnnotationWorkspaceRuntime.moveSelectedArmed.value;
    return Semantics(
      container: true,
      label: widget.controller.projectionMode.is3D
          ? '3D model viewport'
          : '2D drawing viewport',
      hint: _annotationModeActive
          ? moveArmed
              ? 'Tap the new location for the selected annotation.'
              : annotationTool == AnnotationWorkspaceTool.select
                  ? 'Tap a view annotation to select it.'
                  : 'Tap to place the selected view annotation.'
          : 'One finger selects or draws. Two fingers pan and zoom.',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          viewport,
          // Family representations are resolved independently from 3D family
          // geometry. Plan/elevation/section can therefore stay on a cheap
          // vector/generated path even when a family owns a detailed mesh.
          Family2dViewportOverlay(
            controller: widget.controller,
            activeView: widget.activeView,
          ),
          if (AnnotationWorkspaceRuntime.activeViewId != 0)
            AnnotationViewportOverlay(
              controller: widget.controller,
              store: AnnotationWorkspaceRuntime.document.store,
              viewId: AnnotationWorkspaceRuntime.activeViewId,
              selectedAnnotationId:
                  AnnotationWorkspaceRuntime.selectedAnnotationId.value,
              units: widget.units,
            ),
          if (_annotationModeActive)
            AnnotationInteractionOverlay(
              snapPoint: _annotationSnapPreview?.screenPoint,
              draftStart: _annotationDraftStartScreen,
              draftEnd: _annotationDraftEndScreen,
              dragStart: _annotationDragStartScreen,
              dragEnd: _annotationDragEndScreen,
            ),
          AnnotationHistoryControls(visible: _annotationModeActive),
          AnnotationSelectionControls(
            visible: _annotationModeActive &&
                annotationTool == AnnotationWorkspaceTool.select &&
                selectedIndex != null,
            kind: selectedKind,
            moveArmed: moveArmed,
            onEditLabel: canEditSelectedLabel
                ? () => unawaited(_editSelectedLabel())
                : null,
            onMove: _toggleSelectedMove,
            onDelete: _deleteSelectedAnnotation,
            onClear: AnnotationWorkspaceRuntime.clearSelection,
          ),
          if (_annotationTextController != null)
            _buildAnnotationTextEditor(context),
        ],
      ),
    );
  }

  Widget _buildAnnotationTextEditor(BuildContext context) {
    final controller = _annotationTextController!;
    final focusNode = _annotationTextFocusNode!;
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          _annotationTextTitle,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: _annotationTextHint,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) =>
                              _finishAnnotationTextEditor(controller.text),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: _cancelAnnotationTextEditor,
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _finishAnnotationTextEditor(
                                controller.text,
                              ),
                              child: Text(_annotationTextActionLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _finishAnnotationTextEditor(String rawValue) {
    final completer = _annotationTextCompleter;
    if (completer == null || completer.isCompleted) return;
    final value = rawValue.trim();
    _annotationTextFocusNode?.unfocus();
    completer.complete(value.isEmpty ? null : value);
  }

  void _cancelAnnotationTextEditor() {
    final completer = _annotationTextCompleter;
    if (completer == null || completer.isCompleted) return;
    _annotationTextFocusNode?.unfocus();
    completer.complete(null);
  }

  Widget _buildViewport(BuildContext context) {
    final scene = widget.controller.scene;
    if (scene == null) {
      return const Center(
        child: Text('Load a RenderScene sample to preview the viewport.'),
      );
    }

    if (_shouldUseNativeAndroidView) {
      final nativeClipOwnsInteraction =
          widget.controller.nativeOwnsClipGestures;
      return _FallbackRenderSceneView(
        controller: widget.controller,
        interactionMode: widget.interactionMode,
        annotationGestureMode: _annotationModeActive,
        onSceneTap: _routeSceneTap,
        onSceneDragStart: _routeSceneDragStart,
        onSceneDragUpdate: _routeSceneDragUpdate,
        onSceneDragEnd: _routeSceneDragEnd,
        onSceneHover: _routeSceneHover,
        onSceneMultiTouchStart: widget.onSceneMultiTouchStart,
        onSceneSecondaryTap: widget.onSceneSecondaryTap,
        authoringPickKinds: widget.authoringPickKinds,
        directSurfaceDrag: widget.directSurfaceDrag,
        planPickResolver: widget.planPickResolver,
        onLevelElevationSubmitted: widget.onLevelElevationSubmitted,
        draftSurfaceWallIds: widget.draftSurfaceWallIds,
        draftWallThicknessMeters: widget.draftWallThicknessMeters,
        draftWallHeightMeters: widget.draftWallHeightMeters,
        draftWallEditElementId: widget.draftWallEditElementId,
        showDiagnostics: widget.showDiagnostics,
        units: widget.units,
        nativeRenderer: true,
        rendererChild: IgnorePointer(
          // Native Filament owns gestures only for the 3D Section Box. Planar
          // section views use the shared Flutter camera/gesture path so the
          // model, levels and authoring hit tests cannot drift apart.
          ignoring: _annotationModeActive ||
              (!nativeClipOwnsInteraction &&
                  !widget.controller.projectionMode.is3D),
          child: _AndroidRenderSceneView(controller: widget.controller),
        ),
      );
    }

    return _FallbackRenderSceneView(
      controller: widget.controller,
      interactionMode: widget.interactionMode,
      annotationGestureMode: _annotationModeActive,
      onSceneTap: _routeSceneTap,
      onSceneDragStart: _routeSceneDragStart,
      onSceneDragUpdate: _routeSceneDragUpdate,
      onSceneDragEnd: _routeSceneDragEnd,
      onSceneHover: _routeSceneHover,
      onSceneMultiTouchStart: widget.onSceneMultiTouchStart,
      onSceneSecondaryTap: widget.onSceneSecondaryTap,
      authoringPickKinds: widget.authoringPickKinds,
      directSurfaceDrag: widget.directSurfaceDrag,
      planPickResolver: widget.planPickResolver,
      onLevelElevationSubmitted: widget.onLevelElevationSubmitted,
      draftSurfaceWallIds: widget.draftSurfaceWallIds,
      draftWallThicknessMeters: widget.draftWallThicknessMeters,
      draftWallHeightMeters: widget.draftWallHeightMeters,
      draftWallEditElementId: widget.draftWallEditElementId,
      showDiagnostics: widget.showDiagnostics,
      units: widget.units,
    );
  }

  RenderSceneProjection? _annotationProjection() {
    final scene = widget.controller.scene;
    final size = context.size;
    if (scene == null || size == null || size.isEmpty) return null;
    return RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: widget.controller.projectionMode,
      orbitProjectionStyle: widget.controller.orbitProjectionStyle,
      planCamera: widget.controller.planCamera,
      camera: widget.controller.camera,
      padding: 48,
    );
  }

  RenderSceneObject? _annotationObjectAt(Offset position) {
    final scene = widget.controller.scene;
    final size = context.size;
    if (scene == null || size == null || size.isEmpty) return null;
    return RenderSceneViewportHitTest.objectAtPosition(
      scene: scene,
      controller: widget.controller,
      size: size,
      position: position,
      interactionMode: RenderSceneInteractionMode.select,
      authoringPickKinds: const <String>{},
      touchFriendly: true,
    );
  }

  void _addAnnotationObjectSnapGeometry({
    required RenderSceneObject object,
    required RenderSceneProjection projection,
    required List<AnnotationSnapCandidate> points,
    required List<AnnotationSnapSegment> segments,
  }) {
    final elementId = object.elementId;
    final edges = object.featureEdges.where((edge) => edge.isFinite).take(128);
    var hasEdges = false;
    for (final edge in edges) {
      hasEdges = true;
      final startScreen = projection.project(edge.start).screen;
      final endScreen = projection.project(edge.end).screen;
      final midpoint = RenderScenePoint(
        x: (edge.start.x + edge.end.x) * 0.5,
        y: (edge.start.y + edge.end.y) * 0.5,
        z: (edge.start.z + edge.end.z) * 0.5,
      );
      points
        ..add(AnnotationSnapCandidate(
          modelPoint: edge.start,
          screenPoint: startScreen,
          kind: AnnotationSnapKind.endpoint,
          elementId: elementId,
        ))
        ..add(AnnotationSnapCandidate(
          modelPoint: edge.end,
          screenPoint: endScreen,
          kind: AnnotationSnapKind.endpoint,
          elementId: elementId,
        ))
        ..add(AnnotationSnapCandidate(
          modelPoint: midpoint,
          screenPoint: Offset(
            (startScreen.dx + endScreen.dx) * 0.5,
            (startScreen.dy + endScreen.dy) * 0.5,
          ),
          kind: AnnotationSnapKind.midpoint,
          elementId: elementId,
        ));
      segments.add(AnnotationSnapSegment(
        start: edge.start,
        end: edge.end,
        startScreen: startScreen,
        endScreen: endScreen,
        elementId: elementId,
      ));
    }
    if (hasEdges) return;

    // Imported/detail objects do not always expose semantic feature edges.
    // Their projected bounding box still gives reliable endpoint/center snaps
    // without walking a potentially massive mesh on every touch.
    final bounds = object.bounds;
    final z = (bounds.min.z + bounds.max.z) * 0.5;
    final corners = <RenderScenePoint>[
      RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: z),
      RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: z),
      RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: z),
      RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: z),
    ];
    final projected = corners
        .map((point) => projection.project(point).screen)
        .toList(growable: false);
    for (var index = 0; index < corners.length; index++) {
      points.add(AnnotationSnapCandidate(
        modelPoint: corners[index],
        screenPoint: projected[index],
        kind: AnnotationSnapKind.endpoint,
        elementId: elementId,
      ));
      final next = (index + 1) % corners.length;
      segments.add(AnnotationSnapSegment(
        start: corners[index],
        end: corners[next],
        startScreen: projected[index],
        endScreen: projected[next],
        elementId: elementId,
      ));
    }
    points.add(AnnotationSnapCandidate(
      modelPoint: bounds.center,
      screenPoint: projection.project(bounds.center).screen,
      kind: AnnotationSnapKind.center,
      elementId: elementId,
    ));
  }

  AnnotationSnapResult? _resolveAnnotationSnap({
    required Offset screenPoint,
    RenderScenePoint? fallbackModelPoint,
    RenderSceneObject? pickedObject,
    int? excludeAnnotationId,
  }) {
    final scene = widget.controller.scene;
    final projection = _annotationProjection();
    if (scene == null || projection == null) return null;

    final points = <AnnotationSnapCandidate>[];
    final segments = <AnnotationSnapSegment>[];
    final object = pickedObject ?? _annotationObjectAt(screenPoint);
    if (object != null) {
      _addAnnotationObjectSnapGeometry(
        object: object,
        projection: projection,
        points: points,
        segments: segments,
      );
    }

    final annotationTargets = <AnnotationSnapCandidate>[];
    final store = AnnotationWorkspaceRuntime.document.store;
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (viewId != 0) {
      for (final annotationIndex in store.queryView(viewId)) {
        if (annotationIndex >= store.length ||
            store.annotationIds[annotationIndex] == excludeAnnotationId) {
          continue;
        }
        final anchor = annotationIndex * 3;
        final modelPoint = RenderScenePoint(
          x: store.anchors[anchor],
          y: store.anchors[anchor + 1],
          z: store.anchors[anchor + 2],
        );
        final target = AnnotationSnapCandidate(
          modelPoint: modelPoint,
          screenPoint: projection.project(modelPoint).screen,
          kind: AnnotationSnapKind.center,
          elementId: null,
        );
        annotationTargets.add(target);
        points.add(target);
      }
    }

    // Alignment snaps keep notes/labels tidy without forcing the user to hit
    // the exact existing anchor. They are intentionally planar because a
    // screen-space horizontal/vertical alignment has no single 3D meaning.
    if (widget.controller.projectionMode.isPlanar) {
      const alignmentTolerance = 14.0;
      for (final target in annotationTargets) {
        final dx = (target.screenPoint.dx - screenPoint.dx).abs();
        final dy = (target.screenPoint.dy - screenPoint.dy).abs();
        if (dx <= alignmentTolerance && dy > 2) {
          final aligned = projection.unprojectPlan(
            Offset(target.screenPoint.dx, screenPoint.dy),
          );
          if (aligned != null) {
            points.add(AnnotationSnapCandidate(
              modelPoint: aligned,
              screenPoint: Offset(target.screenPoint.dx, screenPoint.dy),
              kind: AnnotationSnapKind.alignment,
            ));
          }
        }
        if (dy <= alignmentTolerance && dx > 2) {
          final aligned = projection.unprojectPlan(
            Offset(screenPoint.dx, target.screenPoint.dy),
          );
          if (aligned != null) {
            points.add(AnnotationSnapCandidate(
              modelPoint: aligned,
              screenPoint: Offset(screenPoint.dx, target.screenPoint.dy),
              kind: AnnotationSnapKind.alignment,
            ));
          }
        }
      }
    }

    final semanticSnap = AnnotationSnapResolver.resolve(
      pointer: screenPoint,
      points: points,
      segments: segments,
      tolerancePixels: 28,
    );
    if (semanticSnap != null ||
        fallbackModelPoint == null ||
        !widget.controller.projectionMode.isPlanar) {
      return semanticSnap;
    }

    // Grid is the deterministic fallback, not a competitor to a nearby wall
    // endpoint/edge or an alignment guide. Otherwise every touch would snap
    // to the nearest 100 mm grid point even when the user is clearly aiming
    // at a BIM feature.
    final gridPoint = snapAnnotationPointToGrid(fallbackModelPoint);
    return AnnotationSnapResolver.resolve(
      pointer: screenPoint,
      points: <AnnotationSnapCandidate>[
        AnnotationSnapCandidate(
          modelPoint: gridPoint,
          screenPoint: projection.project(gridPoint).screen,
          kind: AnnotationSnapKind.grid,
        ),
      ],
      tolerancePixels: 28,
    );
  }

  RenderScenePoint? _annotationModelPoint(
    RenderSceneTapDetails details, {
    AnnotationSnapResult? snap,
  }) =>
      snap?.modelPoint ?? details.modelPoint;

  int _annotationLevelId(RenderSceneTapDetails details) {
    final scene = widget.controller.scene;
    return AnnotationWorkspaceRuntime.activeLevelId != 0
        ? AnnotationWorkspaceRuntime.activeLevelId
        : details.pickedObject?.levelId ??
            (scene != null && scene.levels.isNotEmpty
                ? scene.levels.first.levelId
                : 0);
  }

  AnnotationHit? _annotationHit(Offset screenPoint) {
    final size = context.size;
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (size == null || size.isEmpty || viewId == 0) return null;
    return AnnotationHitTester.hitTest(
      store: AnnotationWorkspaceRuntime.document.store,
      viewId: viewId,
      controller: widget.controller,
      canvasSize: size,
      screenPoint: screenPoint,
      tolerancePixels: 24,
    );
  }

  void _routeSceneDragStart(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneDragStart?.call(details);
      return;
    }
    _clearAnnotationInteractionPreview();
    final tool = WorkspaceToolSelection.annotationTool;
    if (tool == AnnotationWorkspaceTool.dimension ||
        tool == AnnotationWorkspaceTool.detailLine) {
      final kind = tool == AnnotationWorkspaceTool.dimension
          ? AnnotationDraftKind.dimension
          : AnnotationDraftKind.detailLine;
      final existing = AnnotationWorkspaceRuntime.draftStart;
      final start = details.gestureStartPosition ?? details.screenPosition;
      final snap = _resolveAnnotationSnap(
        screenPoint: start,
        fallbackModelPoint: details.modelPoint,
        pickedObject: details.pickedObject,
      );
      final point = _annotationModelPoint(details, snap: snap);
      if (point == null) return;
      if (existing == null || existing.kind != kind) {
        AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
          kind: kind,
          point: point,
          referenceElementId:
              snap?.elementId ?? details.pickedObject?.elementId,
        );
        _annotationDraftStartScreen = snap?.screenPoint ?? start;
      } else {
        _annotationDraftStartScreen =
            _annotationProjection()?.project(existing.point).screen ?? start;
      }
      _annotationDraftDragging = true;
      _annotationSnapPreview = snap;
      _annotationDraftEndScreen = snap?.screenPoint ?? details.screenPosition;
      if (mounted) setState(() {});
      return;
    }
    if (tool != AnnotationWorkspaceTool.select) {
      // A one-finger drag belongs to the active annotation command. Never let
      // it leak into BIM selection/authoring, which was the source of the
      // apparent frozen objects and accidental model movement on tablets.
      return;
    }
    final start = details.gestureStartPosition ?? details.screenPosition;
    final hit = _annotationHit(start);
    if (hit == null) {
      AnnotationWorkspaceRuntime.clearSelection();
      return;
    }
    final store = AnnotationWorkspaceRuntime.document.store;
    final anchor = hit.annotationIndex * 3;
    _annotationDragId = hit.annotationId;
    _annotationDragOrigin = RenderScenePoint(
      x: store.anchors[anchor],
      y: store.anchors[anchor + 1],
      z: store.anchors[anchor + 2],
    );
    _annotationDragStartScreen = start;
    _annotationDragEndScreen = details.screenPosition;
    AnnotationWorkspaceRuntime.selectAnnotation(hit.annotationId);
    if (mounted) setState(() {});
  }

  void _routeSceneDragUpdate(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneDragUpdate?.call(details);
      return;
    }
    final selectedId = _annotationDragId;
    if (_annotationDraftDragging) {
      final snap = _resolveAnnotationSnap(
        screenPoint: details.screenPosition,
        fallbackModelPoint: details.modelPoint,
        pickedObject: details.pickedObject,
      );
      final point = _annotationModelPoint(details, snap: snap);
      if (point != null) {
        _annotationSnapPreview = snap;
        _annotationDraftEndScreen = snap?.screenPoint ?? details.screenPosition;
        if (mounted) setState(() {});
      }
      return;
    }
    if (selectedId == null) return;
    final snap = _resolveAnnotationSnap(
      screenPoint: details.screenPosition,
      fallbackModelPoint: details.modelPoint,
      excludeAnnotationId: selectedId,
    );
    final point = _annotationModelPoint(details, snap: snap);
    if (point == null) return;
    _annotationSnapPreview = snap;
    _annotationDragEndScreen = snap?.screenPoint ?? details.screenPosition;
    _annotationDragMoved = true;
    if (mounted) setState(() {});
  }

  void _routeSceneDragEnd(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneDragEnd?.call(details);
      return;
    }
    if (_annotationDraftDragging) {
      final draft = AnnotationWorkspaceRuntime.draftStart;
      final snap = _resolveAnnotationSnap(
        screenPoint: details.screenPosition,
        fallbackModelPoint: details.modelPoint,
        pickedObject: details.pickedObject,
      );
      final point = _annotationModelPoint(details, snap: snap);
      if (draft != null && point != null) {
        AnnotationWorkspaceRuntime.cancelDraft();
        final levelId = _annotationLevelId(details);
        if (draft.kind == AnnotationDraftKind.dimension) {
          AnnotationWorkspaceRuntime.document.addLinearDimension(
            viewId: AnnotationWorkspaceRuntime.activeViewId,
            levelId: levelId,
            anchorX: (draft.point.x + point.x) * 0.5,
            anchorY: (draft.point.y + point.y) * 0.5,
            anchorZ: (draft.point.z + point.z) * 0.5,
            startX: draft.point.x,
            startY: draft.point.y,
            startZ: draft.point.z,
            endX: point.x,
            endY: point.y,
            endZ: point.z,
            referenceAId: draft.referenceElementId,
            referenceBId: snap?.elementId,
          );
          _showAnnotationMessage('Dimension placed and aligned.');
        } else {
          AnnotationWorkspaceRuntime.document.addDetailLine(
            viewId: AnnotationWorkspaceRuntime.activeViewId,
            levelId: levelId,
            startX: draft.point.x,
            startY: draft.point.y,
            startZ: draft.point.z,
            endX: point.x,
            endY: point.y,
            endZ: point.z,
          );
          _showAnnotationMessage('Detail line placed and aligned.');
        }
      }
      _clearAnnotationInteractionPreview();
      if (mounted) setState(() {});
      return;
    }
    final selectedId = _annotationDragId;
    final origin = _annotationDragOrigin;
    if (selectedId == null || origin == null) {
      _clearAnnotationInteractionPreview();
      return;
    }
    final snap = _resolveAnnotationSnap(
      screenPoint: details.screenPosition,
      fallbackModelPoint: details.modelPoint,
      excludeAnnotationId: selectedId,
    );
    final point = _annotationModelPoint(details, snap: snap);
    if (_annotationDragMoved && point != null) {
      final moved = AnnotationWorkspaceRuntime.document.moveAnnotation(
        selectedId,
        dx: point.x - origin.x,
        dy: point.y - origin.y,
        dz: point.z - origin.z,
      );
      _showAnnotationMessage(
        moved
            ? 'Annotation moved and aligned.'
            : 'Annotation position unchanged.',
      );
    }
    _clearAnnotationInteractionPreview();
    if (mounted) setState(() {});
  }

  void _routeSceneTap(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneTap?.call(details);
      return;
    }
    // Annotation taps are consumed here and never forwarded to model
    // authoring. This keeps view documentation outside wall/floor rebuilds.
    unawaited(_handleAnnotationTap(details));
  }

  void _routeSceneHover(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneHover?.call(details);
      return;
    }
    final snap = _resolveAnnotationSnap(
      screenPoint: details.screenPosition,
      fallbackModelPoint: details.modelPoint,
      pickedObject: details.pickedObject,
      excludeAnnotationId: _annotationDragId,
    );
    _annotationSnapPreview = snap;
    final draft = AnnotationWorkspaceRuntime.draftStart;
    if (draft != null && !_annotationDraftDragging) {
      _annotationDraftStartScreen ??=
          _annotationProjection()?.project(draft.point).screen;
      _annotationDraftEndScreen = snap?.screenPoint ?? details.screenPosition;
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleAnnotationTap(RenderSceneTapDetails details) async {
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (viewId == 0) return;
    final tool = WorkspaceToolSelection.annotationTool;

    if (tool == AnnotationWorkspaceTool.select) {
      AnnotationWorkspaceRuntime.cancelDraft();
      if (AnnotationWorkspaceRuntime.moveSelectedArmed.value) {
        final selectedId =
            AnnotationWorkspaceRuntime.selectedAnnotationId.value;
        final selectedIndex = _selectedAnnotationIndex();
        final snap = _resolveAnnotationSnap(
          screenPoint: details.screenPosition,
          fallbackModelPoint: details.modelPoint,
          pickedObject: details.pickedObject,
          excludeAnnotationId: selectedId,
        );
        final point = _annotationModelPoint(details, snap: snap);
        if (selectedId == null || selectedIndex == null) {
          AnnotationWorkspaceRuntime.clearSelection();
          return;
        }
        if (point == null) {
          _showAnnotationMessage(
              'Tap inside the active model view to move it.');
          return;
        }
        final store = AnnotationWorkspaceRuntime.document.store;
        final anchor = selectedIndex * 3;
        final moved = AnnotationWorkspaceRuntime.document.moveAnnotation(
          selectedId,
          dx: point.x - store.anchors[anchor],
          dy: point.y - store.anchors[anchor + 1],
          dz: point.z - store.anchors[anchor + 2],
        );
        AnnotationWorkspaceRuntime.cancelSelectedMove();
        _showAnnotationMessage(
          moved
              ? 'Annotation moved and aligned.'
              : 'Annotation position unchanged.',
        );
        return;
      }

      final hit = _annotationHit(details.screenPosition);
      AnnotationWorkspaceRuntime.selectAnnotation(hit?.annotationId);
      return;
    }

    final snap = _resolveAnnotationSnap(
      screenPoint: details.screenPosition,
      fallbackModelPoint: details.modelPoint,
      pickedObject: details.pickedObject,
    );
    final point = _annotationModelPoint(details, snap: snap);
    if (point == null) {
      _showAnnotationMessage('Tap inside the active model view.');
      return;
    }
    final levelId = _annotationLevelId(details);
    final pickedId = details.pickedObject?.elementId;

    // Single-tap tools do not own a two-point draft. Clear any unfinished
    // Dimension/Detail Line command before placing one of these annotations.
    if (tool != AnnotationWorkspaceTool.dimension &&
        tool != AnnotationWorkspaceTool.detailLine &&
        AnnotationWorkspaceRuntime.draftStart != null) {
      AnnotationWorkspaceRuntime.cancelDraft();
    }

    switch (tool) {
      case AnnotationWorkspaceTool.select:
        // Handled before model-point validation so selecting screen-space text
        // does not depend on a BIM surface existing behind the annotation.
        return;
      case AnnotationWorkspaceTool.text:
        final value = await _promptText(
          title: 'Text note',
          hint: 'Enter annotation text',
        );
        if (!mounted || value == null || value.isEmpty) return;
        AnnotationWorkspaceRuntime.document.addText(
          viewId: viewId,
          levelId: levelId,
          x: point.x,
          y: point.y,
          z: point.z,
          value: value,
        );
        _showAnnotationMessage('Text note placed.');
        _clearAnnotationInteractionPreview();
      case AnnotationWorkspaceTool.dimension:
        final start = AnnotationWorkspaceRuntime.draftStart;
        if (start == null || start.kind != AnnotationDraftKind.dimension) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            kind: AnnotationDraftKind.dimension,
            point: point,
            referenceElementId: pickedId,
          );
          _annotationDraftStartScreen =
              snap?.screenPoint ?? details.screenPosition;
          _annotationDraftEndScreen = _annotationDraftStartScreen;
          _annotationSnapPreview = snap;
          if (mounted) setState(() {});
          _showAnnotationMessage('Dimension start set. Tap the second point.');
          return;
        }
        AnnotationWorkspaceRuntime.cancelDraft();
        AnnotationWorkspaceRuntime.document.addLinearDimension(
          viewId: viewId,
          levelId: levelId,
          anchorX: (start.point.x + point.x) * 0.5,
          anchorY: (start.point.y + point.y) * 0.5,
          anchorZ: (start.point.z + point.z) * 0.5,
          startX: start.point.x,
          startY: start.point.y,
          startZ: start.point.z,
          endX: point.x,
          endY: point.y,
          endZ: point.z,
          referenceAId: start.referenceElementId,
          referenceBId: pickedId,
        );
        _clearAnnotationInteractionPreview();
        _showAnnotationMessage('Dimension placed.');
      case AnnotationWorkspaceTool.tag:
        final object = details.pickedObject;
        final elementId = object?.elementId;
        if (object == null || elementId == null) {
          _showAnnotationMessage('Tap a BIM element to place a tag.');
          return;
        }
        final metadataName = object.metadata['name'] ??
            object.metadata['family_name'] ??
            object.metadata['familyName'];
        final defaultLabel = metadataName?.toString().trim().isNotEmpty == true
            ? metadataName.toString().trim()
            : '${object.kind} $elementId';
        final label = await _promptText(
          title: 'Tag label',
          hint: 'Tag text',
          initialValue: defaultLabel,
        );
        if (!mounted || label == null || label.isEmpty) return;
        AnnotationWorkspaceRuntime.document.addTag(
          viewId: viewId,
          levelId: levelId,
          x: point.x,
          y: point.y,
          z: point.z,
          targetElementId: elementId,
          label: label,
        );
        _showAnnotationMessage('Tag placed.');
        _clearAnnotationInteractionPreview();
      case AnnotationWorkspaceTool.detailLine:
        final start = AnnotationWorkspaceRuntime.draftStart;
        if (start == null || start.kind != AnnotationDraftKind.detailLine) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            kind: AnnotationDraftKind.detailLine,
            point: point,
            referenceElementId: pickedId,
          );
          _annotationDraftStartScreen =
              snap?.screenPoint ?? details.screenPosition;
          _annotationDraftEndScreen = _annotationDraftStartScreen;
          _annotationSnapPreview = snap;
          if (mounted) setState(() {});
          _showAnnotationMessage('Detail-line start set. Tap the end point.');
          return;
        }
        AnnotationWorkspaceRuntime.cancelDraft();
        AnnotationWorkspaceRuntime.document.addDetailLine(
          viewId: viewId,
          levelId: levelId,
          startX: start.point.x,
          startY: start.point.y,
          startZ: start.point.z,
          endX: point.x,
          endY: point.y,
          endZ: point.z,
        );
        _clearAnnotationInteractionPreview();
        _showAnnotationMessage('Detail line placed.');
      case AnnotationWorkspaceTool.symbol:
        AnnotationWorkspaceRuntime.document.addSymbol(
          viewId: viewId,
          levelId: levelId,
          x: point.x,
          y: point.y,
          z: point.z,
          // Keep the first placement one-tap on a touch device. The marker is
          // the built-in, renderer-independent fallback; a future symbol
          // library can add a picker without putting a raw asset key in the
          // primary placement flow.
          assetKey: 'builtin:marker',
        );
        _clearAnnotationInteractionPreview();
        _showAnnotationMessage('Symbol placed.');
    }
  }

  int? _selectedAnnotationIndex() {
    final selectedId = AnnotationWorkspaceRuntime.selectedAnnotationId.value;
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (selectedId == null || viewId == 0) return null;
    final store = AnnotationWorkspaceRuntime.document.store;
    for (final annotationIndex in store.queryView(viewId)) {
      if (store.annotationIds[annotationIndex] == selectedId) {
        return annotationIndex;
      }
    }
    return null;
  }

  int? _rowForAnnotation(List<int> annotationIndices, int annotationIndex) {
    for (var row = 0; row < annotationIndices.length; row++) {
      if (annotationIndices[row] == annotationIndex) return row;
    }
    return null;
  }

  String? _selectedAnnotationLabel(int annotationIndex) {
    final store = AnnotationWorkspaceRuntime.document.store;
    switch (store.kindAt(annotationIndex)) {
      case AnnotationKind.text:
        final row =
            _rowForAnnotation(store.text.annotationIndices, annotationIndex);
        return row == null ? null : store.strings[store.text.stringIds[row]];
      case AnnotationKind.tag:
        final row =
            _rowForAnnotation(store.tags.annotationIndices, annotationIndex);
        return row == null
            ? null
            : store.strings[store.tags.labelStringIds[row]];
      case AnnotationKind.linearDimension:
      case AnnotationKind.detailLine:
      case AnnotationKind.symbol:
        return null;
    }
  }

  Future<void> _editSelectedLabel() async {
    final selectedId = AnnotationWorkspaceRuntime.selectedAnnotationId.value;
    final annotationIndex = _selectedAnnotationIndex();
    if (selectedId == null || annotationIndex == null) return;
    final current = _selectedAnnotationLabel(annotationIndex);
    if (current == null) return;
    final value = await _promptText(
      title: 'Edit annotation',
      hint: 'Annotation text',
      initialValue: current,
      actionLabel: 'Save',
    );
    if (!mounted || value == null || value.isEmpty) return;
    final changed = AnnotationWorkspaceRuntime.document
        .replaceAnnotationLabel(selectedId, value);
    if (changed) _showAnnotationMessage('Annotation updated.');
  }

  void _toggleSelectedMove() {
    if (AnnotationWorkspaceRuntime.moveSelectedArmed.value) {
      AnnotationWorkspaceRuntime.cancelSelectedMove();
      _showAnnotationMessage('Annotation move cancelled.');
      return;
    }
    if (_selectedAnnotationIndex() == null) return;
    AnnotationWorkspaceRuntime.armSelectedMove();
    _showAnnotationMessage('Tap the new annotation location.');
  }

  void _deleteSelectedAnnotation() {
    final selectedId = AnnotationWorkspaceRuntime.selectedAnnotationId.value;
    if (selectedId == null) return;
    final deleted =
        AnnotationWorkspaceRuntime.document.deleteAnnotation(selectedId);
    if (!deleted) return;
    AnnotationWorkspaceRuntime.clearSelection();
    _showAnnotationMessage('Annotation deleted. Undo is available.');
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue = '',
    String actionLabel = 'Place',
  }) async {
    if (_annotationTextCompleter != null) return null;
    final controller = TextEditingController(text: initialValue);
    final focusNode = FocusNode();
    final completer = Completer<String?>();
    setState(() {
      _annotationTextController = controller;
      _annotationTextFocusNode = focusNode;
      _annotationTextCompleter = completer;
      _annotationTextTitle = title;
      _annotationTextHint = hint;
      _annotationTextActionLabel = actionLabel;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_annotationTextFocusNode, focusNode)) {
        focusNode.requestFocus();
      }
    });

    final value = await completer.future;
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future<void>.delayed(Duration.zero);
    if (mounted && identical(_annotationTextController, controller)) {
      setState(() {
        _annotationTextController = null;
        _annotationTextFocusNode = null;
        _annotationTextCompleter = null;
      });
    }
    controller.dispose();
    focusNode.dispose();
    return value;
  }

  void _showAnnotationMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(value),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }
}
