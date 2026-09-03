import 'bim_element_registry.dart';
import 'bim_element_module.dart';

/// Stable route from an element module to its Inspector adapter.
///
/// Element modules own the route key. This registry owns only resolution; it
/// contains no widget, metadata key, or authoring command knowledge.
final class BimElementInspectorRegistry {
  const BimElementInspectorRegistry(this.elements);

  static const BimElementInspectorRegistry standard =
      BimElementInspectorRegistry(BimElementRegistry.standard);

  final BimElementRegistry elements;

  String keyForKind(String kind) =>
      elements.forKind(kind)?.inspectorKey ?? BimElementInspectorKeys.generic;
}
