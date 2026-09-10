import 'dart:convert';
import 'dart:io';

import '../../../../app_project_storage.dart';
import '../../../../atomic_file_writer.dart';
import '../../application/templates/start_screen_template_preferences.dart';

/// Local persistence adapter for start-screen template preferences.
abstract final class StartScreenTemplateStore {
  static const _fileName = 'start_screen_templates.json';
  static final SerializedFileWriter _writer = SerializedFileWriter();

  static Future<StartScreenTemplatePreferences> load() async {
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

  static Future<void> save(StartScreenTemplatePreferences preferences) async {
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
