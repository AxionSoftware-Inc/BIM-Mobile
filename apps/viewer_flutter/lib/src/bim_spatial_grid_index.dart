import 'dart:math' as math;
import 'dart:typed_data';

import 'bim_compact_instance_store.dart';

/// Compact CSR-style 3D grid over BIM instance bounds.
///
/// The persistent representation is dense typed data. Build-time buckets are
/// temporary, but camera queries intentionally do *not* allocate a `Set<int>`
/// or one object per candidate. A reusable generation-stamp table de-duplicates
/// instance indices, which keeps orbit/pan queries predictable under GC.
final class BimSpatialGridIndex {
  BimSpatialGridIndex._({
    required this.cellSizeX,
    required this.cellSizeY,
    required this.cellSizeZ,
    required this.cellKeys,
    required this.cellOffsets,
    required this.instanceIndices,
    required int instanceCount,
  })  : _queryMarks = Uint32List(instanceCount),
        _queryScratch = Uint32List(instanceCount);

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

      // Large imported proxies are indexed by their center. Expanding one
      // campus shell through every occupied cell can otherwise make the index
      // itself larger than the geometry it is meant to accelerate.
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
    var membershipCount = 0;
    for (final key in keys) {
      membershipCount += buckets[key]!.length;
    }
    final flattened = Uint32List(membershipCount);
    var writeOffset = 0;
    for (var cellIndex = 0; cellIndex < keys.length; cellIndex += 1) {
      offsets[cellIndex] = writeOffset;
      final bucket = buckets[keys[cellIndex]]!;
      for (final instanceIndex in bucket) {
        flattened[writeOffset] = instanceIndex;
        writeOffset += 1;
      }
    }
    offsets[keys.length] = writeOffset;

    return BimSpatialGridIndex._(
      cellSizeX: cellSizeX,
      cellSizeY: cellSizeY,
      cellSizeZ: cellSizeZ,
      cellKeys: Int64List.fromList(keys),
      cellOffsets: offsets,
      instanceIndices: flattened,
      instanceCount: instances.length,
    );
  }

  final double cellSizeX;
  final double cellSizeY;
  final double cellSizeZ;
  final Int64List cellKeys;
  final Uint32List cellOffsets;
  final Uint32List instanceIndices;

  // One stamp and one candidate scratch array are shared by sequential camera
  // queries on this isolate. This index is intentionally not cross-isolate
  // mutable state; workers should build/read their own index snapshot.
  final Uint32List _queryMarks;
  final Uint32List _queryScratch;
  int _queryGeneration = 0;

  int get occupiedCellCount => cellKeys.length;

  /// Returns unique instance indices intersecting a coarse camera neighborhood.
  /// Only the final exact-size Uint32List is allocated per query.
  Uint32List queryAabb({
    required double minX,
    required double minY,
    required double minZ,
    required double maxX,
    required double maxY,
    required double maxZ,
  }) {
    final count = _collectAabbCandidates(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
    final result = Uint32List(count);
    result.setRange(0, count, _queryScratch);
    result.sort();
    return result;
  }

  /// Coarse Google-Earth-style camera query. Candidate de-duplication is done
  /// in the reusable stamp/scratch arrays, then exact camera relevance is
  /// written back into the same scratch buffer before one final allocation.
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
    final candidateCount = _collectAabbCandidates(
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
    var resultCount = 0;

    for (var candidateOffset = 0;
        candidateOffset < candidateCount;
        candidateOffset += 1) {
      final index = _queryScratch[candidateOffset];
      final centerX = (instances.minX(index) + instances.maxX(index)) * 0.5;
      final centerY = (instances.minY(index) + instances.maxY(index)) * 0.5;
      final centerZ = (instances.minZ(index) + instances.maxZ(index)) * 0.5;
      final dx = centerX - cameraX;
      final dy = centerY - cameraY;
      final dz = centerZ - cameraZ;
      final distanceSquared = dx * dx + dy * dy + dz * dz;
      if (distanceSquared > radiusSquared) continue;
      if (distanceSquared <= nearSquared) {
        _queryScratch[resultCount++] = index;
        continue;
      }
      final distance = math.max(math.sqrt(distanceSquared), 1e-9);
      final dot = (dx * fx + dy * fy + dz * fz) / distance;
      if (dot >= rearDotThreshold) {
        _queryScratch[resultCount++] = index;
      }
    }

    final result = Uint32List(resultCount);
    result.setRange(0, resultCount, _queryScratch);
    return result;
  }

  int _collectAabbCandidates({
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
    final generation = _nextGeneration();
    var count = 0;

    for (var x = firstX; x <= lastX; x += 1) {
      for (var y = firstY; y <= lastY; y += 1) {
        for (var z = firstZ; z <= lastZ; z += 1) {
          final cellIndex = _binarySearch(cellKeys, _pack(x, y, z));
          if (cellIndex < 0) continue;
          final start = cellOffsets[cellIndex];
          final end = cellOffsets[cellIndex + 1];
          for (var offset = start; offset < end; offset += 1) {
            final instanceIndex = instanceIndices[offset];
            if (_queryMarks[instanceIndex] == generation) continue;
            _queryMarks[instanceIndex] = generation;
            _queryScratch[count++] = instanceIndex;
          }
        }
      }
    }
    return count;
  }

  int _nextGeneration() {
    _queryGeneration = (_queryGeneration + 1) & 0xffffffff;
    if (_queryGeneration == 0) {
      // A 32-bit stamp wraps only after billions of queries. Clearing here is
      // still cheaper and safer than letting an ancient mark become current.
      _queryMarks.fillRange(0, _queryMarks.length, 0);
      _queryGeneration = 1;
    }
    return _queryGeneration;
  }

  static int _cell(double coordinate, double cellSize) =>
      (coordinate / cellSize).floor();

  // 21 signed bits per axis packed into 63 bits. At a 32 m cell size this
  // covers roughly +/-33,500 km around project origin, well beyond BIM needs.
  static int _pack(int x, int y, int z) {
    const bias = 1 << 20;
    const mask = (1 << 21) - 1;
    final bx = (x + bias).clamp(0, mask).toInt();
    final by = (y + bias).clamp(0, mask).toInt();
    final bz = (z + bias).clamp(0, mask).toInt();
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
