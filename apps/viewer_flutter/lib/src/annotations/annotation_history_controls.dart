import 'package:flutter/material.dart';

import 'annotation_workspace_runtime.dart';

/// Compact annotation-only history controls.
///
/// These intentionally do not call the BIM model undo stack. Annotation
/// snapshots are cheap packed stores and can be undone/redone without a wall,
/// floor or native-cache rebuild.
class AnnotationHistoryControls extends StatelessWidget {
  const AnnotationHistoryControls({
    super.key,
    required this.visible,
  });

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomLeft,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: AnimatedBuilder(
          // Draft state is intentionally not a document mutation. Listen to
          // both sources so Cancel enables immediately after the first point
          // of a Dimension/Detail Line without publishing a fake undo entry.
          animation: Listenable.merge(<Listenable>[
            AnnotationWorkspaceRuntime.document,
            AnnotationWorkspaceRuntime.draft,
          ]),
          builder: (context, _) {
            final document = AnnotationWorkspaceRuntime.document;
            final hasDraft = AnnotationWorkspaceRuntime.draftStart != null;
            return Material(
              elevation: 2,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh
                  .withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Undo annotation',
                      visualDensity: VisualDensity.compact,
                      onPressed: document.canUndo ? () => document.undo() : null,
                      icon: const Icon(Icons.undo, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Redo annotation',
                      visualDensity: VisualDensity.compact,
                      onPressed: document.canRedo ? () => document.redo() : null,
                      icon: const Icon(Icons.redo, size: 19),
                    ),
                    const SizedBox(height: 22, child: VerticalDivider(width: 8)),
                    IconButton(
                      tooltip: 'Cancel annotation draft',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          hasDraft ? AnnotationWorkspaceRuntime.cancelDraft : null,
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
