import 'bim_element_module.dart';

final class RoomElementModule extends BimElementModule {
  const RoomElementModule()
      : super(
          kindKey: 'room',
          displayName: 'Room',
          typeFamily: BimElementTypeFamily.none,
          aliases: const <String>{'room'},
          isPlanCore: true,
        );
}
