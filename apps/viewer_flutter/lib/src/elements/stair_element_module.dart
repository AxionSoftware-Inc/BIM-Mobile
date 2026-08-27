import 'bim_element_module.dart';

final class StairElementModule extends BimElementModule {
  const StairElementModule()
      : super(
          kindKey: 'stair',
          displayName: 'Stair',
          typeFamily: BimElementTypeFamily.stair,
          aliases: const <String>{'stair'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
