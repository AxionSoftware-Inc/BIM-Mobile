import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'render_scene_editor.dart';
import 'render_scene_level_overlay.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_projection.dart';
import 'render_scene_viewport_types.dart';
import 'tools/wall_authoring_geometry.dart';

part 'render_scene_painter_plan.dart';
part 'render_scene_painter_render.dart';
part 'render_scene_painter_overlay.dart';

class FallbackRenderScenePainter extends CustomPainter
    with
        _FallbackScenePlanPainterMixin,
        _FallbackSceneRenderMixin,
        _FallbackSceneOverlayMixin {
  FallbackRenderScenePainter({
    required this.scene,
    required this.visibleKinds,
    required this.selectedElementIds,
    required this.activeElementId,
    required this.selectedLevelId,
    this.selectionRect,
    required this.highlightedElementId,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.displayStyle,
    this.viewportTheme = RenderSceneViewportTheme.light,
    required this.camera,
    required this.planCamera,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftOpening,
    required this.draftSurface,
    required this.draftWallThicknessMeters,
    required this.draftWallHeightMeters,
    this.showObjectLabels = true,
    this.showReferenceGrid = true,
  });

  static const double padding = 48;

  @override
  final RenderScene scene;
  final Set<String> visibleKinds;
  @override
  final Set<String> selectedElementIds;
  @override
  final String? activeElementId;
  @override
  final int? selectedLevelId;
  final Rect? selectionRect;
  @override
  final String? highlightedElementId;
  @override
  final RenderSceneProjectionMode projectionMode;
  @override
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  @override
  final RenderSceneDisplayStyle displayStyle;
  @override
  final RenderSceneViewportTheme viewportTheme;
  @override
  final RenderSceneCameraState camera;
  final RenderScenePlanCameraState planCamera;
  @override
  final RenderScenePoint? draftWallStart;
  @override
  final RenderScenePoint? draftWallEnd;
  @override
  final RenderSceneOpeningDraft? draftOpening;
  @override
  final RenderSceneSurfaceDraft? draftSurface;
  @override
  final double draftWallThicknessMeters;
  @override
  final double draftWallHeightMeters;
  final bool showObjectLabels;
  final bool showReferenceGrid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = switch (viewportTheme) {
          RenderSceneViewportTheme.light => const Color(0xFFF5F8F6),
          RenderSceneViewportTheme.standardDark => const Color(0xFF202427),
          RenderSceneViewportTheme.amoledBlack => Colors.black,
        },
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

    if (showReferenceGrid) {
      _drawGrid(canvas, projection);
      _drawAxes(canvas, projection);
      _drawLevels(canvas, projection);
      if (projectionMode == RenderSceneProjectionMode.topDown) {
        _drawSectionGuides(canvas, projection);
      }
    }

    final packets = <_RenderPacket>[];
    final filteredObjects = scene.objectsForKinds(visibleKinds);
    // Keep structural/active silhouettes at city scale, but avoid drawing a
    // distracting soup of passive secondary edges.
    final denseModel = filteredObjects.length > 420 ||
        filteredObjects.fold<int>(
              0,
              (sum, object) => sum + object.mesh.triangleCount,
            ) >
            42000;
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      // Engine wall meshes are predominantly vertical faces. Their triangles
      // can collapse to zero area in a top projection, so draw the canonical
      // wall footprint independently of mesh tessellation.
      _drawPlanWallFootprints(canvas, projection, filteredObjects);
    }
    final depthRange = projectionMode.isElevation
        ? _projectedObjectDepthRange(filteredObjects, projection)
        : null;

    for (final object in filteredObjects) {
      // A plan wall is already painted above as one joined horizontal cut.
      // Re-projecting the 3D wall mesh here draws its triangulation and its
      // unjoined end caps over the canonical footprint, producing diagonal
      // selection lines and dark spikes at otherwise valid wall corners.
      if (projectionMode == RenderSceneProjectionMode.topDown &&
          (object.kindKey == 'wall' ||
              object.kindKey == 'door' ||
              object.kindKey == 'window')) {
        continue;
      }
      final elementId = object.elementId?.toString();
      final isSelected =
          elementId != null && selectedElementIds.contains(elementId);
      final isHighlighted =
          elementId == highlightedElementId && highlightedElementId != null;
      final isFloorSurface =
          object.kindKey == 'floor' || object.kindKey == 'slab';
      final baseColor = isFloorSurface
          ? displayStyle == RenderSceneDisplayStyle.solid
              ? const Color(0xFFE5E7EB)
              : _floorSurfaceColor(object)
          : _kindColor(object.kindKey);
      final objectColor = isSelected
          ? const Color(0xFF2563EB)
          : isHighlighted
              ? const Color(0xFFDC2626)
              : baseColor;
      final depthWeight = projectionMode.isElevation
          ? _depthVisualWeight(
              depth: projectObjectDepth(object.bounds, projection),
              minDepth: depthRange!.$1,
              maxDepth: depthRange.$2,
            )
          : 1.0;

      final strokeWidth = _triangleStrokeWidth(
        kind: object.kindKey,
        isSelected: isSelected,
        isHighlighted: isHighlighted,
      );
      final fillAlpha = displayStyle == RenderSceneDisplayStyle.wireframe
          ? 0.0
          : _fillAlphaForObject(
              object: object,
              kind: object.kindKey,
              isSelected: isSelected,
              isHighlighted: isHighlighted,
            );

      packets.add(
        _RenderPacket(
          triangles: _buildObjectTriangles(
            object: object,
            projection: projection,
            fillColor: _withScaledAlpha(
              objectColor.withValues(alpha: fillAlpha),
              depthWeight,
            ),
            strokeColor: _withScaledAlpha(
              objectColor.withValues(alpha: 0.96),
              depthWeight,
            ),
            strokeWidth: strokeWidth,
            materialColors: {
              for (final material in scene.materials)
                material.id: _materialColor(material.displayColor),
            },
            // Keep the architectural display colors stable in both Shaded
            // and Solid modes. Assembly/material colors are still used by
            // the lightweight layer hatch renderer below.
            honorMaterialColors: !isSelected &&
                !isHighlighted &&
                !isFloorSurface &&
                object.kindKey != 'wall' &&
                object.kindKey != 'door' &&
                object.kindKey != 'window',
          ),
          outlines: displayStyle == RenderSceneDisplayStyle.solid &&
                  _shouldDrawSolidOutline(
                    kind: object.kindKey,
                    isSelected: isSelected,
                    isHighlighted: isHighlighted,
                    denseModel: denseModel,
                  )
              ? _buildOutlineSegments(object, projection)
              : const <_OutlineSegment>[],
          outlineColor: _outlineColor(
            kind: object.kindKey,
            objectColor: objectColor,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
            depthWeight: depthWeight,
          ),
          outlineStrokeWidth: _outlineStrokeWidth(
            kind: object.kindKey,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
          ),
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

        if (displayStyle != RenderSceneDisplayStyle.wireframe) {
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

    _drawFloorSurfacePatterns(canvas, projection, filteredObjects);

    if (projectionMode == RenderSceneProjectionMode.topDown) {
      _drawPlanOpeningSymbols(canvas, projection, filteredObjects);
    }

    if (projectionMode.isElevation) {
      _drawSectionLayerSeparators(canvas, projection, filteredObjects);
    }
    if (displayStyle == RenderSceneDisplayStyle.solid) {
      _drawRoofSlopeLines(canvas, projection, filteredObjects);
    }

    if (showObjectLabels) {
      _drawLabels(canvas, projection, filteredObjects);
    }
    _drawActiveObjectGizmo(canvas, projection);
    _drawSelectedWallHandles(canvas, projection);
    _drawDraftOverlay(canvas, projection);
    final rectangle = selectionRect;
    if (rectangle != null) {
      canvas.drawRect(rectangle, Paint()..color = const Color(0x332563EB));
      canvas.drawRect(
        rectangle,
        Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFCBD5E1),
    );
  }

  List<_OutlineSegment> _buildOutlineSegments(
    RenderSceneObject object,
    RenderSceneProjection projection,
  ) {
    final authoritative = object.featureEdges
        .where((edge) => edge.isFinite)
        .map(
          (edge) => _OutlineSegment(
            a: projection.project(edge.start).screen,
            b: projection.project(edge.end).screen,
          ),
        )
        .toList(growable: false);
    if (authoritative.isNotEmpty) {
      return _stabilizeOutlineSegments(authoritative);
    }
    if (projectionMode.useProjectedBoundsOutline) {
      return _stabilizeOutlineSegments(
        _buildProjectedBoundsRectOutlineSegments(object.bounds, projection),
      );
    }

    final meshSegments = _buildVisibleMeshOutlineSegments(object, projection);
    if (meshSegments.isNotEmpty) {
      return _stabilizeOutlineSegments(meshSegments);
    }

    return _stabilizeOutlineSegments(
      _buildBoundsOutlineSegments(object.bounds, projection),
    );
  }

  /// A projected edge that is smaller than a pixel cannot be represented
  /// consistently by the rasterizer: a tiny camera change makes it land on
  /// alternating pixel samples and look like it is blinking.  Drop those
  /// unresolved passive edges and deduplicate coincident projected segments;
  /// selected geometry still remains readable through its highlight overlay.
  List<_OutlineSegment> _stabilizeOutlineSegments(
    Iterable<_OutlineSegment> source,
  ) {
    const minimumLengthPixels = 0.75;
    final seen = <String>{};
    final stable = <_OutlineSegment>[];
    for (final segment in source) {
      final dx = segment.b.dx - segment.a.dx;
      final dy = segment.b.dy - segment.a.dy;
      if (!dx.isFinite ||
          !dy.isFinite ||
          (dx * dx + dy * dy) < minimumLengthPixels * minimumLengthPixels) {
        continue;
      }
      int quantize(double value) => (value * 4.0).round();
      final first = '${quantize(segment.a.dx)}:${quantize(segment.a.dy)}';
      final second = '${quantize(segment.b.dx)}:${quantize(segment.b.dy)}';
      final key =
          first.compareTo(second) <= 0 ? '$first|$second' : '$second|$first';
      if (seen.add(key)) {
        stable.add(segment);
      }
    }
    return stable;
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

  @override
  List<_OutlineSegment> _buildProjectedBoundsRectOutlineSegments(
    RenderSceneBounds bounds,
    RenderSceneProjection projection,
  ) {
    final rect = projectBoundsRect(bounds, projection);
    if (rect.width <= 0.01 || rect.height <= 0.01) {
      return const <_OutlineSegment>[];
    }

    final topLeft = rect.topLeft;
    final topRight = rect.topRight;
    final bottomRight = rect.bottomRight;
    final bottomLeft = rect.bottomLeft;

    return <_OutlineSegment>[
      _OutlineSegment(a: topLeft, b: topRight),
      _OutlineSegment(a: topRight, b: bottomRight),
      _OutlineSegment(a: bottomRight, b: bottomLeft),
      _OutlineSegment(a: bottomLeft, b: topLeft),
    ];
  }

  @override
  bool shouldRepaint(covariant FallbackRenderScenePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.visibleKinds != visibleKinds ||
        !setEquals(oldDelegate.selectedElementIds, selectedElementIds) ||
        oldDelegate.activeElementId != activeElementId ||
        oldDelegate.selectedLevelId != selectedLevelId ||
        oldDelegate.selectionRect != selectionRect ||
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
        oldDelegate.draftWallHeightMeters != draftWallHeightMeters ||
        oldDelegate.showObjectLabels != showObjectLabels ||
        oldDelegate.showReferenceGrid != showReferenceGrid;
  }
}

/// Debug-only projection of semantic geometry supplied by the engine.
///
/// This deliberately reads only feature edges and wall axis metadata. It is a
/// diagnosis overlay, not an alternate renderer or a geometry reconstruction
/// path, so it can sit above both Flutter and Android/Filament viewports.
class RenderSceneGeometryDiagnosticsPainter extends CustomPainter {
  const RenderSceneGeometryDiagnosticsPainter({
    required this.scene,
    required this.visibleKinds,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.camera,
    required this.planCamera,
  });

  final RenderScene scene;
  final Set<String> visibleKinds;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderSceneCameraState camera;
  final RenderScenePlanCameraState planCamera;

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
      padding: FallbackRenderScenePainter.padding,
    );
    final axisPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final silhouettePaint = Paint()
      ..color = const Color(0xFF9333EA).withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final openingPaint = Paint()
      ..color = const Color(0xFF06B6D4).withValues(alpha: 0.98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    for (final object in scene.objectsForKinds(visibleKinds)) {
      for (final edge in object.featureEdges) {
        if (!edge.isFinite) continue;
        canvas.drawLine(
          projection.project(edge.start).screen,
          projection.project(edge.end).screen,
          edge.role == 'opening_contour' ? openingPaint : silhouettePaint,
        );
      }

      if (object.kindKey == 'wall') {
        final start = RenderSceneEditor.wallStartPoint(object);
        final end = RenderSceneEditor.wallEndPoint(object);
        if (start != null && end != null) {
          final a = projection.project(start).screen;
          final b = projection.project(end).screen;
          canvas.drawLine(a, b, axisPaint);
          canvas.drawCircle(a, 3.4, Paint()..color = const Color(0xFF2563EB));
          canvas.drawCircle(b, 3.4, Paint()..color = const Color(0xFF2563EB));
        }
      }

      final id = object.elementId;
      if (id != null) {
        final anchor = projection.project(object.bounds.center).screen;
        final label = TextPainter(
          text: TextSpan(
            text: '${object.kindKey} #$id',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              backgroundColor: Color(0xDDF8FAFC),
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: 130);
        label.paint(canvas, anchor + const Offset(5, 5));
      }
    }

    final legend = TextPainter(
      text: const TextSpan(
        text: 'Blue: wall axis  Purple: silhouette  Cyan: opening contour',
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          backgroundColor: Color(0xDDF8FAFC),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: math.max(0, size.width - 24));
    legend.paint(canvas, Offset(12, math.max(12, size.height - 24)));
  }

  @override
  bool shouldRepaint(RenderSceneGeometryDiagnosticsPainter oldDelegate) =>
      scene != oldDelegate.scene ||
      visibleKinds != oldDelegate.visibleKinds ||
      projectionMode != oldDelegate.projectionMode ||
      orbitProjectionStyle != oldDelegate.orbitProjectionStyle ||
      camera != oldDelegate.camera ||
      planCamera != oldDelegate.planCamera;
}

class _LayerProfileEntry {
  const _LayerProfileEntry({
    required this.materialId,
    required this.thicknessMeters,
  });

  final int materialId;
  final double thicknessMeters;
}

class _PlanWallFootprint {
  const _PlanWallFootprint({
    required this.path,
    required this.start,
    required this.end,
    required this.axis,
    required this.length,
    required this.thickness,
    required this.profile,
    required this.selected,
    required this.highlighted,
  });

  final Path path;
  final RenderScenePoint start;
  final RenderScenePoint end;
  final RenderScenePoint axis;
  final double length;
  final double thickness;
  final List<_LayerProfileEntry> profile;
  final bool selected;
  final bool highlighted;
}

class _PlanLayerBandKey {
  const _PlanLayerBandKey({
    required this.materialId,
    required this.layerIndex,
    required this.layerCount,
  });

  final int materialId;
  final int layerIndex;
  final int layerCount;

  @override
  bool operator ==(Object other) =>
      other is _PlanLayerBandKey &&
      materialId == other.materialId &&
      layerIndex == other.layerIndex &&
      layerCount == other.layerCount;

  @override
  int get hashCode => Object.hash(materialId, layerIndex, layerCount);
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
