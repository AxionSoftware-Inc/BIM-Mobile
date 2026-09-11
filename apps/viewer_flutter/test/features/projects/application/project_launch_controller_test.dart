import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/application/start_screen/project_launch_controller.dart';
import 'package:viewer_flutter/src/features/projects/application/start_screen/start_screen_models.dart';

void main() {
  test('template selection is one authoritative launch target', () {
    final controller = ProjectLaunchController();

    controller.openProject(
      json: '{"scene_version":1}',
      projectName: 'Existing',
      projectPath: '/tmp/existing.tbe.json',
    );
    controller.selectTemplate(ProjectTemplate.tower9);

    expect(controller.state.selectedTemplate, ProjectTemplate.tower9);
    expect(controller.state.projectJson, isNull);
    expect(controller.state.projectName, isNull);
    expect(controller.state.projectPath, isNull);
    expect(controller.state.createBlank, isFalse);
    expect(controller.state.busy, isTrue);

    controller.finishTemplateSelection();
    expect(controller.state.busy, isFalse);
  });

  test('blank and recovered project replace previous launch selection', () {
    final controller = ProjectLaunchController();

    controller.selectTemplate(ProjectTemplate.modern3);
    controller.createBlankProject();
    expect(controller.state.createBlank, isTrue);
    expect(controller.state.selectedTemplate, isNull);

    controller.recoverProject(
      json: '{"recovered":true}',
      projectName: 'Recovered project',
    );
    expect(controller.state.projectJson, '{"recovered":true}');
    expect(controller.state.projectName, 'Recovered project');
    expect(controller.state.projectPath, isNull);
    expect(controller.state.createBlank, isFalse);
  });

  test('error state does not discard the selected launch target', () {
    final controller = ProjectLaunchController();
    controller.createBlankProject();

    controller.fail('Could not continue');

    expect(controller.state.createBlank, isTrue);
    expect(controller.state.errorMessage, 'Could not continue');
    expect(controller.state.busy, isFalse);

    controller.clearError();
    expect(controller.state.errorMessage, isNull);
    expect(controller.state.createBlank, isTrue);
  });

  test('return to start resets all launch state', () {
    final controller = ProjectLaunchController();
    controller.openProject(
      json: '{}',
      projectName: 'Project',
      projectPath: '/tmp/project.json',
    );

    controller.returnToStart();

    expect(controller.state, const ProjectLaunchState());
    expect(controller.state.hasLaunchTarget, isFalse);
  });
}
