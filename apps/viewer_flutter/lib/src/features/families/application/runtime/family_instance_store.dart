import 'dart:typed_data';

import 'family_representation.dart';

/// Shared family definition. One definition may own many types and millions
/// of placed instances; instances never copy the authoring graph or mesh.
final class FamilyRuntimeDefinition {
  const FamilyRuntimeDefinition({
    required this.id,
    required this.assetId,
    required this.category,
  });

  final int id;
  final String assetId;
  final String category;
}

/// Shared type identity underneath a family definition.
final class FamilyRuntimeType {
  const FamilyRuntimeType({
    required this.id,
    required this.definitionId,
    required this.typeId,
  });

  final int id;
  final int definitionId;
  final String typeId;
}

/// One evaluated geometry/representation variant.
///
/// Parameter changes do not create a heavyweight object per placement. They
/// produce/intern a variant signature; all instances with the same signature
/// share this row and therefore share the same eventual GPU geometry.
final class FamilyGeometryVariant {
  const FamilyGeometryVariant({
    required this.id,
    required this.typeId,
    required this.parameterSignature,
    required this.geometryKey,
    required this.representations,
  });

  final int id;
  final int typeId;
  final String parameterSignature;
  final String geometryKey;
  final FamilyRepresentationSet representations;
}

/// Input DTO used only while compiling authoring/project data into the runtime
/// store. The final [FamilyInstanceStore] is structure-of-arrays.
final class FamilyRuntimeInstanceSeed {
  const FamilyRuntimeInstanceSeed({
    required this.instanceId,
    required this.familyAssetId,
    required this.familyTypeId,
    required this.category,
    required this.parameterSignature,
    required this.geometryKey,
    required this.representations,
    required this.levelId,
    required this.x,
    required this.y,
    required this.z,
    this.rotationX = 0,
    this.rotationY = 0,
    this.rotationZ = 0,
    this.rotationW = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.scaleZ = 1,
    this.halfExtentX = 0.5,
    this.halfExtentY = 0.5,
    this.halfExtentZ = 0.5,
    this.hostId,
    this.flags = 0,
  });

  final int instanceId;
  final String familyAssetId;
  final String familyTypeId;
  final String category;
  final String parameterSignature;
  final String geometryKey;
  final FamilyRepresentationSet representations;
  final int levelId;
  final double x;
  final double y;
  final double z;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double rotationW;
  final double scaleX;
  final double scaleY;
  final double scaleZ;
  final double halfExtentX;
  final double halfExtentY;
  final double halfExtentZ;
  final int? hostId;
  final int flags;
}

/// Data-oriented placed-family database.
///
/// Runtime invariant:
/// `Definition -> Type -> GeometryVariant -> N compact instances`.
///
/// This is intentionally separate from Family Authoring. Editing/evaluating a
/// family may use rich objects, but a 1000-room project must not retain 1000
/// copies of a chair/sofa/casework mesh or parameter graph.
final class FamilyInstanceStore {
  FamilyInstanceStore._({
    required this.definitions,
    required this.types,
    required this.geometryVariants,
    required this.instanceIds,
    required this.definitionIds,
    required this.typeIds,
    required this.geometryVariantIds,
    required this.levelIds,
    required this.hostIds,
    required this.flags,
    required this.positions,
    required this.rotations,
    required this.scales,
    required this.halfExtents,
  });

