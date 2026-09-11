import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/annotations/application/annotation_workspace_runtime.dart';

void main() {
  setUp(AnnotationWorkspaceRuntime.resetProject);

  test('selected annotation move is transient and selection-scoped', () {
    expect(AnnotationWorkspaceRuntime.selectedAnnotationId.value, isNull);
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isFalse);

    AnnotationWorkspaceRuntime.armSelectedMove();
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isFalse);

    AnnotationWorkspaceRuntime.selectAnnotation(42);
    AnnotationWorkspaceRuntime.armSelectedMove();
    expect(AnnotationWorkspaceRuntime.selectedAnnotationId.value, 42);
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isTrue);

    AnnotationWorkspaceRuntime.selectAnnotation(43);
    expect(AnnotationWorkspaceRuntime.selectedAnnotationId.value, 43);
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isFalse);

    AnnotationWorkspaceRuntime.armSelectedMove();
    AnnotationWorkspaceRuntime.clearSelection();
    expect(AnnotationWorkspaceRuntime.selectedAnnotationId.value, isNull);
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isFalse);
  });

  test('view change clears transient annotation selection and move command',
      () {
    AnnotationWorkspaceRuntime.activateView(
      workspaceViewId: 'plan:level-1',
      levelId: 1,
      acceptsAnnotations: true,
    );
    AnnotationWorkspaceRuntime.selectAnnotation(7);
    AnnotationWorkspaceRuntime.armSelectedMove();

    AnnotationWorkspaceRuntime.activateView(
      workspaceViewId: 'plan:level-2',
      levelId: 2,
      acceptsAnnotations: true,
    );

    expect(AnnotationWorkspaceRuntime.selectedAnnotationId.value, isNull);
    expect(AnnotationWorkspaceRuntime.moveSelectedArmed.value, isFalse);
  });
}
