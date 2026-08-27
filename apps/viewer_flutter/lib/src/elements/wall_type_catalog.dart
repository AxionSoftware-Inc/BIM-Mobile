/// Native document wall type/material semantics exposed to the Inspector.
///
/// These records are immutable presentation-neutral data. The native document
/// owns persistence and geometry; Flutter only uses this catalog to present a
/// type choice and its assembly layers.
enum WallTypeCategory {
  interior,
  exterior,
  generic,
}

extension WallTypeCategoryLabel on WallTypeCategory {
  String get label {
    switch (this) {
      case WallTypeCategory.interior:
        return 'Interior';
      case WallTypeCategory.exterior:
        return 'Exterior';
      case WallTypeCategory.generic:
        return 'Generic';
    }
  }
}

enum WallLayerFunction {
  core,
  interiorFinish,
  exteriorFinish,
  insulation,
  airGap,
  generic,
}

extension WallLayerFunctionLabel on WallLayerFunction {
  String get label {
    switch (this) {
      case WallLayerFunction.core:
        return 'Core';
      case WallLayerFunction.interiorFinish:
        return 'Interior finish';
      case WallLayerFunction.exteriorFinish:
        return 'Exterior finish';
      case WallLayerFunction.insulation:
        return 'Insulation';
      case WallLayerFunction.airGap:
        return 'Air gap';
      case WallLayerFunction.generic:
        return 'Layer';
    }
  }
}

enum WallLayerSide {
  unspecified,
  exterior,
  interior,
}

extension WallLayerSideLabel on WallLayerSide {
  String get label {
    switch (this) {
      case WallLayerSide.unspecified:
        return 'Unspecified';
      case WallLayerSide.exterior:
        return 'Exterior';
      case WallLayerSide.interior:
        return 'Interior';
    }
  }
}

final class WallTypeLayerDefinition {
  const WallTypeLayerDefinition({
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
  final WallLayerFunction function;
  final int priority;
  final bool structural;
  final WallLayerSide side;
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

  static WallTypeLayerDefinition? fromJson(Object? value) {
    if (value is! Map) return null;
    final materialId =
        _wallTypeInt(value['material_id'] ?? value['materialId']);
    final thicknessMeters =
        _wallTypeDouble(value['thickness_meters'] ?? value['thicknessMeters']);
    if (materialId == null ||
        materialId == 0 ||
        thicknessMeters == null ||
        !thicknessMeters.isFinite ||
        thicknessMeters <= 0) {
      return null;
    }
    return WallTypeLayerDefinition(
      materialId: materialId,
      thicknessMeters: thicknessMeters,
      function: _wallLayerFunction(value['function']),
      priority: _wallTypeInt(value['priority']) ?? 0,
      structural: _wallTypeBool(value['structural']),
      side: _wallLayerSide(value['side']),
      wrapsOpenings:
          value['wraps_openings'] != false && value['wrapsOpenings'] != false,
      wrapsEnds: value['wraps_ends'] != false && value['wrapsEnds'] != false,
    );
  }
}

final class WallTypeDefinition {
  const WallTypeDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.totalThicknessMeters,
    required this.layers,
    required this.coreStartLayer,
    required this.coreEndLayer,
  });

  final int id;
  final String name;
  final WallTypeCategory category;
  final double totalThicknessMeters;
  final List<WallTypeLayerDefinition> layers;
  final int coreStartLayer;
  final int coreEndLayer;

  String get categoryLabel => category.label;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'category': category.label,
        'total_thickness_meters': totalThicknessMeters,
        'core_start_layer': coreStartLayer,
        'core_end_layer': coreEndLayer,
        'layers': layers.map((layer) => layer.toJson()).toList(),
      };

  static WallTypeDefinition? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = _wallTypeInt(value['id'] ?? value['wall_type_id']);
    if (id == null || id == 0) return null;
    final rawLayers = value['layers'];
    final layers = <WallTypeLayerDefinition>[];
    if (rawLayers is List) {
      for (final rawLayer in rawLayers) {
        final layer = WallTypeLayerDefinition.fromJson(rawLayer);
        if (layer != null) layers.add(layer);
      }
    }
    final calculatedThickness = layers.fold<double>(
      0.0,
      (total, layer) => total + layer.thicknessMeters,
    );
    return WallTypeDefinition(
      id: id,
      name: value['name']?.toString().trim().isNotEmpty == true
          ? value['name'].toString()
          : 'Wall type $id',
      category: _wallTypeCategory(value['category']),
      totalThicknessMeters: _wallTypeDouble(
            value['total_thickness_meters'] ?? value['totalThicknessMeters'],
          ) ??
          calculatedThickness,
      layers: List<WallTypeLayerDefinition>.unmodifiable(layers),
      coreStartLayer:
          _wallTypeInt(value['core_start_layer'] ?? value['coreStartLayer']) ??
              -1,
      coreEndLayer:
          _wallTypeInt(value['core_end_layer'] ?? value['coreEndLayer']) ?? -1,
    );
  }
}

WallTypeCategory _wallTypeCategory(Object? value) {
  if (value is num) {
    return switch (value.toInt()) {
      0 => WallTypeCategory.interior,
      1 => WallTypeCategory.exterior,
      _ => WallTypeCategory.generic,
    };
  }
  switch (value?.toString().toLowerCase()) {
    case 'interior':
      return WallTypeCategory.interior;
    case 'exterior':
      return WallTypeCategory.exterior;
    default:
      return WallTypeCategory.generic;
  }
}

WallLayerFunction _wallLayerFunction(Object? value) {
  if (value is num) {
    return WallLayerFunction
        .values[value.toInt().clamp(0, WallLayerFunction.values.length - 1)];
  }
  switch (value?.toString().toLowerCase()) {
    case 'core':
      return WallLayerFunction.core;
    case 'interiorfinish':
    case 'interior_finish':
      return WallLayerFunction.interiorFinish;
    case 'exteriorfinish':
    case 'exterior_finish':
      return WallLayerFunction.exteriorFinish;
    case 'insulation':
      return WallLayerFunction.insulation;
    case 'airgap':
    case 'air_gap':
      return WallLayerFunction.airGap;
    default:
      return WallLayerFunction.generic;
  }
}

WallLayerSide _wallLayerSide(Object? value) {
  if (value is num) {
    return WallLayerSide
        .values[value.toInt().clamp(0, WallLayerSide.values.length - 1)];
  }
  switch (value?.toString().toLowerCase()) {
    case 'exterior':
      return WallLayerSide.exterior;
    case 'interior':
      return WallLayerSide.interior;
    default:
      return WallLayerSide.unspecified;
  }
}

int? _wallTypeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _wallTypeDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _wallTypeBool(Object? value) =>
    value == true || value?.toString() == 'true';
