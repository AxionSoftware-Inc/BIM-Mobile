import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_project_storage.dart';
import 'render_scene_viewport_types.dart';

enum AppThemeMode {
  light,
  standardDark,
  amoledBlack,
}

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

@immutable
class ViewerAppSettings {
  const ViewerAppSettings({
    required this.appTheme,
    required this.viewportTheme,
  });

  const ViewerAppSettings.defaults()
      : appTheme = AppThemeMode.light,
        viewportTheme = RenderSceneViewportTheme.light;

  final AppThemeMode appTheme;
  final RenderSceneViewportTheme viewportTheme;

  ViewerAppSettings copyWith({
    AppThemeMode? appTheme,
    RenderSceneViewportTheme? viewportTheme,
  }) {
    return ViewerAppSettings(
      appTheme: appTheme ?? this.appTheme,
      viewportTheme: viewportTheme ?? this.viewportTheme,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'appTheme': appTheme.name,
        'viewportTheme': viewportTheme.name,
      };

  static ViewerAppSettings fromJson(Map<Object?, Object?> json) {
    AppThemeMode parseAppTheme(Object? value) =>
        AppThemeMode.values
            .where((candidate) => candidate.name == value?.toString())
            .firstOrNull ??
        AppThemeMode.light;

    RenderSceneViewportTheme parseViewportTheme(Object? value) =>
        RenderSceneViewportTheme.values
            .where((candidate) => candidate.name == value?.toString())
            .firstOrNull ??
        RenderSceneViewportTheme.light;

    return ViewerAppSettings(
      appTheme: parseAppTheme(json['appTheme']),
      viewportTheme: parseViewportTheme(json['viewportTheme']),
    );
  }
}

abstract final class ViewerAppSettingsStore {
  static const String _fileName = 'tablet_bim_settings.json';

  static Future<ViewerAppSettings> load() async {
    try {
      final directory = await AppProjectStorage.projectDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$_fileName',
      );
      if (!await file.exists()) return const ViewerAppSettings.defaults();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const ViewerAppSettings.defaults();
      return ViewerAppSettings.fromJson(decoded.cast<Object?, Object?>());
    } catch (_) {
      return const ViewerAppSettings.defaults();
    }
  }

  static Future<void> save(ViewerAppSettings settings) async {
    try {
      final directory = await AppProjectStorage.projectDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$_fileName',
      );
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Appearance remains usable for the current session even when a host
      // does not expose persistent app storage.
    }
  }
}

ThemeData viewerThemeFor(AppThemeMode mode) {
  if (mode == AppThemeMode.light) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F5D4E),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F6F4),
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );
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
  return ThemeData(
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
  );
}

class ViewerSettingsDialog extends StatefulWidget {
  const ViewerSettingsDialog({
    super.key,
    required this.appTheme,
    required this.viewportTheme,
    required this.onAppThemeChanged,
    required this.onViewportThemeChanged,
  });

  final AppThemeMode appTheme;
  final RenderSceneViewportTheme viewportTheme;
  final ValueChanged<AppThemeMode> onAppThemeChanged;
  final ValueChanged<RenderSceneViewportTheme> onViewportThemeChanged;

  @override
  State<ViewerSettingsDialog> createState() => _ViewerSettingsDialogState();
}

class _ViewerSettingsDialogState extends State<ViewerSettingsDialog> {
  late AppThemeMode _appTheme = widget.appTheme;
  late RenderSceneViewportTheme _viewportTheme = widget.viewportTheme;

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
              RadioGroup<RenderSceneViewportTheme>(
                groupValue: _viewportTheme,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _viewportTheme = value);
                  widget.onViewportThemeChanged(value);
                },
                child: Column(
                  children: <Widget>[
                    for (final mode in RenderSceneViewportTheme.values)
                      RadioListTile<RenderSceneViewportTheme>(
                        value: mode,
                        secondary: Icon(mode.icon),
                        title: Text(mode.label),
                        subtitle: Text(mode.description),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
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
