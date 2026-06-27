import 'dart:math' as math;

import 'render_scene_editor.dart';
import 'render_scene_models.dart';

class EstimateLineItem {
  const EstimateLineItem({
    required this.label,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.totalCost,
  });

  final String label;
  final double quantity;
  final String unit;
  final double unitCost;
  final double totalCost;
}

class RenderSceneEstimateSummary {
  const RenderSceneEstimateSummary({
    required this.roomCount,
    required this.totalRoomArea,
    required this.totalRoomPerimeter,
    required this.wallCount,
    required this.wallGrossVolume,
    required this.wallNetVolume,
    required this.wallGrossArea,
    required this.wallNetArea,
    required this.brickCount,
    required this.floorCount,
    required this.floorArea,
    required this.floorConcreteVolume,
    required this.ceilingCount,
    required this.ceilingArea,
    required this.doorCount,
    required this.windowCount,
    required this.openingArea,
    required this.lineItems,
    required this.totalCost,
  });

  final int roomCount;
  final double totalRoomArea;
  final double totalRoomPerimeter;
  final int wallCount;
  final double wallGrossVolume;
  final double wallNetVolume;
  final double wallGrossArea;
  final double wallNetArea;
  final int brickCount;
  final int floorCount;
  final double floorArea;
  final double floorConcreteVolume;
  final int ceilingCount;
  final double ceilingArea;
  final int doorCount;
  final int windowCount;
  final double openingArea;
  final List<EstimateLineItem> lineItems;
  final double totalCost;
}

class RenderSceneEstimateCatalog {
  const RenderSceneEstimateCatalog({
    this.bricksPerCubicMeter = 500.0,
    this.brickUnitCost = 0.32,
    this.concreteCostPerCubicMeter = 95.0,
    this.floorFinishCostPerSquareMeter = 18.0,
    this.ceilingCostPerSquareMeter = 12.0,
    this.doorUnitCost = 180.0,
    this.windowUnitCost = 220.0,
  });

  final double bricksPerCubicMeter;
  final double brickUnitCost;
  final double concreteCostPerCubicMeter;
  final double floorFinishCostPerSquareMeter;
  final double ceilingCostPerSquareMeter;
  final double doorUnitCost;
  final double windowUnitCost;

  RenderSceneEstimateCatalog copyWith({
    double? bricksPerCubicMeter,
    double? brickUnitCost,
    double? concreteCostPerCubicMeter,
    double? floorFinishCostPerSquareMeter,
    double? ceilingCostPerSquareMeter,
    double? doorUnitCost,
    double? windowUnitCost,
  }) {
    return RenderSceneEstimateCatalog(
      bricksPerCubicMeter: bricksPerCubicMeter ?? this.bricksPerCubicMeter,
      brickUnitCost: brickUnitCost ?? this.brickUnitCost,
      concreteCostPerCubicMeter:
          concreteCostPerCubicMeter ?? this.concreteCostPerCubicMeter,
      floorFinishCostPerSquareMeter:
          floorFinishCostPerSquareMeter ?? this.floorFinishCostPerSquareMeter,
      ceilingCostPerSquareMeter:
          ceilingCostPerSquareMeter ?? this.ceilingCostPerSquareMeter,
      doorUnitCost: doorUnitCost ?? this.doorUnitCost,
      windowUnitCost: windowUnitCost ?? this.windowUnitCost,
    );
  }
}

class RenderSceneEstimator {
  const RenderSceneEstimator._();

