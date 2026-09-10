import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/presentation/design_system/arvela_brand.dart';
import '../application/start_screen/start_screen_models.dart';
import '../application/templates/start_screen_template_preferences.dart';
import '../application/templates/start_screen_template_preferences_repository.dart';

/// Revit-style launch page shown before a project is opened.
class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    required this.onOpen,
    required this.onCreate,
    required this.onCreateFamily,
    required this.onSelectTemplate,
    required this.onSettings,
    required this.templatePreferencesRepository,
    this.recoveryEntry,
    this.onRecover,
    this.onDismissRecovery,
    this.busy = false,
    this.errorMessage,
  });

  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final VoidCallback onCreateFamily;
  final ValueChanged<ProjectTemplate> onSelectTemplate;
  final VoidCallback onSettings;
  final StartScreenTemplatePreferencesRepository templatePreferencesRepository;
  final ProjectRecoverySummary? recoveryEntry;
  final VoidCallback? onRecover;
  final VoidCallback? onDismissRecovery;
  final bool busy;
  final String? errorMessage;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  StartScreenTemplatePreferences _preferences =
      const StartScreenTemplatePreferences();

  @override
  void initState() {
    super.initState();
    unawaited(_loadTemplatePreferences());
  }

  Future<void> _loadTemplatePreferences() async {
    final preferences = await widget.templatePreferencesRepository.load();
    if (mounted) setState(() => _preferences = preferences);
  }

  Future<void> _saveTemplatePreferences(
    StartScreenTemplatePreferences preferences,
  ) async {
    setState(() => _preferences = preferences);
    await widget.templatePreferencesRepository.save(preferences);
  }

  List<_TemplateDefinition> get _templateDefinitions => _allTemplateDefinitions
      .where((definition) =>
          !_preferences.hidden.contains(definition.template.name))
      .toList(growable: false);

  String _titleFor(_TemplateDefinition definition) =>
      _preferences.names[definition.template.name] ?? definition.title;

  Future<void> _showTemplateActions(_TemplateDefinition definition) async {
    final action = await showModalBottomSheet<_TemplateCardAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(definition.icon),
              title: Text(_titleFor(definition)),
              subtitle: const Text('Project card actions'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new_outlined),
              title: const Text('Open project'),
              onTap: () => Navigator.of(context).pop(_TemplateCardAction.open),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename card'),
              onTap: () =>
                  Navigator.of(context).pop(_TemplateCardAction.rename),
            ),
            if (_preferences.names.containsKey(definition.template.name))
              ListTile(
                leading: const Icon(Icons.restart_alt_outlined),
                title: const Text('Restore default name'),
                onTap: () =>
                    Navigator.of(context).pop(_TemplateCardAction.restoreName),
              ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Remove from start screen'),
              onTap: () =>
                  Navigator.of(context).pop(_TemplateCardAction.remove),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _TemplateCardAction.open:
        widget.onSelectTemplate(definition.template);
      case _TemplateCardAction.rename:
        await _renameTemplate(definition);
      case _TemplateCardAction.restoreName:
        final names = Map<String, String>.of(_preferences.names)
          ..remove(definition.template.name);
        await _saveTemplatePreferences(
          StartScreenTemplatePreferences(
            names: names,
            hidden: Set<String>.of(_preferences.hidden),
          ),
        );
      case _TemplateCardAction.remove:
        await _removeTemplate(definition);
    }
  }

  Future<void> _renameTemplate(_TemplateDefinition definition) async {
    final controller = TextEditingController(text: _titleFor(definition));
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project card'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(labelText: 'Card name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = title?.trim() ?? '';
    if (!mounted || normalized.isEmpty) return;
    final names = Map<String, String>.of(_preferences.names)
      ..[definition.template.name] = normalized;
    await _saveTemplatePreferences(
      StartScreenTemplatePreferences(
        names: names,
        hidden: Set<String>.of(_preferences.hidden),
      ),
    );
  }

  Future<void> _removeTemplate(_TemplateDefinition definition) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove project card?'),
        content: Text(
          '“${_titleFor(definition)}” will be hidden from the start screen. '
          'The template itself is not deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove card'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final hidden = Set<String>.of(_preferences.hidden)
      ..add(definition.template.name);
    await _saveTemplatePreferences(
      StartScreenTemplatePreferences(
        names: Map<String, String>.of(_preferences.names),
        hidden: hidden,
      ),
    );
  }

  Future<void> _restoreTemplates() => _saveTemplatePreferences(
        const StartScreenTemplatePreferences(),
      );

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
                        busy: widget.busy,
                        onSettings: widget.onSettings,
                      ),
                      const SizedBox(height: 20),
                      _StartHero(
                        busy: widget.busy,
                        onOpen: widget.onOpen,
                        onCreate: widget.onCreate,
                        onCreateFamily: widget.onCreateFamily,
                      ),
                      if (widget.recoveryEntry != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _RecoveryBanner(
                          entry: widget.recoveryEntry!,
                          busy: widget.busy,
                          onRecover: widget.onRecover,
                          onDismiss: widget.onDismissRecovery,
                        ),
                      ],
                      if (widget.errorMessage != null) ...<Widget>[
                        const SizedBox(height: 18),
                        _StartError(message: widget.errorMessage!),
                      ],
                      const SizedBox(height: 26),
                      const _StartSectionHeader(title: 'Project templates'),
                      const SizedBox(height: 12),
                      if (_templateDefinitions.isNotEmpty)
                        _StartCardGrid(
                          columnCount: columnCount,
                          gap: cardGap,
                          children: _templateDefinitions
                              .map(
                                (definition) => _TemplateCard(
                                  template: definition.template,
                                  title: _titleFor(definition),
                                  icon: definition.icon,
                                  onPressed: widget.busy
                                      ? null
                                      : () => widget.onSelectTemplate(
                                            definition.template,
                                          ),
                                  onLongPress: widget.busy
                                      ? null
                                      : () => _showTemplateActions(definition),
                                ),
                              )
                              .toList(),
                        ),
                      if (_templateDefinitions.length <
                          _allTemplateDefinitions.length) ...<Widget>[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: widget.busy ? null : _restoreTemplates,
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Restore project cards'),
                        ),
                      ],
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

