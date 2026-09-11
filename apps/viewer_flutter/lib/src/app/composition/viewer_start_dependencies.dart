import '../../features/projects/application/start_screen/project_open_document_picker.dart';
import '../../features/projects/application/start_screen/start_screen_recovery_repository.dart';
import '../../features/projects/application/templates/start_screen_template_preferences_repository.dart';
import '../../features/projects/infrastructure/import/file_project_open_document_picker.dart';
import '../../features/projects/infrastructure/recovery/file_start_screen_recovery_repository.dart';
import '../../features/projects/infrastructure/templates/start_screen_template_store.dart';

/// Composition-owned adapters used before a workspace is opened.
///
/// The start UI receives application ports only; platform file selectors,
/// recovery storage and preference persistence are assembled here.
final class ViewerStartDependencies {
  const ViewerStartDependencies({
    required this.projectPicker,
    required this.recovery,
    required this.templatePreferences,
  });

  factory ViewerStartDependencies.production({required String projectLabel}) =>
      ViewerStartDependencies(
        projectPicker: FileProjectOpenDocumentPicker(label: projectLabel),
        recovery: FileStartScreenRecoveryRepository(),
        templatePreferences:
            const FileStartScreenTemplatePreferencesRepository(),
      );

  final ProjectOpenDocumentPicker projectPicker;
  final StartScreenRecoveryRepository recovery;
  final StartScreenTemplatePreferencesRepository templatePreferences;
}
