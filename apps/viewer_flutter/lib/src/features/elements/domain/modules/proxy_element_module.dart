import '../bim_element_module.dart';

final class ProxyElementModule extends BimElementModule {
  const ProxyElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.proxy,
          typeFamily: BimElementTypeFamily.none,
          inspectorAdapterKey: BimElementInspectorKeys.family,
          isArchitectural: false,
        );
}
