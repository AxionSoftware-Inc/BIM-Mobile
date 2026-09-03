import 'package:flutter/foundation.dart';

/// Project display units. Model coordinates and authoring commands remain in
/// metres; this value object is the only place where the UI converts or
/// formats project lengths.
@immutable
final class ProjectUnitSettings {
  const ProjectUnitSettings({
    required this.system,
    required this.length,
    required this.angle,
  });

  const ProjectUnitSettings.defaults()
      : system = 'metric',
        length = 'meter',
        angle = 'degrees';

  final String system;
  final String length;
  final String angle;

  factory ProjectUnitSettings.fromMap(Map<String, dynamic> value) {
    const validLengths = <String>{
      'millimeter',
      'centimeter',
      'meter',
      'inch',
      'foot',
    };
    final parsedLength = value['length']?.toString() ?? 'meter';
    return ProjectUnitSettings(
      system: value['system']?.toString() == 'imperial' ? 'imperial' : 'metric',
      length: validLengths.contains(parsedLength) ? parsedLength : 'meter',
      angle: value['angle']?.toString() ?? 'degrees',
    );
  }

  ProjectUnitSettings copyWith({
    String? system,
    String? length,
    String? angle,
  }) =>
      ProjectUnitSettings(
        system: system ?? this.system,
        length: length ?? this.length,
        angle: angle ?? this.angle,
      );

  String get lengthSymbol => switch (length) {
        'millimeter' => 'mm',
        'centimeter' => 'cm',
        'inch' => 'in',
        'foot' => 'ft',
        _ => 'm',
      };

  String get areaSymbol => switch (length) {
        'millimeter' => 'mm²',
        'centimeter' => 'cm²',
        'inch' => 'in²',
        'foot' => 'ft²',
        _ => 'm²',
      };

  double get _lengthFactor => switch (length) {
        'millimeter' => 1000.0,
        'centimeter' => 100.0,
        'inch' => 39.37007874015748,
        'foot' => 3.280839895013123,
        _ => 1.0,
      };

  double get _areaFactor => _lengthFactor * _lengthFactor;

  int get _lengthDecimals => switch (length) {
        'millimeter' => 0,
        'centimeter' => 1,
        _ => 2,
      };

  int get lengthDecimals => _lengthDecimals;

  double fromMeters(double meters) => meters * _lengthFactor;

  double toMeters(double displayValue) => displayValue / _lengthFactor;

  String formatLength(double meters, {bool withUnit = true}) {
    if (!meters.isFinite) return '-';
    final value = fromMeters(meters).toStringAsFixed(_lengthDecimals);
    return withUnit ? '$value $lengthSymbol' : value;
  }

  String formatArea(double squareMeters, {bool withUnit = true}) {
    if (!squareMeters.isFinite) return '-';
    final value = (squareMeters * _areaFactor).toStringAsFixed(2);
    return withUnit ? '$value $areaSymbol' : value;
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectUnitSettings &&
      other.system == system &&
      other.length == length &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(system, length, angle);
}
