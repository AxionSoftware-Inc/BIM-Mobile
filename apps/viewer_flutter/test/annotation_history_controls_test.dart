import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/annotations/annotation_history_controls.dart';
import 'package:viewer_flutter/src/annotations/annotation_workspace_runtime.dart';
import 'package:viewer_flutter/src/render_scene_models.dart';

void main() {
  setUp(() {
    AnnotationWorkspaceRuntime.resetProject();
  });

  tearDown(() {
    AnnotationWorkspaceRuntime.resetProject();
  });

  Future<void> pumpControls(WidgetTester tester, {bool visible = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationHistoryControls(visible: visible),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('controls stay absent outside annotation mode', (tester) async {
    await pumpControls(tester, visible: false);

    expect(find.byTooltip('Undo annotation'), findsNothing);
    expect(find.byTooltip('Redo annotation'), findsNothing);
    expect(find.byTooltip('Cancel annotation draft'), findsNothing);
  });

  testWidgets('undo and redo operate only on annotation document history',
      (tester) async {
    final document = AnnotationWorkspaceRuntime.document;
    document.addText(
      viewId: 7,
      levelId: 1,
      x: 1,
      y: 2,
      z: 0,
      value: 'Room note',
    );
    expect(document.store.length, 1);

    await pumpControls(tester);
    final undo = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Undo annotation'),
        matching: find.byType(IconButton),
      ),
    );
    expect(undo.onPressed, isNotNull);

    await tester.tap(find.byTooltip('Undo annotation'));
    await tester.pump();
    expect(document.store.length, 0);
    expect(document.canRedo, isTrue);

    await tester.tap(find.byTooltip('Redo annotation'));
    await tester.pump();
    expect(document.store.length, 1);
    expect(document.store.text.annotationIndices.length, 1);
  });

  testWidgets('draft notifier enables cancel without document mutation',
      (tester) async {
    await pumpControls(tester);

    IconButton cancelButton() => tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Cancel annotation draft'),
            matching: find.byType(IconButton),
          ),
        );

    expect(cancelButton().onPressed, isNull);
    final beforeRevision = AnnotationWorkspaceRuntime.document.revision;

    AnnotationWorkspaceRuntime.draftStart = const AnnotationDraftPoint(
      kind: AnnotationDraftKind.dimension,
      point: RenderScenePoint(x: 3, y: 4, z: 0),
      referenceElementId: 55,
    );
    await tester.pump();

    expect(cancelButton().onPressed, isNotNull);
    expect(AnnotationWorkspaceRuntime.document.revision, beforeRevision);

    await tester.tap(find.byTooltip('Cancel annotation draft'));
    await tester.pump();

    expect(AnnotationWorkspaceRuntime.draftStart, isNull);
    expect(cancelButton().onPressed, isNull);
    expect(AnnotationWorkspaceRuntime.document.store.length, 0);
    expect(AnnotationWorkspaceRuntime.document.revision, beforeRevision);
  });

  test('dimension and detail-line drafts retain explicit command identity', () {
    const dimension = AnnotationDraftPoint(
      kind: AnnotationDraftKind.dimension,
      point: RenderScenePoint(x: 1, y: 2, z: 0),
    );
    const detail = AnnotationDraftPoint(
      kind: AnnotationDraftKind.detailLine,
      point: RenderScenePoint(x: 1, y: 2, z: 0),
    );

    expect(dimension.kind, isNot(detail.kind));
  });
}
