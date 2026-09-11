import '../bim_element_module.dart';

final class LevelElementModule extends BimElementModule {
  const LevelElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.level,
          typeFamily: BimElementTypeFamily.none,
        );
}
