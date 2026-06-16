import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

abstract class RenderSceneViewportActions extends ChangeNotifier {
  RenderScene? get scene;
  Set<String> get visibleKinds;
  String? get selectedElementId;
  String? get highlightedElementId;
  int get fitRevision;
  RenderSceneProjectionMode get projectionMode;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle;
  RenderSceneDisplayStyle get displayStyle;
  Offset get planPanOffset;

  Future<void> loadRenderScene(RenderScene scene);
  Future<void> clearScene();
  Future<void> fitCamera();
  Future<void> setVisibleKinds(Set<String> kinds);
  Future<void> setProjectionMode(RenderSceneProjectionMode mode);
  Future<void> setOrbitProjectionStyle(RenderSceneOrbitProjectionStyle style);
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style);
  void panPlanBy(Offset delta);
  void zoomPlanBy(double scaleDelta);
  Future<void> selectElement(String? elementId);
  Future<void> highlightElement(String? elementId);
}

class RenderSceneViewportController extends RenderSceneViewportActions {
  RenderSceneViewportController({
    Set<String>? visibleKinds,
  }) : _visibleKinds = visibleKinds ?? kDefaultVisibleSceneKinds.toSet();

  RenderScene? _scene;
  Set<String> _visibleKinds;
  String? _selectedElementId;
  String? _highlightedElementId;
  int _fitRevision = 0;
  int _sceneRevision = 0;
  RenderSceneProjectionMode _projectionMode = RenderSceneProjectionMode.topDown;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.perspective;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneBounds _sceneBounds = RenderSceneBounds.zero();
  double _orbitYawRadians = math.pi / 4;
  double _orbitPitchRadians = math.pi / 4.4;
  double _orbitDistance = 12.0;
  RenderScenePoint _orbitCenter = RenderScenePoint.zero();
  Offset _planPanOffset = Offset.zero;
  double _planZoom = 1.0;
  MethodChannel? _channel;

  @override
  RenderScene? get scene => _scene;

  @override
  Set<String> get visibleKinds => _visibleKinds;

  @override
  String? get selectedElementId => _selectedElementId;

  @override
  String? get highlightedElementId => _highlightedElementId;

  @override
  int get fitRevision => _fitRevision;

  @override
  RenderSceneProjectionMode get projectionMode => _projectionMode;

  @override
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle =>
      _orbitProjectionStyle;

  @override
  RenderSceneDisplayStyle get displayStyle => _displayStyle;

  @override
  Offset get planPanOffset => _planPanOffset;

  double get planZoom => _planZoom;

  int get sceneRevision => _sceneRevision;

  bool get hasNativeBridge => _channel != null;

