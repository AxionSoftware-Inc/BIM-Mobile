// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.scene,
  });

  final RenderScene scene;

  @override
  Widget build(BuildContext context) {
    final diagnostics = scene.diagnostics;

    return _InfoCard(
      title: 'Diagnostics',
      icon: Icons.bug_report_outlined,
      children: <Widget>[
        _InfoRow(label: 'Source', value: diagnostics.source),
        _InfoRow(
            label: 'Visible', value: diagnostics.visibleObjectCount.toString()),
        _InfoRow(
          label: 'Selectable',
          value: diagnostics.selectableObjectCount.toString(),
        ),
        _InfoRow(
          label: 'Missing geometry',
          value: diagnostics.missingGeometryCount.toString(),
        ),
        _InfoRow(
          label: 'Invalid bounds',
          value: diagnostics.invalidBoundsCount.toString(),
        ),
        _InfoRow(label: 'Levels', value: diagnostics.levelCount.toString()),
        const SizedBox(height: 8),
        Text(
          'Kinds',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final entry in diagnostics.kindCounts.entries)
          _InfoRow(
            label: prettySceneKind(entry.key),
            value: entry.value.toString(),
          ),
        if (diagnostics.warnings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Warnings',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          for (final warning in diagnostics.warnings)
            _BulletText(text: warning),
        ],
        if (diagnostics.errors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Errors',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: const Color(0xFF991B1B)),
          ),
          const SizedBox(height: 6),
          for (final error in diagnostics.errors)
            _BulletText(text: error, color: const Color(0xFF991B1B)),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
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

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText({
    required this.text,
    this.color,
  });

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('• ', style: TextStyle(color: color)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  const _EmptyPanelMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'wall':
      return Icons.linear_scale;
    case 'door':
      return Icons.door_front_door_outlined;
    case 'window':
      return Icons.window_outlined;
    case 'room':
      return Icons.meeting_room_outlined;
    case 'slab':
    case 'floor':
      return Icons.layers_outlined;
    case 'ceiling':
      return Icons.flip_to_front_outlined;
    case 'roof':
      return Icons.roofing_outlined;
    case 'column':
      return Icons.view_column_outlined;
    case 'beam':
      return Icons.horizontal_rule;
    case 'stair':
      return Icons.stairs_outlined;
    default:
      return Icons.category_outlined;
  }
}

Color _kindUiColor(String kind) {
  switch (kind) {
    case 'wall':
      return const Color(0xFF1F5D4E);
    case 'door':
      return const Color(0xFFC2410C);
    case 'window':
      return const Color(0xFF0284C7);
    case 'room':
      return const Color(0xFF7C3AED);
    case 'slab':
    case 'floor':
      return const Color(0xFF475569);
    case 'ceiling':
      return const Color(0xFF64748B);
    case 'roof':
      return const Color(0xFFB91C1C);
    case 'column':
      return const Color(0xFF374151);
    case 'beam':
      return const Color(0xFF92400E);
    case 'stair':
      return const Color(0xFF4338CA);
    default:
      return const Color(0xFF6B7280);
  }
}
