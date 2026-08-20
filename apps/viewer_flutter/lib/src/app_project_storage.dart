import 'dart:io';

import 'package:flutter/services.dart';

/// Resolves an app-owned, persistent directory without requiring a plugin.
/// Android returns Context.filesDir from the embedding; other hosts keep a
/// development fallback until their native embedding is added.
abstract final class AppProjectStorage {
  static const MethodChannel _channel = MethodChannel('tbe/app_storage');

  static Future<Directory> projectDirectory() async {
    String? path;
    if (Platform.isAndroid) {
      path = await _channel.invokeMethod<String>('getProjectDirectory');
    }
    final directory = Directory(
      path ??
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'tablet_bim_projects',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
