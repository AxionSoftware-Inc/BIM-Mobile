import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_types.dart';

@immutable
class RenderSceneProjectedPoint {
  const RenderSceneProjectedPoint({
    required this.screen,
    required this.depth,
  });

  final Offset screen;
  final double depth;
}

@immutable
class RenderSceneCameraBasis {
  const RenderSceneCameraBasis({
    required this.eye,
    required this.forward,
    required this.right,
    required this.up,
  });

  final RenderScenePoint eye;
  final RenderScenePoint forward;
  final RenderScenePoint right;
  final RenderScenePoint up;
}

class RenderSceneProjection {
  RenderSceneProjection({
    required this.sceneBounds,
    required this.canvasSize,
    required this.projectionMode,
    required this.orbitProjectionStyle,
    required this.planCamera,
    required this.camera,
    required this.padding,
  }) {
    if (!projectionMode.is3D) {
      projectedBounds = Rect.fromLTWH(
        padding,
        padding,
        math.max(canvasSize.width - padding * 2, 1),
        math.max(canvasSize.height - padding * 2, 1),
      );
      screenScale = 1.0;
      screenOffset = Offset.zero;
      return;
    }

    projectedBounds = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    screenScale =
        math.max(math.min(canvasSize.width, canvasSize.height) * 0.42, 1.0);
    screenOffset = viewportCenter;
  }

  final RenderSceneBounds sceneBounds;
  final Size canvasSize;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;
  final RenderScenePlanCameraState planCamera;
  final RenderSceneCameraState camera;
  final double padding;

  late final Rect projectedBounds;
  late final double screenScale;
  late final Offset screenOffset;

  Offset get viewportCenter =>
      Offset(canvasSize.width * 0.5, canvasSize.height * 0.5);

  RenderSceneProjectedPoint project(RenderScenePoint point) {
    final raw = _projectRawPoint(point);
    return RenderSceneProjectedPoint(
      screen: projectionMode.isPlanar
          ? raw.screen
          : Offset(
              screenOffset.dx + raw.screen.dx * screenScale,
              screenOffset.dy + raw.screen.dy * screenScale,
            ),
      depth: raw.depth,
    );
  }

  RenderScenePoint? unprojectPlan(Offset localPosition) {
    final descriptor = projectionMode.planarDescriptor;
    if (descriptor == null) {
      return null;
    }
    return descriptor.screenToModel(
      localPosition: localPosition,
      viewportCenter: viewportCenter,
      cameraState: planCamera,
    );
  }

  RenderSceneProjectedPoint _projectRawPoint(RenderScenePoint point) {
    final descriptor = projectionMode.planarDescriptor;
    if (descriptor != null) {
      return RenderSceneProjectedPoint(
        screen: descriptor.modelToScreen(
          point: point,
          viewportCenter: viewportCenter,
          cameraState: planCamera,
        ),
        depth: descriptor.projectDepth(point),
      );
    }

    switch (projectionMode) {
      case RenderSceneProjectionMode.isometric:
        final basis = buildCameraBasis(
          center: camera.center,
          yawRadians: camera.yawRadians,
          pitchRadians: camera.pitchRadians,
          distance: camera.distance,
        );

        final relative = subtractPoint(point, basis.eye);
        final x = dotPoint(relative, basis.right);
        final y = dotPoint(relative, basis.up);
        final depth = math.max(0.001, dotPoint(relative, basis.forward));

        if (orbitProjectionStyle ==
            RenderSceneOrbitProjectionStyle.orthographic) {
          return RenderSceneProjectedPoint(
            screen: Offset(x * camera.zoomScale, -y * camera.zoomScale),
            depth: depth,
          );
        }

        final perspectiveScale = camera.zoomScale / depth;
        return RenderSceneProjectedPoint(
          screen: Offset(x * perspectiveScale, -y * perspectiveScale),
          depth: depth,
        );
      case RenderSceneProjectionMode.topDown:
      case RenderSceneProjectionMode.northElevation:
      case RenderSceneProjectionMode.southElevation:
      case RenderSceneProjectionMode.eastElevation:
      case RenderSceneProjectionMode.westElevation:
        throw StateError('Planar projection modes must resolve via descriptor.');
    }
  }
}