  static RenderSceneEstimateSummary summarize(
    RenderScene scene, {
    RenderSceneEstimateCatalog catalog = const RenderSceneEstimateCatalog(),
  }) {
    var roomCount = 0;
    var totalRoomArea = 0.0;
    var totalRoomPerimeter = 0.0;
    var wallCount = 0;
    var wallGrossVolume = 0.0;
    var wallNetVolume = 0.0;
    var wallGrossArea = 0.0;
    var wallNetArea = 0.0;
    var floorCount = 0;
    var floorArea = 0.0;
    var floorConcreteVolume = 0.0;
    var ceilingCount = 0;
    var ceilingArea = 0.0;
    var doorCount = 0;
    var windowCount = 0;
    var openingArea = 0.0;

    final openingsByWall = <int, List<RenderSceneObject>>{};
    for (final object in scene.objects) {
      if (object.kindKey != 'door' && object.kindKey != 'window') {
        continue;
      }
      final hostWallId = (object.metadata['host_wall_id'] as num?)?.toInt();
      if (hostWallId == null) {
        continue;
      }
      openingsByWall.putIfAbsent(hostWallId, () => <RenderSceneObject>[]).add(object);
    }

    for (final object in scene.objects) {
      switch (object.kindKey) {
        case 'room':
          roomCount += 1;
          totalRoomArea +=
              (object.metadata['area_m2'] as num?)?.toDouble() ??
                  (object.bounds.width * object.bounds.depth);
          totalRoomPerimeter +=
              (object.metadata['perimeter_m'] as num?)?.toDouble() ??
                  ((object.bounds.width + object.bounds.depth) * 2.0);
          break;
        case 'wall':
          wallCount += 1;
          final length =
              RenderSceneEditor.wallLength(object) ?? object.bounds.width;
          final thickness =
              RenderSceneEditor.wallThickness(object) ??
                  math.min(object.bounds.width, object.bounds.depth);
          final height =
              (object.metadata['height_meters'] as num?)?.toDouble() ??
                  object.bounds.height;
          final grossVolume = length * thickness * height;
          final grossArea = length * height;
          final attachedOpenings = openingsByWall[object.elementId] ?? const <RenderSceneObject>[];
          var wallOpeningVolume = 0.0;
          var wallOpeningArea = 0.0;
          for (final opening in attachedOpenings) {
            final width =
                (opening.metadata['width_meters'] as num?)?.toDouble() ??
                    opening.bounds.width;
            final openingHeight =
                (opening.metadata['height_meters'] as num?)?.toDouble() ??
                    opening.bounds.height;
            wallOpeningArea += width * openingHeight;
            wallOpeningVolume += width * openingHeight * thickness;
          }
          wallGrossVolume += grossVolume;
          wallNetVolume += math.max(0.0, grossVolume - wallOpeningVolume);
          wallGrossArea += grossArea;
          wallNetArea += math.max(0.0, grossArea - wallOpeningArea);
          break;
        case 'floor':
          floorCount += 1;
          final area = object.bounds.width * object.bounds.depth;
          final thickness =
              (object.metadata['thickness_meters'] as num?)?.toDouble() ??
                  object.bounds.height;
          floorArea += area;
          floorConcreteVolume += area * thickness;
          break;
        case 'ceiling':
          ceilingCount += 1;
          ceilingArea += object.bounds.width * object.bounds.depth;
          break;
        case 'door':
          doorCount += 1;
          openingArea +=
              ((object.metadata['width_meters'] as num?)?.toDouble() ??
                      object.bounds.width) *
                  ((object.metadata['height_meters'] as num?)?.toDouble() ??
                      object.bounds.height);
          break;
        case 'window':
          windowCount += 1;
          openingArea +=
              ((object.metadata['width_meters'] as num?)?.toDouble() ??
                      object.bounds.width) *
                  ((object.metadata['height_meters'] as num?)?.toDouble() ??
                      object.bounds.height);
          break;
      }
    }

    final brickCount =
        (wallNetVolume * catalog.bricksPerCubicMeter).round().clamp(0, 1 << 30);
    final brickCost = brickCount * catalog.brickUnitCost;
    final concreteCost = floorConcreteVolume * catalog.concreteCostPerCubicMeter;
    final floorFinishCost = floorArea * catalog.floorFinishCostPerSquareMeter;
    final ceilingCost = ceilingArea * catalog.ceilingCostPerSquareMeter;
    final doorCost = doorCount * catalog.doorUnitCost;
    final windowCost = windowCount * catalog.windowUnitCost;

    final lineItems = <EstimateLineItem>[
      EstimateLineItem(
        label: 'Brick masonry',
        quantity: brickCount.toDouble(),
        unit: 'pcs',
        unitCost: catalog.brickUnitCost,
        totalCost: brickCost,
      ),
      EstimateLineItem(
        label: 'Concrete floor',
        quantity: floorConcreteVolume,
        unit: 'm³',
        unitCost: catalog.concreteCostPerCubicMeter,
        totalCost: concreteCost,
      ),
      EstimateLineItem(
        label: 'Floor finish',
        quantity: floorArea,
        unit: 'm²',
        unitCost: catalog.floorFinishCostPerSquareMeter,
        totalCost: floorFinishCost,
      ),
      EstimateLineItem(
        label: 'Ceiling finish',
        quantity: ceilingArea,
        unit: 'm²',
        unitCost: catalog.ceilingCostPerSquareMeter,
        totalCost: ceilingCost,
      ),
      EstimateLineItem(
        label: 'Doors',
        quantity: doorCount.toDouble(),
        unit: 'pcs',
        unitCost: catalog.doorUnitCost,
        totalCost: doorCost,
      ),
      EstimateLineItem(
        label: 'Windows',
        quantity: windowCount.toDouble(),
        unit: 'pcs',
        unitCost: catalog.windowUnitCost,
        totalCost: windowCost,
      ),
    ];

    final totalCost = lineItems.fold<double>(
      0.0,
      (sum, item) => sum + item.totalCost,
    );

    return RenderSceneEstimateSummary(
      roomCount: roomCount,
      totalRoomArea: totalRoomArea,
      totalRoomPerimeter: totalRoomPerimeter,
      wallCount: wallCount,
      wallGrossVolume: wallGrossVolume,
      wallNetVolume: wallNetVolume,
      wallGrossArea: wallGrossArea,
      wallNetArea: wallNetArea,
      brickCount: brickCount,
      floorCount: floorCount,
      floorArea: floorArea,
      floorConcreteVolume: floorConcreteVolume,
      ceilingCount: ceilingCount,
      ceilingArea: ceilingArea,
      doorCount: doorCount,
      windowCount: windowCount,
      openingArea: openingArea,
      lineItems: lineItems,
      totalCost: totalCost,
    );
  }
}
