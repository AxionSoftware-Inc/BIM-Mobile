import 'package:flutter/material.dart';

import 'documentation/document_models.dart';
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
    required this.sheets,
    this.activeSheetId,
    required this.onCreateSheet,
    required this.onOpenSheet,
  });

  final RenderScene scene;
  final RenderSceneProjectionMode projectionMode;
  final int? activeLevelId;
  final String? activeSectionName;
  final Future<void> Function() onOpen3d;
  final Future<void> Function(int levelId) onOpenFloorPlan;
  final Future<void> Function(RenderSceneProjectionMode mode) onOpenElevation;
  final Future<void> Function(RenderSceneSection section) onOpenSection;
  final List<ProjectSheet> sheets;
  final String? activeSheetId;
  final VoidCallback onCreateSheet;
  final ValueChanged<String> onOpenSheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = projectBrowserSections(scene);

    Widget viewRow({
      required String label,
      required bool selected,
      required IconData icon,
      required Future<void> Function() onTap,
      SheetViewReference? dragView,
    }) {
      final tile = Material(
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
      if (dragView == null) return tile;
      return LongPressDraggable<SheetViewReference>(
        data: dragView,
        delay: const Duration(milliseconds: 280),
        hapticFeedbackOnStart: true,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 220,
            child: ListTile(
              dense: true,
              leading: Icon(icon, size: 18),
              title: Text(dragView.label),
              subtitle: const Text('Sheetga joylashtirish'),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      );
    }

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
            dragView: const SheetViewReference(
              id: 'view-3d-default',
              label: '3D View',
              kind: SheetViewKind.threeD,
              projectionMode: RenderSceneProjectionMode.isometric,
            ),
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
                  dragView: SheetViewReference(
                    id: 'floor-plan-${level.levelId}',
                    label: '${level.name} plan',
                    kind: SheetViewKind.floorPlan,
                    projectionMode: RenderSceneProjectionMode.topDown,
                    levelId: level.levelId,
                  ),
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
                  dragView: SheetViewReference(
                    id: 'elevation-${mode.name}',
                    label: '${mode.shortLabel} Elevation',
                    kind: SheetViewKind.elevation,
                    projectionMode: mode,
                  ),
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
                  dragView: SheetViewReference(
                    id: 'section-${section.name}',
                    label: section.name,
                    kind: SheetViewKind.section,
                    projectionMode: RenderSceneProjectionMode.northElevation,
                    section: section,
                  ),
                ),
            ],
          ),
          _ProjectBrowserGroup(
            storageKey: 'project-browser-sheets',
            icon: Icons.description_outlined,
            title: Text('Sheets (${sheets.length})'),
            children: <Widget>[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minLeadingWidth: 24,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.add_box_outlined, size: 18),
                title: const Text('New Sheet'),
                subtitle: const Text('A3 landscape'),
                onTap: onCreateSheet,
              ),
              for (final sheet in sheets)
                viewRow(
                  label: '${sheet.number} - ${sheet.title}',
                  icon: Icons.insert_drive_file_outlined,
                  selected: activeSheetId == sheet.id,
                  onTap: () async => onOpenSheet(sheet.id),
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
