import 'package:flutter/widgets.dart';

import '../../../core/domain/units/project_unit_settings.dart';
import '../../../render_scene_models.dart';
import '../../authoring/application/authoring_command_service.dart';

/// Applies an authoritative engine snapshot produced by an Inspector command.
typedef BimInspectorApplyResult = Future<void> Function(
  RenderSceneLoadResult result,
  String message,
);

/// Public, typed boundary between PropertyEditor and one element Inspector.
///
/// Legacy Inspector `part` files currently read private symbols from
/// property_editor.dart. New/migrated adapters receive everything they need
/// through this object so each Inspector can become an ordinary importable
/// widget with an independently testable dependency surface.
@immutable
final class BimInspectorContext {
  const BimInspectorContext({
    required this.scene,
    required this.object,
    required this.units,
    required this.commands,
    required this.onApplied,
  });

  final RenderScene scene;
  final RenderSceneObject object;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final BimInspectorApplyResult onApplied;

  List<RenderSceneLevel> get levels => scene.levels;
}

/// One independently importable Inspector presentation adapter.
abstract interface class BimElementInspectorAdapter {
  String get key;

  Widget build(BuildContext context, BimInspectorContext inspector);
}

/// Adapter lookup is intentionally separate from BimElementInspectorRegistry.
/// The element registry decides *which key* a kind uses; this registry decides
/// *which presentation adapter* implements that key.
final class BimElementInspectorAdapterRegistry {
  BimElementInspectorAdapterRegistry(
    Iterable<BimElementInspectorAdapter> adapters,
  ) : _byKey = _index(adapters);

  final Map<String, BimElementInspectorAdapter> _byKey;

  BimElementInspectorAdapter? forKey(String key) => _byKey[key.trim()];

  Iterable<String> get keys => _byKey.keys;

  static Map<String, BimElementInspectorAdapter> _index(
    Iterable<BimElementInspectorAdapter> adapters,
  ) {
    final result = <String, BimElementInspectorAdapter>{};
    for (final adapter in adapters) {
      final key = adapter.key.trim();
      if (key.isEmpty) {
        throw StateError('Inspector adapter key cannot be empty.');
      }
      if (result.containsKey(key)) {
        throw StateError('Duplicate Inspector adapter key: $key');
      }
      result[key] = adapter;
    }
    return Map<String, BimElementInspectorAdapter>.unmodifiable(result);
  }
}
