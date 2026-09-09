import 'dart:math' as math;

import '../../viewer/application/runtime/bim_compact_instance_store.dart';
import '../../../render_scene_estimator.dart';

/// Quantity estimator that scans dense typed arrays rather than a graph of
/// RenderSceneObject + metadata maps.
///
/// SCHEDULE APPLICATION OWNERSHIP: calculation belongs to schedule/quantity
/// use-cases. The compact BIM store is a viewer/runtime read-model consumed
/// here without becoming schedule-owned state.
final class BimCompactEstimator {
  const BimCompactEstimator._();

  static RenderSceneEstimateSummary summarize(
    BimCompactInstanceStore store, {
    RenderSceneEstimateCatalog catalog = const RenderSceneEstimateCatalog(),
  }) {
    var totalRoomArea = 0.0;
    var totalRoomPerimeter = 0.0;
    for (var row = 0; row < store.rooms.length; row += 1) {
      totalRoomArea += store.rooms.areas[row];
      totalRoomPerimeter += store.rooms.perimeters[row];
    }

    final openingAreaByHostWall = <int, double>{};
    final openingVolumeWidthHeightByHostWall = <int, double>{};
    var doorCount = 0;
    var windowCount = 0;
    var openingArea = 0.0;
    for (var row = 0; row < store.openings.length; row += 1) {
      final instanceIndex = store.openings.instanceIndices[row];
      final kind = BimCompactKind.values[store.instances.kindCodes[instanceIndex]];
      if (kind == BimCompactKind.door) {
        doorCount += 1;
      } else if (kind == BimCompactKind.window) {
        windowCount += 1;
      }
      final area = store.openings.widths[row] * store.openings.heights[row];
      openingArea += area;
      final host = store.openings.hostWallIds[row];
      if (host != BimCompactInstanceStore.missingId) {
        openingAreaByHostWall.update(host, (value) => value + area,
            ifAbsent: () => area);
        openingVolumeWidthHeightByHostWall.update(
          host,
          (value) => value + area,
          ifAbsent: () => area,
        );
      }
    }

    var wallGrossVolume = 0.0;
    var wallNetVolume = 0.0;
    var wallGrossArea = 0.0;
    var wallNetArea = 0.0;
    for (var row = 0; row < store.walls.length; row += 1) {
      final instanceIndex = store.walls.instanceIndices[row];
      final wallId = store.instances.elementIds[instanceIndex];
      final length = store.walls.lengths[row];
      final thickness = store.walls.thicknesses[row];
      final height = store.walls.heights[row];
      final grossVolume = length * thickness * height;
      final grossArea = length * height;
      final hostedOpeningArea = openingAreaByHostWall[wallId] ?? 0.0;
      final hostedOpeningVolume =
          (openingVolumeWidthHeightByHostWall[wallId] ?? 0.0) * thickness;
      wallGrossVolume += grossVolume;
      wallNetVolume += math.max(0.0, grossVolume - hostedOpeningVolume);
      wallGrossArea += grossArea;
      wallNetArea += math.max(0.0, grossArea - hostedOpeningArea);
    }

    var floorCount = 0;
    var floorArea = 0.0;
    var floorConcreteVolume = 0.0;
    var ceilingCount = 0;
    var ceilingArea = 0.0;
    for (var row = 0; row < store.surfaces.length; row += 1) {
      final instanceIndex = store.surfaces.instanceIndices[row];
      final kind = BimCompactKind.values[store.instances.kindCodes[instanceIndex]];
      final area = store.surfaces.areas[row];
      if (kind == BimCompactKind.floor || kind == BimCompactKind.slab) {
        floorCount += 1;
        floorArea += area;
        floorConcreteVolume += area * store.surfaces.thicknesses[row];
      } else if (kind == BimCompactKind.ceiling) {
        ceilingCount += 1;
        ceilingArea += area;
      }
    }

    final brickCount =
        (wallNetVolume * catalog.bricksPerCubicMeter).round().clamp(0, 1 << 30);
    final brickCost = brickCount * catalog.brickUnitCost;
    final concreteCost =
        floorConcreteVolume * catalog.concreteCostPerCubicMeter;
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
      roomCount: store.rooms.length,
      totalRoomArea: totalRoomArea,
      totalRoomPerimeter: totalRoomPerimeter,
      wallCount: store.walls.length,
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
