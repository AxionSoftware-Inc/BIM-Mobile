import '../bim_element_module.dart';

final class ColumnElementModule extends BimElementModule {
  const ColumnElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.column,
          typeFamily: BimElementTypeFamily.column,
          inspectorAdapterKey: BimElementInspectorKeys.linear,
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