RenderSceneObject? pickObjectAt({
  required RenderScene scene,
  required Size size,
  required Offset localPosition,
  required RenderSceneProjectionMode projectionMode,
  required RenderSceneOrbitProjectionStyle orbitProjectionStyle,
  required RenderScenePlanCameraState planCamera,
  required RenderSceneCameraState camera,
  required Set<String> visibleKinds,
  required double padding,
}) {
  final objects = scene.objectsForKinds(visibleKinds);
  if (objects.isEmpty) {
    return null;
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

  RenderSceneObject? bestObject;
  var bestScore = double.infinity;
  var bestDepth = -double.infinity;
  var bestPriority = 1 << 30;

  for (final object in objects) {
    final hit = _pickScoreForObject(
      object: object,
      localPosition: localPosition,
      projection: projection,
    );
    if (hit == null) {
      continue;
    }

    final centerDistance = hit;
    final objectDepth = projectObjectDepth(object.bounds, projection);
    final score = centerDistance - objectDepth * 0.0001;
    final priority = _selectionPriorityForKind(object.kindKey);

    if (priority < bestPriority ||
        (priority == bestPriority &&
            (score < bestScore ||
                (score == bestScore && objectDepth > bestDepth)))) {
      bestPriority = priority;
      bestScore = score;
      bestDepth = objectDepth;
      bestObject = object;
    }
  }

  return bestObject;
}

double? _pickScoreForObject({
  required RenderSceneObject object,
  required Offset localPosition,
  required RenderSceneProjection projection,
}) {
  final mesh = object.mesh;
  double? bestTriangleDistance;
  if (mesh.hasGeometry) {
    for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
      final a = safeMeshPoint(mesh.positions, mesh.indices[i]);
      final b = safeMeshPoint(mesh.positions, mesh.indices[i + 1]);
      final c = safeMeshPoint(mesh.positions, mesh.indices[i + 2]);
      if (a == null || b == null || c == null) {
        continue;
      }
      final pa = projection.project(a).screen;
      final pb = projection.project(b).screen;
      final pc = projection.project(c).screen;
      final triangleBounds = Rect.fromPoints(pa, pb).expandToInclude(Rect.fromPoints(pa, pc));
      if (!triangleBounds.inflate(6).contains(localPosition)) {
        continue;
      }
      if (_pointInTriangle(localPosition, pa, pb, pc)) {
        final centroid = Offset(
          (pa.dx + pb.dx + pc.dx) / 3.0,
          (pa.dy + pb.dy + pc.dy) / 3.0,
        );
        final distance = (centroid - localPosition).distance;
        if (bestTriangleDistance == null || distance < bestTriangleDistance) {
          bestTriangleDistance = distance;
        }
      }
    }
  }
  if (bestTriangleDistance != null) {
    return bestTriangleDistance;
  }

  final rect = projectBoundsRect(object.bounds, projection).inflate(14);
  if (!rect.contains(localPosition)) {
    return null;
  }
  return (rect.center - localPosition).distance + 1000.0;
}

int _selectionPriorityForKind(String kind) {
  switch (normalizePointLikeKind(kind)) {
    case 'door':
    case 'window':
      return 0;
    case 'wall':
      return 1;
    case 'column':
    case 'beam':
    case 'stair':
      return 2;
    case 'roof':
    case 'slab':
    case 'floor':
    case 'ceiling':
      return 3;
    case 'room':
      return 4;
    default:
      return 5;
  }
}

String normalizePointLikeKind(String value) {
  return value.trim().toLowerCase().replaceAll(' ', '_');
}

bool _pointInTriangle(Offset p, Offset a, Offset b, Offset c) {
  final denominator =
      ((b.dy - c.dy) * (a.dx - c.dx)) + ((c.dx - b.dx) * (a.dy - c.dy));
  if (denominator.abs() <= 1e-9) {
    return false;
  }
  final alpha =
      (((b.dy - c.dy) * (p.dx - c.dx)) + ((c.dx - b.dx) * (p.dy - c.dy))) /
          denominator;
  final beta =
      (((c.dy - a.dy) * (p.dx - c.dx)) + ((a.dx - c.dx) * (p.dy - c.dy))) /
          denominator;
  final gamma = 1.0 - alpha - beta;
  const epsilon = -1e-6;
  return alpha >= epsilon && beta >= epsilon && gamma >= epsilon;
}

