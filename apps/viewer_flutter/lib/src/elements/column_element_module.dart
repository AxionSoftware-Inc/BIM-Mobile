import 'bim_element_module.dart';

final class ColumnElementModule extends BimElementModule {
  const ColumnElementModule()
      : super(
          kindKey: 'column',
          displayName: 'Column',
          typeFamily: BimElementTypeFamily.column,
          aliases: const <String>{'column'},
          isLevelHosted: true,
          isPlanCore: true,
          levelLockedByDefault: true,
        );
}
