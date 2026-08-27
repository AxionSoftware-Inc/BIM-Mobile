/// Stable semantic boundary for a BIM element family.
///
/// Element modules describe identity and cross-cutting capabilities only.
/// They do not own viewport state, FFI handles, or generated mesh data. That
/// keeps a new element/type from becoming a dependency of the renderer.
enum BimElementTypeFamily {
  none,
  wall,
  door,
  window,
  floor,
  ceiling,
  roof,
  slab,
  column,
  beam,
  stair,
}

/// Presentation-neutral definition of a type supplied by an element module.
///
/// The native document remains authoritative for persisted type records. This
/// value is the shared contract used by Dart adapters when a type catalog is
/// exposed to Inspector or authoring tools.
final class BimElementTypeDefinition {
  const BimElementTypeDefinition({
    required this.id,
    required this.name,
    required this.family,
    this.parameters = const <String, Object?>{},
  });

  final String id;
  final String name;
  final BimElementTypeFamily family;
  final Map<String, Object?> parameters;

  String get key => '${family.name}:$id';
}

/// Immutable catalog boundary for element types.
final class BimElementTypeCatalog {
  const BimElementTypeCatalog({
    this.types = const <BimElementTypeDefinition>[],
  });

  final List<BimElementTypeDefinition> types;

  Iterable<BimElementTypeDefinition> forFamily(BimElementTypeFamily family) {
    return types.where((type) => type.family == family);
  }

  BimElementTypeDefinition? find(
    BimElementTypeFamily family,
    String id,
  ) {
    for (final type in types) {
      if (type.family == family && type.id == id) return type;
    }
    return null;
  }
}

/// Cross-cutting behavior needed by view policies and level binding.
class BimElementModule {
  const BimElementModule({
    required this.kindKey,
    required this.displayName,
    required this.typeFamily,
    this.aliases = const <String>{},
    this.isArchitectural = true,
    this.isLevelHosted = false,
    this.isPlanCore = false,
    this.isOpening = false,
    this.defaultVisibleIn3d = true,
    this.levelLockedByDefault = false,
    this.typeDefinitions = const <BimElementTypeDefinition>[],
  });

  final String kindKey;
  final String displayName;
  final BimElementTypeFamily typeFamily;
  final Set<String> aliases;
  final bool isArchitectural;
  final bool isLevelHosted;
  final bool isPlanCore;
  final bool isOpening;
  final bool defaultVisibleIn3d;
  final bool levelLockedByDefault;
  final List<BimElementTypeDefinition> typeDefinitions;
}
