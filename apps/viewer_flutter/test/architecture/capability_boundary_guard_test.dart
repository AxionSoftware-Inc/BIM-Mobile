import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authoring capabilities are split and Family stays outside core ports',
      () {
    final sourceRoot = _sourceRoot();
    final coreGatewayDirectory = Directory(
      '${sourceRoot.path}${Platform.pathSeparator}core'
      '${Platform.pathSeparator}application${Platform.pathSeparator}engine',
    );
    final oldGateway = File(
      '${coreGatewayDirectory.path}${Platform.pathSeparator}viewer_authoring_gateway.dart',
    );
    expect(oldGateway.existsSync(), isFalse);

    final session = File(
      '${coreGatewayDirectory.path}${Platform.pathSeparator}viewer_project_session.dart',
    ).readAsStringSync();
    expect(session, isNot(contains('family_authoring_gateway.dart')));
    expect(session, isNot(contains('FamilyAuthoringGateway')));

    final capabilityNames = <String>[
      'viewer_level_authoring_gateway.dart',
      'viewer_wall_authoring_gateway.dart',
      'viewer_opening_authoring_gateway.dart',
      'viewer_element_authoring_gateway.dart',
      'viewer_roof_authoring_gateway.dart',
      'viewer_stair_authoring_gateway.dart',
    ];
    for (final name in capabilityNames) {
      expect(
        File('${coreGatewayDirectory.path}${Platform.pathSeparator}$name')
            .existsSync(),
        isTrue,
        reason: 'Missing split authoring capability $name',
      );
    }
  });

  test('external import orchestration has no ProjectLifecycle dependency', () {
    final sourceRoot = _sourceRoot();
    final importService = File(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}projects${Platform.pathSeparator}infrastructure'
      '${Platform.pathSeparator}import${Platform.pathSeparator}model_import_service.dart',
    ).readAsStringSync();
    final importModels = File(
      '${sourceRoot.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}projects${Platform.pathSeparator}application'
      '${Platform.pathSeparator}import${Platform.pathSeparator}model_import_models.dart',
    ).readAsStringSync();
    expect(importService, isNot(contains('project_lifecycle_service.dart')));
    expect(importModels, isNot(contains('project_lifecycle_service.dart')));
    expect(importService, contains('ModelImportSessionLoader'));
    expect(importModels, contains('ModelImportSessionLoader'));
  });
}

Directory _sourceRoot() {
  final packageLocal = Directory('lib/src');
  if (packageLocal.existsSync()) return packageLocal.absolute;

  final repositoryLocal = Directory('apps/viewer_flutter/lib/src');
  if (repositoryLocal.existsSync()) return repositoryLocal.absolute;

  throw StateError('Could not locate apps/viewer_flutter/lib/src.');
}
