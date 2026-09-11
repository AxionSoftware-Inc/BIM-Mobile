import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/features/documentation/application/document_models.dart';
import 'package:viewer_flutter/src/features/documentation/presentation/export/document_pdf_service.dart';
import 'package:viewer_flutter/src/features/documentation/presentation/sheet_workspace_controller.dart';
import 'package:viewer_flutter/src/features/elements/domain/bim_element_module.dart';
import 'package:viewer_flutter/src/features/elements/application/bim_element_registry.dart';
import 'package:viewer_flutter/src/core/domain/assemblies/floor_type_catalog.dart';
import 'package:viewer_flutter/src/features/elements/presentation/bim_element_inspector_registry.dart';
import 'package:viewer_flutter/src/features/elements/application/parameters/linear_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/opening_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/parameters/room_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/parameters/roof_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/parameters/stair_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/parameters/surface_element_parameters.dart';
import 'package:viewer_flutter/src/features/elements/application/wall_element_parameters.dart';
import 'package:viewer_flutter/src/core/domain/assemblies/wall_type_catalog.dart';
import 'package:viewer_flutter/src/features/authoring/application/scene/render_scene_editor.dart';
import 'package:viewer_flutter/src/features/schedules/application/render_scene_estimator.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_level_overlay.dart';
import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';
import 'package:viewer_flutter/src/features/viewer/infrastructure/render_scene_source.dart';
import 'package:viewer_flutter/src/features/authoring/application/scene_mutation_service.dart';
import 'package:viewer_flutter/src/features/viewer/application/scene_view_service.dart';
import 'package:viewer_flutter/src/features/projects/application/project_persistence_service.dart';
import 'package:viewer_flutter/src/features/projects/application/project_lifecycle_service.dart';
import 'package:viewer_flutter/src/features/projects/application/project_session_controller.dart';
import 'package:viewer_flutter/src/features/projects/infrastructure/project_recovery_store.dart';
import 'package:viewer_flutter/src/core/domain/units/project_unit_settings.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_viewport_controller.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_viewport_planar.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_viewport_projection.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/selection_controller.dart';
import 'package:viewer_flutter/src/features/elements/presentation/inspector_controller.dart';
import 'package:viewer_flutter/src/features/elements/presentation/property_editor/property_editor.dart';
import 'package:viewer_flutter/src/features/families/infrastructure/library/local_family_asset_repository.dart';
import 'package:viewer_flutter/src/features/authoring/application/authoring_command_service.dart';
import 'package:viewer_flutter/src/features/authoring/application/viewer_authoring_ports.dart';
import 'package:viewer_flutter/src/platform/native_engine/ffi/tbe_ffi.dart';
import 'package:viewer_flutter/src/core/application/engine/viewer_engine_contracts.dart';
import 'package:viewer_flutter/src/core/application/engine/viewer_project_gateway.dart';
import 'package:viewer_flutter/src/core/application/engine/viewer_project_session.dart';
import 'package:viewer_flutter/src/core/application/engine/viewer_scene_gateway.dart';
import 'package:viewer_flutter/src/features/authoring/presentation/tools/level_tool_controller.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/opening_authoring_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/presentation/tools/opening_tool_controller.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/plan_sketch_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/stair_authoring_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/surface_authoring_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/presentation/tools/surface_tool_controller.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/wall_authoring_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/application/geometry/wall_repair_geometry.dart';
import 'package:viewer_flutter/src/features/authoring/presentation/tools/wall_tool_controller.dart';
import 'package:viewer_flutter/src/viewer_app.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/viewport_interaction.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/viewport/viewport_gesture_controller.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/view_workspace_store.dart';
import 'package:viewer_flutter/src/features/viewer/application/navigation/view_navigation_coordinator.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/opened_view_tab.dart';
import 'package:viewer_flutter/src/features/viewer/application/navigation/view_navigation_policy.dart';
import 'package:viewer_flutter/src/core/application/concurrency/async_serial_queue.dart';
import 'package:viewer_flutter/src/features/viewer/application/viewport/viewer_viewport_scene_policy.dart';
import 'package:viewer_flutter/src/features/viewer/presentation/workspace/workspace_chrome.dart';

