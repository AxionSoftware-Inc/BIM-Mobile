import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render_scene_viewport.dart';
import 'family_authoring_scene_builder.dart';
import 'family_document.dart';
import 'family_geometry.dart';
import 'family_render_scene_adapter.dart';

enum FamilyAuthoringViewportMode { result, pickFeatures }

enum FamilyGizmoMode { none, move, rotate, scale, extrude, revolve }

enum FamilyGizmoAxis { x, y, z, rotation, scale }

/// Family viewport host that deliberately reuses the production project
/// RenderScene viewport. Family Authoring owns only geometry/document state;
/// orbit, pinch, pan, selection, native Filament and fallback rendering remain
/// one shared implementation with the project workspace.
class FamilyAuthoringViewport extends StatefulWidget {
  const FamilyAuthoringViewport({
    super.key,
    required this.document,
    required this.type,
    required this.mesh,
    this.mode = FamilyAuthoringViewportMode.result,
    this.candidateFeatureIds = const <String>{},
    this.selectedFeatureIds = const <String>{},
    this.gizmoFeatureId,
    this.gizmoMode = FamilyGizmoMode.none,
    this.onFeatureSelected,
    this.onFinalFeatureSelected,
    this.onGizmoBegin,
    this.onGizmoChanged,
    this.onGizmoEnd,
    this.prompt,
    this.showDiagnostics = false,
  });

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final FamilyEvaluatedMesh mesh;
  final FamilyAuthoringViewportMode mode;
  final Set<String> candidateFeatureIds;
  final Set<String> selectedFeatureIds;
  final String? gizmoFeatureId;
  final FamilyGizmoMode gizmoMode;
  final ValueChanged<String?>? onFeatureSelected;

  /// Backward-compatible alias used by older editor shells.
  final ValueChanged<String?>? onFinalFeatureSelected;
  final ValueChanged<FamilyGizmoAxis>? onGizmoBegin;
  final void Function(FamilyGizmoAxis axis, double delta)? onGizmoChanged;
  final ValueChanged<FamilyGizmoAxis>? onGizmoEnd;
  final String? prompt;
  final bool showDiagnostics;

  @override
  State<FamilyAuthoringViewport> createState() => _FamilyAuthoringViewportState();
}

class _FamilyAuthoringViewportState extends State<FamilyAuthoringViewport> {
  late final RenderSceneViewportController _controller;
  String? _sceneKey;
  String? _lastReportedFeatureId;

  @override
  void initState() {
    super.initState();
    _controller = RenderSceneViewportController(visibleKinds: <String>{'proxy'});
    _controller.addListener(_handleControllerChanged);
    unawaited(_configureAndLoad(resetView: true));
  }

  @override
  void didUpdateWidget(covariant FamilyAuthoringViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget);
    if (_sceneKey != nextKey) {
      unawaited(_configureAndLoad(resetView: false));
    } else if (oldWidget.selectedFeatureIds != widget.selectedFeatureIds) {
      unawaited(_syncSelection());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final scene = _controller.scene;
    final active = _controller.activeElementId;
    String? featureId;
    if (scene != null && active != null) {
      final object = scene.objectByStableId(active);
      featureId = FamilyAuthoringSceneBuilder.featureIdForObject(object);
    }
    if (featureId != null && featureId != _lastReportedFeatureId) {
      _lastReportedFeatureId = featureId;
      widget.onFeatureSelected?.call(featureId);
      widget.onFinalFeatureSelected?.call(featureId);
    }
    if (mounted) setState(() {});
  }

  Future<void> _configureAndLoad({required bool resetView}) async {
    final key = _keyFor(widget);
    _sceneKey = key;
    await _controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    await _controller.setOrbitProjectionStyle(
      RenderSceneOrbitProjectionStyle.perspective,
    );
    await _controller.setDisplayStyle(RenderSceneDisplayStyle.shaded);

    final scene = widget.mode == FamilyAuthoringViewportMode.pickFeatures
        ? await FamilyAuthoringSceneBuilder.buildCandidates(
            widget.document,
            widget.type,
            featureIds: widget.candidateFeatureIds,
          )
        : FamilyRenderSceneAdapter.build(
            widget.document,
            widget.type,
            mesh: widget.mesh,
          );
    if (!mounted || _sceneKey != key) return;
    await _controller.updateRenderScene(
      scene,
      resetView: resetView || _controller.scene == null,
      visibleKinds: const <String>{'proxy'},
    );
    await _syncSelection();
  }

  Future<void> _syncSelection() async {
    final scene = _controller.scene;
    if (scene == null) return;
    final ids = <String>{};
    String? active;
    for (final object in scene.objects) {
      final featureId = FamilyAuthoringSceneBuilder.featureIdForObject(object);
      if (featureId != null && widget.selectedFeatureIds.contains(featureId)) {
        final elementId = object.elementIdRaw;
        if (elementId != null) {
          ids.add(elementId);
          active ??= elementId;
        }
      }
    }
    if (ids.isEmpty) {
      await _controller.selectElements(const <String>{});
    } else {
      await _controller.selectElements(ids, activeElementId: active);
    }
  }

