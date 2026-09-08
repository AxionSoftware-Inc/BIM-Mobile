import 'dart:math' as math;
import 'dart:typed_data';

import 'bim_compact_instance_store.dart';

/// Compact CSR-style 3D grid over BIM instance bounds.
///
/// The index allocates objects per occupied spatial cell, not per BIM element.
/// Once built, cell keys, offsets and instance indices are dense typed arrays.
/// This is the semantic-side counterpart to the native chunk streamer: camera
/// queries touch only nearby cells instead of scanning every building/floor.
final class BimSpatialGridIndex {
  BimSpatialGridIndex._({
    required this.cellSizeX,
    required this.cellSizeY,
    required this.cellSizeZ,
    required this.cellKeys,
    required this.cellOffsets,
    required this.instanceIndices,
  });

  factory BimSpatialGridIndex.build(
    BimCompactInstanceStore store, {
    double cellSizeX = 32.0,
    double cellSizeY = 32.0,
    double cellSizeZ = 12.0,
  }) {
    assert(cellSizeX > 0 && cellSizeY > 0 && cellSizeZ > 0);
    final buckets = <int, List<int>>{};
    final instances = store.instances;

    for (var index = 0; index < instances.length; index += 1) {
      final minCellX = _cell(instances.minX(index), cellSizeX);
      final minCellY = _cell(instances.minY(index), cellSizeY);
      final minCellZ = _cell(instances.minZ(index), cellSizeZ);
      final maxCellX = _cell(instances.maxX(index), cellSizeX);
      final maxCellY = _cell(instances.maxY(index), cellSizeY);
      final maxCellZ = _cell(instances.maxZ(index), cellSizeZ);

      // Large imported proxy meshes should not explode the grid by occupying
      // tens of thousands of cells. They are inserted at their center and can
      // later be handled by the coarse building/proxy hierarchy.
      final cellCount = (maxCellX - minCellX + 1) *
          (maxCellY - minCellY + 1) *
          (maxCellZ - minCellZ + 1);
      if (cellCount > 256) {
        final cx = _cell(
          (instances.minX(index) + instances.maxX(index)) * 0.5,
          cellSizeX,
        );
        final cy = _cell(
          (instances.minY(index) + instances.maxY(index)) * 0.5,
          cellSizeY,
        );
        final cz = _cell(
          (instances.minZ(index) + instances.maxZ(index)) * 0.5,
          cellSizeZ,
        );
        buckets.putIfAbsent(_pack(cx, cy, cz), () => <int>[]).add(index);
        continue;
      }

      for (var x = minCellX; x <= maxCellX; x += 1) {
        for (var y = minCellY; y <= maxCellY; y += 1) {
          for (var z = minCellZ; z <= maxCellZ; z += 1) {
            buckets.putIfAbsent(_pack(x, y, z), () => <int>[]).add(index);
          }
        }
      }
    }

    final keys = buckets.keys.toList()..sort();
    final offsets = Uint32List(keys.length + 1);
    final flattened = <int>[];
    for (var cellIndex = 0; cellIndex < keys.length; cellIndex += 1) {
      offsets[cellIndex] = flattened.length;
      flattened.addAll(buckets[keys[cellIndex]]!);
    }
    offsets[keys.length] = flattened.length;

    return BimSpatialGridIndex._(
      cellSizeX: cellSizeX,
      cellSizeY: cellSizeY,
      cellSizeZ: cellSizeZ,
      cellKeys: Int64List.fromList(keys),
      cellOffsets: offsets,
      instanceIndices: Uint32List.fromList(flattened),
    );
  }

  final double cellSizeX;
  final double cellSizeY;
  final double cellSizeZ;
  final Int64List cellKeys;
  final Uint32List cellOffsets;
  final Uint32List instanceIndices;

  int get occupiedCellCount => cellKeys.length;

