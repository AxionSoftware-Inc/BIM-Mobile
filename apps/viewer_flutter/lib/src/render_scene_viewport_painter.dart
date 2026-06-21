import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'render_scene_editor.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';

class FallbackRenderScenePainter extends CustomPainter {
  FallbackRenderScenePainter({
    required this.scene,
    required this.visibleKinds,
    required this.selectedElementId,
    required this.highlightedElementId,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.displayStyle,
    required this.camera,
    required this.planCamera,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftOpening,
    required this.draftSurface,
    required this.draftWallThicknessMeters,
    required this.draftWallHeightMeters,
  });

  static const double padding = 48;

  final RenderScene scene;
  final Set<String> visibleKinds;
  final String? selectedElementId;
  final String? highlightedElementId;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneDisplayStyle displayStyle;
  final RenderSceneCameraState camera;
  final RenderScenePlanCameraState planCamera;
  final RenderScenePoint? draftWallStart;
  final RenderScenePoint? draftWallEnd;
  final RenderSceneOpeningDraft? draftOpening;
  final RenderSceneSurfaceDraft? draftSurface;
  final double draftWallThicknessMeters;
  final double draftWallHeightMeters;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF5F8F6),
    );

    if (size.width <= 1 || size.height <= 1) {
      return;
    }

    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      planCamera: planCamera,
      camera: camera,
      padding: padding,
    );

    _drawGrid(canvas, projection);
    _drawAxes(canvas, projection);

    final packets = <_RenderPacket>[];
    final filteredObjects = scene.objectsForKinds(visibleKinds);

    for (final object in filteredObjects) {
      final elementId = object.elementId?.toString();
      final isSelected =
          elementId == selectedElementId && selectedElementId != null;
      final isHighlighted =
          elementId == highlightedElementId && highlightedElementId != null;
      final baseColor = _kindColor(object.kindKey);
      final objectColor = isSelected
          ? const Color(0xFF2563EB)
          : isHighlighted
              ? const Color(0xFFDC2626)
              : baseColor;

      final strokeWidth = isSelected || isHighlighted ? 2.2 : 1.0;
      final fillAlpha = displayStyle == RenderSceneDisplayStyle.wireframe
          ? 0.0
          : _fillAlphaForObject(
              kind: object.kindKey,
              isSelected: isSelected,
              isHighlighted: isHighlighted,
            );

      packets.add(
        _RenderPacket(
          triangles: _buildObjectTriangles(
            object: object,
            projection: projection,
            fillColor: objectColor.withValues(alpha: fillAlpha),
            strokeColor: objectColor.withValues(alpha: 0.96),
            strokeWidth: strokeWidth,
          ),
          outlines: displayStyle == RenderSceneDisplayStyle.solid &&
                  _shouldDrawSolidOutline(
                    kind: object.kindKey,
                    isSelected: isSelected,
                    isHighlighted: isHighlighted,
                  )
              ? _buildOutlineSegments(object, projection)
              : const <_OutlineSegment>[],
          outlineColor: isSelected || isHighlighted
              ? objectColor.withValues(alpha: 0.95)
              : const Color(0xFF475569).withValues(alpha: 0.40),
          outlineStrokeWidth: isSelected ? 2.0 : (isHighlighted ? 1.6 : 1.0),
        ),
      );
    }

    packets.sort((a, b) => b.depth.compareTo(a.depth));

    for (final packet in packets) {
      for (final triangle in packet.triangles) {
        final path = Path()
          ..moveTo(triangle.a.dx, triangle.a.dy)
          ..lineTo(triangle.b.dx, triangle.b.dy)
          ..lineTo(triangle.c.dx, triangle.c.dy)
          ..close();

        if (displayStyle == RenderSceneDisplayStyle.solid) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.fill
              ..color = triangle.fillColor,
          );
        }

        if (displayStyle == RenderSceneDisplayStyle.wireframe) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = triangle.strokeWidth
              ..color = triangle.strokeColor,
          );
        }
      }

      if (displayStyle == RenderSceneDisplayStyle.solid) {
        for (final segment in packet.outlines) {
          canvas.drawLine(
            segment.a,
            segment.b,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = packet.outlineStrokeWidth
              ..color = packet.outlineColor,
          );
        }
      }
    }

    _drawLabels(canvas, projection, filteredObjects);
    _drawDraftOverlay(canvas, projection);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFCBD5E1),
    );
  }

  List<_TriangleRender> _buildObjectTriangles({
    required RenderSceneObject object,
    required RenderSceneProjection projection,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) {
    final rawTriangles = <List<RenderScenePoint>>[];
    final mesh = object.mesh;
    if (mesh.hasGeometry) {
      for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
        final a = safeMeshPoint(mesh.positions, mesh.indices[i]);
        final b = safeMeshPoint(mesh.positions, mesh.indices[i + 1]);
        final c = safeMeshPoint(mesh.positions, mesh.indices[i + 2]);
        if (a != null && b != null && c != null) {
          rawTriangles.add(<RenderScenePoint>[a, b, c]);
        }
      }
    }

    if (rawTriangles.isEmpty) {
      rawTriangles.addAll(fallbackBoxTriangles(object.bounds));
    }

    final rendered = <_TriangleRender>[];
    for (final triangle in rawTriangles) {
      if (displayStyle == RenderSceneDisplayStyle.solid &&
          !_isTriangleVisible(triangle, projection)) {
        continue;
      }

      final a = projection.project(triangle[0]);
      final b = projection.project(triangle[1]);
      final c = projection.project(triangle[2]);

      final area = triangleArea(a.screen, b.screen, c.screen).abs();
      if (area < 0.25) {
        continue;
      }

      rendered.add(
        _TriangleRender(
          a: a.screen,
          b: b.screen,
          c: c.screen,
          depth: (a.depth + b.depth + c.depth) / 3.0,
          fillColor: _shadeTriangleColor(
            baseColor: fillColor,
            triangle: triangle,
          ),
          strokeColor: _shadeTriangleColor(
            baseColor: strokeColor,
            triangle: triangle,
            minShade: 0.82,
            maxShade: 1.0,
          ),
          strokeWidth: strokeWidth,
        ),
      );
    }
    rendered.sort((a, b) => b.depth.compareTo(a.depth));
    return rendered;
  }

  Color _shadeTriangleColor({
    required Color baseColor,
    required List<RenderScenePoint> triangle,
    double minShade = 0.72,
    double maxShade = 0.98,
  }) {
    if (triangle.length < 3 || projectionMode == RenderSceneProjectionMode.topDown) {
      return baseColor;
    }
    final normal = normalizePoint(crossPoint(triangle[1] - triangle[0], triangle[2] - triangle[0]));
    final lightDirection = normalizePoint(
      const RenderScenePoint(x: 0.35, y: -0.25, z: 0.9),
    );
    final lit = ((dotPoint(normal, lightDirection) + 1.0) * 0.5)
        .clamp(0.0, 1.0)
        .toDouble();
    final shade = minShade + (maxShade - minShade) * lit;
    return Color.fromARGB(
      (baseColor.a * 255.0).round().clamp(0, 255),
      (baseColor.r * shade * 255.0).round().clamp(0, 255),
      (baseColor.g * shade * 255.0).round().clamp(0, 255),
      (baseColor.b * shade * 255.0).round().clamp(0, 255),
    );
  }

  bool _isTriangleVisible(
    List<RenderScenePoint> triangle,
    RenderSceneProjection projection,
  ) {
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      return true;
    }
    if (triangle.length < 3) {
      return false;
    }

    final a = triangle[0];
    final b = triangle[1];
    final c = triangle[2];
    final normal = crossPoint(b - a, c - a);
    if (lengthPoint(normal) <= 1e-8) {
      return false;
    }

    final basis = buildCameraBasis(
      center: camera.center,
      yawRadians: camera.yawRadians,
      pitchRadians: camera.pitchRadians,
      distance: camera.distance,
    );
    final toEye = basis.eye - a;
    return dotPoint(normal, toEye) > 1e-8;
  }

  double _fillAlphaForObject({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (isSelected || isHighlighted) {
      return 0.84;
    }

    switch (kind) {
      case 'wall':
        return 1.0;
      case 'door':
      case 'window':
        return 0.96;
      case 'room':
        return 0.22;
      default:
        return 0.92;
    }
  }

  bool _shouldDrawSolidOutline({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      return true;
    }
    if (isSelected || isHighlighted) {
      return true;
    }
    switch (kind) {
      case 'wall':
      case 'door':
      case 'window':
        return false;
      default:
        return true;
    }
  }

  List<_OutlineSegment> _buildOutlineSegments(
    RenderSceneObject object,
    RenderSceneProjection projection,
  ) {
    final meshSegments = _buildVisibleMeshOutlineSegments(object, projection);
    if (meshSegments.isNotEmpty) {
      return meshSegments;
    }

    return _buildBoundsOutlineSegments(object.bounds, projection);
  }

  List<_OutlineSegment> _buildVisibleMeshOutlineSegments(
    RenderSceneObject object,
    RenderSceneProjection projection,
  ) {
    final positions = object.mesh.positions;
    final indices = object.mesh.indices;
    if (positions.isEmpty || indices.length < 3) {
      return const <_OutlineSegment>[];
    }

    final edgeMap = <String, List<_EdgeRecord>>{};
    for (var i = 0; i + 2 < indices.length; i += 3) {
      final ia = indices[i];
      final ib = indices[i + 1];
      final ic = indices[i + 2];
      final a = safeMeshPoint(positions, ia);
      final b = safeMeshPoint(positions, ib);
      final c = safeMeshPoint(positions, ic);
      if (a == null || b == null || c == null) {
        continue;
      }
      final triangle = <RenderScenePoint>[a, b, c];
      if (displayStyle == RenderSceneDisplayStyle.solid &&
          !_isTriangleVisible(triangle, projection)) {
        continue;
      }

      void addEdge(int startIndex, int endIndex, RenderScenePoint start,
          RenderScenePoint end) {
        final low = math.min(startIndex, endIndex);
        final high = math.max(startIndex, endIndex);
        final key = '$low:$high';
        edgeMap.putIfAbsent(key, () => <_EdgeRecord>[]).add(
              _EdgeRecord(start: start, end: end),
            );
      }

      addEdge(ia, ib, a, b);
      addEdge(ib, ic, b, c);
      addEdge(ic, ia, c, a);
    }

    final segments = <_OutlineSegment>[];
    for (final records in edgeMap.values) {
      if (records.isEmpty) {
        continue;
      }
      final first = records.first;
      if (records.length != 1) {
        continue;
      }
      segments.add(
        _OutlineSegment(
          a: projection.project(first.start).screen,
          b: projection.project(first.end).screen,
        ),
      );
    }
    return segments;
  }

  List<_OutlineSegment> _buildBoundsOutlineSegments(
    RenderSceneBounds bounds,
    RenderSceneProjection projection,
  ) {
    final corners = boundsCorners(bounds);
    final projected = corners.map(projection.project).toList(growable: false);
    const edgePairs = <List<int>>[
      <int>[0, 1],
      <int>[1, 2],
      <int>[2, 3],
      <int>[3, 0],
      <int>[4, 5],
      <int>[5, 6],
      <int>[6, 7],
      <int>[7, 4],
      <int>[0, 4],
      <int>[1, 5],
      <int>[2, 6],
      <int>[3, 7],
    ];

    return edgePairs
        .map(
          (pair) => _OutlineSegment(
            a: projected[pair[0]].screen,
            b: projected[pair[1]].screen,
          ),
        )
        .toList(growable: false);
  }

  void _drawDraftOverlay(Canvas canvas, RenderSceneProjection projection) {
    final wallStart = draftWallStart;
    final wallEnd = draftWallEnd;
    final opening = draftOpening;
    final surface = draftSurface;

    if (wallStart != null && wallEnd != null) {
      final wallLength = wallStart.distanceTo(wallEnd);
      if (wallLength > 1e-6) {
        final draftTriangles = _draftWallTriangles(wallStart, wallEnd);
        for (final triangle in draftTriangles) {
          final a = projection.project(triangle[0]).screen;
          final b = projection.project(triangle[1]).screen;
          final c = projection.project(triangle[2]).screen;
          final path = Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(c.dx, c.dy)
            ..close();
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.fill
              ..color = const Color(0xFFEF4444).withValues(alpha: 0.18),
          );
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = const Color(0xFFDC2626).withValues(alpha: 0.9),
          );
        }
      }

      final a = projection.project(wallStart).screen;
      final b = projection.project(wallEnd).screen;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFB91C1C)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(a, 5, Paint()..color = const Color(0xFFEF4444));
      canvas.drawCircle(b, 5, Paint()..color = const Color(0xFFEF4444));
    }

    if (surface != null) {
      final minX = math.min(surface.start.x, surface.end.x);
      final maxX = math.max(surface.start.x, surface.end.x);
      final minY = math.min(surface.start.y, surface.end.y);
      final maxY = math.max(surface.start.y, surface.end.y);
      final z = math.max(surface.start.z, surface.end.z);
      final corners = <RenderScenePoint>[
        RenderScenePoint(x: minX, y: minY, z: z),
        RenderScenePoint(x: maxX, y: minY, z: z),
        RenderScenePoint(x: maxX, y: maxY, z: z),
        RenderScenePoint(x: minX, y: maxY, z: z),
      ];
      final projected = corners
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final path = Path()
        ..moveTo(projected[0].dx, projected[0].dy)
        ..lineTo(projected[1].dx, projected[1].dy)
        ..lineTo(projected[2].dx, projected[2].dy)
        ..lineTo(projected[3].dx, projected[3].dy)
        ..close();
      final fillColor = surface.kind == 'ceiling'
          ? const Color(0xFF60A5FA).withValues(alpha: 0.18)
          : const Color(0xFF10B981).withValues(alpha: 0.18);
      final strokeColor = surface.kind == 'ceiling'
          ? const Color(0xFF2563EB)
          : const Color(0xFF059669);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = strokeColor,
      );
    }

    if (opening == null || opening.hostWallId == null) {
      return;
    }

    final host = scene.objectById(opening.hostWallId);
    if (host == null) {
      return;
    }

    final hostStart = RenderSceneEditor.wallStartPoint(host);
    final hostEnd = RenderSceneEditor.wallEndPoint(host);
    final wallThickness = RenderSceneEditor.wallThickness(host);
    if (hostStart == null || hostEnd == null || wallThickness == null) {
      return;
    }

    final axis = hostEnd - hostStart;
    final axisLength = hostStart.distanceTo(hostEnd);
    if (axisLength <= 1e-9) {
      return;
    }

    final axisUnit = axis.scale(1.0 / axisLength);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final halfWidth = opening.widthMeters * 0.5;
    final center = hostStart + axisUnit.scale(opening.offsetMeters);
    final startPoint = center - axisUnit.scale(halfWidth);
    final endPoint = center + axisUnit.scale(halfWidth);
    final halfThickness = wallThickness * 0.5;
    final upper = opening.sillHeightMeters + opening.heightMeters;

    final corners = <RenderScenePoint>[
      startPoint + normal.scale(halfThickness),
      endPoint + normal.scale(halfThickness),
      endPoint - normal.scale(halfThickness),
      startPoint - normal.scale(halfThickness),
      RenderScenePoint(
        x: startPoint.x + normal.x * halfThickness,
        y: startPoint.y + normal.y * halfThickness,
        z: upper,
      ),
      RenderScenePoint(
        x: endPoint.x + normal.x * halfThickness,
        y: endPoint.y + normal.y * halfThickness,
        z: upper,
      ),
      RenderScenePoint(
        x: endPoint.x - normal.x * halfThickness,
        y: endPoint.y - normal.y * halfThickness,
        z: upper,
      ),
      RenderScenePoint(
        x: startPoint.x - normal.x * halfThickness,
        y: startPoint.y - normal.y * halfThickness,
        z: upper,
      ),
    ];

    final projectedCorners = corners
        .map((point) => projection.project(point).screen)
        .toList(growable: false);
    final rect = Rect.fromPoints(projectedCorners.first, projectedCorners[2]);

    canvas.drawRect(
      rect,
      Paint()
        ..color = opening.valid
            ? const Color(0xFF22C55E).withValues(alpha: 0.24)
            : const Color(0xFFF59E0B).withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color =
            opening.valid ? const Color(0xFF16A34A) : const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final messagePainter = TextPainter(
      text: TextSpan(
        text: opening.message,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 160);
    messagePainter.paint(canvas, rect.topLeft + const Offset(4, -18));
  }

  List<List<RenderScenePoint>> _draftWallTriangles(
    RenderScenePoint start,
    RenderScenePoint end,
  ) {
    final axis = end - start;
    final length = start.distanceTo(end);
    if (length <= 1e-6) {
      return const <List<RenderScenePoint>>[];
    }

    final axisUnit = axis.scale(1.0 / length);
    final normal =
        RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0).scale(
      draftWallThicknessMeters * 0.5,
    );
    final lower0 = start + normal;
    final lower1 = end + normal;
    final lower2 = end - normal;
    final lower3 = start - normal;
    final upper0 =
        RenderScenePoint(x: lower0.x, y: lower0.y, z: draftWallHeightMeters);
    final upper1 =
        RenderScenePoint(x: lower1.x, y: lower1.y, z: draftWallHeightMeters);
    final upper2 =
        RenderScenePoint(x: lower2.x, y: lower2.y, z: draftWallHeightMeters);
    final upper3 =
        RenderScenePoint(x: lower3.x, y: lower3.y, z: draftWallHeightMeters);

    return <List<RenderScenePoint>>[
      <RenderScenePoint>[lower0, lower2, lower1],
      <RenderScenePoint>[lower0, lower3, lower2],
      <RenderScenePoint>[upper0, upper1, upper2],
      <RenderScenePoint>[upper0, upper2, upper3],
      <RenderScenePoint>[lower0, lower1, upper1],
      <RenderScenePoint>[lower0, upper1, upper0],
      <RenderScenePoint>[lower1, lower2, upper2],
      <RenderScenePoint>[lower1, upper2, upper1],
      <RenderScenePoint>[lower2, lower3, upper3],
      <RenderScenePoint>[lower2, upper3, upper2],
      <RenderScenePoint>[lower3, lower0, upper0],
      <RenderScenePoint>[lower3, upper0, upper3],
    ];
  }

  void _drawLabels(
    Canvas canvas,
    RenderSceneProjection projection,
    List<RenderSceneObject> objects,
  ) {
    if (objects.length > 220) {
      return;
    }

    for (final object in objects) {
      final elementId = object.elementId?.toString();
      final isSelected =
          elementId == selectedElementId && selectedElementId != null;
      final isHighlighted =
          elementId == highlightedElementId && highlightedElementId != null;
      if (!isSelected && !isHighlighted && objects.length > 80) {
        continue;
      }

      final projected = projection.project(object.bounds.max);
      final label = '${prettySceneKind(object.kind)} ${object.elementId ?? ''}';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: isSelected || isHighlighted
                ? const Color(0xFF111827)
                : const Color(0xFF374151),
            fontSize: isSelected || isHighlighted ? 11 : 9,
            fontWeight:
                isSelected || isHighlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 160);
      painter.paint(canvas, projected.screen + const Offset(5, -16));
    }
  }

  void _drawGrid(Canvas canvas, RenderSceneProjection projection) {
    final bounds = scene.bounds;
    final width = math.max(bounds.width, 0.001);
    final depth = math.max(bounds.depth, 0.001);
    final maxExtent = math.max(width, depth);

    final spacing = _niceGridSpacing(maxExtent);
    final minX = (bounds.min.x / spacing).floor() * spacing;
    final maxX = (bounds.max.x / spacing).ceil() * spacing;
    final minY = (bounds.min.y / spacing).floor() * spacing;
    final maxY = (bounds.max.y / spacing).ceil() * spacing;

    final paint = Paint()
      ..color = const Color(0xFFD1D5DB).withValues(alpha: 0.75)
      ..strokeWidth = 0.7;

    for (var x = minX; x <= maxX; x += spacing) {
      final a = projection.project(RenderScenePoint(x: x, y: minY, z: 0));
      final b = projection.project(RenderScenePoint(x: x, y: maxY, z: 0));
      canvas.drawLine(a.screen, b.screen, paint);
    }

    for (var y = minY; y <= maxY; y += spacing) {
      final a = projection.project(RenderScenePoint(x: minX, y: y, z: 0));
      final b = projection.project(RenderScenePoint(x: maxX, y: y, z: 0));
      canvas.drawLine(a.screen, b.screen, paint);
    }
  }

  void _drawAxes(Canvas canvas, RenderSceneProjection projection) {
    final origin = projection.project(const RenderScenePoint(x: 0, y: 0, z: 0));
    final xAxis = projection.project(const RenderScenePoint(x: 1, y: 0, z: 0));
    final yAxis = projection.project(const RenderScenePoint(x: 0, y: 1, z: 0));
    final zAxis = projection.project(const RenderScenePoint(x: 0, y: 0, z: 1));

    canvas.drawLine(
      origin.screen,
      xAxis.screen,
      Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      origin.screen,
      yAxis.screen,
      Paint()
        ..color = const Color(0xFF16A34A)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      origin.screen,
      zAxis.screen,
      Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2,
    );
  }

  double _niceGridSpacing(double maxExtent) {
    if (maxExtent <= 10) return 1;
    if (maxExtent <= 30) return 2;
    if (maxExtent <= 80) return 5;
    if (maxExtent <= 180) return 10;
    if (maxExtent <= 400) return 20;
    return 50;
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'wall':
        return const Color(0xFFF7F7F2);
      case 'door':
        return const Color(0xFFB08968);
      case 'window':
        return const Color(0xFF96C6FF);
      case 'slab':
      case 'floor':
        return const Color(0xFFE5E7EB);
      case 'ceiling':
        return const Color(0xFFF8FAFC);
      case 'roof':
        return const Color(0xFFD6C1A3);
      case 'column':
        return const Color(0xFFE7E5E4);
      case 'beam':
        return const Color(0xFFD6D3D1);
      case 'stair':
        return const Color(0xFFE9D5FF);
      case 'room':
        return const Color(0xFFD1FAE5);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  @override
  bool shouldRepaint(covariant FallbackRenderScenePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.visibleKinds != visibleKinds ||
        oldDelegate.selectedElementId != selectedElementId ||
        oldDelegate.highlightedElementId != highlightedElementId ||
        oldDelegate.projectionMode != projectionMode ||
        oldDelegate.orbitProjectionStyle != orbitProjectionStyle ||
        oldDelegate.displayStyle != displayStyle ||
        oldDelegate.camera != camera ||
        oldDelegate.planCamera != planCamera ||
        oldDelegate.draftWallStart != draftWallStart ||
        oldDelegate.draftWallEnd != draftWallEnd ||
        oldDelegate.draftOpening != draftOpening ||
        oldDelegate.draftSurface != draftSurface ||
        oldDelegate.draftWallThicknessMeters != draftWallThicknessMeters ||
        oldDelegate.draftWallHeightMeters != draftWallHeightMeters;
  }
}

class _RenderPacket {
  const _RenderPacket({
    required this.triangles,
    required this.outlines,
    required this.outlineColor,
    required this.outlineStrokeWidth,
  });

  final List<_TriangleRender> triangles;
  final List<_OutlineSegment> outlines;
  final Color outlineColor;
  final double outlineStrokeWidth;

  double get depth {
    if (triangles.isEmpty) {
      return double.negativeInfinity;
    }
    return triangles.fold<double>(
          0,
          (sum, triangle) => sum + triangle.depth,
        ) /
        triangles.length;
  }
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

  final Offset a;
  final Offset b;
  final Offset c;
  final double depth;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
}

class _OutlineSegment {
  const _OutlineSegment({
    required this.a,
    required this.b,
  });

  final Offset a;
  final Offset b;
}

class _EdgeRecord {
  const _EdgeRecord({
    required this.start,
    required this.end,
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
}
