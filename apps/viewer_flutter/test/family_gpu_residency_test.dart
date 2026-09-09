import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_runtime/family_gpu_residency.dart';
import 'package:viewer_flutter/src/family_runtime/family_render_batches.dart';
import 'package:viewer_flutter/src/family_runtime/family_representation.dart';

void main() {
  FamilyGpuInstanceBatch batch(
    int variant,
    FamilyGeometryLod lod,
    int instanceCount,
  ) =>
      FamilyGpuInstanceBatch(
        geometryVariantId: variant,
        lod: lod,
        geometryAssetKey: 'family:$variant:${lod.name}',
        instanceIndices: Uint32List.fromList(
          List<int>.generate(instanceCount, (index) => index),
        ),
      );

  FamilyRenderPlan plan(List<FamilyGpuInstanceBatch> batches) =>
      FamilyRenderPlan(gpuInstanceBatches: batches);

  FamilyGpuResidencyKey key(int variant, FamilyGeometryLod lod) =>
      FamilyGpuResidencyKey(geometryVariantId: variant, lod: lod);

  group('FamilyGpuResidencyController', () {
    test('loads one geometry payload for many visible instances', () {
      final controller = FamilyGpuResidencyController();
      final chair = batch(11, FamilyGeometryLod.medium, 10000);
      final decision = controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[chair]),
        currentResident: <FamilyGpuResidencyKey>{},
        estimateBytes: (_) => 2 * 1024 * 1024,
      );

      expect(decision.loadOrder, <FamilyGpuResidencyKey>[
        key(11, FamilyGeometryLod.medium),
      ]);
      expect(decision.keepResident.length, 1);
      expect(decision.targetResidentBytes, 2 * 1024 * 1024);
      expect(decision.activeOverBudget, isFalse);
    });

    test('keeps recently used geometry warm inside grace window', () {
      final controller = FamilyGpuResidencyController(
        maxResidentGeometryBytes: 16 * 1024 * 1024,
        warmGraceEpochs: 2,
      );
      final chairKey = key(1, FamilyGeometryLod.low);
      final tableKey = key(2, FamilyGeometryLod.low);

      controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(1, FamilyGeometryLod.low, 40),
        ]),
        currentResident: <FamilyGpuResidencyKey>{},
        estimateBytes: (_) => 4 * 1024 * 1024,
      );

      final decision = controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(2, FamilyGeometryLod.low, 12),
        ]),
        currentResident: <FamilyGpuResidencyKey>{chairKey},
        estimateBytes: (_) => 4 * 1024 * 1024,
      );

      expect(decision.keepResident, containsAll(<FamilyGpuResidencyKey>[
        chairKey,
        tableKey,
      ]));
      expect(decision.evict, isEmpty);
      expect(decision.loadOrder, <FamilyGpuResidencyKey>[tableKey]);
    });

    test('evicts warm geometry before exceeding byte budget', () {
      final controller = FamilyGpuResidencyController(
        maxResidentGeometryBytes: 8 * 1024 * 1024,
        warmGraceEpochs: 4,
      );
      final oldKey = key(1, FamilyGeometryLod.medium);
      final activeKey = key(2, FamilyGeometryLod.medium);

      controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(1, FamilyGeometryLod.medium, 20),
        ]),
        currentResident: <FamilyGpuResidencyKey>{},
        estimateBytes: (_) => 6 * 1024 * 1024,
      );

      final decision = controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(2, FamilyGeometryLod.medium, 20),
        ]),
        currentResident: <FamilyGpuResidencyKey>{oldKey},
        estimateBytes: (_) => 6 * 1024 * 1024,
      );

      expect(decision.keepResident, <FamilyGpuResidencyKey>{activeKey});
      expect(decision.evict, <FamilyGpuResidencyKey>{oldKey});
      expect(decision.targetResidentBytes, 6 * 1024 * 1024);
    });

    test('does not hide active families when visible set itself is over budget', () {
      final controller = FamilyGpuResidencyController(
        maxResidentGeometryBytes: 4 * 1024 * 1024,
        maxResidentVariants: 1,
      );
      final decision = controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(7, FamilyGeometryLod.full, 2),
          batch(8, FamilyGeometryLod.full, 2),
        ]),
        currentResident: <FamilyGpuResidencyKey>{},
        estimateBytes: (_) => 3 * 1024 * 1024,
      );

      expect(decision.activeOverBudget, isTrue);
      expect(decision.keepResident, containsAll(<FamilyGpuResidencyKey>[
        key(7, FamilyGeometryLod.full),
        key(8, FamilyGeometryLod.full),
      ]));
      expect(decision.loadOrder.length, 2);
      expect(decision.activeBytes, 6 * 1024 * 1024);
    });

    test('variant and LOD are separate residency identities', () {
      final controller = FamilyGpuResidencyController();
      final decision = controller.decide(
        plan: plan(<FamilyGpuInstanceBatch>[
          batch(4, FamilyGeometryLod.low, 50),
          batch(4, FamilyGeometryLod.medium, 5),
        ]),
        currentResident: <FamilyGpuResidencyKey>{},
        estimateBytes: (value) =>
            value.lod == FamilyGeometryLod.low ? 1000000 : 2000000,
      );

      expect(decision.keepResident.length, 2);
      expect(
        decision.keepResident,
        containsAll(<FamilyGpuResidencyKey>[
          key(4, FamilyGeometryLod.low),
          key(4, FamilyGeometryLod.medium),
        ]),
      );
    });
  });
}
