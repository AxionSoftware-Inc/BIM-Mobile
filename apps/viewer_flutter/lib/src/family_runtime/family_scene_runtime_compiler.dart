import 'dart:convert';
import 'dart:math' as math;

import '../render_scene_models.dart';
import 'family_2d_asset_library.dart';
import 'family_instance_store.dart';
import 'family_representation.dart';

final class FamilySceneRuntimeCompilation {
  const FamilySceneRuntimeCompilation({
    required this.store,
    required this.twoDimensionalAssets,
  });

  final FamilyInstanceStore store;
  final Family2dAssetLibrary twoDimensionalAssets;
}

/// Compiles the authoritative project snapshot into the compact family runtime.
///
/// This adapter is deliberately tolerant of snake_case/camelCase metadata so
/// old projects and native scene DTO migrations do not fork the runtime path.
/// Family Authoring is not consulted here: placed project elements already
/// carry the stable family/type reference and resolved parameter payload.
abstract final class FamilySceneRuntimeCompiler {
  static FamilyInstanceStore compile(RenderScene scene) =>
      FamilyInstanceStore.fromSeeds(seeds(scene));

  /// Compiles both packed instance rows and the tiny shared 2D asset table.
  /// SVG parsing happens once here, never during camera pan/zoom frames.
  static FamilySceneRuntimeCompilation compileRuntime(RenderScene scene) {
    final assetBuilder = Family2dAssetLibraryBuilder();
    for (final object in scene.objects) {
      final metadata = object.metadata;
      final familyAssetId = _string(metadata, const <String>[
        'family_asset_id',
        'familyAssetId',
        'family_id',
        'familyId',
      ]);
      if (familyAssetId == null || familyAssetId.isEmpty) continue;
      final planSvg = _string(metadata, const <String>[
            'family_plan_svg',
            'familyPlanSvg',
            'plan_svg',
            'planSvg',
          ]) ??
          '';
      if (planSvg.isEmpty) continue;
      assetBuilder.addSvg(
        assetKey: 'svg:${_fnv1a64(planSvg)}',
        svg: planSvg,
      );
    }
    return FamilySceneRuntimeCompilation(
      store: compile(scene),
      twoDimensionalAssets: assetBuilder.build(),
    );
  }

  static Iterable<FamilyRuntimeInstanceSeed> seeds(RenderScene scene) sync* {
    for (final object in scene.objects) {
      final instanceId = object.elementId;
      if (instanceId == null) continue;
      final metadata = object.metadata;
      final familyAssetId = _string(metadata, const <String>[
        'family_asset_id',
        'familyAssetId',
        'family_id',
        'familyId',
      ]);
      if (familyAssetId == null || familyAssetId.isEmpty) continue;

      final familyTypeId = _string(metadata, const <String>[
            'family_type_id',
            'familyTypeId',
            'type_id',
            'typeId',
          ]) ??
          'default';
      final category = _string(metadata, const <String>[
            'family_category',
            'familyCategory',
          ]) ??
          object.kindKey;
      final parameterPayload = _string(metadata, const <String>[
            'family_parameter_values_json',
            'familyParameterValuesJson',
            'family_parameter_values',
            'familyParameterValues',
          ]) ??
          '';
      final parameterSignature = _canonicalParameterSignature(parameterPayload);
      final geometryKey =
          'family3d:$familyAssetId:$familyTypeId:${_fnv1a64(parameterSignature)}';

      final planSvg = _string(metadata, const <String>[
            'family_plan_svg',
            'familyPlanSvg',
            'plan_svg',
            'planSvg',
          ]) ??
          '';
      final plan = planSvg.isEmpty
          ? Family2dRepresentationDescriptor(
              encoding: Family2dEncoding.generated,
              assetKey: 'generated:plan:$familyAssetId:$familyTypeId',
            )
          : Family2dRepresentationDescriptor(
              encoding: Family2dEncoding.svg,
              // The payload itself stays in the family/project asset cache.
              // Runtime rows keep only an internable stable key.
              assetKey: 'svg:${_fnv1a64(planSvg)}',
            );

      final bounds = object.bounds;
      final centerX = (bounds.min.x + bounds.max.x) * 0.5;
      final centerY = (bounds.min.y + bounds.max.y) * 0.5;
      final centerZ = (bounds.min.z + bounds.max.z) * 0.5;
      final halfX = ((bounds.max.x - bounds.min.x) * 0.5).abs();
      final halfY = ((bounds.max.y - bounds.min.y) * 0.5).abs();
      final halfZ = ((bounds.max.z - bounds.min.z) * 0.5).abs();
      final decodedParameters = _decodeParameterMap(parameterPayload);
      final hostId = _intValue(decodedParameters, const <String>[
            '_hostWallId',
            'hostWallId',
            'host_wall_id',
          ]) ??
          _intValue(metadata, const <String>[
            'host_wall_id',
            'hostWallId',
            'host_id',
            'hostId',
          ]);
      final rotationZ = _doubleValue(metadata, const <String>[
            'rotation_radians',
            'rotationRadians',
            'rotation_z_radians',
            'rotationZRadians',
          ]) ??
          0.0;
      final halfAngle = rotationZ * 0.5;

      yield FamilyRuntimeInstanceSeed(
        instanceId: instanceId,
        familyAssetId: familyAssetId,
        familyTypeId: familyTypeId,
        category: category,
        parameterSignature: parameterSignature,
        geometryKey: geometryKey,
        representations: FamilyRepresentationSet(
          plan: plan,
          elevation: Family2dRepresentationDescriptor(
            encoding: Family2dEncoding.generated,
            assetKey: 'generated:elevation:$familyAssetId:$familyTypeId',
          ),
          section: Family2dRepresentationDescriptor(
            encoding: Family2dEncoding.generated,
            assetKey: 'generated:section:$familyAssetId:$familyTypeId',
          ),
          model3d: Family3dRepresentationDescriptor(
            // FamilyInstanceStore replaces this placeholder with the interned
            // runtime variant id when the variant is first created.
            geometryVariantId: -1,
            proxyAssetKey: '$geometryKey:proxy',
            lowAssetKey: '$geometryKey:low',
            mediumAssetKey: '$geometryKey:medium',
            fullAssetKey: '$geometryKey:full',
          ),
        ),
        levelId: object.levelId ?? 0,
        x: centerX,
        y: centerY,
        z: centerZ,
        rotationZ: math.sin(halfAngle),
        rotationW: math.cos(halfAngle),
        halfExtentX: halfX > 0 ? halfX : 0.05,
        halfExtentY: halfY > 0 ? halfY : 0.05,
        halfExtentZ: halfZ > 0 ? halfZ : 0.05,
        hostId: hostId,
      );
    }
  }

  static String _canonicalParameterSignature(String payload) {
    if (payload.trim().isEmpty) return '{}';
    try {
      return jsonEncode(_canonicalize(jsonDecode(payload)));
    } catch (_) {
      return payload.trim();
    }
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _canonicalize(item)];
    }
    return value;
  }

  static Map<String, Object?> _decodeParameterMap(String payload) {
    if (payload.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map
          ? Map<String, Object?>.from(decoded.cast<String, Object?>())
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  static String? _string(Map metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _intValue(Map metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static double? _doubleValue(Map metadata, List<String> keys) {
    for (final key in keys) {
      final value = metadata[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  /// 64-bit FNV-1a rendered as hex. This is a cache key, not a security hash.
  static String _fnv1a64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
