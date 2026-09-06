import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render_scene_models.dart';
import '../render_scene_viewport.dart';
import '../tools/plan_sketch_geometry.dart';
import 'family_document.dart';

/// 2D Family sketch editor hosted by the same RenderScene viewport used by the
/// project plan workspace. Camera, pan/zoom, hit testing and snapping all reuse
/// the project authoring contracts; Family owns only its local sketch points.
class FamilySketchViewport extends StatefulWidget {
  const FamilySketchViewport({
    super.key,
    required this.sketch,
    required this.onAddPoint,
    required this.onMovePoint,
  });

  final FamilySketch sketch;
  final ValueChanged<FamilySketchPoint> onAddPoint;
  final void Function(int index, FamilySketchPoint point) onMovePoint;

  @override
  State<FamilySketchViewport> createState() => _FamilySketchViewportState();
}

class _FamilySketchViewportState extends State<FamilySketchViewport> {
  static const double _familyGridStepMeters = 0.05;
  static const double _endpointToleranceMeters = 0.12;

  late final RenderSceneViewportController _controller;
  int? _dragPointIndex;
  String? _sceneKey;
  bool _snapEnabled = true;
  String? _snapHint;

  @override
  void initState() {
    super.initState();
    _controller = RenderSceneViewportController(
      visibleKinds: <String>{'proxy'},
      backend: RenderSceneViewportBackend.fallback,
    );
    unawaited(_load(resetView: true));
  }