  Future<void> attachNativeBridge(int viewId) async {
    _channel = MethodChannel('tbe/render_scene_view_$viewId');
    await _syncNativeBridge();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
        return _syncNativeBridge();
      }),
    );
  }

  @override
  Future<void> loadRenderScene(RenderScene scene) async {
    _scene = scene;
    _sceneBounds = scene.bounds;
    _sceneRevision += 1;
    _fitRevision += 1;
    notifyListeners();
    await _invoke('loadRenderSceneJson', jsonEncode(scene.toJson()));
  }

  @override
  Future<void> clearScene() async {
    _scene = null;
    _selectedElementId = null;
    _highlightedElementId = null;
    _sceneRevision += 1;
    _fitRevision += 1;
    notifyListeners();
    await _invoke('clearScene');
  }

  @override
  Future<void> fitCamera() async {
    final bounds = _scene?.bounds ?? _sceneBounds;
    _sceneBounds = bounds;
    _orbitCenter = RenderScenePoint(
      x: (bounds.min.x + bounds.max.x) * 0.5,
      y: (bounds.min.y + bounds.max.y) * 0.5,
      z: (bounds.min.z + bounds.max.z) * 0.5,
    );
    final width = (bounds.max.x - bounds.min.x).abs().clamp(0.001, 1e9);
    final depth = (bounds.max.y - bounds.min.y).abs().clamp(0.001, 1e9);
    final height = (bounds.max.z - bounds.min.z).abs().clamp(0.001, 1e9);
    final radius = math.max(width, math.max(depth, height)) * 0.95 + 1.0;
    _orbitDistance = math.max(radius * 4.4, 8.0);
    _orbitYawRadians = math.pi / 3.2;
    _orbitPitchRadians = math.pi / 4.8;
    _planPanOffset = Offset.zero;
    _planZoom = 1.0;
    _fitRevision += 1;
    notifyListeners();
    await _invoke('fitCamera');
  }

  @override
  Future<void> setProjectionMode(RenderSceneProjectionMode mode) async {
    _projectionMode = mode;
    if (mode == RenderSceneProjectionMode.topDown) {
      _orbitPitchRadians = math.pi / 2.0 - 0.12;
    } else if (_orbitPitchRadians >= math.pi / 2.0) {
      _orbitPitchRadians = math.pi / 4.8;
    }
    notifyListeners();
  }

  @override
  Future<void> setOrbitProjectionStyle(
    RenderSceneOrbitProjectionStyle style,
  ) async {
    _orbitProjectionStyle = style;
    notifyListeners();
  }

  @override
  Future<void> setDisplayStyle(RenderSceneDisplayStyle style) async {
    _displayStyle = style;
    notifyListeners();
  }

  @override
  void panPlanBy(Offset delta) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }
    _planPanOffset += delta;
    notifyListeners();
  }

  @override
  void zoomPlanBy(double scaleDelta) {
    if (_projectionMode != RenderSceneProjectionMode.topDown) {
      return;
    }
    _planZoom = (_planZoom * scaleDelta).clamp(0.2, 8.0);
    notifyListeners();
  }

  void orbitBy(Offset delta, Size viewportSize) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }
    final minDimension =
        math.max(math.min(viewportSize.width, viewportSize.height), 1.0);
    _orbitYawRadians += delta.dx / minDimension * math.pi * 1.35;
    _orbitPitchRadians =
        (_orbitPitchRadians - delta.dy / minDimension * math.pi * 1.05)
            .clamp(0.18, math.pi / 2.0 - 0.16);
    notifyListeners();
  }

  void zoomOrbit(double scaleDelta) {
    if (_projectionMode != RenderSceneProjectionMode.isometric) {
      return;
    }
    _orbitDistance = (_orbitDistance / scaleDelta).clamp(3.0, 650.0);
    notifyListeners();
  }

  RenderScenePoint get orbitCenter => _orbitCenter;
  double get orbitYawRadians => _orbitYawRadians;
  double get orbitPitchRadians => _orbitPitchRadians;
  double get orbitDistance => _orbitDistance;

  @override
  Future<void> setVisibleKinds(Set<String> kinds) async {
    _visibleKinds = kinds;
    notifyListeners();
    await _invoke('setVisibleKinds', kinds.toList());
  }

  @override
  Future<void> selectElement(String? elementId) async {
    _selectedElementId = elementId;
    notifyListeners();
    await _invoke('selectElement', elementId);
  }

  @override
  Future<void> highlightElement(String? elementId) async {
    _highlightedElementId = elementId;
    notifyListeners();
    await _invoke('highlightElement', elementId);
  }

  Future<void> _syncNativeBridge() async {
    if (_scene != null) {
      await _invoke('loadRenderSceneJson', jsonEncode(_scene!.toJson()));
    }
    await _invoke('setVisibleKinds', _visibleKinds.toList());
    await _invoke('selectElement', _selectedElementId);
    await _invoke('highlightElement', _highlightedElementId);
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Native bridge is intentionally optional in the skeleton.
    }
  }
}

class RenderSceneViewport extends StatefulWidget {
  const RenderSceneViewport({
    super.key,
    required this.controller,
  });

  final RenderSceneViewportController controller;

  @override
  State<RenderSceneViewport> createState() => _RenderSceneViewportState();
}

class _RenderSceneViewportState extends State<RenderSceneViewport> {
  Offset? _lastDragPosition;
  Offset? _pointerDownPosition;

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

  @override
  Widget build(BuildContext context) {
    return _buildFallbackViewport(context);
  }