  String _keyFor(FamilyAuthoringViewport widget) {
    final candidates = widget.candidateFeatureIds.toList()..sort();
    return '${widget.type.id}\u001f${widget.mode.name}\u001f${candidates.join(',')}\u001f'
        '${widget.document.toJsonText()}';
  }

  RenderSceneObject? get _gizmoObject {
    final featureId = widget.gizmoFeatureId;
    final scene = _controller.scene;
    if (featureId == null || scene == null) return null;
    for (final object in scene.objects) {
      if (FamilyAuthoringSceneBuilder.featureIdForObject(object) == featureId) {
        return object;
      }
    }
    // Result mode has a single object whose metadata points at the final
    // feature. It is still the correct gizmo anchor for a draft operation.
    if (scene.objects.length == 1) return scene.objects.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RenderSceneViewport(
              controller: _controller,
              interactionMode: RenderSceneInteractionMode.select,
              authoringPickKinds: const <String>{'proxy'},
              showDiagnostics: widget.showDiagnostics,
              onSceneTap: (details) {
                final object = details.pickedObject;
                if (object == null) return;
                unawaited(_controller.selectElement(object.elementIdRaw));
                final featureId =
                    FamilyAuthoringSceneBuilder.featureIdForObject(object);
                if (featureId != null) {
                  _lastReportedFeatureId = featureId;
                  widget.onFeatureSelected?.call(featureId);
                  widget.onFinalFeatureSelected?.call(featureId);
                }
              },
            ),
          ),
          if (widget.gizmoMode != FamilyGizmoMode.none && _gizmoObject != null)
            Positioned.fill(
              child: _FamilyViewportGizmo(
                controller: _controller,
                object: _gizmoObject!,
                mode: widget.gizmoMode,
                onBegin: widget.onGizmoBegin,
                onChanged: widget.onGizmoChanged,
                onEnd: widget.onGizmoEnd,
              ),
            ),
          Positioned(
            left: 12,
            top: 12,
            child: _ViewportBadge(
              label: widget.mode == FamilyAuthoringViewportMode.pickFeatures
                  ? 'Pick a solid in the viewport'
                  : 'Project viewport · Family',
              icon: widget.mode == FamilyAuthoringViewportMode.pickFeatures
                  ? Icons.touch_app_outlined
                  : Icons.view_in_ar_outlined,
            ),
          ),
          if (widget.prompt?.trim().isNotEmpty == true)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .inverseSurface
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Text(
                        widget.prompt!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
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
                IconButton.filledTonal(
                  tooltip: 'Fit family',
                  onPressed: () => unawaited(_controller.fitCamera()),
                  icon: const Icon(Icons.center_focus_strong_outlined),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Solid / shaded',
                  onPressed: () {
                    final next =
                        _controller.displayStyle == RenderSceneDisplayStyle.shaded
                            ? RenderSceneDisplayStyle.solid
                            : RenderSceneDisplayStyle.shaded;
                    unawaited(_controller.setDisplayStyle(next));
                  },
                  icon: const Icon(Icons.contrast_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyViewportGizmo extends StatefulWidget {
  const _FamilyViewportGizmo({
    required this.controller,
    required this.object,
    required this.mode,
    this.onBegin,
    this.onChanged,
    this.onEnd,
  });

  final RenderSceneViewportController controller;
  final RenderSceneObject object;
  final FamilyGizmoMode mode;
  final ValueChanged<FamilyGizmoAxis>? onBegin;
  final void Function(FamilyGizmoAxis axis, double delta)? onChanged;
  final ValueChanged<FamilyGizmoAxis>? onEnd;

  @override
  State<_FamilyViewportGizmo> createState() => _FamilyViewportGizmoState();
}

class _FamilyViewportGizmoState extends State<_FamilyViewportGizmo> {
  final Map<FamilyGizmoAxis, double> _accumulated = <FamilyGizmoAxis, double>{};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final scene = widget.controller.scene;
        if (scene == null || size.isEmpty) return const SizedBox.shrink();
        final projection = RenderSceneProjection(
          sceneBounds: scene.bounds,
          canvasSize: size,
          projectionMode: widget.controller.projectionMode,
          orbitProjectionStyle: widget.controller.orbitProjectionStyle,
          planCamera: widget.controller.planCamera,
          camera: widget.controller.camera,
          padding: 0,
        );
        final center3 = widget.object.bounds.center;
        final center = projection.project(center3).screen;

        if (widget.mode == FamilyGizmoMode.move) {
          final axes = <(FamilyGizmoAxis, String, RenderScenePoint, Color)>[
            (
              FamilyGizmoAxis.x,
              'X',
              RenderScenePoint(x: center3.x + 1, y: center3.y, z: center3.z),
              Colors.red,
            ),
            (
              FamilyGizmoAxis.z,
              'Z',
              RenderScenePoint(x: center3.x, y: center3.y + 1, z: center3.z),
              Colors.blue,
            ),
            (
              FamilyGizmoAxis.y,
              'Y',
              RenderScenePoint(x: center3.x, y: center3.y, z: center3.z + 1),
              Colors.green,
            ),
          ];
          return Stack(
            children: <Widget>[
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _AxisPainter(
                    center: center,
                    axes: <_AxisVisual>[
                      for (final axis in axes)
                        _AxisVisual(
                          label: axis.$2,
                          color: axis.$4,
                          endpoint: projection.project(axis.$3).screen,
                        ),
                    ],
                  ),
                ),
              ),
              for (final axis in axes)
                _axisHandle(
                  axis: axis.$1,
                  label: axis.$2,
                  color: axis.$4,
                  center: center,
                  endpoint: projection.project(axis.$3).screen,
                ),
            ],
          );
        }

        if (widget.mode == FamilyGizmoMode.extrude) {
          final endpoint = projection.project(
            RenderScenePoint(x: center3.x, y: center3.y + 1, z: center3.z),
          ).screen;
          return Stack(
            children: <Widget>[
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _AxisPainter(
                    center: center,
                    axes: <_AxisVisual>[
                      _AxisVisual(
                        label: 'DEPTH',
                        color: Colors.blue,
                        endpoint: endpoint,
                      ),
                    ],
                  ),
                ),
              ),
              _axisHandle(
                axis: FamilyGizmoAxis.z,
                label: 'D',
                color: Colors.blue,
                center: center,
                endpoint: endpoint,
              ),
            ],
          );
        }

