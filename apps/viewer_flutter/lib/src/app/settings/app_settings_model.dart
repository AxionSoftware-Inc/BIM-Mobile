/// Application-shell theme selection.
///
/// Presentation labels/icons intentionally live in the presentation adapter;
/// this enum is persisted as a stable semantic value only.
enum AppThemeMode {
  light,
  standardDark,
  amoledBlack,
}

/// Persisted viewport appearance preference.
///
/// The renderer-specific `RenderSceneViewportTheme` mapping belongs to the
/// presentation boundary so this settings model stays Flutter-independent.
enum AppViewportTheme {
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
        viewportTheme = AppViewportTheme.light,
        onboardingComplete = false,
        largeTouchTargets = true,
        highContrast = false,
        textScale = 1.0;

  final AppThemeMode appTheme;
  final AppViewportTheme viewportTheme;
  final bool onboardingComplete;
  final bool largeTouchTargets;
  final bool highContrast;
  final double textScale;

  ViewerAppSettings copyWith({
    AppThemeMode? appTheme,
    AppViewportTheme? viewportTheme,
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

    AppViewportTheme parseViewportTheme(Object? value) =>
        AppViewportTheme.values
            .where((candidate) => candidate.name == value?.toString())
            .firstOrNull ??
        AppViewportTheme.light;

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
