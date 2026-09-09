import 'dart:collection';

import 'family_render_batches.dart';
import 'family_representation.dart';

/// Stable identity of one shared family GPU geometry payload.
///
/// Instances never appear in this key: ten thousand chairs using the same
/// geometry variant/LOD must reference one resident mesh allocation.
final class FamilyGpuResidencyKey {
  const FamilyGpuResidencyKey({
    required this.geometryVariantId,
    required this.lod,
  });

  factory FamilyGpuResidencyKey.fromBatch(FamilyGpuInstanceBatch batch) =>
      FamilyGpuResidencyKey(
        geometryVariantId: batch.geometryVariantId,
        lod: batch.lod,
      );

  final int geometryVariantId;
  final FamilyGeometryLod lod;

  @override
  bool operator ==(Object other) =>
      other is FamilyGpuResidencyKey &&
      other.geometryVariantId == geometryVariantId &&
      other.lod == lod;

  @override
  int get hashCode => Object.hash(geometryVariantId, lod);

  @override
  String toString() => 'family:$geometryVariantId:${lod.name}';
}

typedef FamilyGpuByteEstimator = int Function(FamilyGpuInstanceBatch batch);

/// Result of one camera/residency reconciliation.
///
/// [loadOrder] contains only geometry that is actively requested by the current
/// render plan. Recently used geometry may remain in [keepResident] for a few
/// camera epochs, but is never reloaded merely to keep the warm cache full.
final class FamilyGpuResidencyDecision {
  const FamilyGpuResidencyDecision({
    required this.loadOrder,
    required this.keepResident,
    required this.evict,
    required this.activeBytes,
    required this.targetResidentBytes,
    required this.activeOverBudget,
  });

  final List<FamilyGpuResidencyKey> loadOrder;
  final Set<FamilyGpuResidencyKey> keepResident;
  final Set<FamilyGpuResidencyKey> evict;
  final int activeBytes;
  final int targetResidentBytes;

  /// True when the currently visible/requested geometry alone exceeds the
  /// configured budget. Active geometry is deliberately not dropped here;
  /// the caller can respond by selecting a coarser LOD on the next plan.
  final bool activeOverBudget;
}

/// Small stateful controller for family geometry residency.
///
/// The spatial index decides *which placements* matter. The render planner
/// groups those placements by geometry variant/LOD. This controller is the
/// final memory boundary: it keeps active geometry, opportunistically retains
/// recently used variants to avoid camera-edge thrash, and evicts warm assets
/// before they can exceed the GPU budget.
final class FamilyGpuResidencyController {
  FamilyGpuResidencyController({
    this.maxResidentGeometryBytes = 256 * 1024 * 1024,
    this.maxResidentVariants = 256,
    this.warmGraceEpochs = 6,
  })  : assert(maxResidentGeometryBytes > 0),
        assert(maxResidentVariants > 0),
        assert(warmGraceEpochs >= 0);

  final int maxResidentGeometryBytes;
  final int maxResidentVariants;
  final int warmGraceEpochs;

  int _epoch = 0;
  final Map<FamilyGpuResidencyKey, int> _lastRequestedEpoch =
      <FamilyGpuResidencyKey, int>{};
  final Map<FamilyGpuResidencyKey, int> _estimatedBytes =
      <FamilyGpuResidencyKey, int>{};

  int get epoch => _epoch;

