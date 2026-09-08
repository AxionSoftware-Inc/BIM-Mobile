import 'dart:math' as math;
import 'dart:typed_data';

import 'family_instance_store.dart';

/// Camera input independent of Flutter/Filament so the same family residency
/// policy can be reused by Android and a future desktop renderer.
final class FamilyStreamingCamera {
  const FamilyStreamingCamera({
    required this.x,
    required this.y,
    required this.z,
    required this.forwardX,
    required this.forwardY,
    required this.forwardZ,
  });

  final double x;
  final double y;
  final double z;
  final double forwardX;
  final double forwardY;
  final double forwardZ;
}

/// Compact spatial lookup for placed family instances.
///
/// Build-time uses a Map/List for clarity, but the retained runtime structure
/// is CSR-style typed arrays: sorted cell keys + offsets + instance indices.
/// The renderer queries only nearby cells instead of scanning every furniture
/// placement in a campus-size project.
final class FamilySpatialIndex {
  FamilySpatialIndex._({
    required this.store,
    required this.cellSizeX,
    required this.cellSizeY,
    required this.cellSizeZ,
    required this.cellKeys,
    required this.cellOffsets,
    required this.instanceIndices,
  })  : _seenStamp = Uint32List(store.length),
        _scratch = Uint32List(math.max(store.length, 1));

