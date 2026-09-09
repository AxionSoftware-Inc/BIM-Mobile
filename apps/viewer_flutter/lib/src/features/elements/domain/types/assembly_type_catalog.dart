/// Shared semantic layer contract for every layered assembly.
///
/// Walls, floors, ceilings, roofs and stairs use the same layer shape. The
/// element-specific catalogs add only their own identity/category fields; they
/// must not create another copy of this record.
enum AssemblyLayerFunction {
  core,
  interiorFinish,
  exteriorFinish,
  insulation,
  airGap,
  generic,
}

extension AssemblyLayerFunctionLabel on AssemblyLayerFunction {
  String get label {
    switch (this) {
      case AssemblyLayerFunction.core:
        return 'Core';
      case AssemblyLayerFunction.interiorFinish:
        return 'Interior finish';
      case AssemblyLayerFunction.exteriorFinish:
        return 'Exterior finish';
      case AssemblyLayerFunction.insulation:
        return 'Insulation';
      case AssemblyLayerFunction.airGap:
        return 'Air gap';
      case AssemblyLayerFunction.generic:
        return 'Layer';
    }
  }
}

enum AssemblyLayerSide {
  unspecified,
  exterior,
  interior,
}

extension AssemblyLayerSideLabel on AssemblyLayerSide {
  String get label {
    switch (this) {
      case AssemblyLayerSide.unspecified:
        return 'Unspecified';
      case AssemblyLayerSide.exterior:
        return 'Exterior';
      case AssemblyLayerSide.interior:
        return 'Interior';
    }
  }
}

final class AssemblyLayerDefinition {
  const AssemblyLayerDefinition({
    required this.materialId,
    required this.thicknessMeters,
    required this.function,
    required this.priority,
    required this.structural,
    required this.side,
    required this.wrapsOpenings,
    required this.wrapsEnds,
  });

  final int materialId;
  final double thicknessMeters;
  final AssemblyLayerFunction function;
  final int priority;
  final bool structural;
  final AssemblyLayerSide side;
  final bool wrapsOpenings;
  final bool wrapsEnds;

  Map<String, Object?> toJson() => <String, Object?>{
        'material_id': materialId,
        'thickness_meters': thicknessMeters,
        'function': function.index,
        'priority': priority,
        'structural': structural,
        'side': side.index,
        'wraps_openings': wrapsOpenings,
        'wraps_ends': wrapsEnds,
      };

  static AssemblyLayerDefinition? fromJson(Object? value) {
    if (value is! Map) return null;
    final materialId =
        _assemblyInt(value['material_id'] ?? value['materialId']);
    final thicknessMeters =
        _assemblyDouble(value['thickness_meters'] ?? value['thicknessMeters']);
    if (materialId == null ||
        materialId == 0 ||
        thicknessMeters == null ||
        !thicknessMeters.isFinite ||
        thicknessMeters <= 0) {
      return null;
    }
    return AssemblyLayerDefinition(
      materialId: materialId,
      thicknessMeters: thicknessMeters,
      function: _assemblyFunction(value['function']),
      priority: _assemblyInt(value['priority']) ?? 0,
      structural: _assemblyBool(value['structural']),
      side: _assemblySide(value['side']),
      wrapsOpenings:
          value['wraps_openings'] != false && value['wrapsOpenings'] != false,
      wrapsEnds: value['wraps_ends'] != false && value['wrapsEnds'] != false,
    );
  }
}

AssemblyLayerFunction _assemblyFunction(Object? value) {
  if (value is num) {
    return AssemblyLayerFunction.values[
        value.toInt().clamp(0, AssemblyLayerFunction.values.length - 1)];
  }
  switch (value?.toString().toLowerCase()) {
    case 'core':
      return AssemblyLayerFunction.core;
    case 'interiorfinish':
    case 'interior_finish':
      return AssemblyLayerFunction.interiorFinish;
    case 'exteriorfinish':
    case 'exterior_finish':
      return AssemblyLayerFunction.exteriorFinish;
    case 'insulation':
      return AssemblyLayerFunction.insulation;
    case 'airgap':
    case 'air_gap':
      return AssemblyLayerFunction.airGap;
    default:
      return AssemblyLayerFunction.generic;
  }
}

AssemblyLayerSide _assemblySide(Object? value) {
  if (value is num) {
    return AssemblyLayerSide
        .values[value.toInt().clamp(0, AssemblyLayerSide.values.length - 1)];
  }
  switch (value?.toString().toLowerCase()) {
    case 'exterior':
      return AssemblyLayerSide.exterior;
    case 'interior':
      return AssemblyLayerSide.interior;
    default:
      return AssemblyLayerSide.unspecified;
  }
}

int? _assemblyInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _assemblyDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _assemblyBool(Object? value) =>
    value == true || value?.toString() == 'true';
