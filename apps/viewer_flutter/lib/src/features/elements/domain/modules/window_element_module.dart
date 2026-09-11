import '../bim_element_module.dart';

final class WindowElementModule extends BimElementModule {
  const WindowElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.window,
          typeFamily: BimElementTypeFamily.window,
          inspectorAdapterKey: BimElementInspectorKeys.opening,
        );
}
