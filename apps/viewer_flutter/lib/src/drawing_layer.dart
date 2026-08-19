import 'dart:async';

import 'package:flutter/material.dart';

import 'drawing_kernel.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport.dart';

typedef WallCommitCallback = Future<bool> Function(DrawingSegment segment);
typedef PolygonCommitCallback = Future<bool> Function(
  DrawingToolKind tool,
  List<RenderScenePoint> polygon,
);

class DrawingInteractionController extends ChangeNotifier {
  DrawingInteractionController({DrawingKernel? kernel})
      : kernel = kernel ?? const DrawingKernel();

  final DrawingKernel kernel;
  DrawingToolKind tool = DrawingToolKind.wall;
  bool enabled = false;
  bool chainMode = true;
  List<DrawingSegment> _segments = const <DrawingSegment>[];
  RenderScenePoint? _start;
  RenderScenePoint? _previewEnd;
  DrawingSnap? _snap;
  final List<RenderScenePoint> _polygon = <RenderScenePoint>[];
  Offset? _pointerDown;
  bool _busy = false;
  String? message;

  RenderScenePoint? get start => _start;
  RenderScenePoint? get previewEnd => _previewEnd;
  DrawingSnap? get snap => _snap;
  List<RenderScenePoint> get polygon => List.unmodifiable(_polygon);
  bool get busy => _busy;
  List<DrawingSegment> get segments => _segments;

  void setScene(RenderScene? scene) {
    _segments = scene == null
        ? const <DrawingSegment>[]
        : drawingSegmentsFromScene(scene);
    if (_start != null && scene == null) {
      cancel();
    }
    notifyListeners();
  }

  void setTool(DrawingToolKind nextTool) {
    if (tool == nextTool) {
      enabled = true;
      notifyListeners();
      return;
    }
    tool = nextTool;
    enabled = true;
    cancel(notify: false);
    message = '${_toolLabel(nextTool)} tool ready';
    notifyListeners();
  }

  void toggle() {
    enabled = !enabled;
    if (!enabled) {
      cancel(notify: false);
    }
    notifyListeners();
  }

  void cancel({bool notify = true}) {
    _start = null;
    _previewEnd = null;
    _snap = null;
    _polygon.clear();
    _pointerDown = null;
    if (notify) {
      notifyListeners();
    }
  }

  void pointerDown(
    Offset position,
    Size size,
    RenderSceneViewportController viewport,
  ) {
    if (!enabled || _busy || viewport.projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }
    _pointerDown = position;
    if (tool == DrawingToolKind.wall) {
      final world = viewport.planScreenToWorld(position, size);
      if (_start == null) {
        final snap = kernel.nearestEndpoint(world, _segments, kernel.endpointTolerance);
        _start = snap?.point ?? world;
        _snap = snap;
        message = snap == null ? 'Wall start set' : 'Wall start snapped to endpoint';
      }
    } else if (_start == null) {
      final world = viewport.planScreenToWorld(position, size);
      final snap = kernel.nearestEndpoint(world, _segments, kernel.endpointTolerance);
      _start = snap?.point ?? world;
      _snap = snap;
      message = snap == null
          ? '${_toolLabel(tool)} first point set'
          : '${_toolLabel(tool)} point snapped to endpoint';
    }
    notifyListeners();
  }

  void pointerMove(
    Offset position,
    Size size,
    RenderSceneViewportController viewport,
  ) {
    if (!enabled || _busy || _start == null ||
        viewport.projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }
    final down = _pointerDown;
    if (down != null && (position - down).distance >= 8) {
    }
    final world = viewport.planScreenToWorld(position, size);
    if (tool == DrawingToolKind.wall) {
      final solution = kernel.solveSegment(
        start: _start!,
        rawEnd: world,
        existing: _segments,
      );
      _previewEnd = solution.end;
      _snap = solution.snap;
    }
    notifyListeners();
  }

