import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_sketch_viewport.dart';

/// Compatibility surface for older Family Authoring callers.
///
/// The former fixed-scale CustomPainter has been retired. Sketch navigation and
/// point dragging now run through [FamilySketchViewport], which reuses the
/// project plan viewport's pan/zoom, touch thresholds, hit testing and drag
/// semantics. Keeping this class name avoids breaking existing callers while
/// preventing a second family-specific viewport implementation from returning.
class FamilySketchCanvas extends StatelessWidget {
  const FamilySketchCanvas({
    super.key,
    required this.sketch,
    required this.onAddPoint,
    required this.onMovePoint,
  });

  final FamilySketch sketch;
  final ValueChanged<FamilySketchPoint> onAddPoint;
  final void Function(int index, FamilySketchPoint point) onMovePoint;

  @override
  Widget build(BuildContext context) {
    return FamilySketchViewport(
      sketch: sketch,
      onAddPoint: onAddPoint,
      onMovePoint: onMovePoint,
    );
  }
}
