import '../bim_element_module.dart';

final class FloorElementModule extends BimElementModule {
  const FloorElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.floor,
          typeFamily: BimElementTypeFamily.floor,
          inspectorAdapterKey: BimElementInspectorKeys.surface,
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
