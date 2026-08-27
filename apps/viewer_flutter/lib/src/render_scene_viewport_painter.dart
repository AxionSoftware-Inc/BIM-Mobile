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
      final baseColor = _kindColor(object.kindKey);
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
    if (projectionMode.useProjectedBoundsOutline) {
      return _buildProjectedBoundsRectOutlineSegments(
          object.bounds, projection);
    }

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
