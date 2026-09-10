import 'dart:io';

import '../../../../core/application/engine/viewer_project_gateway.dart';
import '../../application/project_persistence_service.dart';

/// Keeps dart:io save artifacts below the projects infrastructure boundary.
final class NativeProjectSavePathResolver implements ProjectSavePathResolver {
  const NativeProjectSavePathResolver();

  @override
  Future<String> savePath(ViewerProjectGateway repository) async {
    final artifact = await repository.saveProjectToDefaultLocation();
    if (artifact is File) return artifact.path;
    if (artifact is String && artifact.trim().isNotEmpty) return artifact;
    throw StateError(
      'Native project save returned an unsupported location artifact: '
      '${artifact.runtimeType}',
    );
  }
}
