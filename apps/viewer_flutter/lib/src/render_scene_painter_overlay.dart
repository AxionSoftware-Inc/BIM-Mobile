part of 'render_scene_viewport_painter.dart';

mixin _FallbackSceneOverlayMixin {
  RenderScene get scene;
  Set<String> get selectedElementIds;
  String? get activeElementId;
  int? get selectedLevelId;
  String? get highlightedElementId;
  RenderSceneProjectionMode get projectionMode;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle;
  RenderSceneDisplayStyle get displayStyle;
  RenderSceneOpeningDraft? get draftOpening;
  RenderSceneSurfaceDraft? get draftSurface;
  RenderScenePoint? get draftWallStart;
  RenderScenePoint? get draftWallEnd;
  double get draftWallThicknessMeters;
  double get draftWallHeightMeters;

  void _drawDraftOverlay(Canvas canvas, RenderSceneProjection projection) {
    final wallStart = draftWallStart;
    final wallEnd = draftWallEnd;
    final opening = draftOpening;
    final surface = draftSurface;

    if (wallStart != null && wallEnd != null) {
      final wallLength = wallStart.distanceTo(wallEnd);
      if (wallLength > 1e-6 && projectionMode.supportsPlanFootprintEditing) {
        // Filled wall draft is intentionally plan-only. Elevation views reuse the
        // same planar projection pipeline, but wall creation preview there is a
        // line/elevation workflow rather than a thick footprint preview.
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
      final projected = surface.points
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      if (projected.length >= 2) {
        final path = Path()..moveTo(projected[0].dx, projected[0].dy);
        for (var index = 1; index < projected.length; index += 1) {
          path.lineTo(projected[index].dx, projected[index].dy);
        }
        if (surface.closed && projected.length >= 3) {
          path.close();
        }
        final fillColor = switch (surface.kind) {
          'ceiling' => const Color(0xFF60A5FA).withValues(alpha: 0.18),
          'roof' => const Color(0xFFF59E0B).withValues(alpha: 0.18),
          _ => const Color(0xFF10B981).withValues(alpha: 0.18),
        };
        final strokeColor = switch (surface.kind) {
          'ceiling' => const Color(0xFF2563EB),
          'roof' => const Color(0xFFD97706),
          _ => const Color(0xFF059669),
        };
        if (surface.closed && projected.length >= 3) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.fill
              ..color = fillColor,
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = strokeColor,
        );
        for (final point in projected) {
          canvas.drawCircle(point, 4.5, Paint()..color = strokeColor);
        }

        // A roof direction/ridge preview is defined for the whole boundary.
        // Keep every picked/polyline point connected to the common centre so
        // concave and six-point footprints do not leave half of the roof
        // guidance missing.
        if (surface.kind == 'roof' && projected.length >= 3) {
          final center = Offset(
            projected.fold<double>(0.0, (sum, point) => sum + point.dx) /
                projected.length,
            projected.fold<double>(0.0, (sum, point) => sum + point.dy) /
                projected.length,
          );
          final directionPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = strokeColor.withValues(alpha: 0.9);
          for (final point in projected) {
            canvas.drawLine(point, center, directionPaint);
          }
          canvas.drawCircle(center, 4.0, Paint()..color = strokeColor);
        }
      }
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
    final normal = RenderScenePoint(x: -axisUnit.y, y: axisUnit.x, z: 0).scale(
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
          elementId != null && selectedElementIds.contains(elementId);
      final isHighlighted =
          elementId == highlightedElementId && highlightedElementId != null;
      if (!isSelected && !isHighlighted && objects.length > 80) {
        continue;
      }

      final anchor = projectionMode.useBoundsCenterLabelAnchor
          ? object.bounds.center
          : object.bounds.max;
      final projected = projection.project(anchor);
      final label = '${prettySceneKind(object.kind)} ${object.elementId ?? ''}';
      if (projectionMode.isElevation && !isSelected && !isHighlighted) {
        continue;
      }
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
    if (!projectionMode.showGrid) {
      return;
    }
    final bounds = scene.bounds;
    final descriptor = projectionMode.planarDescriptor;
    final primaryExtent = descriptor != null
        ? math.max(descriptor.boundsWidth(bounds), 0.001)
        : math.max(bounds.width, 0.001);
    final secondaryExtent = descriptor != null
        ? math.max(descriptor.boundsHeight(bounds), 0.001)
        : math.max(bounds.depth, 0.001);
    final maxExtent = math.max(primaryExtent, secondaryExtent);

    final spacing = _niceGridSpacing(maxExtent);

    final paint = Paint()
      ..color = const Color(0xFFD1D5DB)
          .withValues(alpha: projectionMode.isElevation ? 0.42 : 0.75)
      ..strokeWidth = 0.7;

    if (descriptor == null) {
      return;
    }

    final minHorizontal =
        (descriptor.minAxis(bounds, descriptor.horizontalAxis) / spacing)
                .floor() *
            spacing;
    final maxHorizontal =
        (descriptor.maxAxis(bounds, descriptor.horizontalAxis) / spacing)
                .ceil() *
            spacing;
    final minVertical =
        (descriptor.minAxis(bounds, descriptor.verticalAxis) / spacing)
                .floor() *
            spacing;
    final maxVertical =
        (descriptor.maxAxis(bounds, descriptor.verticalAxis) / spacing).ceil() *
            spacing;

    for (var h = minHorizontal; h <= maxHorizontal; h += spacing) {
      final a = projection.project(
        descriptor.pointOnPlane(
          bounds: bounds,
          horizontalValue: h,
          verticalValue: minVertical,
        ),
      );
      final b = projection.project(
        descriptor.pointOnPlane(
          bounds: bounds,
          horizontalValue: h,
          verticalValue: maxVertical,
        ),
      );
      canvas.drawLine(a.screen, b.screen, paint);
    }
    for (var v = minVertical; v <= maxVertical; v += spacing) {
      final a = projection.project(
        descriptor.pointOnPlane(
          bounds: bounds,
          horizontalValue: minHorizontal,
          verticalValue: v,
        ),
      );
      final b = projection.project(
        descriptor.pointOnPlane(
          bounds: bounds,
          horizontalValue: maxHorizontal,
          verticalValue: v,
        ),
      );
      canvas.drawLine(a.screen, b.screen, paint);
    }
  }

  void _drawSelectedWallHandles(
    Canvas canvas,
    RenderSceneProjection projection,
  ) {
    if (!projectionMode.supportsPlanFootprintEditing ||
        activeElementId == null) {
      return;
    }
    // Endpoint handles remain plan-only on purpose. The projection/navigation
    // math is unified across planar views, but handle editing here still targets
    // footprint wall endpoints rather than elevation grips.
    final object = scene.objectByStableId(activeElementId!);
    if (object == null || object.kindKey != 'wall') {
      return;
    }
    final start = RenderSceneEditor.wallStartPoint(object);
    final end = RenderSceneEditor.wallEndPoint(object);
    if (start == null || end == null) {
      return;
    }
    final startScreen = projection.project(start).screen;
    final endScreen = projection.project(end).screen;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF2563EB);
    canvas.drawCircle(startScreen, 6.5, fill);
    canvas.drawCircle(startScreen, 6.5, stroke);
    canvas.drawCircle(endScreen, 6.5, fill);
    canvas.drawCircle(endScreen, 6.5, stroke);
  }

  void _drawActiveObjectGizmo(
    Canvas canvas,
    RenderSceneProjection projection,
  ) {
    final id = activeElementId;
    if (id == null || projectionMode == RenderSceneProjectionMode.topDown) {
      return;
    }
    final object = scene.objectByStableId(id);
    if (object == null) {
      return;
    }
    final center = projection.project(object.bounds.center).screen;
    const radius = 10.0;
    final halo = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x332563EB);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFF2563EB);
    canvas.drawCircle(center, radius, halo);
    canvas.drawCircle(center, radius, stroke);
    canvas.drawLine(
        center + const Offset(-16, 0), center + const Offset(16, 0), stroke);
    canvas.drawLine(
        center + const Offset(0, -16), center + const Offset(0, 16), stroke);
  }

  void _drawAxes(Canvas canvas, RenderSceneProjection projection) {
    if (!projectionMode.showAxes) {
      return;
    }
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

  void _drawLevels(Canvas canvas, RenderSceneProjection projection) {
    const textStyle = TextStyle(
      color: Color(0xFF334155),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    final overlays = buildLevelOverlayEntries(
      scene: scene,
      projectionMode: projectionMode,
      projection: projection,
    );
    for (final overlay in overlays) {
      final isSelected = overlay.level.levelId == selectedLevelId;
      _drawDashedLine(
        canvas,
        overlay.lineStart,
        overlay.lineEnd,
        Paint()
          ..color =
              (isSelected ? const Color(0xFF2563EB) : const Color(0xFF0F766E))
                  .withValues(alpha: 0.96)
          ..strokeWidth = isSelected ? 3.2 : 1.6,
        dashLength: 12,
        gapLength: 6,
      );
      final painter = TextPainter(
        text: TextSpan(
          text:
              '${overlay.level.name} ${overlay.level.elevationMeters.toStringAsFixed(2)}m',
          style: isSelected
              ? textStyle.copyWith(color: const Color(0xFF1D4ED8), fontSize: 13)
              : textStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 220);
      painter.paint(canvas, overlay.labelOrigin);
    }
  }

  double _niceGridSpacing(double maxExtent) {
    if (maxExtent <= 10) return 1;
    if (maxExtent <= 30) return 2;
    if (maxExtent <= 80) return 5;
    if (maxExtent <= 180) return 10;
    if (maxExtent <= 400) return 20;
    return 50;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final vector = end - start;
    final length = vector.distance;
    if (length <= 1e-6) {
      return;
    }
    final direction = vector / length;
    var offset = 0.0;
    while (offset < length) {
      final dashStart = start + direction * offset;
      final dashEnd = start + direction * math.min(offset + dashLength, length);
      canvas.drawLine(dashStart, dashEnd, paint);
      offset += dashLength + gapLength;
    }
  }

  Color _materialColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return const Color(0xFFB0B7C3);
    if (normalized.length == 6) return Color(0xFF000000 | parsed);
    if (normalized.length == 8) return Color(parsed);
    return const Color(0xFFB0B7C3);
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'wall':
        return const Color(0xFF9CA3AF);
      case 'door':
        return const Color(0xFF2563EB);
      case 'window':
        return const Color(0xFF0284C7);
      case 'slab':
      case 'floor':
        return const Color(0xFFE2D6B5);
      case 'ceiling':
        return const Color(0xFFE7EEF6);
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

}