  FamilyGpuResidencyDecision decide({
    required FamilyRenderPlan plan,
    required Set<FamilyGpuResidencyKey> currentResident,
    required FamilyGpuByteEstimator estimateBytes,
  }) {
    _epoch += 1;

    final activeBatches = <FamilyGpuResidencyKey, FamilyGpuInstanceBatch>{};
    for (final batch in plan.gpuInstanceBatches) {
      final key = FamilyGpuResidencyKey.fromBatch(batch);
      activeBatches[key] = batch;
      _lastRequestedEpoch[key] = _epoch;
      // Unknown/zero estimates must not create an unbounded warm cache. A
      // 4 KiB floor is intentionally tiny but still gives every asset weight.
      _estimatedBytes[key] = estimateBytes(batch).clamp(4096, 1 << 62);
    }

    final activeKeys = activeBatches.keys.toSet();
    final activeBytes = activeKeys.fold<int>(
      0,
      (sum, key) => sum + (_estimatedBytes[key] ?? 4096),
    );
    final activeOverBudget =
        activeBytes > maxResidentGeometryBytes ||
            activeKeys.length > maxResidentVariants;

    // Active geometry is never silently discarded. Missing visible families
    // are worse than temporary memory pressure; a higher layer can request a
    // coarser LOD after observing [activeOverBudget].
    final keep = LinkedHashSet<FamilyGpuResidencyKey>()..addAll(activeKeys);
    var targetBytes = activeBytes;

    final warmCandidates = currentResident
        .where((key) => !activeKeys.contains(key))
        .where((key) {
          final lastSeen = _lastRequestedEpoch[key];
          return lastSeen != null && _epoch - lastSeen <= warmGraceEpochs;
        })
        .toList()
      ..sort((left, right) {
        final recency = (_lastRequestedEpoch[right] ?? -1)
            .compareTo(_lastRequestedEpoch[left] ?? -1);
        if (recency != 0) return recency;
        return (_estimatedBytes[left] ?? 4096)
            .compareTo(_estimatedBytes[right] ?? 4096);
      });

    for (final key in warmCandidates) {
      if (keep.length >= maxResidentVariants) break;
      final bytes = _estimatedBytes[key] ?? 4096;
      if (targetBytes + bytes > maxResidentGeometryBytes) continue;
      keep.add(key);
      targetBytes += bytes;
    }

    final evict = currentResident.difference(keep);
    final loadBatches = activeBatches.values
        .where((batch) =>
            !currentResident.contains(FamilyGpuResidencyKey.fromBatch(batch)))
        .toList()
      ..sort((left, right) {
        // Coarse assets first give the renderer a useful image sooner. Within
        // one LOD, geometry reused by more placements has higher visible value.
        final lodOrder = left.lod.index.compareTo(right.lod.index);
        if (lodOrder != 0) return lodOrder;
        final instanceOrder =
            right.instanceIndices.length.compareTo(left.instanceIndices.length);
        if (instanceOrder != 0) return instanceOrder;
        return left.geometryVariantId.compareTo(right.geometryVariantId);
      });

    _pruneHistory(currentResident: currentResident, activeKeys: activeKeys);

    return FamilyGpuResidencyDecision(
      loadOrder: List<FamilyGpuResidencyKey>.unmodifiable(
        loadBatches.map(FamilyGpuResidencyKey.fromBatch),
      ),
      keepResident: Set<FamilyGpuResidencyKey>.unmodifiable(keep),
      evict: Set<FamilyGpuResidencyKey>.unmodifiable(evict),
      activeBytes: activeBytes,
      targetResidentBytes: targetBytes,
      activeOverBudget: activeOverBudget,
    );
  }

  void reset() {
    _epoch = 0;
    _lastRequestedEpoch.clear();
    _estimatedBytes.clear();
  }

  void _pruneHistory({
    required Set<FamilyGpuResidencyKey> currentResident,
    required Set<FamilyGpuResidencyKey> activeKeys,
  }) {
    final retention = warmGraceEpochs + 8;
    final stale = _lastRequestedEpoch.entries
        .where((entry) =>
            !currentResident.contains(entry.key) &&
            !activeKeys.contains(entry.key) &&
            _epoch - entry.value > retention)
        .map((entry) => entry.key)
        .toList();
    for (final key in stale) {
      _lastRequestedEpoch.remove(key);
      _estimatedBytes.remove(key);
    }
  }
}
