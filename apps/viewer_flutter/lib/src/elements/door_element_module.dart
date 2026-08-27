import 'bim_element_module.dart';

final class DoorElementModule extends BimElementModule {
  const DoorElementModule()
      : super(
          kindKey: 'door',
          displayName: 'Door',
          typeFamily: BimElementTypeFamily.door,
          aliases: const <String>{'door', 'opening'},
          isLevelHosted: true,
          isPlanCore: true,
          isOpening: true,
          levelLockedByDefault: true,
        );
}
