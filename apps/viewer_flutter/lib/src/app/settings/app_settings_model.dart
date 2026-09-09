import '../../render_scene_viewport_types.dart';

/// Application-shell theme selection.
///
/// Presentation labels/icons intentionally live in the presentation adapter;
/// this enum is persisted as a stable semantic value only.
enum AppThemeMode {
  light,
  standardDark,
  amoledBlack,
}

/// Persisted application/viewer preferences.
///
/// This model owns values only. File I/O belongs to the settings store and
/// Material/Widget concerns belong to the presentation adapter.
final class ViewerAppSettings {
  const ViewerAppSettings({
    required this.appTheme,
    required this.viewportTheme,
    required this.onboardingComplete,
    required this.largeTouchTargets,
    required this.highContrast,
    required this.textScale,
  });

  const ViewerAppSettings.defaults()
      : appTheme = AppThemeMode.light,
        viewportTheme = RenderSceneViewportTheme.light,
        onboardingComplete = false,
        largeTouchTargets = true,
        highContrast = false,
        textScale = 1.0;

  final AppThemeMode appTheme;
  final RenderSceneViewportTheme viewportTheme;
  final bool onboardingComplete;
  final bool largeTouchTargets;
  final bool highContrast;
  final double textScale;

  ViewerAppSettings copyWith({
    AppThemeMode? appTheme,
    RenderSceneViewportTheme? viewportTheme,
    bool? onboardingComplete,
    bool? largeTouchTargets,
    bool? highContrast,
    double? textScale,
  }) {
    return ViewerAppSettings(
      appTheme: appTheme ?? this.appTheme,
      viewportTheme: viewportTheme ?? this.viewportTheme,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      largeTouchTargets: largeTouchTargets ?? this.largeTouchTargets,
      highContrast: highContrast ?? this.highContrast,
      textScale: textScale ?? this.textScale,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'appTheme': appTheme.name,
        'viewportTheme': viewportTheme.name,
        'onboardingComplete': onboardingComplete,
        'largeTouchTargets': largeTouchTargets,
        'highContrast': highContrast,
        'textScale': textScale,
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
      onboardingComplete: json['onboardingComplete'] == true,
      largeTouchTargets: json['largeTouchTargets'] != false,
      highContrast: json['highContrast'] == true,
      textScale:
          ((json['textScale'] as num?)?.toDouble() ?? 1.0).clamp(0.9, 1.35),
    );
  }
}