  Widget _buildFallbackViewport(BuildContext context) {
    final scene = widget.controller.scene;
    if (scene == null) {
      return const Center(
        child: Text('Load a RenderScene sample to preview the viewport.'),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) {
              return;
            }
            final scaleDelta = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
            if (widget.controller.projectionMode ==
                RenderSceneProjectionMode.isometric) {
              widget.controller.zoomOrbit(scaleDelta);
            } else {
              widget.controller.zoomPlanBy(scaleDelta);
            }
          },
          onPointerDown: (PointerDownEvent event) {
            _pointerDownPosition = event.localPosition;
            _lastDragPosition = event.localPosition;
          },
          onPointerMove: (PointerMoveEvent event) {
            if (widget.controller.projectionMode ==
                RenderSceneProjectionMode.isometric) {
              final last = _lastDragPosition;
              if (last != null) {
                final delta = event.localPosition - last;
                widget.controller.orbitBy(delta, constraints.biggest);
              }
              _lastDragPosition = event.localPosition;
            } else {
              final last = _lastDragPosition;
              if (last != null) {
                final delta = event.localPosition - last;
                widget.controller.panPlanBy(delta);
              }
              _lastDragPosition = event.localPosition;
            }
          },
          onPointerUp: (PointerUpEvent event) async {
            final down = _pointerDownPosition;
            final moved = down == null
                ? double.infinity
                : (event.localPosition - down).distance;
            if (moved < 8.0) {
              final picked = _pickObjectAt(
                scene: scene,
                size: constraints.biggest,
                localPosition: event.localPosition,
                projectionMode: widget.controller.projectionMode,
                orbitProjectionStyle: widget.controller.orbitProjectionStyle,
                orbitCenter: widget.controller.orbitCenter,
                orbitYawRadians: widget.controller.orbitYawRadians,
                orbitPitchRadians: widget.controller.orbitPitchRadians,
                orbitDistance: widget.controller.orbitDistance,
                visibleKinds: widget.controller.visibleKinds,
                planPanOffset: widget.controller.planPanOffset,
                planZoom: widget.controller.planZoom,
              );
              if (picked != null) {
                await widget.controller
                    .selectElement(picked.elementId?.toString());
                await widget.controller
                    .highlightElement(picked.elementId?.toString());
              }
            }
            _pointerDownPosition = null;
            _lastDragPosition = null;
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SizedBox.expand(
                child: CustomPaint(
                  painter: _FallbackRenderScenePainter(
                    scene: scene,
                    visibleKinds: widget.controller.visibleKinds,
                    selectedElementId: widget.controller.selectedElementId,
                    highlightedElementId:
                        widget.controller.highlightedElementId,
                    projectionMode: widget.controller.projectionMode,
                    orbitProjectionStyle:
                        widget.controller.orbitProjectionStyle,
                    displayStyle: widget.controller.displayStyle,
                    orbitCenter: widget.controller.orbitCenter,
                    orbitYawRadians: widget.controller.orbitYawRadians,
                    orbitPitchRadians: widget.controller.orbitPitchRadians,
                    orbitDistance: widget.controller.orbitDistance,
                    planPanOffset: widget.controller.planPanOffset,
                    planZoom: widget.controller.planZoom,
                  ),
                ),
              ),
              const Positioned(
                left: 12,
                bottom: 12,
                child: _ViewportNoteCard(
                  message:
                      'Tap to select. Drag in 3D to orbit. Scroll to zoom.',
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _ViewportStatsCard(scene: scene),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewportNoteCard extends StatelessWidget {
  const _ViewportNoteCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _ViewportStatsCard extends StatelessWidget {
  const _ViewportStatsCard({required this.scene});

  final RenderScene scene;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Objects: ${scene.objectCount}'),
              Text('Vertices: ${scene.vertexCount}'),
              Text('Indices: ${scene.indexCount}'),
              Text('Triangles: ${scene.triangleCount}'),
              Text(
                'Bounds: ${scene.bounds.width.toStringAsFixed(2)} × ${scene.bounds.depth.toStringAsFixed(2)} × ${scene.bounds.height.toStringAsFixed(2)} m',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectedPoint {
  const _ProjectedPoint({
    required this.screen,
    required this.depth,
  });

  final Offset screen;
  final double depth;
}

class _TriangleRender {
  const _TriangleRender({
    required this.a,
    required this.b,
    required this.c,
    required this.depth,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  final _ProjectedPoint a;
  final _ProjectedPoint b;
  final _ProjectedPoint c;
  final double depth;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
}

class _FallbackRenderScenePainter extends CustomPainter {
  _FallbackRenderScenePainter({
    required this.scene,
    required this.visibleKinds,
    required this.selectedElementId,
    required this.highlightedElementId,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.displayStyle,
    required this.orbitCenter,
    required this.orbitYawRadians,
    required this.orbitPitchRadians,
    required this.orbitDistance,
    required this.planPanOffset,
    required this.planZoom,
  });

  final RenderScene scene;
  final Set<String> visibleKinds;
  final String? selectedElementId;
  final String? highlightedElementId;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneDisplayStyle displayStyle;
  final RenderScenePoint orbitCenter;
  final double orbitYawRadians;
  final double orbitPitchRadians;
  final double orbitDistance;
  final Offset planPanOffset;
  final double planZoom;

  static const double _padding = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF5F8F6);
    canvas.drawRect(Offset.zero & size, background);

    final bounds = scene.bounds;
    final projectedBounds = _projectSceneBoundsView(
      bounds,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      orbitCenter: orbitCenter,
      orbitYawRadians: orbitYawRadians,
      orbitPitchRadians: orbitPitchRadians,
      orbitDistance: orbitDistance,
      planPanOffset: planPanOffset,
      planZoom: planZoom,
    );
    final scaleX =
        (size.width - _padding * 2) / math.max(projectedBounds.width, 1e-3);
    final scaleY =
        (size.height - _padding * 2) / math.max(projectedBounds.height, 1e-3);
    final scale = math.min(scaleX, scaleY);
    final offsetX =
        _padding + (size.width - projectedBounds.width * scale) * 0.5;
    final offsetY =
        _padding + (size.height - projectedBounds.height * scale) * 0.5;

    void drawProjectedPoint(RenderScenePoint point, Paint paint) {
      final projected = _projectPoint(point);
      final x = offsetX + (projected.dx - projectedBounds.left) * scale;
      final y = offsetY + (projected.dy - projectedBounds.top) * scale;
      canvas.drawCircle(Offset(x, y), paint.strokeWidth * 1.5, paint);
    }

    _drawGrid(canvas, scale, offsetX, offsetY, projectedBounds);
    _drawAxes(canvas, scale, offsetX, offsetY);

    final filteredObjects = scene.objectsForKinds(visibleKinds);
    final projectedTriangles = <_TriangleRender>[];
    for (final object in filteredObjects) {
      final isSelected = selectedElementId != null &&
          object.elementId?.toString() == selectedElementId;
      final isHighlighted = highlightedElementId != null &&
          object.elementId?.toString() == highlightedElementId;
      final color = _kindColor(object.kindKey);
      final objectColor = isSelected
          ? const Color(0xFF1D4ED8)
          : isHighlighted
              ? const Color(0xFFB42318)
              : color;
      final strokeWidth = isSelected || isHighlighted
          ? 2.4
          : (displayStyle == RenderSceneDisplayStyle.wireframe ? 1.0 : 1.15);
      final triangles = _buildProjectedTriangles(
        object,
        projectionMode: projectionMode,
        orbitProjectionStyle: orbitProjectionStyle,
        orbitCenter: orbitCenter,
        orbitYawRadians: orbitYawRadians,
        orbitPitchRadians: orbitPitchRadians,
        orbitDistance: orbitDistance,
        planPanOffset: planPanOffset,
        planZoom: planZoom,
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY,
        projectedBounds: projectedBounds,
        fillColor: objectColor.withValues(
          alpha: displayStyle == RenderSceneDisplayStyle.wireframe
              ? 0.0
              : (isSelected || isHighlighted ? 0.55 : 0.82),
        ),
        strokeColor: objectColor.withValues(
          alpha: isSelected || isHighlighted ? 1.0 : 0.92,
        ),
        strokeWidth: strokeWidth,
      );
      projectedTriangles.addAll(triangles);

      final labelPoint = _projectScenePointView(
        object.bounds.max,
        projectionMode: projectionMode,
        orbitProjectionStyle: orbitProjectionStyle,
        orbitCenter: orbitCenter,
        orbitYawRadians: orbitYawRadians,
        orbitPitchRadians: orbitPitchRadians,
        orbitDistance: orbitDistance,
        planPanOffset: planPanOffset,
        planZoom: planZoom,
      );
      final labelOffset = Offset(
        offsetX + (labelPoint.screen.dx - projectedBounds.left) * scale,
        offsetY + (labelPoint.screen.dy - projectedBounds.top) * scale,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${prettySceneKind(object.kind)} ${object.elementId ?? ''}',
          style: TextStyle(
            color: isSelected || isHighlighted
                ? const Color(0xFF111827)
                : const Color(0xFF374151),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      tp.paint(canvas, labelOffset + const Offset(4, -14));
      if (displayStyle == RenderSceneDisplayStyle.wireframe) {
        drawProjectedPoint(
          object.bounds.min,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color,
        );
      }
    }

    projectedTriangles.sort((a, b) => b.depth.compareTo(a.depth));
    for (final triangle in projectedTriangles) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = triangle.fillColor;
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = triangle.strokeWidth
        ..color = triangle.strokeColor;
      final path = Path()
        ..moveTo(triangle.a.screen.dx, triangle.a.screen.dy)
        ..lineTo(triangle.b.screen.dx, triangle.b.screen.dy)
        ..lineTo(triangle.c.screen.dx, triangle.c.screen.dy)
        ..close();
      if (displayStyle == RenderSceneDisplayStyle.solid) {
        canvas.drawPath(path, fillPaint);
      }
      canvas.drawPath(path, strokePaint);
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFCBD5E1);
    canvas.drawRect(Offset.zero & size, border);
  }

  void _drawGrid(
    Canvas canvas,
    double scale,
    double offsetX,
    double offsetY,
    Rect projectedBounds,
  ) {
    const gridSpacing = 1.0;
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 0.5;
    for (var x = scene.bounds.min.x.floorToDouble();
        x <= scene.bounds.max.x.ceilToDouble();
        x += gridSpacing) {
      final start = _projectPoint(RenderScenePoint(
        x: x,
        y: scene.bounds.min.y,
        z: 0,
      ));
      final end = _projectPoint(RenderScenePoint(
        x: x,
        y: scene.bounds.max.y,
        z: 0,
      ));
      final a = Offset(
        offsetX + (start.dx - projectedBounds.left) * scale,
        offsetY + (start.dy - projectedBounds.top) * scale,
      );
      final b = Offset(
        offsetX + (end.dx - projectedBounds.left) * scale,
        offsetY + (end.dy - projectedBounds.top) * scale,
      );
      canvas.drawLine(a, b, paint);
    }
    for (var y = scene.bounds.min.y.floorToDouble();
        y <= scene.bounds.max.y.ceilToDouble();
        y += gridSpacing) {
      final start = _projectPoint(RenderScenePoint(
        x: scene.bounds.min.x,
        y: y,
        z: 0,
      ));
      final end = _projectPoint(RenderScenePoint(
        x: scene.bounds.max.x,
        y: y,
        z: 0,
      ));
      final a = Offset(
        offsetX + (start.dx - projectedBounds.left) * scale,
        offsetY + (start.dy - projectedBounds.top) * scale,
      );
      final b = Offset(
        offsetX + (end.dx - projectedBounds.left) * scale,
        offsetY + (end.dy - projectedBounds.top) * scale,
      );
      canvas.drawLine(a, b, paint);
    }
  }

  void _drawAxes(Canvas canvas, double scale, double offsetX, double offsetY) {
    final origin = _projectPoint(const RenderScenePoint(x: 0, y: 0, z: 0));
    final xAxis = _projectPoint(const RenderScenePoint(x: 1, y: 0, z: 0));
    final yAxis = _projectPoint(const RenderScenePoint(x: 0, y: 1, z: 0));
    final zAxis = _projectPoint(const RenderScenePoint(x: 0, y: 0, z: 1));
    final originOffset = Offset(
      offsetX + origin.dx * scale,
      offsetY + origin.dy * scale,
    );
    final xOffset = Offset(
      offsetX + xAxis.dx * scale,
      offsetY + xAxis.dy * scale,
    );
    final yOffset = Offset(
      offsetX + yAxis.dx * scale,
      offsetY + yAxis.dy * scale,
    );
    final zOffset = Offset(
      offsetX + zAxis.dx * scale,
      offsetY + zAxis.dy * scale,
    );
    final xPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2;
    final yPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..strokeWidth = 2;
    final zPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2;
    canvas.drawLine(originOffset, xOffset, xPaint);
    canvas.drawLine(originOffset, yOffset, yPaint);
    canvas.drawLine(originOffset, zOffset, zPaint);
  }

  List<_TriangleRender> _buildProjectedTriangles(
    RenderSceneObject object, {
    required RenderSceneProjectionMode projectionMode,
    required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
    required RenderScenePoint orbitCenter,
    required double orbitYawRadians,
    required double orbitPitchRadians,
    required double orbitDistance,
    required Offset planPanOffset,
    required double planZoom,
    required double scale,
    required double offsetX,
    required double offsetY,
    required Rect projectedBounds,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) {
    final rawTriangles = <List<RenderScenePoint>>[];
    final mesh = object.mesh;
    if (mesh.hasGeometry) {
      for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
        final a = _safeMeshPoint(mesh.positions, mesh.indices[i]);
        final b = _safeMeshPoint(mesh.positions, mesh.indices[i + 1]);
        final c = _safeMeshPoint(mesh.positions, mesh.indices[i + 2]);
        if (a != null && b != null && c != null) {
          rawTriangles.add(<RenderScenePoint>[a, b, c]);
        }
      }
    }
    if (rawTriangles.isEmpty) {
      rawTriangles.addAll(_fallbackBoxTriangles(object.bounds));
    }

    final renders = <_TriangleRender>[];
    for (final triangle in rawTriangles) {
      final projected = triangle
          .map(
            (point) => _projectScenePointView(
              point,
              projectionMode: projectionMode,
              orbitProjectionStyle: orbitProjectionStyle,
              orbitCenter: orbitCenter,
              orbitYawRadians: orbitYawRadians,
              orbitPitchRadians: orbitPitchRadians,
              orbitDistance: orbitDistance,
              planPanOffset: planPanOffset,
              planZoom: planZoom,
            ),
          )
          .toList(growable: false);
      final canvasPoints = projected
          .map(
            (point) => _canvasPoint(
              point.screen,
              scale: scale,
              offsetX: offsetX,
              offsetY: offsetY,
              projectedBounds: projectedBounds,
            ),
          )
          .toList(growable: false);
      if (_triangleArea(canvasPoints[0], canvasPoints[1], canvasPoints[2])
              .abs() <
          0.35) {
        continue;
      }
      final depth =
          (projected[0].depth + projected[1].depth + projected[2].depth) / 3.0;
      renders.add(
        _TriangleRender(
          a: _ProjectedPoint(
              screen: canvasPoints[0], depth: projected[0].depth),
          b: _ProjectedPoint(
              screen: canvasPoints[1], depth: projected[1].depth),
          c: _ProjectedPoint(
              screen: canvasPoints[2], depth: projected[2].depth),
          depth: depth,
          fillColor: fillColor,
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
        ),
      );
    }
    return renders;
  }

  Offset _projectPoint(RenderScenePoint point) {
    switch (projectionMode) {
      case RenderSceneProjectionMode.topDown:
        return Offset(point.x * planZoom, -point.y * planZoom) + planPanOffset;
      case RenderSceneProjectionMode.isometric:
        return _projectOrbit(point);
    }
  }

  Offset _projectOrbit(RenderScenePoint point) {
    final center = orbitCenter;
    final eyeX = center.x +
        orbitDistance * math.cos(orbitPitchRadians) * math.cos(orbitYawRadians);
    final eyeY = center.y +
        orbitDistance * math.cos(orbitPitchRadians) * math.sin(orbitYawRadians);
    final eyeZ = center.z + orbitDistance * math.sin(orbitPitchRadians);
    final forward = _normalize(RenderScenePoint(
      x: center.x - eyeX,
      y: center.y - eyeY,
      z: center.z - eyeZ,
    ));
    const upHint = RenderScenePoint(x: 0, y: 0, z: 1);
    var right = _cross(forward, upHint);
    if (_length(right) < 1e-6) {
      right = const RenderScenePoint(x: 1, y: 0, z: 0);
    } else {
      right = _normalize(right);
    }
    final up = _normalize(_cross(right, forward));
    final relative = RenderScenePoint(
      x: point.x - eyeX,
      y: point.y - eyeY,
      z: point.z - eyeZ,
    );
    final x = _dot(relative, right);
    final y = _dot(relative, up);
    final depth = math.max(0.001, _dot(relative, forward) + orbitDistance);
    if (orbitProjectionStyle == RenderSceneOrbitProjectionStyle.orthographic) {
      return Offset(x, y);
    }
    return Offset(x / depth, y / depth);
  }

  double _dot(RenderScenePoint a, RenderScenePoint b) =>
      a.x * b.x + a.y * b.y + a.z * b.z;

  RenderScenePoint _cross(RenderScenePoint a, RenderScenePoint b) {
    return RenderScenePoint(
      x: a.y * b.z - a.z * b.y,
      y: a.z * b.x - a.x * b.z,
      z: a.x * b.y - a.y * b.x,
    );
  }

  double _length(RenderScenePoint point) =>
      math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z);

  RenderScenePoint _normalize(RenderScenePoint point) {
    final length = _length(point);
    if (length <= 1e-9) {
      return const RenderScenePoint(x: 0, y: 0, z: 1);
    }
    return RenderScenePoint(
      x: point.x / length,
      y: point.y / length,
      z: point.z / length,
    );
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'wall':
        return const Color(0xFF7C9885);
      case 'door':
        return const Color(0xFF8D6E63);
      case 'window':
        return const Color(0xFF4C8BF5);
      case 'slab':
        return const Color(0xFF94A3B8);
      case 'roof':
        return const Color(0xFFB45309);
      case 'column':
        return const Color(0xFF6B7280);
      case 'beam':
        return const Color(0xFF4B5563);
      case 'stair':
        return const Color(0xFF7E57C2);
      case 'room':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  bool shouldRepaint(covariant _FallbackRenderScenePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.visibleKinds != visibleKinds ||
        oldDelegate.selectedElementId != selectedElementId ||
        oldDelegate.highlightedElementId != highlightedElementId ||
        oldDelegate.projectionMode != projectionMode ||
        oldDelegate.orbitProjectionStyle != orbitProjectionStyle ||
        oldDelegate.displayStyle != displayStyle ||
        oldDelegate.orbitCenter != orbitCenter ||
        oldDelegate.orbitYawRadians != orbitYawRadians ||
        oldDelegate.orbitPitchRadians != orbitPitchRadians ||
        oldDelegate.orbitDistance != orbitDistance ||
        oldDelegate.planPanOffset != planPanOffset ||
        oldDelegate.planZoom != planZoom;
  }
}

RenderSceneObject? _pickObjectAt({
  required RenderScene scene,
  required Size size,
  required Offset localPosition,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderScenePoint orbitCenter,
  required double orbitYawRadians,
  required double orbitPitchRadians,
  required double orbitDistance,
  required Set<String> visibleKinds,
  required Offset planPanOffset,
  required double planZoom,
}) {
  final objects = scene.objectsForKinds(visibleKinds);
  if (objects.isEmpty) {
    return null;
  }
  final projectedBounds = _projectSceneBoundsView(
    scene.bounds,
    projectionMode: projectionMode,
    orbitProjectionStyle: orbitProjectionStyle,
    orbitCenter: orbitCenter,
    orbitYawRadians: orbitYawRadians,
    orbitPitchRadians: orbitPitchRadians,
    orbitDistance: orbitDistance,
    planPanOffset: planPanOffset,
    planZoom: planZoom,
  );
  final scaleX = (size.width - _FallbackRenderScenePainter._padding * 2) /
      math.max(projectedBounds.width, 1e-3);
  final scaleY = (size.height - _FallbackRenderScenePainter._padding * 2) /
      math.max(projectedBounds.height, 1e-3);
  final scale = math.min(scaleX, scaleY);
  final offsetX = _FallbackRenderScenePainter._padding +
      (size.width - projectedBounds.width * scale) * 0.5;
  final offsetY = _FallbackRenderScenePainter._padding +
      (size.height - projectedBounds.height * scale) * 0.5;

  RenderSceneObject? bestObject;
  double bestScore = double.infinity;
  for (final object in objects) {
    final rect = _projectObjectRectView(
      object.bounds,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      orbitCenter: orbitCenter,
      orbitYawRadians: orbitYawRadians,
      orbitPitchRadians: orbitPitchRadians,
      orbitDistance: orbitDistance,
      planPanOffset: planPanOffset,
      planZoom: planZoom,
    );
    final canvasRect = Rect.fromLTRB(
      offsetX + (rect.left - projectedBounds.left) * scale,
      offsetY + (rect.top - projectedBounds.top) * scale,
      offsetX + (rect.right - projectedBounds.left) * scale,
      offsetY + (rect.bottom - projectedBounds.top) * scale,
    );
    if (!canvasRect.inflate(18).contains(localPosition)) {
      continue;
    }
    final center = canvasRect.center;
    final score = (center - localPosition).distance;
    if (score < bestScore) {
      bestScore = score;
      bestObject = object;
    }
  }
  return bestObject;
}

Rect _projectSceneBoundsView(
  RenderSceneBounds bounds, {
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderScenePoint orbitCenter,
  required double orbitYawRadians,
  required double orbitPitchRadians,
  required double orbitDistance,
  required Offset planPanOffset,
  required double planZoom,
}) {
  final corners = _boundsCorners(bounds);
  final projected = corners
      .map(
        (point) => _projectScenePointView(
          point,
          projectionMode: projectionMode,
          orbitProjectionStyle: orbitProjectionStyle,
          orbitCenter: orbitCenter,
          orbitYawRadians: orbitYawRadians,
          orbitPitchRadians: orbitPitchRadians,
          orbitDistance: orbitDistance,
          planPanOffset: planPanOffset,
          planZoom: planZoom,
        ),
      )
      .toList(growable: false);
  var minX = projected.first.screen.dx;
  var minY = projected.first.screen.dy;
  var maxX = projected.first.screen.dx;
  var maxY = projected.first.screen.dy;
  for (final point in projected.skip(1)) {
    if (point.screen.dx < minX) minX = point.screen.dx;
    if (point.screen.dy < minY) minY = point.screen.dy;
    if (point.screen.dx > maxX) maxX = point.screen.dx;
    if (point.screen.dy > maxY) maxY = point.screen.dy;
  }
  if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Rect _projectObjectRectView(
  RenderSceneBounds bounds, {
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderScenePoint orbitCenter,
  required double orbitYawRadians,
  required double orbitPitchRadians,
  required double orbitDistance,
  required Offset planPanOffset,
  required double planZoom,
}) {
  return _projectSceneBoundsView(
    bounds,
    projectionMode: projectionMode,
    orbitProjectionStyle: orbitProjectionStyle,
    orbitCenter: orbitCenter,
    orbitYawRadians: orbitYawRadians,
    orbitPitchRadians: orbitPitchRadians,
    orbitDistance: orbitDistance,
    planPanOffset: planPanOffset,
    planZoom: planZoom,
  );
}

_ProjectedPoint _projectScenePointView(
  RenderScenePoint point, {
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderScenePoint orbitCenter,
  required double orbitYawRadians,
  required double orbitPitchRadians,
  required double orbitDistance,
  required Offset planPanOffset,
  required double planZoom,
}) {
  switch (projectionMode) {
    case RenderSceneProjectionMode.topDown:
      return _ProjectedPoint(
        screen: Offset(point.x * planZoom, -point.y * planZoom) + planPanOffset,
        depth: point.z,
      );
    case RenderSceneProjectionMode.isometric:
      final eyeX = orbitCenter.x +
          orbitDistance *
              math.cos(orbitPitchRadians) *
              math.cos(orbitYawRadians);
      final eyeY = orbitCenter.y +
          orbitDistance *
              math.cos(orbitPitchRadians) *
              math.sin(orbitYawRadians);
      final eyeZ = orbitCenter.z + orbitDistance * math.sin(orbitPitchRadians);
      final forward = _normalizePoint(RenderScenePoint(
        x: orbitCenter.x - eyeX,
        y: orbitCenter.y - eyeY,
        z: orbitCenter.z - eyeZ,
      ));
      const upHint = RenderScenePoint(x: 0, y: 0, z: 1);
      var right = _crossPoint(forward, upHint);
      if (_lengthPoint(right) < 1e-6) {
        right = const RenderScenePoint(x: 1, y: 0, z: 0);
      } else {
        right = _normalizePoint(right);
      }
      final up = _normalizePoint(_crossPoint(right, forward));
      final relative = RenderScenePoint(
        x: point.x - eyeX,
        y: point.y - eyeY,
        z: point.z - eyeZ,
      );
      final x = _dotPoint(relative, right);
      final y = _dotPoint(relative, up);
      final depth =
          math.max(0.001, _dotPoint(relative, forward) + orbitDistance);
      if (orbitProjectionStyle ==
          RenderSceneOrbitProjectionStyle.orthographic) {
        return _ProjectedPoint(
          screen: Offset(x, y),
          depth: depth,
        );
      }
      return _ProjectedPoint(
        screen: Offset(x / depth, y / depth),
        depth: depth,
      );
  }
}

Offset _canvasPoint(
  Offset point, {
  required double scale,
  required double offsetX,
  required double offsetY,
  required Rect projectedBounds,
}) {
  return Offset(
    offsetX + (point.dx - projectedBounds.left) * scale,
    offsetY + (point.dy - projectedBounds.top) * scale,
  );
}

double _triangleArea(Offset a, Offset b, Offset c) {
  return ((b.dx - a.dx) * (c.dy - a.dy)) - ((b.dy - a.dy) * (c.dx - a.dx));
}

RenderScenePoint? _safeMeshPoint(List<RenderScenePoint> positions, int index) {
  if (index < 0 || index >= positions.length) {
    return null;
  }
  final point = positions[index];
  if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
    return null;
  }
  return point;
}

List<List<RenderScenePoint>> _fallbackBoxTriangles(RenderSceneBounds bounds) {
  final corners = _boundsCorners(bounds);
  return <List<RenderScenePoint>>[
    <RenderScenePoint>[corners[0], corners[1], corners[2]],
    <RenderScenePoint>[corners[0], corners[2], corners[3]],
    <RenderScenePoint>[corners[4], corners[5], corners[6]],
    <RenderScenePoint>[corners[4], corners[6], corners[7]],
    <RenderScenePoint>[corners[0], corners[1], corners[5]],
    <RenderScenePoint>[corners[0], corners[5], corners[4]],
    <RenderScenePoint>[corners[1], corners[2], corners[6]],
    <RenderScenePoint>[corners[1], corners[6], corners[5]],
    <RenderScenePoint>[corners[2], corners[3], corners[7]],
    <RenderScenePoint>[corners[2], corners[7], corners[6]],
    <RenderScenePoint>[corners[3], corners[0], corners[4]],
    <RenderScenePoint>[corners[3], corners[4], corners[7]],
  ];
}

List<RenderScenePoint> _boundsCorners(RenderSceneBounds bounds) {
  return <RenderScenePoint>[
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.max.z),
  ];
}

double _dotPoint(RenderScenePoint a, RenderScenePoint b) =>
    a.x * b.x + a.y * b.y + a.z * b.z;

RenderScenePoint _crossPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  );
}

double _lengthPoint(RenderScenePoint point) =>
    math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z);

RenderScenePoint _normalizePoint(RenderScenePoint point) {
  final length = _lengthPoint(point);
  if (length <= 1e-9) {
    return const RenderScenePoint(x: 0, y: 0, z: 1);
  }
  return RenderScenePoint(
    x: point.x / length,
    y: point.y / length,
    z: point.z / length,
  );
}