part 'widget_scene_geometry_tests.dart';
part 'widget_golden_authoring_scenario_tests.dart';
part 'widget_engine_integration_tests.dart';
part 'widget_editor_projection_tests.dart';
part 'widget_interaction_authoring_tests.dart';
part 'widget_workspace_documentation_tests.dart';
part 'widget_architecture_module_tests.dart';
part 'widget_authoring_tool_module_tests.dart';
part 'widget_view_navigation_policy_tests.dart';
part 'element_module_registry_tests.dart';
part 'widget_wall_type_tests.dart';

class _RecordingSceneGateway implements ViewerSceneGateway {
  int? activeLevelId;
  bool? fullSceneEnabled;

  static const RenderSceneLoadResult result = RenderSceneLoadResult(
    scene: null,
    warnings: <String>[],
    errors: <String>[],
  );

  @override
  Future<RenderSceneLoadResult> currentRenderScene() async => result;

  @override
  Future<RenderSceneLoadResult> setActiveLevel(int levelId) async {
    activeLevelId = levelId;
    return result;
  }

  @override
  Future<RenderSceneLoadResult> setFullSceneRenderScope(bool enabled) async {
    fullSceneEnabled = enabled;
    return result;
  }

  @override
  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  ) async =>
      result;
}

class _RecordingProjectGateway implements ViewerProjectGateway {
  String? receivedProjectName;
  String? receivedJson;

  @override
  Future<ViewerLoadResult> loadFromJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    receivedProjectName = projectName;
    receivedJson = json;
    return _emptyLoadResult();
  }

  @override
  Future<ViewerLoadResult> loadFromPackage({
    required String packagePath,
  }) async =>
      _emptyLoadResult();

  @override
  Future<ViewerLoadResult> loadFromIfc({required String ifcPath}) async =>
      _emptyLoadResult();

  @override
  Future<void> exportIfc({required String path}) async {}

  @override
  Future<Map<String, dynamic>> getUnitSettings() async => <String, dynamic>{
        'system': 'metric',
        'length': 'meter',
        'angle': 'degrees',
      };

  @override
  Future<void> setUnitSettings({
    required String system,
    required String length,
    required String angle,
  }) async {}

  @override
  Future<ViewerLoadResult> reloadCurrent() async => _emptyLoadResult();

  @override
  Future<String> saveProjectJson() async => '{"schema_version": 1}';

  @override
  Future<String> snapshotImportedProjectJson() async => '{"schema_version": 1}';

  @override
  Future<File> saveProjectToDefaultLocation() async =>
      File('/tmp/example.tbe.json');

  @override
  Future<RenderSceneLoadResult> undo() async => const RenderSceneLoadResult(
        scene: null,
        warnings: <String>[],
        errors: <String>[],
      );

  @override
  Future<RenderSceneLoadResult> redo() async => const RenderSceneLoadResult(
        scene: null,
        warnings: <String>[],
        errors: <String>[],
      );

  @override
  Future<({int undoCount, int redoCount})> historyCounts() async =>
      (undoCount: 0, redoCount: 0);

  @override
  Future<String> snapshotProjectJson() async => '{"schema_version": 1}';

  ViewerLoadResult _emptyLoadResult() => ViewerLoadResult(
        snapshot: ViewerSnapshot(
          projectName: 'Test project',
          engineVersion: 'test',
          apiVersion: 'test',
          schemaVersion: 1,
          levelId: 0,
          validation: ValidationSummary(
            issueCount: 0,
            warningCount: 0,
            errorCount: 0,
          ),
          schedule: ScheduleSummary(
            wallRows: 0,
            openingRows: 0,
            roomRows: 0,
            slabRows: 0,
            roofRows: 0,
            columnRows: 0,
            beamRows: 0,
            stairRows: 0,
            floorRows: 0,
            ceilingRows: 0,
            materialTakeoffRows: 0,
          ),
          svgPath: '',
          packagePath: '',
          validationMessages: const <String>[],
        ),
        hitCandidates: const <HitCandidateView>[],
      );
}

