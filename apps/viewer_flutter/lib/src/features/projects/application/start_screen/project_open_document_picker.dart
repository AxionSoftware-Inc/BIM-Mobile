/// User-selected project document passed into the start flow.
final class ProjectOpenDocument {
  const ProjectOpenDocument({
    required this.json,
    required this.projectName,
    this.projectPath,
  });

  final String json;
  final String projectName;
  final String? projectPath;
}

/// Port for selecting a project document from the host platform.
abstract interface class ProjectOpenDocumentPicker {
  Future<ProjectOpenDocument?> pick();
}
