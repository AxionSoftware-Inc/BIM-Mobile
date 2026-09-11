import '../bim_element_module.dart';

final class SlabElementModule extends BimElementModule {
  const SlabElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.slab,
          typeFamily: BimElementTypeFamily.slab,
          inspectorAdapterKey: BimElementInspectorKeys.surface,
        );
}
