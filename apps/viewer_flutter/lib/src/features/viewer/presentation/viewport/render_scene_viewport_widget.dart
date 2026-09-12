import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../annotations/presentation/annotation_history_controls.dart';
import '../../../annotations/presentation/annotation_hit_test.dart';
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
    final viewId = AnnotationWorkspaceRuntime.activeViewId;
    if (viewId == 0) return;
    final tool = WorkspaceToolSelection.annotationTool;

    if (tool == AnnotationWorkspaceTool.select) {
      AnnotationWorkspaceRuntime.cancelDraft();
      if (AnnotationWorkspaceRuntime.moveSelectedArmed.value) {
        final selectedId =
            AnnotationWorkspaceRuntime.selectedAnnotationId.value;
        final selectedIndex = _selectedAnnotationIndex();
        final point = details.modelPoint;
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
          moved ? 'Annotation moved.' : 'Annotation position unchanged.',
        );
        return;
      }

      final size = context.size;
      if (size == null || size.isEmpty) return;
      final hit = AnnotationHitTester.hitTest(
        store: AnnotationWorkspaceRuntime.document.store,
        viewId: viewId,
        controller: widget.controller,
        canvasSize: size,
        screenPoint: details.screenPosition,
        tolerancePixels: 16,
      );
      AnnotationWorkspaceRuntime.selectAnnotation(hit?.annotationId);
      return;
    }

    final point = details.modelPoint;
    if (point == null) {
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
      case AnnotationWorkspaceTool.dimension:
        final start = AnnotationWorkspaceRuntime.draftStart;
        if (start == null || start.kind != AnnotationDraftKind.dimension) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            kind: AnnotationDraftKind.dimension,
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
        if (start == null || start.kind != AnnotationDraftKind.detailLine) {
          AnnotationWorkspaceRuntime.draftStart = AnnotationDraftPoint(
            kind: AnnotationDraftKind.detailLine,
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
