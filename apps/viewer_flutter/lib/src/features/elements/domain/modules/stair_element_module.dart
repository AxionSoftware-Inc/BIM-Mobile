import '../bim_element_module.dart';

final class StairElementModule extends BimElementModule {
  const StairElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.stair,
          typeFamily: BimElementTypeFamily.stair,
        );
}
