import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/documentation/document_models.dart';
import 'package:viewer_flutter/src/documentation/document_pdf_service.dart';
import 'package:viewer_flutter/src/documentation/sheet_workspace_controller.dart';
import 'package:viewer_flutter/src/elements/bim_element_module.dart';
import 'package:viewer_flutter/src/elements/bim_element_registry.dart';
import 'package:viewer_flutter/src/render_scene_editor.dart';
import 'package:viewer_flutter/src/render_scene_estimator.dart';
import 'package:viewer_flutter/src/render_scene_level_overlay.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';
import 'package:viewer_flutter/src/render_scene_repository.dart';
import 'package:viewer_flutter/src/scene_mutation_service.dart';
import 'package:viewer_flutter/src/scene_view_service.dart';
import 'package:viewer_flutter/src/project_persistence_service.dart';
import 'package:viewer_flutter/src/project_lifecycle_service.dart';
import 'package:viewer_flutter/src/project_session_controller.dart';
import 'package:viewer_flutter/src/project_recovery_store.dart';
import 'package:viewer_flutter/src/render_scene_viewport_controller.dart';
import 'package:viewer_flutter/src/render_scene_viewport_planar.dart';
import 'package:viewer_flutter/src/render_scene_viewport_projection.dart';
import 'package:viewer_flutter/src/render_scene_viewport_types.dart';
import 'package:viewer_flutter/src/selection_controller.dart';
import 'package:viewer_flutter/src/inspector_controller.dart';
import 'package:viewer_flutter/src/property_editor.dart';
import 'package:viewer_flutter/src/authoring_command_service.dart';
import 'package:viewer_flutter/src/tbe_ffi.dart';
import 'package:viewer_flutter/src/viewer_engine_contracts.dart';
import 'package:viewer_flutter/src/viewer_project_gateway.dart';
import 'package:viewer_flutter/src/viewer_project_session.dart';
import 'package:viewer_flutter/src/viewer_scene_gateway.dart';
import 'package:viewer_flutter/src/tools/level_tool_controller.dart';
import 'package:viewer_flutter/src/tools/opening_authoring_geometry.dart';
import 'package:viewer_flutter/src/tools/opening_tool_controller.dart';
import 'package:viewer_flutter/src/tools/plan_sketch_geometry.dart';
import 'package:viewer_flutter/src/tools/stair_authoring_geometry.dart';
import 'package:viewer_flutter/src/tools/surface_authoring_geometry.dart';
import 'package:viewer_flutter/src/tools/surface_tool_controller.dart';
import 'package:viewer_flutter/src/tools/wall_authoring_geometry.dart';
import 'package:viewer_flutter/src/tools/wall_repair_geometry.dart';
import 'package:viewer_flutter/src/tools/wall_tool_controller.dart';
import 'package:viewer_flutter/src/viewer_app.dart';
import 'package:viewer_flutter/src/viewport_interaction.dart';
import 'package:viewer_flutter/src/viewport_gesture_controller.dart';
import 'package:viewer_flutter/src/view_workspace_store.dart';
import 'package:viewer_flutter/src/view_navigation_coordinator.dart';
import 'package:viewer_flutter/src/view_tabs.dart';
import 'package:viewer_flutter/src/view_navigation_policy.dart';
import 'package:viewer_flutter/src/async_serial_queue.dart';
import 'package:viewer_flutter/src/viewer_viewport_scene_policy.dart';
import 'package:viewer_flutter/src/workspace_chrome.dart';

part 'widget_scene_geometry_tests.dart';
part 'widget_engine_integration_tests.dart';
part 'widget_editor_projection_tests.dart';
part 'widget_interaction_authoring_tests.dart';
part 'widget_workspace_documentation_tests.dart';
part 'widget_architecture_module_tests.dart';
part 'widget_authoring_tool_module_tests.dart';
part 'widget_view_navigation_policy_tests.dart';
part 'element_module_registry_tests.dart';

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

class _RecordingProjectSession extends _RecordingProjectGateway
    implements ViewerProjectSession {
  int? buildingCount;
  int? storyCount;
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
  registerEngineIntegrationTests();
  registerEditorProjectionTests();
  registerInteractionAuthoringTests();
  registerWorkspaceDocumentationTests();
  registerArchitectureModuleTests();
  registerAuthoringToolModuleTests();
  registerViewNavigationPolicyTests();
  registerElementModuleRegistryTests();

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
}
