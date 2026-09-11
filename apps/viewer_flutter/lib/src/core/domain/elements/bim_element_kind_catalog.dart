/// Renderer- and UI-neutral identity and capabilities for one BIM element kind.
///
/// This is the authoritative owner of canonical kind keys, display names,
/// import aliases and cross-cutting semantic capabilities. Feature modules may
/// add authoring/type/inspection behavior, but must reuse these descriptors.
final class BimElementKindDescriptor {
  const BimElementKindDescriptor({
    required this.kindKey,
    required this.displayName,
    this.aliases = const <String>{},
    this.isArchitectural = true,
    this.isLevelHosted = false,
    this.isPlanCore = false,
    this.isOpening = false,
    this.defaultVisibleIn3d = true,
    this.levelLockedByDefault = false,
  });

  final String kindKey;
  final String displayName;
  final Set<String> aliases;
  final bool isArchitectural;
  final bool isLevelHosted;
  final bool isPlanCore;
  final bool isOpening;
  final bool defaultVisibleIn3d;
  final bool levelLockedByDefault;
}

abstract final class BimElementKindCatalog {
  static const level = BimElementKindDescriptor(
    kindKey: 'level',
    displayName: 'Level',
    aliases: <String>{'level'},
    isArchitectural: false,
    defaultVisibleIn3d: false,
  );
  static const wall = BimElementKindDescriptor(
    kindKey: 'wall',
    displayName: 'Wall',
    aliases: <String>{'wall'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const door = BimElementKindDescriptor(
    kindKey: 'door',
    displayName: 'Door',
    aliases: <String>{'door', 'opening'},
    isLevelHosted: true,
    isPlanCore: true,
    isOpening: true,
    levelLockedByDefault: true,
  );
  static const window = BimElementKindDescriptor(
    kindKey: 'window',
    displayName: 'Window',
    aliases: <String>{'window'},
    isLevelHosted: true,
    isPlanCore: true,
    isOpening: true,
    levelLockedByDefault: true,
  );
  static const room = BimElementKindDescriptor(
    kindKey: 'room',
    displayName: 'Room',
    aliases: <String>{'room'},
    isPlanCore: true,
  );
  static const floor = BimElementKindDescriptor(
    kindKey: 'floor',
    displayName: 'Floor',
    aliases: <String>{'floor', 'floorsystem'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const ceiling = BimElementKindDescriptor(
    kindKey: 'ceiling',
    displayName: 'Ceiling',
    aliases: <String>{'ceiling', 'ceilingsystem'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const roof = BimElementKindDescriptor(
    kindKey: 'roof',
    displayName: 'Roof',
    aliases: <String>{'roof'},
    isLevelHosted: true,
    levelLockedByDefault: true,
  );
  static const slab = BimElementKindDescriptor(
    kindKey: 'slab',
    displayName: 'Slab',
    aliases: <String>{'slab'},
    isLevelHosted: true,
    levelLockedByDefault: true,
  );
  static const column = BimElementKindDescriptor(
    kindKey: 'column',
    displayName: 'Column',
    aliases: <String>{'column'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const beam = BimElementKindDescriptor(
    kindKey: 'beam',
    displayName: 'Beam',
    aliases: <String>{'beam'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const stair = BimElementKindDescriptor(
    kindKey: 'stair',
    displayName: 'Stair',
    aliases: <String>{'stair'},
    isLevelHosted: true,
    isPlanCore: true,
    levelLockedByDefault: true,
  );
  static const proxy = BimElementKindDescriptor(
    kindKey: 'proxy',
    displayName: 'Imported element',
    aliases: <String>{
      'proxy',
      'fbx',
      'fbxmesh',
      'fbxmodel',
      'fbximport',
      'fbx_import',
      'mesh',
      'meshmodel',
      'imported',
      'importedmesh',
      'importedmodel',
      'model3d',
      'external',
      'externalmesh',
      'foreignmesh',
    },
    isArchitectural: false,
  );

  static const List<BimElementKindDescriptor> standard =
      <BimElementKindDescriptor>[
    level,
    wall,
    door,
    window,
    room,
    floor,
    ceiling,
    roof,
    slab,
    column,
    beam,
    stair,
    proxy,
  ];

  static final Map<String, BimElementKindDescriptor> _index = _buildIndex();

  static BimElementKindDescriptor? resolve(String value) =>
      _index[_canonical(value)];

  static String normalizeKind(String value) {
    final descriptor = resolve(value);
    if (descriptor != null) return descriptor.kindKey;
    final canonical = _canonical(value);
    return canonical.isEmpty ? 'unknown' : canonical;
  }

  static String displayName(String value) {
    final descriptor = resolve(value);
    if (descriptor != null) return descriptor.displayName;
    final normalized = normalizeKind(value);
    if (normalized == 'unknown') return 'Unknown';
    return normalized
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static bool isLevelLockedByDefault(String value) =>
      resolve(value)?.levelLockedByDefault ?? false;

  static Map<String, BimElementKindDescriptor> _buildIndex() {
    final result = <String, BimElementKindDescriptor>{};
    for (final descriptor in standard) {
      for (final rawKey in <String>{
        descriptor.kindKey,
        ...descriptor.aliases,
      }) {
        final key = _canonical(rawKey);
        final previous = result[key];
        if (previous != null && !identical(previous, descriptor)) {
          throw StateError(
            'Duplicate BIM element identity key "$rawKey" (canonical "$key") '
            'claimed by ${previous.kindKey} and ${descriptor.kindKey}.',
          );
        }
        result[key] = descriptor;
      }
    }
    return Map<String, BimElementKindDescriptor>.unmodifiable(result);
  }

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
}
