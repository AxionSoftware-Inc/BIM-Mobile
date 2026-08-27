import 'bim_element_module.dart';

final class RoofElementModule extends BimElementModule {
  const RoofElementModule()
      : super(
          kindKey: 'roof',
          displayName: 'Roof',
          typeFamily: BimElementTypeFamily.roof,
          aliases: const <String>{'roof'},
          isLevelHosted: true,
          levelLockedByDefault: true,
        );
}
