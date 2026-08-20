part of 'render_scene_viewport_painter.dart';

mixin _FallbackScenePlanPainterMixin {
  RenderScene get scene;
  Set<String> get selectedElementIds;
  String? get highlightedElementId;
  int? get selectedLevelId;
  List<_OutlineSegment> _buildProjectedBoundsRectOutlineSegments(
    RenderSceneBounds bounds,
    RenderSceneProjection projection,
  );
  Color _materialColor(String value);

  void _drawSectionLayerSeparators(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    // Section scenes emit one wall object per assembly layer. Outline each
    // emitted layer so the cut remains readable even when two adjacent
    // materials have similar colours or the display is set to solid.
    final sectionWalls = objects.where(
      (object) =>
          object.kindKey == 'wall' &&
          object.metadata['section_kind'] != null &&
          object.metadata['section_layer_index'] != null,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF475569).withValues(alpha: 0.72);
    for (final wall in sectionWalls) {
      final rect = projectBoundsRect(wall.bounds, projection);
      final layerIndex = int.tryParse(
            '${wall.metadata['section_layer_index'] ?? 0}',
          ) ??
          0;
      _drawHatchPattern(
        canvas,
        Path()..addRect(rect),
        rect,
        layerIndex,
        const Color(0xFF475569).withValues(alpha: 0.18),
      );
      for (final segment in _buildProjectedBoundsRectOutlineSegments(
        wall.bounds,
        projection,
      )) {
        canvas.drawLine(segment.a, segment.b, paint);
      }
    }
  }

  void _drawRoofSlopeLines(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    // A footprint roof is a set of slope planes.  Draw the non-horizontal
    // shared edges explicitly: generic mesh-outline suppression otherwise
    // hides the hip/valley lines that connect every eave corner to its raised
    // ridge loop.  This works for L, U and arbitrary simple footprints; it
    // deliberately does not assume a single centre apex.
    for (final roof in objects.where(
      (object) =>
          object.kindKey == 'roof' &&
          object.metadata['roof_type'] == 'AutoFootprint',
    )) {
      final positions = roof.mesh.positions;
      final indices = roof.mesh.indices;
      if (positions.length < 4 || indices.length < 3) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF7C2D12).withValues(alpha: 0.82);
      final baseZ = positions.map((point) => point.z).reduce(math.min);
      final ridgeZ = positions.map((point) => point.z).reduce(math.max);
      final drawnEdges = <String>{};
      for (var index = 0; index + 2 < indices.length; index += 3) {
        final triangle = <int>[
          indices[index],
          indices[index + 1],
          indices[index + 2],
        ];
        for (final edge in <(int, int)>[
          (triangle[0], triangle[1]),
          (triangle[1], triangle[2]),
          (triangle[2], triangle[0]),
        ]) {
          final firstIndex = edge.$1;
          final secondIndex = edge.$2;
          if (firstIndex < 0 ||
              secondIndex < 0 ||
              firstIndex >= positions.length ||
              secondIndex >= positions.length) {
            continue;
          }
          final first = positions[firstIndex];
          final second = positions[secondIndex];
          final isRidgeEdge = (first.z - ridgeZ).abs() <= 1e-6 &&
              (second.z - ridgeZ).abs() <= 1e-6;
          if (first.z <= baseZ + 1e-6 ||
              second.z <= baseZ + 1e-6 ||
              ((first.z - second.z).abs() <= 1e-6 && !isRidgeEdge)) {
            continue;
          }
          final low = math.min(firstIndex, secondIndex);
          final high = math.max(firstIndex, secondIndex);
          if (!drawnEdges.add('$low:$high')) continue;
          canvas.drawLine(
            projection.project(first).screen,
            projection.project(second).screen,
            paint,
          );
        }
      }
    }
  }

  void _drawPlanWallFootprints(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    final wallObjects = objects
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    final footprints = <_PlanWallFootprint>[];
    for (final wall in wallObjects) {
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      final thickness = RenderSceneEditor.wallThickness(wall);
      if (start == null || end == null || thickness == null) continue;
      final axis = end - start;
      final length = axis.distanceTo(RenderScenePoint.zero());
      if (length <= 1e-8) continue;
      final half = thickness * 0.5;
      final normal = RenderScenePoint(
        x: -axis.y / length * half,
        y: axis.x / length * half,
        z: 0,
      );
      final corners = <RenderScenePoint>[
        start + normal,
        end + normal,
        end - normal,
        start - normal,
      ];
      final screen = corners
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final id = wall.elementId?.toString();
      final selected = id != null && selectedElementIds.contains(id);
      final highlighted = id != null && id == highlightedElementId;
      final path = Path()
        ..moveTo(screen.first.dx, screen.first.dy)
        ..lineTo(screen[1].dx, screen[1].dy)
        ..lineTo(screen[2].dx, screen[2].dy)
        ..lineTo(screen[3].dx, screen[3].dy)
        ..close();
      footprints.add(
        _PlanWallFootprint(
          path: path,
          start: start,
          end: end,
          axis: axis,
          length: length,
          thickness: thickness,
          profile: _parseLayerProfile(wall.metadata['layer_profile']),
          selected: selected,
          highlighted: highlighted,
        ),
      );
    }
    if (footprints.isEmpty) return;

    // A floor plan is one horizontal cut through the wall network, not a
    // stack of independent wall rectangles. Unioning the cut footprints
    // removes doubled outlines, square end caps and protruding corners at
    // miter, tee and cross joins while preserving the semantic wall objects
    // used for picking and editing.
    final joinedWallPath = _unionPaths(
      footprints.map((footprint) => footprint.path),
    );
    const wallColor = Color(0xFF334155);
    canvas.drawPath(
      joinedWallPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = wallColor.withValues(alpha: 0.28),
    );

    // Keep assembly geometry semantic and lightweight. Layer strips from
    // touching walls are unioned before paint, so their hatches continue
    // through corners instead of drawing a rectangular cap for every wall.
    if (footprints.length <= 2000) {
      final layerBands = <_PlanLayerBandKey, List<Path>>{};
      for (final footprint in footprints) {
        final profile = footprint.profile;
        if (profile.isEmpty) continue;
        final profileThickness = profile.fold<double>(
          0.0,
          (sum, layer) => sum + layer.thicknessMeters,
        );
        if (profileThickness <= 1e-8) continue;
        final half = footprint.thickness * 0.5;
        final normalUnit = RenderScenePoint(
          x: -footprint.axis.y / footprint.length,
          y: footprint.axis.x / footprint.length,
          z: 0,
        );
        var offset = -half;
        for (var layerIndex = 0; layerIndex < profile.length; layerIndex += 1) {
          final layer = profile[layerIndex];
          final previousOffset = offset;
          offset +=
              (layer.thicknessMeters / profileThickness) * footprint.thickness;
          final layerStart = footprint.start +
              RenderScenePoint(
                x: normalUnit.x * previousOffset,
                y: normalUnit.y * previousOffset,
                z: 0,
              );
          final layerEnd = footprint.end +
              RenderScenePoint(
                x: normalUnit.x * previousOffset,
                y: normalUnit.y * previousOffset,
                z: 0,
              );
          final nextStart = footprint.start +
              RenderScenePoint(
                x: normalUnit.x * offset,
                y: normalUnit.y * offset,
                z: 0,
              );
          final nextEnd = footprint.end +
              RenderScenePoint(
                x: normalUnit.x * offset,
                y: normalUnit.y * offset,
                z: 0,
              );
          final layerScreen = <Offset>[
            projection.project(layerStart).screen,
            projection.project(layerEnd).screen,
            projection.project(nextEnd).screen,
            projection.project(nextStart).screen,
          ];
          final layerPath = Path()
            ..moveTo(layerScreen.first.dx, layerScreen.first.dy)
            ..lineTo(layerScreen[1].dx, layerScreen[1].dy)
            ..lineTo(layerScreen[2].dx, layerScreen[2].dy)
            ..lineTo(layerScreen[3].dx, layerScreen[3].dy)
            ..close();
          final key = _PlanLayerBandKey(
            materialId: layer.materialId,
            layerIndex: layerIndex,
            layerCount: profile.length,
          );
          layerBands.putIfAbsent(key, () => <Path>[]).add(layerPath);
        }
      }

      final orderedBands = layerBands.entries.toList(growable: false)
        ..sort((a, b) => a.key.layerIndex.compareTo(b.key.layerIndex));
      for (final entry in orderedBands) {
        final bandPath = Path.combine(
          PathOperation.intersect,
          _unionPaths(entry.value),
          joinedWallPath,
        );
        final layerColor =
            _materialColorForId(entry.key.materialId) ?? wallColor;
        canvas.drawPath(
          bandPath,
          Paint()
            ..style = PaintingStyle.fill
            ..color = layerColor.withValues(alpha: 0.34),
        );
        _drawHatchPattern(
          canvas,
          bandPath,
          bandPath.getBounds(),
          entry.key.layerIndex,
          layerColor.withValues(alpha: 0.34),
        );
        canvas.drawPath(
          bandPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.85
            ..strokeJoin = StrokeJoin.miter
            ..color = wallColor.withValues(alpha: 0.55),
        );
      }
    }

    // The network gets exactly one architectural cut outline. Selection is a
    // separate transient overlay and never reintroduces per-wall normal
    // outlines at unselected joins.
    canvas.drawPath(
      joinedWallPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.miter
        ..color = wallColor,
    );
    for (final footprint in footprints) {
      if (!footprint.selected && !footprint.highlighted) continue;
      final color = footprint.selected
          ? const Color(0xFF2563EB)
          : const Color(0xFFDC2626);
      canvas.drawPath(
        footprint.path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.22),
      );
      canvas.drawPath(
        footprint.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.miter
          ..color = color,
      );
    }
  }

  void _drawPlanOpeningSymbols(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    final walls = <int, RenderSceneObject>{
      for (final object in objects)
        if (object.kindKey == 'wall' && object.elementId != null)
          object.elementId!: object,
    };
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..color = const Color(0xFF111827);
    for (final opening in objects) {
      if (opening.kindKey != 'door' && opening.kindKey != 'window') continue;
      final hostId = int.tryParse('${opening.metadata['host_wall_id'] ?? ''}');
      final host = hostId == null ? null : walls[hostId];
      if (host == null) continue;
      final start = RenderSceneEditor.wallStartPoint(host);
      final end = RenderSceneEditor.wallEndPoint(host);
      final offset = _metadataDouble(opening, 'offset_meters');
      final width = _metadataDouble(opening, 'width_meters');
      if (start == null || end == null || offset == null || width == null) {
        continue;
      }
      final axis = end - start;
      final length = axis.distanceTo(RenderScenePoint.zero());
      if (length <= 1e-8 || width <= 1e-8) continue;
      final axisUnit = axis.scale(1.0 / length);
      final normal = RenderScenePoint(
        x: -axisUnit.y,
        y: axisUnit.x,
        z: 0,
      );
      final center = start + axisUnit.scale(offset);
      final halfWidth = width * 0.5;
      final first = center - axisUnit.scale(halfWidth);
      final second = center + axisUnit.scale(halfWidth);
      final hostThickness = RenderSceneEditor.wallThickness(host) ?? 0.20;
      final halfThickness = hostThickness * 0.5;
      final cutCorners = <RenderScenePoint>[
        first + normal.scale(halfThickness),
        second + normal.scale(halfThickness),
        second - normal.scale(halfThickness),
        first - normal.scale(halfThickness),
      ];
      final cutScreen = cutCorners
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final cutPath = Path()
        ..moveTo(cutScreen[0].dx, cutScreen[0].dy)
        ..lineTo(cutScreen[1].dx, cutScreen[1].dy)
        ..lineTo(cutScreen[2].dx, cutScreen[2].dy)
        ..lineTo(cutScreen[3].dx, cutScreen[3].dy)
        ..close();
      // Openings are not rendered as a second full wall prism in plan. Paint
      // a small background-coloured cut first, then keep the existing Revit-
      // style door/window symbol above it.
      canvas.drawPath(
        cutPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFF5F8F6),
      );
      final openEnd = first + normal.scale(width);
      final p0 = projection.project(first).screen;
      final p1 = projection.project(second).screen;
      final pc = projection.project(center).screen;
      final po = projection.project(openEnd).screen;
      // Do not leave the cut as a blank white rectangle. The jamb strokes
      // make the opening visibly part of its host wall even when the native
      // wall material is very light or the plan is zoomed out.
      final firstOuter =
          projection.project(first + normal.scale(halfThickness)).screen;
      final firstInner =
          projection.project(first - normal.scale(halfThickness)).screen;
      final secondOuter =
          projection.project(second + normal.scale(halfThickness)).screen;
      final secondInner =
          projection.project(second - normal.scale(halfThickness)).screen;
      canvas.drawLine(firstOuter, firstInner, paint);
      canvas.drawLine(secondOuter, secondInner, paint);
      if (opening.kindKey == 'window') {
        // Double-casement window: draw two door-like leaves side by side.
        // Each leaf is hinged at its outer jamb and swings toward the
        // centre, so the two quarter-circle arcs meet at the centre split.
        final panelWidth = halfWidth;
        final leftOpen = first + normal.scale(panelWidth);
        final rightOpen = second + normal.scale(panelWidth);
        final leftHinge = projection.project(first).screen;
        final rightHinge = projection.project(second).screen;
        final leftOpenPoint = projection.project(leftOpen).screen;
        final rightOpenPoint = projection.project(rightOpen).screen;
        canvas.drawLine(leftHinge, leftOpenPoint, paint);
        canvas.drawLine(rightHinge, rightOpenPoint, paint);

        void drawSwingArc(Offset hinge, Offset closed, Offset open) {
          final radius = (closed - hinge).distance;
          if (radius <= 1.0) return;
          final startAngle = math.atan2(
            closed.dy - hinge.dy,
            closed.dx - hinge.dx,
          );
          final endAngle = math.atan2(
            open.dy - hinge.dy,
            open.dx - hinge.dx,
          );
          var sweep = endAngle - startAngle;
          while (sweep > math.pi) {
            sweep -= math.pi * 2;
          }
          while (sweep < -math.pi) {
            sweep += math.pi * 2;
          }
          canvas.drawArc(
            Rect.fromCircle(center: hinge, radius: radius),
            startAngle,
            sweep,
            false,
            paint,
          );
        }

        drawSwingArc(leftHinge, pc, leftOpenPoint);
        drawSwingArc(rightHinge, pc, rightOpenPoint);
        continue;
      }
      canvas.drawLine(p0, po, paint);
      final radius = (p1 - p0).distance;
      if (radius <= 1.0) continue;
      final startAngle = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
      final endAngle = math.atan2(po.dy - p0.dy, po.dx - p0.dx);
      var sweep = endAngle - startAngle;
      while (sweep > math.pi) {
        sweep -= math.pi * 2;
      }
      while (sweep < -math.pi) {
        sweep += math.pi * 2;
      }
      if (sweep.abs() < 0.08) sweep = sweep < 0 ? -math.pi / 2 : math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: p0, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  double? _metadataDouble(RenderSceneObject object, String key) {
    final value = object.metadata[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Path _unionPaths(Iterable<Path> paths) {
    final iterator = paths.iterator;
    if (!iterator.moveNext()) return Path();
    var joined = Path.from(iterator.current);
    while (iterator.moveNext()) {
      joined = Path.combine(PathOperation.union, joined, iterator.current);
    }
    return joined;
  }

  void _drawHatchPattern(
    Canvas canvas,
    Path clipPath,
    Rect bounds,
    int patternIndex,
    Color color,
  ) {
    if (bounds.width <= 0.5 || bounds.height <= 0.5) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = color;
    canvas.save();
    canvas.clipPath(clipPath);
    const spacing = 7.0;
    switch (patternIndex % 4) {
      case 0:
        for (var x = bounds.left - bounds.height;
            x <= bounds.right + bounds.height;
            x += spacing) {
          canvas.drawLine(Offset(x, bounds.bottom),
              Offset(x + bounds.height, bounds.top), paint);
        }
      case 1:
        for (var x = bounds.left - bounds.height;
            x <= bounds.right + bounds.height;
            x += spacing) {
          canvas.drawLine(Offset(x, bounds.top),
              Offset(x + bounds.height, bounds.bottom), paint);
        }
      case 2:
        for (var y = bounds.top; y <= bounds.bottom; y += spacing) {
          canvas.drawLine(
              Offset(bounds.left, y), Offset(bounds.right, y), paint);
        }
      case 3:
        for (var x = bounds.left; x <= bounds.right; x += spacing) {
          canvas.drawLine(
              Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
        }
    }
    canvas.restore();
  }

  void _drawSectionGuides(
    Canvas canvas,
    RenderSceneProjection projection,
  ) {
    final z = scene.levelById(selectedLevelId)?.elevationMeters ?? 0.0;
    final sections = scene.sections.isNotEmpty
        ? scene.sections
        : <RenderSceneSection>[
            RenderSceneSection(
              name: 'Section A',
              start: RenderScenePoint(
                x: scene.bounds.min.x,
                y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
                z: 0,
              ),
              end: RenderScenePoint(
                x: scene.bounds.max.x,
                y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
                z: 0,
              ),
            ),
            RenderSceneSection(
              name: 'Section B',
              start: RenderScenePoint(
                x: (scene.bounds.min.x + scene.bounds.max.x) * 0.5,
                y: scene.bounds.min.y,
                z: 0,
              ),
              end: RenderScenePoint(
                x: (scene.bounds.min.x + scene.bounds.max.x) * 0.5,
                y: scene.bounds.max.y,
                z: 0,
              ),
            ),
          ];
    for (final section in sections) {
      final start = RenderScenePoint(
        x: section.start.x,
        y: section.start.y,
        z: z,
      );
      final end = RenderScenePoint(x: section.end.x, y: section.end.y, z: z);
      final delta = end - start;
      final length = delta.distanceTo(RenderScenePoint.zero());
      if (length <= 1e-8) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xFFB42318).withValues(alpha: 0.92);
      const dash = 0.45;
      const gap = 0.22;
      for (var cursor = 0.0; cursor < length; cursor += dash + gap) {
        final from = cursor / length;
        final to = math.min(cursor + dash, length) / length;
        final a = start +
            RenderScenePoint(
              x: delta.x * from,
              y: delta.y * from,
              z: 0,
            );
        final b = start +
            RenderScenePoint(
              x: delta.x * to,
              y: delta.y * to,
              z: 0,
            );
        canvas.drawLine(
          projection.project(a).screen,
          projection.project(b).screen,
          paint,
        );
      }
    }
  }

  List<_LayerProfileEntry> _parseLayerProfile(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <_LayerProfileEntry>[];
    final result = <_LayerProfileEntry>[];
    for (final entry in raw.split(';')) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      final materialId = int.tryParse(parts[0]);
      final thickness = double.tryParse(parts[1]);
      if (materialId == null || thickness == null || thickness <= 0) continue;
      result.add(
        _LayerProfileEntry(materialId: materialId, thicknessMeters: thickness),
      );
    }
    return result;
  }

  Color? _materialColorForId(int materialId) {
    final material = scene.materialById(materialId);
    return material == null ? null : _materialColor(material.displayColor);
  }
}
