// COMPATIBILITY: temporary import facade for the pre-0.3.2 composition-root path.
// REMOVE WHEN: app/workspace callers import app/composition directly.
export 'app/composition/viewer_app_dependencies.dart';
export 'app/composition/viewer_start_dependencies.dart';

// Legacy exports retained until model-import callers use their feature paths.
export 'model_import/model_import_models.dart';
export 'model_import/model_import_service.dart';