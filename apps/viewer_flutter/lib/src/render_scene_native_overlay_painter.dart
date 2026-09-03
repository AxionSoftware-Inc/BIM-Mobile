import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'render_scene_editor.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'tools/wall_authoring_geometry.dart';

class NativeDraftOverlayPainter extends CustomPainter {
  NativeDraftOverlayPainter({
    required this.scene,
    required this.projectionMode,
    required this.interactionMode,
    required this.orbitProjectionStyle,
    required this.camera,
    required this.planCamera,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftOpening,
    required this.draftSurface,
    required this.pickedWallIds,
    required this.wallThicknessMeters,
    required this.activeElementId,
    required this.selectedLevelId,
    this.draftWallEditElementId,
  });

  final RenderScene scene;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneInteractionMode interactionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneCameraState camera;
  final RenderScenePlanCameraState planCamera;
  final RenderScenePoint? draftWallStart;
  final RenderScenePoint? draftWallEnd;
  final RenderSceneOpeningDraft? draftOpening;
  final RenderSceneSurfaceDraft? draftSurface;
  final Set<int> pickedWallIds;
  final double wallThicknessMeters;
  final String? activeElementId;
  final int? selectedLevelId;
  final int? draftWallEditElementId;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final projection = RenderSceneProjection(
      sceneBounds: scene.bounds,
      canvasSize: size,
      projectionMode: projectionMode,
      orbitProjectionStyle: orbitProjectionStyle,
      planCamera: planCamera,
      camera: camera,
      padding: 48.0,
    );

    if (projectionMode == RenderSceneProjectionMode.topDown) {
      _drawZoomedOutPlanWallGuides(canvas, projection);
    }

