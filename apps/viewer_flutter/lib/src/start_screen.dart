import 'package:flutter/material.dart';

import 'ifc_template_catalog.dart';
import 'project_recovery_store.dart';
import 'workspace_chrome.dart';

/// Revit-style launch page shown before a project is opened.
class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.onOpen,
    required this.onCreate,
    required this.onCreateFamily,
    required this.onSelectTemplate,
    required this.onSettings,
    this.onSelectIfcTemplate,
    this.recoveryEntry,
    this.onRecover,
    this.onDismissRecovery,
    this.busy = false,
    this.errorMessage,
  });

  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final VoidCallback onCreateFamily;
  final ValueChanged<WorkspaceTemplate> onSelectTemplate;
  final VoidCallback onSettings;
  final ValueChanged<IfcTemplate>? onSelectIfcTemplate;
  final ProjectRecoveryEntry? recoveryEntry;
  final VoidCallback? onRecover;
  final VoidCallback? onDismissRecovery;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1600.0;
            final horizontalPadding = availableWidth >= 1200 ? 32.0 : 18.0;
            final contentWidth = (availableWidth - horizontalPadding * 2)
                .clamp(0.0, 1480.0)
                .toDouble();
            // The tablet landscape layout is deliberately five columns so the
            // preview and project name remain readable at a glance.
            // Smaller windows retain readable cards instead of compressing
            // the same information into unusable slivers.
            final columnCount = contentWidth >= 1080
                ? 5
                : contentWidth >= 680
                    ? 3
                    : contentWidth >= 420
                        ? 2
                        : 1;
            const cardGap = 14.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                36,
              ),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _StartHeader(
                        busy: busy,
                        onSettings: onSettings,
                      ),
                      const SizedBox(height: 20),
                      _StartHero(
                        busy: busy,
                        onOpen: onOpen,
                        onCreate: onCreate,
                        onCreateFamily: onCreateFamily,
                      ),
                      if (recoveryEntry != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _RecoveryBanner(
                          entry: recoveryEntry!,
                          busy: busy,
                          onRecover: onRecover,
                          onDismiss: onDismissRecovery,
                        ),
                      ],
                      if (errorMessage != null) ...<Widget>[
                        const SizedBox(height: 18),
                        _StartError(message: errorMessage!),
                      ],
                      const SizedBox(height: 26),
                      const _StartSectionHeader(title: 'Project templates'),
                      const SizedBox(height: 12),
                      _StartCardGrid(
                        columnCount: columnCount,
                        gap: cardGap,
                        children: <Widget>[
                          _TemplateCard(
                            template: WorkspaceTemplate.default3,
                            title: 'Default building',
                            icon: Icons.apartment_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.default3,
                                    ),
                          ),
                          _TemplateCard(
                            template: WorkspaceTemplate.tower9,
                            title: 'Residential tower',
                            icon: Icons.location_city_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.tower9,
                                    ),
                          ),
                          _TemplateCard(
                            template: WorkspaceTemplate.campus6x9,
                            title: 'Residential campus',
                            icon: Icons.grid_view_rounded,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.campus6x9,
                                    ),
                          ),
                          _TemplateCard(
                            template: WorkspaceTemplate.modern3,
                            title: 'Modern glass house',
                            icon: Icons.house_siding_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.modern3,
                                    ),
                          ),
                          _TemplateCard(
                            template: WorkspaceTemplate.glassTower9,
                            title: 'Glass residential tower',
                            icon: Icons.business_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.glassTower9,
                                    ),
                          ),
                          _TemplateCard(
                            template: WorkspaceTemplate.glassCampus6x9,
                            title: 'Glass courtyard campus',
                            icon: Icons.account_balance_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.glassCampus6x9,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const _StartSectionHeader(
                        title: 'IFC sample projects',
                        trailing: 'Download on first open',
                      ),
                      const SizedBox(height: 12),
                      _StartCardGrid(
                        columnCount: columnCount,
                        gap: cardGap,
                        children: onlineIfcTemplates
                            .map(
                              (template) => _IfcTemplateCard(
                                template: template,
                                onPressed: busy || onSelectIfcTemplate == null
                                    ? null
                                    : () => onSelectIfcTemplate!(template),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StartHeader extends StatelessWidget {
  const _StartHeader({
    required this.busy,
    required this.onSettings,
  });

  final bool busy;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.36),
            ),
          ),
          child: Icon(
            Icons.view_in_ar_outlined,
            color: colors.primary,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Tablet BIM',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Settings',
          onPressed: busy ? null : onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _StartSectionHeader extends StatelessWidget {
  const _StartSectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const Spacer(),
          Text(
            trailing!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _StartCardGrid extends StatelessWidget {
  const _StartCardGrid({
    required this.columnCount,
    required this.gap,
    required this.children,
  });

  final int columnCount;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        mainAxisExtent: columnCount == 5 ? 198 : 264,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _IfcTemplateCard extends StatelessWidget {
  const _IfcTemplateCard({
    required this.template,
    required this.onPressed,
  });

  final IfcTemplate template;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _StartProjectCard(
      title: template.title,
      icon: Icons.cloud_download_outlined,
      onPressed: onPressed,
      preview: _IfcTemplatePreview(
        kind: template.kind,
        primary: colors.primary,
        secondary: colors.tertiary,
        surface: colors.surfaceContainerHighest,
      ),
    );
  }
}

class _StartProjectCard extends StatelessWidget {
  const _StartProjectCard({
    required this.title,
    required this.icon,
    required this.onPressed,
    required this.preview,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onPressed;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Column(
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: 124,
              child: RepaintBoundary(child: preview),
            ),
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.68),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
                  child: Row(
                    children: <Widget>[
                      Icon(icon, size: 17, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IfcTemplatePreview extends StatelessWidget {
  const _IfcTemplatePreview({
    required this.kind,
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final IfcTemplateKind kind;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _IfcTemplatePreviewPainter(
        kind: kind,
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _IfcTemplatePreviewPainter extends CustomPainter {
  const _IfcTemplatePreviewPainter({
    required this.kind,
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final IfcTemplateKind kind;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = surface.withValues(alpha: 0.44),
    );
    switch (kind) {
      case IfcTemplateKind.building:
        _drawBuilding(canvas, size, floors: 5, widthFactor: 0.34);
      case IfcTemplateKind.structure:
        _drawBuilding(canvas, size, floors: 4, widthFactor: 0.41);
        _drawStructuralFrame(canvas, size);
      case IfcTemplateKind.infrastructure:
        _drawRoad(canvas, size);
    }
  }

  void _drawBuilding(
    Canvas canvas,
    Size size, {
    required int floors,
    required double widthFactor,
  }) {
    final center = Offset(size.width * 0.5, size.height * 0.73);
    final width = size.width * widthFactor;
    final depth = size.width * 0.18;
    final floorHeight = size.height * 0.075;
    final height = floorHeight * floors;
    final footprint = <Offset>[
      Offset(center.dx - width, center.dy),
      Offset(center.dx, center.dy + depth * 0.5),
      Offset(center.dx + width, center.dy),
      Offset(center.dx, center.dy - depth * 0.5),
    ];
    final top =
        footprint.map((point) => Offset(point.dx, point.dy - height)).toList();
    final outline = Paint()
      ..color = primary.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final edge in <int>[0, 1]) {
      final next = edge + 1;
      final face = Path()
        ..moveTo(footprint[edge].dx, footprint[edge].dy)
        ..lineTo(footprint[next].dx, footprint[next].dy)
        ..lineTo(top[next].dx, top[next].dy)
        ..lineTo(top[edge].dx, top[edge].dy)
        ..close();
      canvas.drawPath(
        face,
        Paint()..color = primary.withValues(alpha: edge == 0 ? 0.17 : 0.11),
      );
      canvas.drawPath(face, outline);
    }
    final roof = Path()..moveTo(top.first.dx, top.first.dy);
    for (final point in top.skip(1)) {
      roof.lineTo(point.dx, point.dy);
    }
    roof.close();
    canvas.drawPath(roof, Paint()..color = secondary.withValues(alpha: 0.22));
    canvas.drawPath(roof, outline);

    final detail = Paint()
      ..color = secondary.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    for (var floor = 1; floor < floors; floor++) {
      final y = center.dy - floorHeight * floor;
      canvas.drawLine(
        Offset(center.dx - width * 0.96, y),
        Offset(center.dx, y + depth * 0.47),
        detail,
      );
      canvas.drawLine(
        Offset(center.dx, y + depth * 0.47),
        Offset(center.dx + width * 0.96, y),
        detail,
      );
    }
  }

  void _drawStructuralFrame(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = secondary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final left = size.width * 0.30;
    final right = size.width * 0.70;
    final top = size.height * 0.20;
    final bottom = size.height * 0.72;
    for (final x in <double>[left, (left + right) / 2, right]) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
    for (var index = 0; index < 4; index++) {
      final y = top + (bottom - top) * index / 4;
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  void _drawRoad(Canvas canvas, Size size) {
    final road = Path()
      ..moveTo(size.width * 0.12, size.height * 0.74)
      ..lineTo(size.width * 0.40, size.height * 0.20)
      ..lineTo(size.width * 0.60, size.height * 0.20)
      ..lineTo(size.width * 0.88, size.height * 0.74)
      ..close();
    canvas.drawPath(
      road,
      Paint()..color = primary.withValues(alpha: 0.15),
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = primary.withValues(alpha: 0.58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final centerLine = Paint()
      ..color = secondary.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.22),
      Offset(size.width * 0.5, size.height * 0.73),
      centerLine,
    );
  }

  @override
  bool shouldRepaint(covariant _IfcTemplatePreviewPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.surface != surface;
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({
    required this.entry,
    required this.busy,
    required this.onRecover,
    required this.onDismiss,
  });

  final ProjectRecoveryEntry entry;
  final bool busy;
  final VoidCallback? onRecover;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.restore_outlined, size: 20, color: colors.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unsaved recovery available · ${entry.projectName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: busy ? null : onDismiss,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Dismiss'),
          ),
          FilledButton.tonal(
            onPressed: busy ? null : onRecover,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
  }
}

class _StartHero extends StatelessWidget {
  const _StartHero({
    required this.busy,
    required this.onOpen,
    required this.onCreate,
    required this.onCreateFamily,
  });

  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final VoidCallback onCreateFamily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onCreate,
                style: _startActionButtonStyle(colors.primary),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create project'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onCreateFamily,
                style: _startActionButtonStyle(colors.primary),
                icon: const Icon(Icons.category_outlined),
                label: const Text('Create family'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onOpen,
                style: _startActionButtonStyle(colors.outline),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open project'),
              ),
            ],
          );
          final title = Text(
            'Start a project',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[title, const SizedBox(height: 14), actions],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: title),
              actions,
            ],
          );
        },
      ),
    );
  }
}

ButtonStyle _startActionButtonStyle(Color borderColor) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    side: BorderSide(color: borderColor.withValues(alpha: 0.8)),
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.title,
    required this.icon,
    required this.onPressed,
  });

  final WorkspaceTemplate template;
  final String title;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _StartProjectCard(
      title: title,
      icon: icon,
      onPressed: onPressed,
      preview: _TemplatePreview(
        template: template,
        primary: colors.primary,
        secondary: colors.tertiary,
        surface: colors.surfaceContainerHighest,
      ),
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    required this.template,
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final WorkspaceTemplate template;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TemplatePreviewPainter(
        template: template,
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  const _TemplatePreviewPainter({
    required this.template,
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  final WorkspaceTemplate template;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = surface.withValues(alpha: 0.44);
    canvas.drawRect(Offset.zero & size, background);

    switch (template) {
      case WorkspaceTemplate.default3:
        _drawBuilding(canvas, size, floors: 3, scale: 0.90, offsetX: 0.0);
      case WorkspaceTemplate.tower9:
        _drawBuilding(canvas, size, floors: 9, scale: 0.78, offsetX: 0.0);
      case WorkspaceTemplate.campus6x9:
        _drawCampusGround(canvas, size);
        // The engine template is a 3 x 2 campus of nine-storey L-shaped
        // buildings. Keep the same silhouette here without starting the
        // native renderer or decoding a large bitmap on the start screen.
        for (final offset in <Offset>[
          const Offset(-0.28, -0.10),
          const Offset(0.00, -0.16),
          const Offset(0.28, -0.10),
          const Offset(-0.28, 0.13),
          const Offset(0.00, 0.19),
          const Offset(0.28, 0.13),
        ]) {
          _drawBuilding(
            canvas,
            size,
            floors: 9,
            scale: 0.43,
            offsetX: offset.dx,
            offsetY: offset.dy,
          );
        }
      case WorkspaceTemplate.modern3:
        _drawModernGround(canvas, size);
        _drawBuilding(canvas, size,
            floors: 3, scale: 0.90, offsetX: 0.0, modern: true);
      case WorkspaceTemplate.glassTower9:
        _drawModernGround(canvas, size);
        _drawBuilding(canvas, size,
            floors: 9, scale: 0.78, offsetX: 0.0, modern: true);
      case WorkspaceTemplate.glassCampus6x9:
        _drawCampusGround(canvas, size);
        for (final offset in <Offset>[
          const Offset(-0.28, -0.10),
          const Offset(0.00, -0.16),
          const Offset(0.28, -0.10),
          const Offset(-0.28, 0.13),
          const Offset(0.00, 0.19),
          const Offset(0.28, 0.13),
        ]) {
          _drawBuilding(canvas, size,
              floors: 9,
              scale: 0.43,
              offsetX: offset.dx,
              offsetY: offset.dy,
              modern: true);
        }
    }
  }

  void _drawModernGround(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(size.width * 0.14, size.height * 0.64,
        size.width * 0.72, size.height * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..color = secondary.withValues(alpha: 0.13),
    );
    final pathPaint = Paint()
      ..color = primary.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(size.width * 0.16, size.height * 0.73),
        Offset(size.width * 0.84, size.height * 0.73), pathPaint);
  }

  void _drawCampusGround(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.68);
    final ground = Path()
      ..moveTo(center.dx, center.dy - size.height * 0.25)
      ..lineTo(center.dx + size.width * 0.43, center.dy - size.height * 0.04)
      ..lineTo(center.dx, center.dy + size.height * 0.18)
      ..lineTo(center.dx - size.width * 0.43, center.dy - size.height * 0.04)
      ..close();
    canvas.drawPath(
      ground,
      Paint()..color = secondary.withValues(alpha: 0.075),
    );
    canvas.drawPath(
      ground,
      Paint()
        ..color = primary.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final pathPaint = Paint()
      ..color = primary.withValues(alpha: 0.11)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = -2; index <= 2; index++) {
      final dx = size.width * index * 0.12;
      canvas.drawLine(
        Offset(center.dx + dx, center.dy - size.height * 0.12),
        Offset(center.dx + dx * 0.55, center.dy + size.height * 0.11),
        pathPaint,
      );
    }
  }

  void _drawBuilding(
    Canvas canvas,
    Size size, {
    required int floors,
    required double scale,
    required double offsetX,
    double offsetY = 0,
    bool modern = false,
  }) {
    const footprint = <Offset>[
      Offset(0.00, 0.00),
      Offset(1.00, 0.00),
      Offset(1.00, 1.00),
      Offset(0.00, 1.00),
    ];
    final center = Offset(
      size.width * (0.50 + offsetX),
      size.height * (0.67 + offsetY),
    );
    final width = size.width * 0.31 * scale;
    final depth = size.width * 0.16 * scale;
    final depthProjection = depth * 0.56;
    final floorHeight = size.height * 0.055 * scale;
    final height = floorHeight * floors;

    Offset project(Offset point, double z) {
      return Offset(
        center.dx + (point.dx - 0.5) * width - (point.dy - 0.5) * depth,
        center.dy + (point.dx + point.dy - 1.0) * depthProjection - z,
      );
    }

    final bottom = footprint.map((point) => project(point, 0)).toList();
    final top = footprint.map((point) => project(point, height)).toList();
    final linePaint = Paint()
      ..color = primary.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;

    for (var edge = footprint.length - 1; edge >= 0; edge--) {
      final next = (edge + 1) % footprint.length;
      final face = Path()
        ..moveTo(bottom[edge].dx, bottom[edge].dy)
        ..lineTo(bottom[next].dx, bottom[next].dy)
        ..lineTo(top[next].dx, top[next].dy)
        ..lineTo(top[edge].dx, top[edge].dy)
        ..close();
      final faceColor = modern && (edge == 0 || edge == 2)
          ? secondary.withValues(alpha: 0.28)
          : edge == 0 || edge == 1 || edge == 2
              ? primary.withValues(alpha: 0.19)
              : secondary.withValues(alpha: 0.16);
      canvas.drawPath(face, Paint()..color = faceColor);
      canvas.drawPath(face, linePaint);
    }

    final roof = Path()..moveTo(top.first.dx, top.first.dy);
    for (final point in top.skip(1)) {
      roof.lineTo(point.dx, point.dy);
    }
    roof.close();
    canvas.drawPath(
      roof,
      Paint()..color = primary.withValues(alpha: 0.30),
    );
    canvas.drawPath(roof, linePaint);

    final detailPaint = Paint()
      ..color = primary.withValues(alpha: 0.29)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var floor = 1; floor < floors; floor++) {
      final z = floorHeight * floor;
      for (final edge in <int>[0, 1, 2, 3]) {
        final next = (edge + 1) % footprint.length;
        canvas.drawLine(project(footprint[edge], z),
            project(footprint[next], z), detailPaint);
      }
    }

    final windowPaint = Paint()..color = secondary.withValues(alpha: 0.62);
    _drawWindowsOnEdge(
      canvas,
      project,
      footprint,
      edge: 0,
      floors: floors,
      floorHeight: floorHeight,
      columns: 3,
      paint: windowPaint,
    );
    _drawWindowsOnEdge(
      canvas,
      project,
      footprint,
      edge: 1,
      floors: floors,
      floorHeight: floorHeight,
      columns: 1,
      paint: windowPaint,
    );
    _drawWindowsOnEdge(
      canvas,
      project,
      footprint,
      edge: 3,
      floors: floors,
      floorHeight: floorHeight,
      columns: 1,
      paint: windowPaint,
    );
  }

  void _drawWindowsOnEdge(
    Canvas canvas,
    Offset Function(Offset point, double z) project,
    List<Offset> footprint, {
    required int edge,
    required int floors,
    required double floorHeight,
    required int columns,
    required Paint paint,
  }) {
    final next = (edge + 1) % footprint.length;
    final start = footprint[edge];
    final end = footprint[next];
    Offset between(double t) => Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t,
        );
    for (var floor = 0; floor < floors; floor++) {
      final lower = floor * floorHeight + floorHeight * 0.28;
      final upper = lower + floorHeight * 0.30;
      for (var column = 0; column < columns; column++) {
        final t0 = 0.14 + column * (0.72 / columns);
        final t1 = t0 + (0.12 / columns.clamp(1, 3));
        final window = Path()
          ..moveTo(
              project(between(t0), lower).dx, project(between(t0), lower).dy)
          ..lineTo(
              project(between(t1), lower).dx, project(between(t1), lower).dy)
          ..lineTo(
              project(between(t1), upper).dx, project(between(t1), upper).dy)
          ..lineTo(
              project(between(t0), upper).dx, project(between(t0), upper).dy)
          ..close();
        canvas.drawPath(window, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TemplatePreviewPainter oldDelegate) =>
      oldDelegate.template != template ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.surface != surface;
}

class _StartError extends StatelessWidget {
  const _StartError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.onErrorContainer),
      ),
    );
  }
}
