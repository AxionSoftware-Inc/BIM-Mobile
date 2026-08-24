import 'package:flutter/material.dart';

import 'workspace_chrome.dart';

/// Revit-style launch page shown before a project is opened.
class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.onOpen,
    required this.onCreate,
    required this.onSelectTemplate,
    this.busy = false,
    this.errorMessage,
  });

  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final ValueChanged<WorkspaceTemplate> onSelectTemplate;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1180.0;
            final contentWidth = availableWidth.clamp(0.0, 1180.0).toDouble();
            final columnCount = contentWidth >= 1120
                ? 3
                : contentWidth >= 820
                    ? 2
                    : 1;
            final cardGap = columnCount == 3 ? 14.0 : 18.0;
            final cardWidth = columnCount == 1
                ? contentWidth
                : (contentWidth - cardGap * (columnCount - 1)) / columnCount;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                contentWidth >= 900 ? 34 : 20,
                24,
                contentWidth >= 900 ? 34 : 20,
                40,
              ),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _StartHero(
                        busy: busy,
                        onOpen: onOpen,
                        onCreate: onCreate,
                      ),
                      if (errorMessage != null) ...<Widget>[
                        const SizedBox(height: 18),
                        _StartError(message: errorMessage!),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Templates',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Lightweight previews, ready-to-edit BIM models.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (columnCount > 1)
                            _TemplateCountBadge(
                              color: colors.primaryContainer,
                              textColor: colors.onPrimaryContainer,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: cardGap,
                        runSpacing: cardGap,
                        children: <Widget>[
                          _TemplateCard(
                            width: cardWidth,
                            template: WorkspaceTemplate.default3,
                            title: 'Default building',
                            subtitle: '3-storey simple starter project',
                            meta: '3 levels · ready to edit',
                            icon: Icons.apartment_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.default3,
                                    ),
                          ),
                          _TemplateCard(
                            width: cardWidth,
                            template: WorkspaceTemplate.tower9,
                            title: 'Residential tower',
                            subtitle:
                                '9-storey single-building starter project',
                            meta: '9 levels · vertical study',
                            icon: Icons.location_city_outlined,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.tower9,
                                    ),
                          ),
                          _TemplateCard(
                            width: cardWidth,
                            template: WorkspaceTemplate.campus6x9,
                            title: 'Residential campus',
                            subtitle: '6 buildings, 9 storeys each',
                            meta: '54 levels · campus study',
                            icon: Icons.grid_view_rounded,
                            onPressed: busy
                                ? null
                                : () => onSelectTemplate(
                                      WorkspaceTemplate.campus6x9,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.touch_app_outlined,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Choose a template to open a ready-to-edit model in the BIM workspace.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
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

class _StartHero extends StatelessWidget {
  const _StartHero({
    required this.busy,
    required this.onOpen,
    required this.onCreate,
  });

  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 18,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.view_in_ar_outlined,
                        size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'TABLET BIM  ·  PROJECT WORKSPACE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Start a project',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF173D35),
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Open an existing BIM project or begin with a lightweight starter model.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onOpen,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open project'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onCreate,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create new'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateCountBadge extends StatelessWidget {
  const _TemplateCountBadge({
    required this.color,
    required this.textColor,
  });

  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '3 STARTER MODELS',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.width,
    required this.template,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.onPressed,
  });

  final double width;
  final WorkspaceTemplate template;
  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: 238,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: enabled ? 1.5 : 0,
        shadowColor: colors.shadow.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: width < 500 ? width * 0.42 : 218,
                height: double.infinity,
                child: RepaintBoundary(
                  child: _TemplatePreview(
                    template: template,
                    primary: colors.primary,
                    secondary: colors.tertiary,
                    surface: colors.surfaceContainerHighest,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(17, 18, 15, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(icon, size: 20, color: colors.primary),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        meta.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final background = Paint()..color = surface.withValues(alpha: 0.72);
    canvas.drawRect(Offset.zero & size, background);

    final gridPaint = Paint()
      ..color = primary.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width + size.height; x += 24) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        gridPaint,
      );
    }

    switch (template) {
      case WorkspaceTemplate.default3:
        _drawBuilding(canvas, size, floors: 3, scale: 0.90, offsetX: 0.0);
      case WorkspaceTemplate.tower9:
        _drawBuilding(canvas, size, floors: 9, scale: 0.78, offsetX: 0.0);
      case WorkspaceTemplate.campus6x9:
        for (final offset in <Offset>[
          const Offset(-0.25, 0.11),
          const Offset(0.02, -0.08),
          const Offset(0.27, 0.14),
          const Offset(-0.08, 0.28),
        ]) {
          _drawBuilding(
            canvas,
            size,
            floors: 5,
            scale: 0.38,
            offsetX: offset.dx,
            offsetY: offset.dy,
          );
        }
    }
  }

  void _drawBuilding(
    Canvas canvas,
    Size size, {
    required int floors,
    required double scale,
    required double offsetX,
    double offsetY = 0,
  }) {
    final center = Offset(
      size.width * (0.52 + offsetX),
      size.height * (0.63 + offsetY),
    );
    final width = size.width * 0.34 * scale;
    final depth = size.width * 0.17 * scale;
    final floorHeight = size.height * 0.055 * scale;
    final height = floorHeight * floors;
    final top = center.translate(-width * 0.5, -height);
    final frontBottom = center.translate(-width * 0.5, 0);
    final sideBottom = center.translate(width * 0.5, 0);
    final roof = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx + width, top.dy)
      ..lineTo(top.dx + width + depth, top.dy - depth * 0.55)
      ..lineTo(top.dx + depth, top.dy - depth * 0.55)
      ..close();
    final front = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx + width, top.dy)
      ..lineTo(sideBottom.dx, sideBottom.dy)
      ..lineTo(frontBottom.dx, frontBottom.dy)
      ..close();
    final side = Path()
      ..moveTo(top.dx + width, top.dy)
      ..lineTo(top.dx + width + depth, top.dy - depth * 0.55)
      ..lineTo(sideBottom.dx + depth, sideBottom.dy - depth * 0.55)
      ..lineTo(sideBottom.dx, sideBottom.dy)
      ..close();

    final frontFill = Paint()..color = primary.withValues(alpha: 0.18);
    final sideFill = Paint()..color = secondary.withValues(alpha: 0.17);
    final roofFill = Paint()..color = primary.withValues(alpha: 0.29);
    canvas.drawPath(front, frontFill);
    canvas.drawPath(side, sideFill);
    canvas.drawPath(roof, roofFill);

    final linePaint = Paint()
      ..color = primary.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas
      ..drawPath(front, linePaint)
      ..drawPath(side, linePaint)
      ..drawPath(roof, linePaint);

    final detailPaint = Paint()
      ..color = primary.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var floor = 1; floor < floors; floor++) {
      final y = top.dy + floorHeight * floor;
      canvas.drawLine(
          Offset(top.dx, y), Offset(top.dx + width, y), detailPaint);
    }
    final windowPaint = Paint()..color = secondary.withValues(alpha: 0.62);
    final windowW = width * 0.09;
    final windowH = floorHeight * 0.30;
    final windowGap = width * 0.11;
    for (var floor = 0; floor < floors; floor++) {
      final y = top.dy + floorHeight * floor + floorHeight * 0.35;
      for (var column = 0; column < 3; column++) {
        final x = top.dx + width * 0.18 + column * (windowW + windowGap);
        canvas.drawRect(Rect.fromLTWH(x, y, windowW, windowH), windowPaint);
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
