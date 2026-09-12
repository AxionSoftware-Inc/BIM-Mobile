import '../../core/application/engine/viewer_project_session.dart';
import '../../features/annotations/infrastructure/annotation_project_companion.dart';
import '../../features/elements/application/bim_element_registry.dart';
import '../../features/elements/presentation/bim_element_inspector_registry.dart';
import '../../features/families/application/library/family_asset_repository.dart';
import '../../features/families/infrastructure/library/local_family_asset_repository.dart';
import '../../features/projects/application/project_companion_document.dart';
import '../../features/projects/application/project_lifecycle_service.dart';
import '../../features/projects/application/project_persistence_service.dart';
import '../../features/projects/application/project_session_controller.dart';
import '../../features/projects/application/recovery/project_recovery_checkpoint_repository.dart';
import '../../features/projects/infrastructure/persistence/native_project_save_path_resolver.dart';
import '../../features/projects/infrastructure/recovery/file_project_recovery_checkpoint_repository.dart';
import '../../features/viewer/application/scene_view_service.dart';
import '../../features/schedules/application/schedule_csv_export_service.dart';
import '../../features/schedules/infrastructure/platform_schedule_csv_export_port.dart';
import '../../platform/native_engine/native_viewer_session_factory.dart';
import 'project_session_scene_gateway_resolver.dart';

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
    required this.projectRecovery,
    required this.familyAssets,
    required this.elements,
    required this.inspectors,
    required this.scheduleCsvExport,
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
        savePathResolver: const NativeProjectSavePathResolver(),
        companions: companions,
      ),
      projectSession: projectSession,
      projectRecovery: FileProjectRecoveryCheckpointRepository(),
      familyAssets: const LocalFamilyAssetRepository(),
      elements: elements,
      inspectors: BimElementInspectorRegistry(elements),
      scheduleCsvExport: const ScheduleCsvExportService(
        PlatformScheduleCsvExportPort(),
      ),
    );
  }

  final ProjectLifecycleService<ViewerEngineSession> projectLifecycle;
  final ProjectPersistenceService projectPersistence;
  final ProjectSessionController<ViewerEngineSession> projectSession;
  final ProjectRecoveryCheckpointRepository projectRecovery;
  final FamilyAssetRepository familyAssets;
  final BimElementRegistry elements;
  final BimElementInspectorRegistry inspectors;
  final ScheduleCsvExportService scheduleCsvExport;

  /// Builds the viewer scene use-case against the same project session owned by
  /// this composition root. Presentation code should use this instead of
  /// recreating repository/engine-availability callbacks.
  SceneViewService createSceneViewService() => SceneViewService.resolved(
        ProjectSessionSceneGatewayResolver(projectSession),
      );

  void dispose() {
    projectSession.dispose();
  }
}
