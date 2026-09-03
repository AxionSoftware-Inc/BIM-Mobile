import 'bim_element_module.dart';

final class WindowElementModule extends BimElementModule {
  const WindowElementModule()
      : super(
          kindKey: 'window',
          displayName: 'Window',
          typeFamily: BimElementTypeFamily.window,
          inspectorAdapterKey: BimElementInspectorKeys.opening,
          aliases: const <String>{'window'},
          isLevelHosted: true,
          isPlanCore: true,
          isOpening: true,
          levelLockedByDefault: true,
        );
}
