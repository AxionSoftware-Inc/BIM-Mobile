import 'package:flutter/material.dart';

import '../../../core/application/render_scene/render_scene_models.dart';
import '../application/bim_element_registry.dart';

/// Shared Inspector card chrome for standalone element adapters.
class BimInspectorCard extends StatelessWidget {
  const BimInspectorCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 16,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ...children,
          ],
        ),
      ),
    );
  }
}

class BimReadOnlyObjectSection extends StatelessWidget {
  const BimReadOnlyObjectSection({
    super.key,
    required this.object,
    required this.title,
    required this.rows,
  });

  final RenderSceneObject object;
  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => BimInspectorCard(
        title: title,
        icon: bimInspectorIcon(object.kindKey),
        children: <Widget>[
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

String bimInspectorLabel(RenderSceneObject object) =>
    BimElementRegistry.standard.displayName(object.kind);

IconData bimInspectorIcon(String kind) => switch (kind) {
      'wall' => Icons.architecture_outlined,
      'door' => Icons.door_front_door_outlined,
      'window' => Icons.window_outlined,
      'stair' => Icons.stairs_outlined,
      'roof' => Icons.roofing_outlined,
      'floor' || 'slab' => Icons.layers_outlined,
      'ceiling' => Icons.space_dashboard_outlined,
      'column' => Icons.view_column_outlined,
      'beam' => Icons.horizontal_rule,
      _ => Icons.category_outlined,
    };
