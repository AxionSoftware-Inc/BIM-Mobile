import 'dart:convert';

import 'annotation_store.dart';

/// Versioned persistence codec for the packed annotation document.
///
/// Runtime stays typed-array/data-oriented. JSON is only the durable interchange
/// form, intentionally separate from RenderScene geometry so annotation edits
/// never invalidate BIM mesh caches.
abstract final class AnnotationStoreCodec {
  static const int formatVersion = 1;

  static String encode(AnnotationStore store) => jsonEncode(toJson(store));

  static Map<String, Object?> toJson(AnnotationStore store) => <String, Object?>{
        'format': formatVersion,
        'styles': <Object?>[
          for (final style in store.styles)
            <String, Object?>{
              'name': style.name,
              'text_height_m': style.textHeightMeters,
              'line_weight': style.lineWeight,
              'arrow_size_m': style.arrowSizeMeters,
            },
        ],
        'strings': store.strings.values,
        'common': <String, Object?>{
          'ids': store.annotationIds.toList(growable: false),
          'views': store.viewIds.toList(growable: false),
          'levels': store.levelIds.toList(growable: false),
          'kinds': store.kindCodes.toList(growable: false),
          'styles': store.styleIds.toList(growable: false),
          'flags': store.flags.toList(growable: false),
          'anchors': store.anchors.toList(growable: false),
        },
        'text': <String, Object?>{
          'rows': store.text.annotationIndices.toList(growable: false),
          'strings': store.text.stringIds.toList(growable: false),
          'rotations': store.text.rotations.toList(growable: false),
        },
        'dimensions': <String, Object?>{
          'rows': store.dimensions.annotationIndices.toList(growable: false),
          'reference_a': store.dimensions.referenceAIds.toList(growable: false),
          'reference_b': store.dimensions.referenceBIds.toList(growable: false),
          'start': store.dimensions.startPoints.toList(growable: false),
          'end': store.dimensions.endPoints.toList(growable: false),
          'offsets': store.dimensions.offsets.toList(growable: false),
        },
        'tags': <String, Object?>{
          'rows': store.tags.annotationIndices.toList(growable: false),
          'targets': store.tags.targetElementIds.toList(growable: false),
          'labels': store.tags.labelStringIds.toList(growable: false),
        },
        'detail_lines': <String, Object?>{
          'rows': store.detailLines.annotationIndices.toList(growable: false),
          'start': store.detailLines.startPoints.toList(growable: false),
          'end': store.detailLines.endPoints.toList(growable: false),
        },
        'symbols': <String, Object?>{
          'rows': store.symbols.annotationIndices.toList(growable: false),
          'assets': store.symbols.assetStringIds.toList(growable: false),
          'rotations': store.symbols.rotations.toList(growable: false),
          'scales': store.symbols.scales.toList(growable: false),
        },
      };

