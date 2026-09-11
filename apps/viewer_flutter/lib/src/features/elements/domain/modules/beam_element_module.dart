import '../bim_element_module.dart';

final class BeamElementModule extends BimElementModule {
  const BeamElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.beam,
          typeFamily: BimElementTypeFamily.beam,
          inspectorAdapterKey: BimElementInspectorKeys.linear,
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
