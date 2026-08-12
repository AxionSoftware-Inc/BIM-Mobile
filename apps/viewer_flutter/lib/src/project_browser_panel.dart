import 'package:flutter/material.dart';

import 'documentation/document_models.dart';
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
    required this.activeViewTabId,
    required this.onClose,
    required this.onVisibleKindsChanged,
    required this.onOpen3d,
    required this.onOpenFloorPlan,
    required this.onOpenElevation,
    required this.onOpenSection,
    required this.sheets,
    this.activeSheetId,
    required this.onCreateSheet,
    required this.onOpenSheet,
  });

  final RenderScene? scene;
  final List<String> availableKinds;
  final Set<String> visibleKinds;
  final String? activeViewTabId;
  final VoidCallback onClose;
  final ValueChanged<Set<String>> onVisibleKindsChanged;
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
    final activeScene = scene;
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
                        activeViewTabId: activeViewTabId,
                        onOpen3d: onOpen3d,
                        onOpenFloorPlan: onOpenFloorPlan,
                        onOpenElevation: onOpenElevation,
                        onOpenSection: onOpenSection,
                        sheets: sheets,
                        activeSheetId: activeSheetId,
                        onCreateSheet: onCreateSheet,
                        onOpenSheet: onOpenSheet,
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
