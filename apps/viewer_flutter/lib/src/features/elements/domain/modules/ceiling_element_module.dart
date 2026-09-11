import '../bim_element_module.dart';

final class CeilingElementModule extends BimElementModule {
  const CeilingElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.ceiling,
          typeFamily: BimElementTypeFamily.ceiling,
          inspectorAdapterKey: BimElementInspectorKeys.ceiling,
        );
}