  factory FamilySpatialIndex.build(
    FamilyInstanceStore store, {
    double cellSizeX = 24,
    double cellSizeY = 24,
    double cellSizeZ = 8,
  }) {
    if (cellSizeX <= 0 || cellSizeY <= 0 || cellSizeZ <= 0) {
      throw ArgumentError('Family spatial cell sizes must be positive.');
    }
    final cells = <int, List<int>>{};
    for (var index = 0; index < store.length; index++) {
      final p = store.positionAt(index);
      final e = store.halfExtentAt(index);
      final minX = ((p.x - e.x) / cellSizeX).floor();
      final maxX = ((p.x + e.x) / cellSizeX).floor();
      final minY = ((p.y - e.y) / cellSizeY).floor();
      final maxY = ((p.y + e.y) / cellSizeY).floor();
      final minZ = ((p.z - e.z) / cellSizeZ).floor();
      final maxZ = ((p.z + e.z) / cellSizeZ).floor();

      final span = (maxX - minX + 1) *
          (maxY - minY + 1) *
          (maxZ - minZ + 1);
      if (span > 256) {
        // A pathological/very large proxy must not explode the grid. Its
        // center cell keeps it discoverable; future building-HLOD can own
        // coarse coverage for truly huge assets.
        final key = _packCell(
          (p.x / cellSizeX).floor(),
          (p.y / cellSizeY).floor(),
          (p.z / cellSizeZ).floor(),
        );
        (cells[key] ??= <int>[]).add(index);
        continue;
      }
      for (var z = minZ; z <= maxZ; z++) {
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            (cells[_packCell(x, y, z)] ??= <int>[]).add(index);
          }
        }
      }
    }

    final keys = cells.keys.toList()..sort();
    final offsets = Uint32List(keys.length + 1);
    var total = 0;
    for (var index = 0; index < keys.length; index++) {
      offsets[index] = total;
      total += cells[keys[index]]!.length;
    }
    offsets[keys.length] = total;
    final indices = Uint32List(total);
    var cursor = 0;
    for (final key in keys) {
      for (final instanceIndex in cells[key]!) {
        indices[cursor++] = instanceIndex;
      }
    }
    return FamilySpatialIndex._(
      store: store,
      cellSizeX: cellSizeX,
      cellSizeY: cellSizeY,
      cellSizeZ: cellSizeZ,
      cellKeys: Int64List.fromList(keys),
      cellOffsets: offsets,
      instanceIndices: indices,
    );
  }

  final FamilyInstanceStore store;
  final double cellSizeX;
  final double cellSizeY;
  final double cellSizeZ;
  final Int64List cellKeys;
  final Uint32List cellOffsets;
  final Uint32List instanceIndices;

  final Uint32List _seenStamp;
  final Uint32List _scratch;
  int _generation = 0;

  /// Returns only camera-neighbourhood instances, optionally restricted to a
  /// level (floor plan). This is the family equivalent of native BIM chunk
  /// streaming: knowing one million placements does not make them renderable.
  Uint32List queryCamera(
    FamilyStreamingCamera camera, {
    double radiusMeters = 180,
    double rearDotThreshold = -0.20,
    int? levelId,
    int maxResults = 50000,
  }) {
    if (store.isEmpty || maxResults <= 0 || radiusMeters <= 0) {
      return Uint32List(0);
    }
    _nextGeneration();
    final radius2 = radiusMeters * radiusMeters;
    final forwardLength = math.sqrt(
      camera.forwardX * camera.forwardX +
          camera.forwardY * camera.forwardY +
          camera.forwardZ * camera.forwardZ,
    );
    final fx = forwardLength > 1e-9 ? camera.forwardX / forwardLength : 0.0;
    final fy = forwardLength > 1e-9 ? camera.forwardY / forwardLength : 0.0;
    final fz = forwardLength > 1e-9 ? camera.forwardZ / forwardLength : -1.0;

    final minCellX = ((camera.x - radiusMeters) / cellSizeX).floor();
    final maxCellX = ((camera.x + radiusMeters) / cellSizeX).floor();
    final minCellY = ((camera.y - radiusMeters) / cellSizeY).floor();
    final maxCellY = ((camera.y + radiusMeters) / cellSizeY).floor();
    final minCellZ = ((camera.z - radiusMeters) / cellSizeZ).floor();
    final maxCellZ = ((camera.z + radiusMeters) / cellSizeZ).floor();

    var count = 0;
    for (var z = minCellZ; z <= maxCellZ && count < maxResults; z++) {
      for (var y = minCellY; y <= maxCellY && count < maxResults; y++) {
        for (var x = minCellX; x <= maxCellX && count < maxResults; x++) {
          final cell = _findCell(_packCell(x, y, z));
          if (cell < 0) continue;
          final start = cellOffsets[cell];
          final end = cellOffsets[cell + 1];
          for (var offset = start; offset < end && count < maxResults; offset++) {
            final instanceIndex = instanceIndices[offset];
            if (_seenStamp[instanceIndex] == _generation) continue;
            _seenStamp[instanceIndex] = _generation;
            if (levelId != null && store.levelIds[instanceIndex] != levelId) {
              continue;
            }
            final p = store.positionAt(instanceIndex);
            final dx = p.x - camera.x;
            final dy = p.y - camera.y;
            final dz = p.z - camera.z;
            final distance2 = dx * dx + dy * dy + dz * dz;
            if (distance2 > radius2) continue;
            final distance = math.sqrt(distance2).clamp(1e-9, double.infinity);
            final dot = (dx * fx + dy * fy + dz * fz) / distance;
            // Keep very near instances even if technically behind the camera;
            // orbit/pan gestures would otherwise pop furniture at the edge.
            if (distance > 12 && dot < rearDotThreshold) continue;
            _scratch[count++] = instanceIndex;
          }
        }
      }
    }
    return Uint32List.fromList(_scratch.sublist(0, count));
  }

  void _nextGeneration() {
    _generation = (_generation + 1) & 0xFFFFFFFF;
    if (_generation == 0) {
      _seenStamp.fillRange(0, _seenStamp.length, 0);
      _generation = 1;
    }
  }

  int _findCell(int key) {
    var low = 0;
    var high = cellKeys.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final value = cellKeys[middle];
      if (value == key) return middle;
      if (value < key) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return -1;
  }

  static int _packCell(int x, int y, int z) {
    const bias = 1 << 20;
    const mask = (1 << 21) - 1;
    final px = (x + bias) & mask;
    final py = (y + bias) & mask;
    final pz = (z + bias) & mask;
    return (px << 42) | (py << 21) | pz;
  }
}
