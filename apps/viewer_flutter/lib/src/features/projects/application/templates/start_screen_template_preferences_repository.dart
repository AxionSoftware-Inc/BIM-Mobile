import 'start_screen_template_preferences.dart';

/// Application port for loading and persisting start-screen template choices.
///
/// Presentation code depends on this contract; local files, cloud sync or any
/// future host storage implementation stays behind an infrastructure adapter.
abstract interface class StartScreenTemplatePreferencesRepository {
  Future<StartScreenTemplatePreferences> load();

  Future<void> save(StartScreenTemplatePreferences preferences);
}
