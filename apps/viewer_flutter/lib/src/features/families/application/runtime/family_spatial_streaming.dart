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
/// The retained structure is CSR-style typed arrays: sorted cell keys +
/// offsets + packed instance indices. Build uses two count/fill passes rather
/// than a `Map<int, List<int>>`, avoiding one growable List object per occupied
/// cell in family-heavy campuses.
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

    void visitInstanceCells(int instanceIndex, void Function(int key) visit) {
      final p = store.positionAt(instanceIndex);
      final e = store.halfExtentAt(instanceIndex);
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
        visit(
          _packCell(
            (p.x / cellSizeX).floor(),
            (p.y / cellSizeY).floor(),
            (p.z / cellSizeZ).floor(),
          ),
        );
        return;
      }
      for (var z = minZ; z <= maxZ; z++) {
        for (var y = minY; y <= maxY; y++) {
          for (var x = minX; x <= maxX; x++) {
            visit(_packCell(x, y, z));
          }
        }
      }
    }

    // Pass 1: count references per occupied cell. Integers are much cheaper
    // than retaining thousands of growable per-cell lists during compilation.
    final counts = <int, int>{};
    for (var instanceIndex = 0;
        instanceIndex < store.length;
        instanceIndex++) {
      visitInstanceCells(instanceIndex, (key) {
        counts[key] = (counts[key] ?? 0) + 1;
      });
    }

    final keys = counts.keys.toList()..sort();
    final offsets = Uint32List(keys.length + 1);
    final keyToCell = <int, int>{};
    var total = 0;
    for (var cell = 0; cell < keys.length; cell++) {
      final key = keys[cell];
      keyToCell[key] = cell;
      offsets[cell] = total;
      total += counts[key]!;
    }
    offsets[keys.length] = total;

    // Pass 2: fill the final CSR array directly.
    final indices = Uint32List(total);
    final cursors = Uint32List(keys.length);
    for (var cell = 0; cell < keys.length; cell++) {
      cursors[cell] = offsets[cell];
    }
    for (var instanceIndex = 0;
        instanceIndex < store.length;
        instanceIndex++) {
      visitInstanceCells(instanceIndex, (key) {
        final cell = keyToCell[key];
        if (cell == null) return;
        final cursor = cursors[cell];
        indices[cursor] = instanceIndex;
        cursors[cell] = cursor + 1;
      });
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

  static final Uint32List _empty = Uint32List(0);

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
  ///
  /// The returned typed-list is a zero-copy view over reusable query scratch.
  /// Consume it immediately (render planning does); do not retain it across a
  /// later query on this same index.
  Uint32List queryCamera(
    FamilyStreamingCamera camera, {
    double radiusMeters = 180,
    double rearDotThreshold = -0.20,
    int? levelId,
    int maxResults = 50000,
  }) {
    if (store.isEmpty || maxResults <= 0 || radiusMeters <= 0) {
      return _empty;
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
    final resultLimit = math.min(maxResults, store.length);

    var count = 0;
    for (var z = minCellZ; z <= maxCellZ && count < resultLimit; z++) {
      for (var y = minCellY; y <= maxCellY && count < resultLimit; y++) {
        for (var x = minCellX; x <= maxCellX && count < resultLimit; x++) {
          final cell = _findCell(_packCell(x, y, z));
          if (cell < 0) continue;
          final start = cellOffsets[cell];
          final end = cellOffsets[cell + 1];
          for (var offset = start;
              offset < end && count < resultLimit;
              offset++) {
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

    // View allocation is tiny; importantly, it does not copy `count` integers
    // on every camera update as Uint32List.fromList(sublist(...)) did.
    return Uint32List.view(
      _scratch.buffer,
      _scratch.offsetInBytes,
      count,
    );
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
