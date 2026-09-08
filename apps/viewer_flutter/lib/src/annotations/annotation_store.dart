import 'dart:typed_data';

/// Persistent annotation kinds. Generated measurements/snaps should remain
/// transient render data and must not be promoted into document entities.
enum AnnotationKind {
  text,
  linearDimension,
  tag,
  detailLine,
  symbol,
}

abstract final class AnnotationFlags {
  static const int generated = 1 << 0;
  static const int hidden = 1 << 1;
  static const int locked = 1 << 2;
}

/// Shared style referenced by id from thousands of annotation rows.
final class AnnotationStyle {
  const AnnotationStyle({
    required this.name,
    this.textHeightMeters = 0.0025,
    this.lineWeight = 1,
    this.arrowSizeMeters = 0.0025,
  });

  final String name;
  final double textHeightMeters;
  final int lineWeight;
  final double arrowSizeMeters;

  String get signature =>
      '$name\u0000$textHeightMeters\u0000$lineWeight\u0000$arrowSizeMeters';
}

/// Interned annotation text and symbol asset keys.
final class AnnotationStringPool {
  AnnotationStringPool._(this.values);

  final List<String> values;

  String operator [](int id) => values[id];
  int get length => values.length;
}

final class AnnotationTextTable {
  const AnnotationTextTable({
    required this.annotationIndices,
    required this.stringIds,
    required this.rotations,
  });

  final Uint32List annotationIndices;
  final Uint32List stringIds;
  final Float32List rotations;
}

final class AnnotationDimensionTable {
  const AnnotationDimensionTable({
    required this.annotationIndices,
    required this.referenceAIds,
    required this.referenceBIds,
    required this.startPoints,
    required this.endPoints,
    required this.offsets,
  });

  final Uint32List annotationIndices;
  final Int64List referenceAIds;
  final Int64List referenceBIds;
  final Float64List startPoints;
  final Float64List endPoints;
  final Float32List offsets;
}

final class AnnotationTagTable {
  const AnnotationTagTable({
    required this.annotationIndices,
    required this.targetElementIds,
    required this.labelStringIds,
  });

  final Uint32List annotationIndices;
  final Int64List targetElementIds;
  final Uint32List labelStringIds;
}

final class AnnotationDetailLineTable {
  const AnnotationDetailLineTable({
    required this.annotationIndices,
    required this.startPoints,
    required this.endPoints,
  });

  final Uint32List annotationIndices;
  final Float64List startPoints;
  final Float64List endPoints;
}

/// Shared-symbol placement table. Asset keys are interned in [strings], so a
/// repeated north arrow/detail marker keeps one string and N compact rows.
final class AnnotationSymbolTable {
  const AnnotationSymbolTable({
    required this.annotationIndices,
    required this.assetStringIds,
    required this.rotations,
    required this.scales,
  });

  final Uint32List annotationIndices;
  final Uint32List assetStringIds;
  final Float32List rotations;
  final Float32List scales;
}

/// Structure-of-arrays annotation database.
///
/// Common rows contain identity/view/style/anchor only. Kind-specific payloads
/// live in packed tables. This avoids one heavyweight Dart object + Maps +
/// Strings per annotation when sheets/floors contain hundreds of thousands of
/// notes, tags and dimensions.
///
/// RENDERING CONTRACT:
/// - query only the active view;
/// - text renderer should use a shared glyph atlas;
/// - lines/arrows should be batched by style;
/// - symbols should be instanced by asset/style;
/// - automatic temporary dimensions/snaps are generated overlays, not rows in
///   this persistent store unless the user explicitly commits them.
final class AnnotationStore {
  AnnotationStore._({
    required this.annotationIds,
    required this.viewIds,
    required this.levelIds,
    required this.kindCodes,
    required this.styleIds,
    required this.flags,
    required this.anchors,
    required this.styles,
    required this.strings,
    required this.text,
    required this.dimensions,
    required this.tags,
    required this.detailLines,
    required this.symbols,
    required this.viewKeys,
    required this.viewOffsets,
    required this.viewAnnotationIndices,
  });

  factory AnnotationStore.empty() => AnnotationStoreBuilder().build();

  final Int64List annotationIds;
  final Int64List viewIds;
  final Int64List levelIds;
  final Uint8List kindCodes;
  final Uint32List styleIds;
  final Uint32List flags;
  final Float64List anchors;

  final List<AnnotationStyle> styles;
  final AnnotationStringPool strings;
  final AnnotationTextTable text;
  final AnnotationDimensionTable dimensions;
  final AnnotationTagTable tags;
  final AnnotationDetailLineTable detailLines;
  final AnnotationSymbolTable symbols;

  /// CSR view index: annotation rendering never scans unrelated views/floors.
  final Int64List viewKeys;
  final Uint32List viewOffsets;
  final Uint32List viewAnnotationIndices;

  int get length => annotationIds.length;
  bool get isEmpty => length == 0;

