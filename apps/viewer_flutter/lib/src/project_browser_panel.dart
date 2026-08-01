import 'package:flutter/material.dart';

import 'project_browser_views.dart';
import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';

/// Complete Project Browser presentation feature.
///
/// The shell owns navigation and selection use-cases through callbacks. This
/// module owns no FFI handles, viewport controllers, or mutable project state.
class ProjectBrowserPanel extends StatelessWidget {
  const ProjectBrowserPanel({
    super.key,
    required this.scene,
    required this.availableKinds,
    required this.visibleKinds,
    required this.selectedElementId,
    required this.projectionMode,
    required this.activeLevelId,
    this.activeSectionName,
    required this.onClose,
    required this.onVisibleKindsChanged,
    required this.onSelectObject,
    required this.onOpen3d,
    required this.onOpenFloorPlan,
    required this.onOpenElevation,
    required this.onOpenSection,
  });

  final RenderScene? scene;
  final List<String> availableKinds;
  final Set<String> visibleKinds;
  final String? selectedElementId;
  final RenderSceneProjectionMode projectionMode;
  final int? activeLevelId;
  final String? activeSectionName;
  final VoidCallback onClose;
  final ValueChanged<Set<String>> onVisibleKindsChanged;
  final Future<void> Function(RenderSceneObject object) onSelectObject;
  final Future<void> Function() onOpen3d;
  final Future<void> Function(int levelId) onOpenFloorPlan;
  final Future<void> Function(RenderSceneProjectionMode mode) onOpenElevation;
  final Future<void> Function(RenderSceneSection section) onOpenSection;

  @override
  Widget build(BuildContext context) {
    final activeScene = scene;
    final objects = activeScene == null
        ? const <RenderSceneObject>[]
        : activeScene.objectsForKinds(visibleKinds);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Project Browser',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Collapse project browser',
                onPressed: onClose,
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: <Widget>[
              if (activeScene != null)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ProjectBrowserViews(
                        scene: activeScene,
                        projectionMode: projectionMode,
                        activeLevelId: activeLevelId,
                        activeSectionName: activeSectionName,
                        onOpen3d: onOpen3d,
                        onOpenFloorPlan: onOpenFloorPlan,
                        onOpenElevation: onOpenElevation,
                        onOpenSection: onOpenSection,
                      ),
                      const Divider(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Categories',
                                style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            _KindFilterWrap(
                              availableKinds: availableKinds,
                              selectedKinds: visibleKinds,
                              kindCounts: activeScene.kindCounts,
                              onChanged: onVisibleKindsChanged,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 20),
                    ],
                  ),
                ),
              if (activeScene == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _BrowserEmptyMessage(
                    icon: Icons.data_object,
                    title: 'No scene loaded',
                    message: 'Load a RenderScene sample to inspect objects.',
                  ),
                )
              else if (objects.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _BrowserEmptyMessage(
                    icon: Icons.filter_alt_off,
                    title: 'No visible objects',
                    message: 'Change category filters to show objects.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final object = objects[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _ObjectListTile(
                            object: object,
                            selected: object.elementId?.toString() ==
                                selectedElementId,
                            onTap: () => onSelectObject(object),
                          ),
                        );
                      },
                      childCount: objects.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindFilterWrap extends StatelessWidget {
  const _KindFilterWrap({
    required this.availableKinds,
    required this.selectedKinds,
    required this.kindCounts,
    required this.onChanged,
  });

  final List<String> availableKinds;
  final Set<String> selectedKinds;
  final Map<String, int> kindCounts;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (availableKinds.isEmpty) return const SizedBox.shrink();
    final allSelected = selectedKinds.isEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilterChip(
          label: const Text('All'),
          selected: allSelected,
          onSelected: (_) => onChanged(<String>{}),
        ),
        for (final kind in availableKinds)
          FilterChip(
            label: Text('${prettySceneKind(kind)} ${kindCounts[kind] ?? 0}'),
            selected: allSelected || selectedKinds.contains(kind),
            onSelected: (selected) {
              final next =
                  allSelected ? availableKinds.toSet() : selectedKinds.toSet();
              if (selected) {
                next.add(kind);
              } else {
                next.remove(kind);
              }
              onChanged(
                  next.length == availableKinds.length ? <String>{} : next);
            },
          ),
      ],
    );
  }
}

class _ObjectListTile extends StatelessWidget {
  const _ObjectListTile({
    required this.object,
    required this.selected,
    required this.onTap,
  });

  final RenderSceneObject object;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = prettySceneKind(object.kind);
    final id = object.elementId?.toString() ?? 'no-id';
    final color = _kindColor(object.kindKey);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 17,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(_kindIcon(object.kindKey), size: 18, color: color),
        ),
        title: Text('$kind #$id', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${object.mesh.positions.length} vertices · ${object.mesh.triangleCount} tris',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected ? const Icon(Icons.check_circle) : null,
      ),
    );
  }
}

class _BrowserEmptyMessage extends StatelessWidget {
  const _BrowserEmptyMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 32, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

IconData _kindIcon(String kind) => switch (kind) {
      'wall' => Icons.linear_scale,
      'door' => Icons.door_front_door_outlined,
      'window' => Icons.window_outlined,
      'room' => Icons.meeting_room_outlined,
      'slab' || 'floor' => Icons.layers_outlined,
      'ceiling' => Icons.flip_to_front_outlined,
      'roof' => Icons.roofing_outlined,
      'column' => Icons.view_column_outlined,
      'beam' => Icons.horizontal_rule,
      'stair' => Icons.stairs_outlined,
      _ => Icons.category_outlined,
    };

Color _kindColor(String kind) => switch (kind) {
      'wall' => const Color(0xFF1F5D4E),
      'door' => const Color(0xFFC2410C),
      'window' => const Color(0xFF0284C7),
      'room' => const Color(0xFF7C3AED),
      'slab' || 'floor' => const Color(0xFF475569),
      'ceiling' => const Color(0xFF64748B),
      'roof' => const Color(0xFFB91C1C),
      'column' => const Color(0xFF374151),
      'beam' => const Color(0xFF92400E),
      'stair' => const Color(0xFF4338CA),
      _ => const Color(0xFF6B7280),
    };
