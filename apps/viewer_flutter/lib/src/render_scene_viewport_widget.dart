import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'annotations/annotation_history_controls.dart';
import 'family_runtime/family_2d_viewport_overlay.dart';
import 'render_scene_editor.dart';
import 'render_scene_level_overlay.dart';
import 'render_scene_models.dart';
import 'render_scene_native_overlay_painter.dart';
import 'project_unit_settings.dart';
import 'render_scene_viewport_hit_test.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_painter.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'viewport_interaction.dart';
import 'viewport_gesture_controller.dart';
import 'workspace_chrome.dart';

part 'render_scene_viewport_support_widgets.dart';
part 'render_scene_viewport_fallback.dart';

class RenderSceneViewport extends StatefulWidget {
  const RenderSceneViewport({
    super.key,
    required this.controller,
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
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    AnnotationWorkspaceRuntime.document.addListener(_handleAnnotationChanged);
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
    widget.controller.removeListener(_handleControllerChanged);
    AnnotationWorkspaceRuntime.document.removeListener(_handleAnnotationChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleAnnotationChanged() {
    if (mounted) setState(() {});
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
    return Semantics(
      container: true,
      label: widget.controller.projectionMode.is3D
          ? '3D model viewport'
          : '2D drawing viewport',
      hint: _annotationModeActive
          ? 'Tap to place the selected view annotation.'
          : 'One finger selects or draws. Two fingers pan and zoom.',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          viewport,
          // Family representations are resolved independently from 3D family
          // geometry. Plan/elevation/section can therefore stay on a cheap
          // vector/generated path even when a family owns a detailed mesh.
          Family2dViewportOverlay(controller: widget.controller),
          if (AnnotationWorkspaceRuntime.activeViewId != 0)
            AnnotationViewportOverlay(
              controller: widget.controller,
              store: AnnotationWorkspaceRuntime.document.store,
              viewId: AnnotationWorkspaceRuntime.activeViewId,
              units: widget.units,
            ),
          AnnotationHistoryControls(visible: _annotationModeActive),
        ],
      ),
    );
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
        onSceneTap: _routeSceneTap,
        onSceneDragStart: widget.onSceneDragStart,
        onSceneDragUpdate: widget.onSceneDragUpdate,
        onSceneDragEnd: widget.onSceneDragEnd,
        onSceneMultiTouchStart: widget.onSceneMultiTouchStart,
        onSceneSecondaryTap: widget.onSceneSecondaryTap,
        onSceneHover: widget.onSceneHover,
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
          ignoring: !nativeClipOwnsInteraction &&
              !widget.controller.projectionMode.is3D,
          child: _AndroidRenderSceneView(controller: widget.controller),
        ),
      );
    }

    return _FallbackRenderSceneView(
      controller: widget.controller,
      interactionMode: widget.interactionMode,
      onSceneTap: _routeSceneTap,
      onSceneDragStart: widget.onSceneDragStart,
      onSceneDragUpdate: widget.onSceneDragUpdate,
      onSceneDragEnd: widget.onSceneDragEnd,
      onSceneMultiTouchStart: widget.onSceneMultiTouchStart,
      onSceneSecondaryTap: widget.onSceneSecondaryTap,
      onSceneHover: widget.onSceneHover,
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

  void _routeSceneTap(RenderSceneTapDetails details) {
    if (!_annotationModeActive) {
      widget.onSceneTap?.call(details);
      return;
    }
    // Annotation taps are consumed here and never forwarded to model
    // authoring. This keeps view documentation outside wall/floor rebuilds.
    unawaited(_handleAnnotationTap(details));
  }

  Future<void> _handleAnnotationTap(RenderSceneTapDetails details) async {
    final point = details.modelPoint;
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (point == null || viewId == 0) {
      _showAnnotationMessage('Tap inside the active model view.');
      return;
    }
    final scene = widget.controller.scene;
    final levelId = AnnotationWorkspaceRuntime.activeLevelId != 0
        ? AnnotationWorkspaceRuntime.activeLevelId
        : details.pickedObject?.levelId ??
            (scene != null && scene.levels.isNotEmpty
                ? scene.levels.first.levelId
                : 0);
    final pickedId = details.pickedObject?.elementId;

    switch (WorkspaceToolSelection.annotationTool) {
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
      case AnnotationWorkspaceTool.dimension:
        final start = AnnotationWorkspaceRuntime.draftStart;
        if (start == null) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            point: point,
            referenceElementId: pickedId,
          );
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
      case AnnotationWorkspaceTool.detailLine:
        final start = AnnotationWorkspaceRuntime.draftStart;
        if (start == null) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            point: point,
            referenceElementId: pickedId,
          );
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
        _showAnnotationMessage('Detail line placed.');
      case AnnotationWorkspaceTool.symbol:
        final assetKey = await _promptText(
          title: 'Annotation symbol',
          hint: 'Shared symbol key',
          initialValue: 'builtin:marker',
        );
        if (!mounted || assetKey == null || assetKey.isEmpty) return;
        AnnotationWorkspaceRuntime.document.addSymbol(
          viewId: viewId,
          levelId: levelId,
          x: point.x,
          y: point.y,
          z: point.z,
          assetKey: assetKey,
        );
        _showAnnotationMessage('Symbol placed.');
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue = '',
  }) async {
    final textController = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text.trim()),
              child: const Text('Place'),
            ),
          ],
        ),
      );
    } finally {
      textController.dispose();
    }
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