  AnnotationKind kindAt(int annotationIndex) =>
      AnnotationKind.values[kindCodes[annotationIndex]];

  Uint32List queryView(int viewId) {
    var low = 0;
    var high = viewKeys.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final key = viewKeys[middle];
      if (key == viewId) {
        return Uint32List.fromList(
          viewAnnotationIndices.sublist(
            viewOffsets[middle],
            viewOffsets[middle + 1],
          ),
        );
      }
      if (key < viewId) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return Uint32List(0);
  }
}

final class AnnotationStoreBuilder {
  final List<int> _ids = <int>[];
  final List<int> _viewIds = <int>[];
  final List<int> _levelIds = <int>[];
  final List<int> _kinds = <int>[];
  final List<int> _styleIds = <int>[];
  final List<int> _flags = <int>[];
  final List<double> _anchors = <double>[];

  final List<AnnotationStyle> _styles = <AnnotationStyle>[];
  final Map<String, int> _styleBySignature = <String, int>{};
  final List<String> _strings = <String>[];
  final Map<String, int> _stringIds = <String, int>{};

  final List<int> _textAnnotationIndices = <int>[];
  final List<int> _textStringIds = <int>[];
  final List<double> _textRotations = <double>[];

  final List<int> _dimensionAnnotationIndices = <int>[];
  final List<int> _dimensionReferenceA = <int>[];
  final List<int> _dimensionReferenceB = <int>[];
  final List<double> _dimensionStartPoints = <double>[];
  final List<double> _dimensionEndPoints = <double>[];
  final List<double> _dimensionOffsets = <double>[];

  final List<int> _tagAnnotationIndices = <int>[];
  final List<int> _tagTargets = <int>[];
  final List<int> _tagLabelIds = <int>[];

  final List<int> _detailLineAnnotationIndices = <int>[];
  final List<double> _detailLineStartPoints = <double>[];
  final List<double> _detailLineEndPoints = <double>[];

  final List<int> _symbolAnnotationIndices = <int>[];
  final List<int> _symbolAssetStringIds = <int>[];
  final List<double> _symbolRotations = <double>[];
  final List<double> _symbolScales = <double>[];

  int _nextId = 1;

  int internString(String value) => _stringIds.putIfAbsent(value, () {
        final id = _strings.length;
        _strings.add(value);
        return id;
      });

  int internStyle(AnnotationStyle style) =>
      _styleBySignature.putIfAbsent(style.signature, () {
        final id = _styles.length;
        _styles.add(style);
        return id;
      });

  int addText({
    int? annotationId,
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String value,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Text'),
    double rotationRadians = 0,
    int flags = 0,
  }) {
    final index = _addCommon(
      annotationId: annotationId,
      viewId: viewId,
      levelId: levelId,
      kind: AnnotationKind.text,
      style: style,
      x: x,
      y: y,
      z: z,
      flags: flags,
    );
    _textAnnotationIndices.add(index);
    _textStringIds.add(internString(value));
    _textRotations.add(rotationRadians);
    return _ids[index];
  }

  int addLinearDimension({
    int? annotationId,
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
    AnnotationStyle style = const AnnotationStyle(name: 'Default Dimension'),
    int flags = 0,
  }) {
    final index = _addCommon(
      annotationId: annotationId,
      viewId: viewId,
      levelId: levelId,
      kind: AnnotationKind.linearDimension,
      style: style,
      x: anchorX,
      y: anchorY,
      z: anchorZ,
      flags: flags,
    );
    _dimensionAnnotationIndices.add(index);
    _dimensionReferenceA.add(referenceAId ?? -1);
    _dimensionReferenceB.add(referenceBId ?? -1);
    _dimensionStartPoints.addAll(<double>[startX, startY, startZ]);
    _dimensionEndPoints.addAll(<double>[endX, endY, endZ]);
    _dimensionOffsets.add(offsetMeters);
    return _ids[index];
  }

  int addTag({
    int? annotationId,
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required int targetElementId,
    required String label,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Tag'),
    int flags = 0,
  }) {
    final index = _addCommon(
      annotationId: annotationId,
      viewId: viewId,
      levelId: levelId,
      kind: AnnotationKind.tag,
      style: style,
      x: x,
      y: y,
      z: z,
      flags: flags,
    );
    _tagAnnotationIndices.add(index);
    _tagTargets.add(targetElementId);
    _tagLabelIds.add(internString(label));
    return _ids[index];
  }

  int addDetailLine({
    int? annotationId,
    required int viewId,
    required int levelId,
    required double startX,
    required double startY,
    required double startZ,
    required double endX,
    required double endY,
    required double endZ,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Detail Line'),
    int flags = 0,
  }) {
    final index = _addCommon(
      annotationId: annotationId,
      viewId: viewId,
      levelId: levelId,
      kind: AnnotationKind.detailLine,
      style: style,
      x: (startX + endX) * 0.5,
      y: (startY + endY) * 0.5,
      z: (startZ + endZ) * 0.5,
      flags: flags,
    );
    _detailLineAnnotationIndices.add(index);
    _detailLineStartPoints.addAll(<double>[startX, startY, startZ]);
    _detailLineEndPoints.addAll(<double>[endX, endY, endZ]);
    return _ids[index];
  }

