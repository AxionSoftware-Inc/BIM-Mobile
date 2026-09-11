import 'dart:typed_data';

import 'family_gpu_residency.dart';
import 'family_instance_store.dart';
import 'family_render_batches.dart';
import 'family_representation.dart';
import 'family_spatial_streaming.dart';

/// One complete camera-frame decision for the family 3D runtime.
///
/// This object is intentionally renderer-agnostic. Android Filament and a
/// future desktop renderer can consume the same visible instance indices,
/// shared-geometry batches and bounded residency decision.
final class Family3dRuntimeFramePlan {
  const Family3dRuntimeFramePlan({
    required this.visibleInstanceIndices,
    required this.renderPlan,
    required this.residency,
  });

  final Uint32List visibleInstanceIndices;
  final FamilyRenderPlan renderPlan;
  final FamilyGpuResidencyDecision residency;
}

/// Composes the family runtime pipeline without scanning all placed families:
///
/// camera -> spatial neighbourhood -> projected-size LOD batches -> residency.
abstract final class Family3dRuntimePlanner {
  static Family3dRuntimeFramePlan plan({
    required FamilyInstanceStore store,
    required FamilySpatialIndex spatialIndex,
    required FamilyGpuResidencyController residencyController,
    required FamilyStreamingCamera camera,
    required Set<FamilyGpuResidencyKey> currentResident,
    required FamilyGpuByteEstimator estimateBytes,
    required FamilyProjectedSizeResolver projectedSizeResolver,
    double radiusMeters = 220,
    double rearDotThreshold = -0.18,
    int maxVisibleInstances = 50000,
    int? levelId,
  }) {
    final visible = spatialIndex.queryCamera(
      camera,
      radiusMeters: radiusMeters,
      rearDotThreshold: rearDotThreshold,
      levelId: levelId,
      maxResults: maxVisibleInstances,
    );
    final renderPlan = FamilyRenderBatchPlanner.plan(
      store: store,
      visibleInstanceIndices: visible,
      view: FamilyViewRepresentation.model3d,
      projectedSizeResolver: projectedSizeResolver,
    );
    final residency = residencyController.decide(
      plan: renderPlan,
      currentResident: currentResident,
      estimateBytes: estimateBytes,
    );
    return Family3dRuntimeFramePlan(
      visibleInstanceIndices: visible,
      renderPlan: renderPlan,
      residency: residency,
    );
  }
}
