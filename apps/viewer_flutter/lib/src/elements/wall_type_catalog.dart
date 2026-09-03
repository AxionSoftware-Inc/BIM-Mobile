import 'assembly_type_catalog.dart';

export 'assembly_type_catalog.dart';

/// Native document wall type/material semantics exposed to the Inspector.
///
/// Layer records are shared by every layered assembly. These aliases keep
/// older wall-focused feature imports source-compatible while preventing a
/// second wall-only layer model from appearing in the application.
typedef WallLayerFunction = AssemblyLayerFunction;
typedef WallLayerSide = AssemblyLayerSide;
typedef WallTypeLayerDefinition = AssemblyLayerDefinition;

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
  final List<AssemblyLayerDefinition> layers;
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
    final layers = <AssemblyLayerDefinition>[];
    if (rawLayers is List) {
      for (final rawLayer in rawLayers) {
        final layer = AssemblyLayerDefinition.fromJson(rawLayer);
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
      layers: List<AssemblyLayerDefinition>.unmodifiable(layers),
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

int? _wallTypeInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _wallTypeDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
