import 'bim_element_module.dart';

final class WallElementModule extends BimElementModule {
  const WallElementModule()
      : super(
          kindKey: 'wall',
          displayName: 'Wall',
          typeFamily: BimElementTypeFamily.wall,
          aliases: const <String>{'wall'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
