import 'package:flutter/material.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_types.dart';

/// Presentation-only view tree for the Project Browser.
///
/// Navigation policy, engine calls, and scene mutation deliberately remain in
/// the host feature. This widget receives only immutable scene data and
/// callbacks, so adding a browser view cannot couple it to FFI or viewport
/// internals.
class ProjectBrowserViews extends StatelessWidget {
  const ProjectBrowserViews({
    super.key,
    required this.scene,
    required this.projectionMode,
    required this.activeLevelId,
    this.activeSectionName,
    required this.onOpen3d,
    required this.onOpenFloorPlan,
    required this.onOpenElevation,
    required this.onOpenSection,
  });

  final RenderScene scene;
  final RenderSceneProjectionMode projectionMode;
  final int? activeLevelId;
  final String? activeSectionName;
  final Future<void> Function() onOpen3d;
  final Future<void> Function(int levelId) onOpenFloorPlan;
  final Future<void> Function(RenderSceneProjectionMode mode) onOpenElevation;
  final Future<void> Function(RenderSceneSection section) onOpenSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = projectBrowserSections(scene);

    Widget viewRow({
      required String label,
      required bool selected,
      required IconData icon,
      required Future<void> Function() onTap,
    }) =>
        Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            minLeadingWidth: 24,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(icon, size: 18),
            selected: selected,
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: onTap,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Views', style: theme.textTheme.labelLarge),
          ),
          viewRow(
            label: '3D View',
            icon: Icons.view_in_ar_outlined,
            selected: projectionMode == RenderSceneProjectionMode.isometric,
            onTap: onOpen3d,
          ),
          _ProjectBrowserGroup(
            storageKey: 'project-browser-floor-plans',
            icon: Icons.map_outlined,
            title: const Text('Floor Plans'),
            children: <Widget>[
              for (final level in scene.levels)
                viewRow(
                  label: '${level.name} plan',
                  icon: Icons.grid_4x4_outlined,
                  selected:
                      projectionMode == RenderSceneProjectionMode.topDown &&
                          activeLevelId == level.levelId,
                  onTap: () => onOpenFloorPlan(level.levelId),
                ),
            ],
          ),
          _ProjectBrowserGroup(
            storageKey: 'project-browser-elevations',
            icon: Icons.stacked_line_chart_outlined,
            title: const Text('Elevations'),
            children: <Widget>[
              for (final mode in <RenderSceneProjectionMode>[
                RenderSceneProjectionMode.northElevation,
                RenderSceneProjectionMode.southElevation,
                RenderSceneProjectionMode.eastElevation,
                RenderSceneProjectionMode.westElevation,
              ])
                viewRow(
                  label: mode.shortLabel,
                  icon: Icons.straighten,
                  selected: projectionMode == mode,
                  onTap: () => onOpenElevation(mode),
                ),
            ],
          ),
          _ProjectBrowserGroup(
            storageKey: 'project-browser-sections',
            icon: Icons.content_cut_outlined,
            title: Text('Sections (${sections.length})'),
            children: <Widget>[
              for (final section in sections)
                viewRow(
                  label: section.name,
                  icon: Icons.straighten,
                  selected: activeSectionName == section.name,
                  onTap: () => onOpenSection(section),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectBrowserGroup extends StatelessWidget {
  const _ProjectBrowserGroup({
    required this.storageKey,
    required this.icon,
    required this.title,
    required this.children,
  });

  final String storageKey;
  final IconData icon;
  final Widget title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: PageStorageKey<String>(storageKey),
          dense: true,
          visualDensity: VisualDensity.compact,
          initiallyExpanded: false,
          leading: Icon(icon, size: 18),
          title: title,
          children: children,
        ),
      );
}

List<RenderSceneSection> projectBrowserSections(RenderScene scene) {
  if (scene.sections.isNotEmpty) return scene.sections;
  final bounds = scene.bounds;
  final centerX = (bounds.min.x + bounds.max.x) * 0.5;
  final centerY = (bounds.min.y + bounds.max.y) * 0.5;
  final width = (bounds.max.x - bounds.min.x).abs();
  final depth = (bounds.max.y - bounds.min.y).abs();
  final span = width > depth ? width : depth;
  // Run beyond the shell so exterior wall cuts are never lost to numerical
  // endpoint tolerances. This matches the generated native default sections.
  final margin = span * 0.08 < 1.0 ? 1.0 : span * 0.08;
  return <RenderSceneSection>[
    RenderSceneSection(
      name: 'Section A',
      start: RenderScenePoint(x: bounds.min.x - margin, y: centerY, z: 0),
      end: RenderScenePoint(x: bounds.max.x + margin, y: centerY, z: 0),
    ),
    RenderSceneSection(
      name: 'Section B',
      start: RenderScenePoint(x: centerX, y: bounds.min.y - margin, z: 0),
      end: RenderScenePoint(x: centerX, y: bounds.max.y + margin, z: 0),
    ),
  ];
}
