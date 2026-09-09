import '../../core/application/engine/viewer_project_session.dart';
import '../../features/annotations/infrastructure/annotation_project_companion.dart';
import '../../features/elements/application/bim_element_registry.dart';
import '../../features/elements/presentation/bim_element_inspector_registry.dart';
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
///
/// All services are explicit. Do not add optional constructor defaults that
/// secretly construct a second persistence/lifecycle stack for tests or custom
/// shells; tests should compose the same contracts with test adapters.
final class ViewerAppDependencies {
  const ViewerAppDependencies({
    required this.projectLifecycle,
    required this.projectPersistence,
    required this.projectSession,
    required this.elements,
    required this.inspectors,
  });

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