  @override
  void didUpdateWidget(covariant FamilySketchViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = widget.sketch.toJson().toString();
    if (_sceneKey != key) unawaited(_load(resetView: false));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load({required bool resetView}) async {
    final key = widget.sketch.toJson().toString();
    _sceneKey = key;
    await _controller.setProjectionMode(RenderSceneProjectionMode.topDown);
    await _controller.setDisplayStyle(RenderSceneDisplayStyle.solid);
    final scene = _buildScene(widget.sketch);
    if (!mounted || _sceneKey != key) return;
    await _controller.updateRenderScene(
      scene,
      resetView: resetView || _controller.scene == null,
      visibleKinds: const <String>{'proxy'},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RenderSceneViewport(
            controller: _controller,
            interactionMode: RenderSceneInteractionMode.select,
            authoringPickKinds: const <String>{'proxy'},
            onSceneTap: (details) {
              final pointIndex = _pointIndex(details.pickedObject);
              if (pointIndex != null) {
                unawaited(
                  _controller.selectElement(details.pickedObject?.elementIdRaw),
                );
                return;
              }
              final point = details.modelPoint;
              if (point != null && !widget.sketch.closed) {
                final resolved = _resolvePoint(point);
                widget.onAddPoint(
                  FamilySketchPoint(x: resolved.point.x, y: resolved.point.y),
                );
                _showSnapHint(resolved.hint);
              }
            },
            onSceneDragStart: (details) {
              _dragPointIndex = _pointIndex(details.pickedObject);
              _showSnapHint(null);
            },
            onSceneDragUpdate: (details) {
              final index = _dragPointIndex;
              final point = details.modelPoint;
              if (index == null || point == null) return;
              final resolved = _resolvePoint(point, movingIndex: index);
              widget.onMovePoint(
                index,
                FamilySketchPoint(x: resolved.point.x, y: resolved.point.y),
              );
              _showSnapHint(resolved.hint);
            },
            onSceneDragEnd: (_) {
              _dragPointIndex = null;
              Future<void>.delayed(const Duration(milliseconds: 700), () {
                if (mounted && _dragPointIndex == null) _showSnapHint(null);
              });
            },
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                'Project plan viewport · tap to draw · drag points · pinch to zoom',
              ),
            ),
          ),
        ),
        if (_snapHint != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .inverseSurface
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    _snapHint!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          top: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilterChip(
                selected: _snapEnabled,
                avatar: Icon(
                  _snapEnabled ? Icons.magnet_on_outlined : Icons.magnet_off_outlined,
                  size: 18,
                ),
                label: Text(_snapEnabled ? 'Snap 50 mm' : 'Snap off'),
                onSelected: (enabled) {
                  setState(() {
                    _snapEnabled = enabled;
                    _snapHint = enabled ? 'Grid snap · 50 mm' : null;
                  });
                },
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Fit sketch',
                onPressed: () => unawaited(_controller.fitCamera()),
                icon: const Icon(Icons.center_focus_strong_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSnapHint(String? hint) {
    if (!mounted || hint == _snapHint) return;
    setState(() => _snapHint = hint);
  }

  ({RenderScenePoint point, String? hint}) _resolvePoint(
    RenderScenePoint raw, {
    int? movingIndex,
  }) {
    if (!_snapEnabled) return (point: raw, hint: null);

    final points = widget.sketch.points;
    RenderScenePoint? reference;
    if (movingIndex == null) {
      if (points.isNotEmpty) {
        final last = points.last;
        reference = RenderScenePoint(x: last.x, y: last.y, z: 0);
      }
    } else if (points.length > 1) {
      final referenceIndex = movingIndex > 0 ? movingIndex - 1 : 1;
      final item = points[referenceIndex];
      reference = RenderScenePoint(x: item.x, y: item.y, z: 0);
    }

    final candidates = <RenderScenePoint>[
      for (var index = 0; index < points.length; index++)
        if (index != movingIndex)
          RenderScenePoint(x: points[index].x, y: points[index].y, z: 0),
    ];
    final resolved = PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: RenderScenePoint(x: raw.x, y: raw.y, z: 0),
      referenceStart: reference,
      candidatePoints: candidates,
      useGridSnap: true,
      gridStepMeters: _familyGridStepMeters,
      constrainOrtho: true,
      endpointToleranceMeters: _endpointToleranceMeters,
    );

    String hint = 'Grid · 50 mm';
    for (final candidate in candidates) {
      if (PlanSketchGeometry.planDistance(resolved, candidate) <= 1e-7) {
        hint = 'Endpoint snap';
        break;
      }
    }
    if (reference != null && hint != 'Endpoint snap') {
      if ((resolved.y - reference.y).abs() <= 1e-7 &&
          (resolved.x - reference.x).abs() > 1e-7) {
        hint = 'Horizontal';
      } else if ((resolved.x - reference.x).abs() <= 1e-7 &&
          (resolved.y - reference.y).abs() > 1e-7) {
        hint = 'Vertical';
      }
    }
    return (point: resolved, hint: hint);
  }

  int? _pointIndex(RenderSceneObject? object) {
    final raw = object?.metadata['family_sketch_point_index'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  static RenderScene _buildScene(FamilySketch sketch) {
    final objects = <RenderSceneObject>[];
    final points = sketch.points;
    final extent = _extent(points);
    final marker = math.max(0.035, extent * 0.018);
    final lineWidth = math.max(0.008, extent * 0.004);

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final half = marker;
      final mesh = RenderSceneMesh(
        positions: <RenderScenePoint>[
          RenderScenePoint(x: point.x - half, y: point.y - half, z: 0),
          RenderScenePoint(x: point.x + half, y: point.y - half, z: 0),
          RenderScenePoint(x: point.x + half, y: point.y + half, z: 0),
          RenderScenePoint(x: point.x - half, y: point.y + half, z: 0),
        ],
        indices: const <int>[0, 1, 2, 0, 2, 3],
        normals: null,
      );
      objects.add(
        RenderSceneObject(
          elementId: 930000 + index,
          kind: 'proxy',
          levelId: 1,
          selectable: true,
          visibleByDefault: true,
          revision: index,
          bounds: _meshBounds(mesh),
          mesh: mesh,
          materialCategory: 'generic',
          metadata: <String, Object?>{
            'family_sketch_point_index': index,
            'family_sketch_point_id': point.id,
          },
        ),
      );
    }

    final segmentCount =
        sketch.closed ? points.length : math.max(0, points.length - 1);
    for (var index = 0; index < segmentCount; index++) {
      final a = points[index];
      final b = points[(index + 1) % points.length];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length <= 1e-9) continue;
      final nx = -dy / length * lineWidth;
      final ny = dx / length * lineWidth;
      final mesh = RenderSceneMesh(
        positions: <RenderScenePoint>[
          RenderScenePoint(x: a.x + nx, y: a.y + ny, z: -0.001),
          RenderScenePoint(x: a.x - nx, y: a.y - ny, z: -0.001),
          RenderScenePoint(x: b.x - nx, y: b.y - ny, z: -0.001),
          RenderScenePoint(x: b.x + nx, y: b.y + ny, z: -0.001),
        ],
        indices: const <int>[0, 1, 2, 0, 2, 3],
        normals: null,
      );
      objects.add(
        RenderSceneObject(
          elementId: 940000 + index,
          kind: 'proxy',
          levelId: 1,
          selectable: false,
          visibleByDefault: true,
          revision: index,
          bounds: _meshBounds(mesh),
          mesh: mesh,
          materialCategory: 'generic',
        ),
      );
    }

    final bounds = objects.isEmpty
        ? RenderSceneBounds(
            min: const RenderScenePoint(x: -1, y: -1, z: -0.1),
            max: const RenderScenePoint(x: 1, y: 1, z: 0.1),
          )
        : RenderSceneBounds.union(objects.map((object) => object.bounds));
    final vertexCount = objects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.positions.length,
    );
    final indexCount = objects.fold<int>(
      0,
      (sum, object) => sum + object.mesh.indices.length,
    );
    final payload = <String, Object?>{
      'scene_version': 1,
      'units': 'meters',
      'coordinate_system': 'X/Y plan, Z up',
      'object_count': objects.length,
      'vertex_count': vertexCount,
      'index_count': indexCount,
      'bounds': bounds.toJson(),
      'levels': <Object?>[
        const RenderSceneLevel(
          levelId: 1,
          name: 'Sketch plane',
          elevationMeters: 0,
          defaultWallHeightMeters: 3,
        ).toJson(),
      ],
      'materials': const <Object?>[],
      'sections': const <Object?>[],
      'objects': objects.map((object) => object.toJson()).toList(),
    };
    final parsed = parseRenderSceneJson(
      jsonEncode(payload),
      source: 'family-sketch:${sketch.id}',
    );
    return parsed.scene!;
  }

  static double _extent(List<FamilySketchPoint> points) {
    if (points.isEmpty) return 2;
    var minX = points.first.x;
    var maxX = minX;
    var minY = points.first.y;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    return math.max(1.0, math.max(maxX - minX, maxY - minY));
  }

  static RenderSceneBounds _meshBounds(RenderSceneMesh mesh) {
    final points = mesh.positions;
    if (points.isEmpty) return RenderSceneBounds.zero();
    var minX = points.first.x;
    var maxX = minX;
    var minY = points.first.y;
    var maxY = minY;
    var minZ = points.first.z;
    var maxZ = minZ;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
      minZ = math.min(minZ, point.z);
      maxZ = math.max(maxZ, point.z);
    }
    return RenderSceneBounds(
      min: RenderScenePoint(x: minX, y: minY, z: minZ),
      max: RenderScenePoint(x: maxX, y: maxY, z: maxZ),
    );
  }
}