enum _TemplateCardAction { open, rename, restoreName, remove }

class _TemplateDefinition {
  const _TemplateDefinition(this.template, this.title, this.icon);

  final ProjectTemplate template;
  final String title;
  final IconData icon;
}

const _allTemplateDefinitions = <_TemplateDefinition>[
  _TemplateDefinition(
    ProjectTemplate.default3,
    'Default building',
    Icons.apartment_outlined,
  ),
  _TemplateDefinition(
    ProjectTemplate.tower9,
    'Residential tower',
    Icons.location_city_outlined,
  ),
  _TemplateDefinition(
    ProjectTemplate.campus6x9,
    'Residential campus',
    Icons.grid_view_rounded,
  ),
  _TemplateDefinition(
    ProjectTemplate.town9,
    'Meadow town',
    Icons.location_city_rounded,
  ),
  _TemplateDefinition(
    ProjectTemplate.modern3,
    'Modern glass house',
    Icons.house_siding_outlined,
  ),
  _TemplateDefinition(
    ProjectTemplate.glassTower9,
    'Glass residential tower',
    Icons.business_outlined,
  ),
  _TemplateDefinition(
    ProjectTemplate.glassCampus6x9,
    'Glass courtyard campus',
    Icons.account_balance_outlined,
  ),
  _TemplateDefinition(
    ProjectTemplate.professionalHouse,
    'Professional courtyard villa',
    Icons.home_work_outlined,
  ),
];

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
    return Row(
      children: <Widget>[
        Text(
          ArvelaBrand.name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFamily: ArvelaBrand.displayFontFamily,
            fontFamilyFallback: ArvelaBrand.fontFallback,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.35,
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
  const _StartSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
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

class _StartProjectCard extends StatelessWidget {
  const _StartProjectCard({
    required this.title,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    required this.preview,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
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
        onLongPress: onLongPress,
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

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({
    required this.entry,
    required this.busy,
    required this.onRecover,
    required this.onDismiss,
  });

  final ProjectRecoverySummary entry;
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
    this.onLongPress,
  });

  final ProjectTemplate template;
  final String title;
  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _StartProjectCard(
      title: title,
      icon: icon,
      onPressed: onPressed,
      onLongPress: onLongPress,
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

  final ProjectTemplate template;
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

  final ProjectTemplate template;
  final Color primary;
  final Color secondary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = surface.withValues(alpha: 0.44);
    canvas.drawRect(Offset.zero & size, background);

    switch (template) {
      case ProjectTemplate.default3:
        _drawBuilding(canvas, size, floors: 3, scale: 0.90, offsetX: 0.0);
      case ProjectTemplate.tower9:
        _drawBuilding(canvas, size, floors: 9, scale: 0.78, offsetX: 0.0);
      case ProjectTemplate.campus6x9:
        _drawCampusGround(canvas, size);
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
      case ProjectTemplate.town9:
        _drawTownPreview(canvas, size);
      case ProjectTemplate.modern3:
        _drawModernGround(canvas, size);
        _drawBuilding(canvas, size,
            floors: 3, scale: 0.90, offsetX: 0.0, modern: true);
      case ProjectTemplate.glassTower9:
        _drawModernGround(canvas, size);
        _drawBuilding(canvas, size,
            floors: 9, scale: 0.78, offsetX: 0.0, modern: true);
      case ProjectTemplate.glassCampus6x9:
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
      case ProjectTemplate.professionalHouse:
        _drawModernGround(canvas, size);
        _drawBuilding(canvas, size,
            floors: 2, scale: 0.92, offsetX: 0.0, modern: true);
        final arcPaint = Paint()
          ..color = secondary.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(size.width * 0.50, size.height * 0.72),
            width: size.width * 0.30,
            height: size.height * 0.16,
          ),
          math.pi,
          math.pi,
          false,
          arcPaint,
        );
    }
  }

  void _drawTownPreview(Canvas canvas, Size size) {
    _drawTownGround(canvas, size);
    const offsets = <Offset>[
      Offset(-0.30, -0.16),
      Offset(-0.10, -0.20),
      Offset(0.12, -0.17),
      Offset(0.32, -0.12),
      Offset(-0.28, 0.05),
      Offset(-0.07, 0.02),
      Offset(0.15, 0.05),
      Offset(0.34, 0.08),
      Offset(-0.25, 0.23),
      Offset(-0.04, 0.20),
      Offset(0.18, 0.23),
      Offset(0.37, 0.20),
    ];
    for (var index = 0; index < offsets.length; index++) {
      final variant = index % 4;
      _drawBuilding(
        canvas,
        size,
        floors: 9,
        scale: 0.25 + variant * 0.025,
        offsetX: offsets[index].dx,
        offsetY: offsets[index].dy,
        modern: index % 5 == 0 || index % 5 == 3,
        office: index % 5 == 0 || index % 5 == 3,
        lShape: variant == 2,
      );
    }
  }

  void _drawTownGround(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.68);
    final ground = Path()
      ..moveTo(center.dx, center.dy - size.height * 0.30)
      ..lineTo(center.dx + size.width * 0.46, center.dy - size.height * 0.04)
      ..lineTo(center.dx, center.dy + size.height * 0.20)
      ..lineTo(center.dx - size.width * 0.46, center.dy - size.height * 0.04)
      ..close();
    canvas.drawPath(
      ground,
      Paint()..color = const Color(0xFF83A978).withValues(alpha: 0.38),
    );
    canvas.drawPath(
      ground,
      Paint()
        ..color = primary.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    final roadPaint = Paint()
      ..color = const Color(0xFF637177).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(7.0, size.width * 0.018);
    for (var index = -1; index <= 1; index++) {
      final y = center.dy + size.height * index * 0.16;
      canvas.drawLine(
        Offset(size.width * 0.13, y + size.height * 0.07),
        Offset(size.width * 0.87, y - size.height * 0.07),
        roadPaint,
      );
    }
    for (var index = -1; index <= 1; index++) {
      final x = center.dx + size.width * index * 0.22;
      canvas.drawLine(
        Offset(x - size.width * 0.12, size.height * 0.42),
        Offset(x + size.width * 0.12, size.height * 0.85),
        roadPaint,
      );
    }
    final plaza = Path()
      ..moveTo(center.dx - size.width * 0.09, center.dy - size.height * 0.03)
      ..lineTo(center.dx + size.width * 0.09, center.dy - size.height * 0.08)
      ..lineTo(center.dx + size.width * 0.12, center.dy + size.height * 0.01)
      ..lineTo(center.dx - size.width * 0.06, center.dy + size.height * 0.06)
      ..close();
    canvas.drawPath(
      plaza,
      Paint()..color = const Color(0xFFD4C59B).withValues(alpha: 0.72),
    );
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
    bool office = false,
    bool lShape = false,
  }) {
    final footprint = lShape
        ? const <Offset>[
            Offset(0.00, 0.00),
            Offset(1.00, 0.00),
            Offset(1.00, 0.52),
            Offset(0.58, 0.52),
            Offset(0.58, 1.00),
            Offset(0.00, 1.00),
          ]
        : const <Offset>[
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

    final windowPaint = Paint()
      ..color = (office ? const Color(0xFFB7D8DB) : secondary)
          .withValues(alpha: office ? 0.78 : 0.62);
    _drawWindowsOnEdge(
      canvas,
      project,
      footprint,
      edge: 0,
      floors: floors,
      floorHeight: floorHeight,
      columns: office ? 5 : 3,
      paint: windowPaint,
    );
    _drawWindowsOnEdge(
      canvas,
      project,
      footprint,
      edge: 1,
      floors: floors,
      floorHeight: floorHeight,
      columns: office ? 2 : 1,
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
