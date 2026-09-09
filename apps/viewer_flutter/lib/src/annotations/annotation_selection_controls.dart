import 'package:flutter/material.dart';

import 'annotation_store.dart';

/// Compact touch-first command bar for the currently selected view annotation.
///
/// The bar owns no document state. All mutations are callbacks into the
/// annotation command boundary so BIM geometry/native-cache history stays
/// completely independent.
class AnnotationSelectionControls extends StatelessWidget {
  const AnnotationSelectionControls({
    super.key,
    required this.visible,
    required this.kind,
    required this.moveArmed,
    required this.onMove,
    required this.onDelete,
    required this.onClear,
    this.onEditLabel,
  });

  final bool visible;
  final AnnotationKind? kind;
  final bool moveArmed;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback? onEditLabel;

  String get _kindLabel => switch (kind) {
        AnnotationKind.text => 'Text',
        AnnotationKind.linearDimension => 'Dimension',
        AnnotationKind.tag => 'Tag',
        AnnotationKind.detailLine => 'Detail line',
        AnnotationKind.symbol => 'Symbol',
        null => 'Annotation',
      };

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Material(
          elevation: 6,
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    _kindLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (onEditLabel != null)
                  IconButton(
                    tooltip: 'Edit label',
                    onPressed: onEditLabel,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: moveArmed
                      ? 'Cancel annotation move'
                      : 'Move annotation',
                  isSelected: moveArmed,
                  onPressed: onMove,
                  icon: Icon(
                    moveArmed ? Icons.close : Icons.open_with_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete annotation',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: 'Clear annotation selection',
                  onPressed: onClear,
                  icon: const Icon(Icons.deselect_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
