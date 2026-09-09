import '../../../elements/beam_element_module.dart';
import '../../../elements/ceiling_element_module.dart';
import '../../../elements/column_element_module.dart';
import '../../../elements/door_element_module.dart';
import '../../../elements/floor_element_module.dart';
import '../../../elements/level_element_module.dart';
import '../../../elements/proxy_element_module.dart';
import '../../../elements/roof_element_module.dart';
import '../../../elements/room_element_module.dart';
import '../../../elements/slab_element_module.dart';
import '../../../elements/stair_element_module.dart';
import '../../../elements/wall_element_module.dart';
import '../../../elements/window_element_module.dart';
import '../domain/bim_element_module.dart';

/// Registry of element modules used by the Flutter application boundary.
///
/// APPLICATION OWNERSHIP: this is the single canonical capability registry for
/// BIM element identity on the Dart side. Production composition validates it
/// once; feature code receives it rather than creating parallel maps/switches.
final class BimElementRegistry {
  const BimElementRegistry(this.modules);

  static const List<BimElementModule> standardModules = <BimElementModule>[
    LevelElementModule(),
    WallElementModule(),
    DoorElementModule(),
    WindowElementModule(),
    RoomElementModule(),
    FloorElementModule(),
    CeilingElementModule(),
    RoofElementModule(),
    SlabElementModule(),
    ColumnElementModule(),
    BeamElementModule(),
    StairElementModule(),
    ProxyElementModule(),
  ];

  static const BimElementRegistry standard =
      BimElementRegistry(standardModules);

  /// Per-registry immutable lookup index. Expando avoids turning this registry
  /// into a process-wide service locator and does not keep short-lived custom
  /// registries alive solely because they were queried once.
  static final Expando<Map<String, BimElementModule>> _indices =
      Expando<Map<String, BimElementModule>>('bim-element-registry-index');

  final List<BimElementModule> modules;

  /// Validates all canonical kind and alias keys, then returns this registry.
  BimElementRegistry validate() {
    _index;
    return this;
  }

  BimElementModule? forKind(String value) => _index[_canonical(value)];

  String normalizeKind(String value) =>
      forKind(value)?.kindKey ??
      (_canonical(value).isEmpty ? 'unknown' : _canonical(value));

  String displayName(String value) {
    final module = forKind(value);
    if (module != null) return module.displayName;
    final normalized = normalizeKind(value);
    if (normalized == 'unknown') return 'Unknown';
    return normalized
        .split(RegExp(r'[_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Set<String> get architecturalKinds => <String>{
        for (final module in modules)
          if (module.isArchitectural) module.kindKey,
      };

  Set<String> get planCoreKinds => <String>{
        for (final module in modules)
          if (module.isPlanCore) module.kindKey,
      };

  Set<String> get levelLockedKinds => <String>{
        for (final module in modules)
          if (module.levelLockedByDefault) module.kindKey,
      };

  Set<String> get defaultVisible3dKinds => <String>{
        for (final module in modules)
          if (module.defaultVisibleIn3d) module.kindKey,
      };

  List<String> get coreKindOrder {
    const preferred = <String>[
      'wall',
      'door',
      'window',
      'room',
      'slab',
      'floor',
      'ceiling',
      'roof',
      'column',
      'beam',
      'stair',
    ];
    final ordered = <String>[
      for (final kind in preferred)
        if (forKind(kind)?.isArchitectural == true) kind,
    ];
    for (final module in modules) {
      if (module.isArchitectural && !ordered.contains(module.kindKey)) {
        ordered.add(module.kindKey);
      }
    }
    return ordered;
  }

  BimElementTypeCatalog get typeCatalog => BimElementTypeCatalog(
        types: <BimElementTypeDefinition>[
          for (final module in modules) ...module.typeDefinitions,
        ],
      );

  bool isKind(String value, String expected) =>
      normalizeKind(value) == normalizeKind(expected);

  bool isOpening(String value) => forKind(value)?.isOpening ?? false;

  bool isLevelHosted(String value) => forKind(value)?.isLevelHosted ?? false;

  bool isLevelLockedByDefault(String value) =>
      forKind(value)?.levelLockedByDefault ?? false;

  Map<String, BimElementModule> get _index {
    final cached = _indices[this];
    if (cached != null) return cached;
    final built = _buildIndex(modules);
    _indices[this] = built;
    return built;
  }

  static Map<String, BimElementModule> _buildIndex(
    List<BimElementModule> modules,
  ) {
    final result = <String, BimElementModule>{};
    for (final module in modules) {
      final keys = <String>{module.kindKey, ...module.aliases};
      for (final rawKey in keys) {
        final key = _canonical(rawKey);
        if (key.isEmpty) {
          throw StateError(
            'BIM element module ${module.runtimeType} registered an empty key.',
          );
        }
        final previous = result[key];
        if (previous != null && !identical(previous, module)) {
          throw StateError(
            'Duplicate BIM element registry key "$rawKey" (canonical "$key") '
            'claimed by ${previous.runtimeType} and ${module.runtimeType}.',
          );
        }
        result[key] = module;
      }
    }
    return Map<String, BimElementModule>.unmodifiable(result);
  }

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
}
