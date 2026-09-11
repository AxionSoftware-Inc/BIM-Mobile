import 'package:file_selector/file_selector.dart';

import '../../application/start_screen/project_open_document_picker.dart';

/// Host file-selector adapter for opening an Arvela project document.
final class FileProjectOpenDocumentPicker implements ProjectOpenDocumentPicker {
  const FileProjectOpenDocumentPicker({required this.label});

  final String label;

  @override
  Future<ProjectOpenDocument?> pick() async {
    final typeGroup = XTypeGroup(
      label: label,
      extensions: const <String>['json', 'tbe.json'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return null;
    return ProjectOpenDocument(
      json: await file.readAsString(),
      projectName: file.name,
      projectPath: file.path,
    );
  }
}
