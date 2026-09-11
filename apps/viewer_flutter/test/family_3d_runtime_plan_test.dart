import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_3d_runtime_plan.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_gpu_residency.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_instance_store.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_representation.dart';
import 'package:viewer_flutter/src/features/families/application/runtime/family_spatial_streaming.dart';

void main() {
  FamilyRepresentationSet representations() => const FamilyRepresentationSet(
        model3d: Family3dRepresentationDescriptor(
          geometryVariantId: -1,
          proxyAssetKey: 'chair-proxy',
          lowAssetKey: 'chair-low',
          mediumAssetKey: 'chair-medium',
          fullAssetKey: 'chair-full',
        ),
      );

  FamilyRuntimeInstanceSeed seed({
    required int id,
    required double x,
    int levelId = 1,
  }) =>
      FamilyRuntimeInstanceSeed(
        instanceId: id,
        familyAssetId: 'builtin:chair',
        familyTypeId: 'Chair 600',
        category: 'furniture',
        parameterSignature: 'w=0.6;d=0.6',
        geometryKey: 'chair-600',
        representations: representations(),
        levelId: levelId,
        x: x,
        y: 0,
        z: 0,
        halfExtentX: 0.3,
        halfExtentY: 0.3,
        halfExtentZ: 0.5,
      );

  test('camera query becomes one shared family geometry residency request', () {
    final store = FamilyInstanceStore.fromSeeds(<FamilyRuntimeInstanceSeed>[
      seed(id: 1, x: 4),
      seed(id: 2, x: 6),
      seed(id: 3, x: 8),
      seed(id: 4, x: 10),
      seed(id: 5, x: 400),
    ]);
    final spatial = FamilySpatialIndex.build(store);
    final residency = FamilyGpuResidencyController();

    final frame = Family3dRuntimePlanner.plan(
      store: store,
      spatialIndex: spatial,
      residencyController: residency,
      camera: const FamilyStreamingCamera(
        x: 0,
        y: 0,
        z: 0,
        forwardX: 1,
        forwardY: 0,
        forwardZ: 0,
      ),
      currentResident: const <FamilyGpuResidencyKey>{},
      estimateBytes: (_) => 2 * 1024 * 1024,
      projectedSizeResolver: (_) => 80,
      radiusMeters: 30,
    );

    expect(frame.visibleInstanceIndices.length, 4);
    expect(frame.renderPlan.gpuInstanceBatches.length, 1);
    final batch = frame.renderPlan.gpuInstanceBatches.single;
    expect(batch.instanceIndices.length, 4);
    expect(batch.lod, FamilyGeometryLod.medium);
    expect(batch.geometryAssetKey, 'chair-medium');
    expect(frame.residency.loadOrder.length, 1);
    expect(frame.residency.targetResidentBytes, 2 * 1024 * 1024);
  });

  test('optional level filter prevents other-floor family residency work', () {
    final store = FamilyInstanceStore.fromSeeds(<FamilyRuntimeInstanceSeed>[
      seed(id: 1, x: 5, levelId: 1),
      seed(id: 2, x: 6, levelId: 2),
    ]);
    final frame = Family3dRuntimePlanner.plan(
      store: store,
      spatialIndex: FamilySpatialIndex.build(store),
      residencyController: FamilyGpuResidencyController(),
      camera: const FamilyStreamingCamera(
        x: 0,
        y: 0,
        z: 0,
        forwardX: 1,
        forwardY: 0,
        forwardZ: 0,
      ),
      currentResident: const <FamilyGpuResidencyKey>{},
      estimateBytes: (_) => 1024 * 1024,
      projectedSizeResolver: (_) => 20,
      radiusMeters: 20,
      levelId: 1,
    );

    expect(frame.visibleInstanceIndices.length, 1);
    expect(
        frame.renderPlan.gpuInstanceBatches.single.instanceIndices.length, 1);
  });
}
