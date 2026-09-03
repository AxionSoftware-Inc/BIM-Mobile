import 'bim_element_module.dart';

final class BeamElementModule extends BimElementModule {
  const BeamElementModule()
      : super(
          kindKey: 'beam',
          displayName: 'Beam',
          typeFamily: BimElementTypeFamily.beam,
          inspectorAdapterKey: BimElementInspectorKeys.linear,
          aliases: const <String>{'beam'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
