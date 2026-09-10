import 'dart:convert';
import 'dart:io';

import '../../../../core/infrastructure/io/atomic_file_writer.dart';
import '../../../../core/infrastructure/storage/app_project_storage.dart';
import '../../application/templates/start_screen_template_preferences.dart';
import '../../application/templates/start_screen_template_preferences_repository.dart';

/// Local persistence adapter for start-screen template preferences.
final class FileStartScreenTemplatePreferencesRepository
    implements StartScreenTemplatePreferencesRepository {
  const FileStartScreenTemplatePreferencesRepository();

  static const _fileName = 'start_screen_templates.json';
  static final SerializedFileWriter _writer = SerializedFileWriter();

  @override
  Future<StartScreenTemplatePreferences> load() async {
    try {
      final directory = await AppProjectStorage.projectDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$_fileName',
      );
      if (!await file.exists()) {
        return const StartScreenTemplatePreferences();
      }
      return StartScreenTemplatePreferences.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return const StartScreenTemplatePreferences();
    }
  }

  @override
  Future<void> save(StartScreenTemplatePreferences preferences) async {
    try {
      final directory = await AppProjectStorage.projectDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$_fileName',
      );
      await _writer.write(file, jsonEncode(preferences.toJson()));
    } catch (_) {
      // Preference persistence is optional. A transient host storage failure
      // must never make project creation or browsing unusable.
    }
  }
}
