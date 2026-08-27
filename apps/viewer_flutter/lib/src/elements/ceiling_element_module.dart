import 'bim_element_module.dart';

final class CeilingElementModule extends BimElementModule {
  const CeilingElementModule()
      : super(
          kindKey: 'ceiling',
          displayName: 'Ceiling',
          typeFamily: BimElementTypeFamily.ceiling,
          aliases: const <String>{'ceiling', 'ceilingsystem'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