  int addSymbol({
    int? annotationId,
    required int viewId,
    required int levelId,
    required double x,
    required double y,
    required double z,
    required String assetKey,
    double rotationRadians = 0,
    double scale = 1,
    AnnotationStyle style = const AnnotationStyle(name: 'Default Symbol'),
    int flags = 0,
  }) {
    final index = _addCommon(
      annotationId: annotationId,
      viewId: viewId,
      levelId: levelId,
      kind: AnnotationKind.symbol,
      style: style,
      x: x,
      y: y,
      z: z,
      flags: flags,
    );
    _symbolAnnotationIndices.add(index);
    _symbolAssetStringIds.add(internString(assetKey));
    _symbolRotations.add(rotationRadians);
    _symbolScales.add(scale.isFinite && scale > 0 ? scale : 1);
    return _ids[index];
  }

  int _addCommon({
    required int? annotationId,
    required int viewId,
    required int levelId,
    required AnnotationKind kind,
    required AnnotationStyle style,
    required double x,
    required double y,
    required double z,
    required int flags,
  }) {
    final id = annotationId ?? _nextId++;
    if (id >= _nextId) _nextId = id + 1;
    final index = _ids.length;
    _ids.add(id);
    _viewIds.add(viewId);
    _levelIds.add(levelId);
    _kinds.add(kind.index);
    _styleIds.add(internStyle(style));
    _flags.add(flags);
    _anchors.addAll(<double>[x, y, z]);
    return index;
  }

  AnnotationStore build() {
    final viewMap = <int, List<int>>{};
    for (var index = 0; index < _viewIds.length; index++) {
      (viewMap[_viewIds[index]] ??= <int>[]).add(index);
    }
    final viewKeys = viewMap.keys.toList()..sort();
    final viewOffsets = Uint32List(viewKeys.length + 1);
    var total = 0;
    for (var index = 0; index < viewKeys.length; index++) {
      viewOffsets[index] = total;
      total += viewMap[viewKeys[index]]!.length;
    }
    viewOffsets[viewKeys.length] = total;
    final viewAnnotationIndices = Uint32List(total);
    var cursor = 0;
    for (final viewKey in viewKeys) {
      for (final annotationIndex in viewMap[viewKey]!) {
        viewAnnotationIndices[cursor++] = annotationIndex;
      }
    }

    return AnnotationStore._(
      annotationIds: Int64List.fromList(_ids),
      viewIds: Int64List.fromList(_viewIds),
      levelIds: Int64List.fromList(_levelIds),
      kindCodes: Uint8List.fromList(_kinds),
      styleIds: Uint32List.fromList(_styleIds),
      flags: Uint32List.fromList(_flags),
      anchors: Float64List.fromList(_anchors),
      styles: List.unmodifiable(_styles),
      strings: AnnotationStringPool._(List.unmodifiable(_strings)),
      text: AnnotationTextTable(
        annotationIndices: Uint32List.fromList(_textAnnotationIndices),
        stringIds: Uint32List.fromList(_textStringIds),
        rotations: Float32List.fromList(_textRotations),
      ),
      dimensions: AnnotationDimensionTable(
        annotationIndices: Uint32List.fromList(_dimensionAnnotationIndices),
        referenceAIds: Int64List.fromList(_dimensionReferenceA),
        referenceBIds: Int64List.fromList(_dimensionReferenceB),
        startPoints: Float64List.fromList(_dimensionStartPoints),
        endPoints: Float64List.fromList(_dimensionEndPoints),
        offsets: Float32List.fromList(_dimensionOffsets),
      ),
      tags: AnnotationTagTable(
        annotationIndices: Uint32List.fromList(_tagAnnotationIndices),
        targetElementIds: Int64List.fromList(_tagTargets),
        labelStringIds: Uint32List.fromList(_tagLabelIds),
      ),
      detailLines: AnnotationDetailLineTable(
        annotationIndices: Uint32List.fromList(_detailLineAnnotationIndices),
        startPoints: Float64List.fromList(_detailLineStartPoints),
        endPoints: Float64List.fromList(_detailLineEndPoints),
      ),
      symbols: AnnotationSymbolTable(
        annotationIndices: Uint32List.fromList(_symbolAnnotationIndices),
        assetStringIds: Uint32List.fromList(_symbolAssetStringIds),
        rotations: Float32List.fromList(_symbolRotations),
        scales: Float32List.fromList(_symbolScales),
      ),
      viewKeys: Int64List.fromList(viewKeys),
      viewOffsets: viewOffsets,
      viewAnnotationIndices: viewAnnotationIndices,
    );
  }
}
