import 'dart:typed_data';

import 'family_representation.dart';

/// Compact path opcodes retained once per shared family symbol.
abstract final class Family2dPathOpcode {
  static const int moveTo = 0;
  static const int lineTo = 1;
  static const int close = 2;
}

final class Family2dCompiledPath {
  const Family2dCompiledPath({
    required this.opcodes,
    required this.coordinates,
  });

  final Uint8List opcodes;

  /// XY pair per opcode. Close commands keep a zero pair so command lookup is
  /// O(1) and does not need a second coordinate-offset array.
  final Float32List coordinates;

  int get length => opcodes.length;
}

final class Family2dCompiledAsset {
  const Family2dCompiledAsset({
    required this.encoding,
    required this.paths,
  });

  final Family2dEncoding encoding;
  final List<Family2dCompiledPath> paths;
}

/// Immutable scene-local lookup of shared family symbols.
///
/// Instance rows retain only [Family2dRepresentationDescriptor.assetKey]. A
/// ten-thousand-chair project therefore parses one SVG/compact symbol, not ten
/// thousand copies and not one copy per viewport frame.
final class Family2dAssetLibrary {
  const Family2dAssetLibrary._(this._assets);

  factory Family2dAssetLibrary.empty() =>
      const Family2dAssetLibrary._(<String, Family2dCompiledAsset>{});

  final Map<String, Family2dCompiledAsset> _assets;

  Family2dCompiledAsset? operator [](String assetKey) => _assets[assetKey];
  int get length => _assets.length;
  bool get isEmpty => _assets.isEmpty;
}

final class Family2dAssetLibraryBuilder {
  final Map<String, Family2dCompiledAsset> _assets =
      <String, Family2dCompiledAsset>{};

  void addSvg({required String assetKey, required String svg}) {
    if (assetKey.isEmpty || svg.trim().isEmpty || _assets.containsKey(assetKey)) {
      return;
    }
    final paths = Family2dSvgCompiler.compile(svg);
    if (paths.isEmpty) return;
    _assets[assetKey] = Family2dCompiledAsset(
      encoding: Family2dEncoding.compactVector,
      paths: paths,
    );
  }

  Family2dAssetLibrary build() => Family2dAssetLibrary._(
        Map<String, Family2dCompiledAsset>.unmodifiable(_assets),
      );
}

/// Tiny SVG-path compiler for family plan symbols.
///
/// This is intentionally not a general SVG renderer. Family authoring emits
/// architectural linework; M/L/H/V/Z are enough for that contract. Unsupported
/// curves fall back to generated/bounds representation instead of pulling a
/// heavyweight SVG package into every BIM viewport.
abstract final class Family2dSvgCompiler {
  static final RegExp _pathPattern = RegExp(
    r'''<path\b[^>]*\bd\s*=\s*(?:"([^"]+)"|'([^']+)')''',
    caseSensitive: false,
  );
  static final RegExp _tokenPattern = RegExp(
    r'[A-Za-z]|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?',
  );

  static List<Family2dCompiledPath> compile(String svg) {
    final result = <Family2dCompiledPath>[];
    for (final match in _pathPattern.allMatches(svg)) {
      final data = (match.group(1) ?? match.group(2) ?? '').trim();
      final path = _compilePath(data);
      if (path != null && path.length > 0) result.add(path);
    }
    return List<Family2dCompiledPath>.unmodifiable(result);
  }

  static Family2dCompiledPath? _compilePath(String data) {
    final tokens = _tokenPattern.allMatches(data).map((m) => m.group(0)!).toList();
    if (tokens.isEmpty) return null;

    final opcodes = <int>[];
    final coordinates = <double>[];
    var index = 0;
    String? command;
    var currentX = 0.0;
    var currentY = 0.0;
    var subpathX = 0.0;
    var subpathY = 0.0;
    var firstMovePairForCommand = false;

    bool isCommand(String value) =>
        value.length == 1 && RegExp(r'[A-Za-z]').hasMatch(value);

    double? nextNumber() {
      if (index >= tokens.length || isCommand(tokens[index])) return null;
      final value = double.tryParse(tokens[index++]);
      return value?.isFinite == true ? value : null;
    }

    void emit(int opcode, double x, double y) {
      opcodes.add(opcode);
      coordinates
        ..add(x)
        ..add(y);
    }

    while (index < tokens.length) {
      if (isCommand(tokens[index])) {
        command = tokens[index++];
        final upper = command!.toUpperCase();
        if (upper == 'Z') {
          emit(Family2dPathOpcode.close, 0, 0);
          currentX = subpathX;
          currentY = subpathY;
          command = null;
          continue;
        }
        if (upper != 'M' && upper != 'L' && upper != 'H' && upper != 'V') {
          return null;
        }
        firstMovePairForCommand = upper == 'M';
      }
      if (command == null) return null;

      final relative = command == command!.toLowerCase();
      switch (command!.toUpperCase()) {
        case 'M':
        case 'L':
          final rawX = nextNumber();
          final rawY = nextNumber();
          if (rawX == null || rawY == null) return null;
          final x = relative ? currentX + rawX : rawX;
          final y = relative ? currentY + rawY : rawY;
          final move = command!.toUpperCase() == 'M' && firstMovePairForCommand;
          emit(
            move ? Family2dPathOpcode.moveTo : Family2dPathOpcode.lineTo,
            x,
            y,
          );
          currentX = x;
          currentY = y;
          if (move) {
            subpathX = x;
            subpathY = y;
            firstMovePairForCommand = false;
          }
        case 'H':
          final rawX = nextNumber();
          if (rawX == null) return null;
          currentX = relative ? currentX + rawX : rawX;
          emit(Family2dPathOpcode.lineTo, currentX, currentY);
        case 'V':
          final rawY = nextNumber();
          if (rawY == null) return null;
          currentY = relative ? currentY + rawY : rawY;
          emit(Family2dPathOpcode.lineTo, currentX, currentY);
      }
    }

    if (opcodes.isEmpty) return null;
    return Family2dCompiledPath(
      opcodes: Uint8List.fromList(opcodes),
      coordinates: Float32List.fromList(coordinates),
    );
  }
}
