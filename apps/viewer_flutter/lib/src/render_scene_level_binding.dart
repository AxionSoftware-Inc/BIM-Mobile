import 'elements/bim_element_registry.dart';

/// The single source of truth for fallback RenderScene level relationships.
///
/// The native engine is authoritative when it is available. This policy keeps
/// the Flutter fallback compatible with it and upgrades older scene snapshots
/// that predate explicit base/top level metadata.
class RenderSceneLevelBinding {
  const RenderSceneLevelBinding._();

  /// Makes level ownership explicit without overwriting a deliberate unlock.
  static void normalizeObjects(
    List<Map<String, Object?>> objects,
    List<Map<String, Object?>> levels,
  ) {
    final elevations = <int, double>{
      for (final level in levels)
        if (levelId(level) != null) levelId(level)!: levelElevation(level),
    };
    final wallsById = <int, Map<String, Object?>>{};

    for (final object in objects) {
      if (kindKey(object) != 'wall') continue;
      final id = elementId(object);
      final baseId = levelId(object);
      if (id == null || baseId == null || !elevations.containsKey(baseId)) {
        continue;
      }
      final metadata = metadataOf(object);
      final metadataBaseId = toInt(metadata['base_level_id']);
      final normalizedBaseId =
          metadataBaseId != null && elevations.containsKey(metadataBaseId)
              ? metadataBaseId
              : baseId;
      final explicitTopId = toInt(metadata['top_level_id']);
      final normalizedTopId = explicitTopId != null &&
              explicitTopId > 0 &&
              elevations.containsKey(explicitTopId) &&
              elevations[explicitTopId]! > elevations[normalizedBaseId]! + 1e-6
          ? explicitTopId
          : nearestHigherLevelId(
              levels: levels,
              baseLevelId: normalizedBaseId,
            );
      metadata['base_level_id'] = normalizedBaseId.toString();
      if (normalizedTopId != null) {
        metadata['top_level_id'] = normalizedTopId.toString();
        metadata['height_mode'] = 'TopLevel';
      } else {
        metadata.remove('top_level_id');
        metadata['height_mode'] = 'Unconnected';
      }
      metadata.putIfAbsent('level_locked', () => true);
      object['level_id'] = normalizedBaseId;
      object['metadata'] = metadata;
      wallsById[id] = object;
    }

    for (final object in objects) {
      final kind = kindKey(object);
      if (!BimElementRegistry.standard.isLevelLockedByDefault(kind)) {
        continue;
      }
      final metadata = metadataOf(object);
      if (kind == 'door' || kind == 'window') {
        final host = wallsById[toInt(metadata['host_wall_id'])];
        if (host != null) {
          final hostMetadata = metadataOf(host);
          final hostBaseId =
              toInt(hostMetadata['base_level_id']) ?? levelId(host);
          if (hostBaseId != null) object['level_id'] = hostBaseId;
        }
      }
      metadata.putIfAbsent('level_locked', () => true);
      object['metadata'] = metadata;
    }
  }

  static int? nearestHigherLevelId({
    required List<Map<String, Object?>> levels,
    required int baseLevelId,
  }) {
    Map<String, Object?>? base;
    for (final level in levels) {
      if (levelId(level) == baseLevelId) {
        base = level;
        break;
      }
    }
    if (base == null) return null;
    final baseElevation = levelElevation(base);
    final candidates = levels
        .where((level) => levelElevation(level) > baseElevation + 1e-6)
        .toList()
      ..sort((a, b) => levelElevation(a).compareTo(levelElevation(b)));
    return candidates.isEmpty ? null : levelId(candidates.first);
  }

  static bool isLevelLocked(Map<String, Object?> object) {
    final value = metadataOf(object)['level_locked'];
    return value is bool
        ? value
        : BimElementRegistry.standard.isLevelLockedByDefault(kindKey(object));
  }

  static String kindKey(Map<String, Object?> object) =>
      BimElementRegistry.standard
          .normalizeKind(object['kind']?.toString() ?? '');

  static int? elementId(Map<String, Object?> object) =>
      toInt(object['element_id']) ?? toInt(object['elementId']);

  static int? levelId(Map<String, Object?> object) =>
      toInt(object['level_id']) ?? toInt(object['levelId']);

  static double levelElevation(Map<String, Object?> level) {
    final elevation = toDouble(level['elevation_meters']);
    return elevation != null && elevation.isFinite ? elevation : 0.0;
  }

  static bool canUseElevation({
    required List<Map<String, Object?>> levels,
    required int targetLevelId,
    required double elevationMeters,
  }) {
    if (!elevationMeters.isFinite) return false;
    for (final level in levels) {
      final otherId = levelId(level);
      if (otherId != null &&
          otherId != targetLevelId &&
          (levelElevation(level) - elevationMeters).abs() <= 1e-6) {
        return false;
      }
    }
    return true;
  }

  static Map<String, Object?> metadataOf(Map<String, Object?> object) {
    final raw = object['metadata'];
    return raw is Map
        ? Map<String, Object?>.from(raw.cast<String, Object?>())
        : <String, Object?>{};
  }

  static int? toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