  /// Returns unique instance indices intersecting a coarse camera neighborhood.
  /// Precise frustum/clip tests are intentionally left to the renderer/native
  /// BVH; this index only avoids the global O(N) scan.
  Uint32List queryAabb({
    required double minX,
    required double minY,
    required double minZ,
    required double maxX,
    required double maxY,
    required double maxZ,
  }) {
    final firstX = _cell(minX, cellSizeX);
    final firstY = _cell(minY, cellSizeY);
    final firstZ = _cell(minZ, cellSizeZ);
    final lastX = _cell(maxX, cellSizeX);
    final lastY = _cell(maxY, cellSizeY);
    final lastZ = _cell(maxZ, cellSizeZ);
    final unique = <int>{};

    for (var x = firstX; x <= lastX; x += 1) {
      for (var y = firstY; y <= lastY; y += 1) {
        for (var z = firstZ; z <= lastZ; z += 1) {
          final key = _pack(x, y, z);
          final cellIndex = _binarySearch(cellKeys, key);
          if (cellIndex < 0) continue;
          final start = cellOffsets[cellIndex];
          final end = cellOffsets[cellIndex + 1];
          for (var offset = start; offset < end; offset += 1) {
            unique.add(instanceIndices[offset]);
          }
        }
      }
    }
    final result = unique.toList()..sort();
    return Uint32List.fromList(result);
  }

  /// Coarse Google-Earth-style camera query. It first visits only grid cells in
  /// [radiusMeters], then keeps near items or items in front of the camera.
  /// The result is an input candidate set for exact native frustum/BVH tests.
  Uint32List queryCameraNeighborhood(
    BimCompactInstanceStore store, {
    required double cameraX,
    required double cameraY,
    required double cameraZ,
    required double forwardX,
    required double forwardY,
    required double forwardZ,
    double radiusMeters = 260.0,
    double alwaysKeepMeters = 50.0,
    double rearDotThreshold = -0.12,
  }) {
    final candidates = queryAabb(
      minX: cameraX - radiusMeters,
      minY: cameraY - radiusMeters,
      minZ: cameraZ - radiusMeters,
      maxX: cameraX + radiusMeters,
      maxY: cameraY + radiusMeters,
      maxZ: cameraZ + radiusMeters,
    );
    final forwardLength = math.sqrt(
      forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ,
    );
    final fx = forwardLength > 1e-9 ? forwardX / forwardLength : 0.0;
    final fy = forwardLength > 1e-9 ? forwardY / forwardLength : 0.0;
    final fz = forwardLength > 1e-9 ? forwardZ / forwardLength : -1.0;
    final radiusSquared = radiusMeters * radiusMeters;
    final nearSquared = alwaysKeepMeters * alwaysKeepMeters;
    final instances = store.instances;
    final result = <int>[];

    for (final index in candidates) {
      final centerX = (instances.minX(index) + instances.maxX(index)) * 0.5;
      final centerY = (instances.minY(index) + instances.maxY(index)) * 0.5;
      final centerZ = (instances.minZ(index) + instances.maxZ(index)) * 0.5;
      final dx = centerX - cameraX;
      final dy = centerY - cameraY;
      final dz = centerZ - cameraZ;
      final distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared > radiusSquared) continue;
      if (distanceSquared <= nearSquared) {
        result.add(index);
        continue;
      }
      final distance = math.sqrt(distanceSquared).coerceAtLeast(1e-9);
      final dot = (dx * fx + dy * fy + dz * fz) / distance;
      if (dot >= rearDotThreshold) result.add(index);
    }

    return Uint32List.fromList(result);
  }

  static int _cell(double coordinate, double cellSize) =>
      (coordinate / cellSize).floor();

  // 21 signed bits per axis packed into 63 bits. At a 32 m cell size this
  // covers roughly +/-33,500 km around project origin, well beyond BIM needs.
  static int _pack(int x, int y, int z) {
    const bias = 1 << 20;
    const mask = (1 << 21) - 1;
    final bx = (x + bias).clamp(0, mask);
    final by = (y + bias).clamp(0, mask);
    final bz = (z + bias).clamp(0, mask);
    return (bx << 42) | (by << 21) | bz;
  }

  static int _binarySearch(Int64List values, int target) {
    var low = 0;
    var high = values.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final value = values[middle];
      if (value == target) return middle;
      if (value < target) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return -1;
  }
}
