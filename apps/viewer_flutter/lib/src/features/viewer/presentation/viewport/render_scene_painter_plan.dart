part of 'render_scene_viewport_painter.dart';

mixin _FallbackScenePlanPainterMixin {
  RenderScene get scene;
  Set<String> get selectedElementIds;
  String? get highlightedElementId;
  int? get selectedLevelId;
  RenderSceneDisplayStyle get displayStyle;
  List<_OutlineSegment> _buildProjectedBoundsRectOutlineSegments(
    RenderSceneBounds bounds,
    RenderSceneProjection projection,
  );
  Color _materialColor(String value);
  Color _floorSurfaceColor(RenderSceneObject object);
  RenderSceneObjectMoveDraft? get draftObjectMove;

  bool _isFamilyPlanObject(RenderSceneObject object) {
    if (object.kindKey != 'column' && object.kindKey != 'proxy') return false;
    final assetId = object.metadata['family_asset_id'];
    return assetId != null && assetId.toString().trim().isNotEmpty;
  }

  void _drawPlanFamilySymbols(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    final movingId = draftObjectMove?.object.elementId;
    for (final object in objects) {
      if (!_isFamilyPlanObject(object) || object.elementId == movingId) {
        continue;
      }
      _drawPlanFamilySymbol(canvas, projection, object);
    }
  }

  void _drawPlanFamilySymbol(
    Canvas canvas,
    RenderSceneProjection projection,
    RenderSceneObject object, {
    RenderScenePoint delta = const RenderScenePoint(x: 0, y: 0, z: 0),
  }) {
    final id = object.elementId?.toString();
    final color = id != null && selectedElementIds.contains(id)
        ? const Color(0xFF2563EB)
        : id != null && id == highlightedElementId
            ? const Color(0xFFDC2626)
            : const Color(0xFF475569);
    final center = object.bounds.center;
    final svg = object.metadata['family_plan_svg'];
    final symbols = svg is String ? FamilyPlanSymbolPath.parse(svg) : const [];
    if (symbols.isNotEmpty) {
      for (final symbol in symbols) {
        final path = Path();
        for (final command in symbol.commands) {
          if (command.isClose) {
            path.close();
            continue;
          }
          final point = projection
              .project(
                RenderScenePoint(
                  x: center.x + command.x + delta.x,
                  y: center.y + command.y + delta.y,
                  z: object.bounds.min.z,
                ),
              )
              .screen;
          if (command.kind == 'M') {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: 0.12),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                id != null && selectedElementIds.contains(id) ? 2.2 : 1.25
            ..strokeJoin = StrokeJoin.round
            ..color = color,
        );
      }
      return;
    }

    final corners = <RenderScenePoint>[
      RenderScenePoint(
        x: object.bounds.min.x + delta.x,
        y: object.bounds.min.y + delta.y,
        z: object.bounds.min.z,
      ),
      RenderScenePoint(
        x: object.bounds.max.x + delta.x,
        y: object.bounds.min.y + delta.y,
        z: object.bounds.min.z,
      ),
      RenderScenePoint(
        x: object.bounds.max.x + delta.x,
        y: object.bounds.max.y + delta.y,
        z: object.bounds.min.z,
      ),
      RenderScenePoint(
        x: object.bounds.min.x + delta.x,
        y: object.bounds.max.y + delta.y,
        z: object.bounds.min.z,
      ),
    ].map((point) => projection.project(point).screen).toList(growable: false);
    if (corners.length < 4) return;
    final path = Path()..moveTo(corners.first.dx, corners.first.dy);
    for (final point in corners.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = color,
    );
  }

  List<RenderScenePoint> _authoritativeWallFootprint(
    RenderSceneObject wall,
  ) {
    final raw =
        wall.metadata['profile_corners'] ?? wall.metadata['profileCorners'];
    if (raw is List) {
      final points = raw
          .map(RenderScenePoint.fromJson)
          .whereType<RenderScenePoint>()
          .where((point) => point.x.isFinite && point.y.isFinite)
          .toList(growable: false);
      if (points.length >= 3) return points;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final points = raw
          .split(';')
          .map((token) {
            final coordinates = token.split(',');
            if (coordinates.length != 2) return null;
            final x = double.tryParse(coordinates[0].trim());
            final y = double.tryParse(coordinates[1].trim());
            if (x == null || y == null || !x.isFinite || !y.isFinite) {
              return null;
            }
            return RenderScenePoint(x: x, y: y, z: 0.0);
          })
          .whereType<RenderScenePoint>()
          .toList(growable: false);
      if (points.length >= 3) return points;
    }
    return const <RenderScenePoint>[];
  }

  List<RenderScenePoint> _surfaceFootprint(RenderSceneObject object) {
    final raw = object.metadata['footprint_points'];
    if (raw is List) {
      final points = raw
          .map(RenderScenePoint.fromJson)
          .whereType<RenderScenePoint>()
          .toList(growable: false);
      if (points.length >= 3) return points;
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final points = raw
          .split(';')
          .map((token) {
            final coordinates = token.split(',');
            if (coordinates.length != 2) return null;
            final x = double.tryParse(coordinates[0].trim());
            final y = double.tryParse(coordinates[1].trim());
            if (x == null || y == null || !x.isFinite || !y.isFinite) {
              return null;
            }
            return RenderScenePoint(x: x, y: y, z: 0.0);
          })
          .whereType<RenderScenePoint>()
          .toList(growable: false);
      if (points.length >= 3) return points;
    }
    return <RenderScenePoint>[
      RenderScenePoint(x: object.bounds.min.x, y: object.bounds.min.y, z: 0.0),
      RenderScenePoint(x: object.bounds.max.x, y: object.bounds.min.y, z: 0.0),
      RenderScenePoint(x: object.bounds.max.x, y: object.bounds.max.y, z: 0.0),
      RenderScenePoint(x: object.bounds.min.x, y: object.bounds.max.y, z: 0.0),
    ];
  }

  Path _projectedSurfacePath(
    RenderSceneObject object,
    RenderSceneProjection projection,
  ) {
    final points = _surfaceFootprint(object);
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(projection.project(points.first).screen.dx,
        projection.project(points.first).screen.dy);
    for (final point in points.skip(1)) {
      final screen = projection.project(point).screen;
      path.lineTo(screen.dx, screen.dy);
    }
    path.close();
    return path;
  }

  void _drawFloorSurfacePatterns(
    Canvas canvas,
    RenderSceneProjection projection,
    Iterable<RenderSceneObject> objects,
  ) {
    if (displayStyle == RenderSceneDisplayStyle.wireframe) return;
    for (final floor in objects.where(
      (object) => object.kindKey == 'floor' || object.kindKey == 'slab',
    )) {
      final footprintPath = _projectedSurfacePath(floor, projection);
      final rect = footprintPath.getBounds();
      if (rect.width <= 1.0 || rect.height <= 1.0) continue;
      final key =
          '${floor.metadata['floor_type'] ?? ''} ${floor.metadata['floor_type_name'] ?? ''}'
              .toLowerCase();
      final isWood = key.contains('wood') ||
          key.contains('timber') ||
          key.contains('laminate') ||
          key.contains('parquet');
      final isAsphalt = key.contains('asphalt') || key.contains('bitumen');
      final isGrass = key.contains('grass') ||
          key.contains('lawn') ||
          key.contains('landscape');
      final isPaving = key.contains('paving') ||
          key.contains('walkway') ||
          key.contains('sidewalk') ||
          key.contains('paver');
      final lineColor = displayStyle == RenderSceneDisplayStyle.solid
          ? const Color(0x66515B66)
          : _floorSurfaceColor(floor).withValues(alpha: 0.34);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            displayStyle == RenderSceneDisplayStyle.solid ? 0.75 : 0.9
        ..color = lineColor;
      canvas.save();
      canvas.clipPath(footprintPath);
      if (isWood) {
        final plankSpacing = math.max(7.0, math.min(22.0, rect.height / 8.0));
        for (var y = rect.top; y <= rect.bottom; y += plankSpacing) {
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
          final seamOffset = ((y - rect.top) / plankSpacing).floor().isEven
              ? rect.left + rect.width * 0.36
              : rect.left + rect.width * 0.68;
          canvas.drawLine(
            Offset(seamOffset, y),
            Offset(seamOffset, y + plankSpacing),
            paint,
          );
        }
      } else if (isAsphalt) {
        final spacing = math.max(9.0, math.min(28.0, rect.shortestSide / 7.0));
        for (var x = rect.left - rect.height;
            x <= rect.right + rect.height;
            x += spacing) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height, rect.top),
            paint,
          );
        }
      } else if (isGrass) {
        final spacing = math.max(8.0, math.min(18.0, rect.shortestSide / 7.0));
        for (var x = rect.left - rect.height;
            x <= rect.right + rect.height;
            x += spacing) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height * 0.28, rect.top),
            paint,
          );
        }
      } else if (isPaving) {
        final spacing = math.max(8.0, math.min(24.0, rect.shortestSide / 5.0));
        for (var x = rect.left; x <= rect.right; x += spacing) {
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
        }
        for (var y = rect.top; y <= rect.bottom; y += spacing) {
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
        }
      } else {
        final spacing = math.max(10.0, math.min(34.0, rect.shortestSide / 6.0));
        for (var x = rect.left; x <= rect.right; x += spacing) {
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
        }
        for (var y = rect.top; y <= rect.bottom; y += spacing) {
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
        }
      }
      canvas.restore();
    }
  }

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
      final centerline = RenderSceneEditor.wallCenterlinePoints(wall);
      if (centerline.length < 2) continue;
      final axis = end - start;
      var length = 0.0;
      for (var index = 0; index + 1 < centerline.length; index += 1) {
        length += (centerline[index + 1] - centerline[index])
            .distanceTo(RenderScenePoint.zero());
      }
      if (length <= 1e-8) continue;
      final half = thickness * 0.5;
      final authoritativeCorners = _authoritativeWallFootprint(wall);
      final curved =
          wall.metadata['curve_kind'] == 'arc' || centerline.length > 2;
      final corners = <RenderScenePoint>[];
      if (authoritativeCorners.length >= 3) {
        // The core has already resolved curved/straight mixed caps and tees.
        // Use that same polygon in the fallback painter so a renderer switch
        // cannot reintroduce a chord, a raw rectangle or a different join.
        corners.addAll(authoritativeCorners);
      } else if (curved) {
        final outside = <RenderScenePoint>[];
        final inside = <RenderScenePoint>[];
        for (var index = 0; index < centerline.length; index += 1) {
          final previous =
              index == 0 ? centerline[index] : centerline[index - 1];
          final next = index == centerline.length - 1
              ? centerline[index]
              : centerline[index + 1];
          final tangent = next - previous;
          final tangentLength = tangent.distanceTo(RenderScenePoint.zero());
          if (tangentLength <= 1e-8) continue;
          final normal = RenderScenePoint(
            x: -tangent.y / tangentLength * half,
            y: tangent.x / tangentLength * half,
            z: 0,
          );
          outside.add(centerline[index] + normal);
          inside.add(centerline[index] - normal);
        }
        if (outside.length < 2 || inside.length != outside.length) continue;
        corners.addAll(outside);
        corners.addAll(inside.reversed);
      } else {
        final axis = end - start;
        final normal = RenderScenePoint(
          x: -axis.y / length * half,
          y: axis.x / length * half,
          z: 0,
        );
        corners.addAll(<RenderScenePoint>[
          start + normal,
          end + normal,
          end - normal,
          start - normal
        ]);
      }
      final screen = corners
          .map((point) => projection.project(point).screen)
          .toList(growable: false);
      final id = wall.elementId?.toString();
      final selected = id != null && selectedElementIds.contains(id);
      final highlighted = id != null && id == highlightedElementId;
      final path = Path()..moveTo(screen.first.dx, screen.first.dy);
      for (final point in screen.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      footprints.add(
        _PlanWallFootprint(
          path: path,
          start: start,
          end: end,
          axis: axis,
          length: length,
          thickness: thickness,
          curved: curved,
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
    final wallFillAlpha =
        displayStyle == RenderSceneDisplayStyle.solid ? 1.0 : 0.28;
    canvas.drawPath(
      joinedWallPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = wallColor.withValues(alpha: wallFillAlpha),
    );

    // Keep assembly geometry semantic and lightweight. Layer strips from
    // touching walls are unioned before paint, so their hatches continue
    // through corners instead of drawing a rectangular cap for every wall.
    if (footprints.length <= 2000) {
      final layerBands = <_PlanLayerBandKey, List<Path>>{};
      for (final footprint in footprints) {
        if (footprint.curved) continue;
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

    // The union above is intentionally the single outer cut contour. It also
    // removes any wall side that is fully inside that contour, which makes
    // interior walls disappear in a floor plan. Restore each wall's two long
    // sides as short, end-inset strokes. They preserve the clean joined
    // corners while keeping every semantic wall readable for authoring.
    final wallSidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = displayStyle == RenderSceneDisplayStyle.solid ? 0.95 : 0.8
      ..strokeCap = StrokeCap.butt
      ..color = wallColor.withValues(
        alpha: displayStyle == RenderSceneDisplayStyle.solid ? 0.82 : 0.58,
      );
    for (final footprint in footprints) {
      if (footprint.curved) continue;
      final axisUnit = footprint.axis.scale(1.0 / footprint.length);
      final normalUnit = RenderScenePoint(
        x: -axisUnit.y,
        y: axisUnit.x,
        z: 0,
      );
      final endInset = math.min(
        footprint.length * 0.08,
        math.max(footprint.thickness * 1.25, 0.08),
      );
      if (footprint.length <= endInset * 2.0) continue;
      for (final side in <double>[-1.0, 1.0]) {
        final edgeStart = footprint.start +
            normalUnit.scale(footprint.thickness * 0.5 * side) +
            axisUnit.scale(endInset);
        final edgeEnd = footprint.end +
            normalUnit.scale(footprint.thickness * 0.5 * side) -
            axisUnit.scale(endInset);
        final start = projection.project(edgeStart).screen;
        final end = projection.project(edgeEnd).screen;
        if ((end - start).distance > 0.5) {
          canvas.drawLine(start, end, wallSidePaint);
        }
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
    final windowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
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
      final centerline = RenderSceneEditor.wallCenterlinePoints(host);
      var length = 0.0;
      for (var index = 0; index + 1 < centerline.length; index += 1) {
        length += (centerline[index + 1] - centerline[index])
            .distanceTo(RenderScenePoint.zero());
      }
      if (length <= 1e-8) {
        length = axis.distanceTo(RenderScenePoint.zero());
      }
      if (length <= 1e-8 || width <= 1e-8) continue;
      RenderScenePoint pointAt(double distance) {
        if (centerline.length < 2) return start + axis.scale(distance / length);
        var cursor = 0.0;
        for (var index = 0; index + 1 < centerline.length; index += 1) {
          final segment = centerline[index + 1] - centerline[index];
          final segmentLength = segment.distanceTo(RenderScenePoint.zero());
          if (cursor + segmentLength >= distance ||
              index == centerline.length - 2) {
            final fraction = segmentLength <= 1e-8
                ? 0.0
                : ((distance - cursor) / segmentLength).clamp(0.0, 1.0);
            return centerline[index] + segment.scale(fraction);
          }
          cursor += segmentLength;
        }
        return centerline.last;
      }

      RenderScenePoint tangentAt(double distance) {
        final before = pointAt((distance - 0.02).clamp(0.0, length));
        final after = pointAt((distance + 0.02).clamp(0.0, length));
        final tangent = after - before;
        final tangentLength = tangent.distanceTo(RenderScenePoint.zero());
        return tangentLength <= 1e-8
            ? axis.scale(1.0 / length)
            : tangent.scale(1.0 / tangentLength);
      }

      final curved = centerline.length > 2;
      final axisUnit = curved ? tangentAt(offset) : axis.scale(1.0 / length);
      final normal = RenderScenePoint(
        x: -axisUnit.y,
        y: axisUnit.x,
        z: 0,
      );
      final halfWidth = width * 0.5;
      final center = curved ? pointAt(offset) : start + axisUnit.scale(offset);
      final first = curved
          ? pointAt((offset - halfWidth).clamp(0.0, length))
          : center - axisUnit.scale(halfWidth);
      final second = curved
          ? pointAt((offset + halfWidth).clamp(0.0, length))
          : center + axisUnit.scale(halfWidth);
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
        // Windows use the compact architectural plan symbol: two glazing
        // lines parallel to the host wall. Swing arcs belong to doors and
        // make small windows noisy and visually ambiguous.
        final glassOffset = halfThickness * 0.70;
        final glassFirst =
            projection.project(first + normal.scale(glassOffset)).screen;
        final glassSecond =
            projection.project(second + normal.scale(glassOffset)).screen;
        final glassFirstBack =
            projection.project(first - normal.scale(glassOffset)).screen;
        final glassSecondBack =
            projection.project(second - normal.scale(glassOffset)).screen;
        canvas.drawLine(glassFirst, glassSecond, windowPaint);
        canvas.drawLine(glassFirstBack, glassSecondBack, windowPaint);
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
