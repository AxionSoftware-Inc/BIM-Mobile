import 'dart:io';

import 'package:flutter/services.dart';

/// Resolves the app-owned persistent data root used by projects, Family
/// Library content and recovery state.
///
/// Android uses Context.filesDir from the embedding. Apple/desktop hosts use
/// their standard per-user application-data locations without adding another
/// storage plugin. `systemTemp` is retained only as a last-resort development
/// fallback when the host exposes no usable home/app-data environment.
abstract final class AppProjectStorage {
  static const MethodChannel _channel = MethodChannel('tbe/app_storage');
  static const String _appDirectoryName = 'TabletBIM';

  static Future<Directory> projectDirectory() async {
    String? path;
    if (Platform.isAndroid) {
      path = await _channel.invokeMethod<String>('getProjectDirectory');
    } else {
      path = persistentHostPath(
        isIOS: Platform.isIOS,
        isMacOS: Platform.isMacOS,
        isWindows: Platform.isWindows,
        isLinux: Platform.isLinux,
        environment: Platform.environment,
        pathSeparator: Platform.pathSeparator,
      );
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

  /// Pure host-path resolver kept public for deterministic platform tests.
  static String? persistentHostPath({
    required bool isIOS,
    required bool isMacOS,
    required bool isWindows,
    required bool isLinux,
    required Map<String, String> environment,
    required String pathSeparator,
  }) {
    String join(String root, List<String> parts) => <String>[
          root.replaceAll(RegExp(r'[\\/]+$'), ''),
          ...parts,
        ].join(pathSeparator);

    final home = environment['HOME']?.trim();
    if (isIOS || isMacOS) {
      if (home == null || home.isEmpty) return null;
      return join(
        home,
        const <String>['Library', 'Application Support', _appDirectoryName],
      );
    }

    if (isWindows) {
      final localAppData = environment['LOCALAPPDATA']?.trim();
      final appData = environment['APPDATA']?.trim();
      final root = localAppData?.isNotEmpty == true
          ? localAppData!
          : appData?.isNotEmpty == true
              ? appData!
              : null;
      return root == null ? null : join(root, const <String>[_appDirectoryName]);
    }

    if (isLinux) {
      final xdg = environment['XDG_DATA_HOME']?.trim();
      if (xdg?.isNotEmpty == true) {
        return join(xdg!, const <String>[_appDirectoryName]);
      }
      if (home == null || home.isEmpty) return null;
      return join(
        home,
        const <String>['.local', 'share', _appDirectoryName],
      );
    }

    return null;
  }
}
