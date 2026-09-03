import 'bim_element_module.dart';

final class SlabElementModule extends BimElementModule {
  const SlabElementModule()
      : super(
          kindKey: 'slab',
          displayName: 'Slab',
          typeFamily: BimElementTypeFamily.slab,
          inspectorAdapterKey: BimElementInspectorKeys.surface,
          aliases: const <String>{'slab'},
          isLevelHosted: true,
          levelLockedByDefault: true,
        );
}
