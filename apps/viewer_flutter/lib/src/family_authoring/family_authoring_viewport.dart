import 'dart:async';

import 'package:flutter/material.dart';

import '../render_scene_viewport.dart';
import 'family_document.dart';
import 'family_geometry.dart';
import 'family_render_scene_adapter.dart';

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
    this.onFinalFeatureSelected,
    this.showDiagnostics = false,
  });

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final FamilyEvaluatedMesh mesh;
  final ValueChanged<String?>? onFinalFeatureSelected;
  final bool showDiagnostics;

  @override
  State<FamilyAuthoringViewport> createState() => _FamilyAuthoringViewportState();
}

class _FamilyAuthoringViewportState extends State<FamilyAuthoringViewport> {
  late final RenderSceneViewportController _controller;
  String? _sceneKey;

  @override
  void initState() {
    super.initState();
    _controller = RenderSceneViewportController(visibleKinds: <String>{'proxy'});
    unawaited(_configureAndLoad(resetView: true));
  }

  @override
  void didUpdateWidget(covariant FamilyAuthoringViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _keyFor(widget);
    if (_sceneKey != nextKey) {
      unawaited(_configureAndLoad(resetView: false));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _configureAndLoad({required bool resetView}) async {
    final key = _keyFor(widget);
    _sceneKey = key;
    await _controller.setProjectionMode(RenderSceneProjectionMode.isometric);
    await _controller.setOrbitProjectionStyle(
      RenderSceneOrbitProjectionStyle.perspective,
    );
    await _controller.setDisplayStyle(RenderSceneDisplayStyle.shaded);
    final scene = FamilyRenderSceneAdapter.build(
      widget.document,
      widget.type,
      mesh: widget.mesh,
    );
    await _controller.updateRenderScene(
      scene,
      resetView: resetView || _controller.scene == null,
      visibleKinds: const <String>{'proxy'},
    );
  }

  String _keyFor(FamilyAuthoringViewport widget) =>
      '${widget.type.id}\u001f${widget.document.toJsonText()}';

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
                final featureId = object.metadata['family_feature_id']?.toString();
                widget.onFinalFeatureSelected?.call(featureId);
              },
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: _ViewportBadge(
              label: 'Project viewport · Family preview',
              icon: Icons.view_in_ar_outlined,
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
                    final next = _controller.displayStyle == RenderSceneDisplayStyle.shaded
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
