/// Renderer- and UI-neutral identity for one BIM element kind.
///
/// This is the authoritative owner of canonical kind keys, display names and
/// import aliases. Capability modules may add authoring/inspection behavior,
/// but must reuse these descriptors instead of maintaining another alias map.
final class BimElementKindDescriptor {
  const BimElementKindDescriptor({
    required this.kindKey,
    required this.displayName,
    this.aliases = const <String>{},
  });

  final String kindKey;
  final String displayName;
  final Set<String> aliases;
}

abstract final class BimElementKindCatalog {
  static const level = BimElementKindDescriptor(
    kindKey: 'level',
    displayName: 'Level',
    aliases: <String>{'level'},
  );
  static const wall = BimElementKindDescriptor(
    kindKey: 'wall',
    displayName: 'Wall',
    aliases: <String>{'wall'},
  );
  static const door = BimElementKindDescriptor(
    kindKey: 'door',
    displayName: 'Door',
    aliases: <String>{'door', 'opening'},
  );
  static const window = BimElementKindDescriptor(
    kindKey: 'window',
    displayName: 'Window',
    aliases: <String>{'window'},
  );
  static const room = BimElementKindDescriptor(
    kindKey: 'room',
    displayName: 'Room',
    aliases: <String>{'room'},
  );
  static const floor = BimElementKindDescriptor(
    kindKey: 'floor',
    displayName: 'Floor',
    aliases: <String>{'floor', 'floorsystem'},
  );
  static const ceiling = BimElementKindDescriptor(
    kindKey: 'ceiling',
    displayName: 'Ceiling',
    aliases: <String>{'ceiling', 'ceilingsystem'},
  );
  static const roof = BimElementKindDescriptor(
    kindKey: 'roof',
    displayName: 'Roof',
    aliases: <String>{'roof'},
  );
  static const slab = BimElementKindDescriptor(
    kindKey: 'slab',
    displayName: 'Slab',
    aliases: <String>{'slab'},
  );
  static const column = BimElementKindDescriptor(
    kindKey: 'column',
    displayName: 'Column',
    aliases: <String>{'column'},
  );
  static const beam = BimElementKindDescriptor(
    kindKey: 'beam',
    displayName: 'Beam',
    aliases: <String>{'beam'},
  );
  static const stair = BimElementKindDescriptor(
    kindKey: 'stair',
    displayName: 'Stair',
    aliases: <String>{'stair'},
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
