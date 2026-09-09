import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/family_runtime/family_instance_store.dart';
import 'package:viewer_flutter/src/family_runtime/family_render_batches.dart';
import 'package:viewer_flutter/src/family_runtime/family_representation.dart';
import 'package:viewer_flutter/src/family_runtime/family_spatial_streaming.dart';

void main() {
  const plan = Family2dRepresentationDescriptor(
    encoding: Family2dEncoding.compactVector,
    assetKey: 'chair-a:plan',
  );
  const representations = FamilyRepresentationSet(
    plan: plan,
    model3d: Family3dRepresentationDescriptor(
      geometryVariantId: 0,
      proxyAssetKey: 'chair-a:proxy',
      lowAssetKey: 'chair-a:low',
      fullAssetKey: 'chair-a:full',
    ),
  );

  FamilyRuntimeInstanceSeed chair(int index, {String signature = 'w=450'}) =>
      FamilyRuntimeInstanceSeed(
        instanceId: index + 1,
        familyAssetId: 'chair-a',
        familyTypeId: 'chair-450',
        category: 'furniture',
        parameterSignature: signature,
        geometryKey: 'chair-a:$signature',
        representations: representations,
        levelId: 1,
        x: (index % 40) * 1.2,
        y: (index ~/ 40) * 1.2,
        z: 0,
        halfExtentX: 0.3,
        halfExtentY: 0.3,
        halfExtentZ: 0.5,
      );

  test('one thousand equal placements share one geometry variant', () {
    final store = FamilyInstanceStore.fromSeeds(
      List.generate(1000, chair),
    );

    expect(store.length, 1000);
    expect(store.definitions, hasLength(1));
    expect(store.types, hasLength(1));
    expect(store.geometryVariants, hasLength(1));
    expect(store.geometryVariantIds.toSet(), <int>{0});
  });

  test('different parameter signatures create variants not per-instance meshes', () {
    final store = FamilyInstanceStore.fromSeeds(<FamilyRuntimeInstanceSeed>[
      chair(0),
      chair(1),
      chair(2, signature: 'w=520'),
      chair(3, signature: 'w=520'),
    ]);

    expect(store.definitions, hasLength(1));
    expect(store.types, hasLength(1));
    expect(store.geometryVariants, hasLength(2));
  });

  test('floor plan produces lightweight symbol batch and no 3D request', () {
    final store = FamilyInstanceStore.fromSeeds(List.generate(1000, chair));
    final visible = Uint32List.fromList(List.generate(1000, (index) => index));

    final renderPlan = FamilyRenderBatchPlanner.plan(
      store: store,
      visibleInstanceIndices: visible,
      view: FamilyViewRepresentation.plan2d,
    );

    expect(renderPlan.requires3dGeometry, isFalse);
    expect(renderPlan.twoDimensionalBatches, hasLength(1));
    expect(renderPlan.twoDimensionalBatches.single.instanceIndices, hasLength(1000));
    expect(renderPlan.twoDimensionalBatches.single.assetKey, 'chair-a:plan');
  });

  test('3D groups equal geometry and LOD into one GPU instancing batch', () {
    final store = FamilyInstanceStore.fromSeeds(List.generate(1000, chair));
    final visible = Uint32List.fromList(List.generate(1000, (index) => index));

    final renderPlan = FamilyRenderBatchPlanner.plan(
      store: store,
      visibleInstanceIndices: visible,
      view: FamilyViewRepresentation.model3d,
      projectedSizeResolver: (_) => 80,
    );

    expect(renderPlan.twoDimensionalBatches, isEmpty);
    expect(renderPlan.gpuInstanceBatches, hasLength(1));
    expect(renderPlan.gpuInstanceBatches.single.lod, FamilyGeometryLod.medium);
    expect(renderPlan.gpuInstanceBatches.single.instanceIndices, hasLength(1000));
  });

  test('spatial index returns only the camera neighbourhood', () {
    final seeds = <FamilyRuntimeInstanceSeed>[
      for (var i = 0; i < 100; i++) chair(i),
      for (var i = 100; i < 200; i++)
        FamilyRuntimeInstanceSeed(
          instanceId: i + 1,
          familyAssetId: 'chair-a',
          familyTypeId: 'chair-450',
          category: 'furniture',
          parameterSignature: 'w=450',
          geometryKey: 'chair-a:w=450',
          representations: representations,
          levelId: 1,
          x: (1000 + i).toDouble(),
          y: 1000,
          z: 0,
        ),
    ];
    final store = FamilyInstanceStore.fromSeeds(seeds);
    final spatial = FamilySpatialIndex.build(store);
    final visible = spatial.queryCamera(
      const FamilyStreamingCamera(
        x: 0,
        y: 0,
        z: 2,
        forwardX: 1,
        forwardY: 0,
        forwardZ: 0,
      ),
      radiusMeters: 120,
    );

    expect(visible, isNotEmpty);
    expect(visible.every((index) => index < 100), isTrue);
  });
}
