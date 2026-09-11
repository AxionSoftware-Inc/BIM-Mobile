import '../../../core/domain/elements/bim_element_kind_catalog.dart';

export '../../../core/domain/elements/bim_element_kind_catalog.dart';

/// Stable semantic boundary for a BIM element family.
///
/// Element modules describe type/inspection behavior. Standard cross-cutting
/// capabilities come from [BimElementKindDescriptor], keeping one authority
/// for renderer, project and element feature policies.
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

class BimElementModule {
  BimElementModule({
    required String kindKey,
    required String displayName,
    required this.typeFamily,
    this.inspectorAdapterKey,
    Set<String> aliases = const <String>{},
    bool isArchitectural = true,
    bool isLevelHosted = false,
    bool isPlanCore = false,
    bool isOpening = false,
    bool defaultVisibleIn3d = true,
    bool levelLockedByDefault = false,
    this.typeDefinitions = const <BimElementTypeDefinition>[],
  })  : identity = BimElementKindDescriptor(
          kindKey: kindKey,
          displayName: displayName,
          aliases: aliases,
          isArchitectural: isArchitectural,
          isLevelHosted: isLevelHosted,
          isPlanCore: isPlanCore,
          isOpening: isOpening,
          defaultVisibleIn3d: defaultVisibleIn3d,
          levelLockedByDefault: levelLockedByDefault,
        ),
        _isArchitecturalOverride = null,
        _isLevelHostedOverride = null,
        _isPlanCoreOverride = null,
        _isOpeningOverride = null,
        _defaultVisibleIn3dOverride = null,
        _levelLockedByDefaultOverride = null;

  const BimElementModule.withIdentity({
    required this.identity,
    required this.typeFamily,
    this.inspectorAdapterKey,
    bool? isArchitectural,
    bool? isLevelHosted,
    bool? isPlanCore,
    bool? isOpening,
    bool? defaultVisibleIn3d,
    bool? levelLockedByDefault,
    this.typeDefinitions = const <BimElementTypeDefinition>[],
  })  : _isArchitecturalOverride = isArchitectural,
        _isLevelHostedOverride = isLevelHosted,
        _isPlanCoreOverride = isPlanCore,
        _isOpeningOverride = isOpening,
        _defaultVisibleIn3dOverride = defaultVisibleIn3d,
        _levelLockedByDefaultOverride = levelLockedByDefault;

  final BimElementKindDescriptor identity;
  final BimElementTypeFamily typeFamily;
  final String? inspectorAdapterKey;
  final List<BimElementTypeDefinition> typeDefinitions;
  final bool? _isArchitecturalOverride;
  final bool? _isLevelHostedOverride;
  final bool? _isPlanCoreOverride;
  final bool? _isOpeningOverride;
  final bool? _defaultVisibleIn3dOverride;
  final bool? _levelLockedByDefaultOverride;

  String get kindKey => identity.kindKey;
  String get displayName => identity.displayName;
  Set<String> get aliases => identity.aliases;
  bool get isArchitectural =>
      _isArchitecturalOverride ?? identity.isArchitectural;
  bool get isLevelHosted => _isLevelHostedOverride ?? identity.isLevelHosted;
  bool get isPlanCore => _isPlanCoreOverride ?? identity.isPlanCore;
  bool get isOpening => _isOpeningOverride ?? identity.isOpening;
  bool get defaultVisibleIn3d =>
      _defaultVisibleIn3dOverride ?? identity.defaultVisibleIn3d;
  bool get levelLockedByDefault =>
      _levelLockedByDefaultOverride ?? identity.levelLockedByDefault;

  String get inspectorKey => inspectorAdapterKey ?? kindKey;
}
