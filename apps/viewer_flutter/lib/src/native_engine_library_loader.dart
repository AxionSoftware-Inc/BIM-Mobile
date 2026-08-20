import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/services.dart';

import 'viewer_engine_contracts.dart';

/// Platform adapter responsible only for locating and opening the native C
/// engine library. ABI symbol binding belongs to `TbeViewerApi`; feature and
/// repository code must not depend on this loader.
final class NativeEngineLibraryLoader {
  NativeEngineLibraryLoader._();

  static String? _androidLibraryPath;

  /// Android's classloader knows the ABI-specific extracted location. Passing
  /// that exact path to FFI avoids vendor-dependent bare-name dlopen lookup.
  static Future<void> prepareForCurrentPlatform() async {
    if (!Platform.isAndroid || _androidLibraryPath != null) return;
    const channel = MethodChannel('tbe/native_engine');
    final info =
        await channel.invokeMapMethod<String, dynamic>('getLibraryInfo');
    final path = info?['path']?.toString();
    final loaded = info?['loaded'] == true;
    if (!loaded || path == null || path.isEmpty) {
      throw TbeApiException(
        'Android C++ engine did not load: ${info?['error'] ?? 'native library path unavailable'}',
      );
    }
    _androidLibraryPath = path;
  }

  static ffi.DynamicLibrary open() {
    final overridePath = Platform.environment['TBE_CAPI_PATH'];
    final current = Directory.current.absolute;
    final executableDir = File(Platform.resolvedExecutable).parent.absolute;

    Iterable<Directory> climbRoots(Directory start, int depth) sync* {
      var cursor = start;
      for (var index = 0; index < depth; index += 1) {
        yield cursor;
        final parent = cursor.parent;
        if (parent.path == cursor.path) break;
        cursor = parent;
      }
    }

    final repoLikeRoots = <Directory>{
      ...climbRoots(current, 8),
      ...climbRoots(executableDir, 12),
    };
    final candidates = <String>[
      if (overridePath != null && overridePath.isNotEmpty) overridePath,
      if (_androidLibraryPath != null) _androidLibraryPath!,
      if (Platform.isAndroid || Platform.isLinux) 'libtbe_capi.so',
      if (Platform.isWindows) 'tbe_capi.dll',
      if (Platform.isMacOS || Platform.isIOS) ...<String>[
        '${executableDir.path}/../Frameworks/libtbe_capi.dylib',
        '${executableDir.path}/../Resources/libtbe_capi.dylib',
      ],
      for (final root in repoLikeRoots) ..._developmentCandidates(root),
      if (Platform.isMacOS || Platform.isIOS) 'libtbe_capi.dylib',
    ];
    final attempted = <String>[];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (_isBareLibraryName(candidate) || file.existsSync()) {
        try {
          return ffi.DynamicLibrary.open(candidate);
        } catch (_) {
          attempted.add(candidate);
        }
      }
    }
    throw TbeApiException(
      'Unable to locate the TBE native library. Build `tbe_capi_shared`, set TBE_CAPI_PATH, '
      'or package libtbe_capi for this platform. Attempted: ${attempted.join(', ')}',
    );
  }

  static Iterable<String> _developmentCandidates(Directory root) sync* {
    const buildRoots = <String>['build', 'build/dev'];
    for (final buildRoot in buildRoots) {
      if (Platform.isMacOS || Platform.isIOS) {
        yield '${root.path}/$buildRoot/src/api/libtbe_capi.dylib';
        yield '${root.path}/$buildRoot/src/api/Debug/libtbe_capi.dylib';
        yield '${root.path}/$buildRoot/src/api/Release/libtbe_capi.dylib';
      } else if (Platform.isWindows) {
        yield '${root.path}/$buildRoot/src/api/tbe_capi.dll';
        yield '${root.path}/$buildRoot/src/api/Debug/tbe_capi.dll';
        yield '${root.path}/$buildRoot/src/api/Release/tbe_capi.dll';
      } else {
        yield '${root.path}/$buildRoot/src/api/libtbe_capi.so';
        yield '${root.path}/$buildRoot/src/api/Debug/libtbe_capi.so';
        yield '${root.path}/$buildRoot/src/api/Release/libtbe_capi.so';
      }
    }
  }

  static bool _isBareLibraryName(String candidate) =>
      candidate == 'libtbe_capi.dylib' ||
      candidate == 'libtbe_capi.so' ||
      candidate == 'tbe_capi.dll';
}