    // The Android model is a platform view, so the regular fallback painter
    // is not above it. Keep the same two endpoint handles in this lightweight
    // overlay; selection and drag feedback therefore remain visible on the
    // real tablet renderer as well.
    if (projectionMode.supportsPlanFootprintEditing &&
        activeElementId != null) {
      final selected = scene.objectByStableId(activeElementId!);
      if (selected != null && selected.kindKey == 'wall') {
        final start = RenderSceneEditor.wallStartPoint(selected);
        final end = RenderSceneEditor.wallEndPoint(selected);
        if (start != null && end != null) {
          final fill = Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0xFFFFFFFF);
          final stroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = const Color(0xFF2563EB);
          for (final point in <RenderScenePoint>[start, end]) {
            final screen = projection.project(point).screen;
            canvas.drawCircle(screen, 7.0, fill);
            canvas.drawCircle(screen, 7.0, stroke);
          }
        }
      }
    }

    final surface = draftSurface;
    if (surface != null && surface.points.length >= 2) {
      final points = surface.points
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final isBoundarySketch = surface.boundarySketch;
      final strokeColor = isBoundarySketch
          ? const Color(0xFFE11D72)
          : const Color(0xFF2563EB).withValues(alpha: 0.9);
      final fillColor = isBoundarySketch
          ? const Color(0xFFFFD1E4).withValues(alpha: 0.28)
          : const Color(0xFF2563EB).withValues(alpha: 0.10);
      final committedCount = (surface.committedPointCount ?? points.length)
          .clamp(0, points.length);
      final committed = points.take(committedCount).toList(growable: false);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (surface.closed && points.length >= 3) path.close();
      if (surface.closed && points.length >= 3) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = fillColor,
        );
      }
      if (isBoundarySketch && !surface.closed && committed.length >= 2) {
        final committedPath = Path()
          ..moveTo(committed.first.dx, committed.first.dy);
        for (final point in committed.skip(1)) {
          committedPath.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(
          committedPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor,
        );
        if (points.length > committed.length) {
          canvas.drawLine(
            committed.last,
            points.last,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0
              ..strokeCap = StrokeCap.round
              ..color = strokeColor.withValues(alpha: 0.62),
          );
        }
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isBoundarySketch ? 3.0 : 2.2
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor,
        );
      }
      for (var index = 0; index < points.length; index += 1) {
        final point = points[index];
        if (isBoundarySketch && index >= committedCount) {
          canvas.drawCircle(
            point,
            8.0,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = strokeColor.withValues(alpha: 0.75),
          );
          canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
          canvas.drawCircle(
            point,
            4.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = strokeColor,
          );
        } else {
          canvas.drawCircle(
            point,
            isBoundarySketch ? 5.5 : 4.5,
            Paint()..color = strokeColor,
          );
        }
      }
      if (isBoundarySketch && !surface.closed && points.length >= 3) {
        canvas.drawCircle(
          points.first,
          10.0,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = strokeColor.withValues(alpha: 0.58),
        );
      }
    }

    // Keep each picked wall visible independently. This is important before
    // a closed footprint exists, and makes an accidental repeated pick clear.
    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          wall.elementId == null ||
          !pickedWallIds.contains(wall.elementId)) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      final thickness = RenderSceneEditor.wallThickness(wall);
      if (start == null || end == null || thickness == null) continue;
      _drawWallBand(
        canvas,
        projection,
        start,
        end,
        thickness,
        fillColor: const Color(0xFF2563EB).withValues(alpha: 0.34),
        strokeColor: const Color(0xFF1D4ED8),
        strokeWidth: 3.0,
      );
    }

    final opening = draftOpening;
    if (opening != null && opening.hostWallId != null) {
      final host = scene.objectById(opening.hostWallId);
      final start =
          host == null ? null : RenderSceneEditor.wallStartPoint(host);
      final end = host == null ? null : RenderSceneEditor.wallEndPoint(host);
      final thickness =
          host == null ? null : RenderSceneEditor.wallThickness(host);
      if (start != null && end != null && thickness != null) {
        final axis = end - start;
        final length = axis.distanceTo(RenderScenePoint.zero());
        if (length > 1e-8) {
          final axisUnit = axis.scale(1.0 / length);
          final normal = RenderScenePoint(
            x: -axisUnit.y,
            y: axisUnit.x,
            z: 0,
          );
          final center = start + axisUnit.scale(opening.offsetMeters);
          final halfWidth = opening.widthMeters * 0.5;
          final first = center - axisUnit.scale(halfWidth);
          final second = center + axisUnit.scale(halfWidth);
          final halfThickness = thickness * 0.5;
          final corners = <RenderScenePoint>[
            first + normal.scale(halfThickness),
            second + normal.scale(halfThickness),
            second - normal.scale(halfThickness),
            first - normal.scale(halfThickness),
          ].map((point) => projection.project(point).screen).toList();
          final cutPath = Path()
            ..moveTo(corners[0].dx, corners[0].dy)
            ..lineTo(corners[1].dx, corners[1].dy)
            ..lineTo(corners[2].dx, corners[2].dy)
            ..lineTo(corners[3].dx, corners[3].dy)
            ..close();
          canvas.drawPath(
            cutPath,
            Paint()
              ..style = PaintingStyle.fill
              ..color = const Color(0xFFF5F8F6),
          );
          final p0 = projection.project(first).screen;
          final p1 = projection.project(second).screen;
          final pc = projection.project(center).screen;
          final openEnd = projection
              .project(first + normal.scale(opening.widthMeters))
              .screen;
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.square
            ..color = opening.valid
                ? const Color(0xFF2563EB)
                : const Color(0xFFD97706);
          canvas.drawLine(p0, p1, paint);
          if (opening.kind.toLowerCase() == 'window') {
            final leftOpen =
                projection.project(first + normal.scale(halfWidth)).screen;
            final rightOpen =
                projection.project(second + normal.scale(halfWidth)).screen;
            canvas.drawLine(p0, leftOpen, paint);
            canvas.drawLine(p1, rightOpen, paint);
          } else {
            canvas.drawLine(p0, openEnd, paint);
            final radius = (p1 - p0).distance;
            if (radius > 1.0) {
              final startAngle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
              final endAngle =
                  math.atan2(openEnd.dy - p0.dy, openEnd.dx - p0.dx);
              var sweep = endAngle - startAngle;
              while (sweep > math.pi) {
                sweep -= math.pi * 2;
              }
              while (sweep < -math.pi) {
                sweep += math.pi * 2;
              }
              canvas.drawArc(
                Rect.fromCircle(center: p0, radius: radius),
                startAngle,
                sweep,
                false,
                paint,
              );
            }
          }
          canvas.drawCircle(pc, 3.0, Paint()..color = paint.color);
        }
      }
    }

    final start = draftWallStart;
    final end = draftWallEnd;
    if (start == null || end == null || start.distanceTo(end) <= 1e-6) {
      return;
    }
    _drawWallBand(
      canvas,
      projection,
      start,
      end,
      wallThicknessMeters,
      fillColor: const Color(0xFF0EA5E9).withValues(alpha: 0.28),
      strokeColor: const Color(0xFF0284C7),
      strokeWidth: 2.6,
    );
    final a = projection.project(start).screen;
    final b = projection.project(end).screen;
    final endpointPaint = Paint()..color = const Color(0xFF0369A1);
    canvas.drawCircle(a, 5.5, endpointPaint);
    canvas.drawCircle(b, 5.5, endpointPaint);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = const Color(0xFFE0F2FE)
        ..strokeWidth = 1.4,
    );
    _drawWallLengthLabel(
      canvas,
      Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5),
      WallAuthoringGeometry.formatWallLengthMeters(start.distanceTo(end)),
    );
    if (projectionMode == RenderSceneProjectionMode.topDown &&
        (interactionMode == RenderSceneInteractionMode.addWall ||
            draftWallEditElementId != null)) {
      _drawDraftWallAngle(
        canvas,
        projection,
        start,
        end,
        excludeWallId: draftWallEditElementId,
        levelId: selectedLevelId,
      );
    }
  }

  void _drawDraftWallAngle(
    Canvas canvas,
    RenderSceneProjection projection,
    RenderScenePoint start,
    RenderScenePoint end, {
    required int? excludeWallId,
    required int? levelId,
  }) {
    final preview = WallAuthoringGeometry.findDraftAngle(
      scene: scene,
      start: start,
      end: end,
      excludeWallId: excludeWallId,
      levelId: levelId,
    );
    if (preview == null) return;

    final vertex = projection.project(preview.vertex).screen;
    final wallPoint = projection.project(preview.wallPoint).screen;
    final referencePoint = projection.project(preview.referencePoint).screen;
    final firstAngle = math.atan2(
      wallPoint.dy - vertex.dy,
      wallPoint.dx - vertex.dx,
    );
    final secondAngle = math.atan2(
      referencePoint.dy - vertex.dy,
      referencePoint.dx - vertex.dx,
    );
    var sweep = secondAngle - firstAngle;
    while (sweep > math.pi) {
      sweep -= math.pi * 2;
    }
    while (sweep < -math.pi) {
      sweep += math.pi * 2;
    }
    if (sweep.abs() < 0.04 || sweep.abs() > math.pi - 0.04) return;

    const radius = 25.0;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF7C3AED);
    canvas.drawArc(
      Rect.fromCircle(center: vertex, radius: radius),
      firstAngle,
      sweep,
      false,
      arcPaint,
    );

    final midpointAngle = firstAngle + sweep * 0.5;
    final labelCenter = vertex +
        Offset(
              math.cos(midpointAngle),
              math.sin(midpointAngle),
            ) *
            (radius + 13);
    final painter = TextPainter(
      text: TextSpan(
        text: '${preview.degrees.round()}°',
        style: const TextStyle(
          color: Color(0xFF4C1D95),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: labelCenter,
      width: painter.width + 12,
      height: painter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = const Color(0xFFF5F3FF).withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFFC4B5FD),
    );
    painter.paint(canvas, rect.topLeft + const Offset(6, 4));
  }

  void _drawWallLengthLabel(Canvas canvas, Offset midpoint, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final rect = Rect.fromCenter(
      center: midpoint + const Offset(0, -22),
      width: painter.width + 16,
      height: painter.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = const Color(0xFFF8FAFC).withValues(alpha: 0.96),
    );
    painter.paint(canvas, rect.topLeft + const Offset(8, 5));
  }

  void _drawZoomedOutPlanWallGuides(
    Canvas canvas,
    RenderSceneProjection projection,
  ) {
    // Filament's world-space edge prisms become sub-pixel at wide plan zooms.
    // Keep this as a lightweight screen-space fallback instead of rebuilding
    // native geometry during pinch updates. It is deliberately only enabled
    // once the wall itself is thin enough that the native edge is unreliable.
    final guidePath = Path();
    var hasGuide = false;
    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          (selectedLevelId != null &&
              wall.levelId != null &&
              wall.levelId != selectedLevelId)) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      final thickness = RenderSceneEditor.wallThickness(wall);
      if (start == null || end == null || thickness == null) continue;

      final delta = end - start;
      final length = math.sqrt(delta.x * delta.x + delta.y * delta.y);
      if (length <= 1e-6) continue;
      final normal = RenderScenePoint(
        x: -delta.y / length,
        y: delta.x / length,
        z: 0,
      ).scale(thickness.abs() * 0.5);
      final corners = <RenderScenePoint>[
        start + normal,
        end + normal,
        end - normal,
        start - normal,
      ];
      final points = corners
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final screenThickness = math.min(
        (points[0] - points[3]).distance,
        (points[1] - points[2]).distance,
      );
      if (screenThickness > 6.0) continue;

      guidePath
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy)
        ..lineTo(points[3].dx, points[3].dy)
        ..close();
      hasGuide = true;
    }
    if (!hasGuide) return;
    canvas.drawPath(
      guidePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter
        ..isAntiAlias = true
        ..color = const Color(0xCC374151),
    );
  }

  void _drawWallBand(
    Canvas canvas,
    RenderSceneProjection projection,
    RenderScenePoint start,
    RenderScenePoint end,
    double thickness, {
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
  }) {
    final delta = end - start;
    final length = math.sqrt(delta.x * delta.x + delta.y * delta.y);
    if (length <= 1e-6) return;
    final normal = RenderScenePoint(
      x: -delta.y / length,
      y: delta.x / length,
      z: 0,
    ).scale(thickness.abs() * 0.5);
    final corners = <RenderScenePoint>[
      start + normal,
      end + normal,
      end - normal,
      start - normal,
    ];
    final points = corners
        .map((point) => projection.project(point).screen)
        .toList(growable: false);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
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
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor,
    );
  }

  @override
  bool shouldRepaint(covariant NativeDraftOverlayPainter oldDelegate) => true;
}
