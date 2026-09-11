// COMPATIBILITY: temporary facade for legacy start-screen imports.
// REMOVE WHEN: viewer app composition imports canonical projects modules directly.
export 'features/projects/presentation/start_screen.dart';
export 'features/projects/application/start_screen/start_screen_models.dart';
export 'features/projects/application/start_screen/project_launch_controller.dart';
export 'features/projects/application/start_screen/start_screen_recovery_repository.dart';
export 'features/projects/infrastructure/recovery/file_start_screen_recovery_repository.dart'
    show FileStartScreenRecoveryRepository;
export 'features/projects/infrastructure/templates/start_screen_template_store.dart'
    show FileStartScreenTemplatePreferencesRepository;
