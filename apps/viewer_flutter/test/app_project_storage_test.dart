import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/app_project_storage.dart';

void main() {
  test('macOS and iOS use sandbox/user Application Support', () {
    expect(
      AppProjectStorage.persistentHostPath(
        isIOS: false,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        environment: const <String, String>{'HOME': '/Users/alex'},
        pathSeparator: '/',
      ),
      '/Users/alex/Library/Application Support/TabletBIM',
    );
    expect(
      AppProjectStorage.persistentHostPath(
        isIOS: true,
        isMacOS: false,
        isWindows: false,
        isLinux: false,
        environment: const <String, String>{'HOME': '/sandbox/app'},
        pathSeparator: '/',
      ),
      '/sandbox/app/Library/Application Support/TabletBIM',
    );
  });

  test('Windows prefers LOCALAPPDATA and Linux honors XDG_DATA_HOME', () {
    expect(
      AppProjectStorage.persistentHostPath(
        isIOS: false,
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        environment: const <String, String>{
          'LOCALAPPDATA': r'C:\Users\alex\AppData\Local',
          'APPDATA': r'C:\Users\alex\AppData\Roaming',
        },
        pathSeparator: r'\',
      ),
      r'C:\Users\alex\AppData\Local\TabletBIM',
    );
    expect(
      AppProjectStorage.persistentHostPath(
        isIOS: false,
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        environment: const <String, String>{
          'HOME': '/home/alex',
          'XDG_DATA_HOME': '/home/alex/.data',
        },
        pathSeparator: '/',
      ),
      '/home/alex/.data/TabletBIM',
    );
  });

  test('unsupported/missing host environment falls back outside resolver', () {
    expect(
      AppProjectStorage.persistentHostPath(
        isIOS: false,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        environment: const <String, String>{},
        pathSeparator: '/',
      ),
      isNull,
    );
  });
}
