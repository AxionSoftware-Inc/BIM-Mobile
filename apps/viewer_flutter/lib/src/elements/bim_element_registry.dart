import 'beam_element_module.dart';
import 'bim_element_module.dart';
import 'ceiling_element_module.dart';
import 'column_element_module.dart';
import 'door_element_module.dart';
import 'floor_element_module.dart';
import 'level_element_module.dart';
import 'proxy_element_module.dart';
import 'roof_element_module.dart';
import 'room_element_module.dart';
import 'slab_element_module.dart';
import 'stair_element_module.dart';
import 'wall_element_module.dart';
import 'window_element_module.dart';

/// Registry of element modules used by the Flutter application boundary.
///
/// The default registry is deliberately immutable. Tests and future product
/// editions can construct a registry with an additional module without
/// changing viewport code or adding another global switch statement.
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

  final List<BimElementModule> modules;

  BimElementModule? forKind(String value) {
    final canonical = _canonical(value);
    for (final module in modules) {
      if (_canonical(module.kindKey) == canonical ||
          module.aliases.any((alias) => _canonical(alias) == canonical)) {
        return module;
      }
    }
    return null;
  }

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

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
}
