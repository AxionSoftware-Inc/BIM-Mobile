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
    required this.onCreateTemplate,
    required this.onSave,
    required this.onDocumentation,
    required this.onOpenMaterials,
    required this.onCreateSection,
    required this.onReload,
    required this.onClearSelection,
    required this.onToggleBrowser,
    required this.onToggleInspector,
    this.activeSectionName,
    this.onExitSection,
    this.rendererToggleVisible = false,
    this.rendererIsNative = true,
    this.onToggleRenderer,
  });

  final String? statusMessage;
  final bool busy;
  final bool engineBacked;
  final bool hasScene;
  final bool hasSelection;
  final bool browserVisible;
  final bool inspectorVisible;
  final ValueChanged<WorkspaceTemplate> onCreateTemplate;
  final VoidCallback onSave;
  final VoidCallback onDocumentation;
  final VoidCallback onOpenMaterials;
  final VoidCallback onCreateSection;
  final VoidCallback onReload;
  final VoidCallback onClearSelection;
  final VoidCallback onToggleBrowser;
  final VoidCallback onToggleInspector;
  final String? activeSectionName;
  final VoidCallback? onExitSection;
  final bool rendererToggleVisible;
  final bool rendererIsNative;
  final VoidCallback? onToggleRenderer;

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
          const Text('Tablet BIM'),
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
        PopupMenuButton<WorkspaceTemplate>(
          tooltip: 'New project template',
          enabled: !busy,
          icon: const Icon(Icons.apartment_outlined),
          onSelected: onCreateTemplate,
          itemBuilder: (context) => const <PopupMenuEntry<WorkspaceTemplate>>[
            PopupMenuItem<WorkspaceTemplate>(
              value: WorkspaceTemplate.tower9,
              child: Text('9-storey residential tower'),
            ),
            PopupMenuItem<WorkspaceTemplate>(
              value: WorkspaceTemplate.campus6x9,
              child: Text('6 × 9-storey campus'),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Save project',
          onPressed: busy || !engineBacked ? null : onSave,
          icon: const Icon(Icons.save_outlined),
        ),
        IconButton(
          tooltip: 'Documentation and PDF',
          onPressed: busy || !hasScene ? null : onDocumentation,
          icon: const Icon(Icons.description_outlined),
        ),
        IconButton(
          tooltip: 'Materials and assemblies',
          onPressed:
              busy || !engineBacked || !hasScene ? null : onOpenMaterials,
          icon: const Icon(Icons.layers_outlined),
        ),
        IconButton(
          tooltip: 'Create section',
          onPressed:
              busy || !engineBacked || !hasScene ? null : onCreateSection,
          icon: const Icon(Icons.content_cut_outlined),
        ),
        PopupMenuButton<_WorkspaceMoreAction>(
          tooltip: 'Workspace actions',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case _WorkspaceMoreAction.reload:
                onReload();
              case _WorkspaceMoreAction.clearSelection:
                onClearSelection();
              case _WorkspaceMoreAction.toggleBrowser:
                onToggleBrowser();
              case _WorkspaceMoreAction.toggleInspector:
                onToggleInspector();
              case _WorkspaceMoreAction.toggleRenderer:
                onToggleRenderer?.call();
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<_WorkspaceMoreAction>>[
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
                    ? 'Hide Project Browser'
                    : 'Show Project Browser'),
              ),
            ),
            PopupMenuItem(
              value: _WorkspaceMoreAction.toggleInspector,
              child: ListTile(
                leading: Icon(inspectorVisible
                    ? Icons.tune_outlined
                    : Icons.tune_outlined),
                title: Text(
                    inspectorVisible ? 'Hide Inspector' : 'Show Inspector'),
              ),
            ),
            if (rendererToggleVisible && onToggleRenderer != null)
              PopupMenuItem(
                value: _WorkspaceMoreAction.toggleRenderer,
                enabled: !busy,
                child: ListTile(
                  leading: Icon(
                    rendererIsNative ? Icons.layers_outlined : Icons.memory,
                  ),
                  title: Text(
                    rendererIsNative
                        ? 'Use Flutter fallback renderer'
                        : 'Use Filament renderer',
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

enum WorkspaceTemplate { tower9, campus6x9 }

enum _WorkspaceMoreAction {
  reload,
  clearSelection,
  toggleBrowser,
  toggleInspector,
  toggleRenderer,
}

/// Icon-first authoring palette. Rare editing commands remain in the overflow.
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
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          for (final tool in _primaryTools)
            _PaletteToolButton(
              tool: tool,
              selected: mode == tool.mode,
              enabled: enabled,
              onPressed: () => onModeChanged(tool.mode),
            ),
          const Divider(height: 20),
          PopupMenuButton<RenderSceneInteractionMode>(
            tooltip: 'Edit tools · Trim / Extend',
            enabled: enabled,
            icon: const Icon(Icons.construction_outlined),
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
    );
  }
}

/// Small touch-first HUD for line tools. It replaces desktop hover
/// instructions with an explicit one-finger gesture contract while keeping
/// navigation available under two fingers.
class LineDrawingContextBar extends StatelessWidget {
  const LineDrawingContextBar({
    super.key,
    required this.mode,
    required this.enabled,
    required this.hasDraft,
    required this.onDone,
    required this.onCancel,
  });

  final RenderSceneInteractionMode mode;
  final bool enabled;
  final bool hasDraft;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWall = mode == RenderSceneInteractionMode.addWall;
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(isWall ? Icons.architecture_outlined : Icons.stairs_outlined,
                size: 19),
            const SizedBox(width: 8),
            Text(isWall ? 'Draw Walls' : 'Draw Stair'),
            const SizedBox(width: 12),
            Text(
              isWall
                  ? 'Drag a wall · tap corners to chain · two fingers navigate'
                  : 'Drag from stair start to direction',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: enabled ? onDone : null,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: hasDraft ? 'Cancel current segment' : 'Close tool',
              onPressed: enabled ? onCancel : null,
              icon: const Icon(Icons.close, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contextual surface-authoring controls, deliberately shown next to the
/// viewport while a Floor, Ceiling, or Roof footprint is active. Keeping the
/// command vocabulary here makes sketching discoverable without duplicating
/// it in the Inspector.
class SurfaceDrawingContextBar extends StatelessWidget {
  const SurfaceDrawingContextBar({
    super.key,
    required this.mode,
    required this.drawMode,
    required this.enabled,
    required this.canFinish,
    required this.canUndo,
    required this.onDrawModeChanged,
    required this.onUndo,
    required this.onTrimExtend,
    required this.onFinish,
    required this.onCancel,
  });

  final RenderSceneInteractionMode mode;
  final RenderSceneSurfaceDrawMode drawMode;
  final bool enabled;
  final bool canFinish;
  final bool canUndo;
  final ValueChanged<RenderSceneSurfaceDrawMode> onDrawModeChanged;
  final VoidCallback onUndo;
  final VoidCallback onTrimExtend;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  bool get _supportsAutoRoom =>
      mode == RenderSceneInteractionMode.addFloor ||
      mode == RenderSceneInteractionMode.addCeiling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = <RenderSceneSurfaceDrawMode>[
      RenderSceneSurfaceDrawMode.polyline,
      RenderSceneSurfaceDrawMode.rectangle,
      RenderSceneSurfaceDrawMode.pickWalls,
      if (_supportsAutoRoom) RenderSceneSurfaceDrawMode.autoRoom,
    ];

    return Material(
      elevation: 4,
      color: theme.colorScheme.surface.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(_surfaceModeIcon(mode), size: 19),
                  const SizedBox(width: 7),
                  Text(
                    'Draw ${mode.authoringLabel}',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 28,
              child: VerticalDivider(width: 8),
            ),
            for (final option in modes)
              Tooltip(
                message: _surfaceDrawModeHint(option),
                child: ChoiceChip(
                  avatar: Icon(_surfaceDrawModeIcon(option), size: 17),
                  label: Text(_surfaceDrawModeLabel(option)),
                  selected: drawMode == option,
                  onSelected: enabled ? (_) => onDrawModeChanged(option) : null,
                ),
              ),
            const SizedBox(
              height: 28,
              child: VerticalDivider(width: 8),
            ),
            Tooltip(
              message: 'Remove the last point or picked wall',
              child: IconButton.filledTonal(
                onPressed: enabled && canUndo ? onUndo : null,
                icon: const Icon(Icons.undo, size: 19),
              ),
            ),
            Tooltip(
              message: 'Switch to the wall Trim / Extend tool',
              child: OutlinedButton.icon(
                onPressed: enabled ? onTrimExtend : null,
                icon: const Icon(Icons.call_merge_outlined, size: 18),
                label: const Text('Trim / Extend'),
              ),
            ),
            FilledButton.icon(
              onPressed: enabled && canFinish ? onFinish : null,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Finish'),
            ),
            TextButton(
              onPressed: enabled ? onCancel : null,
              child: const Text('Cancel'),
            ),
            Text(
              drawMode == RenderSceneSurfaceDrawMode.rectangle
                  ? 'Drag one finger · two fingers navigate'
                  : drawMode == RenderSceneSurfaceDrawMode.pickWalls
                      ? 'Tap walls · tap again to remove'
                      : 'Tap corners · Finish closes the loop',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _surfaceModeIcon(RenderSceneInteractionMode mode) => switch (mode) {
      RenderSceneInteractionMode.addFloor => Icons.layers_outlined,
      RenderSceneInteractionMode.addCeiling => Icons.space_dashboard_outlined,
      RenderSceneInteractionMode.addRoof => Icons.roofing_outlined,
      _ => Icons.edit_outlined,
    };

IconData _surfaceDrawModeIcon(RenderSceneSurfaceDrawMode mode) =>
    switch (mode) {
      RenderSceneSurfaceDrawMode.polyline => Icons.polyline_outlined,
      RenderSceneSurfaceDrawMode.rectangle => Icons.crop_square,
      RenderSceneSurfaceDrawMode.pickWalls => Icons.ads_click_outlined,
      RenderSceneSurfaceDrawMode.autoRoom => Icons.meeting_room_outlined,
    };

String _surfaceDrawModeLabel(RenderSceneSurfaceDrawMode mode) => switch (mode) {
      RenderSceneSurfaceDrawMode.polyline => 'Boundary',
      RenderSceneSurfaceDrawMode.rectangle => 'Rectangle',
      RenderSceneSurfaceDrawMode.pickWalls => 'Pick Walls',
      RenderSceneSurfaceDrawMode.autoRoom => 'Auto Room',
    };

String _surfaceDrawModeHint(RenderSceneSurfaceDrawMode mode) => switch (mode) {
      RenderSceneSurfaceDrawMode.polyline =>
        'Click consecutive boundary points, then Finish',
      RenderSceneSurfaceDrawMode.rectangle => 'Click two opposite corners',
      RenderSceneSurfaceDrawMode.pickWalls =>
        'Select enclosing walls to derive the footprint',
      RenderSceneSurfaceDrawMode.autoRoom =>
        'Select a room to create the system from its boundary',
    };

class ViewportControlDeck extends StatelessWidget {
  const ViewportControlDeck({
    super.key,
    required this.hasScene,
    required this.projectionMode,
    required this.displayStyle,
    required this.orbitStyle,
    required this.onProjectionChanged,
    required this.onDisplayStyleChanged,
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: IconButton.filledTonal(
          isSelected: selected,
          tooltip: tool.label,
          onPressed: enabled ? onPressed : null,
          icon: Icon(tool.icon),
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
      RenderSceneInteractionMode.select, Icons.near_me_outlined, 'Select'),
  _AuthoringTool(
      RenderSceneInteractionMode.addWall, Icons.view_week_outlined, 'Wall'),
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
