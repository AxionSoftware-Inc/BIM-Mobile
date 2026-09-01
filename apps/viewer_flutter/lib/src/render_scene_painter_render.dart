part of 'render_scene_viewport_painter.dart';

mixin _FallbackSceneRenderMixin {
  RenderSceneProjectionMode get projectionMode;
  RenderSceneDisplayStyle get displayStyle;
  RenderSceneCameraState get camera;
  List<_TriangleRender> _buildObjectTriangles({
    required RenderSceneObject object,
    required RenderSceneProjection projection,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
    required Map<int, Color> materialColors,
    required bool honorMaterialColors,
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
    for (var triangleIndex = 0;
        triangleIndex < rawTriangles.length;
        triangleIndex += 1) {
      final triangle = rawTriangles[triangleIndex];
      if (displayStyle != RenderSceneDisplayStyle.wireframe &&
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

      final materialId = triangleIndex < mesh.triangleMaterialIds.length
          ? mesh.triangleMaterialIds[triangleIndex]
          : null;
      final materialColor = honorMaterialColors && materialId != null
          ? materialColors[materialId]
          : null;
      rendered.add(
        _TriangleRender(
          a: a.screen,
          b: b.screen,
          c: c.screen,
          depth: (a.depth + b.depth + c.depth) / 3.0,
          fillColor: _shadeTriangleColor(
            baseColor:
                materialColor?.withValues(alpha: fillColor.a) ?? fillColor,
            triangle: triangle,
          ),
          strokeColor: _shadeTriangleColor(
            baseColor:
                materialColor?.withValues(alpha: strokeColor.a) ?? strokeColor,
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
    if (triangle.length < 3 ||
        projectionMode != RenderSceneProjectionMode.isometric) {
      return baseColor;
    }
    final normal = normalizePoint(
        crossPoint(triangle[1] - triangle[0], triangle[2] - triangle[0]));
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
    if (projectionMode != RenderSceneProjectionMode.isometric) {
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
    required RenderSceneObject object,
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (isSelected || isHighlighted) {
      return 0.84;
    }

    // Solid is a coordination view: faces must occlude one another so the
    // fallback renderer follows the native Filament contract. Preserve the
    // glass exception when metadata is available; every other solid face is
    // opaque so floors and internal walls cannot show through one another.
    if (displayStyle == RenderSceneDisplayStyle.solid) {
      if (kind == 'wall' && _isGlassWall(object)) {
        return 0.10;
      }
      return kind == 'room' ? 0.22 : 1.0;
    }

    if (projectionMode.isElevation) {
      switch (kind) {
        case 'wall':
          return 0.12;
        case 'door':
          return 0.18;
        case 'window':
          return 0.30;
        case 'room':
          return 0.0;
        default:
          return 0.10;
      }
    }

    if (projectionMode == RenderSceneProjectionMode.topDown) {
      switch (kind) {
        case 'wall':
          return 0.18;
        case 'door':
          return 0.32;
        case 'window':
          return 0.30;
        case 'room':
          return 0.05;
        case 'floor':
        case 'ceiling':
        case 'roof':
        case 'slab':
          return 0.03;
        default:
          return 0.10;
      }
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

  bool _isGlassWall(RenderSceneObject object) {
    if (object.kindKey != 'wall') {
      return false;
    }
    final values = <String>[
      object.metadata['wall_type_name']?.toString() ?? '',
      object.metadata['wall_type_category']?.toString() ?? '',
      object.materialCategory,
    ];
    return values.any((value) => value.toLowerCase().contains('glass'));
  }

  double _triangleStrokeWidth({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (isSelected || isHighlighted) {
      return 2.2;
    }
    if (projectionMode.isElevation) {
      switch (kind) {
        case 'wall':
          return 0.8;
        case 'door':
        case 'window':
          return 0.9;
        default:
          return 0.7;
      }
    }
    return 1.0;
  }

  Color _outlineColor({
    required String kind,
    required Color objectColor,
    required bool isSelected,
    required bool isHighlighted,
    required double depthWeight,
  }) {
    if (isSelected || isHighlighted) {
      return objectColor.withValues(alpha: 0.95);
    }
    if (projectionMode.isElevation) {
      final base = switch (kind) {
        'wall' => const Color(0xFF334155),
        'door' || 'window' => const Color(0xFF475569),
        'room' => const Color(0xFF64748B),
        _ => const Color(0xFF64748B),
      };
      final baseAlpha = switch (kind) {
        'wall' => 0.44 + depthWeight * 0.32,
        'door' || 'window' => 0.52 + depthWeight * 0.26,
        'room' => 0.08 + depthWeight * 0.08,
        _ => 0.22 + depthWeight * 0.22,
      };
      return base.withValues(alpha: baseAlpha.clamp(0.0, 1.0));
    }
    if (projectionMode == RenderSceneProjectionMode.topDown) {
      final base = switch (kind) {
        'wall' => const Color(0xFF0F172A),
        'door' => const Color(0xFF7C2D12),
        'window' => const Color(0xFF075985),
        'floor' || 'ceiling' || 'roof' || 'slab' => const Color(0xFF64748B),
        _ => const Color(0xFF475569),
      };
      final alpha = switch (kind) {
        'wall' => 0.92,
        'door' || 'window' => 0.84,
        'floor' || 'ceiling' || 'roof' || 'slab' => 0.32,
        _ => 0.48,
      };
      return base.withValues(alpha: alpha);
    }
    return const Color(0xFF1F2937).withValues(alpha: 0.72);
  }

  double _outlineStrokeWidth({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
  }) {
    if (isSelected) {
      return 2.0;
    }
    if (isHighlighted) {
      return 1.6;
    }
    if (projectionMode.isElevation) {
      switch (kind) {
        case 'wall':
          return 1.25;
        case 'door':
        case 'window':
          return 1.05;
        case 'room':
          return 0.6;
        default:
          return 0.85;
      }
    }
    return 1.35;
  }

  (double, double) _projectedObjectDepthRange(
    List<RenderSceneObject> objects,
    RenderSceneProjection projection,
  ) {
    if (objects.isEmpty) {
      return (0.0, 1.0);
    }
    var minDepth = double.infinity;
    var maxDepth = double.negativeInfinity;
    for (final object in objects) {
      final depth = projectObjectDepth(object.bounds, projection);
      minDepth = math.min(minDepth, depth);
      maxDepth = math.max(maxDepth, depth);
    }
    if (!minDepth.isFinite || !maxDepth.isFinite) {
      return (0.0, 1.0);
    }
    return (minDepth, maxDepth);
  }

  double _depthVisualWeight({
    required double depth,
    required double minDepth,
    required double maxDepth,
  }) {
    final span = maxDepth - minDepth;
    if (span.abs() <= 1e-9) {
      return 1.0;
    }
    final normalized = ((depth - minDepth) / span).clamp(0.0, 1.0);
    return 0.45 + normalized * 0.55;
  }

  Color _withScaledAlpha(Color color, double scale) {
    return color.withValues(alpha: (color.a * scale).clamp(0.0, 1.0));
  }

  bool _shouldDrawSolidOutline({
    required String kind,
    required bool isSelected,
    required bool isHighlighted,
    required bool denseModel,
  }) {
    if (projectionMode.isPlanar) {
      return true;
    }
    if (isSelected || isHighlighted) {
      return true;
    }
    if (denseModel) {
      return kind == 'wall' || kind == 'door' || kind == 'window';
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
}
