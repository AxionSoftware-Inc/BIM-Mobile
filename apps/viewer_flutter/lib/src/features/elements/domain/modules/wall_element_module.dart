import '../bim_element_module.dart';

final class WallElementModule extends BimElementModule {
  const WallElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.wall,
          typeFamily: BimElementTypeFamily.wall,
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
