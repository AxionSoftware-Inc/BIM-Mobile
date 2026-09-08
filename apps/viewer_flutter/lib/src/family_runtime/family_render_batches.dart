import 'dart:typed_data';

import 'family_instance_store.dart';
import 'family_representation.dart';

/// One lightweight 2D symbol with many placed transforms.
final class Family2dSymbolBatch {
  const Family2dSymbolBatch({
    required this.encoding,
    required this.assetKey,
    required this.instanceIndices,
  });

  final Family2dEncoding encoding;
  final String assetKey;
  final Uint32List instanceIndices;
}

/// One shared 3D geometry variant/LOD with many transforms.
///
/// Native Filament integration should create one VertexBuffer/IndexBuffer per
/// `(geometryVariantId, lod)` residency entry and upload only the transform
/// rows for [instanceIndices]. It must never duplicate mesh buffers per placed
/// chair/table/sofa instance.
final class FamilyGpuInstanceBatch {
  const FamilyGpuInstanceBatch({
    required this.geometryVariantId,
    required this.lod,
    required this.geometryAssetKey,
    required this.instanceIndices,
  });

  final int geometryVariantId;
  final FamilyGeometryLod lod;
  final String? geometryAssetKey;
  final Uint32List instanceIndices;
}

final class FamilyRenderPlan {
  const FamilyRenderPlan({
    this.twoDimensionalBatches = const <Family2dSymbolBatch>[],
    this.gpuInstanceBatches = const <FamilyGpuInstanceBatch>[],
  });

  final List<Family2dSymbolBatch> twoDimensionalBatches;
  final List<FamilyGpuInstanceBatch> gpuInstanceBatches;

  bool get requires3dGeometry => gpuInstanceBatches.isNotEmpty;
}

typedef FamilyProjectedSizeResolver = double Function(int instanceIndex);

/// Converts a camera/floor-filtered instance set into a small number of render
/// batches. Batch objects are per unique representation, not per family
/// placement, so runtime object count follows visible unique geometry rather
/// than total BIM element count.
abstract final class FamilyRenderBatchPlanner {
  static FamilyRenderPlan plan({
    required FamilyInstanceStore store,
    required Uint32List visibleInstanceIndices,
    required FamilyViewRepresentation view,
    FamilyProjectedSizeResolver? projectedSizeResolver,
  }) {
    if (visibleInstanceIndices.isEmpty) return const FamilyRenderPlan();

    if (view != FamilyViewRepresentation.model3d) {
      final groups = <String, _Mutable2dBatch>{};
      for (final instanceIndex in visibleInstanceIndices) {
        if (instanceIndex >= store.length) continue;
        final variant = store.variantAtInstance(instanceIndex);
        final decision = FamilyRepresentationPolicy.choose(
          variant.representations,
          FamilyRepresentationRequest(view: view),
        );
        final symbol = decision.twoDimensional;
        if (symbol == null) continue;
        final key = '${symbol.encoding.index}\u0000${symbol.assetKey}';
        final group = groups.putIfAbsent(
          key,
          () => _Mutable2dBatch(symbol.encoding, symbol.assetKey),
        );
        group.indices.add(instanceIndex);
      }
      return FamilyRenderPlan(
        twoDimensionalBatches: List.unmodifiable(
          groups.values.map(
            (group) => Family2dSymbolBatch(
              encoding: group.encoding,
              assetKey: group.assetKey,
              instanceIndices: Uint32List.fromList(group.indices),
            ),
          ),
        ),
      );
    }

    final groups = <String, _Mutable3dBatch>{};
    for (final instanceIndex in visibleInstanceIndices) {
      if (instanceIndex >= store.length) continue;
      final variant = store.variantAtInstance(instanceIndex);
      final projectedPixels = projectedSizeResolver?.call(instanceIndex) ?? 64.0;
      final decision = FamilyRepresentationPolicy.choose(
        variant.representations,
        FamilyRepresentationRequest(
          view: FamilyViewRepresentation.model3d,
          projectedSizePixels: projectedPixels,
        ),
      );
      final lod = decision.lod ?? FamilyGeometryLod.proxy;
      final key = '${variant.id}\u0000${lod.index}';
      final group = groups.putIfAbsent(
        key,
        () => _Mutable3dBatch(
          variant.id,
          lod,
          decision.geometryAssetKey,
        ),
      );
      group.indices.add(instanceIndex);
    }
    return FamilyRenderPlan(
      gpuInstanceBatches: List.unmodifiable(
        groups.values.map(
          (group) => FamilyGpuInstanceBatch(
            geometryVariantId: group.variantId,
            lod: group.lod,
            geometryAssetKey: group.assetKey,
            instanceIndices: Uint32List.fromList(group.indices),
          ),
        ),
      ),
    );
  }
}

final class _Mutable2dBatch {
  _Mutable2dBatch(this.encoding, this.assetKey);

  final Family2dEncoding encoding;
  final String assetKey;
  final List<int> indices = <int>[];
}

final class _Mutable3dBatch {
  _Mutable3dBatch(this.variantId, this.lod, this.assetKey);

  final int variantId;
  final FamilyGeometryLod lod;
  final String? assetKey;
  final List<int> indices = <int>[];
}
