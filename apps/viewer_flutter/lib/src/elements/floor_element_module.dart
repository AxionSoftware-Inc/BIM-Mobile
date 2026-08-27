import 'bim_element_module.dart';

final class FloorElementModule extends BimElementModule {
  const FloorElementModule()
      : super(
          kindKey: 'floor',
          displayName: 'Floor',
          typeFamily: BimElementTypeFamily.floor,
          aliases: const <String>{'floor', 'floorsystem'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
