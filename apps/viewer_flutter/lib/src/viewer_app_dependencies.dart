import 'elements/bim_element_registry.dart';
import 'elements/inspector_registry.dart';
import 'native_viewer_session_factory.dart';
import 'project_lifecycle_service.dart';
import 'project_session_controller.dart';
import 'viewer_project_session.dart';

export 'model_import/model_import_models.dart';
export 'model_import/model_import_service.dart';

/// Dependencies owned by one workspace instance.
///
/// Production construction is kept in one composition root. Widgets receive
/// semantic services and do not construct FFI adapters, native sessions or
/// independent registries.
///
/// ARCHITECTURE: every production registry is assembled here. Feature code may
/// receive a registry/descriptor, but must not create a parallel global map.
final class ViewerAppDependencies {
  ViewerAppDependencies({
    required this.projectLifecycle,
    required this.projectSession,
    required this.elements,
    required this.inspectors,
  });

  factory ViewerAppDependencies.production() {
    final elements = BimElementRegistry.standard.validate();
    return ViewerAppDependencies(
      projectLifecycle: ProjectLifecycleService<ViewerEngineSession>(
        sessionFactory: NativeViewerSessionFactory(),
      ),
      projectSession: ProjectSessionController<ViewerEngineSession>(),
      elements: elements,
      inspectors: BimElementInspectorRegistry(elements),
    );
  }

  final ProjectLifecycleService<ViewerEngineSession> projectLifecycle;
  final ProjectSessionController<ViewerEngineSession> projectSession;
  final BimElementRegistry elements;
  final BimElementInspectorRegistry inspectors;

  void dispose() {
    projectSession.dispose();
  }
}
