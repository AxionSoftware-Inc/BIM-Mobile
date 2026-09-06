import 'dart:math' as math;

import 'family_document.dart';

/// Resolves one Family Type into the effective parameter values consumed by
/// preview, placement and plan graphics.
///
/// A formula is intentionally a numeric expression rather than an arbitrary
/// Dart snippet. Keeping the language small makes family files deterministic,
/// portable and safe to open from external sources.
///
/// Supported syntax:
///
/// - numeric literals (`1`, `0.25`, `1.2e-3`)
/// - parameter ids (`width`, `shelf_count`)
/// - `+`, `-`, `*`, `/`, parentheses and unary +/-
/// - `pi`
/// - `min(a,b)`, `max(a,b)`, `abs(x)`, `clamp(x,min,max)`
///
/// Formula-driven parameters ignore the per-type stored value for that
/// parameter. Dependencies may still read ordinary per-type values. Cycles,
/// unknown ids, division by zero and non-finite results fail explicitly.
final class FamilyParameterResolver {
  FamilyParameterResolver(this.document, this.type)
      : _parameters = <String, FamilyParameterDefinition>{
          for (final parameter in document.parameters) parameter.id: parameter,
        };

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final Map<String, FamilyParameterDefinition> _parameters;
  final Map<String, Object?> _cache = <String, Object?>{};
  final Set<String> _resolving = <String>{};

  Object? resolve(FamilyParameterDefinition parameter) =>
      resolveById(parameter.id);

  Object? resolveById(String parameterId) {
    if (_cache.containsKey(parameterId)) return _cache[parameterId];
    final parameter = _parameters[parameterId];
    if (parameter == null) {
      throw FormatException('Unknown family parameter "$parameterId".');
    }
    if (!_resolving.add(parameterId)) {
      final chain = <String>[..._resolving, parameterId].join(' -> ');
      throw FormatException('Family parameter formula cycle: $chain');
    }
    try {
      final formula = parameter.formula?.trim();
      final Object? value;
      if (formula != null && formula.isNotEmpty) {
        if (!_isNumericKind(parameter.kind)) {
          throw FormatException(
            'Formula parameter "${parameter.label}" must be numeric.',
          );
        }
        value = _ExpressionParser(
          formula,
          resolveIdentifier: _resolveNumericIdentifier,
        ).parse();
      } else {
        value = type.values.containsKey(parameter.id)
            ? type.values[parameter.id]
            : parameter.defaultValue;
      }
      _validateResolvedValue(parameter, value);
      _cache[parameterId] = value;
      return value;
    } finally {
      _resolving.remove(parameterId);
    }
  }

  double resolveNumber(String parameterId) {
    final value = resolveById(parameterId);
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) {
      throw FormatException(
        'Family parameter "$parameterId" does not resolve to a finite number.',
      );
    }
    return number;
  }

  Map<String, Object?> resolveAll() => <String, Object?>{
        for (final parameter in document.parameters)
          parameter.id: resolve(parameter),
      };

  double _resolveNumericIdentifier(String id) {
    if (id == 'pi') return math.pi;
    final parameter = _parameters[id];
    if (parameter == null) {
      throw FormatException('Unknown parameter "$id" in family formula.');
    }
    if (!_isNumericKind(parameter.kind)) {
      throw FormatException(
        'Formula cannot use non-numeric parameter "${parameter.label}".',
      );
    }
    return resolveNumber(id);
  }

  static void _validateResolvedValue(
    FamilyParameterDefinition parameter,
    Object? value,
  ) {
    switch (parameter.kind) {
      case FamilyParameterKind.boolean:
        if (value is! bool) {
          throw FormatException('${parameter.label} must be true or false.');
        }
      case FamilyParameterKind.text:
      case FamilyParameterKind.material:
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('${parameter.label} must be non-empty text.');
        }
      case FamilyParameterKind.length:
      case FamilyParameterKind.number:
      case FamilyParameterKind.angle:
        final number = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (number == null || !number.isFinite) {
          throw FormatException('${parameter.label} must be a finite number.');
        }
        if (parameter.kind == FamilyParameterKind.length && number <= 0.0) {
          throw FormatException('${parameter.label} must be positive.');
        }
        if (parameter.minimum != null && number < parameter.minimum!) {
          throw FormatException('${parameter.label} is below its minimum.');
        }
        if (parameter.maximum != null && number > parameter.maximum!) {
          throw FormatException('${parameter.label} is above its maximum.');
        }
    }
  }

  static bool _isNumericKind(FamilyParameterKind kind) =>
      kind == FamilyParameterKind.length ||
      kind == FamilyParameterKind.number ||
      kind == FamilyParameterKind.angle;
}

final class _ExpressionParser {
  _ExpressionParser(
    this.source, {
    required this.resolveIdentifier,
  });

  final String source;
  final double Function(String id) resolveIdentifier;
  int _offset = 0;

  double parse() {
    final result = _expression();
    _skipWhitespace();
    if (_offset != source.length) {
      throw FormatException(
        'Unexpected token in family formula near "${source.substring(_offset)}".',
      );
    }
    if (!result.isFinite) {
      throw const FormatException('Family formula produced a non-finite result.');
    }
    return result;
  }

