import 'annotation_store.dart';

/// Mutable application command boundary over the immutable packed store.
///
/// The builder is the write-side staging area; every committed command
/// publishes a new typed-array snapshot. Rendering therefore never traverses
/// mutable per-annotation UI objects.
final class AnnotationDocumentController {
  AnnotationStoreBuilder _builder = AnnotationStoreBuilder();
  AnnotationStore _store = AnnotationStore.empty();
  int _revision = 0;

  AnnotationStore get store => _store;
  int get revision => _revision;

  void reset() {
    _builder = AnnotationStoreBuilder();
    _publish();
  }

  int addText({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String value,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Text'),
    double rotationRadians = 0,
  }) {
    final id = _builder.addText(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      value: value,
      style: style,
      rotationRadians: rotationRadians,
    );
    _publish();
    return id;
  }

  int addLinearDimension({
    required int viewId,
    required int levelId,
    required double anchorX,
    required double anchorY,
    required double anchorZ,
    required double startX,
    required double startY,
    required double startZ,
    required double endX,
    required double endY,
    required double endZ,
    int? referenceAId,
    int? referenceBId,
    double offsetMeters = 0,
    AnnotationStyle style =
        const AnnotationStyle(name: 'Default Dimension'),
  }) {
    final id = _builder.addLinearDimension(
      viewId: viewId,
      levelId: levelId,
      anchorX: anchorX,
      anchorY: anchorY,
      anchorZ: anchorZ,
      startX: startX,
      startY: startY,
      startZ: startZ,
      endX: endX,
      endY: endY,
      endZ: endZ,
      referenceAId: referenceAId,
      referenceBId: referenceBId,
      offsetMeters: offsetMeters,
      style: style,
    );
    _publish();
    return id;
  }

  int addTag({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required int targetElementId,
    required String label,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Tag'),
  }) {
    final id = _builder.addTag(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      targetElementId: targetElementId,
      label: label,
      style: style,
    );
    _publish();
    return id;
  }

  int addDetailLine({
    required int viewId,
    required int levelId,
    required double startX,
    required double startY,
    required double startZ,
    required double endX,
    required double endY,
    required double endZ,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Detail Line'),
  }) {
    final id = _builder.addDetailLine(
      viewId: viewId,
      levelId: levelId,
      startX: startX,
      startY: startY,
      startZ: startZ,
      endX: endX,
      endY: endY,
      endZ: endZ,
      style: style,
    );
    _publish();
    return id;
  }

  int addSymbol({
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String assetKey,
    double rotationRadians = 0,
    double scale = 1,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Symbol'),
  }) {
    final id = _builder.addSymbol(
      viewId: viewId,
      levelId: levelId,
      x: x,
      y: y,
      z: z,
      assetKey: assetKey,
      rotationRadians: rotationRadians,
      scale: scale,
      style: style,
    );
    _publish();
    return id;
  }

  void _publish() {
    _store = _builder.build();
    _revision++;
  }
}
