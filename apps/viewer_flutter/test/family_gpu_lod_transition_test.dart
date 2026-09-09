import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_runtime/family_gpu_residency.dart';
import 'package:viewer_flutter/src/family_runtime/family_render_batches.dart';
import 'package:viewer_flutter/src/family_runtime/family_representation.dart';

void main() {
  FamilyGpuInstanceBatch batch(FamilyGeometryLod lod) =>
      FamilyGpuInstanceBatch(
        geometryVariantId: 42,
        lod: lod,
        geometryAssetKey: 'chair:${lod.name}',
        instanceIndices: Uint32List.fromList(<int>[0, 1, 2, 3]),
      );

  FamilyGpuResidencyKey key(FamilyGeometryLod lod) => FamilyGpuResidencyKey(
        geometryVariantId: 42,
        lod: lod,
      );

  test('keeps old same-variant LOD until requested LOD can replace it', () {
    final controller = FamilyGpuResidencyController(
      maxResidentGeometryBytes: 16 * 1024 * 1024,
      warmGraceEpochs: 0,
    );

    controller.decide(
      plan: FamilyRenderPlan(
        gpuInstanceBatches: <FamilyGpuInstanceBatch>[
          batch(FamilyGeometryLod.low),
        ],
      ),
      currentResident: <FamilyGpuResidencyKey>{},
      estimateBytes: (_) => 4 * 1024 * 1024,
    );

    final low = key(FamilyGeometryLod.low);
    final medium = key(FamilyGeometryLod.medium);
    final transition = controller.decide(
      plan: FamilyRenderPlan(
        gpuInstanceBatches: <FamilyGpuInstanceBatch>[
          batch(FamilyGeometryLod.medium),
        ],
      ),
      currentResident: <FamilyGpuResidencyKey>{low},
      estimateBytes: (_) => 4 * 1024 * 1024,
    );

    expect(transition.loadOrder, <FamilyGpuResidencyKey>[medium]);
    expect(transition.keepResident, containsAll(<FamilyGpuResidencyKey>[
      low,
      medium,
    ]));
    expect(transition.fallbackResident[medium], low);
    expect(transition.evict, isEmpty);
  });

  test('drops LOD fallback when it would violate the byte budget', () {
    final controller = FamilyGpuResidencyController(
      maxResidentGeometryBytes: 6 * 1024 * 1024,
      warmGraceEpochs: 8,
    );

    controller.decide(
      plan: FamilyRenderPlan(
        gpuInstanceBatches: <FamilyGpuInstanceBatch>[
          batch(FamilyGeometryLod.low),
        ],
      ),
      currentResident: <FamilyGpuResidencyKey>{},
      estimateBytes: (_) => 4 * 1024 * 1024,
    );

    final low = key(FamilyGeometryLod.low);
    final medium = key(FamilyGeometryLod.medium);
    final transition = controller.decide(
      plan: FamilyRenderPlan(
        gpuInstanceBatches: <FamilyGpuInstanceBatch>[
          batch(FamilyGeometryLod.medium),
        ],
      ),
      currentResident: <FamilyGpuResidencyKey>{low},
      estimateBytes: (_) => 4 * 1024 * 1024,
    );

    expect(transition.keepResident, <FamilyGpuResidencyKey>{medium});
    expect(transition.fallbackResident, isEmpty);
    expect(transition.evict, <FamilyGpuResidencyKey>{low});
  });
}
