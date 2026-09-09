import 'package:flutter/material.dart';

import '../../domain/document/family_document.dart';
import 'family_sketch_viewport.dart';

/// Compatibility widget name retained for callers that still ask for a Family
/// sketch canvas. The implementation delegates to the shared-viewport-backed
/// [FamilySketchViewport]; no second painter/gesture implementation is owned.
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
