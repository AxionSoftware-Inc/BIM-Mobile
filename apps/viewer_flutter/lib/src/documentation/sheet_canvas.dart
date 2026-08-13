import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render_scene_models.dart';
import '../render_scene_viewport_painter.dart';
import '../render_scene_viewport_planar.dart';
import '../render_scene_viewport_types.dart';
import 'document_models.dart';
import 'sheet_workspace_controller.dart';

typedef SheetViewDropCallback = Future<bool> Function(
  SheetViewReference view,
  double normalizedX,
  double normalizedY,
);

/// Main-workspace A3 canvas used while composing documentation sheets.
class SheetCanvas extends StatelessWidget {
  const SheetCanvas({
    super.key,
    required this.controller,
    required this.fallbackScene,
    required this.resolvedScenes,
    required this.onPlaceView,
    required this.onClose,
    required this.onOpenPdf,
  });

  final SheetWorkspaceController controller;
  final RenderScene fallbackScene;
  final Map<String, RenderScene> resolvedScenes;
  final SheetViewDropCallback onPlaceView;
  final VoidCallback onClose;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sheet = controller.activeSheet;
        if (sheet == null) return const SizedBox.shrink();
        return ColoredBox(
          color: const Color(0xFFE8ECEA),
          child: Column(
            children: <Widget>[
              _SheetContextBar(
                sheet: sheet,
                onClose: onClose,
                onOpenPdf: onOpenPdf,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const outerPadding = 28.0;
                    final availableWidth =
                        math.max(1.0, constraints.maxWidth - outerPadding * 2);
                    final availableHeight = math.max(
                      1.0,
                      constraints.maxHeight - outerPadding * 2,
                    );
                    const aspect = 420 / 297;
                    final width = math.min(
                      availableWidth,
                      availableHeight * aspect,
                    );
                    final height = width / aspect;
                    return Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: _SheetPaper(
                          sheet: sheet,
                          controller: controller,
                          fallbackScene: fallbackScene,
                          resolvedScenes: resolvedScenes,
                          onPlaceView: onPlaceView,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetContextBar extends StatelessWidget {
  const _SheetContextBar({
    required this.sheet,
    required this.onClose,
    required this.onOpenPdf,
  });

  final ProjectSheet sheet;
  final VoidCallback onClose;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: SizedBox(
        height: 54,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Close sheet',
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Icon(Icons.description_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${sheet.number} · ${sheet.title}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    'Project Browser view’larini uzoq bosib sheetga sudrang',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onOpenPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _SheetPaper extends StatefulWidget {
  const _SheetPaper({
    required this.sheet,
    required this.controller,
    required this.fallbackScene,
    required this.resolvedScenes,
    required this.onPlaceView,
  });

  final ProjectSheet sheet;
  final SheetWorkspaceController controller;
  final RenderScene fallbackScene;
  final Map<String, RenderScene> resolvedScenes;
  final SheetViewDropCallback onPlaceView;

  @override
  State<_SheetPaper> createState() => _SheetPaperState();
}

class _SheetPaperState extends State<_SheetPaper> {
  final GlobalKey _paperKey = GlobalKey();
  bool _dragHover = false;

  Future<void> _acceptDrop(
      DragTargetDetails<SheetViewReference> details) async {
    final box = _paperKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(details.offset);
    final accepted = await widget.onPlaceView(
      details.data,
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
    if (!mounted || accepted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${details.data.label} bu sheetda allaqachon bor.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paperSize = constraints.biggest;
        return DragTarget<SheetViewReference>(
          key: _paperKey,
          onWillAcceptWithDetails: (_) {
            setState(() => _dragHover = true);
            return true;
          },
          onLeave: (_) => setState(() => _dragHover = false),
          onAcceptWithDetails: (details) {
            setState(() => _dragHover = false);
            unawaited(_acceptDrop(details));
          },
          builder: (context, candidates, rejected) {
            return Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: Colors.black26,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _dragHover
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF111827),
                          width: _dragHover ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                  if (widget.sheet.placements.isEmpty)
                    Center(
                      child: _EmptySheetHint(active: _dragHover),
                    ),
                  for (final placement in widget.sheet.placements)
                    _buildPlacement(placement, paperSize),
                  _SheetTitleBlock(sheet: widget.sheet),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlacement(
    SheetViewportPlacement placement,
    Size paperSize,
  ) {
    final scene = widget.resolvedScenes[placement.view.id] ??
        _sceneForReference(widget.fallbackScene, placement.view);
    return Positioned(
      left: placement.left * paperSize.width,
      top: placement.top * paperSize.height,
      width: placement.width * paperSize.width,
      height: placement.height * paperSize.height,
      child: _PlacedSheetViewport(
        placement: placement,
        scene: scene,
        onMove: (delta) => widget.controller.movePlacement(
          placement.id,
          delta.dx / paperSize.width,
          delta.dy / paperSize.height,
        ),
        onResize: (delta) => widget.controller.resizePlacement(
          placement.id,
          delta.dx / paperSize.width,
          delta.dy / paperSize.height,
        ),
        onRemove: () => widget.controller.removePlacement(placement.id),
      ),
    );
  }
}

class _EmptySheetHint extends StatelessWidget {
  const _EmptySheetHint({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.drag_indicator, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            active ? 'Shu yerga qo‘yib yuboring' : 'Sheet hali bo‘sh',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Floor Plan, Elevation, Section yoki 3D View’ni\nProject Browser’dan uzoq bosib sudrang.',
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PlacedSheetViewport extends StatelessWidget {
  const _PlacedSheetViewport({
    required this.placement,
    required this.scene,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  final SheetViewportPlacement placement;
  final RenderScene scene;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            bottom: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onMove(details.delta),
              child: ClipRect(
                child: _SheetViewPreview(
                  scene: scene,
                  reference: placement.view,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 28,
            bottom: 0,
            height: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onMove(details.delta),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF111827))),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    placement.view.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: -5,
            child: InkResponse(
              radius: 14,
              onTap: onRemove,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 13),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 28,
            height: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onResize(details.delta),
              child: const Icon(Icons.drag_handle, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetViewPreview extends StatelessWidget {
  const _SheetViewPreview({
    required this.scene,
    required this.reference,
  });

  final RenderScene scene;
  final SheetViewReference reference;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final planCamera = _fitPlanCamera(
          scene.bounds,
          reference.projectionMode,
          size,
        );
        final maxExtent = math.max(
          math.max(scene.bounds.width, scene.bounds.depth),
          scene.bounds.height,
        );
        final camera = RenderSceneCameraState(
          center: scene.bounds.center,
          distance: math.max(maxExtent * 2.6, 10),
          yawRadians: math.pi / 4,
          pitchRadians: math.pi / 5.2,
          // The fallback perspective projection is normalized by camera
          // distance. A sheet viewport has no interactive Fit command, so a
          // stable framing multiplier fills the placed rectangle directly.
          zoomScale: 4.2,
        );
        return CustomPaint(
          painter: FallbackRenderScenePainter(
            scene: scene,
            visibleKinds: const <String>{},
            selectedElementIds: const <String>{},
            activeElementId: null,
            selectedLevelId: reference.levelId,
            highlightedElementId: null,
            projectionMode: reference.projectionMode,
            orbitProjectionStyle: reference.orbitProjectionStyle,
            displayStyle: reference.displayStyle,
            camera: camera,
            planCamera: planCamera,
            draftWallStart: null,
            draftWallEnd: null,
            draftOpening: null,
            draftSurface: null,
            draftWallThicknessMeters: 0.2,
            draftWallHeightMeters: 3,
            showObjectLabels: false,
            showReferenceGrid: false,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _SheetTitleBlock extends StatelessWidget {
  const _SheetTitleBlock({required this.sheet});

  final ProjectSheet sheet;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      height: 52,
      child: IgnorePointer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFF111827)),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'TABLET BIM · PROJECT DOCUMENTATION',
                      style: TextStyle(fontSize: 8, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF111827)),
                    right: BorderSide(color: Color(0xFF111827)),
                    bottom: BorderSide(color: Color(0xFF111827)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          sheet.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sheet.number,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

RenderScene _sceneForReference(
  RenderScene scene,
  SheetViewReference reference,
) {
  if (reference.kind == SheetViewKind.floorPlan) {
    return scene.filteredByLevel(reference.levelId);
  }
  return scene;
}

RenderScenePlanCameraState _fitPlanCamera(
  RenderSceneBounds bounds,
  RenderSceneProjectionMode mode,
  Size size,
) {
  final descriptor = mode.planarDescriptor;
  if (descriptor == null) {
    return RenderScenePlanCameraState(center: bounds.center, zoom: 1);
  }
  final width = math.max(descriptor.boundsWidth(bounds), 0.25);
  final height = math.max(descriptor.boundsHeight(bounds), 0.25);
  final usableWidth = math.max(size.width - 20, 1);
  final usableHeight = math.max(size.height - 20, 1);
  return RenderScenePlanCameraState(
    center: bounds.center,
    zoom: math.min(usableWidth / width, usableHeight / height),
  );
}
