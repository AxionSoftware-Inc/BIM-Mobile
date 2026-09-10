import 'package:flutter/material.dart';

import '../../core/presentation/design_system/arvela_brand.dart';
import '../../render_scene_viewport_types.dart';
import 'app_settings_model.dart';

/// Material-specific labels/icons for the persisted theme enum.
extension AppThemeModeX on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.light => 'Light',
        AppThemeMode.standardDark => 'Standard dark',
        AppThemeMode.amoledBlack => 'AMOLED black',
      };

  String get description => switch (this) {
        AppThemeMode.light => 'Clean white Revit-style workspace',
        AppThemeMode.standardDark => 'Comfortable dark grey for everyday work',
        AppThemeMode.amoledBlack => 'Pure black surfaces for AMOLED screens',
      };

  IconData get icon => switch (this) {
        AppThemeMode.light => Icons.light_mode_outlined,
        AppThemeMode.standardDark => Icons.dark_mode_outlined,
        AppThemeMode.amoledBlack => Icons.contrast_outlined,
      };
}

/// Presentation labels plus the renderer adapter for the persisted viewport
/// preference. The settings model deliberately does not import Flutter or the
/// renderer's mixed viewport-types module.
extension AppViewportThemePresentationX on AppViewportTheme {
  String get label => switch (this) {
        AppViewportTheme.light => 'Light viewport',
        AppViewportTheme.standardDark => 'Standard dark viewport',
        AppViewportTheme.amoledBlack => 'AMOLED black viewport',
      };

  String get description => switch (this) {
        AppViewportTheme.light => 'White modelling canvas',
        AppViewportTheme.standardDark => 'Revit-style dark grey canvas',
        AppViewportTheme.amoledBlack => 'Pure black modelling canvas',
      };

  IconData get icon => switch (this) {
        AppViewportTheme.light => Icons.wb_sunny_outlined,
        AppViewportTheme.standardDark => Icons.view_in_ar_outlined,
        AppViewportTheme.amoledBlack => Icons.brightness_2_outlined,
      };

  RenderSceneViewportTheme get renderSceneTheme => switch (this) {
        AppViewportTheme.light => RenderSceneViewportTheme.light,
        AppViewportTheme.standardDark => RenderSceneViewportTheme.standardDark,
        AppViewportTheme.amoledBlack => RenderSceneViewportTheme.amoledBlack,
      };
}

ThemeData viewerThemeFor(AppThemeMode mode) {
  if (mode == AppThemeMode.light) {
    return ArvelaBrand.applyTypography(ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F5D4E),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F6F4),
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    ));
  }

  final isAmoled = mode == AppThemeMode.amoledBlack;
  final surface = isAmoled ? Colors.black : const Color(0xFF202427);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF55C7A7),
    brightness: Brightness.dark,
  ).copyWith(
    surface: surface,
    surfaceContainerLowest: surface,
    surfaceContainerLow:
        isAmoled ? const Color(0xFF050505) : const Color(0xFF24292D),
    surfaceContainer:
        isAmoled ? const Color(0xFF080808) : const Color(0xFF2A3034),
    surfaceContainerHigh:
        isAmoled ? const Color(0xFF0D0D0D) : const Color(0xFF30373B),
    surfaceContainerHighest:
        isAmoled ? const Color(0xFF121212) : const Color(0xFF384045),
  );
  return ArvelaBrand.applyTypography(ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
  ));
}

ThemeData viewerAccessibilityTheme(
  ThemeData base, {
  required bool largeTouchTargets,
  required bool highContrast,
}) {
  final theme = base.copyWith(
    materialTapTargetSize: largeTouchTargets
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.shrinkWrap,
    visualDensity:
        largeTouchTargets ? VisualDensity.standard : VisualDensity.compact,
  );
  if (!highContrast) return theme;
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      outline: theme.colorScheme.onSurface,
      outlineVariant: theme.colorScheme.onSurfaceVariant,
    ),
    dividerTheme: DividerThemeData(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
      thickness: 1.25,
    ),
  );
}

class ViewerSettingsDialog extends StatefulWidget {
  const ViewerSettingsDialog({
    super.key,
    required this.appTheme,
    required this.viewportTheme,
    required this.largeTouchTargets,
    required this.highContrast,
    required this.textScale,
    required this.onAppThemeChanged,
    required this.onViewportThemeChanged,
    required this.onLargeTouchTargetsChanged,
    required this.onHighContrastChanged,
    required this.onTextScaleChanged,
  });

  final AppThemeMode appTheme;
  final AppViewportTheme viewportTheme;
  final bool largeTouchTargets;
  final bool highContrast;
  final double textScale;
  final ValueChanged<AppThemeMode> onAppThemeChanged;
  final ValueChanged<AppViewportTheme> onViewportThemeChanged;
  final ValueChanged<bool> onLargeTouchTargetsChanged;
  final ValueChanged<bool> onHighContrastChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  State<ViewerSettingsDialog> createState() => _ViewerSettingsDialogState();
}

class _ViewerSettingsDialogState extends State<ViewerSettingsDialog> {
  late AppThemeMode _appTheme = widget.appTheme;
  late AppViewportTheme _viewportTheme = widget.viewportTheme;
  late bool _largeTouchTargets = widget.largeTouchTargets;
  late bool _highContrast = widget.highContrast;
  late double _textScale = widget.textScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.settings_outlined),
          SizedBox(width: 10),
          Text('Settings'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Application theme', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              RadioGroup<AppThemeMode>(
                groupValue: _appTheme,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _appTheme = value);
                  widget.onAppThemeChanged(value);
                },
                child: Column(
                  children: <Widget>[
                    for (final mode in AppThemeMode.values)
                      RadioListTile<AppThemeMode>(
                        value: mode,
                        secondary: Icon(mode.icon),
                        title: Text(mode.label),
                        subtitle: Text(mode.description),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              const Divider(height: 28),
              Text('Viewport background', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              RadioGroup<AppViewportTheme>(
                groupValue: _viewportTheme,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _viewportTheme = value);
                  widget.onViewportThemeChanged(value);
                },
                child: Column(
                  children: <Widget>[
                    for (final mode in AppViewportTheme.values)
                      RadioListTile<AppViewportTheme>(
                        value: mode,
                        secondary: Icon(mode.icon),
                        title: Text(mode.label),
                        subtitle: Text(mode.description),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              const Divider(height: 28),
              Text('Touch accessibility', style: theme.textTheme.titleMedium),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _largeTouchTargets,
                title: const Text('Large touch targets'),
                subtitle: const Text('Keep tablet controls easy to hit'),
                onChanged: (value) {
                  setState(() => _largeTouchTargets = value);
                  widget.onLargeTouchTargetsChanged(value);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _highContrast,
                title: const Text('High contrast'),
                subtitle: const Text('Improve edge and control visibility'),
                onChanged: (value) {
                  setState(() => _highContrast = value);
                  widget.onHighContrastChanged(value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Text size'),
                subtitle: Text('${(_textScale * 100).round()}%'),
                trailing: SizedBox(
                  width: 190,
                  child: Slider(
                    value: _textScale,
                    min: 0.9,
                    max: 1.35,
                    divisions: 9,
                    label: '${(_textScale * 100).round()}%',
                    onChanged: (value) {
                      setState(() => _textScale = value);
                      widget.onTextScaleChanged(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
