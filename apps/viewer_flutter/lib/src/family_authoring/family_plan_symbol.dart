import 'dart:math' as math;

import 'family_document.dart';
import 'family_parameter_resolver.dart';

/// Compact, renderer-independent plan representation for a family instance.
///
/// A project instance keeps this small SVG-like symbol next to its family
/// reference. The 3D feature graph is intentionally not part of it, so a floor
/// plan can draw a family without decoding or projecting its mesh.
abstract final class FamilyPlanSymbolGenerator {
  static String svgFor(
    FamilyDocument family,
    FamilyTypeDefinition type, {
    double rotationRadians = 0.0,
  }) {
    final resolver = FamilyParameterResolver(family, type);
    final width = _lengthValue(
      family,
      resolver,
      'width',
      fallback: 1.0,
    );
    final depth = _lengthValue(
      family,
      resolver,
      'depth',
      fallback: width,
    );
    final halfWidth = width * 0.5;
    final halfDepth = depth * 0.5;
    final category = family.category;
    final paths = <String>[
      category == FamilyCategory.wallSweep
          ? _rotatedRectanglePath(
              -halfWidth,
              -halfDepth,
              halfWidth,
              halfDepth,
              rotationRadians,
            )
          : _rectanglePath(-halfWidth, -halfDepth, halfWidth, halfDepth),
    ];

    switch (category) {
      case FamilyCategory.column:
      case FamilyCategory.structural:
        final crossX = width * 0.22;
        final crossY = depth * 0.22;
        paths.add('M ${_number(-crossX)} ${_number(-halfDepth)} '
            'L ${_number(crossX)} ${_number(-halfDepth)} '
            'L ${_number(crossX)} ${_number(halfDepth)} '
            'L ${_number(-crossX)} ${_number(halfDepth)} Z');
        paths.add('M ${_number(-halfWidth)} ${_number(-crossY)} '
            'L ${_number(halfWidth)} ${_number(-crossY)} '
            'L ${_number(halfWidth)} ${_number(crossY)} '
            'L ${_number(-halfWidth)} ${_number(crossY)} Z');
      case FamilyCategory.furniture:
      case FamilyCategory.casework:
        final insetX = width * 0.08;
        final insetY = depth * 0.12;
        paths.add(_rectanglePath(
          -halfWidth + insetX,
          -halfDepth + insetY,
          halfWidth - insetX,
          halfDepth - insetY,
        ));
        paths.add('M 0 ${_number(-halfDepth + insetY)} '
            'L 0 ${_number(halfDepth - insetY)}');
      case FamilyCategory.stair:
        const treadCount = 6;
        for (var index = 1; index < treadCount; index++) {
          final y = -halfDepth + depth * index / treadCount;
          paths.add('M ${_number(-halfWidth)} ${_number(y)} '
              'L ${_number(halfWidth)} ${_number(y)}');
        }
      case FamilyCategory.door:
      case FamilyCategory.window:
      case FamilyCategory.wallSweep:
      case FamilyCategory.genericModel:
        break;
    }

    final viewBox = '${_number(-halfWidth)} ${_number(-halfDepth)} '
        '${_number(width)} ${_number(depth)}';
    final pathMarkup = paths.map((path) => '<path d="${path.trim()}"/>').join();
    return '<svg viewBox="$viewBox" data-family-category="${category.name}">$pathMarkup</svg>';
  }

  static double _lengthValue(
    FamilyDocument family,
    FamilyParameterResolver resolver,
    String id, {
    required double fallback,
  }) {
    for (final parameter in family.parameters) {
      if (parameter.id != id || parameter.kind != FamilyParameterKind.length) {
        continue;
      }
      try {
        final value = resolver.resolveNumber(id);
        if (value.isFinite && value > 0.0) return value;
      } on FormatException {
        return fallback;
      }
    }
    return fallback;
  }

  static String _rectanglePath(
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) =>
      'M ${_number(minX)} ${_number(minY)} '
      'L ${_number(maxX)} ${_number(minY)} '
      'L ${_number(maxX)} ${_number(maxY)} '
      'L ${_number(minX)} ${_number(maxY)} Z';

  static String _rotatedRectanglePath(
    double minX,
    double minY,
    double maxX,
    double maxY,
    double rotationRadians,
  ) {
    final cosine = math.cos(rotationRadians);
    final sine = math.sin(rotationRadians);
    String point(double x, double y) {
      final rotatedX = x * cosine - y * sine;
      final rotatedY = x * sine + y * cosine;
      return '${_number(rotatedX)} ${_number(rotatedY)}';
    }

    return 'M ${point(minX, minY)} '
        'L ${point(maxX, minY)} '
        'L ${point(maxX, maxY)} '
        'L ${point(minX, maxY)} Z';
  }

  static String _number(double value) {
    if (!value.isFinite) return '0';
    final rounded = double.parse(value.toStringAsFixed(5));
    return rounded.toString();
  }
}

/// Parsed subset of [FamilyPlanSymbolGenerator]'s path contract.
///
/// The generator deliberately emits only move, line and close commands. A
/// tiny parser keeps the plan painter dependency-free and avoids loading a
/// general SVG/3D package for a handful of architectural strokes.
final class FamilyPlanSymbolPath {
  const FamilyPlanSymbolPath(this.commands);

  final List<FamilyPlanSymbolCommand> commands;

  static final Map<String, List<FamilyPlanSymbolPath>> _cache =
      <String, List<FamilyPlanSymbolPath>>{};

  static List<FamilyPlanSymbolPath> parse(String svg) {
    final cached = _cache[svg];
    if (cached != null) return cached;
    final paths = <FamilyPlanSymbolPath>[];
    final pathPattern = RegExp(r'<path\b[^>]*\bd="([^"]+)"');
    for (final match in pathPattern.allMatches(svg)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final tokens = raw
          .replaceAll(',', ' ')
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList(growable: false);
      final commands = <FamilyPlanSymbolCommand>[];
      var index = 0;
      while (index < tokens.length) {
        final token = tokens[index++].toUpperCase();
        if (token == 'Z') {
          commands.add(const FamilyPlanSymbolCommand.close());
          continue;
        }
        if (token != 'M' && token != 'L' || index + 1 >= tokens.length) {
          commands.clear();
          break;
        }
        final x = double.tryParse(tokens[index++]);
        final y = double.tryParse(tokens[index++]);
        if (x == null || y == null || !x.isFinite || !y.isFinite) {
          commands.clear();
          break;
        }
        commands.add(FamilyPlanSymbolCommand.point(token, x, y));
      }
      if (commands.isNotEmpty) paths.add(FamilyPlanSymbolPath(commands));
    }
    final result = List<FamilyPlanSymbolPath>.unmodifiable(paths);
    if (_cache.length >= 64) _cache.remove(_cache.keys.first);
    _cache[svg] = result;
    return result;
  }
}

final class FamilyPlanSymbolCommand {
  const FamilyPlanSymbolCommand.point(this.kind, this.x, this.y)
      : isClose = false;
  const FamilyPlanSymbolCommand.close()
      : kind = 'Z',
        x = 0.0,
        y = 0.0,
        isClose = true;

  final String kind;
  final double x;
  final double y;
  final bool isClose;
}
