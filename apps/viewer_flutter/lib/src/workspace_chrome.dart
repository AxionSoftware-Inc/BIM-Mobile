import 'package:flutter/material.dart';

import 'render_scene_viewport_planar.dart';
import 'render_scene_viewport_types.dart';

/// Compact project chrome for a professional tablet BIM workspace.
class WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WorkspaceAppBar({
    super.key,
    required this.statusMessage,
    required this.busy,
    required this.engineBacked,
    required this.hasScene,
    required this.hasSelection,
    required this.browserVisible,
    required this.inspectorVisible,
    required this.onSave,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onDocumentation,
    required this.onImportIfc,
    required this.onExportIfc,
    required this.onProjectUnits,
    required this.onCreateSection,
    required this.onReload,
    required this.onClearSelection,
    required this.onToggleBrowser,
    required this.onToggleInspector,
    this.activeSectionName,
    this.onExitSection,
    this.onReturnToStart,
  });

  final String? statusMessage;
  final bool busy;
  final bool engineBacked;
  final bool hasScene;
  final bool hasSelection;
  final bool browserVisible;
  final bool inspectorVisible;
  final VoidCallback onSave;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDocumentation;
  final Future<void> Function() onImportIfc;
  final Future<void> Function() onExportIfc;
  final Future<void> Function() onProjectUnits;
  final VoidCallback onCreateSection;
  final VoidCallback onReload;
  final VoidCallback onClearSelection;
  final VoidCallback onToggleBrowser;
  final VoidCallback onToggleInspector;
  final String? activeSectionName;
  final VoidCallback? onExitSection;
  final Future<void> Function()? onReturnToStart;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final subtitle = statusMessage?.trim();
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: 18,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (onReturnToStart == null)
            const Text('Tablet BIM')
          else
            InkWell(
              onTap: busy ? null : () => onReturnToStart?.call(),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('Tablet BIM'),
              ),
            ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
      actions: <Widget>[
        if (activeSectionName != null && onExitSection != null)
          IconButton(
            tooltip: 'Return to model from $activeSectionName',
            onPressed: busy ? null : onExitSection,
            icon: const Icon(Icons.close_fullscreen_outlined),
          ),
        IconButton(
          tooltip: 'Save project',
          onPressed: busy || !engineBacked ? null : onSave,
          icon: const Icon(Icons.save_outlined),
        ),
        PopupMenuButton<_WorkspaceMoreAction>(
          tooltip: 'Workspace actions',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case _WorkspaceMoreAction.undo:
                onUndo();
              case _WorkspaceMoreAction.redo:
                onRedo();
              case _WorkspaceMoreAction.documentation:
                onDocumentation();
              case _WorkspaceMoreAction.importIfc:
                onImportIfc();
              case _WorkspaceMoreAction.exportIfc:
                onExportIfc();
              case _WorkspaceMoreAction.projectUnits:
                onProjectUnits();
              case _WorkspaceMoreAction.createSection:
                onCreateSection();
              case _WorkspaceMoreAction.toggleInspector:
                onToggleInspector();
              case _WorkspaceMoreAction.reload:
                onReload();
              case _WorkspaceMoreAction.clearSelection:
                onClearSelection();
              case _WorkspaceMoreAction.toggleBrowser:
                onToggleBrowser();
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<_WorkspaceMoreAction>>[
            PopupMenuItem(
              value: _WorkspaceMoreAction.undo,
              enabled: !busy && engineBacked && canUndo,
              child: const ListTile(
                leading: Icon(Icons.undo),
                title: Text('Undo'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.redo,
              enabled: !busy && engineBacked && canRedo,
              child: const ListTile(
                leading: Icon(Icons.redo),
                title: Text('Redo'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _WorkspaceMoreAction.documentation,
              enabled: !busy && hasScene,
              child: const ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Documentation and PDF'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.importIfc,
              enabled: !busy && engineBacked,
              child: const ListTile(
                leading: Icon(Icons.file_open_outlined),
                title: Text('Import IFC'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.exportIfc,
              enabled: !busy && engineBacked && hasScene,
              child: const ListTile(
                leading: Icon(Icons.ios_share_outlined),
                title: Text('Export IFC'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.projectUnits,
              enabled: !busy && engineBacked && hasScene,
              child: const ListTile(
                leading: Icon(Icons.straighten_outlined),
                title: Text('Project units'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.createSection,
              enabled: !busy && engineBacked && hasScene,
              child: const ListTile(
                leading: Icon(Icons.content_cut_outlined),
                title: Text('Create section'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.toggleInspector,
              enabled: !busy,
              child: ListTile(
                leading: Icon(
                  inspectorVisible ? Icons.tune : Icons.tune_outlined,
                ),
                title: Text(
                  inspectorVisible ? 'Hide Inspector' : 'Show Inspector',
                ),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _WorkspaceMoreAction.reload,
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Reload scene'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.clearSelection,
              enabled: hasSelection,
              child: const ListTile(
                leading: Icon(Icons.deselect),
                title: Text('Clear selection'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.toggleBrowser,
              child: ListTile(
                leading: Icon(browserVisible
                    ? Icons.vertical_split_outlined
                    : Icons.account_tree_outlined),
                title: Text(browserVisible
                    ? 'Hide project browser'
                    : 'Show project browser'),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

enum WorkspaceTemplate {
  default3,
  tower9,
  campus6x9,
  modern3,
  glassTower9,
  glassCampus6x9,
}

/// The right-hand workspace slot hosts one contextual surface at a time.
/// Keeping the tab state explicit prevents Browser and Inspector from
/// accidentally becoming two competing layout trees.
enum WorkspaceSidePanelTab { projectBrowser, inspector }

/// Revit-style tab switcher for the shared Project Browser / Inspector slot.
class WorkspaceSidePanelTabs extends StatelessWidget {
  const WorkspaceSidePanelTabs({
    super.key,
    required this.activeTab,
    required this.onChanged,
  });

  final WorkspaceSidePanelTab activeTab;
  final ValueChanged<WorkspaceSidePanelTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildTab(
              context,
              tab: WorkspaceSidePanelTab.projectBrowser,
              icon: Icons.account_tree_outlined,
              label: 'Project Browser',
              colors: colors,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTab(
              context,
              tab: WorkspaceSidePanelTab.inspector,
              icon: Icons.tune_outlined,
              label: 'Inspector',
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context, {
    required WorkspaceSidePanelTab tab,
    required IconData icon,
    required String label,
    required ColorScheme colors,
  }) {
    final selected = activeTab == tab;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.secondaryContainer : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: selected ? null : () => onChanged(tab),
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _WorkspaceMoreAction {
  undo,
  redo,
  documentation,
  importIfc,
  exportIfc,
  projectUnits,
  createSection,
  toggleInspector,
  reload,
  clearSelection,
  toggleBrowser,
}

/// Touch-first authoring palette. The short labels keep the tools discoverable
/// without requiring the user to remember what an abstract icon means.
class AuthoringToolPalette extends StatelessWidget {
  const AuthoringToolPalette({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onModeChanged,
  });

  final RenderSceneInteractionMode mode;
  final bool enabled;
  final ValueChanged<RenderSceneInteractionMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 28),
        child: SizedBox(
          width: 88,
          child: Material(
            elevation: 3,
            color: theme.colorScheme.surface.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final tool in _primaryTools)
                    _PaletteToolButton(
                      tool: tool,
                      selected: mode == tool.mode,
                      enabled: enabled,
                      onPressed: () => onModeChanged(tool.mode),
                    ),
                  const Divider(height: 20),
                  PopupMenuButton<RenderSceneInteractionMode>(
                    tooltip: 'More editing tools',
                    enabled: enabled,
                    icon: const Icon(Icons.edit_note_outlined),
                    onSelected: onModeChanged,
                    itemBuilder: (context) =>
                        <PopupMenuEntry<RenderSceneInteractionMode>>[
                      for (final tool in _secondaryTools)
                        CheckedPopupMenuItem<RenderSceneInteractionMode>(
                          value: tool.mode,
                          checked: mode == tool.mode,
                          child: Row(
                            children: <Widget>[
                              Icon(tool.icon, size: 18),
                              const SizedBox(width: 10),
                              Text(tool.label),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ViewportControlDeck extends StatelessWidget {
  const ViewportControlDeck({
    super.key,
    required this.hasScene,
    required this.projectionMode,
    required this.displayStyle,
    required this.orbitStyle,
    required this.onProjectionChanged,
    required this.onDisplayStyleChanged,
    required this.shadowsEnabled,
    required this.onShadowsChanged,
    required this.hdriVisible,
    required this.onHdriChanged,
    required this.onOrbitStyleChanged,
    required this.onFit,
    required this.hasSectionBox,
    required this.onSectionBox,
  });

  final bool hasScene;
  final RenderSceneProjectionMode projectionMode;
  final RenderSceneDisplayStyle displayStyle;
  final RenderSceneOrbitProjectionStyle orbitStyle;
  final ValueChanged<RenderSceneProjectionMode> onProjectionChanged;
  final ValueChanged<RenderSceneDisplayStyle> onDisplayStyleChanged;
  final bool shadowsEnabled;
  final ValueChanged<bool> onShadowsChanged;
  final bool hdriVisible;
  final ValueChanged<bool> onHdriChanged;
  final ValueChanged<RenderSceneOrbitProjectionStyle> onOrbitStyleChanged;
  final VoidCallback onFit;
  final bool hasSectionBox;
  final VoidCallback onSectionBox;

  @override
  Widget build(BuildContext context) {
    final is3D = projectionMode.is3D;
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _DeckIconButton(
              tooltip: 'Floor plan',
              selected: projectionMode == RenderSceneProjectionMode.topDown,
              enabled: hasScene,
              icon: Icons.grid_view_outlined,
              onPressed: () => onProjectionChanged(
                RenderSceneProjectionMode.topDown,
              ),
            ),
            _DeckIconButton(
              tooltip: '3D view',
              selected: projectionMode == RenderSceneProjectionMode.isometric,
              enabled: hasScene,
              icon: Icons.view_in_ar_outlined,
              onPressed: () => onProjectionChanged(
                RenderSceneProjectionMode.isometric,
              ),
            ),
            PopupMenuButton<RenderSceneDisplayStyle>(
              tooltip: 'Display style',
              enabled: hasScene,
              icon: Icon(_displayIcon(displayStyle)),
              onSelected: onDisplayStyleChanged,
              itemBuilder: (context) =>
                  <PopupMenuEntry<RenderSceneDisplayStyle>>[
                for (final style in RenderSceneDisplayStyle.values)
                  CheckedPopupMenuItem<RenderSceneDisplayStyle>(
                    value: style,
                    checked: style == displayStyle,
                    child: Text(_displayLabel(style)),
                  ),
              ],
            ),
            if (is3D)
              _DeckIconButton(
                tooltip:
                    shadowsEnabled ? 'Turn shadows off' : 'Turn shadows on',
                selected: shadowsEnabled,
                enabled: hasScene,
                icon: shadowsEnabled ? Icons.wb_sunny_outlined : Icons.wb_sunny,
                onPressed: () => onShadowsChanged(!shadowsEnabled),
              ),
            if (is3D)
              _DeckIconButton(
                tooltip: hdriVisible
                    ? 'Hide HDRI background'
                    : 'Show HDRI background',
                selected: hdriVisible,
                enabled: hasScene,
                icon: hdriVisible ? Icons.landscape : Icons.landscape_outlined,
                onPressed: () => onHdriChanged(!hdriVisible),
              ),
            if (is3D)
              _DeckIconButton(
                tooltip:
                    orbitStyle == RenderSceneOrbitProjectionStyle.perspective
                        ? 'Perspective projection'
                        : 'Orthographic projection',
                selected:
                    orbitStyle == RenderSceneOrbitProjectionStyle.orthographic,
                enabled: hasScene,
                icon: orbitStyle == RenderSceneOrbitProjectionStyle.perspective
                    ? Icons.threed_rotation
                    : Icons.crop_square,
                onPressed: () => onOrbitStyleChanged(
                  orbitStyle == RenderSceneOrbitProjectionStyle.perspective
                      ? RenderSceneOrbitProjectionStyle.orthographic
                      : RenderSceneOrbitProjectionStyle.perspective,
                ),
              ),
            if (is3D)
              _DeckIconButton(
                tooltip:
                    hasSectionBox ? '3D Section Box active' : '3D Section Box',
                selected: hasSectionBox,
                enabled: hasScene,
                icon: Icons.crop_free_outlined,
                onPressed: onSectionBox,
              ),
            const VerticalDivider(width: 14),
            _DeckIconButton(
              tooltip: 'Fit view',
              enabled: hasScene,
              icon: Icons.fit_screen_outlined,
              onPressed: onFit,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteToolButton extends StatelessWidget {
  const _PaletteToolButton({
    required this.tool,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final _AuthoringTool tool;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Tooltip(
          message: tool.label,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(tool.icon, size: 21),
                  const SizedBox(height: 2),
                  Text(
                    tool.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DeckIconButton extends StatelessWidget {
  const _DeckIconButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: tooltip,
        isSelected: selected,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
      );
}

class _AuthoringTool {
  const _AuthoringTool(this.mode, this.icon, this.label);

  final RenderSceneInteractionMode mode;
  final IconData icon;
  final String label;
}

const List<_AuthoringTool> _primaryTools = <_AuthoringTool>[
  _AuthoringTool(
      RenderSceneInteractionMode.select, Icons.ads_click_outlined, 'Select'),
  _AuthoringTool(
      RenderSceneInteractionMode.addWall, Icons.architecture_outlined, 'Wall'),
  _AuthoringTool(RenderSceneInteractionMode.addDoor,
      Icons.door_front_door_outlined, 'Door'),
  _AuthoringTool(
      RenderSceneInteractionMode.addWindow, Icons.window_outlined, 'Window'),
  _AuthoringTool(
      RenderSceneInteractionMode.addFloor, Icons.layers_outlined, 'Floor'),
  _AuthoringTool(RenderSceneInteractionMode.addCeiling,
      Icons.space_dashboard_outlined, 'Ceiling'),
  _AuthoringTool(
      RenderSceneInteractionMode.addRoof, Icons.roofing_outlined, 'Roof'),
  _AuthoringTool(
      RenderSceneInteractionMode.addStair, Icons.stairs_outlined, 'Stair'),
];

const List<_AuthoringTool> _secondaryTools = <_AuthoringTool>[
  _AuthoringTool(RenderSceneInteractionMode.addLevel, Icons.add_chart_outlined,
      'Add level'),
  _AuthoringTool(RenderSceneInteractionMode.moveLevel, Icons.height_outlined,
      'Move level'),
  _AuthoringTool(RenderSceneInteractionMode.moveWall, Icons.open_with_outlined,
      'Move wall'),
  _AuthoringTool(RenderSceneInteractionMode.moveOpening,
      Icons.compare_arrows_outlined, 'Move opening'),
  _AuthoringTool(
    RenderSceneInteractionMode.trimExtend,
    Icons.call_merge_outlined,
    'Trim / Extend',
  ),
];

IconData _displayIcon(RenderSceneDisplayStyle style) => switch (style) {
      RenderSceneDisplayStyle.shaded => Icons.gradient_outlined,
      RenderSceneDisplayStyle.solid => Icons.circle_outlined,
      RenderSceneDisplayStyle.wireframe => Icons.grid_4x4_outlined,
    };

String _displayLabel(RenderSceneDisplayStyle style) => switch (style) {
      RenderSceneDisplayStyle.shaded => 'Shaded',
      RenderSceneDisplayStyle.solid => 'Solid',
      RenderSceneDisplayStyle.wireframe => 'Wireframe',
    };
