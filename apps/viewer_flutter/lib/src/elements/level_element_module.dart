import 'bim_element_module.dart';

final class LevelElementModule extends BimElementModule {
  const LevelElementModule()
      : super(
          kindKey: 'level',
          displayName: 'Level',
          typeFamily: BimElementTypeFamily.none,
          isArchitectural: false,
          defaultVisibleIn3d: false,
          aliases: const <String>{'level'},
        );
}