  double _expression() {
    var value = _term();
    while (true) {
      _skipWhitespace();
      if (_consume('+')) {
        value += _term();
      } else if (_consume('-')) {
        value -= _term();
      } else {
        return value;
      }
      _requireFinite(value);
    }
  }

  double _term() {
    var value = _unary();
    while (true) {
      _skipWhitespace();
      if (_consume('*')) {
        value *= _unary();
      } else if (_consume('/')) {
        final divisor = _unary();
        if (divisor.abs() <= 1.0e-12) {
          throw const FormatException('Division by zero in family formula.');
        }
        value /= divisor;
      } else {
        return value;
      }
      _requireFinite(value);
    }
  }

  double _unary() {
    _skipWhitespace();
    if (_consume('+')) return _unary();
    if (_consume('-')) return -_unary();
    return _primary();
  }

  double _primary() {
    _skipWhitespace();
    if (_consume('(')) {
      final value = _expression();
      _skipWhitespace();
      if (!_consume(')')) {
        throw const FormatException('Missing ")" in family formula.');
      }
      return value;
    }
    final number = _number();
    if (number != null) return number;
    final identifier = _identifier();
    if (identifier == null) {
      throw FormatException(
        'Expected a number or parameter at position $_offset in family formula.',
      );
    }
    _skipWhitespace();
    if (!_consume('(')) return resolveIdentifier(identifier);

    final arguments = <double>[];
    _skipWhitespace();
    if (!_consume(')')) {
      while (true) {
        arguments.add(_expression());
        _skipWhitespace();
        if (_consume(')')) break;
        if (!_consume(',')) {
          throw const FormatException(
            'Expected "," or ")" in family formula function.',
          );
        }
      }
    }
    return _call(identifier, arguments);
  }

  double _call(String name, List<double> arguments) {
    switch (name) {
      case 'min':
        _requireArity(name, arguments, 2);
        return math.min(arguments[0], arguments[1]);
      case 'max':
        _requireArity(name, arguments, 2);
        return math.max(arguments[0], arguments[1]);
      case 'abs':
        _requireArity(name, arguments, 1);
        return arguments[0].abs();
      case 'clamp':
        _requireArity(name, arguments, 3);
        if (arguments[1] > arguments[2]) {
          throw const FormatException(
            'clamp minimum cannot be greater than maximum.',
          );
        }
        return arguments[0].clamp(arguments[1], arguments[2]).toDouble();
      default:
        throw FormatException('Unknown family formula function "$name".');
    }
  }

  double? _number() {
    _skipWhitespace();
    final start = _offset;
    var sawDigit = false;
    while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
      _offset++;
      sawDigit = true;
    }
    if (_offset < source.length && source.codeUnitAt(_offset) == 46) {
      _offset++;
      while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
        _offset++;
        sawDigit = true;
      }
    }
    if (!sawDigit) {
      _offset = start;
      return null;
    }
    if (_offset < source.length &&
        (source.codeUnitAt(_offset) == 69 || source.codeUnitAt(_offset) == 101)) {
      final exponentStart = _offset;
      _offset++;
      if (_offset < source.length &&
          (source.codeUnitAt(_offset) == 43 || source.codeUnitAt(_offset) == 45)) {
        _offset++;
      }
      final exponentDigits = _offset;
      while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
        _offset++;
      }
      if (_offset == exponentDigits) {
        _offset = exponentStart;
      }
    }
    final value = double.tryParse(source.substring(start, _offset));
    if (value == null || !value.isFinite) {
      throw const FormatException('Invalid numeric literal in family formula.');
    }
    return value;
  }

  String? _identifier() {
    _skipWhitespace();
    if (_offset >= source.length || !_isIdentifierStart(source.codeUnitAt(_offset))) {
      return null;
    }
    final start = _offset++;
    while (_offset < source.length && _isIdentifierPart(source.codeUnitAt(_offset))) {
      _offset++;
    }
    return source.substring(start, _offset);
  }

  void _skipWhitespace() {
    while (_offset < source.length) {
      final unit = source.codeUnitAt(_offset);
      if (unit == 32 || unit == 9 || unit == 10 || unit == 13) {
        _offset++;
      } else {
        break;
      }
    }
  }

  bool _consume(String token) {
    if (_offset < source.length && source.startsWith(token, _offset)) {
      _offset += token.length;
      return true;
    }
    return false;
  }

  static void _requireArity(String name, List<double> values, int expected) {
    if (values.length != expected) {
      throw FormatException(
        '$name() expects $expected argument${expected == 1 ? '' : 's'}.',
      );
    }
  }

  static void _requireFinite(double value) {
    if (!value.isFinite) {
      throw const FormatException('Family formula produced a non-finite result.');
    }
  }

  static bool _isDigit(int unit) => unit >= 48 && unit <= 57;

  static bool _isIdentifierStart(int unit) =>
      unit == 95 || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);

  static bool _isIdentifierPart(int unit) =>
      _isIdentifierStart(unit) || _isDigit(unit);
}