        if (widget.mode == FamilyGizmoMode.rotate ||
            widget.mode == FamilyGizmoMode.revolve) {
          return Stack(
            children: <Widget>[
              IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _RingPainter(center: center, radius: 58),
                ),
              ),
              Positioned(
                left: center.dx + 44,
                top: center.dy - 14,
                child: _dragHandle(
                  axis: FamilyGizmoAxis.rotation,
                  icon: Icons.rotate_right,
                  color: Colors.orange,
                  scalar: (delta) => delta.dx * 0.6,
                ),
              ),
            ],
          );
        }

        return Stack(
          children: <Widget>[
            Positioned(
              left: center.dx + 38,
              top: center.dy + 38,
              child: _dragHandle(
                axis: FamilyGizmoAxis.scale,
                icon: Icons.open_in_full,
                color: Theme.of(context).colorScheme.primary,
                scalar: (delta) => (delta.dx - delta.dy) / 140.0,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _axisHandle({
    required FamilyGizmoAxis axis,
    required String label,
    required Color color,
    required Offset center,
    required Offset endpoint,
  }) {
    final vector = endpoint - center;
    final distance = vector.distance;
    if (!distance.isFinite || distance < 8) return const SizedBox.shrink();
    final unit = vector / distance;
    final handle = center + unit * math.min(math.max(distance, 44), 82);
    return Positioned(
      left: handle.dx - 18,
      top: handle.dy - 18,
      child: _dragHandle(
        axis: axis,
        label: label,
        color: color,
        scalar: (delta) =>
            (delta.dx * unit.dx + delta.dy * unit.dy) / math.max(distance, 12),
      ),
    );
  }

  Widget _dragHandle({
    required FamilyGizmoAxis axis,
    IconData? icon,
    String? label,
    required Color color,
    required double Function(Offset delta) scalar,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _accumulated[axis] = 0;
        widget.onBegin?.call(axis);
      },
      onPanUpdate: (details) {
        final next = (_accumulated[axis] ?? 0) + scalar(details.delta);
        _accumulated[axis] = next;
        widget.onChanged?.call(axis, next);
      },
      onPanEnd: (_) => widget.onEnd?.call(axis),
      onPanCancel: () => widget.onEnd?.call(axis),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const <BoxShadow>[
            BoxShadow(blurRadius: 5, color: Color(0x55000000)),
          ],
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: Colors.white, size: 19)
            : Text(
                label ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _AxisVisual {
  const _AxisVisual({
    required this.label,
    required this.color,
    required this.endpoint,
  });

  final String label;
  final Color color;
  final Offset endpoint;
}

class _AxisPainter extends CustomPainter {
  const _AxisPainter({required this.center, required this.axes});

  final Offset center;
  final List<_AxisVisual> axes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final axis in axes) {
      final vector = axis.endpoint - center;
      if (vector.distance < 8) continue;
      final unit = vector / vector.distance;
      final end = center + unit * math.min(math.max(vector.distance, 44), 82);
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = axis.color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AxisPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.axes != axes;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}

class _ViewportBadge extends StatelessWidget {
  const _ViewportBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 17),
            const SizedBox(width: 7),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
