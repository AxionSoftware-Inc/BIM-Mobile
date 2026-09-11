import '../bim_element_module.dart';

final class RoofElementModule extends BimElementModule {
  const RoofElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.roof,
          typeFamily: BimElementTypeFamily.roof,
        );
}
