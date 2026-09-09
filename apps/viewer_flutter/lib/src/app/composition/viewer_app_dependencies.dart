import '../../core/application/engine/viewer_project_session.dart';
import '../../elements/bim_element_registry.dart';
import '../../elements/inspector_registry.dart';
import '../../features/annotations/infrastructure/annotation_project_companion.dart';
import '../../features/project/application/project_companion_document.dart';
import '../../features/project/application/project_lifecycle_service.dart';
import '../../features/project/application/project_persistence_service.dart';
import '../../features/project/application/project_session_controller.dart';
import '../../platform/native_engine/native_viewer_session_factory.dart';

/// Dependencies owned by one workspace instance.
///
/// This is the production composition root. Widgets receive semantic services
/// and do not construct FFI adapters, native sessions or independent registries.
///
/// ARCHITECTURE: every production registry and cross-feature adapter is
/// assembled here. Feature code receives typed contracts; it must not discover
/// another feature through globals or construct a parallel registry.
final class ViewerAppDependencies {
  ViewerAppDependencies({
    required this.projectLifecycle,
    required this.projectSession,
    required this.elements,
    required this.inspectors,
    ProjectPersistenceService? projectPersistence,
  }) : projectPersistence = projectPersistence ??
            ProjectPersistenceService(
              repository: () => projectSession.session,
              engineEnabled: () => projectSession.isEngineBacked,
            );

  factory ViewerAppDependencies.production() {
    final elements = BimElementRegistry.standard.validate();
    final projectSession = ProjectSessionController<ViewerEngineSession>();
    final companions = ProjectCompanionDocuments(
      const <ProjectCompanionDocument>[
        AnnotationProjectCompanion(),
      ],
    );

    return ViewerAppDependencies(
      projectLifecycle: ProjectLifecycleService<ViewerEngineSession>(
        sessionFactory: NativeViewerSessionFactory(),
        companions: companions,
      ),
      projectPersistence: ProjectPersistenceService(
        repository: () => projectSession.session,
        engineEnabled: () => projectSession.isEngineBacked,
        companions: companions,
      ),
      projectSession: projectSession,
      elements: elements,
      inspectors: BimElementInspectorRegistry(elements),
    );
  }

  final ProjectLifecycleService<ViewerEngineSession> projectLifecycle;
  final ProjectPersistenceService projectPersistence;
  final ProjectSessionController<ViewerEngineSession> projectSession;
  final BimElementRegistry elements;
  final BimElementInspectorRegistry inspectors;

  void dispose() {
    projectSession.dispose();
  }
}
