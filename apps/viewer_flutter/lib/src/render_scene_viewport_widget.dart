import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'render_scene_editor.dart';
import 'render_scene_level_overlay.dart';
import 'render_scene_models.dart';
import 'render_scene_native_overlay_painter.dart';
import 'render_scene_viewport_hit_test.dart';
import 'render_scene_viewport_controller.dart';
import 'render_scene_viewport_painter.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'viewport_interaction.dart';
import 'viewport_gesture_controller.dart';

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
  });

  final RenderSceneViewportController controller;
  final RenderSceneInteractionMode interactionMode;
  final ValueChanged<RenderSceneTapDetails>? onSceneTap;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragStart;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragUpdate;
  final ValueChanged<RenderSceneTapDetails>? onSceneDragEnd;
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

  @override
  State<RenderSceneViewport> createState() => _RenderSceneViewportState();
}

class _RenderSceneViewportState extends State<RenderSceneViewport> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
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
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _shouldUseNativeAndroidView {
    return widget.controller.backend == RenderSceneViewportBackend.native &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
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
        onSceneTap: widget.onSceneTap,
        onSceneDragStart: widget.onSceneDragStart,
        onSceneDragUpdate: widget.onSceneDragUpdate,
        onSceneDragEnd: widget.onSceneDragEnd,
        onSceneSecondaryTap: widget.onSceneSecondaryTap,
        onSceneHover: widget.onSceneHover,
        authoringPickKinds: widget.authoringPickKinds,
        directSurfaceDrag: widget.directSurfaceDrag,
        planPickResolver: widget.planPickResolver,
        onLevelElevationSubmitted: widget.onLevelElevationSubmitted,
        draftSurfaceWallIds: widget.draftSurfaceWallIds,
        draftWallThicknessMeters: widget.draftWallThicknessMeters,
        draftWallHeightMeters: widget.draftWallHeightMeters,
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
      onSceneTap: widget.onSceneTap,
      onSceneDragStart: widget.onSceneDragStart,
      onSceneDragUpdate: widget.onSceneDragUpdate,
      onSceneDragEnd: widget.onSceneDragEnd,
      onSceneSecondaryTap: widget.onSceneSecondaryTap,
      onSceneHover: widget.onSceneHover,
      authoringPickKinds: widget.authoringPickKinds,
      directSurfaceDrag: widget.directSurfaceDrag,
      planPickResolver: widget.planPickResolver,
      onLevelElevationSubmitted: widget.onLevelElevationSubmitted,
      draftSurfaceWallIds: widget.draftSurfaceWallIds,
      draftWallThicknessMeters: widget.draftWallThicknessMeters,
      draftWallHeightMeters: widget.draftWallHeightMeters,
    );
  }
}