Rect projectBoundsRect(
    RenderSceneBounds bounds, RenderSceneProjection projection) {
  final corners = boundsCorners(bounds);
  final projected = corners.map(projection.project).toList(growable: false);

  var minX = projected.first.screen.dx;
  var minY = projected.first.screen.dy;
  var maxX = projected.first.screen.dx;
  var maxY = projected.first.screen.dy;

  for (final point in projected.skip(1)) {
    minX = math.min(minX, point.screen.dx);
    minY = math.min(minY, point.screen.dy);
    maxX = math.max(maxX, point.screen.dx);
    maxY = math.max(maxY, point.screen.dy);
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double projectObjectDepth(
    RenderSceneBounds bounds, RenderSceneProjection projection) {
  final corners = boundsCorners(bounds);
  var depth = 0.0;
  for (final corner in corners) {
    depth += projection.project(corner).depth;
  }
  return depth / corners.length;
}

List<RenderScenePoint> boundsCorners(RenderSceneBounds bounds) {
  return <RenderScenePoint>[
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.min.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.max.x, y: bounds.max.y, z: bounds.max.z),
    RenderScenePoint(x: bounds.min.x, y: bounds.max.y, z: bounds.max.z),
  ];
}

RenderSceneCameraBasis buildCameraBasis({
  required RenderScenePoint center,
  required double yawRadians,
  required double pitchRadians,
  required double distance,
}) {
  final eye = RenderScenePoint(
    x: center.x + distance * math.cos(pitchRadians) * math.cos(yawRadians),
    y: center.y + distance * math.cos(pitchRadians) * math.sin(yawRadians),
    z: center.z + distance * math.sin(pitchRadians),
  );

  final forward = normalizePoint(subtractPoint(center, eye));

  const worldUp = RenderScenePoint(x: 0, y: 0, z: 1);
  var right = crossPoint(forward, worldUp);
  if (lengthPoint(right) < 1e-8) {
    right = const RenderScenePoint(x: 1, y: 0, z: 0);
  } else {
    right = normalizePoint(right);
  }

  final up = normalizePoint(crossPoint(right, forward));

  return RenderSceneCameraBasis(
    eye: eye,
    forward: forward,
    right: right,
    up: up,
  );
}

RenderScenePoint addPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
}

RenderScenePoint subtractPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z);
}

RenderScenePoint scalePoint(RenderScenePoint point, double scale) {
  return RenderScenePoint(
    x: point.x * scale,
    y: point.y * scale,
    z: point.z * scale,
  );
}

double dotPoint(RenderScenePoint a, RenderScenePoint b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

RenderScenePoint crossPoint(RenderScenePoint a, RenderScenePoint b) {
  return RenderScenePoint(
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  );
}

double lengthPoint(RenderScenePoint point) {
  return math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z);
}

RenderScenePoint normalizePoint(RenderScenePoint point) {
  final length = lengthPoint(point);
  if (length <= 1e-9) {
    return const RenderScenePoint(x: 0, y: 0, z: 1);
  }

  return RenderScenePoint(
    x: point.x / length,
    y: point.y / length,
    z: point.z / length,
  );
}

double triangleArea(Offset a, Offset b, Offset c) {
  return ((b.dx - a.dx) * (c.dy - a.dy)) - ((b.dy - a.dy) * (c.dx - a.dx));
}

RenderScenePoint? safeMeshPoint(List<RenderScenePoint> positions, int index) {
  if (index < 0 || index >= positions.length) {
    return null;
  }

  final point = positions[index];
  if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
    return null;
  }

  return point;
}

List<List<RenderScenePoint>> fallbackBoxTriangles(RenderSceneBounds bounds) {
  final corners = boundsCorners(bounds);

  return <List<RenderScenePoint>>[
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
  ];
}
