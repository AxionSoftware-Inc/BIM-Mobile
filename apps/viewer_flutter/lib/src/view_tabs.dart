import 'package:flutter/material.dart';

import 'render_scene_models.dart';
import 'render_scene_viewport_types.dart';

/// A view that has been opened in the model workspace.
///
/// The tab is deliberately a semantic reference rather than a second scene
/// snapshot. Geometry remains owned by the active project; selecting a tab
/// reapplies this view's navigation recipe to that authoritative scene.
enum OpenedViewKind {
  threeD,
  floorPlan,
  elevation,
  section,
  sheet,
}

@immutable
class OpenedViewTab {
  const OpenedViewTab({
    required this.id,
    required this.label,
    required this.kind,
    this.projectionMode,
    this.levelId,
    this.section,
    this.sheetId,
  });

  final String id;
  final String label;
  final OpenedViewKind kind;
  final RenderSceneProjectionMode? projectionMode;
  final int? levelId;
  final RenderSceneSection? section;
  final String? sheetId;
}

/// Revit-like persistent view strip displayed above the viewport.
class OpenedViewTabBar extends StatelessWidget {
  const OpenedViewTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.enabled,
    required this.onSelect,
    required this.onClose,
  });

  final List<OpenedViewTab> tabs;
  final String? activeTabId;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      child: SizedBox(
        height: 46,
        child: Scrollbar(
          thumbVisibility: tabs.length > 4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            itemCount: tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 3),
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final selected = tab.id == activeTabId;
              return _OpenedViewTabItem(
                tab: tab,
                selected: selected,
                enabled: enabled,
                onSelect: () => onSelect(tab.id),
                onClose: () => onClose(tab.id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OpenedViewTabItem extends StatelessWidget {
  const _OpenedViewTabItem({
    required this.tab,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onClose,
  });

  final OpenedViewTab tab;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onSelect : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 142, maxWidth: 250),
          padding: const EdgeInsets.only(left: 11, right: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.3 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_openedViewIcon(tab.kind), size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Close ${tab.label}',
                onPressed: enabled ? onClose : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                iconSize: 17,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _openedViewIcon(OpenedViewKind kind) => switch (kind) {
      OpenedViewKind.threeD => Icons.view_in_ar_outlined,
      OpenedViewKind.floorPlan => Icons.grid_4x4_outlined,
      OpenedViewKind.elevation => Icons.straighten,
      OpenedViewKind.section => Icons.content_cut_outlined,
      OpenedViewKind.sheet => Icons.insert_drive_file_outlined,
    };
