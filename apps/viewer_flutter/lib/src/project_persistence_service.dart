import 'dart:io';

import 'viewer_engine_contracts.dart';
import 'viewer_project_gateway.dart';

/// Application use-cases for durable project checkpoints and JSON replacement.
///
/// The UI works with paths and snapshots only. Session handles, source-path
/// precedence and native JSON serialization stay in the repository adapter.
class ProjectPersistenceService {
  ProjectPersistenceService({
    required ViewerProjectGateway? Function() repository,
    required bool Function() engineEnabled,
  })  : _repository = repository,
        _engineEnabled = engineEnabled;

  final ViewerProjectGateway? Function() _repository;
  final bool Function() _engineEnabled;

  Future<String> exportJson() => _requireRepository().saveProjectJson();

  Future<File> saveToDefaultLocation() =>
      _requireRepository().saveProjectToDefaultLocation();

  Future<ViewerLoadResult> replaceFromJson({
    required String projectName,
    required String json,
  }) =>
      _requireRepository().loadFromJson(
        projectName: projectName,
        json: json,
      );

  Future<ViewerLoadResult> reload() => _requireRepository().reloadCurrent();

  ViewerProjectGateway _requireRepository() {
    final repository = _repository();
    if (!_engineEnabled() || repository == null) {
      throw TbeApiException(
        'Authoritative engine is required for project persistence',
      );
    }
    return repository;
  }
}
