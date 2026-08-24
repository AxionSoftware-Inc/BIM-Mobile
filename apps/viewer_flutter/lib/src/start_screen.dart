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
                      const SizedBox(height: 28),
                      Text(
                        'Templates',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 17),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
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
          );
          final title = Text(
            'Start a project',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF173D35),
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
      height: 316,
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
          child: Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                height: 188,
                child: RepaintBoundary(
                  child: _TemplatePreview(
                    template: template,
                    primary: colors.primary,
                    secondary: colors.tertiary,
                    surface: colors.surfaceContainerHighest,
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.68),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(17, 14, 15, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(icon, size: 18, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.08,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
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
    }
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
  }) {
    const footprint = <Offset>[
      Offset(0.00, 0.00),
      Offset(1.00, 0.00),
      Offset(1.00, 0.50),
      Offset(0.58, 0.50),
      Offset(0.58, 1.00),
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
      final faceColor = edge == 0 || edge == 1 || edge == 2
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
