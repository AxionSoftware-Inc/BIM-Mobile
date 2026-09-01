import 'wall_type_catalog.dart';

/// Native floor assemblies exposed to the Inspector and viewport.
///
/// A floor type is an engine-owned layered assembly. Flutter only keeps the
/// stable assembly id and a small semantic surface key used to choose the
/// viewport pattern; geometry and persistence remain in the native document.
enum FloorSurfaceKind {
  asphalt,
  concrete,
  wood,
  generic,
}

extension FloorSurfaceKindLabel on FloorSurfaceKind {
  String get key {
    switch (this) {
      case FloorSurfaceKind.asphalt:
        return 'asphalt';
      case FloorSurfaceKind.concrete:
        return 'concrete';
      case FloorSurfaceKind.wood:
        return 'wood';
      case FloorSurfaceKind.generic:
        return 'generic';
    }
  }

  String get label {
    switch (this) {
      case FloorSurfaceKind.asphalt:
        return 'Asphalt';
      case FloorSurfaceKind.concrete:
        return 'Concrete';
      case FloorSurfaceKind.wood:
        return 'Wood';
      case FloorSurfaceKind.generic:
        return 'Generic';
    }
  }
}

final class FloorTypeDefinition {
  const FloorTypeDefinition({
    required this.id,
    required this.name,
    required this.surfaceKind,
    required this.totalThicknessMeters,
    required this.layers,
    required this.coreStartLayer,
    required this.coreEndLayer,
  });

  final int id;
  final String name;
  final FloorSurfaceKind surfaceKind;
  final double totalThicknessMeters;
  final List<WallTypeLayerDefinition> layers;
  final int coreStartLayer;
  final int coreEndLayer;

  String get surfaceKey => surfaceKind.key;
  String get surfaceLabel => surfaceKind.label;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'surface_key': surfaceKey,
        'total_thickness_meters': totalThicknessMeters,
        'core_start_layer': coreStartLayer,
        'core_end_layer': coreEndLayer,
        'layers': layers.map((layer) => layer.toJson()).toList(),
      };

  static FloorTypeDefinition? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = _floorTypeInt(value['id'] ?? value['assembly_id']);
    if (id == null || id == 0) return null;

    final layers = <WallTypeLayerDefinition>[];
    final rawLayers = value['layers'];
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
    final name = value['name']?.toString().trim();
    final surfaceKind = _floorSurfaceKind(
      value['surface_key'] ??
          value['surfaceKey'] ??
          value['floor_type'] ??
          name,
    );
    return FloorTypeDefinition(
      id: id,
      name: name == null || name.isEmpty ? 'Floor type $id' : name,
      surfaceKind: surfaceKind,
      totalThicknessMeters: _floorTypeDouble(
            value['total_thickness_meters'] ?? value['totalThicknessMeters'],
          ) ??
          calculatedThickness,
      layers: List<WallTypeLayerDefinition>.unmodifiable(layers),
      coreStartLayer:
          _floorTypeInt(value['core_start_layer'] ?? value['coreStartLayer']) ??
              -1,
      coreEndLayer:
          _floorTypeInt(value['core_end_layer'] ?? value['coreEndLayer']) ?? -1,
    );
  }
}

FloorSurfaceKind _floorSurfaceKind(Object? value) {
  final normalized = value?.toString().toLowerCase().replaceAll('_', ' ') ?? '';
  if (normalized.contains('asphalt') || normalized.contains('bitumen')) {
    return FloorSurfaceKind.asphalt;
  }
  if (normalized.contains('wood') ||
      normalized.contains('timber') ||
      normalized.contains('laminate') ||
      normalized.contains('parquet')) {
    return FloorSurfaceKind.wood;
  }
  if (normalized.contains('concrete') || normalized.contains('cement')) {
    return FloorSurfaceKind.concrete;
  }
  return FloorSurfaceKind.generic;
}

int? _floorTypeInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _floorTypeDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
