import 'dart:convert';
import 'dart:io';

import 'app_project_storage.dart';
import 'atomic_file_writer.dart';

/// Small, app-owned preferences for the cards shown on the start screen.
///
/// Template identity remains the enum value used by the engine. These
/// preferences only change the card label or visibility, so a rename/delete
/// cannot mutate a project that has already been opened.
final class StartScreenTemplatePreferences {
  const StartScreenTemplatePreferences({
    this.names = const <String, String>{},
    this.hidden = const <String>{},
  });

  final Map<String, String> names;
  final Set<String> hidden;

  factory StartScreenTemplatePreferences.fromJson(Object? value) {
    if (value is! Map) return const StartScreenTemplatePreferences();
    final names = <String, String>{};
    final rawNames = value['names'];
    if (rawNames is Map) {
      for (final entry in rawNames.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final title = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && title.isNotEmpty) names[key] = title;
      }
    }
    final hidden = <String>{
      if (value['hidden'] is List)
        ...(value['hidden'] as List)
            .map((entry) => entry?.toString().trim() ?? '')
            .where((entry) => entry.isNotEmpty),
    };
    return StartScreenTemplatePreferences(names: names, hidden: hidden);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'names': names,
        'hidden': hidden.toList()..sort(),
      };
}

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
      // The current session remains usable if a host temporarily rejects the
      // app-owned preferences directory.
    }
  }
}
