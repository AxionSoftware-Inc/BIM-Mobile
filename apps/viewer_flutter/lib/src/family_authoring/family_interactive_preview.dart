import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_geometry.dart';

/// Lightweight interactive 3D family preview.
///
/// This stays renderer-independent so Family Authoring does not acquire a
/// project/Filament dependency. One-finger drag orbits, pinch zooms and double
/// tap resets the camera. Geometry is evaluated only by the Family engine;
/// camera interaction never mutates the family document.
class FamilyInteractivePreview extends StatefulWidget {
  const FamilyInteractivePreview({
    super.key,
    required this.mesh,
    required this.lineColor,
    required this.fillColor,
    required this.background,
  });

  final FamilyEvaluatedMesh mesh;
  final Color lineColor;
  final Color fillColor;
  final Color background;

  @override
  State<FamilyInteractivePreview> createState() =>
      _FamilyInteractivePreviewState();
}

class _FamilyInteractivePreviewState extends State<FamilyInteractivePreview> {
  static const _defaultYaw = -0.68;
  static const _defaultPitch = -0.48;
  static const _defaultZoom = 1.0;

  double _yaw = _defaultYaw;
  double _pitch = _defaultPitch;
  double _zoom = _defaultZoom;
  double _startYaw = _defaultYaw;
  double _startPitch = _defaultPitch;
  double _startZoom = _defaultZoom;
  Offset _startFocal = Offset.zero;

  void _reset() {
    setState(() {
      _yaw = _defaultYaw;
      _pitch = _defaultPitch;
      _zoom = _defaultZoom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _reset,
      onScaleStart: (details) {
        _startYaw = _yaw;
        _startPitch = _pitch;
        _startZoom = _zoom;
        _startFocal = details.focalPoint;
      },
      onScaleUpdate: (details) {
        final delta = details.focalPoint - _startFocal;
        setState(() {
          if (details.pointerCount <= 1) {
            _yaw = _startYaw + delta.dx * 0.010;
            _pitch = (_startPitch + delta.dy * 0.010).clamp(-1.45, 1.45);
          } else {
            _zoom = (_startZoom * details.scale).clamp(0.22, 8.0);
            // Two-finger movement can still make a small orbit correction.
            // This feels much less rigid on a tablet than locking rotation
            // completely during a pinch.
            _yaw = _startYaw + delta.dx * 0.0025;
            _pitch = (_startPitch + delta.dy * 0.0025).clamp(-1.45, 1.45);
          }
        });
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _OrbitFamilyPainter(
                mesh: widget.mesh,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
                lineColor: widget.lineColor,
                fillColor: widget.fillColor,
                background: widget.background,
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Zoom out',
                    onPressed: () => setState(
                      () => _zoom = (_zoom / 1.22).clamp(0.22, 8.0),
                    ),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reset 3D view',
                    onPressed: _reset,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Zoom in',
                    onPressed: () => setState(
                      () => _zoom = (_zoom * 1.22).clamp(0.22, 8.0),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 10,
            child: Text(
              'Drag: orbit · Pinch: zoom · Double tap: reset',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.72),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ProjectedVertex {
  const _ProjectedVertex(this.x, this.y, this.depth);

  final double x;
  final double y;
  final double depth;
}

class _OrbitFamilyPainter extends CustomPainter {
  const _OrbitFamilyPainter({
    required this.mesh,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.lineColor,
    required this.fillColor,
    required this.background,
  });

  final FamilyEvaluatedMesh mesh;
  final double yaw;
  final double pitch;
  final double zoom;
  final Color lineColor;
  final Color fillColor;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty || size.isEmpty) return;

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final vertex in mesh.vertices) {
      minX = math.min(minX, vertex.x);
      minY = math.min(minY, vertex.y);
      minZ = math.min(minZ, vertex.z);
      maxX = math.max(maxX, vertex.x);
      maxY = math.max(maxY, vertex.y);
      maxZ = math.max(maxZ, vertex.z);
    }
    final cx = (minX + maxX) * 0.5;
    final cy = (minY + maxY) * 0.5;
    final cz = (minZ + maxZ) * 0.5;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    final projected = <_ProjectedVertex>[];
    for (final vertex in mesh.vertices) {
      final x = vertex.x - cx;
      final y = vertex.y - cy;
      final z = vertex.z - cz;
      final yawX = x * cosYaw - z * sinYaw;
      final yawZ = x * sinYaw + z * cosYaw;
      final pitchY = y * cosPitch - yawZ * sinPitch;
      final pitchZ = y * sinPitch + yawZ * cosPitch;
      projected.add(_ProjectedVertex(yawX, -pitchY, pitchZ));
    }

    final projectedMinX = projected.map((p) => p.x).reduce(math.min);
    final projectedMaxX = projected.map((p) => p.x).reduce(math.max);
    final projectedMinY = projected.map((p) => p.y).reduce(math.min);
    final projectedMaxY = projected.map((p) => p.y).reduce(math.max);
    final width = math.max(projectedMaxX - projectedMinX, 0.05);
    final height = math.max(projectedMaxY - projectedMinY, 0.05);
    final fit = math.min(
      math.max(size.width - 52.0, 1.0) / width,
      math.max(size.height - 62.0, 1.0) / height,
    );
    final scale = fit * 0.80 * zoom;
    final center = Offset(size.width * 0.5, size.height * 0.54);
    final modelCenter = Offset(
      (projectedMinX + projectedMaxX) * 0.5,
      (projectedMinY + projectedMaxY) * 0.5,
    );

    Offset screen(int index) {
      final point = projected[index];
      return Offset(
        center.dx + (point.x - modelCenter.dx) * scale,
        center.dy + (point.y - modelCenter.dy) * scale,
      );
    }

    final faceOrder = <({FamilyMeshFace face, double depth})>[];
    for (final face in mesh.faces) {
      if (face.indices.length < 3 ||
          face.indices.any((index) => index < 0 || index >= projected.length)) {
        continue;
      }
      final depth = face.indices
              .map((index) => projected[index].depth)
              .reduce((a, b) => a + b) /
          face.indices.length;
      faceOrder.add((face: face, depth: depth));
    }
    faceOrder.sort((a, b) => a.depth.compareTo(b.depth));

    final outline = Paint()
      ..color = lineColor.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    for (final entry in faceOrder) {
      final path = Path();
      final first = screen(entry.face.indices.first);
      path.moveTo(first.dx, first.dy);
      for (final index in entry.face.indices.skip(1)) {
        final point = screen(index);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      final depthShade = 0.78 +
          ((entry.depth -
                      faceOrder.first.depth) /
                  math.max(faceOrder.last.depth - faceOrder.first.depth, 1e-6)) *
              0.22;
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor.withValues(
            alpha: (fillColor.a * depthShade).clamp(0.0, 1.0),
          ),
      );
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitFamilyPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.background != background;
}
