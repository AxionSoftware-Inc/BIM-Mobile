import 'dart:convert';
import 'dart:io';

import '../../core/infrastructure/io/atomic_file_writer.dart';
import '../../core/infrastructure/storage/app_project_storage.dart';
import 'app_settings_model.dart';

/// Infrastructure adapter for persisted application settings.
///
/// The settings model stays storage-agnostic; this adapter owns JSON and host
/// filesystem policy and is the only settings component that touches dart:io.
abstract final class ViewerAppSettingsStore {
  static const String _fileName = 'tablet_bim_settings.json';
  static final SerializedFileWriter _writer = SerializedFileWriter();

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
      await _writer.write(file, jsonEncode(settings.toJson()));
    } catch (_) {
      // Appearance remains usable for the current session even when a host
      // does not expose persistent app storage.
    }
  }
}
