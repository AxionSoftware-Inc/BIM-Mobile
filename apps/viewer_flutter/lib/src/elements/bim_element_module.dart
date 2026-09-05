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

/// Canonical Inspector adapter routes shared by element modules and the
/// presentation registry. Keeping these keys in the semantic boundary avoids
/// a second, stringly-typed object-family map in the UI.
abstract final class BimElementInspectorKeys {
  static const wall = 'wall';
  static const opening = 'opening';
  static const surface = 'surface';
  static const roof = 'roof';
  static const stair = 'stair';
  static const ceiling = 'ceiling';
  static const linear = 'linear';
  static const family = 'family';
  static const generic = 'generic';
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
    this.inspectorAdapterKey,
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

  /// Presentation boundary used to connect this element to its Inspector.
  ///
  /// Element modules own this identity. The Inspector only resolves the key;
  /// it must not infer object families with a second switch statement.
  final String? inspectorAdapterKey;
  final Set<String> aliases;
  final bool isArchitectural;
  final bool isLevelHosted;
  final bool isPlanCore;
  final bool isOpening;
  final bool defaultVisibleIn3d;
  final bool levelLockedByDefault;
  final List<BimElementTypeDefinition> typeDefinitions;

  String get inspectorKey => inspectorAdapterKey ?? kindKey;
}