  static AnnotationStore decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Annotation document must be a JSON object.');
    }
    return fromJson(Map<String, Object?>.from(decoded));
  }

  static AnnotationStore fromJson(Map<String, Object?> root) {
    final version = _integer(root['format']);
    if (version != formatVersion) {
      throw FormatException('Unsupported annotation format: $version');
    }

    final styles = <AnnotationStyle>[];
    for (final entry in _list(root['styles'])) {
      final map = _map(entry);
      styles.add(AnnotationStyle(
        name: map['name']?.toString() ?? 'Annotation',
        textHeightMeters: _number(map['text_height_m'], 0.0025),
        lineWeight: _integer(map['line_weight'], 1),
        arrowSizeMeters: _number(map['arrow_size_m'], 0.0025),
      ));
    }
    final strings = _list(root['strings']).map((v) => v.toString()).toList();
    final common = _map(root['common']);
    final ids = _ints(common['ids']);
    final views = _ints(common['views']);
    final levels = _ints(common['levels']);
    final kinds = _ints(common['kinds']);
    final styleIds = _ints(common['styles']);
    final flags = _ints(common['flags']);
    final anchors = _doubles(common['anchors']);
    final count = ids.length;
    if (views.length != count ||
        levels.length != count ||
        kinds.length != count ||
        styleIds.length != count ||
        flags.length != count ||
        anchors.length != count * 3) {
      throw const FormatException('Annotation common columns have mismatched lengths.');
    }

    final text = _map(root['text']);
    final textRows = _ints(text['rows']);
    final textStrings = _ints(text['strings']);
    final textRotations = _doubles(text['rotations']);
    _requireEqual('text', textRows.length, textStrings.length, textRotations.length);

    final dimensions = _map(root['dimensions']);
    final dimensionRows = _ints(dimensions['rows']);
    final referenceA = _ints(dimensions['reference_a']);
    final referenceB = _ints(dimensions['reference_b']);
    final dimensionStart = _doubles(dimensions['start']);
    final dimensionEnd = _doubles(dimensions['end']);
    final dimensionOffsets = _doubles(dimensions['offsets']);
    _requireEqual('dimension refs', dimensionRows.length, referenceA.length, referenceB.length, dimensionOffsets.length);
    if (dimensionStart.length != dimensionRows.length * 3 ||
        dimensionEnd.length != dimensionRows.length * 3) {
      throw const FormatException('Dimension point columns have mismatched lengths.');
    }

    final tags = _map(root['tags']);
    final tagRows = _ints(tags['rows']);
    final tagTargets = _ints(tags['targets']);
    final tagLabels = _ints(tags['labels']);
    _requireEqual('tag', tagRows.length, tagTargets.length, tagLabels.length);

    final detailLines = _map(root['detail_lines']);
    final detailRows = _ints(detailLines['rows']);
    final detailStart = _doubles(detailLines['start']);
    final detailEnd = _doubles(detailLines['end']);
    if (detailStart.length != detailRows.length * 3 ||
        detailEnd.length != detailRows.length * 3) {
      throw const FormatException('Detail line columns have mismatched lengths.');
    }

    final symbols = _map(root['symbols']);
    final symbolRows = _ints(symbols['rows']);
    final symbolAssets = _ints(symbols['assets']);
    final symbolRotations = _doubles(symbols['rotations']);
    final symbolScales = _doubles(symbols['scales']);
    _requireEqual('symbol', symbolRows.length, symbolAssets.length, symbolRotations.length, symbolScales.length);

    final textByRow = _indexPayload(textRows);
    final dimensionByRow = _indexPayload(dimensionRows);
    final tagByRow = _indexPayload(tagRows);
    final detailByRow = _indexPayload(detailRows);
    final symbolByRow = _indexPayload(symbolRows);
    final builder = AnnotationStoreBuilder();

    for (var row = 0; row < count; row++) {
      final kindIndex = kinds[row];
      if (kindIndex < 0 || kindIndex >= AnnotationKind.values.length) {
        throw FormatException('Invalid annotation kind at row $row.');
      }
      final styleId = styleIds[row];
      if (styleId < 0 || styleId >= styles.length) {
        throw FormatException('Invalid annotation style at row $row.');
      }
      final anchorOffset = row * 3;
      final style = styles[styleId];
      switch (AnnotationKind.values[kindIndex]) {
        case AnnotationKind.text:
          final payload = textByRow[row];
          if (payload == null) throw FormatException('Missing text payload for row $row.');
          final stringId = textStrings[payload];
          builder.addText(
            annotationId: ids[row],
            viewId: views[row],
            levelId: levels[row],
            x: anchors[anchorOffset],
            y: anchors[anchorOffset + 1],
            z: anchors[anchorOffset + 2],
            value: _stringAt(strings, stringId),
            style: style,
            rotationRadians: textRotations[payload],
            flags: flags[row],
          );
        case AnnotationKind.linearDimension:
          final payload = dimensionByRow[row];
          if (payload == null) throw FormatException('Missing dimension payload for row $row.');
          final p = payload * 3;
          builder.addLinearDimension(
            annotationId: ids[row],
            viewId: views[row],
            levelId: levels[row],
            anchorX: anchors[anchorOffset],
            anchorY: anchors[anchorOffset + 1],
            anchorZ: anchors[anchorOffset + 2],
            startX: dimensionStart[p],
            startY: dimensionStart[p + 1],
            startZ: dimensionStart[p + 2],
            endX: dimensionEnd[p],
            endY: dimensionEnd[p + 1],
            endZ: dimensionEnd[p + 2],
            referenceAId: referenceA[payload] < 0 ? null : referenceA[payload],
            referenceBId: referenceB[payload] < 0 ? null : referenceB[payload],
            offsetMeters: dimensionOffsets[payload],
            style: style,
            flags: flags[row],
          );
        case AnnotationKind.tag:
          final payload = tagByRow[row];
          if (payload == null) throw FormatException('Missing tag payload for row $row.');
          builder.addTag(
            annotationId: ids[row],
            viewId: views[row],
            levelId: levels[row],
            x: anchors[anchorOffset],
            y: anchors[anchorOffset + 1],
            z: anchors[anchorOffset + 2],
            targetElementId: tagTargets[payload],
            label: _stringAt(strings, tagLabels[payload]),
            style: style,
            flags: flags[row],
          );
        case AnnotationKind.detailLine:
          final payload = detailByRow[row];
          if (payload == null) throw FormatException('Missing detail-line payload for row $row.');
          final p = payload * 3;
          builder.addDetailLine(
            annotationId: ids[row],
            viewId: views[row],
            levelId: levels[row],
            startX: detailStart[p],
            startY: detailStart[p + 1],
            startZ: detailStart[p + 2],
            endX: detailEnd[p],
            endY: detailEnd[p + 1],
            endZ: detailEnd[p + 2],
            style: style,
            flags: flags[row],
          );
        case AnnotationKind.symbol:
          final payload = symbolByRow[row];
          if (payload == null) throw FormatException('Missing symbol payload for row $row.');
          builder.addSymbol(
            annotationId: ids[row],
            viewId: views[row],
            levelId: levels[row],
            x: anchors[anchorOffset],
            y: anchors[anchorOffset + 1],
            z: anchors[anchorOffset + 2],
            assetKey: _stringAt(strings, symbolAssets[payload]),
            rotationRadians: symbolRotations[payload],
            scale: symbolScales[payload],
            style: style,
            flags: flags[row],
          );
      }
    }
    return builder.build();
  }

  static Map<int, int> _indexPayload(List<int> rows) {
    final result = <int, int>{};
    for (var index = 0; index < rows.length; index++) {
      if (result.containsKey(rows[index])) {
        throw FormatException('Duplicate annotation payload row ${rows[index]}.');
      }
      result[rows[index]] = index;
    }
    return result;
  }

  static void _requireEqual(String label, int first, int second, [int? third, int? fourth]) {
    if (first != second || (third != null && first != third) || (fourth != null && first != fourth)) {
      throw FormatException('$label columns have mismatched lengths.');
    }
  }

  static String _stringAt(List<String> values, int index) {
    if (index < 0 || index >= values.length) {
      throw FormatException('Annotation string id $index is out of range.');
    }
    return values[index];
  }

  static Map<String, Object?> _map(Object? value) => value is Map
      ? Map<String, Object?>.from(value)
      : const <String, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];

  static List<int> _ints(Object? value) =>
      _list(value).map(_integer).toList(growable: false);

  static List<double> _doubles(Object? value) =>
      _list(value).map((entry) => _number(entry, 0)).toList(growable: false);

  static int _integer(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _number(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }
}
