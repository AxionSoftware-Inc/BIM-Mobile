import 'dart:io';

import '../../../core/application/engine/viewer_engine_contracts.dart';
import '../../../core/application/engine/viewer_project_gateway.dart';
import 'project_companion_document.dart';

/// Application use-cases for durable project checkpoints and replacement.
///
/// Widgets work with semantic commands only. Session handles, source-path
/// precedence and native JSON serialization stay behind the project gateway.
final class ProjectPersistenceService {
  ProjectPersistenceService({
    required ViewerProjectGateway? Function() repository,
    required bool Function() engineEnabled,
    ProjectCompanionDocuments? companions,
  })  : _repository = repository,
        _engineEnabled = engineEnabled,
        _companions = companions ?? ProjectCompanionDocuments.empty;

  final ViewerProjectGateway? Function() _repository;
  final bool Function() _engineEnabled;
  final ProjectCompanionDocuments _companions;

  Future<String> exportJson() => _requireRepository().saveProjectJson();

  Future<File> saveToDefaultLocation() async {
    final projectFile =
        await _requireRepository().saveProjectToDefaultLocation();
    await _companions.saveForProjectPath(projectFile.path);
    return projectFile;
  }

  Future<ViewerLoadResult> replaceFromJson({
    required String projectName,
    required String json,
  }) =>
      _requireRepository().loadFromJson(
        projectName: projectName,
        json: json,
      );

  Future<ViewerLoadResult> replaceFromIfc({required String ifcPath}) =>
      _requireRepository().loadFromIfc(ifcPath: ifcPath);

  Future<void> exportIfc({required String path}) =>
      _requireRepository().exportIfc(path: path);

  Future<Map<String, dynamic>> getUnitSettings() =>
      _requireRepository().getUnitSettings();

  Future<void> setUnitSettings({
    required String system,
    required String length,
    required String angle,
  }) =>
      _requireRepository().setUnitSettings(
        system: system,
        length: length,
        angle: angle,
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