  Future<void> pointerUp(
    Offset position,
    Size size,
    RenderSceneViewportController viewport, {
    required WallCommitCallback onWallCommit,
    PolygonCommitCallback? onPolygonCommit,
  }) async {
    if (!enabled || _busy || viewport.projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }
    final world = viewport.planScreenToWorld(position, size);
    final down = _pointerDown;
    final wasTap = down == null || (position - down).distance < 8;
    _pointerDown = null;

    if (tool == DrawingToolKind.wall) {
      if (_start == null) {
        return;
      }
      final solution = kernel.solveSegment(
        start: _start!,
        rawEnd: world,
        existing: _segments,
      );
      final end = solution.end;
      if (kernel.distance(_start!, end) < 0.12) {
        message = 'Wall is too short';
        notifyListeners();
        return;
      }
      _previewEnd = end;
      _snap = solution.snap;
      _busy = true;
      notifyListeners();
      final segment = DrawingSegment(start: _start!, end: end, thickness: 0.2);
      try {
        final committed = await onWallCommit(segment);
        if (committed && chainMode) {
          _start = end;
          _previewEnd = null;
          _snap = null;
          message = 'Wall created — continue from the snapped endpoint';
        } else if (committed) {
          cancel(notify: false);
          message = 'Wall created';
        }
      } finally {
        _busy = false;
        notifyListeners();
      }
      return;
    }

    if (!wasTap || _start == null) {
      return;
    }
    final snap = kernel.nearestEndpoint(world, _segments, kernel.endpointTolerance);
    final point = snap?.point ?? world;
    if (_polygon.isEmpty) {
      _polygon.add(_start!);
      message = '${_toolLabel(tool)} first point set — tap the next point';
      notifyListeners();
      return;
    }
    if (_polygon.length >= 3 && kernel.distance(point, _polygon.first) <= kernel.endpointTolerance) {
      final polygon = List<RenderScenePoint>.from(_polygon);
      if (onPolygonCommit != null) {
        _busy = true;
        notifyListeners();
        try {
          final committed = await onPolygonCommit(tool, polygon);
          message = committed
              ? '${_toolLabel(tool)} outline committed'
              : '${_toolLabel(tool)} outline is preview-only';
        } finally {
          _busy = false;
          cancel(notify: false);
          notifyListeners();
        }
      } else {
        message = '${_toolLabel(tool)} outline closed';
        cancel();
      }
      return;
    }
    _polygon.add(point);
    _start = point;
    _previewEnd = null;
    _snap = snap;
    message = '${_polygon.length} points — tap the first point to close';
    notifyListeners();
  }

  String _toolLabel(DrawingToolKind value) {
    switch (value) {
      case DrawingToolKind.wall:
        return 'Wall';
      case DrawingToolKind.floor:
        return 'Floor';
      case DrawingToolKind.ceiling:
        return 'Ceiling';
    }
  }
}

class DrawingLayer extends StatefulWidget {
  const DrawingLayer({
    super.key,
    required this.controller,
    required this.viewport,
    required this.onWallCommit,
    this.onPolygonCommit,
  });

  final DrawingInteractionController controller;
  final RenderSceneViewportController viewport;
  final WallCommitCallback onWallCommit;
  final PolygonCommitCallback? onPolygonCommit;

  @override
  State<DrawingLayer> createState() => _DrawingLayerState();
}

class _DrawingLayerState extends State<DrawingLayer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.enabled ||
        widget.viewport.projectionMode != RenderSceneProjectionMode.topDown) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => widget.controller.pointerDown(
                event.localPosition,
                size,
                widget.viewport,
              ),
          onPointerMove: (event) => widget.controller.pointerMove(
                event.localPosition,
                size,
                widget.viewport,
              ),
          onPointerUp: (event) => unawaited(widget.controller.pointerUp(
                event.localPosition,
                size,
                widget.viewport,
                onWallCommit: widget.onWallCommit,
                onPolygonCommit: widget.onPolygonCommit,
              )),
          onPointerCancel: (_) => widget.controller.cancel(),
          child: CustomPaint(
            painter: _DrawingPainter(
              controller: widget.controller,
              viewport: widget.viewport,
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter({
    required this.controller,
    required this.viewport,
    required this.size,
  });

  final DrawingInteractionController controller;
  final RenderSceneViewportController viewport;
  final Size size;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;
    final snapPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final polygon = controller.polygon;
    if (polygon.length >= 2) {
      final path = Path();
      for (var index = 0; index < polygon.length; index++) {
        final screen = viewport.worldToPlanScreen(polygon[index], this.size);
        if (index == 0) {
          path.moveTo(screen.dx, screen.dy);
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    final start = controller.start;
    final end = controller.previewEnd;
    if (start != null && end != null) {
      final startScreen = viewport.worldToPlanScreen(start, this.size);
      final endScreen = viewport.worldToPlanScreen(end, this.size);
      canvas.drawLine(startScreen, endScreen, linePaint);
      canvas.drawCircle(startScreen, 8, pointPaint);
      canvas.drawCircle(endScreen, 8, pointPaint);
      final snap = controller.snap;
      if (snap != null) {
        final snapScreen = viewport.worldToPlanScreen(snap.point, this.size);
        canvas.drawCircle(snapScreen, 14, snapPaint);
        canvas.drawLine(
          snapScreen + const Offset(-18, 0),
          snapScreen + const Offset(18, 0),
          snapPaint,
        );
        canvas.drawLine(
          snapScreen + const Offset(0, -18),
          snapScreen + const Offset(0, 18),
          snapPaint,
        );
      }
    } else if (start != null) {
      canvas.drawCircle(viewport.worldToPlanScreen(start, this.size), 9, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
