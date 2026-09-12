import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../application/schedule_csv_export_service.dart';

/// Adapts schedule exports to the host platform.
///
/// Android uses the Storage Access Framework instead of file_selector's
/// desktop-only save-location API. This avoids broad storage permissions and
/// lets the user choose Downloads or another document-provider location.
final class PlatformScheduleCsvExportPort implements ScheduleCsvExportPort {
  const PlatformScheduleCsvExportPort();

  static const MethodChannel _androidChannel = MethodChannel('tbe/file_export');

  @override
  Future<String?> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    if (Platform.isAndroid) {
      return _androidChannel
          .invokeMethod<String>('saveTextFile', <String, Object?>{
        'fileName': suggestedName,
        'mimeType': 'text/csv',
        'contents': contents,
      });
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(contents, flush: true);
    return location.path;
  }
}
