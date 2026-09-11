import '../../domain/elements/bim_element_kind_catalog.dart';

/// Library-private compatibility shape used by the unchanged RenderScene
/// parser parts. Identity resolution is owned by the core kind catalog; this
/// adapter exists only so the read-model migration does not change behavior.
final class BimElementRegistry {
  const BimElementRegistry._();

  static const BimElementRegistry standard = BimElementRegistry._();

  String normalizeKind(String value) => BimElementKindCatalog.normalizeKind(value);

  String displayName(String value) => BimElementKindCatalog.displayName(value);
}