final class _FixedProjectSavePathResolver implements ProjectSavePathResolver {
  @override
  Future<String> savePath(ViewerProjectGateway repository) async =>
      '/tmp/example.tbe.json';
}

class _RecordingProjectSession extends _RecordingProjectGateway
    implements ViewerProjectSession {
  int? buildingCount;
  int? storyCount;
  int? showcaseKind;
  bool disposed = false;

  @override
  Future<RenderSceneLoadResult> createBlankProject({
    String projectName = 'New Project',
  }) async {
    return const RenderSceneLoadResult(
      scene: null,
      warnings: <String>[],
      errors: <String>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> createResidentialTemplate({
    required int buildingCount,
    required int storyCount,
  }) async {
    this.buildingCount = buildingCount;
    this.storyCount = storyCount;
    return const RenderSceneLoadResult(
      scene: null,
      warnings: <String>[],
      errors: <String>[],
    );
  }

  @override
  Future<RenderSceneLoadResult> createShowcaseTemplate({
    required int templateKind,
  }) async {
    showcaseKind = templateKind;
    return const RenderSceneLoadResult(
      scene: null,
      warnings: <String>[],
      errors: <String>[],
    );
  }

  @override
  void dispose() => disposed = true;
}

class _RecordingSessionFactory
    implements ViewerSessionFactory<_RecordingProjectSession> {
  _RecordingSessionFactory(this.session);

  final _RecordingProjectSession session;
  int createCount = 0;

  @override
  Future<_RecordingProjectSession> create() async {
    createCount += 1;
    return session;
  }
}

void main() {
  registerSceneGeometryTests();
  registerGoldenAuthoringScenarioTests();
  registerEngineIntegrationTests();
  registerEditorProjectionTests();
  registerInteractionAuthoringTests();
  registerWorkspaceDocumentationTests();
  registerArchitectureModuleTests();
  registerAuthoringToolModuleTests();
  registerViewNavigationPolicyTests();
  registerElementModuleRegistryTests();
  registerWallTypeTests();

  test('project units convert and format model lengths consistently', () {
    const units = ProjectUnitSettings(
      system: 'metric',
      length: 'centimeter',
      angle: 'degrees',
    );

    expect(units.fromMeters(1.25), closeTo(125, 1e-9));
    expect(units.toMeters(250), closeTo(2.5, 1e-9));
    expect(units.formatLength(1.25), '125.0 cm');
    expect(units.formatArea(1), '10000.00 cm²');
  });

  test(
    'project recovery store writes and removes a durable checkpoint',
    () async {
      final store = ProjectRecoveryStore();
      const projectName = 'viewer-recovery-test';
      await store.deleteForProject(projectName);
      final entry = await store.write(
        projectName: projectName,
        json: '{"schema_version": 1, "recovery": true}',
      );
      expect(await entry.readJson(), contains('recovery'));
      expect(
        (await store.list()).any(
          (candidate) => candidate.jsonPath == entry.jsonPath,
        ),
        isTrue,
      );
      await store.deleteEntry(entry);
      expect(
        (await store.list()).any(
          (candidate) => candidate.jsonPath == entry.jsonPath,
        ),
        isFalse,
      );
    },
  );

  test('project recovery entry rejects paths outside app storage', () async {
    final entry = ProjectRecoveryEntry(
      projectName: 'viewer-recovery-test',
      jsonPath: '/tmp/untrusted-recovery.json',
      updatedAt: DateTime.utc(2026),
    );

    await expectLater(
      entry.readJson(),
      throwsA(isA<StateError>()),
    );
  });

  test('showcase template lifecycle reaches the native session seam', () async {
    final session = _RecordingProjectSession();
    final service = ProjectLifecycleService<_RecordingProjectSession>(
      sessionFactory: _RecordingSessionFactory(session),
    );
    final result = await service.createShowcaseTemplate(
      existingSession: session,
      templateKind: 2,
    );
    expect(result.session, same(session));
    expect(session.showcaseKind, 2);
    expect(result.createdSession, isFalse);
  });
}
