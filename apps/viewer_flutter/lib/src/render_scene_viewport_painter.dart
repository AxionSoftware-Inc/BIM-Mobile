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

    final triangles = <_TriangleRender>[];
    final outlines = <_ObjectOutline>[];
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

      triangles.addAll(
        _buildObjectTriangles(
          object: object,
          projection: projection,
          fillColor: objectColor.withValues(alpha: fillAlpha),
          strokeColor: objectColor.withValues(alpha: 0.96),
          strokeWidth: strokeWidth,
        ),
      );

      if (displayStyle == RenderSceneDisplayStyle.solid) {
        outlines.add(
          _ObjectOutline(
            segments: _buildOutlineSegments(object, projection),
            color: isSelected || isHighlighted
                ? objectColor.withValues(alpha: 0.95)
                : const Color(0xFF475569).withValues(alpha: 0.40),
            strokeWidth: isSelected ? 2.0 : (isHighlighted ? 1.6 : 1.0),
          ),
        );
      }
    }

    triangles.sort((a, b) => b.depth.compareTo(a.depth));

    for (final triangle in triangles) {
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
      for (final outline in outlines) {
        for (final segment in outline.segments) {
          canvas.drawLine(
            segment.a,
            segment.b,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outline.strokeWidth
              ..color = outline.color,
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
    final wallTriangles = _buildWallTrianglesWithOpenings(object);
    if (wallTriangles != null) {
      rawTriangles.addAll(wallTriangles);
    } else {
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
    }

    if (rawTriangles.isEmpty) {
      rawTriangles.addAll(fallbackBoxTriangles(object.bounds));
    }

    final rendered = <_TriangleRender>[];
    for (final triangle in rawTriangles) {
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
          fillColor: fillColor,
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
        ),
      );
    }
    return rendered;
  }

  List<List<RenderScenePoint>>? _buildWallTrianglesWithOpenings(
    RenderSceneObject wall,
  ) {
    if (wall.kindKey != 'wall') {
      return null;
    }

    final wallStart = RenderSceneEditor.wallStartPoint(wall);
    final wallEnd = RenderSceneEditor.wallEndPoint(wall);
    final wallThickness = RenderSceneEditor.wallThickness(wall);
    final wallHeight =
        _toDouble(wall.metadata['height_meters'] ?? wall.bounds.height) ??
            wall.bounds.height;
    if (wallStart == null ||
        wallEnd == null ||
        wallThickness == null ||
        wallHeight <= 1e-6) {
      return null;
    }

    final axis = wallEnd - wallStart;
    final length = wallStart.distanceTo(wallEnd);
    if (length <= 1e-6) {
      return null;
    }

    final openings = _openingSpecsForWall(wall.elementId);
    if (openings.isEmpty) {
      return null;
    }

    final axisUnit = axis.scale(1.0 / length);
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0);
    final baseZ = math.min(wallStart.z, wallEnd.z);
    final halfThickness = wallThickness * 0.5;

    final xBreaks = <double>[0, length];
    final zBreaks = <double>[0, wallHeight];

    for (final opening in openings) {
      xBreaks.add(opening.startOffset);
      xBreaks.add(opening.endOffset);
      zBreaks.add(opening.bottomZ);
      zBreaks.add(opening.topZ);
    }

    final xs = _sortedUniqueBreaks(xBreaks);
    final zs = _sortedUniqueBreaks(zBreaks);
    final triangles = <List<RenderScenePoint>>[];

    for (var xi = 0; xi + 1 < xs.length; xi += 1) {
      final x0 = xs[xi];
      final x1 = xs[xi + 1];
      if (x1 - x0 <= 1e-6) {
        continue;
      }

      for (var zi = 0; zi + 1 < zs.length; zi += 1) {
        final z0 = zs[zi];
        final z1 = zs[zi + 1];
        if (z1 - z0 <= 1e-6) {
          continue;
        }

        final cellCenterX = (x0 + x1) * 0.5;
        final cellCenterZ = (z0 + z1) * 0.5;
        final blocked = openings.any(
          (opening) =>
              cellCenterX > opening.startOffset + 1e-6 &&
              cellCenterX < opening.endOffset - 1e-6 &&
              cellCenterZ > opening.bottomZ + 1e-6 &&
              cellCenterZ < opening.topZ - 1e-6,
        );
        if (blocked) {
          continue;
        }

        _appendBoxTriangles(
          triangles: triangles,
          cornerBuilder: (double localX, double localY, double localZ) {
            return RenderScenePoint(
              x: wallStart.x + axisUnit.x * localX + normal.x * localY,
              y: wallStart.y + axisUnit.y * localX + normal.y * localY,
              z: baseZ + localZ,
            );
          },
          x0: x0,
          x1: x1,
          y0: -halfThickness,
          y1: halfThickness,
          z0: z0,
          z1: z1,
        );
      }
    }

    return triangles;
  }

  double _fillAlphaForObject({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (isSelected || isHighlighted) {
      return 0.62;
    }

    switch (kind) {
      case 'door':
      case 'window':
        return 0.08;
      case 'room':
        return 0.22;
      default:
        return 0.82;
    }
  }

  List<_OutlineSegment> _buildOutlineSegments(
    RenderSceneObject object,
    RenderSceneProjection projection,
  ) {
    final corners = boundsCorners(object.bounds);
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

  List<_WallOpeningSpec> _openingSpecsForWall(int? wallElementId) {
    if (wallElementId == null) {
      return const <_WallOpeningSpec>[];
    }

    final specs = <_WallOpeningSpec>[];
    for (final object in scene.objects) {
      if (object.kindKey != 'door' && object.kindKey != 'window') {
        continue;
      }

      final hostId = _toInt(object.metadata['host_wall_id']);
      if (hostId != wallElementId) {
        continue;
      }

      final offset = _toDouble(object.metadata['offset_meters']);
      final width = _toDouble(object.metadata['width_meters']);
      final height = _toDouble(object.metadata['height_meters']);
      final sill = _toDouble(object.metadata['sill_height_meters']) ?? 0.0;
      if (offset == null || width == null || height == null) {
        continue;
      }

      specs.add(
        _WallOpeningSpec(
          startOffset: math.max(0, offset - width * 0.5),
          endOffset: math.max(0, offset + width * 0.5),
          bottomZ: math.max(0, sill),
          topZ: math.max(0, sill + height),
        ),
      );
    }

    return specs;
  }

  List<double> _sortedUniqueBreaks(List<double> values) {
    final sorted = values.where((value) => value.isFinite).toList()..sort();
    final unique = <double>[];
    for (final value in sorted) {
      if (unique.isEmpty || (value - unique.last).abs() > 1e-6) {
        unique.add(value);
      }
    }
    return unique;
  }

  void _appendBoxTriangles({
    required List<List<RenderScenePoint>> triangles,
    required RenderScenePoint Function(double x, double y, double z)
        cornerBuilder,
    required double x0,
    required double x1,
    required double y0,
    required double y1,
    required double z0,
    required double z1,
  }) {
    final corners = <RenderScenePoint>[
      cornerBuilder(x0, y0, z0),
      cornerBuilder(x1, y0, z0),
      cornerBuilder(x1, y1, z0),
      cornerBuilder(x0, y1, z0),
      cornerBuilder(x0, y0, z1),
      cornerBuilder(x1, y0, z1),
      cornerBuilder(x1, y1, z1),
      cornerBuilder(x0, y1, z1),
    ];

    triangles.addAll(<List<RenderScenePoint>>[
      <RenderScenePoint>[corners[0], corners[1], corners[2]],
      <RenderScenePoint>[corners[0], corners[2], corners[3]],
      <RenderScenePoint>[corners[4], corners[6], corners[5]],
      <RenderScenePoint>[corners[4], corners[7], corners[6]],
      <RenderScenePoint>[corners[0], corners[5], corners[1]],
      <RenderScenePoint>[corners[0], corners[4], corners[5]],
      <RenderScenePoint>[corners[1], corners[6], corners[2]],
      <RenderScenePoint>[corners[1], corners[5], corners[6]],
      <RenderScenePoint>[corners[2], corners[7], corners[3]],
      <RenderScenePoint>[corners[2], corners[6], corners[7]],
      <RenderScenePoint>[corners[3], corners[4], corners[0]],
      <RenderScenePoint>[corners[3], corners[7], corners[4]],
    ]);
  }

  void _drawDraftOverlay(Canvas canvas, RenderSceneProjection projection) {
    final wallStart = draftWallStart;
    final wallEnd = draftWallEnd;
    final opening = draftOpening;

    if (wallStart != null && wallEnd != null) {
      final a = projection.project(wallStart).screen;
      final b = projection.project(wallEnd).screen;
      final paint = Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, paint);
      canvas.drawCircle(a, 5, Paint()..color = const Color(0xFFEF4444));
      canvas.drawCircle(b, 5, Paint()..color = const Color(0xFFEF4444));
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

  double? _toDouble(Object? value) {
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return null;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
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
        oldDelegate.draftOpening != draftOpening;
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

class _ObjectOutline {
  const _ObjectOutline({
    required this.segments,
    required this.color,
    required this.strokeWidth,
  });

  final List<_OutlineSegment> segments;
  final Color color;
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

class _WallOpeningSpec {
  const _WallOpeningSpec({
    required this.startOffset,
    required this.endOffset,
    required this.bottomZ,
    required this.topZ,
  });

  final double startOffset;
  final double endOffset;
  final double bottomZ;
  final double topZ;
}
