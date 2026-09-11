import '../bim_element_module.dart';

final class DoorElementModule extends BimElementModule {
  const DoorElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.door,
          typeFamily: BimElementTypeFamily.door,
          inspectorAdapterKey: BimElementInspectorKeys.opening,
        );
}