  factory FamilyInstanceStore.fromSeeds(
    Iterable<FamilyRuntimeInstanceSeed> values,
  ) {
    final seeds = values.toList(growable: false);
    final definitions = <FamilyRuntimeDefinition>[];
    final types = <FamilyRuntimeType>[];
    final variants = <FamilyGeometryVariant>[];
    final definitionByKey = <String, int>{};
    final typeByKey = <String, int>{};
    final variantByKey = <String, int>{};

    final count = seeds.length;
    final instanceIds = Int64List(count);
    final definitionIds = Uint32List(count);
    final typeIds = Uint32List(count);
    final geometryVariantIds = Uint32List(count);
    final levelIds = Int64List(count);
    final hostIds = Int64List(count);
    final flags = Uint32List(count);
    final positions = Float64List(count * 3);
    final rotations = Float32List(count * 4);
    final scales = Float32List(count * 3);
    final halfExtents = Float32List(count * 3);

    for (var index = 0; index < count; index++) {
      final seed = seeds[index];
      final definitionId = definitionByKey.putIfAbsent(seed.familyAssetId, () {
        final id = definitions.length;
        definitions.add(
          FamilyRuntimeDefinition(
            id: id,
            assetId: seed.familyAssetId,
            category: seed.category,
          ),
        );
        return id;
      });

      final typeKey = '$definitionId\u0000${seed.familyTypeId}';
      final typeId = typeByKey.putIfAbsent(typeKey, () {
        final id = types.length;
        types.add(
          FamilyRuntimeType(
            id: id,
            definitionId: definitionId,
            typeId: seed.familyTypeId,
          ),
        );
        return id;
      });

      // The signature is intentionally opaque here. Family authoring/native
      // evaluation owns canonicalization. Runtime only interns identical keys.
      final variantKey = '$typeId\u0000${seed.parameterSignature}';
      final variantId = variantByKey.putIfAbsent(variantKey, () {
        final id = variants.length;
        variants.add(
          FamilyGeometryVariant(
            id: id,
            typeId: typeId,
            parameterSignature: seed.parameterSignature,
            geometryKey: seed.geometryKey,
            // A seed cannot know its final interned variant id. Normalize the
            // representation descriptor here so render batching can trust that
            // descriptor.geometryVariantId == this row's id.
            representations: _withVariantId(seed.representations, id),
          ),
        );
        return id;
      });

      instanceIds[index] = seed.instanceId;
      definitionIds[index] = definitionId;
      typeIds[index] = typeId;
      geometryVariantIds[index] = variantId;
      levelIds[index] = seed.levelId;
      hostIds[index] = seed.hostId ?? -1;
      flags[index] = seed.flags;

      final p = index * 3;
      positions[p] = seed.x;
      positions[p + 1] = seed.y;
      positions[p + 2] = seed.z;
      scales[p] = seed.scaleX;
      scales[p + 1] = seed.scaleY;
      scales[p + 2] = seed.scaleZ;
      halfExtents[p] = seed.halfExtentX.abs();
      halfExtents[p + 1] = seed.halfExtentY.abs();
      halfExtents[p + 2] = seed.halfExtentZ.abs();

      final r = index * 4;
      rotations[r] = seed.rotationX;
      rotations[r + 1] = seed.rotationY;
      rotations[r + 2] = seed.rotationZ;
      rotations[r + 3] = seed.rotationW;
    }

    return FamilyInstanceStore._(
      definitions: List.unmodifiable(definitions),
      types: List.unmodifiable(types),
      geometryVariants: List.unmodifiable(variants),
      instanceIds: instanceIds,
      definitionIds: definitionIds,
      typeIds: typeIds,
      geometryVariantIds: geometryVariantIds,
      levelIds: levelIds,
      hostIds: hostIds,
      flags: flags,
      positions: positions,
      rotations: rotations,
      scales: scales,
      halfExtents: halfExtents,
    );
  }

  final List<FamilyRuntimeDefinition> definitions;
  final List<FamilyRuntimeType> types;
  final List<FamilyGeometryVariant> geometryVariants;

  final Int64List instanceIds;
  final Uint32List definitionIds;
  final Uint32List typeIds;
  final Uint32List geometryVariantIds;
  final Int64List levelIds;
  final Int64List hostIds;
  final Uint32List flags;

  /// XYZ in project coordinates. A future native/chunk compiler may convert
  /// these to chunk-local floats without changing the semantic store contract.
  final Float64List positions;
  final Float32List rotations;
  final Float32List scales;
  final Float32List halfExtents;

  int get length => instanceIds.length;
  bool get isEmpty => length == 0;

  FamilyGeometryVariant variantAtInstance(int instanceIndex) =>
      geometryVariants[geometryVariantIds[instanceIndex]];

  ({double x, double y, double z}) positionAt(int instanceIndex) {
    final offset = instanceIndex * 3;
    return (
      x: positions[offset],
      y: positions[offset + 1],
      z: positions[offset + 2],
    );
  }

  ({double x, double y, double z}) halfExtentAt(int instanceIndex) {
    final offset = instanceIndex * 3;
    return (
      x: halfExtents[offset],
      y: halfExtents[offset + 1],
      z: halfExtents[offset + 2],
    );
  }
}

FamilyRepresentationSet _withVariantId(
  FamilyRepresentationSet source,
  int variantId,
) {
  final model = source.model3d;
  return FamilyRepresentationSet(
    plan: source.plan,
    elevation: source.elevation,
    section: source.section,
    model3d: model == null
        ? null
        : Family3dRepresentationDescriptor(
            geometryVariantId: variantId,
            proxyAssetKey: model.proxyAssetKey,
            lowAssetKey: model.lowAssetKey,
            mediumAssetKey: model.mediumAssetKey,
            fullAssetKey: model.fullAssetKey,
          ),
  );
}
